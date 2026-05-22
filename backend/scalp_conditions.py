"""Scalp condition labels, feature helpers, and runtime inference."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import joblib
import numpy as np

from train_bald_model import _extract_features

CONDITIONS = [
    "Alopecia",
    "Dandruff",
    "Fungal Infection",
    "Dry Scalp",
]

_MODEL_CACHE: Dict[str, Any] = {}


def flake_score(gray: np.ndarray) -> float:
    g = cv2.resize(gray, (256, 256), interpolation=cv2.INTER_AREA)
    bright = g > 175
    if float(np.mean(bright)) < 0.02:
        return 0.0
    lap = cv2.Laplacian(g, cv2.CV_64F)
    return float(np.var(lap[bright]))


def dry_score(img_bgr: np.ndarray) -> float:
    hsv = cv2.cvtColor(cv2.resize(img_bgr, (256, 256)), cv2.COLOR_BGR2HSV)
    s = hsv[:, :, 1].astype(np.float32)
    v = hsv[:, :, 2].astype(np.float32)
    return float(np.clip(1.0 - np.mean(s) / 90.0, 0, 1) * np.clip(np.mean(v) / 200.0, 0.3, 1))


def fungal_patch_score(mask: np.ndarray) -> float:
    m = (mask > 127).astype(np.uint8)
    if m.sum() < 50:
        return 0.0
    k = 32
    h, w = m.shape
    vals: List[float] = []
    for y in range(0, h - k, k):
        for x in range(0, w - k, k):
            vals.append(float(np.mean(m[y : y + k, x : x + k])))
    if len(vals) < 4:
        return 0.0
    return float(np.std(vals))


def weak_labels(
    *,
    class_id: int,
    mask_ratio: float,
    flake: float,
    dry: float,
    fungal_patch: float,
) -> np.ndarray:
    sev = float(np.clip(class_id / 15.0, 0, 1)) if class_id > 0 else 0.5
    alopecia = int(mask_ratio >= 0.12 or sev >= 0.55 or (mask_ratio >= 0.06 and sev >= 0.4))
    dandruff = int(flake >= 120.0 or (flake >= 60.0 and sev >= 0.25 and sev <= 0.75))
    dry_l = int(dry >= 0.45 or (sev <= 0.35 and mask_ratio < 0.08))
    fungal = int(
        fungal_patch >= 0.22
        and 0.2 <= sev <= 0.65
        and mask_ratio >= 0.04
        and mask_ratio < 0.25
    )
    if not any((alopecia, dandruff, fungal, dry_l)):
        dry_l = 1
    return np.array([alopecia, dandruff, fungal, dry_l], dtype=np.int32)


def load_condition_model(model_path: str | Path) -> Optional[Dict[str, Any]]:
    path = Path(model_path)
    key = str(path.resolve())
    if key in _MODEL_CACHE:
        return _MODEL_CACHE[key]
    if not path.is_file():
        return None
    try:
        bundle = joblib.load(path)
        _MODEL_CACHE[key] = bundle
        return bundle
    except Exception:
        return None


def predict_conditions(
    image_bgr: np.ndarray,
    *,
    model_path: str | Path,
    mask_gray: Optional[np.ndarray] = None,
    class_id_norm: float = 0.5,
    mask_ratio: float = 0.0,
    threshold: float = 0.5,
) -> Tuple[List[str], Dict[str, float]]:
    bundle = load_condition_model(model_path)
    if bundle is None:
        return [], {}

    model = bundle["model"]
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    flake = flake_score(gray)
    dry = dry_score(image_bgr)
    fungal_patch = fungal_patch_score(mask_gray) if mask_gray is not None else 0.0

    feat = _extract_features(image_bgr)
    extra = np.array([mask_ratio, flake, dry, fungal_patch, class_id_norm], dtype=np.float32)
    row = np.concatenate([feat, extra]).reshape(1, -1)

    names: List[str] = []
    probs: Dict[str, float] = {}
    estimators = getattr(model, "estimators_", [])
    for i, est in enumerate(estimators):
        label = CONDITIONS[i] if i < len(CONDITIONS) else f"class_{i}"
        p = 0.0
        if hasattr(est, "predict_proba"):
            proba = est.predict_proba(row)[0]
            p = float(proba[1]) if len(proba) >= 2 else float(proba[0])
        else:
            p = float(est.predict(row)[0])
        probs[label] = p
        if p >= threshold or int(est.predict(row)[0]) == 1:
            names.append(label)

    if not names and probs:
        best = max(probs, key=probs.get)
        if probs[best] >= 0.35:
            names.append(best)
    return names, probs
