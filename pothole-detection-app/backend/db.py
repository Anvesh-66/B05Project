import os
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

from sqlmodel import Field, Session, SQLModel, create_engine

# Everything the server writes at runtime lives here: database, uploads, signing key.
DATA_DIR = Path(os.getenv("POTHOLE_DATA_DIR") or Path(__file__).resolve().parent.parent / "var")
UPLOAD_DIR = DATA_DIR / "uploads"

REPORT_STATUSES = ("pending", "in_review", "resolved")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str
    email: str = Field(index=True, unique=True)
    password_hash: str
    role: str = "user"  # "user" or "admin"
    created_at: datetime = Field(default_factory=utcnow)


class Report(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    image_file: str
    annotated_file: str
    latitude: float | None = None
    longitude: float | None = None
    # Looked up from the coordinates when the report is created; None when unknown.
    address: str | None = None
    area: str | None = Field(default=None, index=True)
    detection_count: int
    severe_count: int
    risk: str  # LOW | MED | HIGH
    # Highest confidence among the report's detections.
    top_confidence: float = 0.0
    # False while the reporter is still reviewing the detection result. Such a draft is
    # visible only to its owner and is never listed, counted or shown on the map.
    submitted: bool = Field(default=True, index=True)
    status: str = Field(default="pending", index=True)
    created_at: datetime = Field(default_factory=utcnow, index=True)
    resolved_at: datetime | None = None
    # Enhanced features
    priority_score: float | None = Field(default=None, index=True)
    priority_level: str | None = None  # CRITICAL | HIGH | MEDIUM | LOW
    weather_adjusted: bool = Field(default=False)
    nearby_reports_count: int = Field(default=0)


class DetectionRecord(SQLModel, table=True):
    __tablename__ = "detection"

    id: int | None = Field(default=None, primary_key=True)
    report_id: int = Field(foreign_key="report.id", index=True)
    class_name: str
    confidence: float
    severity: str
    x1: float
    y1: float
    x2: float
    y2: float
    depth_index: float | None = None
    has_water: bool = False


engine = create_engine(
    f"sqlite:///{(DATA_DIR / 'pothole.db').as_posix()}",
    connect_args={"check_same_thread": False},
)


def init_db() -> None:
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    SQLModel.metadata.create_all(engine)
    # create_all does not add columns to a table that already exists.
    added = {
        "detection": (("depth_index", "FLOAT"), ("has_water", "BOOLEAN NOT NULL DEFAULT 0")),
        "report": (
            ("address", "VARCHAR"),
            ("area", "VARCHAR"),
            ("top_confidence", "FLOAT NOT NULL DEFAULT 0"),
            ("submitted", "BOOLEAN NOT NULL DEFAULT 1"),
            ("priority_score", "FLOAT"),
            ("priority_level", "VARCHAR"),
            ("weather_adjusted", "BOOLEAN NOT NULL DEFAULT 0"),
            ("nearby_reports_count", "INTEGER NOT NULL DEFAULT 0"),
        ),
    }
    with engine.begin() as conn:
        for table, columns in added.items():
            existing = {row[1] for row in conn.exec_driver_sql(f"PRAGMA table_info({table})")}
            for name, sql_type in columns:
                if name in existing:
                    continue
                conn.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {name} {sql_type}")
                if name == "top_confidence":
                    conn.exec_driver_sql(
                        "UPDATE report SET top_confidence = COALESCE("
                        "(SELECT MAX(confidence) FROM detection WHERE detection.report_id = report.id), 0)"
                    )


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session
