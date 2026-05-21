"""
Systematic offline evaluation for the FYP scalp pipeline.

Metrics (top / crown images with mask_top_*.png):
  - Binary Dice and IoU for bald, thin, and affected (bald ∪ thin) vs ground truth.
  - Pixel accuracy for affected vs non-affected (within full frame; same as train mask semantics).
  - Scalar bald-ratio error: |pred_affected_fraction - gt_affected_fraction|.

Orientation (optional, when both front and top exist):
  - Accuracy of predict_view_orientation vs filename-derived label (front vs top).

Splits:
  - Subject-level train/val/test by numeric folder id (default 70/15/15) with fixed seed.
  - Report aggregate metrics on the test split to avoid optimistic leakage from augmented siblings.

Usage (from repo root or backend folder):
  py evaluate_scalp_algorithm.py --dataset "path/to/Male" --cnn on --cohort-label Male
  py evaluate_scalp_algorithm.py --dataset "path/to/Female" --cnn off --cohort-label Female --out-dir evaluation_runs/run1
  py evaluate_scalp_algorithm.py --dataset "path/to/Male" --trained auto --skip-pipeline-scalars

Honesty note for the thesis: if masks are pseudo-labels (OpenCV-generated) or heavy
augmentation copies the same subject, scores are not clinical ground-truth accuracy;
they measure consistency with the chosen label generator and in-distribution fit.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import statistics
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np

from scalp_processor import (
    _bytes_to_image,
    _preprocess,
    analyze_scalp_with_opencv,
    eval_vertex_segmentation_masks,
    predict_view_orientation,
)


def _dice_iou(pred: np.ndarray, gt: np.ndarray, eps: float = 1e-7) -> Tuple[float, float]:
    """pred, gt: float32 or uint8 0/1 same shape. Returns (nan, nan) if both masks empty (undefined)."""
    p = (pred > 0.5).astype(np.float32).ravel()
    g = (gt > 0.5).astype(np.float32).ravel()
    inter = float(np.dot(p, g))
    s_p = float(np.sum(p))
    s_g = float(np.sum(g))
    if s_p < 1.0 and s_g < 1.0:
        return float("nan"), float("nan")
    union = s_p + s_g - inter + eps
    dice = (2.0 * inter + eps) / (s_p + s_g + eps)
    iou = (inter + eps) / union
    return dice, iou


def _pixel_acc_affected(pred_affected: np.ndarray, gt_affected: np.ndarray) -> float:
    p = pred_affected > 0.5
    g = gt_affected > 0.5
    return float(np.mean(p == g))


def _parse_gt_masks(gt_u8: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Ground-truth encoding from build_three_class_mask_png / dataset convention:
      ~0 hair, ~128 thin, ~255 bald. Pseudo-binary masks may be 0/255 only.
    """
    bald = (gt_u8 >= 200).astype(np.float32)
    thin = ((gt_u8 > 80) & (gt_u8 < 200)).astype(np.float32)
    # Any labeled scalp (thin or bald)
    affected = (gt_u8 > 127).astype(np.float32)
    return bald, thin, affected


def _encode_image_bytes(img_bgr: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".png", img_bgr)
    if not ok:
        raise RuntimeError("cv2.imencode failed")
    return buf.tobytes()


def _aligned_gt_mask(mask_path: Path, image_bytes: bytes) -> np.ndarray:
    proc = _preprocess(_bytes_to_image(image_bytes))
    h, w = proc.shape[:2]
    raw = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    if raw is None:
        raise ValueError(f"Unreadable mask: {mask_path}")
    if raw.shape[:2] != (h, w):
        raw = cv2.resize(raw, (w, h), interpolation=cv2.INTER_NEAREST)
    return raw


@dataclass
class SegRow:
    subject_id: int
    split: str
    dice_bald: float
    dice_thin: float
    dice_affected: float
    iou_bald: float
    iou_thin: float
    iou_affected: float
    pixel_acc_affected: float
    gt_affected_ratio: float
    pred_affected_ratio: float
    abs_ratio_err: float
    segmentation_method: str


@dataclass
class OriRow:
    subject_id: int
    split: str
    view_label: str
    predicted: str
    correct: bool
    path: str


def _collect_subjects(root: Path) -> List[int]:
    ids: List[int] = []
    for p in root.iterdir():
        if p.is_dir() and p.name.isdigit():
            sid = int(p.name)
            top_img = p / f"top_{sid}.png"
            top_mask = p / f"mask_top_{sid}.png"
            if top_img.is_file() and top_mask.is_file():
                ids.append(sid)
    return sorted(ids)


def _split_subjects(
    ids: Sequence[int],
    *,
    seed: int,
    train_frac: float,
    val_frac: float,
) -> Dict[int, str]:
    rng = np.random.default_rng(seed)
    shuffled = list(ids)
    rng.shuffle(shuffled)
    n = len(shuffled)
    n_train = int(round(train_frac * n))
    n_val = int(round(val_frac * n))
    n_train = max(1, min(n_train, n - 1))
    n_val = max(0, min(n_val, n - n_train - 1))
    n_test = n - n_train - n_val
    if n_test < 1:
        # Guarantee at least one test subject when possible
        if n_val > 0:
            n_val -= 1
        elif n_train > 1:
            n_train -= 1
        else:
            n_train, n_val, n_test = 1, 0, n - 1
        n_test = n - n_train - n_val
    out: Dict[int, str] = {}
    for sid in shuffled[:n_train]:
        out[sid] = "train"
    for sid in shuffled[n_train : n_train + n_val]:
        out[sid] = "val"
    for sid in shuffled[n_train + n_val :]:
        out[sid] = "test"
    return out


def _sanitize_json(obj: Any) -> Any:
    """Replace non-finite floats so summary.json is strict JSON."""
    if isinstance(obj, dict):
        return {k: _sanitize_json(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_sanitize_json(v) for v in obj]
    if isinstance(obj, float) and not (obj == obj and abs(obj) != float("inf")):
        return None
    return obj


def _summarize(values: Sequence[float]) -> Dict[str, float]:
    finite = [float(x) for x in values if x == x]  # drop nan
    if not finite:
        return {
            "mean": float("nan"),
            "median": float("nan"),
            "std": float("nan"),
            "min": float("nan"),
            "max": float("nan"),
            "n": 0.0,
            "n_omitted_nan": float(len(values)),
        }
    return {
        "mean": float(statistics.mean(finite)),
        "median": float(statistics.median(finite)),
        "std": float(statistics.pstdev(finite)) if len(finite) > 1 else 0.0,
        "min": float(min(finite)),
        "max": float(max(finite)),
        "n": float(len(finite)),
        "n_omitted_nan": float(len(values) - len(finite)),
    }


def _pearson_r(xs: Sequence[float], ys: Sequence[float]) -> Optional[float]:
    """Pearson r between equal-length sequences (finite pairs only). None if undefined."""
    pairs = [(float(a), float(b)) for a, b in zip(xs, ys) if a == a and b == b]
    if len(pairs) < 3:
        return None
    x = np.array([p[0] for p in pairs], dtype=np.float64)
    y = np.array([p[1] for p in pairs], dtype=np.float64)
    if float(np.std(x)) < 1e-12 or float(np.std(y)) < 1e-12:
        return None
    m = np.corrcoef(x, y)
    r = float(m[0, 1])
    return r if r == r else None


def _bootstrap_mean_ci(
    values: Sequence[float],
    *,
    seed: int,
    n_boot: int = 2000,
    alpha: float = 0.05,
) -> Dict[str, float]:
    """Percentile bootstrap CI for the mean (handles small n honestly)."""
    finite = np.array([float(x) for x in values if x == x], dtype=np.float64)
    if finite.size == 0:
        return {
            "mean": float("nan"),
            "ci95_low": float("nan"),
            "ci95_high": float("nan"),
            "n_boot": 0.0,
        }
    if finite.size == 1:
        m = float(finite[0])
        return {"mean": m, "ci95_low": m, "ci95_high": m, "n_boot": 0.0}
    rng = np.random.default_rng(seed)
    means = np.empty(n_boot, dtype=np.float64)
    for i in range(n_boot):
        sample = rng.choice(finite, size=finite.size, replace=True)
        means[i] = float(np.mean(sample))
    return {
        "mean": float(np.mean(finite)),
        "ci95_low": float(np.quantile(means, alpha / 2.0)),
        "ci95_high": float(np.quantile(means, 1.0 - alpha / 2.0)),
        "n_boot": float(n_boot),
    }


def _orientation_confusion(ori_rows: Sequence[OriRow]) -> Dict[str, Any]:
    """Counts: given view_label (GT from filename), how often predict_view_orientation agreed."""
    out: Dict[str, Any] = {
        "front_as_front": 0,
        "front_as_top": 0,
        "top_as_top": 0,
        "top_as_front": 0,
    }
    for r in ori_rows:
        if r.view_label == "front":
            if r.predicted == "front":
                out["front_as_front"] += 1
            else:
                out["front_as_top"] += 1
        elif r.view_label == "top":
            if r.predicted == "top":
                out["top_as_top"] += 1
            else:
                out["top_as_front"] += 1
    return out


def _segmentation_by_split(seg_rows: Sequence[SegRow], split: str) -> Dict[str, Any]:
    sub = [r for r in seg_rows if r.split == split]
    if not sub:
        return {"n": 0.0}
    return {
        "n": float(len(sub)),
        "dice_affected": _summarize([r.dice_affected for r in sub]),
        "iou_affected": _summarize([r.iou_affected for r in sub]),
        "pixel_acc_affected": _summarize([r.pixel_acc_affected for r in sub]),
        "abs_ratio_err": _summarize([r.abs_ratio_err for r in sub]),
    }


def run_full_pipeline_scalar_eval(
    root: Path,
    subject_split: Dict[int, str],
    splits_report: Sequence[str],
    *,
    use_cnn: bool,
    cnn_model_path: Optional[str],
    use_trained_model: bool,
    trained_model_path: Optional[str],
    patient_profile_gender: Optional[str],
) -> List[Dict[str, Any]]:
    """
    End-to-end analyze_scalp_with_opencv on each top image; compare bald_ratio to GT affected fraction.
    Does not claim clinical truth—sanity-check that scalar outputs move with mask-derived severity.
    """
    rows: List[Dict[str, Any]] = []
    for sid in sorted(subject_split.keys()):
        sp = subject_split[sid]
        if sp not in splits_report:
            continue
        d = root / str(sid)
        top_img = d / f"top_{sid}.png"
        top_mask = d / f"mask_top_{sid}.png"
        if not top_img.is_file() or not top_mask.is_file():
            continue
        img = cv2.imread(str(top_img), cv2.IMREAD_COLOR)
        if img is None:
            continue
        image_bytes = _encode_image_bytes(img)
        gt_raw = _aligned_gt_mask(top_mask, image_bytes)
        _, _, gt_aff = _parse_gt_masks(gt_raw)
        gt_affected_ratio = float(np.mean(gt_aff))

        try:
            out = analyze_scalp_with_opencv(
                image_bytes,
                use_cnn=use_cnn,
                cnn_model_path=cnn_model_path,
                use_trained_model=use_trained_model,
                trained_model_path=trained_model_path,
                patient_profile_gender=patient_profile_gender,
                patient_profile_age=None,
            )
        except Exception as e:
            rows.append(
                {
                    "subject_id": sid,
                    "split": sp,
                    "error": str(e),
                    "gt_affected_ratio": gt_affected_ratio,
                }
            )
            continue

        br = out.get("bald_ratio")
        try:
            br_f = float(br)
            if not (br_f == br_f):
                br_f = float("nan")
        except (TypeError, ValueError):
            br_f = float("nan")
        rows.append(
            {
                "subject_id": sid,
                "split": sp,
                "gt_affected_ratio": gt_affected_ratio,
                "pred_bald_ratio": br_f,
                "abs_bald_ratio_err": abs(br_f - gt_affected_ratio) if br_f == br_f else float("nan"),
                "hair_strength": out.get("hair_strength"),
                "hair_damage_level": out.get("hair_damage_level"),
                "hair_fall_risk": out.get("hair_fall_risk"),
                "view_orientation": out.get("view_orientation"),
            }
        )
    return rows


def run_segmentation_eval(
    root: Path,
    subject_split: Dict[int, str],
    splits_report: Sequence[str],
    *,
    use_cnn: bool,
    cnn_model_path: Optional[str],
) -> List[SegRow]:
    rows: List[SegRow] = []
    for sid in sorted(subject_split.keys()):
        sp = subject_split[sid]
        if sp not in splits_report:
            continue
        d = root / str(sid)
        top_img = d / f"top_{sid}.png"
        top_mask = d / f"mask_top_{sid}.png"
        img = cv2.imread(str(top_img), cv2.IMREAD_COLOR)
        if img is None:
            continue
        image_bytes = _encode_image_bytes(img)
        gt_raw = _aligned_gt_mask(top_mask, image_bytes)
        gt_bald, gt_thin, gt_aff = _parse_gt_masks(gt_raw)

        bald_p, thin_p, seg_m = eval_vertex_segmentation_masks(
            image_bytes, use_cnn=use_cnn, cnn_model_path=cnn_model_path
        )
        pb = (bald_p > 127).astype(np.float32)
        pt = (thin_p > 127).astype(np.float32)
        pa = np.clip(pb + pt, 0.0, 1.0)

        db, ib = _dice_iou(pb, gt_bald)
        dt, it = _dice_iou(pt, gt_thin)
        da, ia = _dice_iou(pa, gt_aff)
        pacc = _pixel_acc_affected(pa, gt_aff)
        gt_r = float(np.mean(gt_aff))
        pr_r = float(np.mean(pa))

        rows.append(
            SegRow(
                subject_id=sid,
                split=sp,
                dice_bald=db,
                dice_thin=dt,
                dice_affected=da,
                iou_bald=ib,
                iou_thin=it,
                iou_affected=ia,
                pixel_acc_affected=pacc,
                gt_affected_ratio=gt_r,
                pred_affected_ratio=pr_r,
                abs_ratio_err=abs(pr_r - gt_r),
                segmentation_method=seg_m,
            )
        )
    return rows


def run_orientation_eval(
    root: Path,
    subject_split: Dict[int, str],
    splits_report: Sequence[str],
) -> List[OriRow]:
    rows: List[OriRow] = []
    for sid in sorted(subject_split.keys()):
        sp = subject_split[sid]
        if sp not in splits_report:
            continue
        d = root / str(sid)
        for view_label, stem in (("front", f"front_{sid}.png"), ("top", f"top_{sid}.png")):
            p = d / stem
            if not p.is_file():
                continue
            img = cv2.imread(str(p), cv2.IMREAD_COLOR)
            if img is None:
                continue
            b = _encode_image_bytes(img)
            pred = predict_view_orientation(b)
            # Label from capture type; routing may still choose "top" for ambiguous fronts.
            correct = pred == view_label
            rows.append(
                OriRow(
                    subject_id=sid,
                    split=sp,
                    view_label=view_label,
                    predicted=pred,
                    correct=correct,
                    path=str(p),
                )
            )
    return rows


def main() -> None:
    here = Path(__file__).resolve().parent
    default_onnx = here / "models" / "scalp_seg.onnx"

    ap = argparse.ArgumentParser(description="Offline scalp pipeline evaluation (FYP metrics).")
    ap.add_argument("--dataset", type=Path, required=True, help="Structured root e.g. .../Male")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--train-frac", type=float, default=0.70)
    ap.add_argument("--val-frac", type=float, default=0.15)
    ap.add_argument(
        "--splits",
        type=str,
        default="test",
        help="Comma-separated splits to aggregate (e.g. test or val,test).",
    )
    ap.add_argument("--cnn", choices=("on", "off", "auto"), default="auto")
    ap.add_argument("--onnx", type=Path, default=default_onnx, help="ONNX path when --cnn on/auto")
    ap.add_argument("--out-dir", type=Path, default=None, help="Write JSON/CSV here (default: evaluation_runs/<timestamp>)")
    ap.add_argument("--skip-orientation", action="store_true", help="Do not run front/top routing accuracy")
    ap.add_argument(
        "--cohort-label",
        type=str,
        default=None,
        help="Optional cohort tag (e.g. Male / Female) stored in summary and passed to full-pipeline eval like the app profile.",
    )
    ap.add_argument("--trained", choices=("on", "off", "auto"), default="auto", help="Use bald_regressor.joblib blend when available.")
    ap.add_argument(
        "--trained-model",
        type=Path,
        default=None,
        help="Joblib regressor path (default: backend/models/bald_regressor.joblib).",
    )
    ap.add_argument(
        "--skip-pipeline-scalars",
        action="store_true",
        help="Skip end-to-end analyze_scalp_with_opencv sweep (faster; segmentation-only).",
    )
    args = ap.parse_args()

    trained_model_path = (args.trained_model or (here / "models" / "bald_regressor.joblib")).expanduser().resolve()
    use_trained = args.trained == "on" or (args.trained == "auto" and trained_model_path.is_file())
    trained_path_str = str(trained_model_path) if use_trained else None
    if args.trained == "on" and not trained_model_path.is_file():
        raise SystemExit(f"--trained on but model missing: {trained_model_path}")

    root = args.dataset.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Dataset folder not found: {root}")

    use_cnn = args.cnn == "on" or (args.cnn == "auto" and args.onnx.is_file())
    cnn_path = str(args.onnx) if use_cnn else None
    if args.cnn == "on" and not args.onnx.is_file():
        raise SystemExit(f"--cnn on but ONNX missing: {args.onnx}")

    subject_ids = _collect_subjects(root)
    if len(subject_ids) < 2:
        raise SystemExit(
            f"Need at least 2 subjects with top_<id>.png + mask_top_<id>.png under {root}. "
            "Found: " + str(len(subject_ids))
        )

    subject_split = _split_subjects(
        subject_ids, seed=args.seed, train_frac=args.train_frac, val_frac=args.val_frac
    )
    splits_report = tuple(s.strip() for s in args.splits.split(",") if s.strip())

    t0 = time.perf_counter()
    seg_rows = run_segmentation_eval(
        root, subject_split, splits_report, use_cnn=use_cnn, cnn_model_path=cnn_path
    )
    ori_rows: List[OriRow] = []
    if not args.skip_orientation:
        ori_rows = run_orientation_eval(root, subject_split, splits_report)

    pipeline_rows: List[Dict[str, Any]] = []
    if not args.skip_pipeline_scalars:
        cohort_gender = (args.cohort_label or "").strip() or None
        pipeline_rows = run_full_pipeline_scalar_eval(
            root,
            subject_split,
            splits_report,
            use_cnn=use_cnn,
            cnn_model_path=cnn_path,
            use_trained_model=use_trained,
            trained_model_path=trained_path_str,
            patient_profile_gender=cohort_gender,
        )

    summary: Dict[str, Any] = {
        "dataset": str(root),
        "cohort_label": (args.cohort_label or "").strip() or None,
        "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "seed": args.seed,
        "train_frac": args.train_frac,
        "val_frac": args.val_frac,
        "test_frac": round(1.0 - args.train_frac - args.val_frac, 4),
        "use_cnn": use_cnn,
        "cnn_model_path": cnn_path,
        "use_trained_model": use_trained,
        "trained_model_path": trained_path_str,
        "subjects_total": len(subject_ids),
        "subjects_per_split": {
            k: sum(1 for s in subject_split.values() if s == k) for k in ("train", "val", "test")
        },
        "splits_reported": list(splits_report),
        "segmentation": {},
        "orientation": {},
        "methodology_notes": [
            "Vertex branch is forced for mask comparison so top-view GT aligns with predictions.",
            "Dice/IoU depend on mask semantics (0/128/255 or 0/255 pseudo-labels).",
            "Subject-level split reduces leakage; augmented copies of the same ID still share leakage—prefer distinct subjects for external validation.",
            "Bootstrap CIs quantify sampling uncertainty for the *reported split mean*; they do not validate clinical ground truth.",
            "Full-pipeline rows compare API bald_ratio to mask-derived affected fraction as a sanity check, not a regulatory metric.",
            "When --cohort-label is set, the same string is passed as patient_profile_gender to mirror the app's declared profile context.",
        ],
    }

    if len(subject_ids) < 8:
        summary["methodology_notes"].append(
            f"Small cohort warning: only {len(subject_ids)} subjects — treat aggregate means as indicative, not definitive."
        )

    if seg_rows:
        da = [r.dice_affected for r in seg_rows]
        summary["segmentation"] = {
            "dice_bald": _summarize([r.dice_bald for r in seg_rows]),
            "dice_thin": _summarize([r.dice_thin for r in seg_rows]),
            "dice_affected": _summarize(da),
            "dice_affected_bootstrap_mean_ci95": _bootstrap_mean_ci(da, seed=args.seed + 11),
            "iou_bald": _summarize([r.iou_bald for r in seg_rows]),
            "iou_thin": _summarize([r.iou_thin for r in seg_rows]),
            "iou_affected": _summarize([r.iou_affected for r in seg_rows]),
            "pixel_acc_affected": _summarize([r.pixel_acc_affected for r in seg_rows]),
            "abs_ratio_err": _summarize([r.abs_ratio_err for r in seg_rows]),
            "gt_vs_pred_affected_fraction_pearson_r": _pearson_r(
                [r.gt_affected_ratio for r in seg_rows],
                [r.pred_affected_ratio for r in seg_rows],
            ),
            "by_split": {sp: _segmentation_by_split(seg_rows, sp) for sp in ("train", "val", "test")},
        }
    if ori_rows:
        acc = sum(1 for r in ori_rows if r.correct) / len(ori_rows)
        summary["orientation"] = {
            "accuracy": acc,
            "n_predictions": len(ori_rows),
            "by_label": {},
            "confusion_counts": _orientation_confusion(ori_rows),
        }
        for lab in ("front", "top"):
            sub = [r for r in ori_rows if r.view_label == lab]
            if sub:
                summary["orientation"]["by_label"][lab] = {
                    "accuracy": sum(1 for r in sub if r.correct) / len(sub),
                    "n": len(sub),
                }

    if pipeline_rows:
        ok = [r for r in pipeline_rows if "error" not in r]
        errs = [r for r in pipeline_rows if "error" in r]
        fp: Dict[str, Any] = {"n_ok": len(ok), "n_error": len(errs)}
        if ok:
            abs_errs: List[float] = []
            for r in ok:
                v = r.get("abs_bald_ratio_err")
                if v is not None:
                    try:
                        vf = float(v)
                        if vf == vf:
                            abs_errs.append(vf)
                    except (TypeError, ValueError):
                        pass
            fp["abs_bald_ratio_err"] = _summarize(abs_errs)
            fp["abs_bald_ratio_err_bootstrap_mean_ci95"] = _bootstrap_mean_ci(abs_errs, seed=args.seed + 3)
            xs: List[float] = []
            ys: List[float] = []
            for r in ok:
                try:
                    gt = float(r["gt_affected_ratio"])
                    pr = float(r["pred_bald_ratio"])
                    if pr == pr and gt == gt:
                        xs.append(gt)
                        ys.append(pr)
                except (TypeError, KeyError, ValueError):
                    pass
            fp["pearson_r_gt_affected_vs_pred_bald_ratio"] = _pearson_r(xs, ys)
        if errs:
            fp["errors_sample"] = errs[:5]
        summary["full_pipeline"] = fp
    elif args.skip_pipeline_scalars:
        summary["full_pipeline"] = {"skipped": True, "reason": "--skip-pipeline-scalars"}
    else:
        summary["full_pipeline"] = {"n_ok": 0, "n_error": 0, "note": "pipeline produced no rows"}

    summary["seconds"] = round(time.perf_counter() - t0, 3)

    out_dir = args.out_dir
    if out_dir is None:
        out_dir = here / "evaluation_runs" / time.strftime("eval_%Y%m%d_%H%M%S")
    out_dir = out_dir.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    with (out_dir / "summary.json").open("w", encoding="utf-8") as f:
        json.dump(_sanitize_json(summary), f, indent=2)

    with (out_dir / "segmentation_per_image.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(asdict(seg_rows[0]).keys()) if seg_rows else [])
        if seg_rows:
            w.writeheader()
            for r in seg_rows:
                w.writerow(asdict(r))

    with (out_dir / "orientation_per_image.csv").open("w", newline="", encoding="utf-8") as f:
        fields = list(asdict(ori_rows[0]).keys()) if ori_rows else ["subject_id", "split", "view_label", "predicted", "correct", "path"]
        w = csv.DictWriter(f, fieldnames=fields)
        if ori_rows:
            w.writeheader()
            for r in ori_rows:
                w.writerow(asdict(r))

    if pipeline_rows:
        keys = sorted({k for row in pipeline_rows for k in row.keys()})
        with (out_dir / "full_pipeline_per_subject.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            for row in pipeline_rows:
                w.writerow({k: row.get(k, "") for k in keys})

    print(json.dumps(_sanitize_json(summary), indent=2))
    print(f"\nWrote: {out_dir / 'summary.json'}")
    print(f"Wrote: {out_dir / 'segmentation_per_image.csv'} ({len(seg_rows)} rows)")
    print(f"Wrote: {out_dir / 'orientation_per_image.csv'} ({len(ori_rows)} rows)")
    if pipeline_rows:
        print(f"Wrote: {out_dir / 'full_pipeline_per_subject.csv'} ({len(pipeline_rows)} rows)")


if __name__ == "__main__":
    main()
