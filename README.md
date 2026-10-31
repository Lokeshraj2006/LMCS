<div align="center">

# LMCS: Legal Metrology Compliance Scanner

**Photograph a packaged product's label. LMCS checks it against the Legal Metrology
(Packaged Commodities) Rules, 2011, cross-checks it with the registered product,
and seals the photo as tamper-evident evidence.**

[![CI](https://github.com/Lokeshraj2006/LMCS/actions/workflows/ci.yml/badge.svg)](https://github.com/Lokeshraj2006/LMCS/actions/workflows/ci.yml)
![Flutter](https://img.shields.io/badge/app-Flutter-02569B?logo=flutter)
![FastAPI](https://img.shields.io/badge/server-FastAPI-009688?logo=fastapi)
![React](https://img.shields.io/badge/dashboard-React-61DAFB?logo=react&logoColor=black)
![PostgreSQL](https://img.shields.io/badge/db-PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![CPU only](https://img.shields.io/badge/runs%20on-CPU%20only-2E7D32)

Smart India Hackathon 2026 · Problem statement **SIH26034** · Team **HexTech**

<img src="assets/app.jpg" alt="The LMCS app: scanning a label, reviewing the filled-in fields, a compliant result, and the inspector's map" width="900">

</div>

## What it does

- 📷 **One photo, 13 checks.** The phone reads the label (Google ML Kit, on the device) and the server checks maker, quantity, MRP, dates, customer care, font size and more.
- 📏 **The barcode is a ruler.** An EAN-13 barcode is 37.29 mm wide, so letter height is measured in millimetres from an ordinary photo.
- 🔎 **Registry cross-check.** The barcode pulls up the registered product. A raised MRP is flagged as tampering; a lower one is an allowed sticker.
- 🔒 **Evidence that holds up.** Each photo gets a SHA-256 fingerprint, GPS and network time, and the dashboard re-checks the fingerprint every time it is viewed.
- ⚖️ **Honest verdicts.** **Compliant**, **Needs review** or **Action needed**. If the photo can't settle a check it says REVIEW and a person decides, never a guessed pass.
- 🏛️ **People decide.** A consumer's scan raises a complaint, an inspector files a report, and only the Controller confirms it and issues the GO notice. The server enforces this.

## How it works

```mermaid
flowchart LR
    A["📷 Photo<br/>+ GPS + time"] --> B["Phone reads<br/>text + barcode"]
    B --> C["User checks<br/>the fields"]
    C --> D["Server: seal evidence,<br/>13 rules, registry"]
    D --> E{"Verdict"}
    E --> F["✅ Compliant"]
    E --> G["🟠 Needs review"]
    E --> H["🔴 Action needed"]
    H --> I["Inspector report"] --> J["Controller confirms"] --> K["GO notice PDF"]
```

<div align="center">
<img src="assets/dashboard.jpg" alt="The Controller's dashboard showing the rule catalogue with each rule's statutory provision" width="820">
<br><sub>The Controller's dashboard: rule catalogue with statutory provisions and on/off switches</sub>
</div>

## Built with

| Part | Folder | Stack |
| --- | --- | --- |
| 📱 Mobile app (consumers, inspectors) | [`mobile/`](mobile/) | Flutter, Google ML Kit |
| 🖥️ Server | [`Backend/`](Backend/) | FastAPI, PostgreSQL, OpenCV, pyzbar, ReportLab |
| 📊 Dashboard (Controller) | [`Frontend/`](Frontend/) | React, Vite, Leaflet |

**Cheap to run:** no GPU and no ML framework. The server takes **0.31 s of CPU per photo** on one core (median over 53 real photos), so a 1 vCPU / 1 GB server is enough.

## Quick start

```bash
docker compose up --build
```

Dashboard at <http://localhost:8080>, API at <http://localhost:8000/docs>. Create the first admin with the command at the top of [`docker-compose.yml`](docker-compose.yml).

Running each part by hand, building the Android app, and troubleshooting are in **[SETUP.md](SETUP.md)**.

## Tests

```bash
cd Backend && python -m pytest tests/ -q     # 352 tests
cd mobile  && flutter test                   # 100 tests
```

GitHub Actions runs both, plus the dashboard build, on every push.

## Learn more

- **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)**: the 13 rules and their provisions, the registry check, why REVIEW is not a violation, and known limitations
- **[SETUP.md](SETUP.md)**: full setup, accounts, API overview, troubleshooting

> **Status:** working prototype, tested end to end on real packs. It is not a production deployment.

<div align="center"><sub>Team HexTech · Smart India Hackathon 2026</sub></div>
