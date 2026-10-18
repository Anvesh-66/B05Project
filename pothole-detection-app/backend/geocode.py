"""Turns coordinates into a street address, using OpenStreetMap's Nominatim service."""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request

logger = logging.getLogger("uvicorn.error")

_URL = "https://nominatim.openstreetmap.org/reverse"
# Nominatim's usage policy asks every client to identify itself.
_USER_AGENT = "pothole-detection-app/0.4 (student project)"
_TIMEOUT_SECONDS = 4

# Address parts tried in order: the first present names the road, then the neighbourhood.
_ROAD_KEYS = ("road", "pedestrian", "footway", "path", "neighbourhood")
_AREA_KEYS = ("suburb", "neighbourhood", "city_district", "town", "village", "city", "county")


def reverse_geocode(latitude: float, longitude: float) -> tuple[str | None, str | None]:
    """The (address, area) at a point, e.g. ("FC Road", "Shivajinagar").

    Either part is None when it is unknown. An address is a convenience on top of the
    coordinates, so a slow or failing lookup returns (None, None) instead of raising.
    Set POTHOLE_GEOCODE=0 to skip the lookup entirely.
    """
    if os.getenv("POTHOLE_GEOCODE", "1").strip().lower() in {"0", "false", "no", "off"}:
        return None, None

    query = urllib.parse.urlencode(
        {"lat": latitude, "lon": longitude, "format": "jsonv2", "zoom": 17, "addressdetails": 1}
    )
    request = urllib.request.Request(
        f"{_URL}?{query}", headers={"User-Agent": _USER_AGENT, "Accept-Language": "en"}
    )
    try:
        with urllib.request.urlopen(request, timeout=_TIMEOUT_SECONDS) as response:
            parts = json.load(response).get("address") or {}
    except (urllib.error.URLError, TimeoutError, ValueError, OSError) as e:
        logger.warning("Address lookup failed for %.5f, %.5f: %s", latitude, longitude, e)
        return None, None

    def first(keys: tuple[str, ...], skip: str | None = None) -> str | None:
        return next((str(parts[k])[:120] for k in keys if parts.get(k) and parts[k] != skip), None)

    address = first(_ROAD_KEYS)
    return address, first(_AREA_KEYS, skip=address)
