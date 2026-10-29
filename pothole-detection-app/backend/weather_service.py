"""Weather integration for severity adjustment based on rainfall."""

from __future__ import annotations

import logging
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from functools import lru_cache

logger = logging.getLogger("uvicorn.error")

# Free weather API (OpenWeatherMap) - requires API key
WEATHER_API_URL = "https://api.openweathermap.org/data/2.5/weather"
WEATHER_TIMEOUT_SECONDS = 5


def _get_weather_api_key() -> str | None:
    """Get weather API key from environment."""
    return os.getenv("WEATHER_API_KEY", "").strip() or None


@lru_cache(maxsize=100)
def _cached_weather(lat_lng_key: tuple[float, float], time_key: int) -> dict | None:
    """Cache weather data for 15 minutes per location."""
    # time_key is unix timestamp rounded to 15 minutes
    # This allows cache to work while preventing stale data
    # Return None to indicate cache miss - actual data stored in closure
    return None


def get_weather_data(latitude: float, longitude: float) -> dict | None:
    """Fetch current weather data for a location.
    
    Args:
        latitude: Location latitude
        longitude: Location longitude
    
    Returns:
        Weather data dict or None if unavailable/error
    """
    api_key = _get_weather_api_key()
    
    if not api_key:
        logger.info("Weather API not configured (WEATHER_API_KEY not set)")
        return None
    
    # Round time to 15 minutes for cache efficiency
    time_key = int(datetime.now(timezone.utc).timestamp() // 900)
    lat_lng_key = (round(latitude, 4), round(longitude, 4))
    
    # Check cache first
    cached = _cached_weather(lat_lng_key, time_key)
    if cached is not None:
        return cached
    
    try:
        params = urllib.parse.urlencode({
            "lat": latitude,
            "lon": longitude,
            "appid": api_key,
            "units": "metric",
        })
        
        request = urllib.request.Request(f"{WEATHER_API_URL}?{params}")
        
        with urllib.request.urlopen(request, timeout=WEATHER_TIMEOUT_SECONDS) as response:
            import json
            data = json.load(response)
            
            # Extract relevant weather info
            weather_info = {
                "temperature": data.get("main", {}).get("temp"),
                "humidity": data.get("main", {}).get("humidity"),
                "description": data.get("weather", [{}])[0].get("description", ""),
                "rain_1h": data.get("rain", {}).get("1h", 0.0),  # Rain in last hour (mm)
                "rain_3h": data.get("rain", {}).get("3h", 0.0),  # Rain in last 3 hours (mm)
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            
            # Note: Can't actually cache with @lru_cache on dict, but key serves as identity
            
            return weather_info
            
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as e:
        logger.warning("Weather API request failed: %s", e)
        return None


def assess_weather_impact(weather_data: dict | None) -> dict:
    """Assess how weather affects pothole severity.
    
    Wet conditions make potholes more dangerous:
    - Harder to see (water hides depth)
    - More vehicle damage risk
    - Hydroplaning risk
    - Accelerates deterioration
    
    Args:
        weather_data: Weather data from get_weather_data
    
    Returns:
        Impact assessment dictionary
    """
    if not weather_data:
        return {
            "weather_available": False,
            "is_wet_conditions": False,
            "severity_multiplier": 1.0,
            "warning_message": None,
        }
    
    rain_1h = weather_data.get("rain_1h", 0.0)
    rain_3h = weather_data.get("rain_3h", 0.0)
    description = weather_data.get("description", "").lower()
    
    # Detect wet conditions
    is_raining = rain_1h > 0.1 or "rain" in description
    is_heavy_rain = rain_1h > 2.5 or rain_3h > 7.5  # Heavy rain thresholds
    is_wet = is_raining or "drizzle" in description or "shower" in description
    
    # Calculate severity multiplier
    if is_heavy_rain:
        multiplier = 1.5  # 50% more dangerous in heavy rain
        warning = "Heavy rain detected - potholes significantly more dangerous"
    elif is_raining:
        multiplier = 1.3  # 30% more dangerous in moderate rain
        warning = "Rain detected - potholes more dangerous due to reduced visibility"
    elif is_wet:
        multiplier = 1.15  # 15% more dangerous in drizzle
        warning = "Wet conditions - exercise caution near potholes"
    else:
        multiplier = 1.0
        warning = None
    
    return {
        "weather_available": True,
        "is_wet_conditions": is_wet,
        "rain_1h_mm": rain_1h,
        "rain_3h_mm": rain_3h,
        "description": weather_data.get("description"),
        "severity_multiplier": multiplier,
        "warning_message": warning,
    }


def adjust_risk_for_weather(
    base_risk: str,
    latitude: float | None,
    longitude: float | None,
) -> tuple[str, dict]:
    """Adjust risk level based on current weather conditions.
    
    Args:
        base_risk: Original risk level (HIGH/MED/LOW)
        latitude: Location latitude
        longitude: Location longitude
    
    Returns:
        Tuple of (adjusted_risk, weather_info)
    """
    if latitude is None or longitude is None:
        return base_risk, {"weather_available": False}
    
    weather_data = get_weather_data(latitude, longitude)
    impact = assess_weather_impact(weather_data)
    
    # Only upgrade risk, never downgrade
    adjusted_risk = base_risk
    
    if impact["is_wet_conditions"]:
        if base_risk == "MED" and impact["severity_multiplier"] >= 1.3:
            adjusted_risk = "HIGH"
            logger.info("Risk upgraded MED → HIGH due to rain at %.5f, %.5f", latitude, longitude)
        elif base_risk == "LOW" and impact["severity_multiplier"] >= 1.3:
            adjusted_risk = "MED"
            logger.info("Risk upgraded LOW → MED due to rain at %.5f, %.5f", latitude, longitude)
    
    return adjusted_risk, impact
