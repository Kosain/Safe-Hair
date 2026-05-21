"""
Create a larger synthetic dataset from a structured scalp dataset.

Input expected layout (same as train_bald_model.py):
  <input_root>/<id>/front_<id>.png
  <input_root>/<id>/top_<id>.png
  <input_root>/<id>/mask_front_<id>.png
  <input_root>/<id>/mask_top_<id>.png

Output layout:
  <output_root>/<new_id>/front_<new_id>.png
  <output_root>/<new_id>/top_<new_id>.png
  <output_root>/<new_id>/mask_front_<new_id>.png
  <output_root>/<new_id>/mask_top_<new_id>.png

This preserves image-mask pairing by applying the exact same geometric transform.
"""
from __future__ import annotations

import argparse
import random
import shutil
from pathlib import Path
from typing import Optional, Tuple

import cv2
import numpy as np


def _read_pair(img_path: Path, mask_path: Path) -> Optional[Tuple[np.ndarray, np.ndarray]]:
    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR)
    mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if img is None or mask is None:
        return None
    if img.shape[:2] != mask.shape[:2]:
        mask = cv2.resize(mask, (img.shape[1], img.shape[0]), interpolation=cv2.INTER_NEAREST)
    return img, mask


def _affine_same(img: np.ndarray, mask: np.ndarray, rng: random.Random) -> Tuple[np.ndarray, np.ndarray]:
    h, w = img.shape[:2]
    angle = rng.uniform(-14.0, 14.0)
    scale = rng.uniform(0.90, 1.10)
    tx = rng.uniform(-0.06, 0.06) * w
    ty = rng.uniform(-0.06, 0.06) * h
    m = cv2.getRotationMatrix2D((w / 2.0, h / 2.0), angle, scale)
    m[0, 2] += tx
    m[1, 2] += ty
    img_t = cv2.warpAffine(img, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT_101)
    mask_t = cv2.warpAffine(mask, m, (w, h), flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_REFLECT_101)
    return img_t, mask_t


def _color_only(img: np.ndarray, rng: random.Random) -> np.ndarray:
    out = img.copy()
    alpha = rng.uniform(0.82, 1.20)  # contrast
    beta = rng.uniform(-24, 24)      # brightness
    out = cv2.convertScaleAbs(out, alpha=alpha, beta=beta)

    # HSV jitter
    hsv = cv2.cvtColor(out, cv2.COLOR_BGR2HSV).astype(np.int16)
    hsv[..., 0] = np.clip(hsv[..., 0] + rng.randint(-7, 7), 0, 179)
    hsv[..., 1] = np.clip(hsv[..., 1] + rng.randint(-20, 20), 0, 255)
    hsv[..., 2] = np.clip(hsv[..., 2] + rng.randint(-18, 18), 0, 255)
    out = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)

    # Optional blur/noise
    if rng.random() < 0.40:
        k = rng.choice([3, 5])
        out = cv2.GaussianBlur(out, (k, k), 0)
    if rng.random() < 0.35:
        n = np.random.normal(0, rng.uniform(2, 9), out.shape).astype(np.float32)
        out = np.clip(out.astype(np.float32) + n, 0, 255).astype(np.uint8)
    return out


def _collect_subject_ids(root: Path) -> list[int]:
    ids: list[int] = []
    for p in root.iterdir():
        if p.is_dir() and p.name.isdigit():
            ids.append(int(p.name))
    return sorted(ids)


def _load_subject(root: Path, sid: int) -> Optional[dict]:
    d = root / str(sid)
    f = _read_pair(d / f"front_{sid}.png", d / f"mask_front_{sid}.png")
    t = _read_pair(d / f"top_{sid}.png", d / f"mask_top_{sid}.png")
    if f is None or t is None:
        return None
    return {"front": f, "top": t}


def _save_subject(out_root: Path, sid: int, data: dict) -> None:
    d = out_root / str(sid)
    d.mkdir(parents=True, exist_ok=True)
    (front_img, front_mask) = data["front"]
    (top_img, top_mask) = data["top"]
    cv2.imwrite(str(d / f"front_{sid}.png"), front_img)
    cv2.imwrite(str(d / f"mask_front_{sid}.png"), front_mask)
    cv2.imwrite(str(d / f"top_{sid}.png"), top_img)
    cv2.imwrite(str(d / f"mask_top_{sid}.png"), top_mask)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path, help="Structured source root (Male)")
    ap.add_argument("--output", required=True, type=Path, help="Structured output root (Male)")
    ap.add_argument("--target-subjects", type=int, default=500, help="Total subjects after augmentation")
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--clean-output", action="store_true", help="Delete numeric dirs in output before writing")
    args = ap.parse_args()

    in_root = args.input.expanduser().resolve()
    out_root = args.output.expanduser().resolve()
    if not in_root.is_dir():
        raise SystemExit(f"Input folder missing: {in_root}")
    out_root.mkdir(parents=True, exist_ok=True)

    if args.clean_output:
        for ch in list(out_root.iterdir()):
            if ch.is_dir() and ch.name.isdigit():
                shutil.rmtree(ch)

    src_ids = _collect_subject_ids(in_root)
    if not src_ids:
        raise SystemExit(f"No numeric subject folders found in {in_root}")

    loaded = []
    for sid in src_ids:
        item = _load_subject(in_root, sid)
        if item is not None:
            loaded.append((sid, item))
    if not loaded:
        raise SystemExit("No valid front/top + mask pairs found in input root.")

    rng = random.Random(args.seed)

    # Keep originals first (reindexed).
    out_idx = 1
    for _, item in loaded:
        _save_subject(out_root, out_idx, item)
        out_idx += 1

    while out_idx <= args.target_subjects:
        _, base = rng.choice(loaded)
        out_item = {}
        for view in ("front", "top"):
            img, mask = base[view]
            img_t, mask_t = _affine_same(img, mask, rng)
            img_t = _color_only(img_t, rng)
            # Keep masks crisp and valid class values.
            mask_t = cv2.medianBlur(mask_t, 3)
            out_item[view] = (img_t, mask_t)
        _save_subject(out_root, out_idx, out_item)
        out_idx += 1

    print(f"Created structured augmented dataset: {out_root}")
    print(f"Subjects written: {args.target_subjects}")


if __name__ == "__main__":
    main()
