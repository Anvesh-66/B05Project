from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Detection:
    class_id: int
    class_name: str
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float
    severity: str = "Neutral"
    # Relative depth from pothole.depth (0 = flat); None when it could not be measured.
    depth_index: float | None = None
    # The pothole looks filled with water, so its depth was not measured.
    has_water: bool = False
