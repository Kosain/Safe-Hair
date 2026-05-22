"""
Train all bundled AI assets for the scalp analyzer (one command).

1) RandomForest bald-ratio regressor -> models/bald_regressor.joblib
2) Multi-label scalp conditions (Alopecia, Dandruff, Fungal, Dry) -> models/scalp_conditions.joblib
3) U-Net segmentation + ONNX -> models/scalp_seg.onnx
   - Prefers TensorFlow if installed (Python 3.10–3.12 typical).
   - Otherwise uses PyTorch (e.g. Python 3.14).

Prereqs:
  pip install -r requirements.txt
  pip install -r requirements-ml.txt   # TensorFlow path, or
  pip install torch                  # PyTorch-only path

Usage:
  python train_all_ai_models.py --dataset "d:\\Safe\\Male"
  python train_all_ai_models.py --dataset "d:\\Safe\\Male" --epochs 35 --skip-seg

After training, restart the API. With default \"auto\" mode, models under backend/models/
are picked up automatically (see main.py).
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def _have_tensorflow() -> bool:
    try:
        import tensorflow as tf  # noqa: F401
        return True
    except Exception:
        return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", type=Path, default=Path(r"d:\Safe\Male"))
    ap.add_argument("--epochs", type=int, default=35)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--runs", type=int, default=3, help="RF repeated train/val splits")
    ap.add_argument("--skip-seg", action="store_true", help="Only train joblib regressor (no CNN/ONNX)")
    ap.add_argument("--skip-export", action="store_true", help="(TensorFlow only) skip tf2onnx step")
    args = ap.parse_args()

    here = Path(__file__).resolve().parent
    models = here / "models"
    models.mkdir(parents=True, exist_ok=True)
    sub_env = os.environ.copy()
    sub_env["PYTHONUNBUFFERED"] = "1"

    ds = args.dataset.expanduser().resolve()
    if not ds.is_dir():
        raise SystemExit(f"Dataset folder not found: {ds}")

    reg_out = models / "bald_regressor.joblib"
    print("=== (1/4) Training bald-ratio regressor ===")
    subprocess.run(
        [
            sys.executable,
            str(here / "train_bald_model.py"),
            "--dataset",
            str(ds),
            "--output",
            str(reg_out),
            "--runs",
            str(args.runs),
        ],
        check=True,
        cwd=str(here),
        env=sub_env,
    )

    cond_out = models / "scalp_conditions.joblib"
    print("=== (2/4) Training scalp condition classifier ===")
    subprocess.run(
        [
            sys.executable,
            str(here / "train_scalp_conditions.py"),
            "--dataset",
            str(ds),
            "--output",
            str(cond_out),
        ],
        check=True,
        cwd=str(here),
        env=sub_env,
    )

    if args.skip_seg:
        print("Skipping segmentation (--skip-seg).")
        return

    onnx_out = models / "scalp_seg.onnx"
    print("=== (3/4) Training scalp segmentation (U-Net) ===")
    if _have_tensorflow():
        keras_out = models / "scalp_segmentation.keras"
        subprocess.run(
            [
                sys.executable,
                str(here / "train_scalp_segmentation_tf.py"),
                "--dataset",
                str(ds),
                "--out",
                str(keras_out),
                "--epochs",
                str(args.epochs),
                "--batch",
                str(args.batch),
            ],
            check=True,
            cwd=str(here),
            env=sub_env,
        )
        if not args.skip_export:
            print("=== (4/4) Export ONNX (tf2onnx) ===")
            subprocess.run(
                [
                    sys.executable,
                    str(here / "export_scalp_seg_onnx.py"),
                    "--keras",
                    str(keras_out),
                    "--onnx",
                    str(onnx_out),
                ],
                check=True,
                cwd=str(here),
                env=sub_env,
            )
        else:
            print("Skipped ONNX export (--skip-export).")
    else:
        print("(TensorFlow not installed — using PyTorch trainer + native ONNX export)")
        subprocess.run(
            [
                sys.executable,
                str(here / "train_scalp_segmentation_torch.py"),
                "--dataset",
                str(ds),
                "--onnx",
                str(onnx_out),
                "--epochs",
                str(args.epochs),
                "--batch",
                str(args.batch),
            ],
            check=True,
            cwd=str(here),
            env=sub_env,
        )

    print("\nDone.")
    print(f"  Regressor:  {reg_out}")
    print(f"  ONNX seg:   {onnx_out}")
    print("Restart the backend; USE_CNN/USE_TRAINED_MODEL default to auto when these files exist.")


if __name__ == "__main__":
    main()
