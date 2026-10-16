#!/usr/bin/env python3
"""[C6-ATTR] Element-level attribution of the Vector-track RMSE (non-gating).

Question this answers: the gate reports ONE number per page (RMSE 0.068/0.079
against a 0.02 ceiling). That number says nothing about WHICH drawn elements
carry the error, or whether each one is a rasteriser artefact or a real content
or geometry defect. This tool attributes the error to elements and classifies
each one.

Method, deliberately mirroring tool/verify_visual_parity.sh so the numbers are
comparable with the gate:

  1. rasterise vector.pdf with `pdftoppm -r 96 -png`               (as the gate)
  2. normalise both sides with ImageMagick: resize the rendered page to the
     manifest size and crop the 2 px board frame off BOTH sides (as the gate)
  3. reproduce the gate's own RMSE with `compare -metric RMSE`     (validation)
  4. then, per page, in numpy over those same normalised files:
       * SSE inside the text rectangles read from the PDF's own words versus
         the non-text remainder, so "it is all text" is measured, not assumed;
       * per PDF line: SSE share, RMSE, RMSE after a 0.5 px gaussian on both
         sides, and the best integer shift in [-2..2]^2. Those three separate
         the possible causes:
             blur collapses        -> antialiasing / sub-pixel rasterisation
             shift collapses       -> a real positional offset
             ink mass differs badly-> weight or double-paint difference
             none of the above     -> real glyph-shape or content difference
       * ink mass per region at a strict and a loose threshold, both sides.

Evidence rules: this is a diagnostic. It never renders a gate verdict, never
touches the RMSE ceiling, the references or the comparison. Its synthetic unit
tests live in tool/test_diag_c6_element_attribution.py and use no real fixture.

Usage: diag_c6_element_attribution.py <artifacts_dir> [--top N] [--pad PX]
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

import numpy as np
import pymupdf

REL_DIR = os.path.join('c6diag', 'element_attribution')
JSON_NAME = 'element_attribution.json'
TXT_NAME = 'element_attribution.txt'

# Classification thresholds. These are DIAGNOSTIC magnitudes for labelling a
# region's dominant cause; they are not gate criteria and nothing here is
# compared against the 0.02 ceiling.
BLUR_COLLAPSE = 0.55      # blurred RMSE / base RMSE below this = AA-dominated
SHIFT_COLLAPSE = 0.45     # RMSE at best shift / base RMSE below this = offset
INK_HIGH = 1.15           # rendered ink / preview ink above this = too much ink
INK_LOW = 0.85            # below this = missing ink
FRAME_PX = 2              # the gate crops 2 px from every side of both images
MAX_SHIFT = 2


def notice(title, lines):
    """Publish text through the only channel readable without job logs."""
    text = "\n".join(str(x) for x in lines)
    for i in range(0, len(text), 3000):
        chunk = (text[i:i + 3000]
                 .replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A'))
        print(f'::notice title={title}::{chunk}')


def warn(title, lines):
    text = "\n".join(str(x) for x in lines)
    for i in range(0, len(text), 3000):
        chunk = (text[i:i + 3000]
                 .replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A'))
        print(f'::warning title={title}::{chunk}')


# ----------------------------------------------------------------- imaging

def im_binary():
    """The same ImageMagick entry point the gate falls back through."""
    if shutil.which('convert'):
        return ['convert']
    if shutil.which('magick'):
        return ['magick', 'convert']
    raise RuntimeError('ImageMagick convert/magick not found')


def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f'{cmd[0]} failed ({proc.returncode}): '
                           f'{proc.stderr.strip()[:300]}')
    return proc.stdout


def render_pdf(pdf_path, out_prefix):
    """pdftoppm at 96 dpi, then the gate's pdftocairo fallback."""
    try:
        run(['pdftoppm', '-r', '96', '-png', pdf_path, out_prefix])
    except Exception:
        run(['pdftocairo', '-r', '96', '-png', pdf_path, out_prefix])
    out_dir = os.path.dirname(out_prefix)
    base = os.path.basename(out_prefix)
    return sorted(os.path.join(out_dir, f) for f in os.listdir(out_dir)
                  if f.startswith(base) and f.endswith('.png'))


def normalize(rendered, preview, width, height, dest):
    """Resize the rendered page to the manifest size and crop both sides."""
    crop = f'{width - 2 * FRAME_PX}x{height - 2 * FRAME_PX}+{FRAME_PX}+{FRAME_PX}'
    magick = im_binary()
    run(magick + [rendered, '-resize', f'{width}x{height}!', '-crop', crop,
                  '+repage', dest['norm']])
    run(magick + [preview, '-crop', crop, '+repage', dest['ref']])


def gate_rmse(norm, ref):
    """The gate's own metric, so this tool can prove it measures the same thing."""
    magick = im_binary()
    if shutil.which('compare'):
        compare = ['compare']
    elif shutil.which('magick'):
        compare = ['magick', 'compare']
    else:
        raise RuntimeError('ImageMagick compare not found')
    proc = subprocess.run(compare + ['-metric', 'RMSE', norm, ref, 'null:'],
                          capture_output=True, text=True)
    raw = (proc.stderr or proc.stdout).strip()
    if '(' in raw and ')' in raw:
        return float(raw[raw.rindex('(') + 1:raw.rindex(')')])
    return float(raw.split()[0]) / 65535.0


def second_rasterizer():
    """An independent PDF rasterizer, or None when the image lacks one.

    The gate compares a Preview raster (Skia) against poppler's rasterization of
    the Vector PDF, so its floor is not zero even for a pixel-perfect document.
    Rendering the *same* PDF with a second, independent rasterizer measures that
    floor on the document under test, in the same run and on the same bytes --
    which is the only way to say whether a residual belongs to the content or
    to the pair of rasterizers being compared.
    """
    for name, command in (
        ('mutool', ['mutool', 'draw', '-r', '96', '-o']),
        ('ghostscript', ['gs', '-q', '-dNOPAUSE', '-dBATCH', '-sDEVICE=png16m',
                         '-r96', '-sOutputFile=']),
    ):
        if shutil.which(command[0]) is None:
            continue
        return (name, command)
    return None


def render_with_second(rasterizer, pdf_path, out_prefix):
    name, command = rasterizer
    # Both tools take a `%d` page pattern; sorting is numeric so page 10 does
    # not land between 1 and 2. The caller passes a prefix inside the
    # temporary directory, whose subdirectory has to exist before the tool
    # writes its first page.
    os.makedirs(os.path.dirname(out_prefix) or '.', exist_ok=True)
    pattern = out_prefix + '%d.png'
    if name == 'mutool':
        run(command + [pattern, pdf_path])
    else:
        run(command[:-1] + [command[-1] + pattern, pdf_path])
    files = glob.glob(out_prefix + '*.png')
    return sorted(files, key=lambda path: int(
        ''.join(ch for ch in os.path.basename(path) if ch.isdigit()) or 0))


def read_gray(path):
    """8-bit luma float array in [0,1]; alpha is composited over white."""
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
    return gray / 255.0


def blur05(image):
    """Gaussian sigma 0.5, matching the gate's own `-blur 0x0.5` diagnostic.

    Edge pixels are extended rather than dropped, so a flat region stays flat
    and the blur changes contrast only where there is structure to lose.
    """
    kernel = np.array([0.106, 0.788, 0.106], dtype=np.float64)
    padded = np.pad(image, ((1, 1), (0, 0)), mode='edge')
    rows = np.apply_along_axis(
        lambda col: np.convolve(col, kernel, mode='valid'), 0, padded)
    padded = np.pad(rows, ((0, 0), (1, 1)), mode='edge')
    out = np.apply_along_axis(
        lambda row: np.convolve(row, kernel, mode='valid'), 1, padded)
    return np.clip(out, 0.0, 1.0)


# ------------------------------------------------------------ pure helpers

def rmse(a, b, mask=None):
    """RMSE over a mask (default: everything). Returns (rmse, sum_squared)."""
    diff = a - b
    if mask is not None:
        diff = diff[mask]
    if diff.size == 0:
        return 0.0, 0.0
    return float(np.sqrt(np.mean(diff ** 2))), float(np.sum(diff ** 2))


def best_shift(a, b, region, max_shift=MAX_SHIFT):
    """Best integer (dy, dx) for region of b under a, and its RMSE.

    Positive dy moves b down, positive dx moves b right. Shifts that leave the
    page are compared over their clamped overlap instead of being skipped, so a
    region that touches an edge -- every line at the top or left margin does --
    still gets a real answer rather than a silent zero.
    """
    y0, y1, x0, x1 = region
    h, w = a.shape
    base_rmse, _ = rmse(a[y0:y1, x0:x1], b[y0:y1, x0:x1])
    best = (0, 0, base_rmse)
    for dy in range(-max_shift, max_shift + 1):
        for dx in range(-max_shift, max_shift + 1):
            if dy == 0 and dx == 0:
                continue
            sy0, sy1 = max(0, y0 + dy), min(h, y1 + dy)
            sx0, sx1 = max(0, x0 + dx), min(w, x1 + dx)
            ay0, ay1 = sy0 - dy, sy1 - dy
            ax0, ax1 = sx0 - dx, sx1 - dx
            if ay1 <= ay0 or ax1 <= ax0:
                continue
            value, _ = rmse(a[ay0:ay1, ax0:ax1], b[sy0:sy1, sx0:sx1])
            if value < best[2]:
                best = (dy, dx, value)
    return best


def slant_profile(image, region, min_ink=4.0, min_rows=5):
    """Least-squares slope of the per-row ink centroid across a text region.

    A synthetic oblique shears glyph outlines so every row's ink centroid moves
    with y: the fitted slope equals the shear factor. Upright text has no such
    trend. Comparing the same region between the preview and the PDF therefore
    answers, with no rendering assumptions, whether one side is slanted and the
    other is not -- and, if it is, by how much.
    """
    y0, y1, x0, x1 = region
    block = 1.0 - image[y0:y1, x0:x1]
    xs = np.arange(block.shape[1], dtype=np.float64)
    rows = []
    for i in range(block.shape[0]):
        weights = block[i]
        total = float(weights.sum())
        if total < min_ink:
            continue
        rows.append((float(i), float((weights * xs).sum() / total), total))
    if len(rows) < min_rows:
        return None
    # Rows that carry much less ink than the densest one are ascender-only
    # slivers (or descender tails): their centroids jump with the glyphs that
    # happen to have ink there, and a fit that keeps them reports a large
    # "slope" for text that is perfectly upright. Measure only where the ink is
    # dense enough for a centroid to mean a position, and say how many rows that
    # was, so a reader can tell a real measurement from an unusable region.
    peak = max(row[2] for row in rows)
    dense = [row for row in rows if row[2] >= 0.1 * peak]
    if len(dense) < min_rows or len(dense) < 0.6 * len(rows):
        return None
    ys = np.array([r[0] for r in dense])
    cs = np.array([r[1] for r in dense])
    design = np.vstack([ys, np.ones_like(ys)]).T
    slope, intercept = np.linalg.lstsq(design, cs, rcond=None)[0]
    predicted = design @ np.array([slope, intercept])
    residual = float(((cs - predicted) ** 2).sum())
    spread = float(((cs - cs.mean()) ** 2).sum())
    # Zero centroid variance means a perfectly constant centroid: there is
    # nothing to explain, so r2 is reported as 1 (a perfect fit of a constant)
    # rather than as the undefined ratio it would otherwise be.
    return {'slope': float(slope), 'rows': len(rows),
            'dense_rows': len(dense),
            'r2': float(1 - residual / spread) if spread > 1e-9 else 1.0,
            'span': (int(y0 + dense[0][0]), int(y0 + dense[-1][0]))}


_RAMP = ' .:-=+*#%@'


def row_profile(image, region, floor_fraction=0.5):
    """Describe the heaviest horizontal ink band of a region.

    A line that carries a rule -- an underline, a fraction bar, a divider --
    differs between two renderings mostly by where that rule sits and how far
    it reaches, and a coarse map shows the two rules as two bands without
    saying which is which. This returns the numbers instead: the row with the
    most ink, its ink mass, the columns that row reaches at half its peak, and
    how many rows stay above that half-peak (a thick rule vs a thin one).
    """
    y0, y1, x0, x1 = region
    block = 1.0 - np.clip(image[y0:y1, x0:x1], 0.0, 1.0)
    if block.size == 0:
        return None
    mass = block.sum(axis=1)
    peak_row = int(np.argmax(mass))
    peak = float(mass[peak_row])
    if peak <= 0:
        return None
    row = block[peak_row]
    columns = np.nonzero(row >= floor_fraction * row.max())[0]
    return {
        'row': int(y0 + peak_row),
        'ink': round(peak / 255.0, 1),
        'span': (int(x0 + columns[0]), int(x0 + columns[-1])) if columns.size
                else None,
        'width_px': int(columns[-1] - columns[0] + 1) if columns.size else 0,
        'band_rows': int((mass >= floor_fraction * peak).sum()),
    }


def coarse_ink(image, region, cols=54, rows=13):
    """Box-average ink of a region as ASCII, for eyeballing in the annotation.

    The RMSE number cannot say whether one side is heavier, offset, or simply
    rasterised differently; a coarse picture can. Each character is one
    averaged cell, so a shifted stem or a weight difference is visible as an
    asymmetry between the two maps printed side by side.
    """
    y0, y1, x0, x1 = region
    block = 1.0 - np.clip(image[y0:y1, x0:x1], 0.0, 1.0)
    h, w = block.shape
    if h == 0 or w == 0:
        return ['(empty)']
    yy = np.linspace(0, h, rows + 1).astype(int)
    xx = np.linspace(0, w, cols + 1).astype(int)
    out = []
    for r in range(rows):
        row = []
        for c in range(cols):
            cell = block[yy[r]:max(yy[r] + 1, yy[r + 1]),
                         xx[c]:max(xx[c] + 1, xx[c + 1])]
            value = float(cell.mean()) if cell.size else 0.0
            row.append(_RAMP[min(len(_RAMP) - 1, int(value * len(_RAMP) * 2.2))])
        out.append(''.join(row))
    return out


def side_by_side(left, right, gap='  |  '):
    return [a + gap + b for a, b in zip(left, right)]


def ink_mass(image, region, strict=0.5, loose=0.05):
    """Ink above two thresholds: `strict` counts solid glyph cores, `loose`
    also counts antialiased fringes."""
    block = image[region[0]:region[1], region[2]:region[3]]
    return (float(np.sum(np.clip((block - strict) / (1 - strict), 0, 1))),
            float(np.sum(np.clip((block - loose) / (1 - loose), 0, 1))))


def classify(base, blurred, shifted, shift, ink_ratio):
    """Label the dominant cause of one region's residual (diagnostic only)."""
    if base <= 1e-9:
        return 'CLEAN', ''
    if shifted < base * SHIFT_COLLAPSE and (shift[0] or shift[1]):
        return 'POSITION', f'shift dy={shift[0]} dx={shift[1]}'
    if ink_ratio > INK_HIGH:
        return 'INK-EXCESS', f'rendered/preview ink {ink_ratio:.2f}'
    if ink_ratio < INK_LOW:
        return 'INK-MISSING', f'rendered/preview ink {ink_ratio:.2f}'
    if blurred < base * BLUR_COLLAPSE:
        return 'ANTIALIAS', f'blur collapses to {blurred / base:.2f}'
    return 'GLYPH-SHAPE', f'blur keeps {blurred / base:.2f}'


def merge_line_rects(words, scale, offx, offy, width, height, pad):
    """One rectangle per PDF line = union of its word boxes, padded and clipped."""
    lines = {}
    for w in words:
        x0, y0, x1, y1, text, block, line, _ = w
        key = (block, line)
        rect = lines.setdefault(key, [x0, y0, x1, y1, []])
        rect[0] = min(rect[0], x0)
        rect[1] = min(rect[1], y0)
        rect[2] = max(rect[2], x1)
        rect[3] = max(rect[3], y1)
        rect[4].append(text)
    out = []
    for key in sorted(lines):
        x0, y0, x1, y1, texts = lines[key]
        px0 = int(np.floor(x0 * scale - offx)) - pad
        py0 = int(np.floor(y0 * scale - offy)) - pad
        px1 = int(np.ceil(x1 * scale - offx)) + pad
        py1 = int(np.ceil(y1 * scale - offy)) + pad
        px0, py0 = max(0, px0), max(0, py0)
        px1, py1 = min(width, px1), min(height, py1)
        if px1 - px0 < 2 or py1 - py0 < 2:
            continue
        out.append({'key': key, 'region': (py0, py1, px0, px1),
                    'text': ' '.join(texts)})
    return out


def mask_of(shape, rects):
    mask = np.zeros(shape, dtype=bool)
    for rect in rects:
        y0, y1, x0, x1 = rect['region']
        mask[y0:y1, x0:x1] = True
    return mask


# --------------------------------------------------------------------- main

def band_lines(preview, rendered, worst):
    """Heaviest horizontal band of the worst offender, both renderings.

    Printed as two short lines next to the slant fits: it is what tells an
    underline, a fraction bar or a divider apart from a glyph-shape difference
    without the reader having to guess which band in the map belongs to whom.
    """
    region = y_first(worst['region'])
    lines = []
    for label, image in (('preview', preview), ('pdf', rendered)):
        profile = row_profile(image, region)
        if profile is None:
            lines.append(f'{label}: no ink band')
            continue
        lines.append(
            f'{label}: heaviest row y={profile["row"]} ink={profile["ink"]} '
            f'span={profile["span"]} width={profile["width_px"]}px '
            f'band_rows={profile["band_rows"]}')
    return lines


def analyse_page(index, args, page, norm_path, ref_path, scale, offx, offy,
                 floor=None):
    rendered = read_gray(norm_path)
    preview = read_gray(ref_path)
    if rendered.shape != preview.shape:
        raise RuntimeError(f'shape mismatch {rendered.shape} vs {preview.shape}')
    height, width = rendered.shape

    words = page.get_text('words')
    lines = merge_line_rects(words, scale, offx, offy, width, height, args.pad)
    text_mask = mask_of(rendered.shape, lines)

    total_rmse, total_sse = rmse(rendered, preview)
    text_rmse, text_sse = rmse(rendered, preview, text_mask)
    rest_rmse, rest_sse = rmse(rendered, preview, ~text_mask)
    blurred_r, blurred_p = blur05(rendered), blur05(preview)
    blur_rmse, _ = rmse(blurred_r, blurred_p)


    rows = []
    for item in lines:
        region = item['region']
        base, sse = rmse(rendered, preview, _only(region, rendered.shape))
        blurred, _ = rmse(blurred_r, blurred_p, _only(region, rendered.shape))
        shift = best_shift(rendered, preview, region)
        ink_r = ink_mass(rendered, region)
        ink_p = ink_mass(preview, region)
        ratio_s = ink_r[0] / ink_p[0] if ink_p[0] > 0 else float('inf')
        ratio_l = ink_r[1] / ink_p[1] if ink_p[1] > 0 else float('inf')
        verdict, why = classify(base, blurred, shift[2], shift[:2], ratio_s)
        rows.append({
            'text': item['text'][:120],
            'region': (int(region[2]), int(region[0]), int(region[3]), int(region[1])),
            'rmse': round(base, 6), 'blurred': round(blurred, 6),
            'best_shift': [int(shift[0]), int(shift[1])],
            'shift_rmse': round(shift[2], 6),
            'ink_ratio_strict': round(ratio_s, 3) if np.isfinite(ratio_s) else None,
            'ink_ratio_loose': round(ratio_l, 3) if np.isfinite(ratio_l) else None,
            'sse_share': round(100 * sse / max(total_sse, 1e-12), 3),
            'verdict': verdict, 'why': why,
        })

    counts = {}
    for r in rows:
        counts[r['verdict']] = counts.get(r['verdict'], 0) + 1

    rows.sort(key=lambda r: r['sse_share'], reverse=True)
    top = rows[:args.top]
    totals_lines = [
        f'gate-shaped RMSE (numpy luma) {total_rmse:.6f} | after 0.5px blur '
        f'{blur_rmse:.6f}',
        f'SSE share: text {100 * text_sse / max(total_sse, 1e-12):.2f}%  '
        f'non-text {100 * rest_sse / max(total_sse, 1e-12):.2f}%  '
        f'(text = {float(text_mask.mean()) * 100:.2f}% of the page)',
        f'RMSE inside text {text_rmse:.6f}  outside text {rest_rmse:.6f}',
        f'scale {scale:.4f} px/pt  crop offset ({offx},{offy})  '
        f'lines {len(lines)}  verdicts {counts}',
    ]
    if floor:
        # Same document, same page, two independent conforming rasterizers. The
        # first number holds no content difference at all, so a ceiling below it
        # cannot be met by any layout or formatting change.
        totals_lines.append(
            f'renderer floor: {floor["renderer"]} vs poppler on the SAME '
            f'vector.pdf = {floor["vs_poppler"]:.6f} | '
            f'{floor["renderer"]} vs preview = {floor["vs_preview"]:.6f} | '
            f'gate (poppler vs preview) = {floor["vs_gate"]:.6f}')
    notice(f'ATTR p{index} totals, floor, top offenders', totals_lines)
    slants = []
    for r in top[:4]:
        region = y_first(r['region'])
        s_preview = slant_profile(preview, region)
        s_rendered = slant_profile(rendered, region)
        if s_preview is None or s_rendered is None:
            continue
        slants.append(
            f'{r["verdict"][:6]} preview k={s_preview["slope"]:+.3f} '
            f'(r2 {s_preview["r2"]:.2f}, rows {s_preview["dense_rows"]}/'
            f'{s_preview["rows"]}) vs pdf k={s_rendered["slope"]:+.3f} '
            f'(r2 {s_rendered["r2"]:.2f}, rows {s_rendered["dense_rows"]}/'
            f'{s_rendered["rows"]})  {r["text"][:44]}')
    worst = top[0]
    region = y_first(worst['region'])
    # Maps are 40 columns wide with an 8-row difference strip: the annotation
    # budget is small, and a wider map would push the numbers out of it.
    preview_map = coarse_ink(preview, region, cols=40, rows=13)
    rendered_map = coarse_ink(rendered, region, cols=40, rows=13)
    diff_map = coarse_ink(1.0 - np.abs(preview - rendered), region,
                          cols=40, rows=8)
    notice(
        f'ATTR p{index} worst offender ink map (left preview | right pdf | '
        f'|difference|) {worst["text"][:50]}',
        [f'{worst["sse_share"]:.2f}% of SSE  rmse {worst["rmse"]:.4f}  '
         f'shift {worst["best_shift"]}'] +
        side_by_side(preview_map, rendered_map) + [''] + diff_map,
    )

    # One notice per page for the numbers: the step's annotation budget is
    # small and GitHub drops the surplus silently, so nothing here is
    # duplicated elsewhere in the page's output.
    notice(f'ATTR p{index} top lines by SSE share + ink slant', [
        f'{r["sse_share"]:6.2f}% rmse {r["rmse"]:.4f} blur {r["blurred"]:.4f} '
        f'shift {r["best_shift"]} inkS {r["ink_ratio_strict"]} '
        f'[{r["verdict"]}] {r["text"][:70]}'
        for r in top[:6]
    ] + slants + band_lines(preview, rendered, top[0]))

    return {'page': index, 'totals': {
        'rmse': round(total_rmse, 6), 'blur_rmse': round(blur_rmse, 6),
        'text_sse_share': round(100 * text_sse / max(total_sse, 1e-12), 3),
        'nontext_sse_share': round(100 * rest_sse / max(total_sse, 1e-12), 3),
        'text_rmse': round(text_rmse, 6), 'nontext_rmse': round(rest_rmse, 6),
    }, 'histogram': counts, 'lines': top}


def y_first(region):
    """Record order `(px0, py0, px1, py1)` -> numpy order `(y0, y1, x0, x1)`.

    The published line records keep rectangles x-first because that is how a
    reader expects to see a rectangle; every numpy helper here indexes y first
    (`image[y0:y1, x0:x1]`). Mixing the two silently measured the wrong box:
    the slant profile was fitted over a transposed region, which is why its r2
    looked like noise instead of a slant.
    """
    px0, py0, px1, py1 = region
    return (py0, py1, px0, px1)


def _only(region, shape):
    mask = np.zeros(shape, dtype=bool)
    mask[region[0]:region[1], region[2]:region[3]] = True
    return mask


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('artifacts')
    parser.add_argument('--top', type=int, default=12)
    parser.add_argument('--pad', type=int, default=1)
    args = parser.parse_args()

    art = args.artifacts
    print(f'[C6-ATTR] start on {art}')
    with open(os.path.join(art, 'manifest.json'), encoding='utf-8') as fh:
        manifest = json.load(fh)
    width = int(manifest['widthPx'])
    height = int(manifest['heightPx'])
    pages = int(manifest['pageCount'])

    out_dir = os.path.join(art, REL_DIR)
    os.makedirs(out_dir, exist_ok=True)

    doc = pymupdf.open(os.path.join(art, 'vector.pdf'))
    if doc.page_count != pages:
        warn('ATTR page count', [f'pdf {doc.page_count} vs manifest {pages}'])

    rasterizer = second_rasterizer()
    results = []
    floors = {}
    with tempfile.TemporaryDirectory() as tmp:
        vector_path = os.path.join(art, 'vector.pdf')
        rendered = render_pdf(vector_path, os.path.join(tmp, 'page'))
        control_pages = []
        if rasterizer is None:
            warn('ATTR renderer floor', [
                'no independent second rasterizer found (mutool/gs); the '
                'renderer floor cannot be measured in this run'])
        else:
            try:
                control_pages = render_with_second(
                    rasterizer, vector_path, os.path.join(tmp, 'second/page'))
            except Exception:
                warn('ATTR renderer floor', traceback.format_exc().splitlines()[-4:])
        if len(rendered) != pages:
            warn('ATTR render', [f'rendered {len(rendered)} pages, manifest {pages}'])
        for i in range(min(len(rendered), doc.page_count)):
            index = i + 1
            try:
                dest = {'norm': os.path.join(tmp, f'norm_{index}.png'),
                        'ref': os.path.join(tmp, f'ref_{index}.png')}
                preview_png = os.path.join(art, f'preview_page_{index}.png')
                normalize(rendered[i], preview_png, width, height, dest)
                gate_value = gate_rmse(dest['norm'], dest['ref'])
                floor = None
                if rasterizer is not None and index <= len(control_pages):
                    control = {'norm': os.path.join(tmp, f'second_{index}.png'),
                               'ref': os.path.join(tmp, f'ref2_{index}.png')}
                    normalize(control_pages[index - 1], preview_png,
                              width, height, control)
                    floor = {'renderer': rasterizer[0],
                             'vs_poppler': gate_rmse(control['norm'],
                                                     dest['norm']),
                             'vs_preview': gate_rmse(control['norm'],
                                                     control['ref']),
                             'vs_gate': gate_value}
                    floors[index] = {key: (round(value, 6)
                                           if isinstance(value, float)
                                           else value)
                                     for key, value in floor.items()}
                page = doc[i]
                # Scale from the FULL-page render, never from the cropped copy:
                # the crop removes 4 px of width, which would understate the
                # px/pt factor and misplace every region box.
                full = pymupdf.Pixmap(rendered[i])
                scale = full.width / page.rect.width
                offx = offy = FRAME_PX
                record = analyse_page(index, args, page, dest['norm'],
                                      dest['ref'], scale, offx, offy,
                                      floor=floor)
                record['totals']['gate_rmse'] = round(gate_value, 6)
                results.append(record)
            except Exception:
                warn(f'ATTR page{index} failed',
                     traceback.format_exc().splitlines()[-6:])

    with open(os.path.join(out_dir, JSON_NAME), 'w', encoding='utf-8') as fh:
        json.dump({'schema': 'c6-element-attribution-v1', 'pages': results,
                   'renderer_floor': floors},
                  fh, ensure_ascii=False, indent=1)
    with open(os.path.join(out_dir, TXT_NAME), 'w', encoding='utf-8') as fh:
        fh.write(f'renderer floor: {floors}\n')
        for record in results:
            fh.write(f"page {record['page']}: {record['totals']}\n")
            fh.write(f"  histogram {record['histogram']}\n")
            for row in record['lines']:
                fh.write(f"  {row['sse_share']:6.2f}% {row['verdict']:12s} "
                         f"{row['text']}\n")
    print(f'[C6-ATTR] wrote {out_dir}/{JSON_NAME} and {TXT_NAME}')


if __name__ == '__main__':
    main()
