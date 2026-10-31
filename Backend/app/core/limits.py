"""
LMCS — Request limits

Login lockout and the cap on scans analysed at once. Both are in-process:
they hold for one server process, which is how this app is deployed (one
uvicorn worker). Behind several workers each would keep its own count.
"""

from __future__ import annotations

import os
import threading
import time
from collections import deque
from typing import Deque, Dict, Iterator, Tuple

from fastapi import HTTPException, UploadFile, status

from app.config import settings


# ── Login lockout ────────────────────────────────────────────────
class LoginLockout:
    """Refuse logins for an (address, account) pair after repeated failures.

    Keyed on both, so one guesser can't lock a real officer out from
    another address, and a successful login clears the count.
    """

    def __init__(self, max_failures: int, window_seconds: float):
        self.max_failures = max_failures
        self.window = window_seconds
        self._failures: Dict[Tuple[str, str], Deque[float]] = {}
        self._lock = threading.Lock()

    def _recent(self, key: Tuple[str, str], now: float) -> Deque[float]:
        times = self._failures.setdefault(key, deque())
        while times and now - times[0] > self.window:
            times.popleft()
        return times

    def check(self, address: str, account: str) -> None:
        """Raise 429 if this pair is locked out."""
        key = (address, account.strip().lower())
        now = time.monotonic()
        with self._lock:
            times = self._recent(key, now)
            if len(times) >= self.max_failures:
                retry = int(self.window - (now - times[0])) + 1
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=(
                        f"Too many failed logins. Try again in {max(retry // 60, 1)} minute(s)."
                    ),
                    headers={"Retry-After": str(retry)},
                )

    def failed(self, address: str, account: str) -> None:
        key = (address, account.strip().lower())
        now = time.monotonic()
        with self._lock:
            self._recent(key, now).append(now)

    def succeeded(self, address: str, account: str) -> None:
        with self._lock:
            self._failures.pop((address, account.strip().lower()), None)

    def reset(self) -> None:
        with self._lock:
            self._failures.clear()


login_lockout = LoginLockout(
    max_failures=settings.login_max_failures,
    window_seconds=settings.login_lockout_minutes * 60,
)


# ── Scan analysis slots ──────────────────────────────────────────
def scan_slot_count() -> int:
    return settings.max_concurrent_scans or os.cpu_count() or 1


_scan_slots = threading.BoundedSemaphore(scan_slot_count())


def scan_slot() -> Iterator[None]:
    """FastAPI dependency: hold one analysis slot for the whole scan.

    Image analysis is CPU-bound and needs a decoded copy of each photo in
    memory, so on a small server extra scans wait their turn instead of
    all running at once.
    """
    _scan_slots.acquire()
    try:
        yield
    finally:
        _scan_slots.release()


# ── Upload checks ────────────────────────────────────────────────
def read_photo(upload: UploadFile, label: str) -> bytes:
    """Read an uploaded photo, refusing one that is too large or not an image.

    Reads at most one byte past the limit, so an oversized upload is never
    loaded into memory whole. Empty uploads are returned as b"" for the
    caller to handle.
    """
    limit = settings.max_upload_mb * 1024 * 1024
    data = upload.file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"{label} is larger than the {settings.max_upload_mb} MB limit.",
        )
    if not data:
        return data
    check_photo_type(data, label)
    return data


def check_photo_type(data: bytes, label: str) -> None:
    """Reject bytes that aren't a JPEG, PNG or WebP image."""
    is_jpeg = data[:3] == b"\xff\xd8\xff"
    is_png = data[:8] == b"\x89PNG\r\n\x1a\n"
    is_webp = data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    if not (is_jpeg or is_png or is_webp):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{label} is not a JPEG, PNG or WebP image.",
        )
