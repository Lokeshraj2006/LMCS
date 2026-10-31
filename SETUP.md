# Setting up LMCS

Everything needed to run the server, dashboard and app from a clean clone. Back to the [README](README.md).

## Getting started

### Prerequisites

| Tool | Version | For |
| --- | --- | --- |
| Python | 3.11 | Server |
| PostgreSQL | 15 or newer | Database |
| Node.js | 18 or newer | Dashboard |
| Flutter | 3.x stable (we use 3.47) | Mobile app |
| JDK | 17 or 21 | Android builds (JDK 24/25 are not supported by the Android Gradle plugin) |
| Android SDK + NDK | NDK `28.2.13676358` | ML Kit's native parts need the NDK |

An Android phone with Google Play services is needed for ML Kit.

### 1. Database

Run these as three separate commands (`CREATE DATABASE` can't run inside a
transaction block):

```bash
psql -U postgres -c "CREATE USER labelguard WITH PASSWORD 'labelguard_dev';"
psql -U postgres -c "CREATE DATABASE labelguard_db OWNER labelguard;"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE labelguard_db TO labelguard;"
```

Add `-p <port>` if your PostgreSQL isn't on 5432.

### 2. Server

```bash
cd Backend
python -m venv venv
venv\Scripts\activate            # Windows
# source venv/bin/activate       # macOS / Linux
pip install -r requirements.txt
```

Create `Backend/.env` from the template and set a real secret key:

```bash
cp .env.example .env
python -c "import secrets; print(secrets.token_hex(32))"   # paste as SECRET_KEY
```

If your database isn't on `localhost:5432`, change `DATABASE_URL` in `.env`.
On macOS/Linux, pyzbar also needs the zbar library
(`sudo apt install libzbar0` or `brew install zbar`); on Windows it comes with
the package.

Create the tables, load the 13 rules and the product registry, and start:

```bash
alembic upgrade head
python -m app.scripts.seed_rules
python -m app.scripts.seed_product_registry
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Check it with `http://localhost:8000/health`. Interactive API docs are at
`http://localhost:8000/docs`.

### 3. Accounts

Public sign-up only creates **consumer** accounts. Inspector and admin
accounts carry enforcement powers, so they are made from the command line (or
by an admin through `POST /auth/users`):

```bash
python -m app.scripts.create_user --username test_admin --email admin@example.com \
    --full-name "Test Controller" --role admin --password "<password>"
python -m app.scripts.create_user --username test_inspector --email inspector@example.com \
    --full-name "Test Inspector" --role inspector --badge-number INSP-01 --password "<password>"
python -m app.scripts.create_user --username test_consumer --email consumer@example.com \
    --full-name "Test Consumer" --role consumer --password "<password>"
```

The app's login screen has quick sign-in buttons for `test_inspector` and
`test_consumer` using the password `Password123!`. Give those two accounts
that password if you want the buttons to work. Use them only on a local demo
server, never on a public one.

Admins sign in on the **dashboard**; the app shows them a redirect screen.

### 4. Dashboard

```bash
cd Frontend
npm install
npm run dev
```

Open `http://localhost:5173`. It must be served like this; opening
`index.html` as a file shows a blank page. The API address defaults to
`http://localhost:8000`; set `VITE_API_BASE` to change it.

### 5. Mobile app

Build with the backend address baked in, then install over USB:

```bash
cd mobile
flutter pub get
flutter build apk --debug --dart-define="LABELGUARD_API_BASE=http://localhost:8000"
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb reverse tcp:8000 tcp:8000
```

`adb reverse` tunnels the phone's `localhost:8000` to the laptop over the USB
cable. It is the most reliable setup, and it has to be run again after the
phone is unplugged or sleeps.

Over Wi-Fi instead: put the laptop's IP address (`ipconfig` / `ip addr`) in
the app's **Settings**, for example `http://192.168.1.20:8000`, and allow
port 8000 through the laptop's firewall. The Android emulator reaches the
laptop at `http://10.0.2.2:8000`, which is the app's default when nothing is
set.

**Windows note:** `mobile/android/gradle.properties` sets
`-Djdk.net.unixdomain.tmpdir=C:\jtmp`. It is needed when the Windows user name
contains a space: without it, Gradle fails with "Unable to establish loopback
connection". Create the folder once with `mkdir C:\jtmp`. On macOS or Linux,
remove that flag from `org.gradle.jvmargs`.

---

## Docker

```bash
docker compose up --build
```

This starts PostgreSQL, the API on `http://localhost:8000` (migrations and
the rules and registry seeds run on each start) and the dashboard on
`http://localhost:8080`. Create the first admin with the command at the top
of `docker-compose.yml`. The compose file runs with `DEBUG=true` and a
placeholder key; with `DEBUG=false` the server refuses to start until
`SECRET_KEY` is a real random value.

---

## Tests

```bash
cd Backend && python -m pytest tests/ -q     # 352 tests
cd mobile  && flutter test                   # 100 tests
```

Server tests run on in-memory SQLite. One test, two "Issue notice" clicks
racing each other, needs PostgreSQL and is skipped without it. GitHub Actions
runs all of these on every push, the race test included.

---

## API overview

The full, live reference is at `/docs` when the server runs.

| Method | Path | Who |
| --- | --- | --- |
| POST | `/auth/register` (consumers only), `/auth/login` | anyone |
| GET | `/auth/me` | signed in |
| POST | `/auth/users` (any role) | admin |
| POST | `/scan` (photo, extra photos, fields read on the phone) | signed in |
| GET | `/scan/history` (own scans) | signed in |
| GET | `/inspections/log` (every scan) | inspector, admin |
| GET | `/inspections/{id}`, `/inspections/{id}/image`, `/inspections/{id}/extra-image/{n}` | inspector, admin; a consumer only for their own scan |
| GET | `/complaints/pending` | inspector, admin |
| GET | `/legal-notice/{id}/generate` (compliance report PDF) | admin |
| POST | `/violations` (file a report) | inspector, admin |
| GET | `/violations`, `/violations/{id}` | inspector (own), admin (all) |
| POST | `/violations/{id}/confirm`, `/violations/{id}/reject` | admin |
| POST | `/violations/{id}/notice` | admin |
| GET | `/violations/{id}/notice.pdf` | inspector, admin |
| GET | `/rules` | signed in |
| PATCH | `/rules/{id}` (switch a rule on or off) | admin |

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Dashboard shows a blank page | Open `http://localhost:5173` (from `npm run dev`), not the file |
| App says it can't reach the server | Re-run `adb reverse tcp:8000 tcp:8000`, or check the address in the app's Settings |
| A scan is rejected with 401 | The login expired; sign in again |
| Login says "Too many failed logins" | 5 wrong passwords for one account from one device lock it for 15 minutes (`LOGIN_MAX_FAILURES`, `LOGIN_LOCKOUT_MINUTES`); restarting the server also clears it |
| Server won't start: "SECRET_KEY is still the example placeholder" | With `DEBUG=false` a real key is required; generate one with `python -c "import secrets; print(secrets.token_hex(32))"` |
| Gradle: "Unable to establish loopback connection" | Create `C:\jtmp` (see the Windows note above) |
| Gradle fails on JDK 24 or 25 | Use JDK 17 or 21 |
| Checks 9–11 are always `REVIEW` | No barcode was found in the photo, so there was no scale; photograph the barcode flat and in focus |

---

## Repository layout

```
Backend/
  app/
    core/            login tokens, role checks, upload / login / concurrency limits
    models/          database tables (users, evidence, rules, reports, notices, registry…)
    routers/         API: auth, scan, inspections, complaints, violations, rules, legal-notice
    schemas/         request and response shapes
    services/
      compliance_rules.py       the 13 checks
      compliance_aggregator.py  turns the checks into one verdict
      authenticity_service.py   registry cross-check
      fssai_mark_service.py     veg / non-veg mark detector
      cv_service.py             barcode-as-ruler measurement, contrast
      barcode_service.py        server-side barcode reading (pyzbar)
      violation_service.py      report → confirm → notice workflow
      report_service.py         the compliance report PDF and the GO notice PDF
    scripts/         seed_rules, seed_product_registry, create_user
    utils/           GSTIN validator, logging
  alembic/versions/  database migrations 0001–0008
  tests/             pytest suite and image fixtures

Frontend/src/
  pages/             Login, Queue, ReportDetail, SystemLog, MapView, Rules

mobile/
  lib/
    models/  providers/  services/  utils/  widgets/
    screens/consumer/   scan → review details → result, my scans
    screens/inspector/  complaints, map, scan log, scan detail, file report
  android/           Android project (manifest, Gradle, icons)
  test/              flutter tests and real OCR fixtures

docker-compose.yml   the whole stack in containers: database, API, dashboard
.github/workflows/   CI: server tests (with PostgreSQL), app tests and analyzer, dashboard build
```
