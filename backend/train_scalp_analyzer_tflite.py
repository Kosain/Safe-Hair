"""
Train 3-class scalp segmentation (severe / mild / infection) + EfficientNetB0 classifier → TFLite.

Classes (segmentation, 4-channel softmax: background + 3 regions):
  ch1 = baldness_high (red)
  ch2 = baldness_mild (orange)
  ch3 = dandruff_infection (teal) — pseudo from texture when no mask labels

Target validation mean IoU >= 0.85 on held-out pairs.

Usage:
  py train_scalp_analyzer_tflite.py --seg-dataset "PATH\\hair_loss_seg"
  py train_scalp_analyzer_tflite.py --seg-dataset datasets/scalp_topdown/structured/Male --cls-dataset "PATH\\hair_disease"
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np

IMG_SEG = 256
IMG_CLS = 224
VAL_TARGET = 0.85
NUM_SEG_CLASSES = 4  # bg, severe, mild, infection


def _require_tf():
    try:
        import tensorflow as tf
        from tensorflow import keras
        from tensorflow.keras import layers
    except ImportError as e:
        raise SystemExit(f"TensorFlow required: pip install -r requirements-ml.txt\n{e}")
    return tf, keras, layers


def _seg_pairs(root: Path) -> List[Tuple[Path, Path]]:
    pairs: List[Tuple[Path, Path]] = []
    if not root.is_dir():
        return pairs
    for class_dir in sorted([p for p in root.iterdir() if p.is_dir()]):
        try:
            cid = class_dir.name
            int(cid)
        except ValueError:
            continue
        for view in ("front", "top"):
            ip = class_dir / f"{view}_{cid}.png"
            mp = class_dir / f"mask_{view}_{cid}.png"
            if ip.exists() and mp.exists():
                pairs.append((ip, mp))
    if pairs:
        return pairs
    images, masks = root / "images", root / "masks"
    if images.is_dir() and masks.is_dir():
        for ip in sorted(images.glob("*")):
            mp = masks / ip.name
            if mp.exists():
                pairs.append((ip, mp))
    return pairs


def _mask_to_onehot(m: np.ndarray, img_bgr: np.ndarray) -> np.ndarray:
    """Grayscale mask 0 / 128 / 255 → one-hot HxWx4."""
    h, w = m.shape[:2]
    severe = (m >= 200).astype(np.float32)
    mild = ((m >= 80) & (m < 200)).astype(np.float32)
    infect = np.zeros((h, w), dtype=np.float32)
    try:
        from scalp_analyzer import _infection_mask

        zone = np.ones((h, w), dtype=np.uint8) * 255
        tissue = zone.copy()
        infect = (_infection_mask(img_bgr, zone, tissue, None).astype(np.float32) / 255.0)
        infect = np.clip(infect, 0, 1) * 0.65
    except Exception:
        pass
    bg = np.clip(1.0 - np.maximum(np.maximum(severe, mild), infect), 0.0, 1.0)
    stack = np.stack([bg, severe, mild, infect], axis=-1)
    s = stack.sum(axis=-1, keepdims=True) + 1e-7
    return (stack / s).astype(np.float32)


def _load_seg_pair(ip: Path, mp: Path) -> Tuple[np.ndarray, np.ndarray]:
    img = cv2.imread(str(ip), cv2.IMREAD_COLOR)
    m = cv2.imread(str(mp), cv2.IMREAD_GRAYSCALE)
    if img is None or m is None:
        raise ValueError(str(ip))
    img = cv2.resize(img, (IMG_SEG, IMG_SEG), interpolation=cv2.INTER_AREA)
    m = cv2.resize(m, (IMG_SEG, IMG_SEG), interpolation=cv2.INTER_NEAREST)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    y = _mask_to_onehot(m, img)
    return rgb, y


def build_unet_multiclass(keras, layers, n_classes: int = NUM_SEG_CLASSES):
    inputs = layers.Input((IMG_SEG, IMG_SEG, 3))
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
    out = layers.Conv2D(n_classes, 1, activation="softmax")(c4)
    return keras.Model(inputs, out)


def _mean_iou(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    yt = np.argmax(y_true, axis=-1).ravel()
    yp = np.argmax(y_pred, axis=-1).ravel()
    ious = []
    for c in range(1, NUM_SEG_CLASSES):
        inter = float(np.sum((yt == c) & (yp == c)))
        union = float(np.sum((yt == c) | (yp == c)))
        if union > 0:
            ious.append(inter / union)
    return float(np.mean(ious)) if ious else 0.0


def train_segmentation(seg_root: Path, out_dir: Path, epochs: int, batch: int) -> dict:
    tf, keras, layers = _require_tf()
    pairs = _seg_pairs(seg_root)
    if len(pairs) < 4:
        raise SystemExit(f"Need >=4 image/mask pairs under {seg_root}")

    rng = np.random.default_rng(42)
    idx = np.arange(len(pairs))
    rng.shuffle(idx)
    n_val = max(1, int(len(pairs) * 0.2))
    val_idx = sorted(set(idx[:n_val].tolist()))
    train_idx = [i for i in range(len(pairs)) if i not in val_idx]

    def stack(idxs):
        xs, ys = [], []
        for i in idxs:
            a, b = _load_seg_pair(*pairs[i])
            xs.append(a)
            ys.append(b)
        return np.stack(xs), np.stack(ys)

    X_train, Y_train = stack(train_idx)
    X_val, Y_val = stack(val_idx)

    aug = keras.Sequential(
        [
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.12),
            layers.RandomZoom(0.15),
            layers.RandomBrightness(0.12),
            layers.RandomContrast(0.1),
        ]
    )

    model = build_unet_multiclass(keras, layers)
    lr_schedule = keras.optimizers.schedules.CosineDecay(
        initial_learning_rate=1e-3, decay_steps=max(1, epochs * (len(train_idx) // batch)), alpha=1e-5
    )
    model.compile(
        optimizer=keras.optimizers.Adam(lr_schedule),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    def _gen(X, Y, training):
        while True:
            i = int(rng.integers(0, len(X)))
            x, y = X[i], Y[i]
            if training:
                xy = aug(tf.concat([x, y], axis=-1))  # type: ignore[name-defined]
                x, y = xy[..., :3], xy[..., 3:]
            yield x, y

    steps = max(1, len(train_idx) // batch)
    train_ds = (
        tf.data.Dataset.from_generator(
            lambda: _gen(X_train, Y_train, True),
            output_signature=(
                tf.TensorSpec((IMG_SEG, IMG_SEG, 3), tf.float32),
                tf.TensorSpec((IMG_SEG, IMG_SEG, NUM_SEG_CLASSES), tf.float32),
            ),
        )
        .batch(batch)
        .prefetch(2)
    )
    val_ds = tf.data.Dataset.from_tensor_slices((X_val, Y_val)).batch(batch)

    early = keras.callbacks.EarlyStopping(patience=12, restore_best_weights=True, monitor="val_loss")
    model.fit(
        train_ds,
        steps_per_epoch=steps,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=[early],
        verbose=1,
    )

    pred = model.predict(X_val, verbose=0)
    miou = _mean_iou(Y_val, pred)
    val_acc = float(np.mean(np.argmax(Y_val, -1) == np.argmax(pred, -1)))

    keras_path = out_dir / "scalp_segmentation_3class.keras"
    model.save(keras_path)
    tflite_path = out_dir / "scalp_model.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_path.write_bytes(converter.convert())
    print(f"Saved {tflite_path} | val mIoU={miou:.3f} acc={val_acc:.3f}")

    if miou < VAL_TARGET:
        print(f"WARNING: mIoU {miou:.3f} < target {VAL_TARGET}. Add Hair Loss Segmentation data or train longer.")

    try:
        import subprocess
        import sys

        onnx_out = out_dir / "scalp_seg.onnx"
        subprocess.run(
            [sys.executable, "export_scalp_seg_onnx.py", "--keras", str(keras_path), "--onnx", str(onnx_out)],
            cwd=str(Path(__file__).parent),
            check=False,
        )
    except Exception as e:
        print(f"ONNX export skipped: {e}")

    return {"val_mean_iou": miou, "val_pixel_accuracy": val_acc}


def _cls_samples(root: Path) -> Tuple[List[Path], List[int], List[str]]:
    paths, labels, names = [], [], []
    if not root.is_dir():
        return paths, labels, names
    for i, sub in enumerate(sorted([p for p in root.iterdir() if p.is_dir()])):
        names.append(sub.name)
        for ext in ("*.jpg", "*.jpeg", "*.png", "*.bmp"):
            for ip in sub.glob(ext):
                paths.append(ip)
                labels.append(i)
    return paths, labels, names


def train_classifier(cls_root: Path, out_dir: Path, epochs: int, batch: int) -> dict:
    tf, keras, layers = _require_tf()
    paths, labels, class_names = _cls_samples(cls_root)
    if len(paths) < 30 or len(class_names) < 2:
        print(f"Skip classifier: {len(paths)} images, {len(class_names)} classes under {cls_root}")
        return {}

    from tensorflow.keras.applications import EfficientNetB0

    rng = np.random.default_rng(42)
    idx = np.arange(len(paths))
    rng.shuffle(idx)
    n_val = max(1, int(len(paths) * 0.15))
    val_idx, train_idx = idx[:n_val], idx[n_val:]

    def load_batch(idxs):
        xs, ys = [], []
        for j in idxs:
            img = cv2.imread(str(paths[j]), cv2.IMREAD_COLOR)
            if img is None:
                continue
            rgb = cv2.resize(cv2.cvtColor(img, cv2.COLOR_BGR2RGB), (IMG_CLS, IMG_CLS))
            xs.append(rgb.astype(np.float32) / 255.0)
            ys.append(labels[j])
        return np.stack(xs), keras.utils.to_categorical(ys, num_classes=len(class_names))

    X_train, Y_train = load_batch(train_idx)
    X_val, Y_val = load_batch(val_idx)

    base = EfficientNetB0(include_top=False, weights="imagenet", input_shape=(IMG_CLS, IMG_CLS, 3))
    base.trainable = False
    x = layers.GlobalAveragePooling2D()(base.output)
    x = layers.Dropout(0.35)(x)
    out = layers.Dense(len(class_names), activation="softmax")(x)
    model = keras.Model(base.input, out)
    lr_schedule = keras.optimizers.schedules.CosineDecay(
        initial_learning_rate=5e-4,
        decay_steps=max(1, epochs * max(1, len(train_idx) // batch)),
        alpha=1e-5,
    )
    model.compile(
        optimizer=keras.optimizers.Adam(lr_schedule),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    aug = keras.Sequential(
        [
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.15),
            layers.RandomZoom(0.12),
            layers.RandomBrightness(0.1),
        ]
    )
    early = keras.callbacks.EarlyStopping(patience=10, restore_best_weights=True, monitor="val_accuracy")
    model.fit(
        aug(X_train),
        Y_train,
        validation_data=(X_val, Y_val),
        epochs=epochs,
        batch_size=batch,
        callbacks=[early],
        verbose=1,
    )
    val_acc = float(model.evaluate(X_val, Y_val, verbose=0)[1])
    (out_dir / "scalp_classifier_classes.json").write_text(json.dumps(class_names, indent=2), encoding="utf-8")
    tflite_path = out_dir / "scalp_classifier.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_path.write_bytes(converter.convert())
    print(f"Saved {tflite_path} val_acc={val_acc:.3f}")
    if val_acc < VAL_TARGET:
        print(f"WARNING: val accuracy {val_acc:.3f} < {VAL_TARGET}")
    return {"val_accuracy": val_acc, "classes": class_names}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seg-dataset", type=Path, default=Path(os.environ.get("SCALP_SEG_DATASET", "datasets/scalp_topdown/structured/Male")))
    ap.add_argument("--cls-dataset", type=Path, default=Path(os.environ.get("SCALP_CLS_DATASET", "")))
    ap.add_argument("--out-dir", type=Path, default=Path("models"))
    ap.add_argument("--epochs", type=int, default=50)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--skip-cls", action="store_true")
    args = ap.parse_args()

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    seg_m = train_segmentation(args.seg_dataset.expanduser().resolve(), out_dir, args.epochs, args.batch)
    cls_m = {}
    if not args.skip_cls and str(args.cls_dataset) and Path(args.cls_dataset).is_dir():
        cls_m = train_classifier(args.cls_dataset.expanduser().resolve(), out_dir, args.epochs, args.batch)
    summary = {"segmentation": seg_m, "classification": cls_m}
    (out_dir / "scalp_analyzer_train_metrics.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
