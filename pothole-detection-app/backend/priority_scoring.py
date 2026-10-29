"""Priority scoring system combining risk, location, traffic, and proximity to critical areas."""

from __future__ import annotations

import logging
import math
from typing import Literal

logger = logging.getLogger("uvicorn.error")

_EARTH_RADIUS_M = 6_371_000

# Critical location types and their importance weights
CRITICAL_LOCATIONS = {
    "school": {"weight": 1.5, "radius_m": 500},
    "hospital": {"weight": 2.0, "radius_m": 800},
    "emergency": {"weight": 2.0, "radius_m": 800},  # Fire stations, police
    "university": {"weight": 1.3, "radius_m": 800},
    "kindergarten": {"weight": 1.6, "radius_m": 300},
    "clinic": {"weight": 1.4, "radius_m": 500},
}


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two points."""
    d_lat, d_lng = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    h = math.sin(d_lat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    return 2 * _EARTH_RADIUS_M * math.asin(math.sqrt(h))


def calculate_base_score(
    risk: Literal["LOW", "MED", "HIGH"],
    severe_count: int,
    detection_count: int,
) -> float:
    """Calculate base priority score from pothole characteristics.
    
    Args:
        risk: Risk level
        severe_count: Number of severe potholes
        detection_count: Total number of detections
    
    Returns:
        Base score (0-100)
    """
    risk_scores = {"LOW": 20, "MED": 50, "HIGH": 80}
    base = risk_scores.get(risk, 20)
    
    # Add points for severe potholes
    base += severe_count * 5
    
    # Add points for multiple potholes (clustering)
    if detection_count >= 4:
        base += 10
    elif detection_count >= 2:
        base += 5
    
    return min(base, 100)


def calculate_location_multiplier(
    latitude: float | None,
    longitude: float | None,
    critical_locations: list[dict] | None = None,
) -> tuple[float, list[str]]:
    """Calculate priority multiplier based on proximity to critical locations.
    
    Critical locations include:
    - Schools (children pedestrians)
    - Hospitals (emergency vehicle access)
    - Emergency services (fire, police)
    
    Args:
        latitude: Pothole latitude
        longitude: Pothole longitude
        critical_locations: List of dicts with 'type', 'lat', 'lng', 'name'
    
    Returns:
        Tuple of (multiplier, list of nearby critical locations)
    """
    if latitude is None or longitude is None:
        return 1.0, []
    
    if not critical_locations:
        # If no critical locations provided, assume average urban area
        return 1.0, []
    
    max_multiplier = 1.0
    nearby = []
    
    for location in critical_locations:
        loc_type = location.get("type", "").lower()
        loc_lat = location.get("lat")
        loc_lng = location.get("lng")
        loc_name = location.get("name", "Unknown")
        
        if loc_lat is None or loc_lng is None:
            continue
        
        distance = _distance_m(latitude, longitude, loc_lat, loc_lng)
        
        # Check if within radius for this type
        for key, config in CRITICAL_LOCATIONS.items():
            if key in loc_type:
                if distance <= config["radius_m"]:
                    # Closer = higher multiplier (inverse distance)
                    proximity_factor = 1.0 - (distance / config["radius_m"]) * 0.5  # 0.5 to 1.0
                    multiplier = 1.0 + (config["weight"] - 1.0) * proximity_factor
                    max_multiplier = max(max_multiplier, multiplier)
                    nearby.append(f"{loc_name} ({int(distance)}m)")
                break
    
    return max_multiplier, nearby


def estimate_traffic_multiplier(
    road_type: str | None = None,
    time_of_day: str | None = None,
) -> float:
    """Estimate traffic impact on priority.
    
    Higher traffic = more vehicles affected = higher priority
    
    Args:
        road_type: Type of road (highway, arterial, residential, etc.)
        time_of_day: Time category (rush_hour, day, night)
    
    Returns:
        Traffic multiplier (0.8 - 1.5)
    """
    multiplier = 1.0
    
    # Road type impact
    road_multipliers = {
        "highway": 1.5,
        "freeway": 1.5,
        "arterial": 1.3,
        "main": 1.3,
        "collector": 1.1,
        "residential": 0.9,
        "service": 0.8,
    }
    
    if road_type:
        for key, mult in road_multipliers.items():
            if key in road_type.lower():
                multiplier *= mult
                break
    
    # Time of day impact (future: could use real-time traffic API)
    time_multipliers = {
        "rush_hour": 1.2,
        "day": 1.0,
        "night": 0.9,
    }
    
    if time_of_day:
        multiplier *= time_multipliers.get(time_of_day, 1.0)
    
    return multiplier


def calculate_recurrence_multiplier(
    report_count: int,
    is_worsening: bool = False,
) -> float:
    """Calculate multiplier based on recurring reports at same location.
    
    Multiple reports indicate:
    - Confirmed problem (not false positive)
    - Persistent issue (needs attention)
    - Possibly worsening
    
    Args:
        report_count: Number of reports at this location
        is_worsening: Whether severity is increasing over time
    
    Returns:
        Recurrence multiplier (1.0 - 2.0)
    """
    if report_count <= 1:
        return 1.0
    
    # Base multiplier from report count
    multiplier = 1.0 + min(report_count - 1, 5) * 0.15  # +15% per additional report, max +75%
    
    # Additional boost if worsening
    if is_worsening:
        multiplier *= 1.2
    
    return min(multiplier, 2.0)


def calculate_priority_score(
    risk: Literal["LOW", "MED", "HIGH"],
    severe_count: int,
    detection_count: int,
    latitude: float | None = None,
    longitude: float | None = None,
    critical_locations: list[dict] | None = None,
    road_type: str | None = None,
    report_count: int = 1,
    is_worsening: bool = False,
    weather_multiplier: float = 1.0,
) -> dict:
    """Calculate comprehensive priority score for a pothole report.
    
    Score components:
    1. Base score (0-100) from risk and severity
    2. Location multiplier (1.0-3.0) from critical locations
    3. Traffic multiplier (0.8-1.5) from road type
    4. Recurrence multiplier (1.0-2.0) from multiple reports
    5. Weather multiplier (1.0-1.5) from current conditions
    
    Final score = base * location * traffic * recurrence * weather
    
    Args:
        risk: Risk level
        severe_count: Number of severe potholes
        detection_count: Total detections
        latitude: Location latitude
        longitude: Location longitude
        critical_locations: List of nearby critical locations
        road_type: Type of road
        report_count: Number of reports at this location
        is_worsening: Whether condition is worsening
        weather_multiplier: Weather impact multiplier
    
    Returns:
        Dictionary with score and breakdown
    """
    base_score = calculate_base_score(risk, severe_count, detection_count)
    
    location_mult, nearby_critical = calculate_location_multiplier(
        latitude, longitude, critical_locations
    )
    
    traffic_mult = estimate_traffic_multiplier(road_type)
    
    recurrence_mult = calculate_recurrence_multiplier(report_count, is_worsening)
    
    # Calculate final score
    final_score = base_score * location_mult * traffic_mult * recurrence_mult * weather_multiplier
    final_score = min(final_score, 1000)  # Cap at 1000
    
    # Determine priority level
    if final_score >= 300:
        priority = "CRITICAL"
    elif final_score >= 150:
        priority = "HIGH"
    elif final_score >= 75:
        priority = "MEDIUM"
    else:
        priority = "LOW"
    
    return {
        "priority_score": round(final_score, 2),
        "priority_level": priority,
        "breakdown": {
            "base_score": base_score,
            "location_multiplier": round(location_mult, 2),
            "traffic_multiplier": round(traffic_mult, 2),
            "recurrence_multiplier": round(recurrence_mult, 2),
            "weather_multiplier": round(weather_multiplier, 2),
        },
        "nearby_critical_locations": nearby_critical,
        "factors": {
            "risk_level": risk,
            "severe_potholes": severe_count,
            "total_potholes": detection_count,
            "multiple_reports": report_count > 1,
            "is_worsening": is_worsening,
            "near_critical_location": len(nearby_critical) > 0,
        },
    }


def get_sample_critical_locations() -> list[dict]:
    """Sample critical locations for demonstration.
    
    In production, this should come from:
    - OpenStreetMap Overpass API
    - Google Places API
    - Local government GIS data
    
    Returns:
        List of sample critical locations
    """
    # Sample locations in Nagpur, India area
    return [
        {"type": "school", "lat": 21.1458, "lng": 79.0882, "name": "Sample School"},
        {"type": "hospital", "lat": 21.1466, "lng": 79.0892, "name": "Sample Hospital"},
        {"type": "school", "lat": 21.1240, "lng": 79.0616, "name": "Another School"},
    ]
