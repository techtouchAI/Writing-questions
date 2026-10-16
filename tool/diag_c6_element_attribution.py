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

def analyse_page(index, args, page, norm_path, ref_path, scale, offx, offy):
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

    rows.sort(key=lambda r: r['sse_share'], reverse=True)
    top = rows[:args.top]
    notice(f'ATTR p{index} totals+histogram', [
        f'gate-shaped RMSE (numpy luma) {total_rmse:.6f} | after 0.5px blur '
        f'{blur_rmse:.6f}',
        f'SSE share: text {100 * text_sse / max(total_sse, 1e-12):.2f}%  '
        f'non-text {100 * rest_sse / max(total_sse, 1e-12):.2f}%  '
        f'(text = {float(text_mask.mean()) * 100:.2f}% of the page)',
        f'RMSE inside text {text_rmse:.6f}  outside text {rest_rmse:.6f}',
        f'scale {scale:.4f} px/pt  crop offset ({offx},{offy})  '
        f'lines {len(lines)}  verdicts {counts}',
    ])
    notice(f'ATTR p{index} top lines by SSE share', [
        f'{r["sse_share"]:6.2f}%  rmse {r["rmse"]:.4f} blur {r["blurred"]:.4f} '
        f'shift {r["best_shift"]}->{r["shift_rmse"]:.4f} '
        f'inkS {r["ink_ratio_strict"]} inkL {r["ink_ratio_loose"]} '
        f'[{r["verdict"]} {r["why"]}]  {r["text"]}'
        for r in top
    ])

    counts = {}
    for r in rows:
        counts[r['verdict']] = counts.get(r['verdict'], 0) + 1
    return {'page': index, 'totals': {
        'rmse': round(total_rmse, 6), 'blur_rmse': round(blur_rmse, 6),
        'text_sse_share': round(100 * text_sse / max(total_sse, 1e-12), 3),
        'nontext_sse_share': round(100 * rest_sse / max(total_sse, 1e-12), 3),
        'text_rmse': round(text_rmse, 6), 'nontext_rmse': round(rest_rmse, 6),
    }, 'histogram': counts, 'lines': top}


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
    notice('ATTR manifest', [f'{manifest}'])

    out_dir = os.path.join(art, REL_DIR)
    os.makedirs(out_dir, exist_ok=True)

    doc = pymupdf.open(os.path.join(art, 'vector.pdf'))
    if doc.page_count != pages:
        warn('ATTR page count', [f'pdf {doc.page_count} vs manifest {pages}'])

    results = []
    with tempfile.TemporaryDirectory() as tmp:
        rendered = render_pdf(os.path.join(art, 'vector.pdf'),
                              os.path.join(tmp, 'page'))
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
                page = doc[i]
                # Scale from the FULL-page render, never from the cropped copy:
                # the crop removes 4 px of width, which would understate the
                # px/pt factor and misplace every region box.
                full = pymupdf.Pixmap(rendered[i])
                scale = full.width / page.rect.width
                offx = offy = FRAME_PX
                record = analyse_page(index, args, page, dest['norm'],
                                      dest['ref'], scale, offx, offy)
                record['totals']['gate_rmse'] = round(gate_value, 6)
                notice(f'ATTR page{index} gate cross-check', [
                    f'`compare -metric RMSE` on the gate-shaped pair = '
                    f'{gate_value:.6f} (the gate prints its own number; a gap '
                    f'here would mean this tool is not measuring the same thing)'])
                results.append(record)
            except Exception:
                warn(f'ATTR page{index} failed',
                     traceback.format_exc().splitlines()[-6:])

    with open(os.path.join(out_dir, JSON_NAME), 'w', encoding='utf-8') as fh:
        json.dump({'schema': 'c6-element-attribution-v1', 'pages': results},
                  fh, ensure_ascii=False, indent=1)
    with open(os.path.join(out_dir, TXT_NAME), 'w', encoding='utf-8') as fh:
        for record in results:
            fh.write(f"page {record['page']}: {record['totals']}\n")
            fh.write(f"  histogram {record['histogram']}\n")
            for row in record['lines']:
                fh.write(f"  {row['sse_share']:6.2f}% {row['verdict']:12s} "
                         f"{row['text']}\n")
    print(f'[C6-ATTR] wrote {out_dir}/{JSON_NAME} and {TXT_NAME}')


if __name__ == '__main__':
    main()
