"""Convert Keras scalp segmentation model to ONNX for onnxruntime (NCHW or NHWC per export)."""
from __future__ import annotations

import argparse
from pathlib import Path

try:
    import tf2onnx  # type: ignore
    import tensorflow as tf
except ImportError as e:
    raise SystemExit(f"Need tensorflow and tf2onnx: pip install -r requirements-ml.txt\n{e}") from e


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keras", required=True, type=Path, help=".keras model from train_scalp_segmentation_tf.py")
    ap.add_argument("--onnx", required=True, type=Path, help="Output .onnx path")
    args = ap.parse_args()

    model = tf.keras.models.load_model(args.keras)
    spec = (tf.TensorSpec((None, 256, 256, 3), tf.float32, name="input"),)
    args.onnx.parent.mkdir(parents=True, exist_ok=True)
    tf2onnx.convert.from_keras(model, input_signature=spec, opset=13, output_path=str(args.onnx))
    print(f"Wrote {args.onnx}")


if __name__ == "__main__":
    main()
