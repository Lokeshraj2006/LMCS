# How LMCS works

The checks, the verdicts and the limits, in detail. Back to the [README](README.md).

## Features

### Mobile app (consumers and inspectors)

- **Scan** from the camera or the gallery. ML Kit reads the text and barcode on
  the phone, and the app fills in the fields: maker and address, product name,
  net quantity, MRP and unit sale price, dates, batch, customer care, FSSAI
  licence and GSTIN.
- **Review Details**: fix anything misread; every change is recorded with the
  scan. **Scan another part** adds up to 3 photos of other faces, such as the
  seal, the lid or the veg mark, when the label says a detail is printed
  elsewhere.
- **Result**: Compliant, Needs review or Action needed, with all 13 checks and
  their reasons, the registry result, who read the barcode, the veg mark, and
  the complaint number if one was filed.
- **Consumers** see only their own scans.
- **Inspectors** get the pending complaints (as a list and on a map), the full
  scan history, their own new scans, and a report form. A registry mismatch
  can be cited only after they tick that they checked the pack themselves.
- The backend address can be changed in **Settings**, so no rebuild is needed
  to move between networks.
- Admin accounts are sent to the dashboard; the app is not for them.

### Controller dashboard (web)

- **Queue** of inspectors' reports.
- **Report page**: the evidence photo and any extra photos, a live SHA-256
  check proving each photo is unchanged since capture, GPS and time, the
  grounds cited and the inspector's notes. **Confirm** or **reject**, then
  **issue the GO show-cause notice** as a PDF.
- **System Log**: every scan, searchable by product, barcode, scan number,
  complaint number or user; a compliance report PDF per scan; CSV export.
- **Map** of complaints and reports.
- **Rules**: the 13 rules with their legal provisions. A rule switched off
  here is recorded as `EXEMPT` on new scans.

---

## What gets checked

### The 13 compliance rules

The rules are stored as data in the `rules` table, so the dashboard can list
them and switch them on or off.

| # | Check | Provision | Severity |
| --- | --- | --- | --- |
| 1 | Manufacturer / packer / importer name and address | Rule 6(1)(a) | major |
| 2 | Country of origin (imported packs) | Rule 6(1)(aa) | moderate |
| 3 | Common or generic name | Rule 6(1)(b) | major |
| 4 | Net quantity | Rule 6(1)(c) | critical |
| 5 | Retail sale price (MRP), with the unit sale price | Rule 6(1)(e) | critical |
| 6 | Month and year of manufacture / packing | Rule 6(1)(d) | major |
| 7 | Best before / use by date | Rule 6(1)(da) | major |
| 8 | Consumer care details | Rule 6(2) | moderate |
| 9 | Minimum letter height | Rule 7(2) and Table I | moderate |
| 10 | Legibility and contrast | Rule 9(1) | moderate |
| 11 | Placement on the principal display panel | Rule 8(1) | minor |
| 12 | LMPC registration number | Rule 27 | major |
| 13 | GSTIN format and checksum | CGST Rules, 2017, Rule 46 | minor |

"Rule 9" in the app means our check number 9; the **Provision** column is the
statute. Provisions are from the LMPC Rules, 2011 as amended up to 2017.

### Beyond the rules

- **Registry cross-check.** The barcode looks up the registered product, and
  the label's MRP, net quantity, FSSAI licence, GSTIN, veg mark and maker are
  compared with it. A contradiction is flagged as suspected tampering.
  - An MRP **higher** than registered is tampering. A **lower** MRP is not:
    Rule 6(3) allows a sticker that lowers the MRP, so it is recorded as a
    difference.
  - Product name and address are free text that OCR often misreads, so
    differences there are recorded but not treated as tampering. So is an
    FSSAI licence that isn't 14 digits, or is one digit off a registered one.
- **FSSAI veg / non-veg mark.** Found by its shape (a dot inside a square
  outline of the same colour, on a light label) and checked against the
  registry. If the whole shape isn't visible it says "not detected" instead of
  guessing.
- **Print measurement.** An EAN-13 barcode is printed to a standard width
  (37.29 mm), so its width in pixels gives millimetres per pixel. That turns
  letter heights into millimetres (check 9) and measures contrast (check 10).
- **Evidence.** Each photo gets a SHA-256 fingerprint, GPS with its accuracy,
  and the phone's time checked against internet (NTP) time. A submitted scan
  is never edited: a rescan is a new record linked to the first, the same
  photo sent twice is flagged, and fields the user changed are recorded.

---

## Results, and why REVIEW matters

Every check returns `PASS`, `FAIL`, `REVIEW` or `EXEMPT`.
**`REVIEW` is not a violation.** It means the system could not establish the
answer from the photo, so a person should look. This is deliberate:

- A heading that was read with no value beside it (a finger over the MRP, say)
  is `REVIEW`, not `FAIL`. A `FAIL` for a missing declaration needs the
  heading to be missing too.
- Check 9 never fails a pack from a photo. A barcode may be printed at 80–200%
  of its standard size, so a reading under the limit asks for a measurement on
  the pack.
- Check 10 passes at 4.5:1, fails only below 1.5:1, and is `REVIEW` in
  between, because phone photos understate print contrast.
- Check 11 measures whether the declarations are grouped together. It is a
  labelled proxy (`dispersion_proxy`), not true display-panel detection.
- Check 13 validates the GSTIN's format and checksum only. It never claims a
  live GST registration lookup.

Each scan gets one of three verdicts:

| Verdict | When | What happens |
| --- | --- | --- |
| **Compliant** | Every required detail was read and nothing failed | Nothing more |
| **Needs review** | Nothing failed, but a required detail couldn't be read | The user is told what to check; no complaint |
| **Action needed** | A check failed, or the label contradicts the registry | A consumer's scan files a complaint for an inspector |

**What a report can cite.** An inspector's report cites only `FAIL`ed checks,
plus one other ground: a registry mismatch in MRP, net quantity or maker, cited
under **Rule 6(3)** (no altering a declaration on the pack). That ground is
accepted only after the inspector confirms they checked the physical pack,
because a misread photo can look exactly like tampering.

**Who can do what** is enforced by the server, not just the UI. Inspectors
file reports; only the Controller confirms them and issues notices. An
inspector trying to issue a notice gets `403`, a notice before confirmation
gets `409`, and each report gets at most one notice, even when two clicks
arrive at the same moment.

---

## Known limitations

1. **OCR sets the ceiling.** A blurred, far or glossy photo can hide details.
   Most of that turns into `REVIEW` or Needs review rather than a false
   `FAIL`, and every notice still needs an inspector and the Controller.
2. **The product registry is small**: 5 illustrative products and 3 real packs
   (Haldiram's Aloo Bhujia 400 g, Ob & Gob Tiramisu & Fudge Ice Cream 200 ml,
   Amul Dark Chocolate 35 g). In real use it would be GS1 India's DataKart,
   which brand owners already fill.
3. **Letter height assumes a flat, front-on photo** and a barcode printed at
   standard size. That is why check 9 never fails a pack on its own.
4. **Contrast from a photo is indicative only.** The 1.5:1 floor was set from
   real packs, not a calibration study.
5. **Placement (check 11) is a proxy**, not true principal-display-panel
   detection.
6. **The veg mark is often "not detected"** on glossy pouches. The detector
   declines rather than guesses; a close extra photo of the mark helps.
7. **GSTIN is checked for format and checksum only**, with no live GST lookup.
8. **English labels only** for now.
