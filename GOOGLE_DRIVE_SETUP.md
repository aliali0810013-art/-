# SINDAR Google Drive Sync — one-time Android OAuth setup

The application code uses only the user's own Google Drive account. There is no SINDAR
server, no service account, no Drive API key stored in the APK, and no external sync
backend.

## What is already implemented

- `google_sign_in` account selection from the Android app.
- Google Drive v3 using only `DriveApi.driveAppdataScope`.
- Hidden `SINDAR_Cloud_Sync` folder under Drive `appDataFolder`.
- One encrypted `sindar_backup.zip` that is replaced on every successful backup.
- SQLite + `sindar_attachments` are compressed and encrypted with AES-256-GCM.
- Restore validates the archive and runs SQLite `PRAGMA integrity_check` before and
  after replacing the active database.
- Automatic rollback protects the previous local database if restore fails.
- Manual, automatic (6-hour), daily and weekly scheduling through Android WorkManager.
- Background jobs run only with network connectivity and use silent Google sign-in.

## Google requirement that cannot be embedded in source code

Google Sign-In requires an OAuth Android client registered for the exact package name and
the SHA-1 certificate that signs the APK. This is Google platform configuration, not a
paid server and not a secret API key.

1. Create or select a Google Cloud project.
2. Enable **Google Drive API**.
3. Configure the OAuth consent screen.
4. Create an **Android OAuth client** with:
   - Package name: `com.sindar.sindar_app`
   - SHA-1: use the value printed by the GitHub Actions step
     **Print APK signing certificate** for the final `sindar_app.apk`.
5. If the OAuth consent screen is still in Testing mode, add the intended Google account
   as a test user.
6. Install the same final APK whose SHA-1 was registered.

No `google-services.json` is required by the SINDAR Drive code itself, and no client
secret should be committed to this repository.

## New phone restore flow

1. Install SINDAR.
2. Activate the customer's SINDAR license.
3. Open **Settings → Backup & Sync**.
4. Connect the same Google account.
5. Tap **Restore backup**.

Backup encryption is derived from the stable licensed customer identity after a valid
license token has been applied, so renewing the same license does not make older backups
undecryptable.
