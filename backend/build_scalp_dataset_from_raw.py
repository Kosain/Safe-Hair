"""
Turn a folder of scalp photos into the layout expected by train_bald_model.py.

Each image becomes:
  <output>/Male/<id>/top_<id>.png
  <output>/Male/<id>/mask_top_<id>.png

The mask is generated with the same OpenCV bald-segmentation logic as scalp_processor
(weak / pseudo labels). Replace with human or CNN masks for supervised training quality.

Usage:
  cd backend
  python build_scalp_dataset_from_raw.py --input datasets/scalp_topdown/raw --output datasets/scalp_topdown/structured/Male
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import cv2

from scalp_processor import _bald_area_mask_opencv, _preprocess

_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def _iter_images(folder: Path) -> list[Path]:
    out: list[Path] = []
    for p in sorted(folder.iterdir()):
        if p.is_file() and p.suffix.lower() in _EXTENSIONS:
            out.append(p)
    return out


def build(input_dir: Path, output_male_root: Path) -> int:
    """
    output_male_root should be the `Male` folder (parent of numeric class dirs).
    """
    images = _iter_images(input_dir)
    if not images:
        raise SystemExit(f"No images found in {input_dir} ({', '.join(sorted(_EXTENSIONS))})")

    out_root = output_male_root
    out_root.mkdir(parents=True, exist_ok=True)

    # Remove previous numeric subdirs only (safety: don't wipe unrelated files)
    for child in list(out_root.iterdir()):
        if child.is_dir() and child.name.isdigit():
            shutil.rmtree(child)

    n = 0
    for idx, src in enumerate(images, start=1):
        img = cv2.imread(str(src), cv2.IMREAD_COLOR)
        if img is None:
            print(f"skip (unreadable): {src.name}")
            continue
        h, w = img.shape[:2]
        if min(h, w) < 64:
            print(f"skip (too small): {src.name}")
            continue

        proc = _preprocess(img)
        mask_scalp, _ = _bald_area_mask_opencv(proc)

        sub = out_root / str(idx)
        sub.mkdir(parents=True, exist_ok=True)
        stem = str(idx)
        img_path = sub / f"top_{stem}.png"
        mask_path = sub / f"mask_top_{stem}.png"
        cv2.imwrite(str(img_path), proc)
        cv2.imwrite(str(mask_path), mask_scalp)
        print(f"OK {idx}: {src.name} -> {img_path.name} (folder {sub.name})")
        n += 1

    print(f"Done. Wrote {n} samples under {out_root}")
    return n


def main() -> None:
    p = argparse.ArgumentParser(description="Build Male/... dataset from raw scalp images")
    p.add_argument("--input", required=True, type=Path, help="Folder with .jpg/.png scalp photos")
    p.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Path to Male folder e.g. datasets/scalp_topdown/structured/Male",
    )
    args = p.parse_args()
    if not args.input.is_dir():
        raise SystemExit(f"Input is not a directory: {args.input}")
    build(args.input.expanduser().resolve(), args.output.expanduser().resolve())


if __name__ == "__main__":
    main()
