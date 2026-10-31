"""
LMCS — Application Configuration

Centralised settings loaded from environment variables / .env file.
Uses pydantic-settings for validation and type coercion.
"""

from __future__ import annotations

from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application-wide settings, sourced from env vars / .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ── Database ───────────────────────────────────────────────
    database_url: str = "postgresql://labelguard:labelguard_dev@localhost:5432/labelguard_db"

    # ── JWT / Auth ─────────────────────────────────────────────
    secret_key: str = "CHANGE_ME"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    # ── Evidence storage ───────────────────────────────────────
    storage_backend: str = "local"  # "local" | "gcs"
    local_storage_path: str = "./uploads"
    gcs_bucket_name: str | None = None

    # ── NTP ────────────────────────────────────────────────────
    ntp_server: str = "pool.ntp.org"
    ntp_max_drift_seconds: int = 5

    # ── Application ────────────────────────────────────────────
    app_name: str = "LMCS"
    app_version: str = "0.1.0"
    debug: bool = False
    log_level: str = "INFO"
    cors_origins: List[str] = ["http://localhost:5173", "http://localhost:3000"]

    # ── Upload & compute limits (CPU-only, sized for a small server) ──
    # Phone photos stored so far are at most 2.4 MB; 15 MB leaves room
    # without letting one request fill memory.
    max_upload_mb: int = 15
    # Scans analysed at the same time. Image analysis is CPU-bound, so more
    # than one per core only adds queueing inside the CPU and memory peaks.
    # 0 = one per CPU core.
    max_concurrent_scans: int = 0

    # ── Login lockout ──────────────────────────────────────────
    login_max_failures: int = 5
    login_lockout_minutes: int = 15


# Secrets shipped in this repo's examples; never acceptable outside debug.
PLACEHOLDER_SECRETS = {
    "CHANGE_ME",
    "CHANGE_ME_TO_A_RANDOM_64_CHAR_HEX_STRING",
    "docker_dev_secret_key_change_in_production",
}


def secret_key_problem(s: "Settings") -> str | None:
    """Why the signing key is unsafe for a non-debug run, or None if it is fine."""
    if s.debug:
        return None
    if s.secret_key in PLACEHOLDER_SECRETS:
        return "SECRET_KEY is still the example placeholder."
    if len(s.secret_key) < 32:
        return "SECRET_KEY is shorter than 32 characters."
    return None


# Singleton instance — import this everywhere
settings = Settings()
