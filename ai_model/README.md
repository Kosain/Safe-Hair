# AI Model

Contents:

- `scripts/` training and export scripts
- `datasets/Male/` scalp dataset
- `models/` trained artifacts (`.joblib`, `.pt`, `.onnx`)

Typical flow:

```powershell
cd scripts
python train_all_ai_models.py --dataset "..\datasets\Male"
```

Backend runtime still uses `backend/models/` by default. Copy/sync updated models there after retraining.

