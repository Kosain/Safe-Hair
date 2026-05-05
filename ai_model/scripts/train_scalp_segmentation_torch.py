"""
PyTorch U-Net for scalp bald segmentation (same dataset layout as train_scalp_segmentation_tf.py).

Use when TensorFlow is not available for your Python version (e.g. 3.14+).

  pip install torch
  python train_scalp_segmentation_torch.py --dataset "d:\\Safe\\Male" --epochs 35
  # writes models/scalp_segmentation_torch.pt and models/scalp_seg.onnx
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np

try:
    import torch
    import torch.nn as nn
except ImportError as e:
    raise SystemExit("Install PyTorch: pip install torch\n" + str(e)) from e

IMG_SIZE = 256


def _collect_pairs(dataset_root: Path) -> List[Tuple[Path, Path]]:
    pairs: List[Tuple[Path, Path]] = []
    for class_dir in sorted([p for p in dataset_root.iterdir() if p.is_dir()]):
        try:
            int(class_dir.name)
        except ValueError:
            continue
        cid = class_dir.name
        for view in ("front", "top"):
            img_path = class_dir / f"{view}_{cid}.png"
            mask_path = class_dir / f"mask_{view}_{cid}.png"
            if img_path.exists() and mask_path.exists():
                pairs.append((img_path, mask_path))
    return pairs


def _load_pair(img_path: Path, mask_path: Path) -> Tuple[np.ndarray, np.ndarray]:
    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR)
    m = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if img is None or m is None:
        raise ValueError(f"Unreadable {img_path} / {mask_path}")
    img = cv2.resize(img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_AREA)
    m = cv2.resize(m, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    y = (m.astype(np.float32) / 255.0)[..., None]
    y = np.clip(y, 0.0, 1.0)
    return rgb, y


class DoubleConv(nn.Module):
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, 3, padding=1),
            nn.ReLU(inplace=True),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


class UNetSmall(nn.Module):
    def __init__(self):
        super().__init__()
        self.c1 = DoubleConv(3, 32)
        self.p1 = nn.MaxPool2d(2)
        self.c2 = DoubleConv(32, 64)
        self.p2 = nn.MaxPool2d(2)
        self.b = DoubleConv(64, 128)
        self.up1 = nn.ConvTranspose2d(128, 64, 2, stride=2)
        self.c3 = DoubleConv(128, 64)
        self.up2 = nn.ConvTranspose2d(64, 32, 2, stride=2)
        self.c4 = DoubleConv(64, 32)
        self.out = nn.Conv2d(32, 1, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        c1 = self.c1(x)
        c2 = self.c2(self.p1(c1))
        b = self.b(self.p2(c2))
        x_ = self.up1(b)
        x_ = torch.cat([x_, c2], dim=1)
        x_ = self.c3(x_)
        x_ = self.up2(x_)
        x_ = torch.cat([x_, c1], dim=1)
        x_ = self.c4(x_)
        return torch.sigmoid(self.out(x_))


def _export_onnx(model: nn.Module, path: Path) -> None:
    model.eval()
    dummy = torch.randn(1, 3, IMG_SIZE, IMG_SIZE)
    path.parent.mkdir(parents=True, exist_ok=True)
    # dynamo=False: TorchScript exporter (avoids onnxscript on PyTorch 2.9+ default path).
    torch.onnx.export(
        model,
        dummy,
        str(path),
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=17,
        dynamo=False,
    )


def train_run(
    dataset_root: Path,
    out_pt: Path,
    out_onnx: Path,
    epochs: int,
    batch: int,
) -> None:
    pairs = _collect_pairs(dataset_root)
    if len(pairs) < 2:
        raise SystemExit(f"Need ≥2 image/mask pairs under {dataset_root}")

    rng = np.random.default_rng(42)
    idx = np.arange(len(pairs))
    rng.shuffle(idx)
    n_val = max(1, int(len(pairs) * 0.2))
    val_set = set(idx[:n_val].tolist())
    tr_idx = [i for i in range(len(pairs)) if i not in val_set]
    va_idx = sorted(val_set)

    X_tr = np.stack([_load_pair(*pairs[i])[0] for i in tr_idx])
    Y_tr = np.stack([_load_pair(*pairs[i])[1] for i in tr_idx])
    X_va = np.stack([_load_pair(*pairs[i])[0] for i in va_idx])
    Y_va = np.stack([_load_pair(*pairs[i])[1] for i in va_idx])

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = UNetSmall().to(device)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.BCELoss()

    best_val = 1e9
    best_state = None
    patience, bad = 8, 0

    def tensors(x: np.ndarray, y: np.ndarray) -> Tuple[torch.Tensor, torch.Tensor]:
        # NHWC -> NCHW
        xt = torch.from_numpy(np.transpose(x, (0, 3, 1, 2))).to(device)
        yt = torch.from_numpy(np.transpose(y, (0, 3, 1, 2))).to(device)
        return xt, yt

    n = len(X_tr)
    for ep in range(epochs):
        model.train()
        perm = rng.permutation(n)
        loss_acc = 0.0
        steps = 0
        for s in range(0, n, batch):
            sel = perm[s : s + batch]
            if len(sel) == 0:
                continue
            xb = X_tr[sel]
            yb = Y_tr[sel]
            xt, yt = tensors(xb, yb)
            opt.zero_grad()
            pred = model(xt)
            loss = loss_fn(pred, yt)
            loss.backward()
            opt.step()
            loss_acc += float(loss.item())
            steps += 1

        model.eval()
        with torch.no_grad():
            xv, yv = tensors(X_va, Y_va)
            vpred = model(xv)
            vloss = float(loss_fn(vpred, yv).item())

        if vloss < best_val - 1e-6:
            best_val = vloss
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
        print(
            f"epoch {ep+1}/{epochs} train_loss ~{loss_acc/max(steps,1):.4f} val_bce {vloss:.4f}",
            flush=True,
        )
        if bad >= patience:
            print("Early stop.", flush=True)
            break

    if best_state is not None:
        model.load_state_dict(best_state)
    out_pt.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"state_dict": model.state_dict(), "img_size": IMG_SIZE}, out_pt)
    print(f"Saved {out_pt}")
    try:
        _export_onnx(model.cpu(), out_onnx)
        print(f"Saved {out_onnx} (NCHW float32 input 'input')", flush=True)
    except Exception as ex:
        print(
            f"ONNX export failed ({ex}). Install `onnx` (pip install onnx) then run:\n"
            f"  python export_torch_checkpoint_to_onnx.py --pt {out_pt} --onnx {out_onnx}",
            flush=True,
        )


def main() -> None:
    p = argparse.ArgumentParser()
    here = Path(__file__).resolve().parent
    p.add_argument("--dataset", default=os.environ.get("SCALP_DATASET_MALE", r"d:\Safe\Male"), type=Path)
    p.add_argument("--out-pt", default=here / "models" / "scalp_segmentation_torch.pt", type=Path)
    p.add_argument("--onnx", default=here / "models" / "scalp_seg.onnx", type=Path)
    p.add_argument("--epochs", type=int, default=35)
    p.add_argument("--batch", type=int, default=4)
    args = p.parse_args()
    train_run(
        args.dataset.expanduser().resolve(),
        args.out_pt,
        args.onnx,
        args.epochs,
        args.batch,
    )


if __name__ == "__main__":
    main()
