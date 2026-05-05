"""
Turn a folder of scalp photos into the folder layout expected by train_bald_model.py.

Each image gets:
  - Preprocessed RGB crop (same pipeline as analysis)
  - A pseudo-label mask: OpenCV bald segmentation (white = bald, black = hair)

This is weak supervision suitable for bootstrapping the joblib regressor. For true CNN
segmentation, label masks manually or train a separate U-Net and export ONNX.

Usage:
  python prepare_scalp_dataset.py --raw dataset/raw_scalp --out dataset/prepared/Male
  python prepare_scalp_dataset.py --raw "D:\\Photos\\scalp_set" --out dataset/prepared/Male
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import cv2

from scalp_processor import _bald_area_mask_opencv, _preprocess, build_three_class_mask_png

_IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def _iter_images(folder: Path):
    for p in sorted(folder.iterdir()):
        if p.is_file() and p.suffix.lower() in _IMAGE_EXT:
            yield p


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare scalp dataset from loose images")
    parser.add_argument("--raw", required=True, type=Path, help="Folder containing scalp photos")
    parser.add_argument("--out", required=True, type=Path, help="Output root, e.g. dataset/prepared/Male")
    parser.add_argument("--start-index", type=int, default=1, help="First numeric folder id (default 1)")
    parser.add_argument("--skip-existing", action="store_true", help="Skip output dirs that already exist")
    parser.add_argument(
        "--three-class-masks",
        action="store_true",
        help="Masks: 0=hair, 128=thin, 255=bald (better for retraining bald vs thin)",
    )
    args = parser.parse_args()

    raw: Path = args.raw
    out_root: Path = args.out
    if not raw.is_dir():
        raise SystemExit(f"Not a folder: {raw}")

    images = list(_iter_images(raw))
    if not images:
        raise SystemExit(f"No images found in {raw} (supported: {sorted(_IMAGE_EXT)})")

    out_root.mkdir(parents=True, exist_ok=True)
    idx = args.start_index
    ok = 0
    for src in images:
        sub = out_root / str(idx)
        if args.skip_existing and sub.is_dir() and any(sub.iterdir()):
            idx += 1
            continue
        sub.mkdir(parents=True, exist_ok=True)

        img = cv2.imread(str(src), cv2.IMREAD_COLOR)
        if img is None:
            print(f"skip (unreadable): {src.name}")
            idx += 1
            continue

        proc = _preprocess(img)
        if args.three_class_masks:
            mask_bald = build_three_class_mask_png(proc)
        else:
            mask_bald, _ = _bald_area_mask_opencv(proc)

        stem_top = f"top_{idx}"
        stem_front = f"front_{idx}"
        cv2.imwrite(str(sub / f"{stem_top}.png"), proc)
        cv2.imwrite(str(sub / f"mask_{stem_top}.png"), mask_bald)
        cv2.imwrite(str(sub / f"{stem_front}.png"), proc)
        cv2.imwrite(str(sub / f"mask_{stem_front}.png"), mask_bald)

        shutil.copy2(src, sub / f"_source{src.suffix.lower()}")
        ok += 1
        print(f"{idx}: {src.name} -> {sub}")
        idx += 1

    print(f"Done. Wrote {ok} subjects under {out_root}. Run train_bald_model.py --dataset {out_root}")


if __name__ == "__main__":
    main()
