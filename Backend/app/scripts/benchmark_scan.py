"""
Time the server's per-photo image work on CPU.

    python -m app.scripts.benchmark_scan [photo_dir]

Runs what POST /scan does to each photo, without the database: decode,
the pyzbar barcode fallback, and the FSSAI mark detector. (Text is read on
the phone by ML Kit, so the server never runs OCR.) Prints the median and
95th-percentile times and the scans per CPU-minute that implies, which is
the figure to size a server by. Defaults to the stored evidence photos.
"""

from __future__ import annotations

import os
import statistics
import sys
import time
from pathlib import Path

import cv2
import numpy as np

from app.services.barcode_service import detect_barcode
from app.services.fssai_mark_service import detect_fssai_mark_from_bytes


def _photos(folder: Path) -> list[Path]:
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"})


def main() -> None:
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd() / "uploads" / "evidence"
    photos = _photos(folder)
    if not photos:
        sys.exit(f"No photos in {folder}")

    cv2.setNumThreads(1)  # one core, as on the smallest server
    timings, megapixels = [], []
    for path in photos:
        data = path.read_bytes()
        start = time.process_time()
        image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
        if image is not None:
            detect_barcode(image)
        detect_fssai_mark_from_bytes(data)
        timings.append(time.process_time() - start)
        if image is not None:
            megapixels.append(image.shape[0] * image.shape[1] / 1e6)

    timings.sort()
    median = statistics.median(timings)
    p95 = timings[min(len(timings) - 1, int(round(0.95 * (len(timings) - 1))))]
    print(f"photos            {len(photos)} ({statistics.median(megapixels):.1f} MP median)")
    print(f"CPU time / photo  median {median * 1000:.0f} ms, p95 {p95 * 1000:.0f} ms, max {timings[-1] * 1000:.0f} ms")
    print(f"throughput        ~{60 / median:.0f} photos per CPU-minute on one core")
    print(f"cores here        {os.cpu_count()} (OpenCV limited to 1 thread for this run)")


if __name__ == "__main__":
    main()
