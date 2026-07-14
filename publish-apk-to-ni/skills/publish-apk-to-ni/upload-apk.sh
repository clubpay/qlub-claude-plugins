#!/usr/bin/env bash
#
# upload-apk.sh — upload one or more APKs to the Network International SFTP
# server's /343/Inbound/APK folder, via the Teleport port-forward tunnel.
#
# Credentials are NOT stored on disk. The SFTP password comes from the
# NI_SFTP_PASSWORD environment variable, or an interactive prompt if run in a
# terminal. config.env holds only non-secret connection settings.
#
# Usage:  NI_SFTP_PASSWORD='...' ./upload-apk.sh <local-apk> [more-apks...]
#     or: ./upload-apk.sh <local-apk>        # prompts for the password
#
# Note: uses an *interactive* sftp session driven by expect. We can't use
# `sftp -b batchfile` because batch mode forces BatchMode=yes, which disables
# password auth (login silently fails with "Permission denied").
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- load NON-SECRET config ----------------------------------------------
CONFIG_FILE="$SCRIPT_DIR/config.env"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# defaults (overridable via config.env or environment)
: "${TSH_NODE:=data-analytics-v2}"
: "${TSH_USER:=bi_analytics}"
: "${SFTP_TARGET_HOST:=10.66.107.155}"
: "${SFTP_TARGET_PORT:=22}"
: "${LOCAL_PORT:=6666}"
: "${REMOTE_DIR:=/343/Inbound/APK}"

# username: NI_SFTP_USER overrides config's SFTP_USER (default qlubuser)
SFTP_USER="${NI_SFTP_USER:-${SFTP_USER:-qlubuser}}"

# password: env var, else interactive prompt. NEVER read from / written to disk.
SFTP_PASSWORD="${NI_SFTP_PASSWORD:-}"
if [ -z "$SFTP_PASSWORD" ] && [ -t 0 ]; then
  read -r -s -p "NI SFTP password for ${SFTP_USER}@${SFTP_TARGET_HOST}: " SFTP_PASSWORD
  echo
fi
if [ -z "$SFTP_PASSWORD" ]; then
  echo "ERROR: no SFTP password. Set NI_SFTP_PASSWORD, or run in a terminal to be prompted." >&2
  exit 5
fi

# ---- args -----------------------------------------------------------------
if [ "$#" -lt 1 ]; then
  echo "Usage: NI_SFTP_PASSWORD='...' $0 <local-apk> [more-apks...]" >&2
  exit 1
fi
for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: file not found: $f" >&2
    exit 1
  fi
  case "$f" in
    *.apk) ;;
    *) echo "WARN: '$f' does not end in .apk — uploading anyway." >&2 ;;
  esac
done

# ---- ensure Teleport session ---------------------------------------------
if ! tsh status >/dev/null 2>&1; then
  echo "ERROR: not logged into Teleport. Run:  tsh login" >&2
  exit 2
fi

# ---- tunnel + temp files: unified cleanup --------------------------------
TUNNEL_PID=""
LOGFILE="$(mktemp -t ni-sftp-log)"
cleanup() {
  [ -n "${LOGFILE:-}" ] && rm -f "$LOGFILE"
  if [ -n "$TUNNEL_PID" ]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    echo "Closed tunnel (pid $TUNNEL_PID)."
  fi
}
trap cleanup EXIT

# ---- ensure tunnel on LOCAL_PORT -----------------------------------------
if nc -z localhost "$LOCAL_PORT" >/dev/null 2>&1; then
  echo "Reusing existing tunnel on localhost:$LOCAL_PORT."
else
  echo "Starting Teleport tunnel: localhost:$LOCAL_PORT -> $SFTP_TARGET_HOST:$SFTP_TARGET_PORT ..."
  tsh ssh -N -L "${LOCAL_PORT}:${SFTP_TARGET_HOST}:${SFTP_TARGET_PORT}" "${TSH_USER}@${TSH_NODE}" &
  TUNNEL_PID=$!
  for _ in $(seq 1 40); do
    if nc -z localhost "$LOCAL_PORT" >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  if ! nc -z localhost "$LOCAL_PORT" >/dev/null 2>&1; then
    echo "ERROR: tunnel did not come up on port $LOCAL_PORT" >&2
    exit 3
  fi
  echo "Tunnel up (pid $TUNNEL_PID)."
fi

# ---- upload via interactive expect ---------------------------------------
FILES_NL=""
for f in "$@"; do FILES_NL+="$f"$'\n'; done
FILES_NL="${FILES_NL%$'\n'}"

echo "Uploading $# file(s) to ${SFTP_USER}@${SFTP_TARGET_HOST}:${REMOTE_DIR} ..."
export SFTP_PASSWORD LOCAL_PORT SFTP_USER REMOTE_DIR LOGFILE FILES_NL

do_upload() {
  : > "$LOGFILE"
  /usr/bin/expect <<'EXP'
set timeout 600
set port  $env(LOCAL_PORT)
set user  $env(SFTP_USER)
set pass  $env(SFTP_PASSWORD)
set dir   $env(REMOTE_DIR)
set files [split $env(FILES_NL) "\n"]
log_file -a $env(LOGFILE)
spawn sftp -P $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $user@localhost
expect {
  -nocase -re {password:} { send -- "$pass\r" }
  timeout { puts "\n>> TIMEOUT waiting for password prompt"; exit 10 }
  eof     { puts "\n>> connection closed before password prompt"; exit 12 }
}
expect {
  "sftp>" {}
  -nocase "permission denied" { puts "\n>> BAD PASSWORD (permission denied)"; exit 13 }
  timeout { puts "\n>> no prompt after password"; exit 11 }
  eof     { puts "\n>> connection closed after password"; exit 12 }
}
send -- "cd \"$dir\"\r"
expect "sftp>"
foreach f $files {
  send -- "put \"$f\"\r"
  expect {
    "sftp>" {}
    timeout { puts "\n>> TIMEOUT uploading $f"; exit 14 }
    eof     { puts "\n>> connection lost uploading $f"; exit 12 }
  }
}
send -- "ls -l\r"
expect "sftp>"
send -- "bye\r"
expect eof
catch wait result
exit [lindex $result 3]
EXP
}

# verify: no error markers in the transcript AND every basename shows in listing
verify_transcript() {
  if grep -Eiq "couldn't|no such file|permission denied|not found|upload error|write error" "$LOGFILE"; then
    echo "   (found an error marker in the sftp transcript)" >&2
    return 1
  fi
  local rc=0
  for f in "$@"; do
    if ! grep -Fq "$(basename "$f")" "$LOGFILE"; then
      echo "   WARN: '$(basename "$f")' not present in remote listing" >&2
      rc=1
    fi
  done
  return $rc
}

attempt() { do_upload && verify_transcript "$@"; }

if attempt "$@"; then
  echo "✅ Upload complete and verified in ${REMOTE_DIR}."
else
  echo "First attempt failed, retrying once..." >&2
  sleep 2
  if attempt "$@"; then
    echo "✅ Upload complete and verified (on retry)."
  else
    echo "❌ Upload failed. Check the password/tunnel and try again." >&2
    exit 4
  fi
fi
