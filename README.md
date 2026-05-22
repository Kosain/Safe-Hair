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
  - Trained models (auto-loaded from `backend/models/`): `scalp_seg.onnx`, `bald_regressor.joblib`, `scalp_conditions.joblib`
- Mobile app:
  - `cd mobile_app`
  - `flutter pub get`
  - `flutter run`
- Web app:
  - `cd mobile_app`
  - `flutter run -d chrome --web-port=8080`

## Scalp AI overlays (FYP)

Analysis uses a **trained CNN** (segmentation) plus **rule-based outlines** on each new photo — not hard-coded for one image.

| Color | Meaning | Drawn when |
|-------|---------|------------|
| Red | Severe bald / high-risk bare scalp | Detected |
| Teal | Mild thinning | Detected |
| Yellow/orange | Dandruff or irritation | Detected only |

Retrain: `cd backend` then `py train_all_ai_models.py` (see `backend/train_scalp_conditions.py` for condition labels).
