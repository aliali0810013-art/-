# SINDAR 1.0.0 — Final Release Handoff

Branch: `sindar-phase1`

This is the final integrated delivery baseline for SINDAR.

## Branding
- Official supplied SINDAR brand is embedded in the customer dashboard.
- Official supplied SINDAR brand is embedded in SINDAR Master Admin.
- Android launcher icon uses the document/chart mark taken from the same supplied brand.
- Android labels are forced in CI after `flutter create`:
  - Customer app: `سندار`
  - Owner app: `سندار - الإدارة`
- CI explicitly rewrites `android:icon` to the tracked SINDAR launcher asset so later host-project regeneration cannot restore the Flutter default icon.

## Integrated operational system
The release includes the completed SQLite ERP, double-entry posting, sales, quotations,
purchases, suppliers, customers/statements, vouchers, journals, inventory/barcodes,
assets/custody, payroll, analytics, VAT controls, ZATCA QR, document PDFs, RBAC,
license enforcement, Master Admin license QR/tokens, encrypted Google Drive backup and restore,
and automatic backup scheduling.

## Final release checks
Every final release run must pass:
- `flutter analyze`
- shared core tests
- customer Flutter tests
- owner/admin Flutter tests
- release APK build for both applications
- APK signing-certificate inspection
- artifact upload

Artifacts contain:
- `sindar_app.apk`
- `sindar_admin.apk`
- each artifact's `signing-cert.txt`

## Google Drive production connection
SINDAR uses the user's own Google Drive AppData storage and no SINDAR sync server.
Google itself requires the Android OAuth client to be registered against the final package
and final APK signing SHA-1. This is the only account-side production configuration and is
documented in `GOOGLE_DRIVE_SETUP.md`; no client secret is committed into the application.

Package:
`com.sindar.sindar_app`

After registering the final signing SHA-1 and enabling Google Drive API, the flow is:
Settings → Backup & Sync → Connect Google Drive → Backup now / Restore.
