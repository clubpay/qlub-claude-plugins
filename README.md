# qlub-tools — Claude Code plugin marketplace

Internal Claude Code plugins for Qlub.

## Plugins

### `publish-apk-to-ni`
Uploads an Android APK to Network International's (N-Genius) SFTP server
(`/343/Inbound/APK`) through the Teleport tunnel, then prepares the release
notification email as a Gmail draft. It **asks for the SFTP password and the
signer's name at runtime and stores no credentials**.

### `qba-mock-data`
Describe what a pitch needs ("UAE café group, 3 branches, 30 days, high tips") and
get synthetic demo venues with payment and tip history on **staging**, ready to show
in QBA. It talks to the staging-only admin API with **your own staging admin token**,
which you store once with `mockdata.sh login`; it is never sent to the chat. Backend:
admin-backend `admin/mock-data` (VP-3599). Panel squad owns it.

## Install (per teammate)

```bash
# 1) Add this marketplace once
/plugin marketplace add <git-host>/<org>/qlub-claude-plugins

# 2) Install the plugin
/plugin install publish-apk-to-ni@qlub-tools
/plugin install qba-mock-data@qlub-tools

# 3) Reload
/reload-plugins
```

Then invoke it in Claude Code:

```
/publish-apk-to-ni
```
or just: *"publish this APK to NI: /path/to/build.apk"*

## Prerequisites

Each user needs:
- **Teleport access** with a login that can reach `data-analytics-v2` (the skill
  uses the `bi_analytics` login by default) and port-forward permission. Run
  `tsh login` first.
- CLI tools: `tsh`, `expect`, `nc` (all standard on macOS).
- The **Gmail connector** enabled in their Claude session (for the draft step).
- The current **NI SFTP password** (the skill prompts for it; it is not shipped).

## Security

- **No credentials are committed.** `config.env` contains only non-secret
  connection settings (host, port, Teleport node, default username, remote dir).
- The SFTP password is supplied via the `NI_SFTP_PASSWORD` env var or an
  interactive prompt, and is never written to disk.
- Rotate the shared NI SFTP password periodically.
