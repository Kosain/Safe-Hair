# Web App

This project reuses the same Flutter codebase as `mobile_app` (shared code ~90%+).

Run web locally from shared Flutter source:

```powershell
cd ..\mobile_app
flutter pub get
flutter run -d chrome --web-port=8080
```

If you want a fully separate Flutter web project folder, it can be scaffolded later and connected to `shared/` packages.

