"""Upload limits, login lockout, the startup key check, and the CPU-only promise."""

from __future__ import annotations

import json
import re
import threading
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import Settings, secret_key_problem, settings
from app.core import limits
from app.core.security import create_access_token, get_password_hash
from app.database import Base, get_db
from app.main import app
from app.models.user import User
from app.routers import scan as scan_router

BACKEND = Path(__file__).resolve().parent.parent
PHOTO = Path(__file__).parent / "fixtures" / "barcode" / "pack_a_back_barcode.png"


@pytest.fixture()
def client(tmp_path, monkeypatch):
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Session = sessionmaker(bind=engine, autoflush=False)
    Base.metadata.create_all(engine)
    with Session() as db:
        user = User(
            email="officer@lm.test", username="officer_one",
            hashed_password=get_password_hash("Password123!"),
            full_name="Officer One", role="inspector",
        )
        db.add(user)
        db.commit()
        token = create_access_token(subject=user.id, role="inspector")

    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = override_get_db
    monkeypatch.setattr(scan_router, "_resolve_upload_dir", lambda: tmp_path)
    limits.login_lockout.reset()
    try:
        yield TestClient(app), token
    finally:
        limits.login_lockout.reset()
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous


def _scan(http, token, image, extra=None):
    files = [("image", image)]
    for item in extra or []:
        files.append(("extra_images", item))
    return http.post(
        "/scan",
        headers={"Authorization": f"Bearer {token}"},
        files=files,
        data={"context": json.dumps({"ocr_fields": {}})},
    )


# ── Uploads ──────────────────────────────────────────────────────
def test_oversized_photo_is_refused_with_413(client, monkeypatch):
    http, token = client
    monkeypatch.setattr(settings, "max_upload_mb", 1)
    big = b"\xff\xd8\xff" + b"\0" * (1024 * 1024)
    response = _scan(http, token, ("big.jpg", big, "image/jpeg"))
    assert response.status_code == 413
    assert "1 MB" in response.json()["detail"]


def test_non_image_upload_is_refused(client):
    http, token = client
    response = _scan(http, token, ("notes.jpg", b"%PDF-1.7 not a photo", "image/jpeg"))
    assert response.status_code == 400
    assert "JPEG, PNG or WebP" in response.json()["detail"]


def test_non_image_extra_photo_is_refused(client):
    http, token = client
    response = _scan(
        http, token,
        ("pack.png", PHOTO.read_bytes(), "image/png"),
        extra=[("seal.jpg", b"<html>", "image/jpeg")],
    )
    assert response.status_code == 400
    assert "Extra photo 1" in response.json()["detail"]


def test_real_photo_still_scans(client):
    http, token = client
    response = _scan(http, token, ("pack.png", PHOTO.read_bytes(), "image/png"))
    assert response.status_code == 201, response.text


@pytest.mark.parametrize("data", [
    b"\xff\xd8\xff\xe0" + b"\0" * 8,
    b"\x89PNG\r\n\x1a\n" + b"\0" * 8,
    b"RIFF\0\0\0\0WEBPVP8 ",
])
def test_jpeg_png_and_webp_are_accepted(data):
    limits.check_photo_type(data, "Photo")


# ── Scan slots ───────────────────────────────────────────────────
def test_scan_slots_hold_extra_scans_back():
    slots = threading.BoundedSemaphore(1)
    original = limits._scan_slots
    limits._scan_slots = slots
    try:
        held = limits.scan_slot()
        next(held)
        assert not slots.acquire(blocking=False), "a second scan must wait"
        with pytest.raises(StopIteration):
            next(held)
        assert slots.acquire(blocking=False), "the slot is free once the scan ends"
        slots.release()
    finally:
        limits._scan_slots = original


# ── Login lockout ────────────────────────────────────────────────
def _login(http, password):
    return http.post(
        "/auth/login",
        json={"username_or_email": "officer_one", "password": password},
    )


def test_repeated_wrong_passwords_lock_the_account_out(client):
    http, _ = client
    for _ in range(settings.login_max_failures):
        assert _login(http, "wrong").status_code == 401
    locked = _login(http, "Password123!")
    assert locked.status_code == 429
    assert int(locked.headers["Retry-After"]) > 0


def test_a_good_login_clears_earlier_failures(client):
    http, _ = client
    for _ in range(settings.login_max_failures - 1):
        _login(http, "wrong")
    assert _login(http, "Password123!").status_code == 200
    for _ in range(settings.login_max_failures - 1):
        assert _login(http, "wrong").status_code == 401


def test_lockout_window_expires():
    lockout = limits.LoginLockout(max_failures=2, window_seconds=0.05)
    lockout.failed("1.2.3.4", "a")
    lockout.failed("1.2.3.4", "a")
    with pytest.raises(Exception):
        lockout.check("1.2.3.4", "a")
    time.sleep(0.1)
    lockout.check("1.2.3.4", "a")  # failures older than the window don't count


def test_lockout_is_per_address_and_account():
    lockout = limits.LoginLockout(max_failures=1, window_seconds=60)
    lockout.failed("1.2.3.4", "Officer_One")
    with pytest.raises(Exception):
        lockout.check("1.2.3.4", "officer_one")
    lockout.check("5.6.7.8", "officer_one")
    lockout.check("1.2.3.4", "someone_else")


# ── Startup key check ────────────────────────────────────────────
@pytest.mark.parametrize("key, debug, ok", [
    ("CHANGE_ME", True, True),
    ("CHANGE_ME", False, False),
    ("docker_dev_secret_key_change_in_production", False, False),
    ("short", False, False),
    ("a" * 64, False, True),
])
def test_placeholder_secret_is_refused_outside_debug(key, debug, ok):
    problem = secret_key_problem(Settings(secret_key=key, debug=debug, _env_file=None))
    assert (problem is None) is ok


# ── CPU only ─────────────────────────────────────────────────────
GPU_PACKAGES = re.compile(
    r"^(torch|torchvision|tensorflow|tensorflow-gpu|jax|jaxlib|paddlepaddle|paddlepaddle-gpu"
    r"|paddleocr|easyocr|onnxruntime-gpu|cupy\S*|nvidia-\S+|opencv-python|opencv-contrib-python"
    r"|ultralytics)(?=[\s=<>~!\[;]|$)",
    re.IGNORECASE,
)


def test_requirements_need_no_gpu_or_ml_framework():
    """The server runs on a plain CPU box; keep heavy ML stacks out.

    opencv-python (non-headless) is listed too: it pulls in GUI/GL libraries
    a server never uses. The headless build is the one to install.
    """
    lines = (BACKEND / "requirements.txt").read_text(encoding="utf-8").splitlines()
    packages = [l.split("#")[0].strip() for l in lines if l.split("#")[0].strip()]
    offending = [p for p in packages if GPU_PACKAGES.match(p)]
    assert offending == []
    assert any(p.startswith("opencv-python-headless") for p in packages)


def test_app_code_imports_no_gpu_framework():
    pattern = re.compile(r"^\s*(import|from)\s+(torch|tensorflow|jax|paddle|cupy|easyocr|ultralytics)\b", re.M)
    hits = [
        str(p.relative_to(BACKEND))
        for p in (BACKEND / "app").rglob("*.py")
        if pattern.search(p.read_text(encoding="utf-8"))
    ]
    assert hits == []
