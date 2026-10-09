#!/usr/bin/env python3
# [C6-DIAG] TEMPORARY diagnostic (removed before merge). Not a gate: always exits 0.
#
# Inputs (written by test/visual/visual_parity_fixture_test.dart):
#   manifest.json, preview_page_N.png, vector.pdf, diag_geometry.json
# Outputs: build/visual_parity/diag/report.txt and ::notice annotations.
#
# Method:
#   1. pdftoppm -r 96 renders vector.pdf exactly as tool/verify_visual_parity.sh
#      does; the RMSE below reproduces that script's number (2px crop).
#   2. Squared error is attributed to canonical categories (text word boxes,
#      math boxes, floats, decorations, unexplained) from diag_geometry.json.
#   3. Per canonical line: best integer (dx,dy) pixel shift of the vector render
#      against the preview, to detect misplaced lines.
#   4. PyMuPDF reads the glyph origins emitted into vector.pdf and matches each
#      canonical word origin, giving the emitted geometry error in points.
import glob
import json
import math
import os
import re
import subprocess
import sys
import traceback

import numpy as np
from PIL import Image

PT2PX = 96.0 / 72.0
CROP = 2
SHIFT = 3
TEXT_UP = 1.0   # em above baseline (generous ascent box)
TEXT_DOWN = 0.35  # em below baseline
CATS = ['text', 'math', 'float', 'decor', 'none']

report = []


def out(line=''):
    report.append(line)


def natural_key(path):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', path)]


def load_rgb(path):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float64) / 255.0


def rmse(a, b):
    return math.sqrt(float(np.mean((a - b) ** 2)))


def paint_rect(mask, x0, y0, x1, y1, value):
    h, w = mask.shape
    xs, xe = max(0, int(math.floor(x0))), min(w, int(math.ceil(x1)))
    ys, ye = max(0, int(math.floor(y0))), min(h, int(math.ceil(y1)))
    if xe > xs and ye > ys:
        mask[ys:ye, xs:xe] = value


def pt_rect_px(x, y, w, h):
    return x * PT2PX, y * PT2PX, (x + w) * PT2PX, (y + h) * PT2PX


def emit_notices(lines, title):
    # GitHub annotations: keep each message well under the 4 KB display cap.
    chunk, size, part = [], 0, 1
    def flush():
        nonlocal chunk, size, part
        if not chunk:
            return
        text = '\n'.join(chunk)
        text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::notice title={title} ({part})::{text}', flush=True)
        chunk, size, part = [], 0, part + 1
    for line in lines:
        cost = len(line.encode('utf-8')) + 1
        if size + cost > 3000 and chunk:
            flush()
        chunk.append(line)
        size += cost
    flush()


def main(art):
    diag = os.path.join(art, 'diag')
    os.makedirs(diag, exist_ok=True)
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    width, height = int(manifest['widthPx']), int(manifest['heightPx'])
    pages_n = int(manifest['pageCount'])
    prefix = os.path.join(diag, 'vec')
    subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix],
                   check=True)
    rendered = sorted(glob.glob(prefix + '-*.png'), key=natural_key)
    out(f'[C6-DIAG] pages={pages_n} size={width}x{height} rendered={len(rendered)}')

    import pymupdf
    pdf = pymupdf.open(os.path.join(art, 'vector.pdf'))

    total_rmse_all = []
    for index in range(pages_n):
        out('')
        out(f'==== PAGE {index + 1} ====')
        preview = load_rgb(os.path.join(art, f'preview_page_{index + 1}.png'))
        vec = load_rgb(rendered[index])
        if preview.shape != vec.shape:
            out(f'SIZE MISMATCH preview={preview.shape} vector={vec.shape}')
            continue
        pa = preview[CROP:-CROP, CROP:-CROP]
        va = vec[CROP:-CROP, CROP:-CROP]
        H, W = pa.shape[:2]
        sse = np.mean((pa - va) ** 2, axis=2)
        page_rmse = math.sqrt(float(sse.mean()))
        total_rmse_all.append(page_rmse)
        out(f'RMSE(official crop)={page_rmse:.6f}')

        # (1) global integer shift search (interior, away from edges)
        best = None
        m = 6
        ref = pa[m:-m, m:-m]
        for dy in range(-SHIFT, SHIFT + 1):
            for dx in range(-SHIFT, SHIFT + 1):
                cand = va[m + dy:H - m + dy, m + dx:W - m + dx]
                value = rmse(ref, cand)
                if best is None or value < best[0]:
                    best = (value, dx, dy)
        zero = rmse(ref, va[m:-m, m:-m])
        out(f'global shift: rmse0={zero:.6f} best={best[0]:.6f} at dx={best[1]} dy={best[2]}')

        page = geo['pages'][index]
        words = page['words']
        # (2) category masks (cropped coordinate frame)
        labels = np.zeros((H + 2 * CROP, W + 2 * CROP), dtype=np.uint8)
        cat_id = {'text': 1, 'decor': 2, 'float': 3, 'math': 4}
        for d in page['decorations']:
            x0, y0, x1, y1 = pt_rect_px(d['x'], d['y'], d['w'], d['h'])
            s = max(1.0, d.get('stroke', 0) * PT2PX)
            paint_rect(labels, x0 - s, y0 - s, x1 + s, y1 + s, cat_id['decor'])
        for f in page['floats']:
            x0, y0, x1, y1 = pt_rect_px(f['x'], f['y'], f['w'], f['h'])
            paint_rect(labels, x0, y0, x1, y1, cat_id['float'])
        for w in words:
            x0 = w['x'] * PT2PX
            x1 = (w['x'] + w['adv']) * PT2PX
            y0 = (w['y'] - TEXT_UP * w['size']) * PT2PX
            y1 = (w['y'] + TEXT_DOWN * w['size']) * PT2PX
            paint_rect(labels, x0, y0, x1, y1, cat_id['text'])
        for mb in page['math']:
            x0 = mb['x'] * PT2PX
            x1 = (mb['x'] + mb['w']) * PT2PX
            y0 = mb['y'] * PT2PX
            y1 = (mb['y'] + mb['h']) * PT2PX
            paint_rect(labels, x0, y0, x1, y1, cat_id['math'])
        lab = labels[CROP:-CROP, CROP:-CROP]
        out('category      px      SSE-share  RMSE-in-mask')
        total_sse = float(sse.sum())
        for name, cid in [('text', 1), ('decor', 2), ('float', 3), ('math', 4), ('none', 0)]:
            sel = lab == cid
            npx = int(sel.sum())
            if npx == 0:
                out(f'{name:<10} {0:>8}      -            -')
                continue
            s = float(sse[sel].sum())
            out(f'{name:<10} {npx:>8}  {100 * s / total_sse:8.2f}%    {math.sqrt(s / npx):.6f}')

        # (3) per-line best shift
        lines = {}
        for w in words:
            key = round(w['y'], 2)
            lines.setdefault(key, []).append(w)
        rows = []
        for key, group in lines.items():
            size = max(w['size'] for w in group)
            x0 = min(w['x'] for w in group) * PT2PX - 2
            x1 = max(w['x'] + w['adv'] for w in group) * PT2PX + 2
            y0 = (key - TEXT_UP * size) * PT2PX
            y1 = (key + TEXT_DOWN * size) * PT2PX
            ya, yb = int(max(0, math.floor(y0)) - CROP), int(min(H + 2 * CROP, math.ceil(y1)) - CROP)
            xa, xb = int(max(0, math.floor(x0)) - CROP), int(min(W + 2 * CROP, math.ceil(x1)) - CROP)
            ya, xa = max(ya, 4), max(xa, 4)
            yb, xb = min(yb, H - 4), min(xb, W - 4)
            if yb - ya < 8 or xb - xa < 8:
                continue
            ref_band = pa[ya:yb, xa:xb]
            line_sse = float(sse[ya:yb, xa:xb].sum())
            zero_band = rmse(ref_band, va[ya:yb, xa:xb])
            bestl = None
            for dy in range(-SHIFT, SHIFT + 1):
                for dx in range(-SHIFT, SHIFT + 1):
                    cand = va[ya + dy:yb + dy, xa + dx:xb + dx]
                    value = rmse(ref_band, cand)
                    if bestl is None or value < bestl[0]:
                        bestl = (value, dx, dy)
            sample = ' '.join(w['t'] for w in group[:4])[:38]
            rows.append((line_sse, key, size, group[0]['font'], zero_band, bestl, sample,
                         len(group), line_sse / total_sse * 100))
        rows.sort(key=lambda r: -r[0])
        out('top lines by SSE (best-shift: dx,dy in px; +dy = vector content lower than preview):')
        for r in rows[:14]:
            _, key, size, font, z, bl, sample, n, share = r
            out(f'  y={key:7.2f} s={size:4.1f} {font[:6]:<6} r0={z:.4f} '
                f'best={bl[0]:.4f}({bl[1]:+d},{bl[2]:+d}) sse%={share:5.2f} n={n} "{sample}"')
        shifted = [r for r in rows if r[5][1] != 0 or r[5][2] != 0]
        out(f'lines={len(rows)} lines_with_nonzero_best_shift={len(shifted)}')

        # (4) emitted glyph origins vs canonical word origins (PyMuPDF)
        try:
            chars = []
            pdf_page = pdf[index]
            raw = pdf_page.get_text('rawdict')
            for block in raw['blocks']:
                for line in block.get('lines', []):
                    for span in line.get('spans', []):
                        for ch in span.get('chars', []):
                            ox, oy = ch['origin']
                            chars.append((ox, oy, ch['c'], span['size'], span['font']))
            cx = np.array([c[0] for c in chars]) if chars else np.zeros(0)
            cy = np.array([c[1] for c in chars]) if chars else np.zeros(0)
            dxs, dys, size_bad, miss, examples = [], [], 0, 0, []
            for w in words:
                if cx.size == 0:
                    miss += 1
                    continue
                cand = np.where((np.abs(cy - w['y']) < 4.0) & (np.abs(cx - w['x']) < 4.0))[0]
                if cand.size == 0:
                    miss += 1
                    if len(examples) < 6:
                        examples.append(f'MISS y={w["y"]:.2f} x={w["x"]:.2f} "{w["t"][:14]}"')
                    continue
                best_i = cand[int(np.argmin(np.abs(cx[cand] - w['x']) + np.abs(cy[cand] - w['y'])))]
                ddx = float(cx[best_i] - w['x'])
                ddy = float(cy[best_i] - w['y'])
                dxs.append(ddx)
                dys.append(ddy)
                if abs(chars[best_i][3] - w['size']) > 0.01:
                    size_bad += 1
                if abs(ddx) > 0.05 or abs(ddy) > 0.05:
                    if len(examples) < 14:  # ddy: +ve = emitted lower than canonical
                        examples.append(f'dx={ddx:+.3f} dy={ddy:+.3f} "{w["t"][:14]}" y={w["y"]:.2f}')
            if dxs:
                ax, ay = np.abs(dxs), np.abs(dys)
                out(f'pdf-origin check: words={len(words)} matched={len(dxs)} miss={miss} '
                    f'size_mismatch={size_bad}')
                out(f'  |dx| median={np.median(ax):.4f} max={ax.max():.4f} | '
                    f'|dy| median={np.median(ay):.4f} max={ay.max():.4f} '
                    f'| >0.05pt: {int(np.sum((ax > 0.05) | (ay > 0.05)))}')
            else:
                out(f'pdf-origin check: no matches (words={len(words)} chars={len(chars)})')
            for e in examples:
                out('  ' + e)
        except Exception as error:  # diagnostics never fail the build
            out(f'pdf-origin check failed: {error!r}')

        # (5) ASCII heat map (cell 16x24 px, cell RMSE)
        out('heat map (cell 16x24px; " .:+#@" = rmse <.01 <.03 <.06 <.10 <.15 >=.15):')
        cw, ch = 16, 24
        glyphs = ' .:+#@'
        thresholds = [0.01, 0.03, 0.06, 0.10, 0.15]
        for by in range(0, H, ch):
            row = []
            for bx in range(0, W, cw):
                cell = sse[by:by + ch, bx:bx + cw]
                v = math.sqrt(float(cell.mean())) if cell.size else 0.0
                k = sum(1 for t in thresholds if v >= t)
                row.append(glyphs[k])
            out('|' + ''.join(row) + '|')

    if total_rmse_all:
        out('')
        out('RMSE summary: ' + ', '.join(f'p{i + 1}={v:.6f}' for i, v in enumerate(total_rmse_all)))
    with open(os.path.join(diag, 'report.txt'), 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(report) + '\n')
    emit_notices(report, 'C6-DIAG')


if __name__ == '__main__':
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity')
    except Exception:  # never fail the build from diagnostics
        out('DIAG FAILED: ' + traceback.format_exc()[-1500:])
        emit_notices(report, 'C6-DIAG')
    sys.exit(0)
