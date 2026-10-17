#!/usr/bin/env python3
"""Per-line registration and ink-mass analysis for the C6 residual.

Diagnostic only. For every PDF text line it finds the translation that minimises
the RMSE against the preview, then reports the residual. If per-line translation
removes most of the error the residual is positional; if it barely moves, the
error is glyph shape, weight or coverage.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def load_gray(path: Path) -> np.ndarray:
    image = Image.open(path)
    if image.mode in ("RGBA", "LA", "PA"):
        background = Image.new("RGBA", image.size, (255, 255, 255, 255))
        image = Image.alpha_composite(background, image.convert("RGBA"))
    return np.asarray(image.convert("L"), dtype=np.float64)


def gate_pair(directory: Path, page: int):
    preview = load_gray(directory / f"preview_page_{page}.png")
    rendered = load_gray(directory / "rendered_vector_pdf" / f"page-{page}.png")
    height, width = preview.shape
    if rendered.shape != preview.shape:
        rendered = np.asarray(
            Image.fromarray(rendered.astype(np.uint8)).resize(
                (width, height), Image.LANCZOS
            ),
            dtype=np.float64,
        )
    return (
        rendered[2 : height - 2, 2 : width - 2],
        preview[2 : height - 2, 2 : width - 2],
    )


def rmse(a: np.ndarray, b: np.ndarray) -> float:
    return float(math.sqrt(np.mean((a - b) ** 2)) / 255.0)


def shift_image(image: np.ndarray, dx: float, dy: float) -> np.ndarray:
    """Sub-pixel translation by bilinear interpolation (edge clamped)."""
    height, width = image.shape
    ys, xs = np.mgrid[0:height, 0:width]
    source_x = np.clip(xs - dx, 0, width - 1)
    source_y = np.clip(ys - dy, 0, height - 1)
    x0 = np.floor(source_x).astype(np.int32)
    y0 = np.floor(source_y).astype(np.int32)
    x1 = np.minimum(x0 + 1, width - 1)
    y1 = np.minimum(y0 + 1, height - 1)
    fx = source_x - x0
    fy = source_y - y0
    return (
        image[y0, x0] * (1 - fx) * (1 - fy)
        + image[y0, x1] * fx * (1 - fy)
        + image[y1, x0] * (1 - fx) * fy
        + image[y1, x1] * fx * fy
    )


def best_shift(pdf: np.ndarray, preview: np.ndarray, span: float = 2.5, step: float = 0.25):
    best = (0.0, 0.0, rmse(pdf, preview))
    offsets = np.arange(-span, span + 1e-9, step)
    for dy in offsets:
        moved = shift_image(pdf, 0.0, dy)
        for dx in offsets:
            candidate = shift_image(moved, dx, 0.0)
            value = rmse(candidate, preview)
            if value < best[2]:
                best = (float(dx), float(dy), value)
    # One refinement pass at a finer step around the winner.
    dx0, dy0, value = best
    for dy in np.arange(dy0 - step, dy0 + step + 1e-9, step / 5):
        moved = shift_image(pdf, 0.0, dy)
        for dx in np.arange(dx0 - step, dx0 + step + 1e-9, step / 5):
            candidate = shift_image(moved, dx, 0.0)
            refined = rmse(candidate, preview)
            if refined < value:
                value = refined
                best = (float(dx), float(dy), refined)
    return best


def line_bands(glyph_json: Path, page: int) -> list[tuple[float, float]]:
    payload = json.loads(glyph_json.read_text(encoding="utf-8"))
    spans = payload["pages"][page - 1]["spans"]
    centres: dict[float, list[float]] = {}
    for span in spans:
        if not span["chars"]:
            continue
        top = min(char[2] for char in span["chars"])
        bottom = top  # vertical origin is the baseline; band from size
        baseline = span["chars"][0][2]
        key = round(baseline, 1)
        centres.setdefault(key, []).append(span["size"])
    scale = 794.0 / 595.2755737304688
    bands = []
    for baseline, sizes in sorted(centres.items()):
        size = max(sizes)
        top = (baseline - size * 1.15) * scale
        bottom = (baseline + size * 0.45) * scale
        bands.append((top, bottom))
    return bands


def analyse_page(directory: Path, page: int) -> None:
    pdf, preview = gate_pair(directory, page)
    height = pdf.shape[0]
    print(f"--- page {page} ---")
    print(f"  gate RMSE                     : {rmse(pdf, preview):.7f}")
    dx, dy, value = best_shift(pdf, preview, span=2.0, step=0.5)
    print(
        f"  whole-page best shift         : dx={dx:+.2f}px dy={dy:+.2f}px"
        f" -> RMSE {value:.7f}  (gain {rmse(pdf, preview) - value:+.7f})"
    )

    bands = line_bands(directory / "c6_pdf_glyphs.json", page)
    print(f"  text line bands               : {len(bands)}")
    shifts = []
    before_sum = 0.0
    after_sum = 0.0
    pixels = 0
    for index, (top, bottom) in enumerate(bands):
        y0 = max(0, int(top) - 1)
        y1 = min(height, int(bottom) + 1)
        if y1 - y0 < 4:
            continue
        strip_pdf = pdf[y0:y1, :]
        strip_pre = preview[y0:y1, :]
        if (255.0 - strip_pre).sum() < 500 or (255.0 - strip_pdf).sum() < 500:
            continue
        base = rmse(strip_pdf, strip_pre)
        index_dx, index_dy, refined = best_shift(strip_pdf, strip_pre, span=2.0, step=0.5)
        shifts.append((index, base, refined, index_dx, index_dy))
        before_sum += base**2 * strip_pdf.size
        after_sum += refined**2 * strip_pdf.size
        pixels += strip_pdf.size
    if pixels:
        print(
            f"  sum of per-line RMSE^2 before : {math.sqrt(before_sum / pixels):.7f}"
        )
        print(
            f"  sum of per-line RMSE^2 after per-line shift : "
            f"{math.sqrt(after_sum / pixels):.7f}"
        )
    drifts = np.array([entry[3] for entry in shifts]) if shifts else np.zeros(1)
    vertical = np.array([entry[4] for entry in shifts]) if shifts else np.zeros(1)
    print(
        f"  per-line dx: median {np.median(drifts):+.2f}  mean {drifts.mean():+.2f}"
        f"  p10 {np.percentile(drifts, 10):+.2f}  p90 {np.percentile(drifts, 90):+.2f}"
        f"  |dx|>0.5px: {int((np.abs(drifts) > 0.5).sum())}/{len(drifts)}"
    )
    print(
        f"  per-line dy: median {np.median(vertical):+.2f}  mean {vertical.mean():+.2f}"
        f"  p10 {np.percentile(vertical, 10):+.2f}  p90 {np.percentile(vertical, 90):+.2f}"
        f"  |dy|>0.5px: {int((np.abs(vertical) > 0.5).sum())}/{len(vertical)}"
    )
    worst = sorted(shifts, key=lambda entry: -entry[1])[:8]
    print("  worst lines (index, RMSE before, after, dx, dy):")
    for entry in worst:
        print(
            f"    line {entry[0]:3d}  {entry[1]:.5f} -> {entry[2]:.5f}"
            f"   dx={entry[3]:+.2f} dy={entry[4]:+.2f}"
        )
    print(
        f"  ink mass PDF/Preview total    : "
        f"{(255.0 - pdf).sum() / max((255.0 - preview).sum(), 1e-9):.6f}"
    )


def main(argv: list[str]) -> int:
    directory = Path(argv[1] if len(argv) > 1 else "c6_forensics")
    for page in (1, 2):
        analyse_page(directory, page)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
