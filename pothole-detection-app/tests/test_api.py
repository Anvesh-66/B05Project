from __future__ import annotations

import io
import os
import tempfile
from dataclasses import replace
from types import SimpleNamespace

import numpy as np
import pytest
from PIL import Image

# The data dir is read when backend.db is imported, so point it at a temp dir first.
os.environ["POTHOLE_DATA_DIR"] = tempfile.mkdtemp(prefix="pothole-test-")

from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import Session, SQLModel, select  # noqa: E402

from backend import main  # noqa: E402
from backend.db import UPLOAD_DIR, User, engine  # noqa: E402
from pothole.types import Detection  # noqa: E402

SEVERE = Detection(0, "pothole", 0.9, 10, 10, 60, 60, "Severe")
MINOR = Detection(0, "pothole", 0.5, 1, 1, 5, 5, "Not Severe")


@pytest.fixture()
def client(monkeypatch):
    SQLModel.metadata.drop_all(engine)
    fake_model = (None, SimpleNamespace(model_path="stub"), {0: "pothole"})
    monkeypatch.setattr(main, "get_model", lambda: fake_model)
    monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: [SEVERE, MINOR])
    # Tests run without the depth model unless they switch it on with _fake_depth.
    monkeypatch.setattr(main, "load_depth_model", _no_depth_model)
    # No network in tests: every located report is "on FC Road in Shivajinagar".
    monkeypatch.setattr(main, "reverse_geocode", lambda lat, lng: ("FC Road", "Shivajinagar"))
    with TestClient(main.app) as c:
        yield c


def _no_depth_model() -> None:
    raise RuntimeError("no depth model in tests")


def _fake_depth(monkeypatch, estimate) -> None:
    monkeypatch.setattr(main, "_depth_loaded", True)
    monkeypatch.setattr(main, "estimate_inverse_depth", estimate)


def _photo() -> bytes:
    # Rough like a dry road: a flat-coloured photo would be read as standing water.
    gravel = np.random.default_rng(0).integers(0, 255, (80, 80), dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(gravel).convert("RGB").save(buf, format="JPEG")
    return buf.getvalue()


def _png(gray: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(gray).save(buf, format="PNG")
    return buf.getvalue()


def _register(client, email="asha@example.com", name="Asha") -> dict:
    resp = client.post("/auth/register", json={"name": name, "email": email, "password": "correct horse"})
    assert resp.status_code == 201, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def _make_admin(client, email="admin@example.com") -> dict:
    headers = _register(client, email, "Admin")
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email)).one()
        user.role = "admin"
        session.add(user)
        session.commit()
    return headers


def _submit(client, headers, **fields):
    return client.post("/reports", headers=headers, files={"file": ("p.jpg", _photo(), "image/jpeg")}, data=fields)


def test_register_login_and_me(client):
    headers = _register(client, "Asha@Example.com")
    assert client.get("/auth/me", headers=headers).json()["email"] == "asha@example.com"

    ok = client.post("/auth/login", json={"email": "asha@example.com", "password": "correct horse"})
    assert ok.status_code == 200 and ok.json()["user"]["role"] == "user"

    assert client.post("/auth/login", json={"email": "asha@example.com", "password": "wrong"}).status_code == 401
    assert client.post("/auth/login", json={"email": "nobody@example.com", "password": "x"}).status_code == 401


def test_register_rejects_duplicates_and_weak_input(client):
    _register(client)
    dup = client.post("/auth/register", json={"name": "A", "email": "ASHA@example.com", "password": "correct horse"})
    assert dup.status_code == 409
    short = client.post("/auth/register", json={"name": "A", "email": "b@example.com", "password": "short"})
    assert short.status_code == 422
    bad_email = client.post("/auth/register", json={"name": "A", "email": "not-an-email", "password": "correct horse"})
    assert bad_email.status_code == 422


def test_passwords_are_stored_hashed(client):
    _register(client)
    with Session(engine) as session:
        stored = session.exec(select(User)).one().password_hash
    assert "correct horse" not in stored and stored.startswith("$2")


def test_endpoints_require_a_valid_token(client):
    assert client.get("/reports").status_code == 401
    assert client.get("/stats").status_code == 401
    assert client.post("/reports", files={"file": ("p.jpg", _photo(), "image/jpeg")}).status_code == 401
    assert client.get("/reports", headers={"Authorization": "Bearer not-a-token"}).status_code == 401


def test_submit_saves_report_with_detections_and_images(client):
    headers = _register(client)
    resp = _submit(client, headers, latitude="17.385", longitude="78.4867")
    assert resp.status_code == 200, resp.text
    report = resp.json()["report"]
    assert report["detection_count"] == 2 and report["severe_count"] == 1
    assert report["risk"] == "MED" and report["status"] == "pending"
    assert report["latitude"] == 17.385 and report["created_at"].endswith("Z")
    assert [d["severity"] for d in report["detections"]] == ["Severe", "Not Severe"]

    for kind in ("annotated", "original"):
        img = client.get(f"/reports/{report['id']}/image?kind={kind}", headers=headers)
        assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"

    assert client.get("/stats", headers=headers).json() == {
        "total": 1, "pending": 1, "in_review": 0, "resolved": 0, "high_risk": 0, "medium_risk": 1, "low_risk": 0,
    }


def test_submit_records_a_depth_index_per_detection(client, monkeypatch):
    # A flat road (inverse depth 10) with a dent under the SEVERE box that is 20% further away.
    road = np.full((80, 80), 10.0, dtype=np.float32)
    road[10:60, 10:60] = 8.0
    _fake_depth(monkeypatch, lambda img: road)
    headers = _register(client)

    assert client.get("/health").json()["depth_loaded"] is True
    report = _submit(client, headers).json()["report"]
    severe, minor = report["detections"]
    assert severe["depth_index"] == pytest.approx(0.2, abs=0.01)
    # The MINOR box is too small to measure, so it keeps its box-size severity.
    assert minor["depth_index"] is None and minor["severity"] == "Not Severe"

    saved = client.get(f"/reports/{report['id']}", headers=headers).json()
    assert saved["detections"][0]["depth_index"] == pytest.approx(0.2, abs=0.01)


def test_depth_raises_severity_but_never_lowers_it(client, monkeypatch):
    shallow = Detection(0, "pothole", 0.8, 10, 10, 60, 60, "Not Severe")
    headers = _register(client)

    def road_with_dent(drop):
        road = np.full((80, 80), 10.0, dtype=np.float32)
        road[10:60, 10:60] = 10.0 - drop
        return road

    def submit_with(drop, box_severity):
        monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: [replace(shallow, severity=box_severity)])
        _fake_depth(monkeypatch, lambda img: road_with_dent(drop))
        return _submit(client, headers).json()["report"]

    # A small box over a deep hole is upgraded, and the report risk follows.
    deep = submit_with(2.0, "Not Severe")
    assert deep["detections"][0]["severity"] == "Severe" and deep["severe_count"] == 1
    assert submit_with(0.6, "Not Severe")["detections"][0]["severity"] == "Neutral"
    # A flat reading leaves the box-size severity alone.
    assert submit_with(0.0, "Severe")["detections"][0]["severity"] == "Severe"
    assert submit_with(0.0, "Not Severe")["detections"][0]["severity"] == "Not Severe"


def test_water_filled_pothole_keeps_box_severity_and_gets_no_depth(client, monkeypatch):
    box = Detection(0, "pothole", 0.8, 10, 10, 60, 60, "Not Severe")
    monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: [box])
    # The depth model reads this hole as deep enough to be Severe.
    deep = np.full((80, 80), 10.0, dtype=np.float32)
    deep[10:60, 10:60] = 8.0
    _fake_depth(monkeypatch, lambda img: deep)
    headers = _register(client)

    def submit(photo):
        resp = client.post("/reports", headers=headers, files={"file": ("p.png", photo, "image/png")})
        return resp.json()["report"]["detections"][0]

    gravel = np.random.default_rng(0).integers(0, 255, (80, 80), dtype=np.uint8)
    puddle = gravel.copy()
    puddle[10:60, 10:60] = 120  # a smooth water surface inside the box

    dry = submit(_png(gravel))
    assert dry["has_water"] is False and dry["severity"] == "Severe" and dry["depth_index"] is not None
    wet = submit(_png(puddle))
    assert wet["has_water"] is True and wet["severity"] == "Not Severe" and wet["depth_index"] is None


def test_report_is_saved_when_depth_is_off_or_fails(client, monkeypatch):
    headers = _register(client)
    assert client.get("/health").json()["depth_loaded"] is False
    assert _submit(client, headers).json()["report"]["detections"][0]["depth_index"] is None

    def boom(img):
        raise RuntimeError("out of memory")

    _fake_depth(monkeypatch, boom)
    resp = _submit(client, headers)
    assert resp.status_code == 200
    assert [d["depth_index"] for d in resp.json()["report"]["detections"]] == [None, None]


def test_photo_without_potholes_is_not_saved(client, monkeypatch):
    monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: [])
    headers = _register(client)
    assert _submit(client, headers).json() == {"report": None}
    assert client.get("/reports", headers=headers).json() == []


def test_submit_validates_input(client):
    headers = _register(client)
    not_image = client.post("/reports", headers=headers, files={"file": ("p.jpg", b"nope", "image/jpeg")})
    assert not_image.status_code == 400
    assert _submit(client, headers, conf="5").status_code == 422
    assert _submit(client, headers, latitude="120").status_code == 422


def test_model_failure_returns_503(client, monkeypatch):
    def boom(img, conf=None, iou=None):
        raise RuntimeError("weights missing")

    monkeypatch.setattr(main, "predict_from_pil", boom)
    assert _submit(client, _register(client)).status_code == 503


def test_users_only_see_their_own_reports(client):
    asha, ravi = _register(client), _register(client, "ravi@example.com", "Ravi")
    report_id = _submit(client, asha).json()["report"]["id"]

    assert client.get("/reports", headers=ravi).json() == []
    assert client.get(f"/reports/{report_id}", headers=ravi).status_code == 404
    assert client.get(f"/reports/{report_id}/image", headers=ravi).status_code == 404
    assert client.get("/stats", headers=ravi).json()["total"] == 0
    assert len(client.get("/reports", headers=asha).json()) == 1


def test_reports_can_be_searched_sorted_and_limited_to_located(client):
    asha, ravi, admin = _register(client), _register(client, "ravi@example.com", "Ravi"), _make_admin(client)
    first = _submit(client, asha, latitude="17.385", longitude="78.4867").json()["report"]["id"]
    second = _submit(client, ravi).json()["report"]["id"]

    def ids(query):
        return [r["id"] for r in client.get(f"/reports?{query}", headers=admin).json()]

    assert ids("") == [second, first] and ids("order=oldest") == [first, second]
    assert ids("q=ravi") == [second] and ids("q=ASHA@example") == [first]
    assert ids(f"q=%23{first}") == [first] and ids(f"q={second}") == [second]
    # With "#" only the report number counts, not digits or text in a reporter's details.
    assert ids("q=%23999") == [] and ids("q=%23ravi") == []
    # A wildcard character is searched for literally.
    assert ids("q=%25") == [] and ids("q=nobody") == []
    assert ids("located=true") == [first]
    # Search never reaches past what the caller may see.
    assert [r["id"] for r in client.get("/reports?q=ravi", headers=asha).json()] == []


def _detect(client, headers, **fields):
    return client.post("/detect", headers=headers, files={"file": ("p.jpg", _photo(), "image/jpeg")}, data=fields)


def test_detect_keeps_a_private_draft_until_it_is_submitted(client):
    asha, ravi, admin = _register(client), _register(client, "ravi@example.com", "Ravi"), _make_admin(client)
    draft = _detect(client, asha, latitude="17.385", longitude="78.4867").json()["report"]
    assert draft["submitted"] is False and draft["address"] == "FC Road" and draft["area"] == "Shivajinagar"
    assert draft["confidence"] == 0.9 and len(draft["detections"]) == 2

    # The owner can look at the draft; nobody else can, and it is listed and counted nowhere.
    assert client.get(f"/reports/{draft['id']}", headers=asha).status_code == 200
    assert client.get(f"/reports/{draft['id']}/image", headers=asha).status_code == 200
    for other in (ravi, admin):
        assert client.get(f"/reports/{draft['id']}", headers=other).status_code == 404
        assert client.post(f"/reports/{draft['id']}/submit", headers=other).status_code == 404
    for viewer in (asha, admin):
        assert client.get("/reports", headers=viewer).json() == []
        assert client.get("/stats", headers=viewer).json()["total"] == 0
        assert client.get("/potholes", headers=viewer).json() == []
        assert client.get("/dashboard", headers=viewer).json()["total"] == 0
    assert client.get(f"/potholes/{draft['id']}", headers=asha).status_code == 404
    assert client.get("/potholes/nearby?lat=17.385&lng=78.4867", headers=asha).json() == []

    submitted = client.post(f"/reports/{draft['id']}/submit", headers=asha)
    assert submitted.status_code == 200 and submitted.json()["submitted"] is True
    assert [r["id"] for r in client.get("/reports", headers=admin).json()] == [draft["id"]]
    assert client.get("/dashboard", headers=ravi).json()["total"] == 1
    # Submitting twice is harmless.
    assert client.post(f"/reports/{draft['id']}/submit", headers=asha).status_code == 200


def test_a_reporter_can_discard_a_draft_but_not_a_submitted_report(client):
    asha, ravi = _register(client), _register(client, "ravi@example.com", "Ravi")
    draft_id = _detect(client, asha).json()["report"]["id"]
    files_before = set(os.listdir(UPLOAD_DIR))

    assert client.delete(f"/reports/{draft_id}", headers=ravi).status_code == 404
    assert client.delete(f"/reports/{draft_id}", headers=asha).status_code == 204
    assert client.get(f"/reports/{draft_id}", headers=asha).status_code == 404
    assert len(files_before - set(os.listdir(UPLOAD_DIR))) == 2

    kept = _detect(client, asha).json()["report"]["id"]
    client.post(f"/reports/{kept}/submit", headers=asha)
    assert client.delete(f"/reports/{kept}", headers=asha).status_code == 403


def test_detect_validates_location_and_saves_nothing_without_potholes(client, monkeypatch):
    headers = _register(client)
    assert _detect(client, headers, latitude="17.385").status_code == 422
    monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: [])
    assert _detect(client, headers).json() == {"report": None}


def test_everyone_sees_submitted_potholes_without_reporter_or_photo(client):
    asha, ravi = _register(client), _register(client, "ravi@example.com", "Ravi")
    report_id = _submit(client, asha, latitude="17.385", longitude="78.4867").json()["report"]["id"]

    seen = client.get("/potholes", headers=ravi).json()
    assert [p["id"] for p in seen] == [report_id]
    pothole = seen[0]
    assert pothole["severity"] == "MED" and pothole["status"] == "pending" and pothole["mine"] is False
    assert pothole["address"] == "FC Road" and pothole["area"] == "Shivajinagar" and pothole["confidence"] == 0.9
    assert not {"reporter_name", "reporter_email", "detections"} & pothole.keys()
    assert client.get("/potholes", headers=asha).json()[0]["mine"] is True
    assert client.get(f"/potholes/{report_id}", headers=ravi).json()["id"] == report_id
    # The photo and the full report stay with the reporter and admins.
    assert client.get(f"/reports/{report_id}/image", headers=ravi).status_code == 404
    assert client.get("/potholes").status_code == 401


def test_nearby_returns_open_potholes_in_range_most_severe_first(client, monkeypatch):
    asha, admin = _register(client), _make_admin(client)

    def report_at(latitude, detections):
        monkeypatch.setattr(main, "predict_from_pil", lambda img, conf=None, iou=None: detections)
        return _submit(client, asha, latitude=str(latitude), longitude="78.4867").json()["report"]["id"]

    # One degree of latitude is about 111 km, so these are roughly 110 m, 330 m and 5.5 km north.
    low_near = report_at(17.386, [MINOR])
    high_far = report_at(17.388, [SEVERE, SEVERE])
    out_of_range = report_at(17.435, [SEVERE])
    without_location = _submit(client, asha).json()["report"]["id"]

    def nearby(query=""):
        return client.get(f"/potholes/nearby?lat=17.385&lng=78.4867{query}", headers=admin).json()

    found = nearby()
    assert [p["id"] for p in found] == [high_far, low_near]
    assert found[1]["distance_m"] == pytest.approx(111, abs=3) and found[0]["distance_m"] == pytest.approx(334, abs=5)
    assert [p["id"] for p in nearby("&radius=200")] == [low_near]
    assert [p["id"] for p in nearby("&major_only=true")] == [high_far]
    assert out_of_range in [p["id"] for p in nearby("&radius=10000")]
    assert without_location not in [p["id"] for p in nearby("&radius=50000")]

    client.patch(f"/reports/{high_far}", headers=admin, json={"status": "resolved"})
    assert [p["id"] for p in nearby()] == [low_near]
    assert client.get("/potholes/nearby?lat=17.385", headers=admin).status_code == 422
    assert client.get("/potholes/nearby?lat=17.385&lng=78.4867&radius=5", headers=admin).status_code == 422


def test_dashboard_summarises_every_submitted_report(client, monkeypatch):
    asha, admin = _register(client), _make_admin(client)
    first = _submit(client, asha, latitude="17.385", longitude="78.4867").json()["report"]["id"]
    second = _submit(client, asha, latitude="17.386", longitude="78.4867").json()["report"]["id"]
    monkeypatch.setattr(main, "reverse_geocode", lambda lat, lng: ("Karve Road", "Kothrud"))
    _submit(client, asha, latitude="17.5", longitude="78.5")
    _submit(client, asha)  # no location, so no area
    client.patch(f"/reports/{first}", headers=admin, json={"status": "resolved"})
    client.patch(f"/reports/{second}", headers=admin, json={"status": "in_review"})

    data = client.get("/dashboard", headers=asha).json()
    assert (data["total"], data["unresolved"], data["resolved"], data["verified"]) == (4, 3, 1, 2)
    assert (data["high"], data["medium"], data["low"]) == (0, 4, 0)
    assert len(data["week"]) == 7 and data["week"][-1]["count"] == 4
    assert sum(day["count"] for day in data["week"][:-1]) == 0
    assert data["week"] == sorted(data["week"], key=lambda day: day["date"])
    assert data["hotspots"] == [{"area": "Shivajinagar", "count": 2}, {"area": "Kothrud", "count": 1}]
    assert client.get("/dashboard").status_code == 401


def test_only_admins_can_change_or_delete(client):
    asha = _register(client)
    report_id = _submit(client, asha).json()["report"]["id"]
    assert client.patch(f"/reports/{report_id}", headers=asha, json={"status": "resolved"}).status_code == 403
    assert client.delete(f"/reports/{report_id}", headers=asha).status_code == 403


def test_admin_sees_all_filters_updates_and_deletes(client):
    asha, admin = _register(client), _make_admin(client)
    report_id = _submit(client, asha).json()["report"]["id"]

    listed = client.get("/reports", headers=admin).json()
    assert [r["reporter_email"] for r in listed] == ["asha@example.com"]

    resolved = client.patch(f"/reports/{report_id}", headers=admin, json={"status": "resolved"})
    assert resolved.status_code == 200 and resolved.json()["resolved_at"] is not None
    assert client.get("/reports?status=pending", headers=admin).json() == []
    assert len(client.get("/reports?status=resolved&risk=MED", headers=admin).json()) == 1
    assert client.patch(f"/reports/{report_id}", headers=admin, json={"status": "bogus"}).status_code == 422

    reopened = client.patch(f"/reports/{report_id}", headers=admin, json={"status": "in_review"})
    assert reopened.json()["resolved_at"] is None

    files_before = set(os.listdir(UPLOAD_DIR))
    assert client.delete(f"/reports/{report_id}", headers=admin).status_code == 204
    assert client.get(f"/reports/{report_id}", headers=admin).status_code == 404
    assert len(files_before - set(os.listdir(UPLOAD_DIR))) == 2

