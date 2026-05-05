Scalp AI dataset (top-down / vertex photos)
==========================================

1) Put your scalp images here:
   backend/datasets/scalp_topdown/raw/
   Supported: .jpg, .jpeg, .png, .webp

2) Build training pairs (OpenCV generates bald masks as weak labels):
   cd backend
   python build_scalp_dataset_from_raw.py --input datasets/scalp_topdown/raw --output datasets/scalp_topdown/structured/Male

3) Train the bald-ratio regressor used by the API (optional; enables USE_TRAINED_MODEL):
   python train_bald_model.py --dataset datasets/scalp_topdown/structured/Male --output models/bald_regressor.joblib

4) Run API with:
   set USE_TRAINED_MODEL=true
   (STRICT_AI may require this model if enabled)

Note: Masks are heuristic (same pipeline as inference). For best accuracy, hand-correct masks or use a labeled CNN dataset and export masks to the same Male/... layout.
