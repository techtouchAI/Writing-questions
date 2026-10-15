#!/usr/bin/env python3
"""Forensic decomposition of the C6 Vector-PDF vs Preview residual.

This is a MEASUREMENT instrument, not a gate and not a fix. It reads the
artifacts the official job already produces (``build/visual_parity``), rebuilds
the gate's exact comparison (crop 2 px, RMSE against the preview) and then asks
which physical difference explains the residual:

* a *geometric* difference (ink moved: err correlates with the preview gradient),
* a *photometric* difference (ink amount/coverage differs: err correlates with
  the preview ink), or
* neither (glyph shape really differs).

Outputs are plain text so they survive the CI annotation channel.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
import fitz  # PyMuPDF: PDF structure/text extraction (diagnostic only)

Image.MAX_IMAGE_PIXELS = None


def load_gray(path: Path) -> np.ndarray:
    """Grayscale float array in 0..255 (alpha composited over white)."""
    image = Image.open(path)
    if image.mode in ("RGBA", "LA", "PA"):
        background = Image.new("RGBA", image.size, (255, 255, 255, 255))
        image = Image.alpha_composite(background, image.convert("RGBA"))
    return np.asarray(image.convert("L"), dtype=np.float64)


def rmse(a: np.ndarray, b: np.ndarray) -> float:
    return float(math.sqrt(np.mean((a - b) ** 2)) / 255.0)


def crop_and_normalise(rendered: np.ndarray, preview: np.ndarray):
    """Mirror tool/verify_visual_parity.sh: resize to the manifest size, crop 2 px."""
    height, width = preview.shape[:2]
    if rendered.shape != preview.shape:
        rendered = np.asarray(
            Image.fromarray(rendered.astype(np.uint8)).resize(
                (width, height), Image.LANCZOS
            ),
            dtype=np.float64,
        )
    rendered = rendered[2 : height - 2, 2 : width - 2]
    preview = preview[2 : height - 2, 2 : width - 2]
    return rendered, preview


def bucket_report(pdf: np.ndarray, preview: np.ndarray) -> None:
    ink_pdf = 1.0 - pdf / 255.0
    ink_pre = 1.0 - preview / 255.0
    both = (ink_pdf > 0.5) & (ink_pre > 0.5)
    only_pdf = (ink_pdf > 0.5) & (ink_pre <= 0.5)
    only_pre = (ink_pre > 0.5) & (ink_pdf <= 0.5)
    partial = (~both) & (~only_pdf) & (~only_pre) & ((ink_pdf > 0.02) | (ink_pre > 0.02))
    total = pdf.size
    print("  pixel classes (>50% = ink):")
    print(
        f"    ink both      : {both.sum():7d} ({100.0 * both.sum() / total:.3f}%)"
        f"  mean |d| = {np.abs(pdf[both] - preview[both]).mean() if both.any() else 0:6.2f}"
    )
    print(
        f"    ink PDF only  : {only_pdf.sum():7d} ({100.0 * only_pdf.sum() / total:.3f}%)"
        f"  mean |d| = {np.abs(pdf[only_pdf] - preview[only_pdf]).mean() if only_pdf.any() else 0:6.2f}"
    )
    print(
        f"    ink Prev only : {only_pre.sum():7d} ({100.0 * only_pre.sum() / total:.3f}%)"
        f"  mean |d| = {np.abs(pdf[only_pre] - preview[only_pre]).mean() if only_pre.any() else 0:6.2f}"
    )
    print(f"    partial/other : {partial.sum():7d} ({100.0 * partial.sum() / total:.3f}%)")
    print(f"    total ink PDF : {ink_pdf.sum():12.1f}")
    print(f"    total ink Prev: {ink_pre.sum():12.1f}")
    print(f"    ink mass ratio PDF/Prev : {ink_pdf.sum() / max(ink_pre.sum(), 1e-9):.6f}")
    cls = np.zeros_like(pdf)
    cls[both] = 1
    cls[only_pdf] = 2
    cls[only_pre] = 3
    cls[partial] = 4
    print("  SSE share by class:")
    for label, index in (("both", 1), ("PDF only", 2), ("Prev only", 3), ("partial", 4)):
        mask = cls == index
        sse = float(((pdf[mask] - preview[mask]) ** 2).sum())
        print(f"    {label:10s} {sse:14.1f}")


def monotone_oracle(pdf: np.ndarray, preview: np.ndarray) -> None:
    """Best achievable RMSE with a single global monotone gray-level map.

    This is an ORACLE, not a fix: it shows how much of the residual is a pure
    coverage-ramp (anti-aliasing) difference with identical geometry.
    """
    bins = np.arange(257)
    pdf_bin = np.clip(np.round(pdf), 0, 255).astype(np.int32)
    table = np.full(256, 255.0)
    for value in range(256):
        selected = preview[pdf_bin == value]
        table[value] = selected.mean() if selected.size else value
    mapped = table[pdf_bin]
    print(f"  oracle global monotone map RMSE : {rmse(mapped, preview):.7f}")
    samples = [0, 32, 64, 96, 128, 160, 192, 224, 255]
    print("  transfer curve pdf->preview (mean preview gray per pdf gray):")
    print("    " + "  ".join(f"{v}->{table[v]:.1f}" for v in samples if (pdf_bin == v).any()))


def linear_model(pdf: np.ndarray, preview: np.ndarray) -> None:
    """Fit err ~ a*Ix + b*Iy + c*ink_preview + d over the content region."""
    err = pdf - preview
    ink_pre = 1.0 - preview / 255.0
    ink_pdf = 1.0 - pdf / 255.0
    gy, gx = np.gradient(preview)
    mask = (ink_pre > 0.02) | (ink_pdf > 0.02)
    count = int(mask.sum())
    if count < 1000:
        print("  linear model: not enough content pixels")
        return
    design = np.stack(
        [gx[mask], gy[mask], ink_pre[mask], np.ones(count)], axis=1
    )
    target = -err[mask]  # ink that the PDF has and the preview does not
    coefficients, *_ = np.linalg.lstsq(design, target, rcond=None)
    a_shift, b_shift, c_gain, d_const = coefficients
    predicted = -(design @ coefficients)
    baseline = float(np.sqrt(np.mean(err[mask] ** 2)) / 255.0)
    residual = float(np.sqrt(np.mean((err[mask] - predicted) ** 2)) / 255.0)
    print(f"  content pixels                 : {count}")
    print(f"  content-region RMSE (raw)      : {baseline:.7f}")
    print(
        f"  implied ink shift (px)         : dx = {a_shift / 255.0:+.4f}"
        f"  dy = {b_shift / 255.0:+.4f}"
    )
    print(f"  implied coverage gain c        : {c_gain / 255.0:+.5f} per unit ink")
    print(f"  residual RMSE after the 3-term model : {residual:.7f}")

    # Same fit with the geometric terms removed, to size the photometric part.
    design_p = np.stack([ink_pre[mask], np.ones(count)], axis=1)
    coefficients_p, *_ = np.linalg.lstsq(design_p, target, rcond=None)
    predicted_p = -(design_p @ coefficients_p)
    residual_p = float(np.sqrt(np.mean((err[mask] - predicted_p) ** 2)) / 255.0)
    print(f"  photometric-only (ink gain) residual : {residual_p:.7f}")

    design_g = np.stack([gx[mask], gy[mask], np.ones(count)], axis=1)
    coefficients_g, *_ = np.linalg.lstsq(design_g, target, rcond=None)
    predicted_g = -(design_g @ coefficients_g)
    residual_g = float(np.sqrt(np.mean((err[mask] - predicted_g) ** 2)) / 255.0)
    print(f"  geometric-only (shift) residual      : {residual_g:.7f}")


def grid_report(pdf: np.ndarray, preview: np.ndarray, rows: int = 8, cols: int = 6) -> None:
    height, width = pdf.shape
    print(f"  RMSE by {rows}x{cols} cell (x1000):")
    for r in range(rows):
        y0, y1 = height * r // rows, height * (r + 1) // rows
        cells = []
        for c in range(cols):
            x0, x1 = width * c // cols, width * (c + 1) // cols
            value = rmse(pdf[y0:y1, x0:x1], preview[y0:y1, x0:x1]) * 1000
            cells.append(f"{value:6.1f}")
        print("    " + " ".join(cells))


def row_profile(pdf: np.ndarray, preview: np.ndarray, top: int = 12) -> None:
    """Worst rows/columns, to locate the residual."""
    del top
    err = (pdf - preview) ** 2
    per_row = err.mean(axis=1)
    per_col = err.mean(axis=0)
    order = np.argsort(per_row)[::-1][:10]
    print("  worst rows (y, row RMSE x1000):")
    print("    " + "  ".join(f"{i}:{math.sqrt(per_row[i]) / 255 * 1000:.1f}" for i in sorted(order)))
    order_c = np.argsort(per_col)[::-1][:10]
    print("  worst cols (x, col RMSE x1000):")
    print(
        "    "
        + "  ".join(f"{i}:{math.sqrt(per_col[i]) / 255 * 1000:.1f}" for i in sorted(order_c))
    )


def pdf_text_report(pdf_path: Path) -> None:
    if not pdf_path.exists():
        return
    document = fitz.open(pdf_path)
    print("  vector.pdf font instances:")
    for page_index in range(document.page_count):
        page = document[page_index]
        fonts = page.get_fonts(full=True)
        print(
            f"    page {page_index + 1}: "
            + ", ".join(sorted({f"{entry[3]}<{entry[2]}>" for entry in fonts}))
        )
        announced = page.get_text("dict")
        span_count = 0
        sizes: dict[float, int] = {}
        for block in announced["blocks"]:
            for line in block.get("lines", []):
                for span in line["spans"]:
                    span_count += 1
                    sizes[round(span["size"], 3)] = sizes.get(round(span["size"], 3), 0) + 1
        print(f"      spans={span_count} sizes={dict(sorted(sizes.items())[:8])}")
    document.close()


def analyse(directory: Path) -> int:
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    pages = int(manifest["pageCount"])
    print("=" * 78)
    print("C6 FORENSICS - gate reproduction and residual decomposition")
    print(f"manifest: pages={pages} {manifest['widthPx']}x{manifest['heightPx']}")
    print("=" * 78)

    for index in range(1, pages + 1):
        preview_path = directory / f"preview_page_{index}.png"
        rendered_path = directory / "rendered" / "vector_pdf" / f"page-{index}.png"
        if not preview_path.exists() or not rendered_path.exists():
            print(f"page {index}: missing {preview_path.name} or {rendered_path.name}")
            continue
        preview_raw = load_gray(preview_path)
        rendered_raw = load_gray(rendered_path)
        print()
        print(f"--- page {index} ---")
        print(
            f"  raw sizes preview={preview_raw.shape[1]}x{preview_raw.shape[0]}"
            f" poppler={rendered_raw.shape[1]}x{rendered_raw.shape[0]}"
        )
        pdf, preview = crop_and_normalise(rendered_raw, preview_raw)
        print(f"  gate RMSE (reproduced)         : {rmse(pdf, preview):.7f}")
        bucket_report(pdf, preview)
        monotone_oracle(pdf, preview)
        linear_model(pdf, preview)
        grid_report(pdf, preview)
        row_profile(pdf, preview)

    print()
    print("--- vector.pdf structure ---")
    pdf_text_report(directory / "vector.pdf")
    print()
    print("=" * 78)
    print("END C6 FORENSICS")
    return 0


def main(argv: list[str]) -> int:
    directory = Path(argv[1] if len(argv) > 1 else "build/visual_parity")
    if not (directory / "manifest.json").exists():
        print(f"manifest.json missing in {directory}")
        return 2
    return analyse(directory)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
