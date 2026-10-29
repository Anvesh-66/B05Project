"""Multi-angle analysis and location-based aggregation for pothole reports."""

from __future__ import annotations

import logging
import math
from datetime import datetime, timedelta, timezone

from sqlmodel import Session, select

from backend.db import Report

logger = logging.getLogger("uvicorn.error")

# Consider reports within this radius (meters) as the same location
LOCATION_CLUSTER_RADIUS = 50.0  # 50 meters
_EARTH_RADIUS_M = 6_371_000


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two points, by the haversine formula."""
    d_lat, d_lng = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    h = math.sin(d_lat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    return 2 * _EARTH_RADIUS_M * math.asin(math.sqrt(h))


def find_nearby_reports(
    session: Session,
    latitude: float,
    longitude: float,
    radius_m: float = LOCATION_CLUSTER_RADIUS,
    days_back: int = 30,
) -> list[Report]:
    """Find all reports within radius of given location, submitted in the last N days.
    
    Args:
        session: Database session
        latitude: Center latitude
        longitude: Center longitude
        radius_m: Search radius in meters
        days_back: Only include reports from last N days
    
    Returns:
        List of nearby reports sorted by distance
    """
    # Bounding box for efficient database filtering
    d_lat = math.degrees(radius_m / _EARTH_RADIUS_M)
    d_lng = d_lat / max(math.cos(math.radians(latitude)), 0.01)
    
    # Use timezone-aware datetime
    min_date = datetime.now(timezone.utc) - timedelta(days=days_back)
    
    stmt = select(Report).where(
        Report.submitted.is_(True),
        Report.latitude.is_not(None),
        Report.longitude.is_not(None),
        Report.latitude.between(latitude - d_lat, latitude + d_lat),
        Report.longitude.between(longitude - d_lng, longitude + d_lng),
        Report.created_at >= min_date,
    )
    
    candidates = session.exec(stmt).all()
    
    # Filter by exact distance and sort
    nearby = []
    for report in candidates:
        if report.latitude is None or report.longitude is None:
            continue
        distance = _distance_m(latitude, longitude, report.latitude, report.longitude)
        if distance <= radius_m:
            nearby.append((distance, report))
    
    nearby.sort(key=lambda x: x[0])
    return [report for _, report in nearby]


def calculate_aggregated_severity(reports: list[Report]) -> dict:
    """Analyze multiple reports at the same location to determine aggregated severity.
    
    Takes into account:
    - Number of reports (more reports = higher concern)
    - Maximum severity across all reports
    - Trend over time (getting worse?)
    - Consistency of severe classifications
    
    Args:
        reports: List of reports at the same location
    
    Returns:
        Dictionary with aggregated analysis
    """
    if not reports:
        return {
            "report_count": 0,
            "aggregated_risk": "LOW",
            "max_severe_count": 0,
            "avg_confidence": 0.0,
            "is_worsening": False,
            "consistency_score": 0.0,
        }
    
    # Sort by date (oldest first)
    sorted_reports = sorted(reports, key=lambda r: r.created_at)
    
    # Count risk levels
    risk_counts = {"HIGH": 0, "MED": 0, "LOW": 0}
    severe_counts = []
    confidences = []
    
    for report in sorted_reports:
        risk_counts[report.risk] += 1
        severe_counts.append(report.severe_count)
        confidences.append(report.top_confidence)
    
    # Determine aggregated risk
    total = len(reports)
    high_ratio = risk_counts["HIGH"] / total
    
    if high_ratio >= 0.5 or risk_counts["HIGH"] >= 2:
        aggregated_risk = "HIGH"
    elif risk_counts["HIGH"] >= 1 or risk_counts["MED"] >= 2:
        aggregated_risk = "MED"
    else:
        aggregated_risk = "LOW"
    
    # Check if worsening (more severe in recent reports)
    is_worsening = False
    if len(severe_counts) >= 3:
        first_half_avg = sum(severe_counts[:len(severe_counts)//2]) / (len(severe_counts)//2)
        second_half_avg = sum(severe_counts[len(severe_counts)//2:]) / (len(severe_counts) - len(severe_counts)//2)
        is_worsening = second_half_avg > first_half_avg * 1.2  # 20% increase
    
    # Consistency score: how often reports agree on high/severe
    high_severe_reports = sum(1 for r in reports if r.risk in ["HIGH", "MED"] and r.severe_count > 0)
    consistency_score = high_severe_reports / total if total > 0 else 0.0
    
    return {
        "report_count": total,
        "aggregated_risk": aggregated_risk,
        "max_severe_count": max(severe_counts) if severe_counts else 0,
        "avg_confidence": sum(confidences) / len(confidences) if confidences else 0.0,
        "is_worsening": is_worsening,
        "consistency_score": consistency_score,
        "risk_distribution": risk_counts,
        "days_span": (sorted_reports[-1].created_at - sorted_reports[0].created_at).days if len(sorted_reports) > 1 else 0,
    }


def get_location_cluster_info(
    session: Session,
    latitude: float,
    longitude: float,
) -> dict:
    """Get comprehensive information about a location cluster.
    
    Useful for:
    - Showing users if their location already has reports
    - Admins seeing if a location is a recurring problem
    - Priority scoring based on report frequency
    
    Args:
        session: Database session
        latitude: Location latitude
        longitude: Location longitude
    
    Returns:
        Cluster information dictionary
    """
    nearby = find_nearby_reports(session, latitude, longitude)
    
    if not nearby:
        return {
            "has_existing_reports": False,
            "report_count": 0,
            "aggregated_risk": "LOW",
        }
    
    aggregated = calculate_aggregated_severity(nearby)
    
    return {
        "has_existing_reports": True,
        "nearest_report_id": nearby[0].id,
        "nearest_distance_m": _distance_m(latitude, longitude, nearby[0].latitude, nearby[0].longitude),
        **aggregated,
    }
