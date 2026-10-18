"""Relative pothole depth from a single photo, using Depth Anything V2.

The depth model returns *inverse* depth for every pixel (larger = closer to the camera),
correct only up to an unknown scale and shift. So nothing here is in centimetres. What can
be measured is how far a pothole's floor sits behind the road surface around it, as a
fraction of the distance to that surface. That is the "depth index" this module produces.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger("uvicorn.error")

DEFAULT_DEPTH_MODEL_DIR = Path(__file__).resolve().parent.parent / "models" / "depth"
DEPTH_MODEL_REPO = "depth-anything/Depth-Anything-V2-Small-hf"

# How far the ring of "surrounding road" extends beyond the box, as a fraction of box size.
_RING_MARGIN = 0.35
# Fewer ring pixels than this and the road plane cannot be fitted reliably.
_MIN_RING_PIXELS = 200

# Water check: the image is shrunk to this size, a pixel is "smooth" below this local standard
# deviation (grey levels 0-255), and a box is wet when this share of its middle is smooth.
_WATER_WORK_SIZE = 640.0
_WATER_MAX_STD = 3.0
_WATER_MIN_FRACTION = 0.10

Box = tuple[float, float, float, float]

_SEVERITIES = ("Not Severe", "Neutral", "Severe")


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    return float(raw) if raw else default


# Depth index at which a pothole counts as Neutral / Severe whatever its box size.
# Starting values read off a handful of photos, not calibrated against measured potholes.
DEPTH_NEUTRAL = _env_float("POTHOLE_DEPTH_NEUTRAL", 0.04)
DEPTH_SEVERE = _env_float("POTHOLE_DEPTH_SEVERE", 0.10)


def severity_with_depth(box_severity: str, index: float | None) -> str:
    """The severity from box size, raised when the measured depth calls for a higher one.

    Depth only ever raises severity. A pothole whose depth could not be measured (``index`` is
    None, which includes water-filled ones) keeps the severity its box size gave it.
    """
    if index is None or box_severity not in _SEVERITIES:
        return box_severity
    depth_rank = 2 if index >= DEPTH_SEVERE else 1 if index >= DEPTH_NEUTRAL else 0
    return _SEVERITIES[max(_SEVERITIES.index(box_severity), depth_rank)]


@lru_cache(maxsize=1)
def _load():
    import torch
    from transformers import AutoImageProcessor, AutoModelForDepthEstimation

    source = os.getenv("POTHOLE_DEPTH_MODEL", "").strip() or str(DEFAULT_DEPTH_MODEL_DIR)
    if not Path(source).is_dir():
        raise RuntimeError(
            f"Depth model not found at {source}. Run `python scripts/download_model.py`."
        )
    processor = AutoImageProcessor.from_pretrained(source)
    model = AutoModelForDepthEstimation.from_pretrained(source)
    model.eval()
    return processor, model, torch


def load_depth_model() -> None:
    """Loads the model now, so the first report doesn't pay for it. Raises if unavailable."""
    _load()


def estimate_inverse_depth(pil_img: Image.Image) -> np.ndarray:
    """Per-pixel inverse depth at the photo's own resolution (float32, larger = closer)."""
    processor, model, torch = _load()
    inputs = processor(images=pil_img.convert("RGB"), return_tensors="pt")
    with torch.no_grad():
        predicted = model(**inputs).predicted_depth
    width, height = pil_img.size
    resized = torch.nn.functional.interpolate(
        predicted.unsqueeze(1), size=(height, width), mode="bicubic", align_corners=False
    )
    return resized.squeeze().cpu().numpy().astype(np.float32)


def depth_index(inverse_depth: np.ndarray, box: Box, other_boxes: list[Box] = ()) -> float | None:
    """How deep the region in ``box`` is relative to the road around it, from 0 (flat) upwards.

    A flat road seen in perspective has inverse depth that changes linearly across the image,
    so the road surface is modelled as a plane fitted to a ring of pixels just outside the box.
    Inside the box, pixels that are further away than that plane belong to the hole. The index
    is that extra distance (in inverse-depth units) divided by the plane's own value, which
    makes it independent of how close the camera was.

    Returns None when there is too little surrounding road to fit the plane.
    """
    h, w = inverse_depth.shape
    x1, y1, x2, y2 = (int(round(v)) for v in box)
    x1, x2 = max(0, x1), min(w, x2)
    y1, y2 = max(0, y1), min(h, y2)
    if x2 - x1 < 4 or y2 - y1 < 4:
        return None

    mx, my = int((x2 - x1) * _RING_MARGIN), int((y2 - y1) * _RING_MARGIN)
    rx1, rx2 = max(0, x1 - mx), min(w, x2 + mx)
    ry1, ry2 = max(0, y1 - my), min(h, y2 + my)

    # Ring = expanded box minus every detected pothole, so only road surface is left.
    ring = np.ones((ry2 - ry1, rx2 - rx1), dtype=bool)
    for bx1, by1, bx2, by2 in [box, *other_boxes]:
        cx1, cx2 = max(rx1, int(bx1)) - rx1, min(rx2, int(np.ceil(bx2))) - rx1
        cy1, cy2 = max(ry1, int(by1)) - ry1, min(ry2, int(np.ceil(by2))) - ry1
        if cx2 > cx1 and cy2 > cy1:
            ring[cy1:cy2, cx1:cx2] = False
    if int(ring.sum()) < _MIN_RING_PIXELS:
        return None

    ys, xs = np.nonzero(ring)
    values = inverse_depth[ry1:ry2, rx1:rx2][ring]
    design = np.column_stack([xs + rx1, ys + ry1, np.ones_like(xs)]).astype(np.float64)
    coeffs, *_ = np.linalg.lstsq(design, values.astype(np.float64), rcond=None)

    grid_y, grid_x = np.mgrid[y1:y2, x1:x2]
    plane = coeffs[0] * grid_x + coeffs[1] * grid_y + coeffs[2]
    reference = float(np.median(plane))
    if reference <= 1e-6:
        return None

    # Positive where the surface is further away than the road plane, i.e. below it.
    below = plane - inverse_depth[y1:y2, x1:x2]
    # The 90th percentile tracks the deepest part without being thrown by a few stray pixels.
    deepest = float(np.percentile(below, 90))
    return max(0.0, deepest / reference)


def find_water(pil_img: Image.Image, boxes: list[Box]) -> list[bool]:
    """For each box, whether the pothole looks filled with water.

    Standing water is smooth, while a dry pothole floor is rough gravel, so a box counts as wet
    when enough of its middle has almost no local texture. The depth model reads a water surface
    and its reflections as a deep hole, so depth must not be trusted for these.

    The cut-offs were chosen on about twenty photos. Reflections with detail in them (trees,
    buildings) and dark muddy water can be missed.
    """
    gray = np.asarray(pil_img.convert("L"), dtype=np.float32)
    # Texture is measured at a fixed working size so the result does not depend on resolution.
    scale = _WATER_WORK_SIZE / max(gray.shape)
    gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    mean = cv2.blur(gray, (7, 7))
    local_std = np.sqrt(np.maximum(cv2.blur(gray * gray, (7, 7)) - mean * mean, 0.0))

    wet = []
    for box in boxes:
        x1, y1, x2, y2 = (int(v * scale) for v in box)
        # The middle of the box, leaving out the broken edge of the pothole.
        mx, my = (x2 - x1) // 5, (y2 - y1) // 5
        middle = local_std[y1 + my : y2 - my, x1 + mx : x2 - mx]
        wet.append(middle.size > 0 and float((middle < _WATER_MAX_STD).mean()) >= _WATER_MIN_FRACTION)
    return wet


def depth_heatmap(inverse_depth: np.ndarray) -> np.ndarray:
    """BGR visualisation of the depth map (bright = close), for debugging."""
    lo, hi = float(inverse_depth.min()), float(inverse_depth.max())
    scaled = ((inverse_depth - lo) / max(hi - lo, 1e-6) * 255).astype(np.uint8)
    return cv2.applyColorMap(scaled, cv2.COLORMAP_INFERNO)
