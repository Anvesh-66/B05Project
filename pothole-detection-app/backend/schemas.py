from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

ReportStatus = Literal["pending", "in_review", "resolved"]
RiskLevel = Literal["LOW", "MED", "HIGH"]

_EMAIL_PATTERN = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    email: str = Field(..., max_length=254, pattern=_EMAIL_PATTERN)
    # bcrypt only uses the first 72 bytes of a password.
    password: str = Field(..., min_length=8, max_length=72)


class LoginRequest(BaseModel):
    email: str = Field(..., max_length=254)
    password: str = Field(..., max_length=72)


class UserOut(BaseModel):
    id: int
    name: str
    email: str
    role: str


class TokenResponse(BaseModel):
    access_token: str
    user: UserOut


class DetectionOut(BaseModel):
    class_name: str
    confidence: float
    severity: str
    x1: float
    y1: float
    x2: float
    y2: float
    depth_index: float | None = Field(
        None,
        description="How far the pothole floor sits below the surrounding road, relative to the "
        "camera's distance from it (0 = flat). Not centimetres. Null when it could not be measured.",
    )
    has_water: bool = Field(
        False, description="The pothole looks filled with water, so severity comes from box size alone."
    )


class ReportSummary(BaseModel):
    id: int
    status: ReportStatus
    risk: RiskLevel
    detection_count: int
    severe_count: int
    confidence: float = Field(..., description="Highest confidence among the detections.")
    latitude: float | None
    longitude: float | None
    address: str | None
    area: str | None
    submitted: bool = Field(..., description="False for a draft the reporter has not confirmed yet.")
    created_at: str = Field(..., description="UTC, ISO 8601")
    resolved_at: str | None
    reporter_name: str
    reporter_email: str


class ReportDetail(ReportSummary):
    detections: list[DetectionOut]


class SubmitResponse(BaseModel):
    report: ReportDetail | None = Field(
        ..., description="The saved report, or null when no pothole was found in the photo."
    )


class PotholeOut(BaseModel):
    """A submitted report as every signed-in user may see it: no reporter and no photo."""

    id: int
    severity: RiskLevel
    confidence: float
    detection_count: int
    status: ReportStatus
    latitude: float | None
    longitude: float | None
    address: str | None
    area: str | None
    created_at: str = Field(..., description="UTC, ISO 8601")
    resolved_at: str | None
    mine: bool = Field(..., description="True when the caller reported it.")


class NearbyPothole(PotholeOut):
    distance_m: float


class DayCount(BaseModel):
    date: str = Field(..., description="UTC day, YYYY-MM-DD")
    count: int


class AreaCount(BaseModel):
    area: str
    count: int


class DashboardOut(BaseModel):
    total: int
    unresolved: int
    resolved: int
    verified: int = Field(..., description="Reports an admin has reviewed or resolved.")
    high: int
    medium: int
    low: int
    week: list[DayCount] = Field(..., description="Reports per day for the last 7 days, oldest first.")
    hotspots: list[AreaCount] = Field(..., description="The areas with the most reports, largest first.")


class StatusUpdate(BaseModel):
    status: ReportStatus


class StatsOut(BaseModel):
    total: int
    pending: int
    in_review: int
    resolved: int
    high_risk: int
    medium_risk: int
    low_risk: int
