"""
Train a TensorFlow (Keras) U-Net–style segmenter for scalp photos using your `Male` dataset.

Expected layout (same as train_bald_model.py):
  Male/
    1/front_1.png, mask_front_1.png, top_1.png, mask_top_1.png
    2/...

Masks: grayscale, white = bald / thinning target, black = hair (or use soft labels 0–255).

Pipeline:
  1. pip install -r requirements-ml.txt
  2. python train_scalp_segmentation_tf.py --dataset "d:\\Safe\\Male" --epochs 40
  3. Export ONNX for the FastAPI app (onnxruntime):
       python export_scalp_seg_onnx.py --keras models/scalp_segmentation.keras --onnx models/scalp_seg.onnx
  4. Run API with:
       set USE_CNN=true
       set CNN_MODEL_PATH=models\\scalp_seg.onnx

Thin hair: use mid-gray (~127) in masks as a third class after extending this script to 3-channel softmax.
Current model: binary bald-vs-hair with sigmoid.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np

# Optional TF import so `python train_bald_model.py` still works without TF.
try:
    import tensorflow as tf
    from tensorflow.keras import layers, models  # type: ignore
except ImportError as e:
    tf = None  # type: ignore
    layers = models = None  # type: ignore
    _TF_ERR = e
else:
    _TF_ERR = None

IMG_SIZE = 256


def _collect_pairs(dataset_root: Path) -> List[Tuple[Path, Path]]:
    pairs: List[Tuple[Path, Path]] = []
    for class_dir in sorted([p for p in dataset_root.iterdir() if p.is_dir()]):
        try:
            cid = class_dir.name
            int(cid)
        except ValueError:
            continue
        for view in ("front", "top"):
            img_path = class_dir / f"{view}_{cid}.png"
            mask_path = class_dir / f"mask_{view}_{cid}.png"
            if img_path.exists() and mask_path.exists():
                pairs.append((img_path, mask_path))
    return pairs


def _load_pair(img_path: Path, mask_path: Path) -> Tuple[np.ndarray, np.ndarray]:
    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR)
    m = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if img is None or m is None:
        raise ValueError(f"Unreadable {img_path} / {mask_path}")
    img = cv2.resize(img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_AREA)
    m = cv2.resize(m, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    # Binary mask: treat mid-gray as partial bald (thin) -> scaled toward 1.0
    y = m.astype(np.float32) / 255.0
    y = np.clip(y[..., None], 0.0, 1.0)
    return rgb, y


def build_unet(input_shape=(IMG_SIZE, IMG_SIZE, 3)):
    assert layers is not None and models is not None
    inputs = layers.Input(input_shape)

    c1 = layers.Conv2D(32, 3, activation="relu", padding="same")(inputs)
    c1 = layers.Conv2D(32, 3, activation="relu", padding="same")(c1)
    p1 = layers.MaxPooling2D(2)(c1)

    c2 = layers.Conv2D(64, 3, activation="relu", padding="same")(p1)
    c2 = layers.Conv2D(64, 3, activation="relu", padding="same")(c2)
    p2 = layers.MaxPooling2D(2)(c2)

    b = layers.Conv2D(128, 3, activation="relu", padding="same")(p2)
    b = layers.Conv2D(128, 3, activation="relu", padding="same")(b)

    u1 = layers.UpSampling2D(2)(b)
    u1 = layers.concatenate([u1, c2])
    c3 = layers.Conv2D(64, 3, activation="relu", padding="same")(u1)
    c3 = layers.Conv2D(64, 3, activation="relu", padding="same")(c3)

    u2 = layers.UpSampling2D(2)(c3)
    u2 = layers.concatenate([u2, c1])
    c4 = layers.Conv2D(32, 3, activation="relu", padding="same")(u2)
    c4 = layers.Conv2D(32, 3, activation="relu", padding="same")(c4)

    outputs = layers.Conv2D(1, 1, activation="sigmoid")(c4)
    return models.Model(inputs, outputs)


def train(dataset_root: Path, out_keras: Path, epochs: int, batch: int) -> None:
    if tf is None:
        raise SystemExit(
            "TensorFlow is not installed. Run: pip install -r requirements-ml.txt\n" f"Original error: {_TF_ERR}"
        )

    pairs = _collect_pairs(dataset_root)
    if len(pairs) < 2:
        raise SystemExit(
            f"Need at least 2 image/mask pairs under {dataset_root}. "
            "Use prepare_scalp_dataset.py or place Male/1/front_1.png + mask_front_1.png etc."
        )

    rng = np.random.default_rng(42)
    idx = np.arange(len(pairs))
    rng.shuffle(idx)
    n_val = max(1, int(len(pairs) * 0.2))
    val_idx = set(idx[:n_val].tolist())
    val_idx_l = sorted(val_idx)

    train_idx = [i for i in range(len(pairs)) if i not in val_idx]
    X_train = np.stack([_load_pair(*pairs[i])[0] for i in train_idx])
    Y_train = np.stack([_load_pair(*pairs[i])[1] for i in train_idx])
    X_val = np.stack([_load_pair(*pairs[i])[0] for i in val_idx_l])
    Y_val = np.stack([_load_pair(*pairs[i])[1] for i in val_idx_l])

    model = build_unet()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss="binary_crossentropy", metrics=["mae"])

    early = tf.keras.callbacks.EarlyStopping(patience=8, restore_best_weights=True)
    out_keras.parent.mkdir(parents=True, exist_ok=True)

    model.fit(
        X_train,
        Y_train,
        validation_data=(X_val, Y_val),
        epochs=epochs,
        batch_size=batch,
        callbacks=[early],
        verbose=1,
    )
    model.save(out_keras)
    print(f"Saved Keras model: {out_keras}")
    print("Export ONNX: python export_scalp_seg_onnx.py --keras", out_keras, "--onnx models/scalp_seg.onnx")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dataset", default=os.environ.get("SCALP_DATASET_MALE", r"d:\Safe\Male"), type=Path)
    p.add_argument("--out", default=Path("models/scalp_segmentation.keras"), type=Path)
    p.add_argument("--epochs", type=int, default=40)
    p.add_argument("--batch", type=int, default=4)
    args = p.parse_args()
    train(args.dataset.expanduser().resolve(), args.out, args.epochs, args.batch)


if __name__ == "__main__":
    main()
