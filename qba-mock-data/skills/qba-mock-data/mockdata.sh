#!/usr/bin/env bash
# Thin client for the staging-only admin mock-data API (VP-3599).
#   mockdata.sh login                 # store your staging admin token (asked on stdin, never echoed)
#   mockdata.sh generate <profile.json>
#   mockdata.sh status <runId>
#   mockdata.sh list
#   mockdata.sh cleanup <runId>
set -euo pipefail
BASE=${QBA_MOCK_API:-https://api-admin-staging.qlub.cloud/v1}
TOKEN_FILE=${QBA_MOCK_TOKEN_FILE:-$HOME/.config/qba-mock-data/token}

case $BASE in
  *staging*|*demo*|*dev[0-9]*|*localhost*) ;;
  *) echo "refusing: $BASE is not a lower env" >&2; exit 2;;
esac

call() {
  [ -s "$TOKEN_FILE" ] || { echo "no token: run '$0 login' first" >&2; exit 3; }
  local out code
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "$BASE$2" \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" -H 'x-user-type: admin' -H 'x-token-type: admin' \
    -H 'Content-Type: application/json' ${3:+--data-binary "@$3"})
  cat "$out"; echo; rm -f "$out"
  case $code in
    2*) ;;
    401) echo "token expired or invalid: run '$0 login' with a fresh token" >&2; exit 4;;
    403) echo "your staging admin account lacks QlubAdmin/QlubSuperAdmin" >&2; exit 5;;
    *) echo "HTTP $code" >&2; exit 1;;
  esac
}

case ${1:-} in
  login)
    mkdir -p "$(dirname "$TOKEN_FILE")"
    printf 'Paste your staging admin access token, then Enter: ' >&2
    read -rs token; echo >&2
    umask 077; printf '%s' "${token#Bearer }" > "$TOKEN_FILE"
    echo "saved to $TOKEN_FILE" >&2;;
  generate) call POST /admin/mock-data/runs "${2:?profile.json}";;
  status) call GET "/admin/mock-data/runs/${2:?runId}";;
  list) call GET /admin/mock-data/runs;;
  cleanup) call DELETE "/admin/mock-data/runs/${2:?runId}";;
  *) echo "usage: $0 login | generate <profile.json> | status <runId> | list | cleanup <runId>" >&2; exit 2;;
esac
