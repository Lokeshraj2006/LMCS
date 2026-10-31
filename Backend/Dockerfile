# ── Stage 1: Build ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# System deps for OpenCV headless, pyzbar, psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libzbar0 \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ────────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# Runtime-only system libs. CPU only: opencv-python-headless needs no GL
# or GPU libraries (libgl1-mesa-glx is also gone from current Debian).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzbar0 \
    libpq5 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local
COPY . .

# Create uploads directory
RUN mkdir -p /app/uploads

EXPOSE 8000

# One worker: the login lockout and scan slots are per process, and a single
# worker with a thread pool is enough for a 1-vCPU server.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
