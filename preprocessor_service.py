"""
preprocessor_service.py
========================
Lightweight Flask HTTP API that accepts a roster photo, performs:
  1. Skew / rotation correction (Hough-based)
  2. Smart table crop (grid-line detection)
  3. Contrast enhancement (CLAHE)
and returns the processed image as JPEG.

Routes:
  POST /preprocess   — multipart field "file" → image/jpeg response
  GET  /health       — returns {"status": "ok"}

Runs on 0.0.0.0:8765 inside the Docker container.
"""

import io
import math
import logging
import sys

import cv2
import numpy as np
from flask import Flask, request, Response, jsonify

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [preprocessor] %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

app = Flask(__name__)

# Maximum accepted upload size: 20 MB
app.config["MAX_CONTENT_LENGTH"] = 20 * 1024 * 1024


# ─────────────────────────────────────────────────────────────────────────────
# IMAGE PROCESSING PIPELINE
# ─────────────────────────────────────────────────────────────────────────────

def detect_skew_angle(image):
    """
    Returns the dominant near-horizontal angle (degrees) using Hough lines.
    Returns 0.0 if no reliable angle is detected.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150, apertureSize=3)

    h, w = image.shape[:2]
    min_line_length = w // 5  # line must span ≥20% of image width

    lines = cv2.HoughLinesP(
        edges,
        rho=1,
        theta=np.pi / 180,
        threshold=80,
        minLineLength=min_line_length,
        maxLineGap=30,
    )

    if lines is None:
        log.info("skew: no lines detected — assuming 0°")
        return 0.0

    angles = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        if x2 != x1:
            angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
            if abs(angle) <= 20:
                angles.append(angle)

    if not angles:
        log.info("skew: no near-horizontal lines — assuming 0°")
        return 0.0

    median = float(np.median(angles))
    log.info("skew: detected %.2f° from %d lines", median, len(angles))

    # Skip tiny corrections
    return median if abs(median) >= 0.5 else 0.0


def rotate_image(image, angle):
    """Rotate image, expanding canvas to avoid cropping, white background."""
    h, w = image.shape[:2]
    cx, cy = w / 2.0, h / 2.0

    M = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
    cos_a = abs(M[0, 0])
    sin_a = abs(M[0, 1])
    new_w = int(h * sin_a + w * cos_a)
    new_h = int(h * cos_a + w * sin_a)
    M[0, 2] += (new_w / 2.0) - cx
    M[1, 2] += (new_h / 2.0) - cy

    rotated = cv2.warpAffine(
        image, M, (new_w, new_h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(255, 255, 255),
    )
    log.info("skew: rotated %.2f° → new size %dx%d", angle, new_w, new_h)
    return rotated


def find_table_bounds(image):
    """
    Detects the main table grid and returns (x1, y1, x2, y2) bounding box.
    Falls back to full image dimensions if no reliable grid is found.
    """
    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    binary = cv2.adaptiveThreshold(
        gray, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        blockSize=15,
        C=5,
    )

    # Detect horizontal lines
    h_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (max(w // 8, 50), 1))
    h_lines = cv2.morphologyEx(binary, cv2.MORPH_OPEN, h_kernel)

    # Detect vertical lines
    v_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(h // 10, 30)))
    v_lines = cv2.morphologyEx(binary, cv2.MORPH_OPEN, v_kernel)

    grid = cv2.add(h_lines, v_lines)

    # Bridge small gaps
    dilate_k = cv2.getStructuringElement(cv2.MORPH_RECT, (40, 40))
    grid_filled = cv2.dilate(grid, dilate_k, iterations=2)

    contours, _ = cv2.findContours(grid_filled, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        log.info("crop: no grid contours — using full image")
        return 0, 0, w, h

    min_area = w * h * 0.05
    large = [c for c in contours if cv2.contourArea(c) > min_area]

    if not large:
        log.info("crop: no large contours — using full image")
        return 0, 0, w, h

    biggest = max(large, key=cv2.contourArea)
    x, y, bw, bh = cv2.boundingRect(biggest)

    pad = 20
    x1 = max(0, x - pad)
    y1 = max(0, y - pad)
    x2 = min(w, x + bw + pad)
    y2 = min(h, y + bh + pad)

    # Sanity: result must cover ≥25% in each dimension
    if (x2 - x1) < w * 0.25 or (y2 - y1) < h * 0.25:
        log.info("crop: crop too small (%dx%d) — using full image", x2 - x1, y2 - y1)
        return 0, 0, w, h

    log.info("crop: (%d,%d)→(%d,%d)", x1, y1, x2, y2)
    return x1, y1, x2, y2


def enhance_contrast(image):
    """Gentle CLAHE contrast boost on LAB L-channel (preserves cell colours)."""
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=1.5, tileGridSize=(8, 8))
    merged = cv2.merge([clahe.apply(l), a, b])
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def preprocess(img_bytes: bytes) -> bytes:
    """
    Run full pipeline: decode → deskew → crop → enhance → encode JPEG.
    Raises ValueError on bad input.
    """
    nparr = np.frombuffer(img_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image data")

    orig_h, orig_w = img.shape[:2]
    log.info("input: %dx%d px  size: %d bytes", orig_w, orig_h, len(img_bytes))

    # 1 — Skew correction
    angle = detect_skew_angle(img)
    if abs(angle) >= 0.5:
        img = rotate_image(img, angle)

    # 2 — Smart crop
    x1, y1, x2, y2 = find_table_bounds(img)
    img = img[y1:y2, x1:x2]
    log.info("output after crop: %dx%d px", img.shape[1], img.shape[0])

    # 3 — Contrast enhancement
    img = enhance_contrast(img)

    # Encode to JPEG
    ok, buffer = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 95])
    if not ok:
        raise RuntimeError("Failed to encode output image")

    return buffer.tobytes()


# ─────────────────────────────────────────────────────────────────────────────
# FLASK ROUTES
# ─────────────────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/preprocess", methods=["POST"])
def preprocess_route():
    """
    Accepts: multipart/form-data with a field named 'file'
    Returns: image/jpeg
    """
    if "file" not in request.files:
        return jsonify({"error": "Missing 'file' field in multipart body"}), 400

    file_bytes = request.files["file"].read()
    if not file_bytes:
        return jsonify({"error": "Uploaded file is empty"}), 400

    try:
        result = preprocess(file_bytes)
        log.info("preprocess complete — returning %d bytes", len(result))
        return Response(result, mimetype="image/jpeg", status=200)
    except ValueError as e:
        log.warning("preprocess error (bad input): %s", e)
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        log.error("preprocess error (internal): %s", e, exc_info=True)
        return jsonify({"error": "Internal processing error"}), 500


# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    log.info("Starting image preprocessor service on 0.0.0.0:8765")
    app.run(host="0.0.0.0", port=8765, threaded=True)
