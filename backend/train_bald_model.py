"""
Train a bald-ratio regressor from SAFE_HAIR dataset masks.

Dataset expected structure (example):
  Male/
    1/
      front_1.png
      top_1.png
      mask_front_1.png
      mask_top_1.png
    2/
    ...
    15/

Usage:
  python train_bald_model.py --dataset "d:\\Zain's DOCUMENT\\fyp\\SAFE_HAIR DATASET\\Male" --output "models/bald_regressor.joblib"

Or build from your own top-down scalp photos first:
  python build_scalp_dataset_from_raw.py --input datasets/scalp_topdown/raw --output datasets/scalp_topdown/structured/Male
  python train_bald_model.py --dataset datasets/scalp_topdown/structured/Male --output models/bald_regressor.joblib
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import List, Tuple

import cv2
import joblib
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error


def _extract_features(img_bgr: np.ndarray) -> np.ndarray:
    """Feature vector from a scalp image."""
    img = cv2.resize(img_bgr, (256, 256), interpolation=cv2.INTER_AREA)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Color stats
    h_mean, s_mean, v_mean = [float(np.mean(hsv[:, :, i])) for i in range(3)]
    h_std, s_std, v_std = [float(np.std(hsv[:, :, i])) for i in range(3)]
    g_mean = float(np.mean(gray))
    g_std = float(np.std(gray))

    # Texture / edge stats
    lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    edges = cv2.Canny(gray, 70, 140)
    edge_ratio = float(np.mean(edges > 0))

    # Bright scalp-like ratios by heuristic ranges
    bright_ratio = float(np.mean(gray > 160))
    mid_ratio = float(np.mean((gray > 100) & (gray <= 160)))
    dark_ratio = float(np.mean(gray <= 100))

    return np.array([
        h_mean, s_mean, v_mean,
        h_std, s_std, v_std,
        g_mean, g_std,
        lap_var, edge_ratio,
        bright_ratio, mid_ratio, dark_ratio,
    ], dtype=np.float32)


def _load_mask_ratio(mask_path: Path) -> float:
    mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if mask is None:
        raise ValueError(f"Could not read mask: {mask_path}")
    return float(np.mean(mask > 127))


def _collect_samples(dataset_root: Path) -> Tuple[np.ndarray, np.ndarray]:
    X: List[np.ndarray] = []
    y: List[float] = []

    for class_dir in sorted([p for p in dataset_root.iterdir() if p.is_dir()]):
        # Parse class id if possible (1..15). Used as weak prior in target blending.
        try:
            class_id = int(class_dir.name)
            class_norm = class_id / 15.0
        except ValueError:
            class_norm = 0.5

        for image_type in ("front", "top"):
            image_path = class_dir / f"{image_type}_{class_dir.name}.png"
            mask_path = class_dir / f"mask_{image_type}_{class_dir.name}.png"
            if not image_path.exists() or not mask_path.exists():
                continue

            img = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
            if img is None:
                continue

            mask_ratio = _load_mask_ratio(mask_path)

            # Blend direct mask ratio with class severity as a small prior.
            target_ratio = float(np.clip(mask_ratio * 0.85 + class_norm * 0.15, 0.0, 1.0))
            X.append(_extract_features(img))
            y.append(target_ratio)

            # Augmentations improve robustness for different lighting/camera styles.
            aug_specs = [
                (0.95, -8),
                (1.05, 8),
                (1.15, 0),
                (0.85, 0),
                (1.0, -14),
                (1.0, 14),
                (0.92, 4),
                (1.08, -4),
            ]
            for alpha, beta in aug_specs:
                aug = cv2.convertScaleAbs(img, alpha=alpha, beta=beta)
                X.append(_extract_features(aug))
                y.append(target_ratio)

    if not X:
        raise RuntimeError("No valid training samples found.")
    return np.vstack(X), np.array(y, dtype=np.float32)


def train(dataset_root: Path, output_path: Path, *, runs: int = 1) -> None:
    X, y = _collect_samples(dataset_root)
    maes: list[float] = []
    best_mae = 1e9
    best_model = None

    for r in range(max(1, runs)):
        rs = 42 + r * 11
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=rs
        )

        model = RandomForestRegressor(
            n_estimators=300,
            random_state=rs,
            n_jobs=-1,
            max_depth=12,
            min_samples_leaf=2,
        )
        model.fit(X_train, y_train)
        pred = model.predict(X_test)
        mae = float(mean_absolute_error(y_test, pred))
        maes.append(mae)
        if mae < best_mae:
            best_mae = mae
            best_model = model

    assert best_model is not None
    output_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({"model": best_model, "feature_dim": X.shape[1]}, output_path)

    print(f"Trained samples: {len(X)}")
    if runs > 1:
        import statistics
        spread = statistics.pstdev(maes) if len(maes) > 1 else 0.0
        print(f"Repeated train/val runs: {runs}; MAE mean {statistics.mean(maes):.4f} spread {spread:.4f}")
    print(f"Best validation MAE (bald ratio): {best_mae:.4f} (saved)")
    print(f"Saved model -> {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to dataset root (Male folder)")
    parser.add_argument("--output", default="models/bald_regressor.joblib", help="Output model path")
    parser.add_argument(
        "--runs",
        type=int,
        default=1,
        help="Repeat train/val with different splits; save the run with lowest MAE (default 1)",
    )
    args = parser.parse_args()

    train(Path(args.dataset), Path(args.output), runs=args.runs)


if __name__ == "__main__":
    main()

