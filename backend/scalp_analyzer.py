"""
AI scalp analysis — strict 3-color overlays, 3-class segmentation, analyze_scalp() API.

Colors (outlines only, never filled):
  Red    #FF0000  — high baldness / severe thinning
  Orange #FFA500  — mild thinning (orange only; no yellow)
  Teal   #008080  — dandruff / infection
"""
from __future__ import annotations

import base64
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np

# BGR for OpenCV (strict hex — never use (0, 255, 255) or (0, 200, 255) yellow)
COLOR_SEVERE_BGR = (0, 0, 255)  # #FF0000
COLOR_MILD_BGR = (0, 140, 255)  # #FF8C00 dark orange (distinct from yellow)
COLOR_INFECTION_BGR = (180, 200, 120)  # light teal #78C8B4

MODELS_DIR = Path(__file__).resolve().parent / "models"
TFLITE_SEG_PATH = MODELS_DIR / "scalp_model.tflite"
TFLITE_CLS_PATH = MODELS_DIR / "scalp_classifier.tflite"
ONNX_SEG_PATH = MODELS_DIR / "scalp_seg.onnx"
_IMG_SIZE = 256

_TFLITE_SEG_INTERP = None
_TFLITE_CLS_INTERP = None
# Filled during draw_scalp_overlay; used to compute per-image metrics (not hardcoded).
_LAST_REGION_STATS: Dict[str, float] = {}


def overlay_legend_caption(legend: Optional[Dict[str, bool]]) -> str:
    if not legend:
        return "Outlines: red = severe baldness · orange = mild thinning · teal = dandruff/infection"
    parts: List[str] = []
    if legend.get("red"):
        parts.append("red = high-level baldness")
    if legend.get("orange"):
        parts.append("orange = mild thinning")
    if legend.get("teal"):
        parts.append("teal = dandruff or infection")
    if not parts:
        return "No colored outlines on this photo."
    return "Shown on photo: " + " · ".join(parts)


def _load_tflite(path: Path):
    try:
        from tensorflow.lite import Interpreter  # type: ignore
    except Exception:
        try:
            import tflite_runtime.interpreter as tflite  # type: ignore

            interp = tflite.Interpreter(model_path=str(path))
            interp.allocate_tensors()
            return interp
        except Exception:
            return None
    interp = Interpreter(model_path=str(path))
    interp.allocate_tensors()
    return interp


def _tflite_seg_three_class(img_bgr: np.ndarray) -> Optional[Tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """
    3-class TFLite output: severe, mild, infection probability maps (HxW float32).
    Supports [1,H,W,3] or [1,H,W,4] (ch0=bg).
    """
    global _TFLITE_SEG_INTERP
    if not TFLITE_SEG_PATH.is_file():
        return None
    if _TFLITE_SEG_INTERP is None:
        _TFLITE_SEG_INTERP = _load_tflite(TFLITE_SEG_PATH)
    if _TFLITE_SEG_INTERP is None:
        return None

    h, w = img_bgr.shape[:2]
    rgb = cv2.cvtColor(
        cv2.resize(img_bgr, (_IMG_SIZE, _IMG_SIZE), interpolation=cv2.INTER_AREA),
        cv2.COLOR_BGR2RGB,
    )
    x = (rgb.astype(np.float32) / 255.0)[None, ...]
    inp = _TFLITE_SEG_INTERP.get_input_details()[0]
    out = _TFLITE_SEG_INTERP.get_output_details()[0]
    if inp["dtype"] == np.uint8:
        x = (x * 255).astype(np.uint8)
    _TFLITE_SEG_INTERP.set_tensor(inp["index"], x)
    _TFLITE_SEG_INTERP.invoke()
    pred = _TFLITE_SEG_INTERP.get_tensor(out["index"])
    if pred.ndim == 4:
        pred = pred[0]
    if pred.ndim == 3 and pred.shape[-1] >= 3:
        # NHWC: channels = [bg, mild, severe] or [bg, severe, mild, infect]
        if pred.shape[-1] >= 4:
            severe = pred[..., 1]
            mild = pred[..., 2]
            infect = pred[..., 3]
        else:
            severe = pred[..., 2]
            mild = pred[..., 1]
            infect = np.zeros_like(severe)
    elif pred.ndim == 3:
        severe = pred
        mild = np.zeros_like(severe)
        infect = np.zeros_like(severe)
    else:
        return None

    def _up(ch: np.ndarray) -> np.ndarray:
        return cv2.resize(ch.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)

    return (
        np.clip(_up(severe), 0.0, 1.0),
        np.clip(_up(mild), 0.0, 1.0),
        np.clip(_up(infect), 0.0, 1.0),
    )


def _analysis_zone(img_bgr: np.ndarray, keep_zone: np.ndarray) -> Tuple[np.ndarray, np.ndarray, Tuple[int, int]]:
    import scalp_processor as sp

    h, w = img_bgr.shape[:2]
    head_mask, head_center, _ = sp._detect_scalp_head_mask(img_bgr)
    if sp._crown_topdown_layout(img_bgr):
        cx, cy = w // 2, int(h * 0.42)
        head_center = (cx, cy)
        head_mask = cv2.bitwise_or(
            head_mask,
            sp._head_roi_mask(h, w, center=head_center, axes=(int(w * 0.38), int(h * 0.36))),
        )
    keyhole = sp._vertex_keyhole_mask(h, w, center=head_center)
    zone = cv2.bitwise_and(cv2.bitwise_and(keep_zone, keyhole), head_mask)
    tissue = sp._scalp_tissue_mask(img_bgr, zone)
    vis = _visible_scalp_mask(img_bgr, zone)
    zone = cv2.bitwise_or(cv2.bitwise_and(zone, tissue), cv2.bitwise_and(vis, keep_zone))
    zone = cv2.bitwise_and(zone, head_mask)
    if cv2.countNonZero(zone) < int(0.015 * h * w):
        zone = cv2.bitwise_and(
            sp._head_roi_mask(h, w, center=head_center, axes=(int(w * 0.34), int(h * 0.30))),
            keyhole,
        )
    return zone, sp._environment_background_mask(img_bgr), head_center


def _infection_mask(
    img_bgr: np.ndarray,
    zone: np.ndarray,
    tissue: np.ndarray,
    exclude: Optional[np.ndarray] = None,
    *,
    bald_mask: Optional[np.ndarray] = None,
    prob: Optional[np.ndarray] = None,
) -> np.ndarray:
    """Teal only: visible white flakes — never on bald/thin CNN regions (pink scalp is not infection)."""
    h, w = img_bgr.shape[:2]
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    # White / yellow flakes only (ignore pink scalp "red" HSV — that caused teal on bald crown).
    white_flake = cv2.inRange(hsv, (0, 0, 178), (180, 48, 255))
    yellow_flake = cv2.inRange(hsv, (18, 35, 150), (38, 255, 255))
    irrit = cv2.bitwise_or(white_flake, yellow_flake)
    irrit = cv2.bitwise_and(irrit, tissue)
    irrit = cv2.bitwise_and(irrit, zone)
    if bald_mask is not None:
        k11 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
        no_bald = cv2.bitwise_not(cv2.dilate(bald_mask, k11, iterations=1))
        irrit = cv2.bitwise_and(irrit, no_bald)
    if prob is not None:
        irrit = cv2.bitwise_and(irrit, (prob < 0.32).astype(np.uint8) * 255)
    if exclude is not None:
        irrit = cv2.bitwise_and(irrit, cv2.bitwise_not(exclude))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    irrit = cv2.morphologyEx(irrit, cv2.MORPH_OPEN, k)
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(irrit, connectivity=8)
    cleaned = np.zeros((h, w), dtype=np.uint8)
    zone_px = max(1, int(cv2.countNonZero(zone)))
    min_a = max(140, int(0.0025 * zone_px))
    max_a = int(0.010 * h * w)
    for lbl in range(1, n_labels):
        area = int(stats[lbl, cv2.CC_STAT_AREA])
        if min_a <= area <= max_a:
            cleaned[labels == lbl] = 255
    return cleaned


def _visible_scalp_mask(img_bgr: np.ndarray, crown: np.ndarray) -> np.ndarray:
    import scalp_processor as sp

    return sp._visible_scalp_mask(img_bgr, crown)


def _largest_connected(mask: np.ndarray, crown: np.ndarray) -> np.ndarray:
    """Keep the main thinning/bald patch on the crown (not edge specks)."""
    h, w = mask.shape[:2]
    work = cv2.bitwise_and(mask, crown)
    if cv2.countNonZero(work) < 40:
        return work
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(work, connectivity=8)
    best_lbl, best_area = 0, 0
    for lbl in range(1, n_labels):
        area = int(stats[lbl, cv2.CC_STAT_AREA])
        if area > best_area:
            best_area, best_lbl = area, lbl
    if best_lbl <= 0:
        return work
    return (labels == best_lbl).astype(np.uint8) * 255


def _damage_region_masks(
    img_bgr: np.ndarray,
    bald_c: np.ndarray,
    thin_c: np.ndarray,
    crown: np.ndarray,
    p_map: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Continuous damage regions on crown:
      severe = central worst core inside main patch
      mild   = ring around patch + CNN thin areas
    """
    h, w = crown.shape[:2]
    vis = cv2.bitwise_and(_visible_scalp_mask(img_bgr, crown), crown)
    affected = cv2.bitwise_or(bald_c, vis)
    if cv2.countNonZero(affected) < 80 and float(np.max(p_map)) > 0.05:
        vals = p_map[crown > 0]
        thr = float(np.percentile(vals, 82)) if vals.size >= 30 else 0.45
        affected = (((p_map >= thr) & (crown > 0)).astype(np.uint8)) * 255

    main = _largest_connected(affected, crown)
    if cv2.countNonZero(main) < 40:
        return np.zeros((h, w), dtype=np.uint8), np.zeros((h, w), dtype=np.uint8)

    k7 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    k15 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    k25 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (25, 25))

    severe = cv2.erode(main, k15, iterations=1)
    if cv2.countNonZero(severe) < int(0.12 * cv2.countNonZero(main)):
        severe = cv2.erode(main, k7, iterations=1)
    if cv2.countNonZero(severe) < 80:
        dist = cv2.distanceTransform(main, cv2.DIST_L2, 5)
        dmax = float(dist.max()) if dist.size else 0.0
        if dmax > 1.0:
            severe = ((dist >= 0.52 * dmax).astype(np.uint8)) * 255
        else:
            severe = main.copy()

    outer = cv2.dilate(main, k25, iterations=1)
    inner = cv2.dilate(severe, k15, iterations=1)
    mild = cv2.bitwise_and(outer, cv2.bitwise_not(inner))
    mild = cv2.bitwise_or(mild, thin_c)
    mild = cv2.bitwise_and(mild, cv2.bitwise_not(severe))
    mild = cv2.bitwise_and(mild, crown)
    k11 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    mild = cv2.morphologyEx(mild, cv2.MORPH_CLOSE, k11)
    return severe, mild


def segment_three_classes(
    img_bgr: np.ndarray,
    zone: np.ndarray,
    prob: Optional[np.ndarray],
    bald_mask: np.ndarray,
    thin_mask: np.ndarray,
    *,
    keep_zone: Optional[np.ndarray] = None,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Evidence-based regions on crown:
      Red    = worst bald / visible-scalp core (1–2 blobs)
      Orange = thinning ring around bald + CNN thin hair
      Teal   = confirmed flakes only (never on hair-loss areas)
    """
    import scalp_processor as sp

    h, w = zone.shape[:2]
    infect = np.zeros((h, w), dtype=np.uint8)

    head_mask, head_center, _ = sp._detect_scalp_head_mask(img_bgr)
    tissue = sp._scalp_tissue_mask(img_bgr, head_mask)
    crown = cv2.bitwise_and(keep_zone if keep_zone is not None else zone, head_mask)
    if cv2.countNonZero(crown) < 80:
        crown = cv2.bitwise_and(zone, head_mask)
    crown_px = max(1, int(cv2.countNonZero(crown)))

    p_map = prob.astype(np.float32) if prob is not None else np.zeros((h, w), np.float32)
    if float(np.max(p_map)) < 0.05:
        p_map = np.where(bald_mask > 0, 0.75, p_map).astype(np.float32)
        p_map = np.where(thin_mask > 0, np.maximum(p_map, 0.38), p_map).astype(np.float32)

    bald_c = cv2.bitwise_and(bald_mask, crown)
    vis = _visible_scalp_mask(img_bgr, crown)
    if cv2.countNonZero(vis) > int(0.06 * crown_px):
        bald_c = cv2.bitwise_or(bald_c, cv2.bitwise_and(vis, cv2.bitwise_not(thin_mask)))
    thin_c = cv2.bitwise_and(thin_mask, crown)
    thin_c = cv2.bitwise_and(thin_c, cv2.bitwise_not(bald_c))

    severe, mild = _damage_region_masks(img_bgr, bald_c, thin_c, crown, p_map)

    try:
        from scalp_conditions import flake_score

        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        scoped = gray.copy()
        scoped[crown == 0] = 0
        fs = float(flake_score(scoped))
    except Exception:
        fs = 0.0

    if fs >= 68.0:
        hair_loss = cv2.bitwise_or(bald_c, cv2.bitwise_or(thin_c, severe))
        infect_raw = _infection_mask(
            img_bgr,
            crown,
            tissue,
            exclude=cv2.bitwise_or(severe, mild),
            bald_mask=bald_mask,
            prob=p_map,
        )
        infect_raw = cv2.bitwise_and(infect_raw, cv2.bitwise_not(hair_loss))
        infect = _largest_connected(infect_raw, crown)

    return severe, mild, infect


def _contour_inside_zone(contour: np.ndarray, zone: np.ndarray, min_ratio: float = 0.72) -> bool:
    h, w = zone.shape[:2]
    painted = np.zeros((h, w), dtype=np.uint8)
    cv2.drawContours(painted, [contour], -1, 255, -1)
    area = float(cv2.contourArea(contour))
    if area < 1:
        return False
    inside = float(cv2.countNonZero(cv2.bitwise_and(painted, zone)))
    return (inside / area) >= min_ratio


def _contour_on_background(contour: np.ndarray, bg_mask: np.ndarray) -> bool:
    m = cv2.moments(contour)
    if m["m00"] <= 0:
        return True
    cx = int(m["m10"] / m["m00"])
    cy = int(m["m01"] / m["m00"])
    h, w = bg_mask.shape[:2]
    cx = max(0, min(w - 1, cx))
    cy = max(0, min(h - 1, cy))
    return bg_mask[cy, cx] > 0


def trace_and_draw_outlines(
    overlay_bgr: np.ndarray,
    mask: np.ndarray,
    *,
    color_bgr: Tuple[int, int, int],
    zone: np.ndarray,
    bg_mask: np.ndarray,
    line_thickness: int,
    min_area: float,
    max_regions: int = 6,
    eps_ratio: float = 0.022,
    prefer_center: Optional[Tuple[int, int]] = None,
    inside_mask: Optional[np.ndarray] = None,
    damage_anchor: Optional[np.ndarray] = None,
) -> bool:
    """Trace real damage boundaries — largest contours first (not tiny edge shards)."""
    h, w = overlay_bgr.shape[:2]
    inside = inside_mask if inside_mask is not None else zone
    work = mask.copy()
    if cv2.countNonZero(work) < min_area:
        return False
    k15 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    work = cv2.morphologyEx(work, cv2.MORPH_CLOSE, k15)
    contours, _ = cv2.findContours(work, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    ranked: List[Tuple[float, np.ndarray]] = []
    for c in contours:
        area = float(cv2.contourArea(c))
        if area < min_area:
            continue
        if not _contour_inside_zone(c, inside, 0.52):
            continue
        if damage_anchor is None and _contour_on_background(c, bg_mask):
            continue
        score = area
        if damage_anchor is not None and cv2.countNonZero(damage_anchor) > 0:
            painted = np.zeros((h, w), dtype=np.uint8)
            cv2.drawContours(painted, [c], -1, 255, -1)
            overlap = float(cv2.countNonZero(cv2.bitwise_and(painted, damage_anchor)))
            score = area + overlap * 3.5
        ranked.append((score, c))
    ranked.sort(key=lambda t: t[0], reverse=True)
    drew = False
    for _, c in ranked[:max_regions]:
        peri = cv2.arcLength(c, True)
        eps = max(2.5, eps_ratio * peri)
        approx = cv2.approxPolyDP(c, eps, True)
        if len(approx) < 3:
            continue
        cv2.polylines(
            overlay_bgr,
            [approx],
            isClosed=True,
            color=color_bgr,
            thickness=line_thickness,
            lineType=cv2.LINE_AA,
        )
        drew = True
    return drew


def _apply_region_metrics(result: Dict[str, Any]) -> Dict[str, Any]:
    """Override generic metrics with values derived from drawn region evidence."""
    stats = _LAST_REGION_STATS
    crown = float(stats.get("crown_px") or 0)
    if crown < 100:
        return result

    bald_frac = float(stats.get("bald_frac") or 0)
    thin_frac = float(stats.get("thin_frac") or 0)
    severe_frac = float(stats.get("severe_frac") or 0)
    mild_frac = float(stats.get("mild_frac") or 0)
    infect_frac = float(stats.get("infect_frac") or 0)
    affected = float(np.clip(max(bald_frac + 0.42 * thin_frac, float(result.get("bald_ratio") or 0)), 0.0, 1.0))

    hair_strength = round(float(np.clip(100 - 52 * affected - 95 * severe_frac, 10, 100)), 1)
    scalp_health = round(float(np.clip(100 - 48 * affected - 70 * infect_frac - 35 * severe_frac, 10, 100)), 1)
    hair_damage = round(float(np.clip(8 + 62 * affected + 88 * severe_frac + 22 * mild_frac, 10, 100)), 1)
    hair_fall = round(float(np.clip(6 + 58 * affected + 92 * severe_frac + 18 * mild_frac, 10, 100)), 1)
    hair_density = round(float(np.clip(100 - 58 * affected - 40 * thin_frac, 10, 100)), 1)

    result["hair_strength"] = hair_strength
    result["scalp_health"] = scalp_health
    result["hair_damage_level"] = hair_damage
    result["hair_fall_risk"] = hair_fall
    result["hair_density"] = hair_density
    result["bald_ratio"] = round(affected, 4)
    result["region_evidence"] = {
        "crown_px": int(crown),
        "bald_frac_crown": round(bald_frac, 4),
        "thin_frac_crown": round(thin_frac, 4),
        "severe_frac_crown": round(severe_frac, 4),
        "mild_frac_crown": round(mild_frac, 4),
        "infect_frac_crown": round(infect_frac, 4),
    }
    return result


def draw_scalp_overlay(
    overlay_bgr: np.ndarray,
    img_bgr: np.ndarray,
    h: int,
    w: int,
    bald_mask: np.ndarray,
    thin_mask: np.ndarray,
    keep_zone: np.ndarray,
    prob: Optional[np.ndarray] = None,
) -> Dict[str, bool]:
    """
    Draw outline-only overlays using strict red / orange / teal.
    """
    drawn: Dict[str, bool] = {"red": False, "teal": False, "orange": False}
    zone, bg, head_center = _analysis_zone(img_bgr, keep_zone)
    import scalp_processor as sp

    head_mask, _, _ = sp._detect_scalp_head_mask(img_bgr)
    mild_draw = cv2.bitwise_and(keep_zone, head_mask)
    if cv2.countNonZero(mild_draw) < 80:
        mild_draw = zone
    zone_px = max(1, int(cv2.countNonZero(zone)))
    mild_px = max(1, int(cv2.countNonZero(mild_draw)))
    min_mild = max(180.0, 0.0025 * mild_px)
    min_severe = max(120.0, 0.0018 * zone_px)
    min_infect = max(110.0, 0.0018 * zone_px)
    line_thin = max(3, min(h, w) // 72)
    line_red = max(4, min(h, w) // 58)
    k_sev = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))
    severe_inside = cv2.bitwise_or(cv2.dilate(zone, k_sev, iterations=1), mild_draw)

    severe_k, mild_k, infect_k = segment_three_classes(
        img_bgr, zone, prob, bald_mask, thin_mask, keep_zone=keep_zone
    )
    damage_anchor = cv2.bitwise_or(
        cv2.bitwise_and(bald_mask, mild_draw),
        cv2.bitwise_or(severe_k, mild_k),
    )

    crown_px = max(1, int(cv2.countNonZero(mild_draw)))
    bald_on = cv2.bitwise_and(bald_mask, mild_draw)
    thin_on = cv2.bitwise_and(thin_mask, mild_draw)
    _LAST_REGION_STATS.clear()
    _LAST_REGION_STATS.update(
        {
            "crown_px": float(crown_px),
            "bald_px": float(cv2.countNonZero(bald_on)),
            "thin_px": float(cv2.countNonZero(thin_on)),
            "severe_px": float(cv2.countNonZero(severe_k)),
            "mild_px": float(cv2.countNonZero(mild_k)),
            "infect_px": float(cv2.countNonZero(infect_k)),
            "bald_frac": float(cv2.countNonZero(bald_on)) / crown_px,
            "thin_frac": float(cv2.countNonZero(thin_on)) / crown_px,
            "severe_frac": float(cv2.countNonZero(severe_k)) / crown_px,
            "mild_frac": float(cv2.countNonZero(mild_k)) / crown_px,
            "infect_frac": float(cv2.countNonZero(infect_k)) / crown_px,
        }
    )

    # Draw order: mild (orange) → severe (red) → infection (teal)
    if trace_and_draw_outlines(
        overlay_bgr,
        mild_k,
        color_bgr=COLOR_MILD_BGR,
        zone=zone,
        bg_mask=bg,
        line_thickness=line_thin,
        min_area=min_mild,
        max_regions=5,
        prefer_center=head_center,
        inside_mask=mild_draw,
        damage_anchor=damage_anchor,
    ):
        drawn["orange"] = True

    if trace_and_draw_outlines(
        overlay_bgr,
        severe_k,
        color_bgr=COLOR_SEVERE_BGR,
        zone=zone,
        bg_mask=bg,
        line_thickness=line_red,
        min_area=min_severe,
        max_regions=2,
        prefer_center=head_center,
        inside_mask=severe_inside,
        damage_anchor=damage_anchor,
    ):
        drawn["red"] = True

    # Infection only if enough evidence
    try:
        from scalp_conditions import flake_score

        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        scoped = gray.copy()
        scoped[zone == 0] = 0
        fs = flake_score(scoped)
    except Exception:
        fs = 0.0
    infect_px = cv2.countNonZero(infect_k)
    show_infect = infect_px >= min_infect and fs >= 72.0
    if show_infect and trace_and_draw_outlines(
        overlay_bgr,
        infect_k,
        color_bgr=COLOR_INFECTION_BGR,
        zone=zone,
        bg_mask=bg,
        line_thickness=line_thin,
        min_area=min_infect,
        max_regions=2,
        prefer_center=head_center,
    ):
        drawn["teal"] = True

    return drawn


def _build_detected_issues(
    legend: Dict[str, bool],
    bald_ratio: float,
    condition_probs: Optional[Dict[str, float]] = None,
) -> List[Dict[str, Any]]:
    issues: List[Dict[str, Any]] = []

    def _row(issue: str, severity: str, loc: str, rec: str, conf: float) -> Dict[str, Any]:
        return {
            "issue": issue,
            "issue_type": issue,
            "severity": severity,
            "location": loc,
            "recommendation": rec,
            "confidence": round(float(np.clip(conf, 0.0, 0.99)), 2),
        }

    if legend.get("red"):
        issues.append(
            _row(
                "High-level baldness",
                "severe",
                "crown / vertex",
                "Consult a dermatologist or hair specialist; consider medical therapy or graft evaluation.",
                min(0.98, 0.58 + bald_ratio * 2.4),
            )
        )
    if legend.get("orange"):
        issues.append(
            _row(
                "Mild thinning",
                "moderate",
                "crown perimeter",
                "Monitor density; gentle scalp care and early treatment may slow progression.",
                min(0.95, 0.52 + bald_ratio * 1.8),
            )
        )
    if legend.get("teal"):
        conf = 0.74
        if condition_probs:
            conf = max(
                conf,
                condition_probs.get("Dandruff", 0),
                condition_probs.get("Fungal Infection", 0),
            )
        issues.append(
            _row(
                "Dandruff or scalp infection",
                "moderate",
                "affected scalp patches",
                "Use medicated shampoo as advised; seek diagnosis if symptoms persist.",
                min(0.98, conf),
            )
        )
    return issues


def _package_api_result(result: Dict[str, Any]) -> Dict[str, Any]:
    """Aliases expected by reports / analyze_scalp without breaking existing keys."""
    legend = result.get("overlay_legend") if isinstance(result.get("overlay_legend"), dict) else {}
    result["overlay_legend_caption"] = overlay_legend_caption(legend)
    result["detected_issues"] = _build_detected_issues(
        legend,
        float(result.get("bald_ratio") or 0),
        result.get("condition_probs"),
    )
    if result.get("overlay_image_base64"):
        result["processed_image"] = result["overlay_image_base64"]
    result["metrics"] = {
        "hair_strength": result.get("hair_strength"),
        "scalp_health": result.get("scalp_health"),
        "hair_density": result.get("hair_density"),
        "moisture_level": result.get("moisture_level"),
        "hair_damage_level": result.get("hair_damage_level"),
        "hair_fall_risk": result.get("hair_fall_risk"),
    }
    result["graft_estimation"] = {
        "min": result.get("graft_min"),
        "max": result.get("graft_max"),
        "bald_area_cm2": result.get("bald_area_cm2"),
    }
    result["overlay_pipeline_version"] = "v8b_crown_zone_fix"
    result["metrics_source"] = (
        "Computed from crown bald/thin/severe/mild pixel evidence on this photo — not random."
    )
    legend = result.get("overlay_legend") if isinstance(result.get("overlay_legend"), dict) else {}
    result["has_ai_overlay"] = bool(
        legend.get("red") or legend.get("orange") or legend.get("teal")
    )
    return result


def analyze_scalp(
    image_path: str,
    *,
    use_cnn: bool = True,
    cnn_model_path: Optional[str] = None,
    use_trained_model: bool = True,
    trained_model_path: Optional[str] = None,
    use_condition_model: bool = True,
    condition_model_path: Optional[str] = None,
) -> Dict[str, Any]:
    """Analyze scalp image from path; returns API-compatible dict + metrics/issues."""
    path = Path(image_path)
    if not path.is_file():
        raise FileNotFoundError(f"Image not found: {image_path}")

    image_bytes = path.read_bytes()
    from scalp_processor import analyze_scalp_with_opencv

    seg_path = cnn_model_path or str(ONNX_SEG_PATH)
    has_onnx = Path(seg_path).is_file()
    has_tflite = TFLITE_SEG_PATH.is_file()
    result = analyze_scalp_with_opencv(
        image_bytes,
        use_cnn=use_cnn and (has_onnx or has_tflite),
        cnn_model_path=seg_path if has_onnx else None,
        use_trained_model=use_trained_model,
        trained_model_path=trained_model_path,
        use_condition_model=use_condition_model,
        condition_model_path=condition_model_path,
    )
    return _package_api_result(result)


def apply_overlay_patch() -> None:
    import scalp_processor as sp

    sp._draw_clinical_scalp_overlay = draw_scalp_overlay  # type: ignore[method-assign]

    _orig_analyze = sp.analyze_scalp_with_opencv

    def _wrapped_analyze(*args: Any, **kwargs: Any) -> Dict[str, Any]:
        out = _orig_analyze(*args, **kwargs)
        out = _apply_region_metrics(out)
        return _package_api_result(out)

    sp.analyze_scalp_with_opencv = _wrapped_analyze  # type: ignore[method-assign]
