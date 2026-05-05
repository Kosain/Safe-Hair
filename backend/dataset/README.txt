Safe Hair — scalp training data

1) Put your top-down scalp photos (JPG/PNG) in:
   backend/dataset/raw_scalp/

   Or use any folder and pass --raw "D:\path\to\folder"

2) Build training pairs (image + pseudo-mask from OpenCV segmentation):
   cd backend
   python prepare_scalp_dataset.py --raw dataset/raw_scalp --out dataset/prepared/Male

3) Train the bald-ratio regressor used by the API (optional, improves STRICT_AI + USE_TRAINED_MODEL):
   python train_bald_model.py --dataset dataset/prepared/Male --output models/bald_regressor.joblib

4) Run the API with:
   set USE_TRAINED_MODEL=true
   (TRAINED_MODEL_PATH defaults to models/bald_regressor.joblib)

Note: Pseudo-masks are OpenCV-derived, not manual labels. For production CNN segmentation,
export an ONNX model and set USE_CNN=true and CNN_MODEL_PATH=...
