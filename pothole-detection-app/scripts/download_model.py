from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pothole.config import DEFAULT_MODEL_PATH  # noqa: E402
from pothole.depth import DEFAULT_DEPTH_MODEL_DIR, DEPTH_MODEL_REPO  # noqa: E402

# Pretrained YOLOv8m pothole detector (single class: "pothole", Apache-2.0).
# .pt files are pickles and run code when loaded, so only use repos you trust.
DEFAULT_REPO = "Logesshhh/road-anomaly-pothole-yolov8m"
DEFAULT_FILE = "potbot_yolov8m.pt"

# Depth Anything V2 Small (Apache-2.0); stored as safetensors, which cannot run code.
DEPTH_FILES = ["config.json", "preprocessor_config.json", "model.safetensors"]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download the pretrained pothole detector and the depth model from Hugging Face."
    )
    parser.add_argument("--repo", default=DEFAULT_REPO, help="Hugging Face repo of the pothole detector.")
    parser.add_argument("--file", default=DEFAULT_FILE, help="Weights filename inside that repo.")
    parser.add_argument("--out", default=str(DEFAULT_MODEL_PATH), help="Where to save the detector weights.")
    parser.add_argument("--skip-depth", action="store_true", help="Do not download the depth model.")
    args = parser.parse_args()

    from huggingface_hub import hf_hub_download

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    cached = hf_hub_download(repo_id=args.repo, filename=args.file)
    shutil.copyfile(cached, out)
    print(f"Saved {args.repo}/{args.file} to {out} ({out.stat().st_size / 1e6:.1f} MB)")

    if not args.skip_depth:
        DEFAULT_DEPTH_MODEL_DIR.mkdir(parents=True, exist_ok=True)
        for name in DEPTH_FILES:
            shutil.copyfile(hf_hub_download(repo_id=DEPTH_MODEL_REPO, filename=name), DEFAULT_DEPTH_MODEL_DIR / name)
        size = sum(f.stat().st_size for f in DEFAULT_DEPTH_MODEL_DIR.iterdir()) / 1e6
        print(f"Saved {DEPTH_MODEL_REPO} to {DEFAULT_DEPTH_MODEL_DIR} ({size:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
