"""
Train multi-label scalp condition classifier (Alopecia, Dandruff, Fungal Infection, Dry Scalp).

Labels are **weak / pseudo** from mask severity + image texture (same dataset as bald regressor).
For clinical claims, replace with dermatologist-labelled CSV and retrain.

Usage:
  py train_scalp_conditions.py --dataset datasets/scalp_topdown/structured/Male
  py train_scalp_conditions.py --dataset datasets/scalp_topdown/structured/Male --output models/scalp_conditions.joblib
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

import cv2
import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split
from sklearn.multioutput import MultiOutputClassifier

from scalp_conditions import CONDITIONS, dry_score, flake_score, fungal_patch_score, weak_labels
from train_bald_model import _extract_features, _load_mask_ratio


def _collect_samples(dataset_root: Path) -> Tuple[np.ndarray, np.ndarray]:
    X: List[np.ndarray] = []
    Y: List[np.ndarray] = []

    for class_dir in sorted([p for p in dataset_root.iterdir() if p.is_dir()]):
        try:
            class_id = int(class_dir.name)
        except ValueError:
            class_id = 0

        for image_type in ("front", "top"):
            image_path = class_dir / f"{image_type}_{class_dir.name}.png"
            mask_path = class_dir / f"mask_{image_type}_{class_dir.name}.png"
            if not image_path.exists() or not mask_path.exists():
                continue
            img = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
            if img is None:
                continue
            mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
            if mask is None:
                continue
            mask_ratio = _load_mask_ratio(mask_path)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            flake = flake_score(gray)
            dry = dry_score(img)
            fungal_patch = fungal_patch_score(mask)

            feat = _extract_features(img)
            extra = np.array([mask_ratio, flake, dry, fungal_patch, class_id / 15.0], dtype=np.float32)
            labels = weak_labels(
                class_id=class_id,
                mask_ratio=mask_ratio,
                flake=flake,
                dry=dry,
                fungal_patch=fungal_patch,
            )
            X.append(np.concatenate([feat, extra]))
            Y.append(labels)

            for alpha, beta in [(0.95, -8), (1.05, 8), (1.0, 12)]:
                aug = cv2.convertScaleAbs(img, alpha=alpha, beta=beta)
                X.append(
                    np.concatenate(
                        [_extract_features(aug), np.array([mask_ratio, flake, dry, fungal_patch, class_id / 15.0], dtype=np.float32)]
                    )
                )
                Y.append(labels.copy())

    if not X:
        raise RuntimeError(f"No samples under {dataset_root}")
    return np.vstack(X), np.vstack(Y)


def _metrics_table(y_true: np.ndarray, y_pred: np.ndarray) -> Dict[str, object]:
    per_class = {}
    for i, name in enumerate(CONDITIONS):
        per_class[name] = {
            "precision": float(precision_score(y_true[:, i], y_pred[:, i], zero_division=0)),
            "recall": float(recall_score(y_true[:, i], y_pred[:, i], zero_division=0)),
            "f1_score": float(f1_score(y_true[:, i], y_pred[:, i], zero_division=0)),
            "support": int(y_true[:, i].sum()),
        }
    subset_acc = float(accuracy_score(y_true, y_pred))
    macro_f1 = float(f1_score(y_true, y_pred, average="macro", zero_division=0))
    return {
        "per_class": per_class,
        "subset_accuracy": subset_acc,
        "macro_f1": macro_f1,
        "overall_accuracy": subset_acc,
    }


def train(dataset_root: Path, output_path: Path, *, test_size: float = 0.2, seed: int = 42) -> Dict[str, object]:
    X, Y = _collect_samples(dataset_root)
    try:
        X_train, X_test, y_train, y_test = train_test_split(
            X, Y, test_size=test_size, random_state=seed, stratify=Y[:, 0]
        )
    except ValueError:
        X_train, X_test, y_train, y_test = train_test_split(X, Y, test_size=test_size, random_state=seed)

    base = RandomForestClassifier(
        n_estimators=400,
        max_depth=14,
        min_samples_leaf=2,
        class_weight="balanced",
        random_state=seed,
        n_jobs=-1,
    )
    model = MultiOutputClassifier(base)
    model.fit(X_train, y_train)
    y_pred = model.predict(X_test)

    metrics = _metrics_table(y_test, y_pred)
    report = classification_report(
        y_test,
        y_pred,
        target_names=CONDITIONS,
        zero_division=0,
    )

    bundle = {
        "model": model,
        "conditions": CONDITIONS,
        "feature_dim": int(X.shape[1]),
        "metrics": metrics,
        "label_type": "weak_pseudo_multi_label",
        "dataset": str(dataset_root.resolve()),
        "n_samples": int(len(X)),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, output_path)

    metrics_path = output_path.with_suffix(".metrics.json")
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(f"Samples: {len(X)}  |  Test rows: {len(y_test)}")
    print(f"Saved -> {output_path}")
    print(f"Metrics -> {metrics_path}")
    print("\n--- Classification report (multi-label) ---")
    print(report)
    print("\n--- FYP table ---")
    print(f"{'Scalp Condition':<22} {'Precision':>10} {'Recall':>10} {'F1-Score':>10}")
    for name in CONDITIONS:
        m = metrics["per_class"][name]
        print(f"{name:<22} {m['precision']:>10.3f} {m['recall']:>10.3f} {m['f1_score']:>10.3f}")
    print(f"\nOverall Accuracy (subset): {metrics['overall_accuracy']:.3f}")
    print(f"Macro F1: {metrics['macro_f1']:.3f}")
    return metrics


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--dataset",
        default="datasets/scalp_topdown/structured/Male",
        help="Structured Male/ folder with front_/top_ images and masks",
    )
    ap.add_argument("--output", default="models/scalp_conditions.joblib")
    ap.add_argument("--test-size", type=float, default=0.2)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    here = Path(__file__).resolve().parent
    root = Path(args.dataset)
    if not root.is_absolute():
        root = (here / root).resolve()
    out = Path(args.output)
    if not out.is_absolute():
        out = (here / out).resolve()
    train(root, out, test_size=args.test_size, seed=args.seed)


if __name__ == "__main__":
    main()
