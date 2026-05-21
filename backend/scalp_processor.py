"""
Scalp image processing: bald area detection and graft estimation.
Uses OpenCV for image preprocessing and color-based segmentation.
Optional: plug in a CNN model for bald vs hair segmentation (see load_cnn_mask).
"""
import base64
import io
import os
from typing import Any, Tuple, Optional, List, Dict

import cv2
import numpy as np

# Graft density range (grafts per cm²) for bald-area transplant estimate.
GRAFTS_PER_CM2_MIN = 30
GRAFTS_PER_CM2_MAX = 40
# Thinning pixels contribute less than full bald pixels to graft math.
THIN_GRAFT_WEIGHT = 0.38
# Visible hair-bearing scalp: rough clinical range (hairs per cm²) for estimating hair count from hair pixels.
HAIRS_PER_CM2_MIN = 130
HAIRS_PER_CM2_MAX = 220
# Approximate pixels per cm for close-up scalp (calibration; adjust per camera)
PIXELS_PER_CM = 45

# CNN session cache (so we don't reload the model each request).
_CNN_SESSIONS = {}
_BALD_REGRESSOR = None


def _has_frontal_face(img_bgr: np.ndarray) -> bool:
    """
    Conservative face check used only to gate frontal mode.
    If no face is found, prefer top/crown pipeline.
    """
    try:
        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        detector = cv2.CascadeClassifier(cascade_path)
        if detector.empty():
            return False
        faces = detector.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(60, 60),
        )
        return len(faces) > 0
    except Exception:
        return False


def _bytes_to_image(image_bytes: bytes) -> np.ndarray:
    """Decode image bytes to BGR array."""
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image")
    return img


def _is_frontal_view(img_bgr: np.ndarray) -> bool:
    """
    Heuristic: frontal selfies show more facial skin in the lower third than the upper third
    (forehead/hair), vs top-down vertex photos.
    """
    h, w = img_bgr.shape[:2]
    if h < 100 or w < 100:
        return False
    ycrcb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))
    bh = max(int(h * 0.30), 1)
    th = max(int(h * 0.30), 1)
    bottom_ratio = float(cv2.countNonZero(skin[h - bh : h, :])) / (bh * w + 1e-6)
    top_ratio = float(cv2.countNonZero(skin[0:th, :])) / (th * w + 1e-6)
    return bool(bottom_ratio > 0.072 and bottom_ratio > top_ratio * 1.08)


def _frontal_view_score(img_bgr: np.ndarray) -> float:
    """
    Soft score [0..1] for frontal selfie likelihood.
    Higher score => more likely front/hairline shot.
    """
    h, w = img_bgr.shape[:2]
    if h < 100 or w < 100:
        return 0.0
    ycrcb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))
    bh = max(int(h * 0.30), 1)
    th = max(int(h * 0.30), 1)
    bottom_ratio = float(cv2.countNonZero(skin[h - bh : h, :])) / (bh * w + 1e-6)
    top_ratio = float(cv2.countNonZero(skin[0:th, :])) / (th * w + 1e-6)
    # Skin in lower frame + contrast between lower and upper bands indicates frontal orientation.
    return float(np.clip((bottom_ratio * 5.5) + max(0.0, bottom_ratio - top_ratio) * 5.0, 0.0, 1.0))


def _is_likely_vertex_top_view(img_bgr: np.ndarray) -> bool:
    """
    Prefer crown / vertex processing when the frame looks like a top-down scalp shot
    (dense texture in the head ROI, little forehead strip, or weak frontal-skin cue).
    Runs before _is_frontal_view so bench/shirt noise does not trigger temple wedges.
    """
    h, w = img_bgr.shape[:2]
    if h < 100 or w < 100:
        return False
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    ycrcb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))
    th = max(int(h * 0.22), 1)
    bh = max(int(h * 0.30), 1)
    top_skin = float(cv2.countNonZero(skin[0:th, :])) / (th * w + 1e-6)
    bottom_skin = float(cv2.countNonZero(skin[h - bh : h, :])) / (bh * w + 1e-6)

    head_roi = _head_roi_mask(h, w)
    roi_pixels = max(1, int(cv2.countNonZero(head_roi)))
    lap = np.abs(cv2.Laplacian(gray, cv2.CV_32F))
    texture_in_roi = float(np.sum((lap > 7.5) & (head_roi > 0))) / roi_pixels

    # Typical vertex: mostly hair/scalp texture in ellipse, not a forehead skin band up top.
    if top_skin < 0.038 and texture_in_roi > 0.26:
        return True
    if bottom_skin < 0.09 and top_skin < 0.055 and texture_in_roi > 0.21:
        return True
    if _scalp_midline_part_boost(img_bgr) >= 0.14:
        return True
    return False


def _vertex_view_score(img_bgr: np.ndarray) -> float:
    """
    Soft score [0..1] for top/crown (vertex) view likelihood.
    Higher score => more likely vertex shot.
    """
    h, w = img_bgr.shape[:2]
    if h < 100 or w < 100:
        return 0.0
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    ycrcb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))
    th = max(int(h * 0.22), 1)
    bh = max(int(h * 0.30), 1)
    top_skin = float(cv2.countNonZero(skin[0:th, :])) / (th * w + 1e-6)
    bottom_skin = float(cv2.countNonZero(skin[h - bh : h, :])) / (bh * w + 1e-6)
    head_roi = _head_roi_mask(h, w)
    roi_pixels = max(1, int(cv2.countNonZero(head_roi)))
    lap = np.abs(cv2.Laplacian(gray, cv2.CV_32F))
    texture_in_roi = float(np.sum((lap > 7.5) & (head_roi > 0))) / roi_pixels
    # Top-view usually has low facial skin bands and high texture in scalp ROI.
    score = (texture_in_roi * 1.9) + max(0.0, 0.08 - top_skin) * 2.0 + max(0.0, 0.12 - bottom_skin) * 1.4
    score += _scalp_midline_part_boost(img_bgr)
    return float(np.clip(score, 0.0, 1.0))


def _scalp_midline_part_boost(img_bgr: np.ndarray) -> float:
    """
    Long hair parted to expose the midline scalp (common in clinical checks, any gender):
    central low-saturation strip with hairier, higher-texture sides. Nudges routing toward
    vertex/crown processing instead of misclassifying as a frontal face selfie.
    """
    h, w = img_bgr.shape[:2]
    if h < 120 or w < 120:
        return 0.0
    head = _head_roi_mask(h, w) > 0
    y0, y1 = int(h * 0.28), int(h * 0.74)
    xc0, xc1 = int(w * 0.43), int(w * 0.57)
    band = head[y0:y1, xc0:xc1]
    if band.sum() < 100:
        return 0.0
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    sat = hsv[y0:y1, xc0:xc1, 1].astype(np.float32)
    val = hsv[y0:y1, xc0:xc1, 2].astype(np.float32)
    scalp_like = ((sat < 92) & (val > 50) & band).astype(np.float32)
    frac = float(scalp_like.sum() / (band.sum() + 1e-6))
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    lap = np.abs(cv2.Laplacian(gray, cv2.CV_32F))
    lx0, lx1 = int(w * 0.12), int(w * 0.34)
    rx0, rx1 = int(w * 0.66), int(w * 0.88)
    mL = head[y0:y1, lx0:lx1]
    mR = head[y0:y1, rx0:rx1]
    left_mean = float(np.mean(lap[y0:y1, lx0:lx1][mL])) if mL.any() else 0.0
    right_mean = float(np.mean(lap[y0:y1, rx0:rx1][mR])) if mR.any() else 0.0
    side_lap = 0.5 * (left_mean + right_mean)
    if frac > 0.30 and side_lap > 6.0:
        return float(np.clip((frac - 0.30) * 0.75 + min(side_lap / 24.0, 1.0) * 0.14, 0.0, 0.30))
    return 0.0


def _frontal_head_guard_mask(h: int, w: int) -> np.ndarray:
    """
    Ellipse over head / upper face only. Keeps frontal temple heuristics off ceiling,
    wallpaper, and other background above the subject.
    """
    guard = np.zeros((h, w), dtype=np.uint8)
    cv2.ellipse(
        guard,
        center=(w // 2, int(h * 0.40)),
        axes=(int(w * 0.44), int(h * 0.50)),
        angle=0,
        startAngle=0,
        endAngle=360,
        color=255,
        thickness=-1,
    )
    return guard


def _forehead_hairline_roi(h: int, w: int) -> np.ndarray:
    """Curved region over forehead + frontal hairline to avoid introducing straight artificial lines."""
    mask = np.zeros((h, w), dtype=np.uint8)
    # create a wide front-facing head ellipse
    cv2.ellipse(
        mask,
        center=(w // 2, int(h * 0.34)),
        axes=(int(w * 0.43), int(h * 0.29)),
        angle=0,
        startAngle=0,
        endAngle=360,
        color=255,
        thickness=-1,
    )
    guard = _frontal_head_guard_mask(h, w)
    roi = cv2.bitwise_and(mask, guard)
    # Keep frontal ROI mostly in upper-head band so overlays stick to hairline
    # instead of extending deep into forehead skin.
    upper_band = np.zeros((h, w), dtype=np.uint8)
    y_top = int(h * 0.02)
    y_bottom = int(h * 0.56)
    upper_band[y_top:y_bottom, :] = 255
    return cv2.bitwise_and(roi, upper_band)


def _left_temple_wedge_polygon(h: int, w: int) -> np.ndarray:
    """
    Closed polygon approximating a temple recession highlight: wide toward the outer side,
    tapering inward toward the midline / widow's peak (clinical markup style).
    Coordinates are tuned for typical frontal selfies in the forehead trapezoid ROI.
    """
    return np.array(
        [
            [int(w * 0.02), int(h * 0.04)],
            [int(w * 0.04), int(h * 0.18)],
            [int(w * 0.10), int(h * 0.36)],
            [int(w * 0.28), int(h * 0.33)],
            [int(w * 0.40), int(h * 0.26)],
            [int(w * 0.47), int(h * 0.15)],
            [int(w * 0.44), int(h * 0.09)],
            [int(w * 0.30), int(h * 0.045)],
        ],
        dtype=np.int32,
    )


def _mirror_polygon_x(pts: np.ndarray, w: int) -> np.ndarray:
    """Reflect polygon horizontally for the right temple wedge."""
    m = pts.copy()
    m[:, 0] = (w - 1) - m[:, 0]
    return m.astype(np.int32)


def _temple_wedge_highlight_polylines(h: int, w: int) -> Tuple[np.ndarray, np.ndarray]:
    """Left and right closed polygons for drawing yellow temple recession highlights."""
    left = _left_temple_wedge_polygon(h, w)
    right = _mirror_polygon_x(left, w)
    return left, right


def _draw_frontal_temple_wedge_highlights(
    overlay_bgr: np.ndarray,
    h: int,
    w: int,
    *,
    line_thickness: Optional[int] = None,
) -> None:
    """
    Draw semi-transparent yellow fill + thick yellow outline on left/right temple wedges
    (matches hand-drawn clinical recession markup).
    """
    yellow_bgr = (0, 255, 255)
    left, right = _temple_wedge_highlight_polylines(h, w)
    if line_thickness is None:
        line_thickness = max(6, min(h, w) // 55)

    # Never paint ceiling/wallpaper: restrict markup to forehead band ∩ head ellipse.
    clip = cv2.bitwise_and(_forehead_hairline_roi(h, w), _frontal_head_guard_mask(h, w))

    fill_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.fillPoly(fill_mask, [left], 255)
    cv2.fillPoly(fill_mask, [right], 255)
    fill_mask = cv2.bitwise_and(fill_mask, clip)
    alpha = 0.14
    layer = np.zeros_like(overlay_bgr)
    layer[:, :] = yellow_bgr
    am = (fill_mask.astype(np.float32) / 255.0) * alpha
    am3 = np.repeat(am[:, :, None], 3, axis=2)
    blended = (
        overlay_bgr.astype(np.float32) * (1.0 - am3) + layer.astype(np.float32) * am3
    ).astype(np.uint8)
    np.copyto(overlay_bgr, blended)

    for poly in (left, right):
        line_art = np.zeros_like(overlay_bgr)
        cv2.polylines(
            line_art,
            [poly.reshape(-1, 1, 2)],
            isClosed=True,
            color=yellow_bgr,
            thickness=line_thickness,
            lineType=cv2.LINE_AA,
        )
        gray_ln = cv2.cvtColor(line_art, cv2.COLOR_BGR2GRAY)
        keep = (gray_ln > 0) & (clip > 0)
        overlay_bgr[keep] = line_art[keep]


def _frontal_temple_scalp_masks(img_bgr: np.ndarray) -> Tuple[np.ndarray, np.ndarray, List[np.ndarray]]:
    """
    Segment visible scalp / thinning in left & right temple zones (frontal hairline).
    Returns (combined_scalp_mask, mask_hair, contours_for_outline).
    """
    h, w = img_bgr.shape[:2]
    forehead = _forehead_hairline_roi(h, w)
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    ycrcb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2YCrCb)
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    # More conservative frontal segmentation to avoid over-marking dense-hair zones.
    low_sat = sat < 108
    high_val = val > 58
    bright = gray > 66
    mask_skin_hsv = ((low_sat & high_val & bright).astype(np.uint8) * 255)
    # YCrCb skin range catches frontal forehead/hairline skin under varied lighting.
    mask_skin_ycrcb = cv2.inRange(ycrcb, (0, 134, 77), (255, 178, 132))
    mask_skin = cv2.bitwise_or(mask_skin_hsv, mask_skin_ycrcb)
    mask_skin = cv2.bitwise_and(mask_skin, forehead)
    # Hard guard: no temple segmentation outside head ellipse (blocks wallpaper skin-tones).
    mask_skin = cv2.bitwise_and(mask_skin, _frontal_head_guard_mask(h, w))
    k_skin = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask_skin = cv2.morphologyEx(mask_skin, cv2.MORPH_CLOSE, k_skin)

    _, mask_dark = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    lap = cv2.Laplacian(gray, cv2.CV_32F)
    mask_texture = (np.abs(lap) > 6.5).astype(np.uint8) * 255
    mask_hair = cv2.bitwise_or(mask_dark, mask_texture)
    mask_hair = cv2.bitwise_and(mask_hair, forehead)
    mask_hair = cv2.bitwise_and(mask_hair, _frontal_head_guard_mask(h, w))

    mask_scalp_raw = cv2.bitwise_and(mask_skin, cv2.bitwise_not(mask_hair))

    # Force highlights to sit near hair boundaries (where thinning is visible),
    # not on broad plain-skin forehead zones.
    k_near_hair = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))
    near_hair = cv2.dilate(mask_hair, k_near_hair)
    mask_scalp_raw = cv2.bitwise_and(mask_scalp_raw, near_hair)

    mid_l, mid_r = int(w * 0.40), int(w * 0.60)
    left_gate = np.zeros((h, w), dtype=np.uint8)
    left_gate[:, :mid_r] = 255
    right_gate = np.zeros((h, w), dtype=np.uint8)
    right_gate[:, mid_l:] = 255

    mask_l = cv2.bitwise_and(mask_scalp_raw, left_gate)
    mask_r = cv2.bitwise_and(mask_scalp_raw, right_gate)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    for m in (mask_l, mask_r):
        cv2.morphologyEx(m, cv2.MORPH_OPEN, kernel, dst=m)
        cv2.morphologyEx(m, cv2.MORPH_CLOSE, kernel, dst=m)
    mask_l = cv2.medianBlur(mask_l, 3)
    mask_r = cv2.medianBlur(mask_r, 3)

    combined = np.zeros((h, w), dtype=np.uint8)
    cv2.bitwise_or(combined, mask_l, dst=combined)
    cv2.bitwise_or(combined, mask_r, dst=combined)

    # Remove tiny isolated islands that often appear near edges/background.
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(combined, connectivity=8)
    cleaned = np.zeros_like(combined)
    kept = 0
    min_comp_area = max(220, int(0.0012 * h * w))
    for lbl in range(1, n_labels):
        area = int(stats[lbl, cv2.CC_STAT_AREA])
        if area < min_comp_area:
            continue
        kept += 1
        cleaned[labels == lbl] = 255
    if kept > 0:
        combined = cleaned

    # Smooth the combined mask heavily before extracting organic contours so it merges seamlessly 
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    smooth_combined = cv2.morphologyEx(combined, cv2.MORPH_CLOSE, k)
    smooth_combined = cv2.morphologyEx(smooth_combined, cv2.MORPH_OPEN, k)

    outline_contours: List[np.ndarray] = []
    contours, _ = cv2.findContours(smooth_combined, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    
    # Keep only top 2 strongest frontal patches to avoid tiny noisy islands.
    for c in contours[:2]:
        if cv2.contourArea(c) < 320.0:
            continue
        hull = cv2.convexHull(c)
        peri = cv2.arcLength(hull, True)
        approx = cv2.approxPolyDP(hull, 0.005 * peri, True)
        if len(approx) >= 3:
            outline_contours.append(approx)

    return combined, mask_hair, outline_contours


def _head_roi_mask(h: int, w: int) -> np.ndarray:
    """Elliptical ROI approximating the scalp region in a top-down photo."""
    head_roi = np.zeros((h, w), dtype=np.uint8)
    cv2.ellipse(
        head_roi,
        center=(w // 2, int(h * 0.48)),
        axes=(int(w * 0.40), int(h * 0.42)),
        angle=0,
        startAngle=0,
        endAngle=360,
        color=255,
        thickness=-1,
    )
    return head_roi


def _vertex_keyhole_mask(h: int, w: int) -> np.ndarray:
    """
    Clinical-style ROI: narrow toward the front (bottom of frame), widening over the crown — keyhole / flask shape.
    """
    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.ellipse(
        mask,
        center=(w // 2, int(h * 0.36)),
        axes=(int(w * 0.37), int(h * 0.34)),
        angle=0,
        startAngle=0,
        endAngle=360,
        color=255,
        thickness=-1,
    )
    # Neck toward anterior hairline (image bottom)
    neck_w0, neck_w1 = int(w * 0.43), int(w * 0.57)
    neck_top = int(h * 0.58)
    pts = np.array(
        [
            [neck_w0, h - 2],
            [neck_w1, h - 2],
            [int(w * 0.54), neck_top],
            [int(w * 0.46), neck_top],
        ],
        dtype=np.int32,
    )
    cv2.fillConvexPoly(mask, pts, 255)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 17))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k)
    return mask


def _draw_vertex_keyhole_overlay(
    overlay_bgr: np.ndarray,
    h: int,
    w: int,
    bald_mask: np.ndarray,
) -> None:
    """Orange translucent fill + smooth outline (matches typical clinical markup)."""
    keyhole = _vertex_keyhole_mask(h, w)
    orange_bgr = (0, 140, 255)
    line_thickness = max(5, min(h, w) // 42)

    alpha = 0.13
    layer = np.zeros_like(overlay_bgr)
    layer[:, :] = orange_bgr
    am = (keyhole.astype(np.float32) / 255.0) * alpha
    am3 = np.repeat(am[:, :, None], 3, axis=2)
    blended = (
        overlay_bgr.astype(np.float32) * (1.0 - am3) + layer.astype(np.float32) * am3
    ).astype(np.uint8)
    np.copyto(overlay_bgr, blended)

    contours, _ = cv2.findContours(keyhole, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        if len(c) < 4:
            continue
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.0035 * peri, True)
        cv2.polylines(
            overlay_bgr,
            [approx],
            isClosed=True,
            color=orange_bgr,
            thickness=line_thickness,
            lineType=cv2.LINE_AA,
        )

    # Emphasize thinning inside keyhole when bald mask is available
    kh_bald = cv2.bitwise_and(keyhole, bald_mask)
    if cv2.countNonZero(kh_bald) > 80:
        layer2 = np.zeros_like(overlay_bgr)
        layer2[:, :] = (0, 100, 255)
        a2 = (kh_bald.astype(np.float32) / 255.0) * 0.10
        a23 = np.repeat(a2[:, :, None], 3, axis=2)
        blended2 = (
            overlay_bgr.astype(np.float32) * (1.0 - a23) + layer2.astype(np.float32) * a23
        ).astype(np.uint8)
        np.copyto(overlay_bgr, blended2)


def _draw_vertex_bald_thin_overlay(
    overlay_bgr: np.ndarray,
    h: int,
    w: int,
    bald_mask: np.ndarray,
    thin_mask: np.ndarray,
) -> None:
    """
    Clinical-style vertex view: cyan = thinning (sparse hair / scalp show-through),
    orange = bald (dominant scalp). Draws a smoothing contour outlining the actual
    detected bald/thin area.
    """
    keyhole = _vertex_keyhole_mask(h, w)
    thin_k = cv2.bitwise_and(thin_mask, keyhole)
    bald_k = cv2.bitwise_and(bald_mask, keyhole)
    seed0 = cv2.bitwise_or(bald_k, thin_k)
    # Avoid painting unrelated regions when almost nothing is detected.
    if cv2.countNonZero(seed0) < 22:
        return
    # Keep all tinting inside a band around AI-detected scalp only (not distant hair/background).
    k_band = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (33, 33))
    seed_band = cv2.dilate(seed0, k_band)
    thin_k = cv2.bitwise_and(thin_k, seed_band)
    bald_k = cv2.bitwise_and(bald_k, seed_band)
    line_thickness = max(5, min(h, w) // 42)
    red_bgr = (35, 35, 235)       # high-risk bald zone
    yellow_bgr = (0, 215, 255)    # thinning zone
    green_bgr = (80, 200, 90)     # low-density fringe

    # derive a low-density fringe around thin zones for green marking
    k_ring = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    low_k = cv2.dilate(thin_k, k_ring)
    low_k = cv2.bitwise_and(low_k, cv2.bitwise_not(thin_k))
    low_k = cv2.bitwise_and(low_k, keyhole)
    low_k = cv2.bitwise_and(low_k, seed_band)

    for mask, color, alpha in (
        (low_k, green_bgr, 0.10),
        (thin_k, yellow_bgr, 0.22),
        (bald_k, red_bgr, 0.20),
    ):
        if cv2.countNonZero(mask) < 8:
            continue
        layer = np.zeros_like(overlay_bgr)
        layer[:, :] = color
        am = (mask.astype(np.float32) / 255.0) * alpha
        am3 = np.repeat(am[:, :, None], 3, axis=2)
        blended = (
            overlay_bgr.astype(np.float32) * (1.0 - am3) + layer.astype(np.float32) * am3
        ).astype(np.uint8)
        np.copyto(overlay_bgr, blended)

    mask_combined = cv2.bitwise_or(bald_k, thin_k)
    # Keep focus near crown center so side artifacts are suppressed.
    yy, xx = np.indices((h, w))
    cx, cy = (w * 0.5), (h * 0.44)
    rx, ry = (w * 0.23), (h * 0.25)
    center_prior = ((((xx - cx) ** 2) / (rx ** 2 + 1e-6) + ((yy - cy) ** 2) / (ry ** 2 + 1e-6)) <= 1.0).astype(np.uint8) * 255
    mask_combined = cv2.bitwise_and(mask_combined, center_prior)

    blur_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    mask_combined = cv2.morphologyEx(mask_combined, cv2.MORPH_CLOSE, blur_kernel)
    mask_combined = cv2.morphologyEx(mask_combined, cv2.MORPH_OPEN, blur_kernel)

    contours, _ = cv2.findContours(mask_combined, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if contours:
        center = np.array([w * 0.5, h * 0.44], dtype=np.float32)
        best = None
        best_score = -1e9
        for c in contours:
            area = float(cv2.contourArea(c))
            if area < 280.0:
                continue
            m = cv2.moments(c)
            if m["m00"] <= 0:
                continue
            ccx = m["m10"] / m["m00"]
            ccy = m["m01"] / m["m00"]
            dist = float(np.linalg.norm(np.array([ccx, ccy], dtype=np.float32) - center))
            score = area - 1.6 * dist
            if score > best_score:
                best_score = score
                best = c
        if best is not None:
            hull = cv2.convexHull(best)
            peri = cv2.arcLength(hull, True)
            approx = cv2.approxPolyDP(hull, 0.005 * peri, True)
            cv2.polylines(
                overlay_bgr,
                [approx],
                isClosed=True,
                color=red_bgr,
                thickness=line_thickness,
                lineType=cv2.LINE_AA,
            )


def _preprocess(img: np.ndarray, max_side: int = 640) -> np.ndarray:
    """Resize and denoise for consistent processing."""
    h, w = img.shape[:2]
    if max(h, w) > max_side:
        scale = max_side / max(h, w)
        new_w, new_h = int(w * scale), int(h * scale)
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
    # Light denoise
    img = cv2.bilateralFilter(img, 5, 50, 50)
    return img


def _bald_area_mask_opencv(img: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """
    Detect bald (scalp/skin) regions using HSV color segmentation.
    Returns (mask_scalp, mask_hair). Scalp = skin-like; hair = dark or non-skin.
    """
    h, w = img.shape[:2]
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 1) Head ROI: center-top ellipse to suppress background edges.
    head_roi = _head_roi_mask(h, w)

    # 2) Skin/scalp candidates: low saturation + medium-high value (works on shaved/thin hair).
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    low_sat = sat < 95
    high_val = val > 65
    bright_scalp = gray > 75
    mask_skin = ((low_sat & high_val & bright_scalp).astype(np.uint8) * 255)
    mask_skin = cv2.bitwise_and(mask_skin, head_roi)

    # 3) Hair candidates: dark/texture-rich regions.
    _, mask_dark = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    lap = cv2.Laplacian(gray, cv2.CV_32F)
    mask_texture = (np.abs(lap) > 8.0).astype(np.uint8) * 255
    mask_hair = cv2.bitwise_or(mask_dark, mask_texture)
    mask_hair = cv2.bitwise_and(mask_hair, head_roi)

    # 4) Scalp visible = skin - hair.
    mask_scalp = cv2.bitwise_and(mask_skin, cv2.bitwise_not(mask_hair))

    # 5) Center prior: bald zone is often around top-center; suppress side/background leakage.
    yy, xx = np.indices((h, w))
    cx, cy = (w * 0.5), (h * 0.53)
    rx, ry = (w * 0.33), (h * 0.35)
    norm = ((xx - cx) ** 2) / (rx ** 2 + 1e-6) + ((yy - cy) ** 2) / (ry ** 2 + 1e-6)
    center_prior = (norm <= 1.25).astype(np.uint8) * 255
    mask_scalp = cv2.bitwise_and(mask_scalp, center_prior)

    # 6) Clean and fill for a smoother single bald region.
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    mask_scalp = cv2.morphologyEx(mask_scalp, cv2.MORPH_OPEN, kernel)
    mask_scalp = cv2.morphologyEx(mask_scalp, cv2.MORPH_CLOSE, kernel)
    mask_scalp = cv2.medianBlur(mask_scalp, 5)
    return mask_scalp, mask_hair


def _contours_to_area(mask: np.ndarray, min_area_px: int = 900) -> Tuple[float, List[np.ndarray]]:
    """Total bald area in pixels and list of contours (for overlay)."""
    contours, _ = cv2.findContours(
        mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    total_area = 0.0
    large_contours = []
    for c in contours:
        a = cv2.contourArea(c)
        if a >= min_area_px:
            total_area += a
            large_contours.append(c)
    if not large_contours:
        return 0.0, []

    # Keep the best center-relevant contour to avoid side highlights.
    h, w = mask.shape[:2]
    center = np.array([w * 0.5, h * 0.53], dtype=np.float32)
    best_score = -1.0
    best_contour = large_contours[0]
    for c in large_contours:
        area = float(cv2.contourArea(c))
        m = cv2.moments(c)
        if m["m00"] <= 0:
            continue
        cx = m["m10"] / m["m00"]
        cy = m["m01"] / m["m00"]
        dist = float(np.linalg.norm(np.array([cx, cy], dtype=np.float32) - center))
        dist_norm = dist / (max(h, w) + 1e-6)
        score = area * (1.0 - min(0.85, dist_norm))
        if score > best_score:
            best_score = score
            best_contour = c

    hull = cv2.convexHull(best_contour)
    total_area = float(cv2.contourArea(hull))
    return total_area, [hull]


def _estimate_grafts(bald_area_pixels: float) -> Tuple[int, int, float]:
    """Estimate graft count from bald area (pixels). Returns (min_grafts, max_grafts, area_cm2)."""
    area_cm2 = bald_area_pixels / (PIXELS_PER_CM * PIXELS_PER_CM)
    area_cm2 = max(0.1, min(area_cm2, 500.0))  # clamp
    min_grafts = int(area_cm2 * GRAFTS_PER_CM2_MIN)
    max_grafts = int(area_cm2 * GRAFTS_PER_CM2_MAX)
    return min_grafts, max_grafts, round(area_cm2, 2)


def _estimate_hair_count_from_hair_pixels(hair_pixels: float) -> Tuple[int, int, int]:
    """
    Estimate visible hair count from hair-segmentation pixels (within ROI).
    Uses hairs/cm² on the hair-bearing area of the crop (not full-scalp census).
    """
    if hair_pixels <= 0:
        return 0, 0, 0
    hair_cm2 = hair_pixels / (PIXELS_PER_CM * PIXELS_PER_CM)
    hair_cm2 = max(0.0, min(hair_cm2, 600.0))
    h_min = int(hair_cm2 * HAIRS_PER_CM2_MIN)
    h_max = int(hair_cm2 * HAIRS_PER_CM2_MAX)
    h_max = max(h_min, h_max)
    h_min = min(h_min, 250_000)
    h_max = min(h_max, 250_000)
    mid = (h_min + h_max) // 2
    return h_min, h_max, mid


def _cnn_raw_probability_map(
    image_bytes: bytes, model_path: Optional[str]
) -> Optional[np.ndarray]:
    """
    Run ONNX segmenter; return float32 HxW in ~[0,1] (sigmoid probability of bald/non-hair scalp).
    """
    if not model_path:
        return None
    try:
        import onnxruntime as ort
    except Exception:
        return None

    if model_path not in _CNN_SESSIONS:
        _CNN_SESSIONS[model_path] = ort.InferenceSession(
            model_path, providers=["CPUExecutionProvider"]
        )

    sess = _CNN_SESSIONS[model_path]
    img = _bytes_to_image(image_bytes)
    img = _preprocess(img)
    h, w = img.shape[:2]

    input_meta = sess.get_inputs()[0]
    input_shape = tuple(input_meta.shape)

    def _dim3(x: Any) -> bool:
        try:
            return int(x) == 3
        except (TypeError, ValueError):
            return False

    target_h = 256
    target_w = 256
    use_nchw = True
    if len(input_shape) == 4:
        a, b, c, d = input_shape
        if _dim3(b):
            use_nchw = True
            hi, wi = c, d
        elif _dim3(d):
            use_nchw = False
            hi, wi = b, c
        else:
            use_nchw = False
            hi, wi = b, c
        try:
            target_h = int(hi) if hi not in (None, "batch", "N") else 256
        except (TypeError, ValueError):
            target_h = 256
        try:
            target_w = int(wi) if wi not in (None, "batch", "N") else 256
        except (TypeError, ValueError):
            target_w = 256

    resized = cv2.resize(img, (target_w, target_h), interpolation=cv2.INTER_AREA)
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    if use_nchw:
        chw = np.transpose(rgb, (2, 0, 1))
        inp = np.expand_dims(chw, axis=0)
    else:
        inp = np.expand_dims(rgb, axis=0)

    output_name = sess.get_outputs()[0].name
    outputs = sess.run([output_name], {input_meta.name: inp})
    if not outputs:
        return None

    mask = outputs[0]
    if mask.ndim == 4:
        if mask.shape[1] == 1:
            mask = mask[0, 0, :, :]
        elif mask.shape[-1] == 1:
            mask = mask[0, :, :, 0]
        else:
            mask = mask[0, 0, :, :]
    elif mask.ndim == 3:
        mask = mask[0, :, :]
    else:
        return None

    mask = cv2.resize(mask.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
    lo, hi = float(np.min(mask)), float(np.max(mask))
    if hi > 1.5 or lo < -0.5:
        mask = 1.0 / (1.0 + np.exp(-np.clip(mask, -20.0, 20.0)))
    else:
        mask = np.clip(mask, 0.0, 1.0)

    head = _head_roi_mask(h, w)
    mask = mask * (head.astype(np.float32) / 255.0)
    return mask.astype(np.float32)


def load_cnn_mask(image_bytes: bytes, model_path: Optional[str] = None) -> Optional[np.ndarray]:
    """
    Optional: CNN segmentation — binary mask (255 = bald / target class).
    """
    prob = _cnn_raw_probability_map(image_bytes, model_path)
    if prob is None:
        return None
    hh, ww = prob.shape[:2]
    binary = (prob > 0.5).astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
    binary = cv2.bitwise_and(binary, _head_roi_mask(hh, ww))
    return binary


def _split_bald_and_thin_from_prob(
    prob: np.ndarray,
    *,
    t_thin: float = 0.18,
    t_bald: float = 0.42,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Split CNN probability into bald (high p) vs thinning (mid p). Hair = low p.
    Returns (bald_uint8_255, thin_uint8_255), disjoint masks.
    """
    bald = ((prob >= t_bald).astype(np.uint8)) * 255
    thin = (((prob >= t_thin) & (prob < t_bald)).astype(np.uint8)) * 255
    k3 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    bald = cv2.morphologyEx(bald, cv2.MORPH_OPEN, k3)
    thin = cv2.morphologyEx(thin, cv2.MORPH_OPEN, k3)
    thin = cv2.bitwise_and(thin, cv2.bitwise_not(bald))
    return bald, thin


def _bald_thin_masks_opencv_vertex(img: np.ndarray, head_roi: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Without CNN: estimate bald vs thinning from scalp visibility + blurred hair response.
    Returns (combined_scalp_for_metrics, bald_mask, thin_mask) uint8 0/255.
    """
    mask_scalp, mask_hair = _bald_area_mask_opencv(img)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    hf = mask_hair.astype(np.float32) / 255.0
    hair_blur = cv2.GaussianBlur(hf, (31, 31), 0)
    scoped = cv2.bitwise_and(mask_scalp, head_roi)
    hb = np.clip(hair_blur * (scoped.astype(np.float32) / 255.0), 0.0, 1.0)
    # Strong hair response nearby → thinning; very weak → slick bald skin
    bald = (scoped > 0) & (hb < 0.12)
    thin = (scoped > 0) & (hb >= 0.12) & (hb < 0.48)
    lap = np.abs(cv2.Laplacian(gray, cv2.CV_32F))
    thin = thin & (lap < 42.0)
    bald_u = (bald.astype(np.uint8)) * 255
    thin_u = (thin.astype(np.uint8)) * 255
    thin_u = cv2.bitwise_and(thin_u, cv2.bitwise_not(bald_u))
    combined = cv2.bitwise_or(bald_u, thin_u)
    return combined, bald_u, thin_u


def build_three_class_mask_png(img_bgr: np.ndarray) -> np.ndarray:
    """
    Pseudo-label for training: 0 = hair, 128 = thin, 255 = bald (saved as grayscale PNG).
    """
    h, w = img_bgr.shape[:2]
    head = _head_roi_mask(h, w)
    _, bald_u, thin_u = _bald_thin_masks_opencv_vertex(img_bgr, head)
    out = np.zeros((h, w), dtype=np.uint8)
    out[thin_u > 0] = 128
    out[bald_u > 0] = 255
    return out


def _extract_ml_features(img_bgr: np.ndarray) -> np.ndarray:
    """Must match features used in train_bald_model.py."""
    img = cv2.resize(img_bgr, (256, 256), interpolation=cv2.INTER_AREA)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    h_mean, s_mean, v_mean = [float(np.mean(hsv[:, :, i])) for i in range(3)]
    h_std, s_std, v_std = [float(np.std(hsv[:, :, i])) for i in range(3)]
    g_mean = float(np.mean(gray))
    g_std = float(np.std(gray))

    lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    edges = cv2.Canny(gray, 70, 140)
    edge_ratio = float(np.mean(edges > 0))
    bright_ratio = float(np.mean(gray > 160))
    mid_ratio = float(np.mean((gray > 100) & (gray <= 160)))
    dark_ratio = float(np.mean(gray <= 100))

    return np.array([
        h_mean, s_mean, v_mean,
        h_std, s_std, v_std,
        g_mean, g_std,
        lap_var, edge_ratio,
        bright_ratio, mid_ratio, dark_ratio,
    ], dtype=np.float32)


def _load_bald_regressor(model_path: Optional[str]) -> Optional[Any]:
    global _BALD_REGRESSOR
    if _BALD_REGRESSOR is not None:
        return _BALD_REGRESSOR
    if not model_path or not os.path.exists(model_path):
        return None
    try:
        import joblib
        payload = joblib.load(model_path)
        _BALD_REGRESSOR = payload.get("model")
        return _BALD_REGRESSOR
    except Exception:
        return None


def _process_frontal_scalp_image(
    img: np.ndarray,
    return_overlay_base64: bool,
    h: int,
    w: int,
    image_bytes: bytes,
    use_cnn: bool = False,
    cnn_model_path: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Front-facing / hairline photo: metrics from temple segmentation; overlay uses fixed yellow temple wedges
    (clinical-style recession markup). When CNN is enabled, merges segmentation inside forehead ∩ head guard.
    """
    segmentation_method = "hairline_view"
    mask_scalp_fb, mask_hair_fb, outline_contours_fb = _frontal_temple_scalp_masks(img)
    if use_cnn and cnn_model_path:
        cm = load_cnn_mask(image_bytes, cnn_model_path)
        if cm is not None:
            if cm.shape[:2] != (h, w):
                cm = cv2.resize(cm, (w, h), interpolation=cv2.INTER_NEAREST)
            fh = _forehead_hairline_roi(h, w)
            guard = _frontal_head_guard_mask(h, w)
            cm = cv2.bitwise_and(cm, cv2.bitwise_and(fh, guard))
            mask_scalp_fb = cv2.bitwise_or(mask_scalp_fb, cm)
            segmentation_method = "hairline_view+cnn"
            
            # Re-generate organic contours for the overlay so they match the CNN-improved mask
            outline_contours_fb = []
            blur_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
            smoothed = cv2.morphologyEx(mask_scalp_fb, cv2.MORPH_CLOSE, blur_k)
            smoothed = cv2.morphologyEx(smoothed, cv2.MORPH_OPEN, blur_k)
            contours, _ = cv2.findContours(smoothed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            contours = sorted(contours, key=cv2.contourArea, reverse=True)
            for c in contours[:2]:
                if cv2.contourArea(c) < 350.0:
                    continue
                hull = cv2.convexHull(c)
                peri = cv2.arcLength(hull, True)
                approx = cv2.approxPolyDP(hull, 0.005 * peri, True)
                if len(approx) >= 3:
                    outline_contours_fb.append(approx)
    forehead = _forehead_hairline_roi(h, w)
    fh_px = max(1, int(cv2.countNonZero(forehead)))

    bald_area_px = float(cv2.countNonZero(mask_scalp_fb))
    hair_pixels = float(cv2.countNonZero(cv2.bitwise_and(mask_hair_fb, forehead)))

    hair_area_cm2 = round(hair_pixels / (PIXELS_PER_CM * PIXELS_PER_CM), 2)
    est_h_min, est_h_max, est_h_mid = _estimate_hair_count_from_hair_pixels(hair_pixels)

    # Conservative scaling for frontal photos to reduce known overestimation risk.
    frontal_effective_px = bald_area_px * 0.82
    graft_min, graft_max, area_cm2 = _estimate_grafts(frontal_effective_px)

    # Ratio of visible scalp in forehead band (more meaningful than full-frame for frontal).
    bald_ratio = min(1.0, bald_area_px / float(fh_px)) if fh_px > 0 else 0.0

    overlay_b64 = None
    if return_overlay_base64:
        overlay = img.copy()
        
        line_thickness = max(5, min(h, w) // 42)
        orange_bgr = (0, 165, 255) # Match the orange line from the top view
        for approx in outline_contours_fb:
            cv2.polylines(
                overlay,
                [approx],
                isClosed=True,
                color=orange_bgr,
                thickness=line_thickness,
                lineType=cv2.LINE_AA,
            )

        _, buf = cv2.imencode(".jpg", overlay)
        overlay_b64 = base64.b64encode(buf.tobytes()).decode("utf-8")

    return {
        "bald_area_pixels": round(bald_area_px, 0),
        "bald_area_cm2": area_cm2,
        "bald_ratio": round(bald_ratio, 4),
        "graft_min": graft_min,
        "graft_max": graft_max,
        "hair_area_cm2": hair_area_cm2,
        "estimated_hair_count_min": est_h_min,
        "estimated_hair_count_max": est_h_max,
        "estimated_hair_count": est_h_mid,
        "segmentation_method": segmentation_method,
        "overlay_image_base64": overlay_b64,
        "contour_count": 2,
        "view_orientation": "front",
    }


def _routing_prefer_frontal(img_bgr: np.ndarray) -> bool:
    """
    Orientation arbitration: avoid false top-view classification on frontal selfies.
    Be strict before selecting frontal mode; otherwise top/crown photos can be
    misrouted to temple/hairline overlays (which looks visually incorrect).
    """
    frontal_flag = _is_frontal_view(img_bgr)
    vertex_flag = _is_likely_vertex_top_view(img_bgr)
    frontal_score = _frontal_view_score(img_bgr)
    vertex_score = _vertex_view_score(img_bgr)
    face_gate = _has_frontal_face(img_bgr)
    return bool(
        face_gate
        and frontal_flag
        and not vertex_flag
        and frontal_score >= (vertex_score + 0.12)
        and frontal_score >= 0.32
    )


def predict_view_orientation(image_bytes: bytes) -> str:
    """Returns 'front' or 'top' using the same routing rules as process_scalp_image."""
    img = _preprocess(_bytes_to_image(image_bytes))
    return "front" if _routing_prefer_frontal(img) else "top"


def eval_vertex_segmentation_masks(
    image_bytes: bytes,
    use_cnn: bool = False,
    cnn_model_path: Optional[str] = None,
) -> Tuple[np.ndarray, np.ndarray, str]:
    """
    Run vertex/crown segmentation only (no frontal routing) for held-out evaluation
    against top-view ground-truth masks.

    Returns (bald_u8, thin_u8, segmentation_method).
    """
    img = _bytes_to_image(image_bytes)
    img = _preprocess(img)
    h, w = img.shape[:2]
    head_roi = _head_roi_mask(h, w)
    segmentation_method = "vertex_standard"
    bald_u = np.zeros((h, w), dtype=np.uint8)
    thin_u = np.zeros((h, w), dtype=np.uint8)
    prob = None
    if use_cnn and cnn_model_path:
        prob = _cnn_raw_probability_map(image_bytes, cnn_model_path)
    if prob is not None:
        bald_u, thin_u = _split_bald_and_thin_from_prob(prob)
        segmentation_method = "cnn_bald_thin"
    else:
        _, bald_u, thin_u = _bald_thin_masks_opencv_vertex(img, head_roi)
        segmentation_method = "opencv_bald_thin"
    return bald_u, thin_u, segmentation_method


def process_scalp_image(
    image_bytes: bytes,
    use_cnn: bool = False,
    cnn_model_path: Optional[str] = None,
    return_overlay_base64: bool = True,
) -> Dict[str, Any]:
    """
    Full pipeline: load image -> preprocess -> bald detection (OpenCV or CNN) -> graft estimate.
    Returns dict with analysis + bald_area_pixels, bald_area_cm2, graft_min, graft_max, overlay_image_base64.
    """
    img = _bytes_to_image(image_bytes)
    img = _preprocess(img)
    h, w = img.shape[:2]
    total_pixels = h * w
    head_roi = _head_roi_mask(h, w)

    if _routing_prefer_frontal(img):
        return _process_frontal_scalp_image(
            img, return_overlay_base64, h, w, image_bytes, use_cnn, cnn_model_path
        )

    segmentation_method = "vertex_standard"
    bald_u = np.zeros((h, w), dtype=np.uint8)
    thin_u = np.zeros((h, w), dtype=np.uint8)
    prob = None
    if use_cnn and cnn_model_path:
        prob = _cnn_raw_probability_map(image_bytes, cnn_model_path)
    if prob is not None:
        bald_u, thin_u = _split_bald_and_thin_from_prob(prob)
        segmentation_method = "cnn_bald_thin"
    else:
        _, bald_u, thin_u = _bald_thin_masks_opencv_vertex(img, head_roi)
        segmentation_method = "opencv_bald_thin"

    mask_scalp = cv2.bitwise_or(bald_u, thin_u)
    _, mask_hair = _bald_area_mask_opencv(img)
    hair_region = cv2.bitwise_and(cv2.bitwise_not(mask_scalp), head_roi)
    hair_pixels = float(cv2.countNonZero(cv2.bitwise_and(mask_hair, hair_region)))

    hair_area_cm2 = round(hair_pixels / (PIXELS_PER_CM * PIXELS_PER_CM), 2)
    est_h_min, est_h_max, est_h_mid = _estimate_hair_count_from_hair_pixels(hair_pixels)

    bald_px = float(cv2.countNonZero(bald_u))
    thin_px = float(cv2.countNonZero(thin_u))
    effective_graft_px = bald_px + THIN_GRAFT_WEIGHT * thin_px
    graft_min, graft_max, area_cm2 = _estimate_grafts(effective_graft_px)
    bald_only_cm2 = round(bald_px / (PIXELS_PER_CM * PIXELS_PER_CM), 2)
    thin_only_cm2 = round(thin_px / (PIXELS_PER_CM * PIXELS_PER_CM), 2)

    bald_area_px, contours = _contours_to_area(mask_scalp)

    # Bald ratio (0-1): visible scalp-related area vs frame
    affected_px = bald_px + thin_px
    bald_ratio = affected_px / total_pixels if total_pixels > 0 else 0.0
    bald_ratio = min(1.0, bald_ratio)

    overlay_b64 = None
    if return_overlay_base64:
        overlay = img.copy()
        _draw_vertex_bald_thin_overlay(overlay, h, w, bald_u, thin_u)

        _, buf = cv2.imencode(".jpg", overlay)
        overlay_b64 = base64.b64encode(buf.tobytes()).decode("utf-8")

    return {
        "bald_area_pixels": round(bald_area_px, 0),
        "bald_area_cm2": area_cm2,
        "bald_only_cm2": bald_only_cm2,
        "thin_area_cm2": thin_only_cm2,
        "bald_ratio": round(bald_ratio, 4),
        "graft_min": graft_min,
        "graft_max": graft_max,
        "hair_area_cm2": hair_area_cm2,
        "estimated_hair_count_min": est_h_min,
        "estimated_hair_count_max": est_h_max,
        "estimated_hair_count": est_h_mid,
        "segmentation_method": segmentation_method,
        "overlay_image_base64": overlay_b64,
        "contour_count": len(contours),
        "view_orientation": "top",
    }


def _estimate_reliability_percent(
    opencv_result: Dict[str, Any],
    *,
    use_cnn: bool,
    use_trained_model: bool,
) -> int:
    """
    Heuristic 18–92: higher when CNN is used, trained regressor is on (top view), and
    segmentation is not wildly inconsistent. Not a statistical confidence interval.
    """
    seg = str(opencv_result.get("segmentation_method") or "").lower()
    score = 42
    if "cnn" in seg:
        score += 30
    elif use_cnn:
        score += 4  # requested but failed → small bump for intent only
    if use_trained_model and opencv_result.get("view_orientation") != "front":
        score += 12
    br = float(opencv_result.get("bald_ratio") or 0)
    gmax = int(opencv_result.get("graft_max") or 0)
    if br < 0.002 and gmax > 600:
        score -= 20
    if br > 0.95:
        score -= 12
    cc = float(opencv_result.get("contour_count") or 0)
    if cc > 10:
        score -= 10
    return int(np.clip(score, 18, 92))


def _derive_damage_and_fall_risk_from_evidence(
    image_bytes: bytes,
    opencv_result: Dict[str, Any],
    *,
    bald_ratio: float,
    graft_max: int,
    contour_penalty: float,
    graft_severity: float,
    is_front: bool,
) -> Tuple[float, float]:
    """
    Hair damage / fall risk as deterministic functions of segmentation, graft heuristics,
    visible hair area, and texture (edge / Laplacian) from the same photo — not random.
    """
    feats = _extract_ml_features(_preprocess(_bytes_to_image(image_bytes)))
    lap_var = float(feats[7])
    edge_ratio = float(feats[8])
    texture_stress = float(
        np.clip(edge_ratio * 1.12 + min(lap_var / 2600.0, 1.0) * 0.34, 0.0, 1.0)
    )

    hair_cm = float(opencv_result.get("hair_area_cm2") or 0.0)
    hair_vis = float(np.clip(hair_cm / 42.0, 0.0, 1.15))

    thin_cm = float(opencv_result.get("thin_area_cm2") or 0.0)
    bald_cm = float(opencv_result.get("bald_only_cm2") or 0.0)
    if is_front:
        thin_cm = 0.0
        bald_cm = float(opencv_result.get("bald_area_cm2") or 0.0)

    denom = thin_cm + bald_cm + 1e-6
    thin_share = float(thin_cm / denom) if denom > 1e-5 else 0.0

    hair_damage = (
        14.0
        + bald_ratio * 50.0
        + thin_share * 26.0
        + graft_severity * 16.0
        + texture_stress * 14.0
        - hair_vis * 20.0
    )
    hair_fall = (
        12.0
        + bald_ratio * 40.0
        + thin_share * 36.0
        + graft_severity * 14.0
        + contour_penalty * 1.05
        + (1.0 - hair_vis) * 24.0
    )
    if is_front:
        hair_damage += bald_ratio * 8.0
        hair_fall += bald_ratio * 10.0

    return (
        round(float(np.clip(hair_damage, 8.0, 98.0)), 1),
        round(float(np.clip(hair_fall, 8.0, 98.0)), 1),
    )


def _normalize_profile_gender(raw: Optional[str]) -> Optional[str]:
    """Account signup gender only (never inferred from the image). Returns male|female|other|None."""
    if raw is None:
        return None
    s = str(raw).strip().lower()
    if not s:
        return None
    if s in {"male", "m", "man"}:
        return "male"
    if s in {"female", "f", "woman"}:
        return "female"
    if s in {"others", "other", "prefer not to say", "non-binary", "nonbinary"}:
        return "other"
    return None


def _profile_gender_context_hint(pg: Optional[str], is_front: bool) -> Optional[str]:
    """Non-diagnostic UX hint tied to declared account gender + view (not a clinical label)."""
    if pg == "female":
        if is_front:
            return (
                "Profile: Female (from your account). For fuller crown context, you can add a parted "
                "top-of-head photo when convenient — scores here still use only this image."
            )
        return (
            "Profile: Female (from your account). Long hair can cover the vertex; parting or lifting "
            "hair at the crown often improves clarity for top-view photos next time."
        )
    if pg == "male":
        if is_front:
            return (
                "Profile: Male (from your account). Pairing a frontal view with a top-down crown photo "
                "(when possible) helps compare hairline vs vertex patterns."
            )
        return (
            "Profile: Male (from your account). A straight-on hairline photo can complement this crown "
            "view for overall pattern context."
        )
    if pg == "other":
        return "Profile gender is set on your account for context only; scores are computed from this scalp image."
    return None


def analyze_scalp_with_opencv(
    image_bytes: bytes,
    use_cnn: bool = False,
    cnn_model_path: Optional[str] = None,
    use_trained_model: bool = False,
    trained_model_path: Optional[str] = None,
    patient_profile_gender: Optional[str] = None,
    patient_profile_age: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Run OpenCV-based bald detection + graft estimate, then merge with existing
    hair strength/health metrics (simulated or from another model).
    """
    try:
        opencv_result = process_scalp_image(
            image_bytes,
            use_cnn=use_cnn,
            cnn_model_path=cnn_model_path,
            return_overlay_base64=True,
        )
    except Exception:
        opencv_result = {
            "bald_area_pixels": 0,
            "bald_area_cm2": 0.0,
            "bald_only_cm2": 0.0,
            "thin_area_cm2": 0.0,
            "bald_ratio": 0.0,
            "graft_min": 0,
            "graft_max": 0,
            "hair_area_cm2": 0.0,
            "estimated_hair_count_min": 0,
            "estimated_hair_count_max": 0,
            "estimated_hair_count": 0,
            "segmentation_method": "vertex_standard",
            "overlay_image_base64": None,
            "contour_count": 0,
            "view_orientation": "top",
            "analysis_summary": "Analysis unavailable for this image (pipeline error).",
        }

    bald_ratio = opencv_result.get("bald_ratio", 0.0) or 0.0
    graft_min = opencv_result.get("graft_min", 0) or 0
    graft_max = opencv_result.get("graft_max", 0) or 0
    old_bald_ratio = float(opencv_result.get("bald_ratio", 0.0) or 0.0)
    is_front = opencv_result.get("view_orientation") == "front"

    # Optional trained regressor adjusts bald ratio from dataset-learned signal.
    if use_trained_model and not is_front:
        try:
            reg = _load_bald_regressor(trained_model_path)
            if reg is not None:
                img = _bytes_to_image(image_bytes)
                feats = _extract_ml_features(img).reshape(1, -1)
                ml_ratio = float(np.clip(reg.predict(feats)[0], 0.0, 1.0))

                # Blend ML estimate with segmentation estimate for stable + image-specific output.
                bald_ratio = float(np.clip(0.65 * bald_ratio + 0.35 * ml_ratio, 0.0, 1.0))
                area_cm2 = float(opencv_result.get("bald_area_cm2", 0.0) or 0.0)
                if area_cm2 > 0:
                    scaled_area_cm2 = float(np.clip(area_cm2 * (0.7 + bald_ratio), 0.1, 500.0))
                    graft_min = int(scaled_area_cm2 * GRAFTS_PER_CM2_MIN)
                    graft_max = int(scaled_area_cm2 * GRAFTS_PER_CM2_MAX)
                    opencv_result["bald_area_cm2"] = round(scaled_area_cm2, 2)
                opencv_result["bald_ratio"] = round(bald_ratio, 4)
                opencv_result["graft_min"] = graft_min
                opencv_result["graft_max"] = graft_max
                new_br = float(opencv_result.get("bald_ratio", 0.0) or 0.0)
                scale = max(0.0, (1.0 - new_br)) / max(1e-6, (1.0 - old_bald_ratio))
                opencv_result["estimated_hair_count_min"] = int(
                    float(opencv_result.get("estimated_hair_count_min", 0)) * scale
                )
                opencv_result["estimated_hair_count_max"] = int(
                    float(opencv_result.get("estimated_hair_count_max", 0)) * scale
                )
                opencv_result["estimated_hair_count"] = (
                    opencv_result["estimated_hair_count_min"] + opencv_result["estimated_hair_count_max"]
                ) // 2
        except Exception:
            pass

    # Deterministic health metrics from observed analysis features only.
    # This removes random variance and keeps output tied to image evidence.
    contour_count = float(opencv_result.get("contour_count", 0) or 0)
    contour_penalty = min(10.0, contour_count * 1.5)
    graft_severity = min(1.0, (graft_max / 4000.0))

    hair_strength = round(float(np.clip(90 - bald_ratio * 55 - graft_severity * 10, 10, 100)), 1)
    scalp_health = round(float(np.clip(88 - bald_ratio * 50 - contour_penalty, 10, 100)), 1)
    hair_density = round(float(np.clip(92 - bald_ratio * 65 - graft_severity * 8, 10, 100)), 1)
    moisture_level = round(float(np.clip(65 - bald_ratio * 20, 10, 100)), 1)

    hair_damage_level, hair_fall_risk = _derive_damage_and_fall_risk_from_evidence(
        image_bytes,
        opencv_result,
        bald_ratio=float(bald_ratio),
        graft_max=int(graft_max),
        contour_penalty=contour_penalty,
        graft_severity=graft_severity,
        is_front=is_front,
    )

    # Conditions & recommendations vary by combined signals (ratio, graft range, cm2).
    conditions: List[str] = []
    recs: List[str] = []

    bald_cm = float(opencv_result.get("bald_only_cm2") or 0.0)
    thin_cm = float(opencv_result.get("thin_area_cm2") or 0.0)
    if is_front:
        affected_cm = max(bald_cm, float(opencv_result.get("bald_area_cm2") or 0.0) * 0.72) + 0.38 * thin_cm
    else:
        affected_cm = bald_cm + 0.42 * thin_cm

    # 0=mild, 1=early, 2=moderate-advanced, 3=severe. Use cm2 heavily: graft math can be low on some crops
    # while visible bald area is still large.
    if bald_ratio >= 0.28 or graft_max >= 2400 or affected_cm >= 40.0:
        scalp_tier = 3
    elif bald_ratio >= 0.15 or graft_max >= 1200 or affected_cm >= 20.0:
        scalp_tier = 2
    elif bald_ratio >= 0.065 or graft_max >= 480 or affected_cm >= 5.0:
        scalp_tier = 1
    else:
        scalp_tier = 0

    if is_front:
        conditions.append(
            "Frontal view: left/right temple recession zones detected and outlined organically (orange) based on AI analysis"
        )

    if scalp_tier == 0:
        conditions.append("Generally healthy scalp with minimal visible thinning in the analyzed region")
        recs.extend(
            [
                "Maintain a gentle, sulfate-free wash routine suited to your scalp type.",
                "Use lightweight natural oils (coconut, argan) 1-2 times per week if lengths feel dry.",
                "Continue 3-5 minute daily fingertip massage to support circulation (no diagnosis implied).",
            ]
        )
    elif scalp_tier == 1:
        conditions.append("Early thinning: increased scalp show-through versus dense hair in this photo")
        recs.extend(
            [
                "Introduce a hydrating scalp serum 2-3 times per week to reduce dryness and tightness.",
                "Use lukewarm water and a mild anti-hair-fall shampoo; avoid harsh daily surfactants.",
                "Discuss topical minoxidil or peptide options with a dermatologist before starting.",
                "Track shedding over 8-12 weeks with consistent lighting and angles for objective comparison.",
            ]
        )
    elif scalp_tier == 2:
        conditions.append("Moderate loss pattern: meaningful visible scalp area or graft estimate in this view")
        recs.extend(
            [
                "Book a trichoscopy or in-person hair consult to map miniaturization versus true density loss.",
                "Combine gentle cleansing with prescription-grade options (e.g. minoxidil) only under medical guidance.",
                "Reduce chemical relaxers/bleach overlap; space color services at least 3-4 weeks apart when possible.",
                "Add scalp SPF or a hat for outdoor UV when the crown is exposed.",
                "Sleep stress and protein intake both influence shedding; aim for consistent sleep timing.",
            ]
        )
    else:
        conditions.append("Advanced hair loss: large bare or near-bare scalp region detected in this view")
        conditions.append(
            "Restoration context: indicative graft range suggests substantial crown or vertex deficit on this frame"
        )
        recs.extend(
            [
                "Schedule a surgical candidacy visit to discuss FUE/FUT zones, donor density, and long-term medical therapy.",
                "Ask about combined medical management (e.g. clinician-directed minoxidil/finasteride) before any procedure.",
                "Avoid tight ponytails, braids, or extensions that add traction on remaining hairs.",
                "Protect exposed scalp from sunburn with SPF or breathable head cover during peak UV.",
                "Support healing nutrition: adequate protein, iron-rich foods, and hydration; discuss labs if fatigue is present.",
                "If rapid progression is new in months, rule out reversible causes (thyroid, iron, post-illness telogen effluvium) with a doctor.",
            ]
        )

    if float(moisture_level) < 35.0:
        recs.append(
            "If dryness or flaking is noticeable, add a weekly fragrance-free scalp-hydration step (not a substitute for medical care)."
        )

    # Always add at least one general recommendation.
    recs.append("Limit heat styling and always use a heat protectant spray when required.")

    note = (
        "Hair count is estimated from hair pixels in this photo; "
        "it reflects the visible region, not your full scalp."
    )
    if is_front:
        note = (
            "Front-facing photo: orange outlines mark the organically detected recession zones (automated overlay, not a diagnosis). "
            + note
        )
    elif not is_front and "bald_thin" in str(opencv_result.get("segmentation_method") or ""):
        note = (
            "Top/crown view: yellow-green tint = thinning (sparse hair); deeper orange = bald scalp. "
            "Grafts use a weighted mix of both zones. " + note
        )

    seg = str(opencv_result.get("segmentation_method") or "")
    reliability = _estimate_reliability_percent(
        opencv_result, use_cnn=use_cnn, use_trained_model=use_trained_model
    )
    estimate_disclaimer = (
        "Numbers are estimates from this single photo (angle, zoom, lighting affect area and graft math). "
        f"Heuristic model confidence ~{reliability}%. "
        "Reported accuracy is not a fixed percentage (e.g. 90-95%) without expert-labelled validation on diverse real-world photos. "
        "Not a diagnosis or treatment plan - confirm with a clinician."
    )
    if not is_front and opencv_result.get("thin_area_cm2") is not None:
        analysis_summary = (
            f"Crown (top) view. Mode: {seg}. "
            f"Bald ~{opencv_result.get('bald_only_cm2', 0)} cm², thinning ~{opencv_result.get('thin_area_cm2', 0)} cm² "
            f"(graft-equivalent ~{opencv_result.get('bald_area_cm2', 0)} cm²). "
            f"Grafts {graft_min}-{graft_max}. "
            f"Scores - strength {hair_strength}%, density {hair_density}%."
        )
    else:
        analysis_summary = (
            f"{'Hairline (front)' if is_front else 'Crown (top)'} view. "
            f"Mode: {seg}. "
            f"Bald area ~{opencv_result.get('bald_area_cm2', 0)} cm². "
            f"Indicative graft range {graft_min}-{graft_max}. "
            f"Scores - strength {hair_strength}%, density {hair_density}%."
        )

    pg = _normalize_profile_gender(patient_profile_gender)
    if patient_profile_gender and str(patient_profile_gender).strip():
        label = str(patient_profile_gender).strip()
        analysis_summary = (
            f"{analysis_summary} Account profile: {label} (from signup — not inferred from this photo)."
        )
    if patient_profile_age is not None and 1 <= int(patient_profile_age) < 120:
        analysis_summary = f"{analysis_summary} Age on profile: {int(patient_profile_age)}."

    recs_out = list(recs)
    hint = _profile_gender_context_hint(pg, is_front)
    if hint and hint not in recs_out:
        recs_out.insert(0, hint)
    recs_final = recs_out[:12]

    out: Dict[str, Any] = {
        **opencv_result,
        "hair_strength": hair_strength,
        "scalp_health": scalp_health,
        "hair_density": hair_density,
        "moisture_level": moisture_level,
        "hair_damage_level": hair_damage_level,
        "hair_fall_risk": hair_fall_risk,
        "conditions": conditions,
        "recommendations": recs_final,
        "hair_count_note": note,
        "analysis_summary": analysis_summary,
        "estimate_reliability_percent": reliability,
        "estimate_disclaimer": estimate_disclaimer,
    }
    if patient_profile_gender and str(patient_profile_gender).strip():
        out["patient_profile_gender"] = str(patient_profile_gender).strip()
    if pg:
        out["patient_profile_gender_normalized"] = pg
    if patient_profile_age is not None and 1 <= int(patient_profile_age) < 120:
        out["patient_profile_age"] = int(patient_profile_age)
    out["patient_profile_source"] = "user_account_signup"
    return out
