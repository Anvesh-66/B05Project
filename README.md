# Pothole Detection Backend

FastAPI server for the pothole reporting app:

- **Detects** potholes in uploaded photos with a pretrained YOLOv8 model
- **Stores** each report (photo, detections, severity, location, status) in SQLite
- **Authenticates** users with hashed passwords and bearer tokens
- **Provides** the API used by the admin panel in `../pothole-admin-panel/`

The mobile client is the Flutter app in `../pothole-flutter-app/`.

## 1) Install

Needs Python 3.10 or newer.

```powershell
cd pothole-detection-app
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## 2) Download the model

```powershell
python scripts\download_model.py
```

This saves the pretrained detector `potbot_yolov8m.pt` (YOLOv8m, single class `pothole`, Apache-2.0) from
[Logesshhh/road-anomaly-pothole-yolov8m](https://huggingface.co/Logesshhh/road-anomaly-pothole-yolov8m)
to `models\pothole\best.pt`, which the server loads by default.

## 3) Create an admin account

```powershell
python scripts\create_admin.py --email you@example.com --name "Your Name"
```

It asks for a password. If the email already belongs to an account, that account is promoted to admin instead.
Accounts created through the app are always normal users.

## 4) Run

```powershell
.\scripts\run_backend.ps1
```

or `uvicorn backend.main:app --host 0.0.0.0 --port 8000`.

- Admin panel: a separate Next.js app, see `../pothole-admin-panel/`
- API docs: <http://127.0.0.1:8000/docs>
- Health: <http://127.0.0.1:8000/health> (`model_loaded` shows whether the weights loaded)

## API

All endpoints except register, login and health need an `Authorization: Bearer <token>` header.

| Method | Path | Who | What |
|---|---|---|---|
| POST | `/auth/register` | anyone | Create a user account, returns a token |
| POST | `/auth/login` | anyone | Returns a token |
| GET | `/auth/me` | signed in | Current account |
| POST | `/detect` | signed in | Analyse a photo (`file`, optional `conf`, `iou`, `latitude`, `longitude`). Keeps the result as a private **draft** for the reporter to review; returns `{"report": null}` if no pothole is found |
| POST | `/reports/{id}/submit` | owner | Turn a draft into a real report |
| POST | `/reports` | signed in | Analyse and submit in one step, with no review. Same fields as `/detect` |
| GET | `/reports` | signed in | Own reports; admins get everyone's. Filters: `status`, `risk`, `q`, `order`, `located`, `limit`, `offset` |
| GET | `/reports/{id}` | owner or admin | One report with its detections |
| GET | `/reports/{id}/image` | owner or admin | Photo; `kind=annotated` (default) or `original` |
| PATCH | `/reports/{id}` | admin | Set `status`: `pending`, `in_review` or `resolved` |
| DELETE | `/reports/{id}` | admin, or owner of a draft | Delete a report and its photos |
| GET | `/stats` | signed in | Report counts (own, or all for admins) |
| GET | `/potholes` | signed in | Every submitted report, for the map and lists. No reporter and no photo |
| GET | `/potholes/nearby` | signed in | Unresolved potholes within `radius` metres of `lat`, `lng`, most severe first then nearest. `major_only=true` leaves out low severity |
| GET | `/potholes/{id}` | signed in | One pothole |
| GET | `/dashboard` | signed in | Totals, severity split, reports per day for the last week, and the five areas with the most reports |

A draft is visible only to its owner, is never listed or counted, and is deleted after 24 hours if not submitted.

Reports with coordinates get a street and area name from OpenStreetMap (Nominatim) when they are created.
The lookup is best-effort: if it is slow or fails, the report is saved with coordinates only.

Severity per pothole starts from how much of the photo its box covers, so it depends on how close the camera was.
When depth can be measured it can raise that severity; a pothole that looks water-filled keeps the box-size severity.
Risk per report is `HIGH` with two or more severe potholes, `MED` with one severe or three or more potholes, otherwise `LOW`.

## Data

Everything the server writes lives in `var/` (ignored by git):

- `var/pothole.db`: SQLite database (tables `user`, `report`, `detection`)
- `var/uploads/`: original and annotated photos
- `var/secret.key`: token signing key, generated on first run

Delete `var/` to start from an empty database. Back it up to keep your data.

## Configuration

Environment variables, all optional:

- `POTHOLE_MODEL_PATH`: path to `.pt` weights (default `models/pothole/best.pt`)
- `POTHOLE_DATA_DIR`: where the database and uploads go (default `var/`)
- `POTHOLE_SECRET_KEY`: token signing key (default: generated and saved in the data dir)
- `POTHOLE_DEVICE`: `cpu`, `0`, `0,1` (default `cpu`)
- `POTHOLE_CONF`: default confidence threshold (default `0.25`)
- `POTHOLE_IOU`: default IoU threshold (default `0.45`)
- `POTHOLE_CLASS_NAME`: model class treated as a pothole (default `pothole`)
- `POTHOLE_ALLOW_ANY_CLASS`: set to `1` to keep every class the model returns
- `POTHOLE_DEPTH_MODEL`: folder of the depth model (default `models/depth`)
- `POTHOLE_DEPTH_NEUTRAL`, `POTHOLE_DEPTH_SEVERE`: depth index at which a pothole counts as at least Neutral / Severe (defaults `0.04`, `0.10`)
- `POTHOLE_GEOCODE`: set to `0` to skip the address lookup

## Tests

```powershell
pip install -r requirements-dev.txt
python -m pytest tests
```

The tests replace the model with a stub and use a temporary database.

## Layout

```
backend/
  main.py            Routes
  auth.py            Password hashing, tokens, access checks
  db.py              Tables and database session
  schemas.py         Request and response shapes
pothole/             Model loading, inference, drawing boxes
scripts/             download_model.py, create_admin.py, run_backend.ps1
tests/               API tests
```

## Before putting this on the internet

It is built to run on a local network. For a public deployment, add HTTPS, rate limiting on login and
registration, and a fixed `POTHOLE_SECRET_KEY`.

