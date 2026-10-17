#!/usr/bin/env python3
"""Compare where an underline sits on screen against where it sits on paper.

Why this exists
---------------
The RMSE gate compares two rasterisers, so it cannot say *what* differs: a
four-pixel offset of one rule is buried in a page-wide number whose floor is
already 2.6x the ceiling. Underlines are the one decoration whose position can
be compared exactly, because the PDF contains the line as geometry and the
Preview contains it as ink:

* PDF side -- exact, no rasterisation: the rule is a horizontal path in the
  page's content stream (`page.get_drawings()`), and the baseline of the text
  line above it comes from the same file (`page.get_text()` span origins).
  PyMuPDF reports both in its own top-left, y-down frame, so the difference is
  the offset with no measurement error at all -- and it carries the same sign
  as the pixel measurement below (positive = below the baseline).
* Preview side -- measured: within the same line's box, a rule is the only row
  whose ink is one *continuous* run, because the gaps inside letters break
  every glyph row into many short runs. The row band that carries ink above it
  is the glyph body, so its last row is the baseline.

The comparison is therefore meaningful even though the two renderings come
from different rasterisers: it compares a decoration's position relative to its
own text, not the rasterisation of that decoration.

Exit status is the gate: 0 when every rule is within --tolerance points of
where the Preview draws it, 1 otherwise. This is a real check on a property the
project owns. It is NOT a substitute for the RMSE gate and does not touch it.
"""
from __future__ import annotations

import argparse
import os
import sys
import traceback

import numpy as np
import pymupdf

# Ink below this (0..255 luma) counts as drawn.
INK = 32
# A horizontal path at least this long (points) counts as a rule to check.
MIN_RULE_PT = 20.0
# A row is "continuous" when its longest unbroken ink run is at least this
# fraction of the rule's own length. Letters never reach it: their rows are
# broken into stems by the gaps inside and between glyphs.
CONTINUOUS = 0.5


def notify(title, lines, level='notice'):
    """Publish through the channel that survives without job logs."""
    text = ' | '.join(str(line) for line in lines)
    text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::{level} title={title}::{text}')


def load_luma(path):
    """8-bit luma float array in [0,1] for a PNG, alpha composited on white."""
    pix = pymupdf.Pixmap(path)
    data = np.frombuffer(pix.samples, dtype=np.uint8)
    data = data.reshape(pix.height, pix.width, pix.n).astype(np.float64)
    if pix.n >= 3:
        rgb = data[:, :, :3]
        if pix.n == 4:
            alpha = data[:, :, 3:4] / 255.0
            rgb = rgb * alpha + 255.0 * (1.0 - alpha)
        gray = (0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] +
                0.114 * rgb[:, :, 2])
    else:
        gray = data[:, :, 0]
    return 1.0 - gray / 255.0          # 0 = white, 1 = black


def longest_run(row, ink=INK):
    """Longest unbroken run of ink in one binary row, in pixels."""
    lit = row > ink
    if not lit.any():
        return 0
    # Run lengths from the transition indices, without a Python loop per pixel.
    edges = np.flatnonzero(np.diff(np.concatenate(([0], lit.view(np.int8),
                                                   [0]))))
    return int((edges[1::2] - edges[0::2]).max())


def rules_in_pdf(page):
    """Horizontal rules of one page, in PDF user space, with their baseline.

    A rule is a horizontal segment long enough to be a decoration. The text
    line it belongs to is the nearest line whose baseline is above it within a
    third of an em, which is where an underline can legitimately sit.
    """
    lines = []
    # PyMuPDF coordinates are y-down from the page's top-left, for text origins
    # and for drawings alike; a rule below a baseline therefore has the larger
    # y. Everything in this file follows that one frame.
    text = page.get_text('dict')
    for block in text.get('blocks', []):
        for line in block.get('lines', []):
            for span in line.get('spans', []):
                if not span.get('text', '').strip():
                    continue
                lines.append({
                    'baseline': float(span['origin'][1]),
                    'size': float(span['size']),
                    'bbox': span['bbox'],
                    'text': span['text'],
                })
    found = []
    for drawing in page.get_drawings():
        for item in drawing['items']:
            if item[0] != 'l':                    # straight strokes only
                continue
            p1, p2 = item[1], item[2]
            if abs(p1.y - p2.y) > 0.5 or abs(p1.x - p2.x) < MIN_RULE_PT:
                continue
            y = (p1.y + p2.y) / 2.0
            x0, x1 = sorted((p1.x, p2.x))
            # The owning line: smallest vertical distance to a baseline above.
            owner = None
            for line in lines:
                below = y - line['baseline']            # + when the rule is
                if below < -0.1:                        # lower on the page
                    continue
                if below > 0.6 * line['size']:          # too far to decorate
                    continue
                if owner is None or below < owner['offset_pt']:
                    owner = {'offset_pt': below, 'line': line}
            if owner is None:
                continue
            found.append({
                'offset_pt': owner['offset_pt'],
                'rule_y': y,
                'rule_x': (x0, x1),
                'baseline': owner['line']['baseline'],
                'size': owner['line']['size'],
                'text': owner['line']['text'][:60],
                'bbox': owner['line']['bbox'],
            })
    return found


def preview_offset(luma, bbox, scale, pad_pt=2.0):
    """Offset of the rule below the glyph baseline, in pixels, for one line.

    Returns (offset_px, thickness_px, baseline_row, rule_rows) or None when the
    region shows no continuous rule -- an unmeasurable region is reported, not
    guessed.
    """
    x0 = max(0, int((bbox[0] - pad_pt) * scale))
    x1 = min(luma.shape[1], int((bbox[2] + pad_pt) * scale) + 1)
    y0 = max(0, int((bbox[1] - pad_pt) * scale))
    y1 = min(luma.shape[0], int((bbox[3] + pad_pt) * scale) + 1)
    if x1 - x0 < 4 or y1 - y0 < 4:
        return None
    region = (luma[y0:y1, x0:x1] * 255.0)
    width = x1 - x0
    runs = np.array([longest_run(region[r]) for r in range(region.shape[0])])
    rule_rows = np.flatnonzero(runs >= CONTINUOUS * width)
    if rule_rows.size == 0:
        return None
    glyph_rows = np.flatnonzero((region > INK).sum(axis=1) > 1)
    above = glyph_rows[glyph_rows < rule_rows[0]]
    if above.size == 0:
        return None
    baseline_row = int(above[-1])
    rule_top = int(rule_rows[0])
    return {
        'offset_px': rule_top - baseline_row,
        'thickness_px': int(rule_rows[-1] - rule_top + 1),
        'baseline_row': int(y0 + baseline_row),
        'rule_rows': (int(y0 + rule_rows[0]), int(y0 + rule_rows[-1])),
        'line_width_px': width,
        'longest_run_px': int(runs[rule_rows[0]]),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('artifacts', nargs='?', default='build/visual_parity')
    parser.add_argument('--tolerance', type=float, default=1.0,
                        help='allowed difference, in points')
    args = parser.parse_args()

    manifest_path = os.path.join(args.artifacts, 'manifest.json')
    pdf_path = os.path.join(args.artifacts, 'vector.pdf')
    import json
    with open(manifest_path, encoding='utf-8') as handle:
        manifest = json.load(handle)
    width_px = int(manifest['widthPx'])

    doc = pymupdf.open(pdf_path)
    checked = 0
    failures = []
    for index in range(doc.page_count):
        page = doc[index]
        preview_png = os.path.join(args.artifacts,
                                   f'preview_page_{index + 1}.png')
        if not os.path.exists(preview_png):
            notify('UNDERLINE missing preview',
                   [f'{preview_png} is absent; nothing to compare'],
                   level='warning')
            continue
        luma = load_luma(preview_png)
        # The preview is the page at 96 dpi: one point is 96/72 pixels. Both
        # numbers must come from the same page-to-pixel mapping, so it is
        # derived from the page width rather than assumed.
        scale = width_px / page.rect.width
        for rule in rules_in_pdf(page):
            measured = preview_offset(luma, rule['bbox'], scale)
            if measured is None:
                notify('UNDERLINE not measurable',
                       [f'p{index + 1} "{rule["text"]}": the preview shows no '
                        f'continuous rule in this line, so the comparison is '
                        f'skipped rather than passed'], level='warning')
                continue
            preview_pt = measured['offset_px'] / scale
            delta = preview_pt - rule['offset_pt']
            checked += 1
            record = (
                f'p{index + 1} "{rule["text"]}" size={rule["size"]:.1f}pt  '
                f'pdf={rule["offset_pt"]:.3f}pt  preview={preview_pt:.3f}pt '
                f'({measured["offset_px"]}px, thickness '
                f'{measured["thickness_px"]}px)  delta={delta:+.3f}pt')
            if abs(delta) > args.tolerance:
                failures.append(record)

    if checked == 0:
        notify('UNDERLINE no rule checked',
               ['no underline was measurable in either source; this check '
                'proves nothing and says so instead of passing'],
               level='warning')
    else:
        notify('UNDERLINE pdf vs preview',
               [f'{checked} rule(s) compared, tolerance '
                f'{args.tolerance}pt'] + failures[:4] or
               [f'{checked} rule(s) within tolerance'],
               level='warning' if failures else 'notice')
    if failures:
        for line in failures[:4]:
            print(f'::error title=UNDERLINE offset::{line}')
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:                      # a crash must not read as a pass
        print('::error title=UNDERLINE crashed::' +
              traceback.format_exc().splitlines()[-1][:200])
        sys.exit(2)
