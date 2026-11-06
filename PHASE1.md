# SINDAR — Phase 1

Phase 1 contains:

- Flutter client app: `sindar_app`
- Flutter master-admin app: `sindar_admin`
- SINDAR navy/gold theme
- RTL responsive dashboard matching the supplied visual direction
- KPI cards, quick actions, module grid, recent transactions, and bottom navigation
- Embedded vector brand asset
- GitHub Actions matrix build that analyzes, tests, and builds APKs for both apps

## Branch policy

Development is isolated on `sindar-phase1`. The application code is not merged to `main`.

## Build locally

```bash
cd sindar_app
flutter create --platforms=android --org com.sindar --project-name sindar_app .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Repeat for `sindar_admin`.
