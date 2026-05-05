# Safe Hair Monorepo

This repository is now organized as:

```
safe_hair/
├── mobile_app/   # Flutter mobile-first app (also contains shared Flutter code)
├── web_app/      # Web entrypoint docs/scripts (reuses mobile_app code)
├── backend/      # FastAPI backend
├── ai_model/     # AI training scripts, datasets, exported models
└── shared/       # Shared docs/resources
```

## Quick start

- Backend:
  - `./run_backend.ps1` (PowerShell)
  - `run_backend.bat` (CMD)
- Mobile app:
  - `cd mobile_app`
  - `flutter pub get`
  - `flutter run`
- Web app:
  - `cd mobile_app`
  - `flutter run -d chrome`
