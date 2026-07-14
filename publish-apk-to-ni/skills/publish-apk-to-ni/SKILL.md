---
name: publish-apk-to-ni
description: Publish this APK to NI — uploads an APK build to Network International's (N-Genius) SFTP server folder /343/Inbound/APK through the Teleport tunnel, then prepares the release notification email as a Gmail draft. Use whenever the user wants to publish, release, upload, push, or deliver an .apk to NI. Asks for the SFTP password and the signer's name at runtime; stores no credentials.
---

# Publish APK to Network International

"Publishing" = two steps:
1. **Upload** the local `.apk` to `/343/Inbound/APK` on the NI SFTP server.
2. **Prepare the release email** as a Gmail draft (there is no send tool — the
   Gmail integration only supports drafts; the user reviews and clicks Send).

**No credentials are stored by this skill.** The SFTP password and the signer's
name are collected at runtime and never written to disk.

## Step 0 — Collect inputs (DO NOT persist)

Ask the user for:
1. **NI SFTP password** — required to log in. Pass it ONLY via the
   `NI_SFTP_PASSWORD` environment variable on the command line (Step 1). Never
   write it to `config.env` or any file, and never echo it back.
2. **Signer name** — literally ask *"Regards, who?"* — used to sign the email.

If the SFTP username differs from the default (`qlubuser`), also ask for it and
pass it as `NI_SFTP_USER`.

## Step 1 — Upload

1. Confirm the local APK path exists.
2. Run the uploader, passing the password inline as an env var (not persisted):

   ```bash
   NI_SFTP_PASSWORD='<password>' "<skill-dir>/upload-apk.sh" "/absolute/path/to/build.apk"
   ```
   (`<skill-dir>` is the directory this SKILL.md lives in. Multiple files allowed.
   If the user runs it themselves without the env var, the script prompts for the
   password.)
3. Confirm the printed `ls -l` shows the file with the correct size.

## Step 2 — Release notification email (Gmail draft)

Derive the **App Number** from the filename `qlub-ngenius-v<version>(<build>).apk`
→ App Number = `<version> (<build>)`. E.g. `qlub-ngenius-v1.51.0(429).apk`
→ `1.51.0 (429)`. If ambiguous, confirm with the user.

Create the draft with `create_draft` (Gmail MCP), replacing every `< App Number >`,
`< apk-filename >`, and `< Signer Name >`:

- **to:**
  - `Jagadeshwar.Reddy@network.global`
  - `Selwyn.Marques@network.global`
- **cc:**
  - `softpos_team@qlub.io`
  - `john@qlub.io`
  - `abhishek.sharma@qlub.io`
  - `zohaib.anwaar@qlub.io`
  - `muhammad.moeez@qlub.io`
  - `reza.pilehvar@qlub.io`
  - `putik@qlub.io`
- **subject:** `Qlub x NI - Integrated Payment Terminal Release of Version < App Number >`
- **body:**
  ```
  Hi all,

  We have successfully tested the SOFTPOS application.

  Can we please deploy version < App Number > to production?

  This release should be available on both manual upload and NGENIUS store upload.

  The APK has been uploaded to the SFTP server at:
  /343/Inbound/APK/< apk-filename >

  @Jagadeshwar Reddy please provide confirmation of UAT signoff.

  Regards,
  < Signer Name >
  ```

After creating the draft, tell the user it's ready in Gmail Drafts to review and
send (report the draft id). **Do not** attempt to send it (no send tool exists).

### Test-first option
When asked to "try it" first, create the draft addressed ONLY to the signer's own
address (no NI recipients, no cc) so they can preview it safely, then create the
real multi-recipient draft once approved.

## Config

`config.env` holds only NON-SECRET settings (Teleport node, host, port, local
port, default username, remote dir) — safe to share/commit. No password lives
there.

## Troubleshooting

- **"not logged into Teleport"** → user runs `tsh login` (may need SSO+MFA);
  suggest `! tsh login` in-session.
- **"BAD PASSWORD"** → wrong SFTP password; re-run with the correct one.
- **Port 6666 busy** → change `LOCAL_PORT` in `config.env`.

## Security notes

- The SFTP password is never stored — it comes from `NI_SFTP_PASSWORD` or an
  interactive prompt only.
- Prefer SSH-key auth over the shared password long term if NI enables it.
