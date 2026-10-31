"""
LMCS — Scan summary PDF, in English or Tamil

A one-page record of a scan for the person who took it: the verdict, all 13
checks, and the evidence (fingerprint, place, time). It is not the
Controller's compliance report or a GO notice, and says so on the page.

Tamil needs real text shaping: vowel signs such as ொ and ை are drawn around
the consonant, not after it. ReportLab doesn't shape, so this page is laid
out as HTML with PyMuPDF, which shapes with HarfBuzz and carries a Noto Tamil
font. Text copied out of the Tamil PDF can come out scrambled, a known limit
of shaped scripts in PDF; what is printed and read on screen is correct.
"""

from __future__ import annotations

import hashlib
import html
import io
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Optional, Tuple

import pymupdf
from PIL import Image, ImageOps

from app.schemas.inspection import InspectionDetailResponse

LANGS = ("en", "ta")
IST = timezone(timedelta(hours=5, minutes=30))

# Rule names by rule_code. The provision text stays as the statute cites it.
RULE_NAMES_TA: Dict[str, str] = {
    "MANUFACTURER_DETAILS": "உற்பத்தியாளர் / பொதி செய்பவர் / இறக்குமதியாளர் பெயர், முகவரி",
    "COUNTRY_OF_ORIGIN": "பிறப்பிட நாடு",
    "GENERIC_NAME": "பொருளின் பொதுப் பெயர்",
    "NET_QUANTITY": "நிகர அளவு அறிவிப்பு",
    "MRP_DECLARATION": "அதிகபட்ச சில்லறை விலை (MRP)",
    "MFG_DATE": "தயாரித்த / பொதி செய்த மாதம், ஆண்டு",
    "EXPIRY_DATE": "சிறந்த பயன்பாட்டு / காலாவதி தேதி",
    "CONSUMER_CARE": "நுகர்வோர் சேவை தொடர்பு விவரங்கள்",
    "FONT_SIZE": "அறிவிப்புகளின் குறைந்தபட்ச எழுத்து அளவு",
    "READABILITY": "தெளிவு மற்றும் நிற வேறுபாடு",
    "PLACEMENT": "முதன்மைக் காட்சிப் பகுதியில் இடம்",
    "LMPC_REGISTRATION": "LMPC பதிவு எண்",
    "GSTIN_FORMAT": "GSTIN வடிவம் மற்றும் சரிபார்ப்பு இலக்கம்",
}

TEXT: Dict[str, Dict[str, str]] = {
    "en": {
        "dept": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "title": "Scan Summary",
        "not_notice": "This is a record of a scan. It is not a notice: only the Controller of Legal "
                      "Metrology can issue one, after an inspector's report.",
        "scan": "Scan", "product": "Product", "barcode": "Barcode", "scanned_by": "Scanned by",
        "captured": "Captured", "place": "Place (GPS)", "verdict": "Verdict",
        "checks_failed": "{failed} of {total} checks failed",
        "compliant": "COMPLIANT", "needs_review": "NEEDS REVIEW", "action_needed": "ACTION NEEDED",
        "checks": "The 13 checks", "rule": "Check", "provision": "Provision", "result": "Result",
        "detail": "Detail",
        "PASS": "Pass", "FAIL": "Fail", "REVIEW": "Check by hand", "EXEMPT": "Not applicable",
        "evidence": "Evidence", "fingerprint": "SHA-256 fingerprint",
        "photo_ok": "The stored photo still matches this fingerprint.",
        "photo_bad": "The stored photo no longer matches this fingerprint.",
        "photo_missing": "The photo is no longer on the server.",
        "ntp": "Clock checked against internet time", "drift": "difference {s} s",
        "review_note": "“Check by hand” is not a violation: the photo could not settle it, "
                       "so a person checks the pack.",
        "footer": "Made by LMCS on {when}.",
        "unknown": "—",
    },
    "ta": {
        "dept": "சட்டமுறை எடையளவு (பொட்டலப் பொருட்கள்) விதிகள், 2011",
        "title": "ஸ்கேன் சுருக்க அறிக்கை",
        "not_notice": "இது ஒரு ஸ்கேனின் பதிவு மட்டுமே; அறிவிப்பு அல்ல. ஆய்வாளரின் அறிக்கைக்குப் பிறகு "
                      "சட்டமுறை எடையளவு கட்டுப்பாட்டு அலுவலர் மட்டுமே அறிவிப்பை வெளியிட முடியும்.",
        "scan": "ஸ்கேன்", "product": "பொருள்", "barcode": "பார்கோடு", "scanned_by": "ஸ்கேன் செய்தவர்",
        "captured": "எடுத்த நேரம்", "place": "இடம் (GPS)", "verdict": "முடிவு",
        "checks_failed": "{total} சோதனைகளில் {failed} தோல்வி",
        "compliant": "விதிமுறைக்கு இணக்கம்", "needs_review": "சரிபார்ப்பு தேவை",
        "action_needed": "நடவடிக்கை தேவை",
        "checks": "13 சோதனைகள்", "rule": "சோதனை", "provision": "விதி", "result": "முடிவு",
        "detail": "விவரம் (ஆங்கிலத்தில்)",
        "PASS": "சரி", "FAIL": "தோல்வி", "REVIEW": "நேரில் சரிபார்க்கவும்", "EXEMPT": "பொருந்தாது",
        "evidence": "சான்று", "fingerprint": "SHA-256 டிஜிட்டல் கைரேகை",
        "photo_ok": "சேமித்த புகைப்படம் இந்தக் கைரேகையுடன் இன்னும் பொருந்துகிறது.",
        "photo_bad": "சேமித்த புகைப்படம் இந்தக் கைரேகையுடன் பொருந்தவில்லை.",
        "photo_missing": "புகைப்படம் சர்வரில் இல்லை.",
        "ntp": "இணைய நேரத்துடன் சரிபார்த்த கடிகாரம்", "drift": "வேறுபாடு {s} வினாடி",
        "review_note": "“நேரில் சரிபார்க்கவும்” என்பது விதிமீறல் அல்ல: புகைப்படத்தால் முடிவு செய்ய "
                       "முடியவில்லை, எனவே ஒருவர் பொட்டலத்தை நேரில் பார்ப்பார்.",
        "footer": "LMCS உருவாக்கியது: {when}.",
        "unknown": "—",
    },
}

VERDICT_COLOURS = {"compliant": "#1E7B3C", "needs_review": "#A35A00", "action_needed": "#B3261E"}
STATUS_COLOURS = {"PASS": "#1E7B3C", "FAIL": "#B3261E", "REVIEW": "#A35A00", "EXEMPT": "#5F6B7A"}

CSS = """
* { font-family: sans-serif; }
body { font-size: 10pt; color: #1a1a1a; }
.dept { font-size: 9pt; color: #5F6B7A; margin: 0; }
h1 { font-size: 18pt; color: #7A3209; margin: 2pt 0 4pt 0; }
h2 { font-size: 12pt; color: #8F3D0E; margin: 10pt 0 4pt 0; }
.note { font-size: 8pt; color: #5F6B7A; margin: 2pt 0; }
table { border-collapse: collapse; width: 100%; }
td, th { border: 0.6pt solid #C9A47E; padding: 2pt 3pt; vertical-align: top; text-align: left; font-size: 8.5pt; }
th { background-color: #EFE4D2; color: #5A2A08; }
.kv td { border: none; padding: 1pt 4pt 1pt 0; font-size: 9pt; }
.key { color: #5F6B7A; }
.verdict td { border: 1.2pt solid; padding: 5pt 8pt; font-size: 13pt; font-weight: bold; }
.hash { font-family: monospace; font-size: 7.5pt; }
.small { font-size: 7.5pt; color: #444444; }
"""
VERDICT_TINTS = {"compliant": "#E3F4E7", "needs_review": "#FFF1D6", "action_needed": "#FCE4E2"}

PAGE = pymupdf.paper_rect("a4")
MARGIN = 36


def _when(dt: Optional[datetime], unknown: str) -> str:
    if dt is None:
        return unknown
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(IST).strftime("%d %b %Y, %H:%M IST")


def _photo_state(path: str, recorded: str) -> str:
    p = Path(path)
    if not p.is_file():
        return "photo_missing"
    return "photo_ok" if hashlib.sha256(p.read_bytes()).hexdigest() == recorded else "photo_bad"


def _first_sentence(text: str, limit: int = 110) -> str:
    """The gist of a check's English reason, short enough for the table."""
    s = text.split(". ")[0].rstrip(".") + "."
    return s if len(s) <= limit else s[: limit - 1].rstrip() + "…"


def summary_html(d: InspectionDetailResponse, lang: str, made_at: datetime) -> str:
    """The page as HTML. Separate from rendering so the wording can be tested
    directly (shaped Tamil can't be read back out of the PDF reliably)."""
    t = TEXT[lang]
    e = html.escape
    ev = d.evidence
    verdict = d.overall_status if d.overall_status in VERDICT_COLOURS else "compliant"
    place = (f"{ev.gps_latitude:.5f}, {ev.gps_longitude:.5f}"
             if ev.gps_latitude is not None and ev.gps_longitude is not None else t["unknown"])
    if ev.gps_latitude is not None and ev.gps_accuracy_meters is not None:
        place += f" (±{ev.gps_accuracy_meters:.0f} m)"
    who = d.captured_by_username or t["unknown"]
    if d.captured_by_username and d.captured_by_role:
        who = f"{d.captured_by_username} ({d.captured_by_role})"

    kv = [
        (t["scan"], f"#{d.evidence_record_id}"), (t["product"], d.product_name or t["unknown"]),
        (t["barcode"], d.barcode or t["unknown"]), (t["scanned_by"], who),
        (t["captured"], _when(ev.timestamp_device, t["unknown"])), (t["place"], place),
    ]
    colour, tint = VERDICT_COLOURS[verdict], VERDICT_TINTS[verdict]
    failed = t["checks_failed"].format(failed=d.failed_checks, total=d.total_checks)
    # The photo is drawn top right after layout (see render_scan_summary), so
    # the header lines are kept short enough to stay clear of it.
    parts = [
        f'<p class="dept">{e(t["dept"])}</p>',
        f'<h1>{e(t["title"])}</h1>',
        '<table class="kv">',
        *(f'<tr><td class="key">{e(k)}</td><td>{e(v)}</td></tr>' for k, v in kv),
        "</table>",
        f'<table class="verdict"><tr><td style="color:{colour}; background-color:{tint}; border-color:{colour}">'
        f'{e(t["verdict"])}: {e(t[verdict])} '
        f'<span style="font-size:9pt; font-weight:normal; color:#1a1a1a">({e(failed)})</span></td></tr></table>',
        f'<p class="note">{e(t["not_notice"])}</p>',
        f'<h2>{e(t["checks"])}</h2>',
        "<table>",
        f'<tr><th>#</th><th>{e(t["rule"])}</th><th>{e(t["provision"])}</th>'
        f'<th>{e(t["result"])}</th><th>{e(t["detail"])}</th></tr>',
    ]
    for rc in d.rule_checks:
        status = rc.status.upper()
        name = RULE_NAMES_TA.get(rc.rule_code, rc.rule_name) if lang == "ta" else rc.rule_name
        provision = rc.statutory_reference.split(",")[0]
        detail = _first_sentence(rc.failure_reason) if status != "PASS" and rc.failure_reason else ""
        parts.append(
            f"<tr><td>{rc.rule_number}</td><td>{e(name)}</td><td>{e(provision)}</td>"
            f'<td style="color:{STATUS_COLOURS.get(status, "#1a1a1a")}"><b>{e(t.get(status, status))}</b></td>'
            f'<td class="small">{e(detail)}</td></tr>'
        )
    parts.append("</table>")
    parts.append(f'<p class="note">{e(t["review_note"])}</p>')

    photo = t[_photo_state(ev.file_path, ev.sha256_hash)]
    ntp = t["unknown"]
    if ev.timestamp_ntp is not None:
        ntp = _when(ev.timestamp_ntp, t["unknown"])
        if ev.ntp_drift_seconds is not None:
            ntp += f" ({t['drift'].format(s=f'{ev.ntp_drift_seconds:.1f}')})"
    parts += [
        f'<h2>{e(t["evidence"])}</h2>',
        '<table class="kv">',
        f'<tr><td class="key">{e(t["fingerprint"])}</td><td class="hash">{e(ev.sha256_hash)}</td></tr>',
        f'<tr><td class="key"></td><td class="small">{e(photo)}</td></tr>',
        f'<tr><td class="key">{e(t["ntp"])}</td><td>{e(ntp)}</td></tr>',
        "</table>",
        f'<p class="note">{e(t["footer"].format(when=_when(made_at, t["unknown"])))}</p>',
    ]
    return "\n".join(parts)


def render_scan_summary(d: InspectionDetailResponse, lang: str,
                        made_at: Optional[datetime] = None) -> Tuple[bytes, str]:
    """Return the PDF bytes and a filename for one scan, in `lang` ("en" or "ta")."""
    if lang not in LANGS:
        raise ValueError(f"Unsupported language {lang!r}")
    made_at = made_at or datetime.now(timezone.utc)
    story = pymupdf.Story(html=summary_html(d, lang, made_at), user_css=CSS)

    # Fill pages until the whole story is placed (the table may run on).
    sink = io.BytesIO()
    writer = pymupdf.DocumentWriter(sink)
    area = pymupdf.Rect(MARGIN, MARGIN, PAGE.width - MARGIN, PAGE.height - MARGIN)
    more = True
    while more:
        device = writer.begin_page(PAGE)
        more, _ = story.place(area)
        story.draw(device)
        writer.end_page()
    writer.close()

    doc = pymupdf.open("pdf", sink.getvalue())
    thumb = _thumbnail(d.evidence.file_path)
    if thumb is not None:
        box = pymupdf.Rect(PAGE.width - MARGIN - 95, MARGIN, PAGE.width - MARGIN, MARGIN + 118)
        doc[0].insert_image(box, stream=thumb, keep_proportion=True)
    doc.set_metadata({"title": f"LMCS scan #{d.evidence_record_id} ({lang})", "creator": "LMCS"})
    return doc.tobytes(garbage=3, deflate=True), f"LMCS_scan_{d.evidence_record_id}_{lang}.pdf"


def _thumbnail(path: str) -> Optional[bytes]:
    """A small JPEG of the evidence photo for the page, or None if unreadable.

    The page shows what was scanned; the full photo, the one the fingerprint
    covers, stays on the server.
    """
    p = Path(path)
    if not p.is_file():
        return None
    try:
        with Image.open(p) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")
            im.thumbnail((480, 480))
            out = io.BytesIO()
            im.save(out, "JPEG", quality=80)
            return out.getvalue()
    except (OSError, ValueError):
        return None
