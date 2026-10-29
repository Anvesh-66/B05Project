from __future__ import annotations

import logging
import math
import threading
import uuid
from contextlib import asynccontextmanager
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, UnidentifiedImageError
from sqlalchemy import and_, false, func, or_, true
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

# Load environment variables from .env file
load_dotenv(Path(__file__).parent.parent / ".env")

from backend.auth import authenticate, create_token, current_user, hash_password, require_admin
from backend.db import UPLOAD_DIR, DetectionRecord, Report, User, engine, get_session, init_db, utcnow
from backend.email_service import send_report_submitted_email, send_status_changed_email
from backend.geocode import reverse_geocode
from backend.location_analysis import calculate_aggregated_severity, find_nearby_reports, get_location_cluster_info
from backend.priority_scoring import calculate_priority_score, get_sample_critical_locations
from backend.weather_service import adjust_risk_for_weather, get_weather_data
from backend.schemas import (
    AreaCount,
    DashboardOut,
    DayCount,
    DetectionOut,
    LoginRequest,
    NearbyPothole,
    PotholeOut,
    RegisterRequest,
    ReportDetail,
    ReportStatus,
    ReportSummary,
    RiskLevel,
    StatsOut,
    StatusUpdate,
    SubmitResponse,
    TokenResponse,
    UserOut,
)
from pothole.depth import (
    depth_index,
    estimate_inverse_depth,
    find_water,
    load_depth_model,
    severity_with_depth,
)
from pothole.inference import draw_detections, load_image_bytes, predict_from_pil
from pothole.model import get_model
from pothole.types import Detection

logger = logging.getLogger("uvicorn.error")

_MAX_UPLOAD_BYTES = 15 * 1024 * 1024
# A draft the reporter never confirmed is removed after this long.
_DRAFT_LIFETIME = timedelta(hours=24)
_EARTH_RADIUS_M = 6_371_000

_model_loaded = False
_depth_loaded = False
# Ultralytics models are not safe to call from several threads at once.
_predict_lock = threading.Lock()


@asynccontextmanager
async def lifespan(_: FastAPI):
    global _model_loaded, _depth_loaded
    init_db()
    with Session(engine) as session:
        stale = select(Report).where(Report.submitted.is_(False), Report.created_at < utcnow() - _DRAFT_LIFETIME)
        for draft in session.exec(stale).all():
            _delete_report(session, draft)
    try:
        _, settings, names = get_model()
        _model_loaded = True
        logger.info("Loaded model %s with classes %s", settings.model_path, list(names.values()))
    except Exception:
        logger.exception("Could not load the YOLO model; report submission will return 503")
    try:
        load_depth_model()
        _depth_loaded = True
        logger.info("Loaded depth model")
    except Exception as e:
        # Depth is an extra: reports still work without it, just with no depth index.
        logger.warning("Depth estimation is off: %s", e)
    yield


app = FastAPI(title="Pothole Detection API", version="0.4.0", lifespan=lifespan)


# ---------- helpers ----------


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _user_out(user: User) -> UserOut:
    return UserOut(id=user.id, name=user.name, email=user.email, role=user.role)


def _summary_fields(report: Report, reporter: User) -> dict:
    return {
        "id": report.id,
        "status": report.status,
        "risk": report.risk,
        "detection_count": report.detection_count,
        "severe_count": report.severe_count,
        "confidence": report.top_confidence,
        "latitude": report.latitude,
        "longitude": report.longitude,
        "address": report.address,
        "area": report.area,
        "submitted": report.submitted,
        "created_at": _iso(report.created_at),
        "resolved_at": _iso(report.resolved_at),
        "reporter_name": reporter.name,
        "reporter_email": reporter.email,
    }


def _detail(session: Session, report: Report, reporter: User) -> ReportDetail:
    rows = session.exec(
        select(DetectionRecord).where(DetectionRecord.report_id == report.id).order_by(DetectionRecord.id)
    ).all()
    return ReportDetail(
        **_summary_fields(report, reporter),
        detections=[DetectionOut.model_validate(r, from_attributes=True) for r in rows],
    )


def _visible_to(user: User):
    """Submitted reports: admins see every one; everyone else sees only their own."""
    mine = true() if user.role == "admin" else Report.user_id == user.id
    return and_(Report.submitted.is_(True), mine)


def _get_report(session: Session, report_id: int, user: User) -> Report:
    report = session.get(Report, report_id)
    # Someone else's report looks the same as a missing one. A draft belongs to its owner alone.
    allowed = report is not None and (
        report.user_id == user.id or (user.role == "admin" and report.submitted)
    )
    if not allowed:
        raise HTTPException(status_code=404, detail="Report not found.")
    return report


def _delete_report(session: Session, report: Report) -> None:
    files = [UPLOAD_DIR / report.image_file, UPLOAD_DIR / report.annotated_file]
    for row in session.exec(select(DetectionRecord).where(DetectionRecord.report_id == report.id)).all():
        session.delete(row)
    session.delete(report)
    session.commit()
    for path in files:
        path.unlink(missing_ok=True)


def _pothole_fields(report: Report, user: User) -> dict:
    return {
        "id": report.id,
        "severity": report.risk,
        "confidence": report.top_confidence,
        "detection_count": report.detection_count,
        "status": report.status,
        "latitude": report.latitude,
        "longitude": report.longitude,
        "address": report.address,
        "area": report.area,
        "created_at": _iso(report.created_at),
        "resolved_at": _iso(report.resolved_at),
        "mine": report.user_id == user.id,
    }


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two points, by the haversine formula."""
    d_lat, d_lng = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    h = math.sin(d_lat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    return 2 * _EARTH_RADIUS_M * math.asin(math.sqrt(h))


def _risk(detections: list[Detection]) -> tuple[int, str]:
    """Calculate overall risk level based on severe potholes and total count.
    
    Enhanced Risk Classification:
    - HIGH: 1+ severe potholes OR 3+ total potholes
    - MED: 1+ neutral potholes OR 2 total potholes (non-severe)
    - LOW: Only "Not Severe" detections AND single pothole
    
    Logic: If ANY pothole is marked as "Severe" by the model, the overall risk is HIGH.
    This ensures that severe detections are taken seriously.
    """
    severe = sum(1 for d in detections if d.severity == "Severe")
    neutral = sum(1 for d in detections if d.severity == "Neutral")
    total = len(detections)
    
    # HIGH risk: Any severe pothole detected OR many potholes
    if severe >= 1 or total >= 3:
        return severe, "HIGH"
    
    # MEDIUM risk: Neutral potholes OR multiple non-severe potholes
    if neutral >= 1 or total >= 2:
        return severe, "MED"
    
    # LOW risk: Single "Not Severe" pothole only
    return severe, "LOW"


def _detect(file: UploadFile, conf: float | None, iou: float | None) -> tuple[Image.Image, list[Detection]]:
    image_bytes = file.file.read(_MAX_UPLOAD_BYTES + 1)
    if len(image_bytes) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Image is too large (limit 15 MB).")
    try:
        pil_img = load_image_bytes(image_bytes)
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as e:
        raise HTTPException(status_code=400, detail="The uploaded file is not a valid image.") from e

    try:
        with _predict_lock:
            return pil_img, predict_from_pil(pil_img, conf=conf, iou=iou)
    except Exception:
        logger.exception("YOLO prediction failed")
        raise HTTPException(
            status_code=503,
            detail="The detection model is not available. Check the model weights on the server.",
        ) from None


def _with_depth(pil_img: Image.Image, detections: list[Detection]) -> list[Detection]:
    """Adds depth index to detections and enhances severity based on depth.

    Process:
    1. Initial severity comes from confidence (>0.50 = Severe)
    2. Depth estimation provides depth_index for each pothole
    3. Depth can RAISE severity but never lower it
    4. Water-filled potholes skip depth (misleads depth model)
    
    Depth thresholds (configurable):
    - depth_index >= 0.10 → Severe
    - depth_index >= 0.04 → Neutral
    - depth_index < 0.04 → No change
    
    Returns detections with enhanced severity and depth data.
    """
    if not _depth_loaded:
        logger.info("Depth model not loaded - using confidence-based severity only")
        return detections
    try:
        with _predict_lock:
            inverse_depth = estimate_inverse_depth(pil_img)
        boxes = [(d.x1, d.y1, d.x2, d.y2) for d in detections]
        measured = []
        for i, (d, box, wet) in enumerate(zip(detections, boxes, find_water(pil_img, boxes), strict=True)):
            if wet:
                measured.append(replace(d, has_water=True))
                logger.debug("Detection %d: Water-filled, depth skipped, severity: %s", i, d.severity)
                continue
            index = depth_index(inverse_depth, box, boxes[:i] + boxes[i + 1 :])
            enhanced_severity = severity_with_depth(d.severity, index)
            if enhanced_severity != d.severity and index is not None:
                logger.info(
                    "Detection %d: Depth %.3f raised severity %s → %s",
                    i, index, d.severity, enhanced_severity
                )
            measured.append(replace(d, depth_index=index, severity=enhanced_severity))
        return measured
    except Exception:
        logger.exception("Depth estimation failed; saving the report without depth")
        return detections


# ---------- health ----------


@app.get("/health")
def health() -> dict[str, str | bool]:
    return {"status": "ok", "model_loaded": _model_loaded, "depth_loaded": _depth_loaded}


# ---------- auth ----------


@app.post("/auth/register", response_model=TokenResponse, status_code=201)
def register(req: RegisterRequest, session: Session = Depends(get_session)) -> TokenResponse:
    user = User(
        name=req.name.strip(),
        email=req.email.strip().lower(),
        password_hash=hash_password(req.password),
    )
    session.add(user)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="An account with this email already exists.") from None
    session.refresh(user)
    return TokenResponse(access_token=create_token(user), user=_user_out(user))


@app.post("/auth/login", response_model=TokenResponse)
def login(req: LoginRequest, session: Session = Depends(get_session)) -> TokenResponse:
    found = session.exec(select(User).where(User.email == req.email.strip().lower())).first()
    user = authenticate(found, req.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Incorrect email or password.")
    return TokenResponse(access_token=create_token(user), user=_user_out(user))


@app.get("/auth/me", response_model=UserOut)
def me(user: User = Depends(current_user)) -> UserOut:
    return _user_out(user)


# ---------- reports ----------


def _analyse_and_save(
    session: Session,
    user: User,
    file: UploadFile,
    conf: float | None,
    iou: float | None,
    latitude: float | None,
    longitude: float | None,
    *,
    submitted: bool,
) -> SubmitResponse:
    if (latitude is None) != (longitude is None):
        raise HTTPException(status_code=422, detail="Send both latitude and longitude, or neither.")
    pil_img, detections = _detect(file, conf, iou)
    if not detections:
        return SubmitResponse(report=None)
    detections = _with_depth(pil_img, detections)
    address, area = reverse_geocode(latitude, longitude) if latitude is not None else (None, None)

    # Re-encoding drops EXIF metadata and guarantees the stored file is a plain JPEG.
    stem = uuid.uuid4().hex
    image_file, annotated_file = f"{stem}.jpg", f"{stem}_annotated.jpg"
    pil_img.save(UPLOAD_DIR / image_file, format="JPEG", quality=90)
    (UPLOAD_DIR / annotated_file).write_bytes(draw_detections(pil_img, detections, ext=".jpg"))

    severe_count, risk = _risk(detections)
    
    # Multi-angle analysis: Check for nearby reports
    nearby_count = 0
    is_worsening = False
    if latitude is not None and longitude is not None:
        nearby_reports = find_nearby_reports(session, latitude, longitude, days_back=30)
        nearby_count = len(nearby_reports)
        if nearby_reports:
            agg_data = calculate_aggregated_severity(nearby_reports)
            is_worsening = agg_data.get("is_worsening", False)
            logger.info(
                "Location has %d nearby reports (cluster analysis: %s risk, %s)",
                nearby_count,
                agg_data.get("aggregated_risk"),
                "worsening" if is_worsening else "stable",
            )
    
    # Weather integration: Adjust risk based on current weather
    adjusted_risk, weather_info = adjust_risk_for_weather(risk, latitude, longitude)
    weather_adjusted = adjusted_risk != risk
    if weather_adjusted:
        logger.info("Risk adjusted %s → %s due to weather: %s", risk, adjusted_risk, weather_info.get("warning_message"))
    risk = adjusted_risk
    
    # Priority scoring: Calculate comprehensive priority
    critical_locs = get_sample_critical_locations() if latitude and longitude else None
    priority_data = calculate_priority_score(
        risk=risk,
        severe_count=severe_count,
        detection_count=len(detections),
        latitude=latitude,
        longitude=longitude,
        critical_locations=critical_locs,
        road_type=area,  # Use area as proxy for road type
        report_count=nearby_count + 1,  # Include this report
        is_worsening=is_worsening,
        weather_multiplier=weather_info.get("severity_multiplier", 1.0),
    )
    
    logger.info(
        "Priority score: %.2f (%s) - Base: %d, Location: %.2fx, Weather: %.2fx, Reports: %d",
        priority_data["priority_score"],
        priority_data["priority_level"],
        priority_data["breakdown"]["base_score"],
        priority_data["breakdown"]["location_multiplier"],
        priority_data["breakdown"]["weather_multiplier"],
        nearby_count + 1,
    )
    
    report = Report(
        user_id=user.id,
        image_file=image_file,
        annotated_file=annotated_file,
        latitude=latitude,
        longitude=longitude,
        address=address,
        area=area,
        detection_count=len(detections),
        severe_count=severe_count,
        risk=risk,
        top_confidence=max(d.confidence for d in detections),
        submitted=submitted,
        priority_score=priority_data["priority_score"],
        priority_level=priority_data["priority_level"],
        weather_adjusted=weather_adjusted,
        nearby_reports_count=nearby_count,
    )
    session.add(report)
    session.flush()
    session.add_all(
        DetectionRecord(
            report_id=report.id,
            class_name=d.class_name,
            confidence=d.confidence,
            severity=d.severity,
            x1=d.x1,
            y1=d.y1,
            x2=d.x2,
            y2=d.y2,
            depth_index=d.depth_index,
            has_water=d.has_water,
        )
        for d in detections
    )
    session.commit()
    session.refresh(report)
    
    # Send confirmation email if report is submitted (not a draft)
    if submitted:
        send_report_submitted_email(
            to_email=user.email,
            user_name=user.name,
            report_id=report.id,
            detection_count=report.detection_count,
            severe_count=severe_count,
            risk=risk,
            address=address,
            area=area,
            created_at=_iso(report.created_at) or "",
        )
    
    return SubmitResponse(report=_detail(session, report, user))


@app.post("/detect", response_model=SubmitResponse)
def detect(
    file: UploadFile = File(...),
    conf: float | None = Form(None, ge=0.0, le=1.0),
    iou: float | None = Form(None, ge=0.0, le=1.0),
    latitude: float | None = Form(None, ge=-90.0, le=90.0),
    longitude: float | None = Form(None, ge=-180.0, le=180.0),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> SubmitResponse:
    """Analyses a photo and keeps the result as a draft for the reporter to review.

    The draft becomes a real report through POST /reports/{id}/submit, or is dropped
    with DELETE /reports/{id}. Nothing is saved when no pothole is found.
    """
    return _analyse_and_save(session, user, file, conf, iou, latitude, longitude, submitted=False)


@app.post("/reports", response_model=SubmitResponse)
def submit_report(
    file: UploadFile = File(...),
    conf: float | None = Form(None, ge=0.0, le=1.0),
    iou: float | None = Form(None, ge=0.0, le=1.0),
    latitude: float | None = Form(None, ge=-90.0, le=90.0),
    longitude: float | None = Form(None, ge=-180.0, le=180.0),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> SubmitResponse:
    """Analyses a photo and submits the report in one step, with no review."""
    return _analyse_and_save(session, user, file, conf, iou, latitude, longitude, submitted=True)


@app.post("/reports/{report_id}/submit", response_model=ReportDetail)
def submit_draft(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> ReportDetail:
    report = _get_report(session, report_id, user)
    if report.user_id != user.id:
        raise HTTPException(status_code=404, detail="Report not found.")
    if not report.submitted:
        report.submitted = True
        # The report is dated from when it was confirmed, not when the photo was analysed.
        report.created_at = utcnow()
        session.add(report)
        session.commit()
        session.refresh(report)
        
        # Send confirmation email to user
        send_report_submitted_email(
            to_email=user.email,
            user_name=user.name,
            report_id=report.id,
            detection_count=report.detection_count,
            severe_count=report.severe_count,
            risk=report.risk,
            address=report.address,
            area=report.area,
            created_at=_iso(report.created_at) or "",
        )
    return _detail(session, report, user)


@app.get("/reports", response_model=list[ReportSummary])
def list_reports(
    status: ReportStatus | None = None,
    risk: RiskLevel | None = None,
    q: str | None = Query(None, max_length=100, description="Report number, or part of the reporter's name or email."),
    order: Literal["newest", "oldest"] = "newest",
    located: bool = Query(False, description="Only reports that have coordinates."),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> list[ReportSummary]:
    stmt = select(Report, User).join(User, User.id == Report.user_id).where(_visible_to(user))
    if status is not None:
        stmt = stmt.where(Report.status == status)
    if risk is not None:
        stmt = stmt.where(Report.risk == risk)
    if located:
        stmt = stmt.where(Report.latitude.is_not(None), Report.longitude.is_not(None))
    term = (q or "").strip()
    if term.startswith("#"):
        # "#12" means report number 12 and nothing else.
        number = term[1:].strip()
        stmt = stmt.where(Report.id == int(number) if number.isdigit() else false())
    elif term:
        # autoescape keeps % and _ in the search text from acting as wildcards.
        matches = [User.name.icontains(term, autoescape=True), User.email.icontains(term, autoescape=True)]
        if term.isdigit():
            matches.append(Report.id == int(term))
        stmt = stmt.where(or_(*matches))
    newest_first = (Report.created_at.desc(), Report.id.desc())
    oldest_first = (Report.created_at.asc(), Report.id.asc())
    stmt = stmt.order_by(*(newest_first if order == "newest" else oldest_first)).limit(limit).offset(offset)
    return [ReportSummary(**_summary_fields(r, u)) for r, u in session.exec(stmt).all()]


@app.get("/reports/{report_id}", response_model=ReportDetail)
def get_report(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> ReportDetail:
    report = _get_report(session, report_id, user)
    return _detail(session, report, session.get(User, report.user_id))


@app.get("/reports/{report_id}/image")
def report_image(
    report_id: int,
    kind: Literal["annotated", "original"] = "annotated",
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> FileResponse:
    report = _get_report(session, report_id, user)
    path = UPLOAD_DIR / (report.annotated_file if kind == "annotated" else report.image_file)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Image file is missing.")
    return FileResponse(path, media_type="image/jpeg")


@app.patch("/reports/{report_id}", response_model=ReportDetail)
def update_report_status(
    report_id: int,
    req: StatusUpdate,
    admin: User = Depends(require_admin),
    session: Session = Depends(get_session),
) -> ReportDetail:
    report = _get_report(session, report_id, admin)
    old_status = report.status
    report.status = req.status
    report.resolved_at = utcnow() if req.status == "resolved" else None
    session.add(report)
    session.commit()
    session.refresh(report)
    
    # Send status change notification to the reporter
    reporter = session.get(User, report.user_id)
    if reporter and old_status != req.status:
        send_status_changed_email(
            to_email=reporter.email,
            user_name=reporter.name,
            report_id=report.id,
            old_status=old_status,
            new_status=req.status,
            risk=report.risk,
            address=report.address,
            area=report.area,
            detection_count=report.detection_count,
            resolved_at=_iso(report.resolved_at),
        )
    
    return _detail(session, report, reporter or admin)


@app.delete("/reports/{report_id}", status_code=204)
def delete_report(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> None:
    """Admins may delete any report; a reporter may only discard their own draft."""
    report = _get_report(session, report_id, user)
    if user.role != "admin" and report.submitted:
        raise HTTPException(status_code=403, detail="Only an admin can delete a submitted report.")
    _delete_report(session, report)


# ---------- community view: every submitted report, without reporter or photo ----------


@app.get("/potholes", response_model=list[PotholeOut])
def list_potholes(
    limit: int = Query(500, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> list[PotholeOut]:
    stmt = (
        select(Report)
        .where(Report.submitted.is_(True))
        .order_by(Report.created_at.desc(), Report.id.desc())
        .limit(limit)
        .offset(offset)
    )
    return [PotholeOut(**_pothole_fields(r, user)) for r in session.exec(stmt).all()]


@app.get("/potholes/nearby", response_model=list[NearbyPothole])
def nearby_potholes(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    radius: float = Query(1000, ge=50, le=50_000, description="Metres."),
    major_only: bool = Query(False, description="Leave out low severity potholes."),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> list[NearbyPothole]:
    """Unresolved potholes within [radius] of a point, most severe first, then nearest."""
    # A box around the point lets the database discard most rows before the exact distance.
    d_lat = math.degrees(radius / _EARTH_RADIUS_M)
    d_lng = d_lat / max(math.cos(math.radians(lat)), 0.01)
    stmt = select(Report).where(
        Report.submitted.is_(True),
        Report.status != "resolved",
        Report.latitude.between(lat - d_lat, lat + d_lat),
        Report.longitude.between(lng - d_lng, lng + d_lng),
    )
    if major_only:
        stmt = stmt.where(Report.risk != "LOW")

    found = []
    for report in session.exec(stmt).all():
        distance = _distance_m(lat, lng, report.latitude, report.longitude)
        if distance <= radius:
            found.append(NearbyPothole(**_pothole_fields(report, user), distance_m=round(distance, 1)))
    rank = {"HIGH": 0, "MED": 1, "LOW": 2}
    found.sort(key=lambda p: (rank[p.severity], p.distance_m))
    return found


@app.get("/potholes/{report_id}", response_model=PotholeOut)
def get_pothole(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> PotholeOut:
    report = session.get(Report, report_id)
    if report is None or not report.submitted:
        raise HTTPException(status_code=404, detail="Pothole not found.")
    return PotholeOut(**_pothole_fields(report, user))


@app.get("/dashboard", response_model=DashboardOut)
def dashboard(_: User = Depends(current_user), session: Session = Depends(get_session)) -> DashboardOut:
    def count(*conditions) -> int:
        stmt = select(func.count()).select_from(Report).where(Report.submitted.is_(True), *conditions)
        return session.exec(stmt).one()

    today = utcnow().date()
    days = [today - timedelta(days=offset) for offset in range(6, -1, -1)]
    since = datetime.combine(days[0], datetime.min.time(), tzinfo=timezone.utc)
    per_day = dict.fromkeys(days, 0)
    recent = select(Report.created_at).where(Report.submitted.is_(True), Report.created_at >= since)
    for created_at in session.exec(recent).all():
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        day = created_at.astimezone(timezone.utc).date()
        if day in per_day:
            per_day[day] += 1

    busiest = (
        select(Report.area, func.count())
        .where(Report.submitted.is_(True), Report.area.is_not(None))
        .group_by(Report.area)
        .order_by(func.count().desc(), Report.area)
        .limit(5)
    )
    return DashboardOut(
        total=count(),
        unresolved=count(Report.status != "resolved"),
        resolved=count(Report.status == "resolved"),
        verified=count(Report.status != "pending"),
        high=count(Report.risk == "HIGH"),
        medium=count(Report.risk == "MED"),
        low=count(Report.risk == "LOW"),
        week=[DayCount(date=day.isoformat(), count=n) for day, n in per_day.items()],
        hotspots=[AreaCount(area=area, count=n) for area, n in session.exec(busiest).all()],
    )


@app.get("/stats", response_model=StatsOut)
def stats(user: User = Depends(current_user), session: Session = Depends(get_session)) -> StatsOut:
    def count(*conditions) -> int:
        stmt = select(func.count()).select_from(Report).where(_visible_to(user), *conditions)
        return session.exec(stmt).one()

    return StatsOut(
        total=count(),
        pending=count(Report.status == "pending"),
        in_review=count(Report.status == "in_review"),
        resolved=count(Report.status == "resolved"),
        high_risk=count(Report.risk == "HIGH"),
        medium_risk=count(Report.risk == "MED"),
        low_risk=count(Report.risk == "LOW"),
    )


# ---------- enhanced features ----------


@app.get("/reports/{report_id}/cluster-analysis")
def get_cluster_analysis(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> dict:
    """Get multi-angle analysis for reports at the same location."""
    report = _get_report(session, report_id, user)
    
    if report.latitude is None or report.longitude is None:
        return {"error": "Report has no location data"}
    
    cluster_info = get_location_cluster_info(session, report.latitude, report.longitude)
    
    return {
        "report_id": report_id,
        "location": {"latitude": report.latitude, "longitude": report.longitude},
        "cluster_info": cluster_info,
    }


@app.get("/reports/{report_id}/weather-impact")
def get_weather_impact(
    report_id: int,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> dict:
    """Get current weather impact on this report's severity."""
    report = _get_report(session, report_id, user)
    
    if report.latitude is None or report.longitude is None:
        return {"error": "Report has no location data"}
    
    weather_data = get_weather_data(report.latitude, report.longitude)
    
    if not weather_data:
        return {"error": "Weather data not available", "configured": False}
    
    from backend.weather_service import assess_weather_impact
    impact = assess_weather_impact(weather_data)
    
    return {
        "report_id": report_id,
        "current_risk": report.risk,
        "weather": weather_data,
        "impact": impact,
    }


@app.get("/reports/priority-queue")
def get_priority_queue(
    limit: int = Query(50, ge=1, le=200),
    min_priority: str = Query("MEDIUM", description="Minimum priority level: LOW, MEDIUM, HIGH, CRITICAL"),
    user: User = Depends(require_admin),
    session: Session = Depends(get_session),
) -> list[dict]:
    """Get reports sorted by priority score (admin only).
    
    Useful for maintenance crews to prioritize repairs.
    """
    priority_order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1}
    min_level = priority_order.get(min_priority, 2)
    
    stmt = (
        select(Report, User)
        .join(User, User.id == Report.user_id)
        .where(
            Report.submitted.is_(True),
            Report.status != "resolved",
            Report.priority_score.is_not(None),
        )
        .order_by(Report.priority_score.desc(), Report.created_at.desc())
        .limit(limit)
    )
    
    results = []
    for report, reporter in session.exec(stmt).all():
        if priority_order.get(report.priority_level, 0) >= min_level:
            results.append({
                **_summary_fields(report, reporter),
                "priority_score": report.priority_score,
                "priority_level": report.priority_level,
                "weather_adjusted": report.weather_adjusted,
                "nearby_reports_count": report.nearby_reports_count,
            })
    
    return results
