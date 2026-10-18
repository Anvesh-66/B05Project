from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return float(raw)


def _env_str(name: str, default: str) -> str:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return raw


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


@dataclass(frozen=True)
class Settings:
    model_path: str
    device: str
    conf: float
    iou: float
    class_name: str
    allow_any_class: bool


# Where scripts/download_model.py saves the pretrained weights.
DEFAULT_MODEL_PATH = Path(__file__).resolve().parent.parent / "models" / "pothole" / "best.pt"


def get_settings() -> Settings:
    model_path = os.getenv("POTHOLE_MODEL_PATH", "").strip() or str(DEFAULT_MODEL_PATH)
    if not Path(model_path).is_file():
        raise RuntimeError(
            f"Model weights not found at {model_path}. Run `python scripts/download_model.py` "
            "or set POTHOLE_MODEL_PATH to a YOLO weights file."
        )

    return Settings(
        model_path=model_path,
        device=_env_str("POTHOLE_DEVICE", "cpu"),
        conf=_env_float("POTHOLE_CONF", 0.25),
        iou=_env_float("POTHOLE_IOU", 0.45),
        class_name=_env_str("POTHOLE_CLASS_NAME", "pothole"),
        allow_any_class=_env_bool("POTHOLE_ALLOW_ANY_CLASS", False),
    )
