#!/usr/bin/env python3
"""Attribute the C6 page error to the PDF object classes that produce it.

Diagnostic only. Every pixel of the gate's comparison is assigned to the object
class that owns it on the PDF side -- text glyph, vector drawing (frame, rules,
underlines) or raster image (math snapshots, floating images) -- using the PDF's
own geometry. Then the squared error of each class is summed, so the residual is
attributed to a producer instead of to a grid cell.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
import pymupdf

Image.MAX_IMAGE_PIXELS = None

POINTS_PER_PIXEL = 595.2755737304688 / 794.0


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


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    out = mask.copy()
    for _ in range(radius):
        shifted = out.copy()
        shifted[1:, :] |= out[:-1, :]
        shifted[:-1, :] |= out[1:, :]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out = shifted
    return out


def to_pixels(rect, width: int, height: int):
    x0 = int(math.floor(rect[0] / POINTS_PER_PIXEL)) + 2
    y0 = int(math.floor(rect[1] / POINTS_PER_PIXEL)) + 2
    x1 = int(math.ceil(rect[2] / POINTS_PER_PIXEL)) + 2
    y1 = int(math.ceil(rect[3] / POINTS_PER_PIXEL)) + 2
    return (
        max(0, x0),
        max(0, y0),
        min(width, max(x1, x0 + 1)),
        min(height, max(y1, y0 + 1)),
    )


def build_masks(pdf_path: Path, page_index: int, height: int, width: int):
    document = pymupdf.open(pdf_path)
    page = document[page_index]

    text_mask = np.zeros((height, width), dtype=bool)
    for block in page.get_text("rawdict")["blocks"]:
        for line in block.get("lines", []):
            for span in line["spans"]:
                for char in span["chars"]:
                    x0, y0, x1, y1 = to_pixels(char["bbox"], width, height)
                    text_mask[y0:y1, x0:x1] = True

    image_mask = np.zeros((height, width), dtype=bool)
    image_boxes = []
    for info in page.get_image_info():
        rect = info["bbox"]
        image_boxes.append(rect)
        x0, y0, x1, y1 = to_pixels(rect, width, height)
        image_mask[y0:y1, x0:x1] = True

    drawing_mask = np.zeros((height, width), dtype=bool)
    drawing_count = 0
    for drawing in page.get_drawings():
        drawing_count += 1
        rect = drawing["rect"]
        for item in drawing["items"]:
            if item[0] == "l":
                points = [item[1], item[2]]
            elif item[0] == "re":
                points = [item[1].tl, item[1].br]
            elif item[0] == "qu":
                points = list(item[1])
            else:
                points = [rect.tl, rect.br]
            for point in points:
                x0, y0, x1, y1 = to_pixels(
                    (point.x - 1.5, point.y - 1.5, point.x + 1.5, point.y + 1.5),
                    width,
                    height,
                )
                drawing_mask[y0:y1, x0:x1] = True
    stroked = [
        drawing
        for drawing in page.get_drawings()
        if drawing.get("width") and (drawing.get("color") or drawing.get("fill"))
    ]
    document.close()
    return text_mask, drawing_mask, image_mask, image_boxes, drawing_count, len(stroked)


def report(directory: Path, page: int) -> None:
    pdf, preview = gate_pair(directory, page)
    height, width = pdf.shape
    text_mask, drawing_mask, image_mask, image_boxes, drawing_count, stroked = build_masks(
        directory / "vector.pdf", page - 1, height, width
    )
    text_zone = dilate(text_mask, 2)
    drawing_zone = dilate(drawing_mask, 2)
    image_zone = dilate(image_mask, 2)

    squared = (pdf - preview) ** 2
    total = float(squared.sum())

    # Exclusive classes, most specific first.
    owned = np.zeros((height, width), dtype=np.uint8)
    owned[drawing_zone] = 1
    owned[image_zone] = 2
    owned[text_zone] = 3

    print(f"--- page {page} ---")
    print(f"  drawings (paths)={drawing_count}  stroked={stroked}")
    print(f"  images={len(image_boxes)}")
    for index, rect in enumerate(image_boxes, 1):
        x0, y0, x1, y1 = rect
        area = (x1 - x0) * (y1 - y0) / POINTS_PER_PIXEL**2
        print(
            f"    image {index}: pt=({x0:.1f},{y0:.1f},{x1:.1f},{y1:.1f})"
            f"  px area={area:.0f}"
        )
    print(f"  total SSE {total:.1f}")
    for label, index in (("drawing", 1), ("image", 2), ("text", 3), ("other", 0)):
        mask = owned == index
        share = float(squared[mask].sum())
        pixels = int(mask.sum())
        percent = 100.0 * share / total if total else 0.0
        print(
            f"    {label:8s} pixels={pixels:8d}  SSE={share:14.1f}  {percent:6.2f}% of page"
        )
    # Text ink, restricted to where either side actually has ink.
    ink = ((pdf < 250) | (preview < 250)) & (owned == 3)
    if ink.any():
        share = float(squared[ink].sum())
        print(
            f"    text(ink only) pixels={int(ink.sum()):8d} SSE={share:14.1f}"
            f"  {100.0 * share / total:6.2f}% of page"
        )


def main(argv: list[str]) -> int:
    directory = Path(argv[1] if len(argv) > 1 else "c6_forensics")
    for page in (1, 2):
        report(directory, page)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
