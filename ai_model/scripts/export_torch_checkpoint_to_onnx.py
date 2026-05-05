"""Export models/scalp_seg.onnx from models/scalp_segmentation_torch.pt (needs pip install onnx torch)."""
from __future__ import annotations

import argparse
from pathlib import Path

import torch

from train_scalp_segmentation_torch import UNetSmall, _export_onnx


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pt", type=Path, default=Path("models/scalp_segmentation_torch.pt"))
    ap.add_argument("--onnx", type=Path, default=Path("models/scalp_seg.onnx"))
    args = ap.parse_args()
    m = UNetSmall()
    try:
        d = torch.load(args.pt, map_location="cpu", weights_only=True)
    except TypeError:
        d = torch.load(args.pt, map_location="cpu")
    m.load_state_dict(d["state_dict"])
    m.eval()
    _export_onnx(m, args.onnx)


if __name__ == "__main__":
    main()
