$ErrorActionPreference = "Stop"

if (!(Test-Path ".\.venv\Scripts\Activate.ps1")) {
  throw "Missing .venv. Run: python -m venv .venv"
}

.\.venv\Scripts\Activate.ps1

if (-not $env:POTHOLE_MODEL_PATH -and !(Test-Path ".\models\pothole\best.pt")) {
  throw "No model weights. Run: python scripts\download_model.py (or set POTHOLE_MODEL_PATH)."
}

uvicorn backend.main:app --host 0.0.0.0 --port 8000
