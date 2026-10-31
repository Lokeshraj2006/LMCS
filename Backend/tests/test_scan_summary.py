"""The scan summary PDF, in English and Tamil, for whoever may see the scan."""

from __future__ import annotations

import html
import json
from datetime import datetime, timezone
from pathlib import Path

import pymupdf
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.security import create_access_token
from app.database import Base, get_db
from app.main import app
from app.models.user import User
from app.routers import scan as scan_router
from app.schemas.inspection import InspectionDetailResponse
from app.services.scan_summary import RULE_NAMES_TA, TEXT, summary_html
from app.scripts.seed_rules import RULES

PHOTO = Path(__file__).parent / "fixtures" / "barcode" / "pack_a_back_barcode.png"
# No net quantity and no label text: Rule 4 fails, so the verdict is action needed.
FAILING = {"ocr_fields": {"mrp": 109.0}}


@pytest.fixture()
def env(tmp_path, monkeypatch):
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Session = sessionmaker(bind=engine, autoflush=False)
    Base.metadata.create_all(engine)
    tokens = {}
    with Session() as db:
        for username, role in (("consumer_one", "consumer"), ("consumer_two", "consumer"),
                               ("inspector_one", "inspector")):
            user = User(email=f"{username}@lm.test", username=username,
                        hashed_password="unused", full_name=username, role=role)
            db.add(user)
            db.flush()
            tokens[username] = create_access_token(subject=user.id, role=role)
        db.commit()

    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = override_get_db
    monkeypatch.setattr(scan_router, "_resolve_upload_dir", lambda: tmp_path)
    try:
        http = TestClient(app)
        with PHOTO.open("rb") as f:
            r = http.post("/scan", headers=_auth(tokens["consumer_one"]),
                          files={"image": ("pack.png", f, "image/png")},
                          data={"context": json.dumps(FAILING)})
        assert r.status_code == 201, r.text
        yield http, tokens, r.json()["evidence_record_id"]
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous
        Base.metadata.drop_all(engine)
        engine.dispose()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _summary(http, token, scan_id, lang="en"):
    return http.get(f"/inspections/{scan_id}/summary.pdf", params={"lang": lang}, headers=_auth(token))


def _fonts(pdf: bytes):
    return {f[3] for page in pymupdf.open("pdf", pdf) for f in page.get_fonts()}


# ── Endpoint ─────────────────────────────────────────────────────────────
@pytest.mark.parametrize("lang", ["en", "ta"])
def test_owner_gets_a_one_page_pdf_in_either_language(env, lang):
    http, t, scan_id = env
    r = _summary(http, t["consumer_one"], scan_id, lang)
    assert r.status_code == 200, r.text
    assert r.headers["content-type"] == "application/pdf"
    assert f"LMCS_scan_{scan_id}_{lang}.pdf" in r.headers["content-disposition"]
    doc = pymupdf.open("pdf", r.content)
    assert doc.page_count == 1
    assert f"#{scan_id}" in doc[0].get_text()


def test_tamil_pdf_carries_a_tamil_font_and_english_does_not(env):
    http, t, scan_id = env
    ta = _fonts(_summary(http, t["consumer_one"], scan_id, "ta").content)
    en = _fonts(_summary(http, t["consumer_one"], scan_id, "en").content)
    assert any("Tamil" in f for f in ta)
    assert not any("Tamil" in f for f in en)


def test_another_consumer_cannot_get_the_summary(env):
    http, t, scan_id = env
    assert _summary(http, t["consumer_two"], scan_id).status_code == 403


def test_an_inspector_can_get_any_scans_summary(env):
    http, t, scan_id = env
    assert _summary(http, t["inspector_one"], scan_id, "ta").status_code == 200


def test_unknown_language_is_refused(env):
    http, t, scan_id = env
    assert _summary(http, t["consumer_one"], scan_id, "hi").status_code == 422


def test_missing_scan_is_404(env):
    http, t, _ = env
    assert _summary(http, t["inspector_one"], 9999).status_code == 404


# ── Wording (checked on the HTML: shaped Tamil can't be read back from a PDF) ─
def _detail(env_tuple):
    http, t, scan_id = env_tuple
    return InspectionDetailResponse(**http.get(f"/inspections/{scan_id}", headers=_auth(t["inspector_one"])).json())


def test_tamil_page_uses_tamil_verdict_and_rule_names(env):
    page = summary_html(_detail(env), "ta", datetime(2026, 10, 31, tzinfo=timezone.utc))
    assert TEXT["ta"]["action_needed"] in page
    assert RULE_NAMES_TA["NET_QUANTITY"] in page
    assert TEXT["ta"]["FAIL"] in page
    assert "ACTION NEEDED" not in page


def test_page_says_it_is_not_a_notice(env):
    d = _detail(env)
    for lang in ("en", "ta"):
        assert html.escape(TEXT[lang]["not_notice"]) in summary_html(d, lang, datetime.now(timezone.utc))


def test_every_rule_has_a_tamil_name():
    assert {r["rule_code"] for r in RULES} == set(RULE_NAMES_TA)


def test_both_languages_have_the_same_wording_keys():
    assert set(TEXT["en"]) == set(TEXT["ta"])
