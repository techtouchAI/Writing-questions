#!/usr/bin/env python3
"""[C6-INK] TEMPORARY diagnostic (non-gating): ink inside verified word windows.

Not for merge. Changes no production file, no gate, no threshold, no image.

Question: is the PDF-vs-Preview ink excess (text ink ratio 1.23 / 1.29 in the
gate pages) caused by glyph shape, edge smoothing or stroke weight, or by a
flaw in how the comparison is made?

Method (measurement only):
  1. Same raster as the gate for the PDF: pdftoppm -r 96 (794x1123). The
     Preview PNG is the gate's own preview_page_N.png (794x1123).
     Frame mapping: pixel = point * 4/3 on both sides (canvas.scale(4/3)).
  2. Windows come only from words whose positions are VERIFIED: the Preview
     word is paired with a PyMuPDF word (tool/diag_c6_text_positions.py), with
     |dy| <= 0.05 pt and both edges within 0.1 pt. Nothing is fitted or shifted.
  3. A window is an integer box around the Preview line box (PAD px). It is
     excluded, with the reason counted, when it touches the frame edge, another
     word window (either side), a PDF word box, a thin rule or an image, when
     the paper around it is not white, or when ink reaches the 2 px ring around
     the window (glyph ink leaving the box, or a neighbour).
  4. Per window and per side: coverage = clip((bg - gray) / bg, 0, 1), with bg
     the median of the ring. Reported separately (never mixed):
       mass   = sum of coverage (grey ink mass)
       dark   = count of pixels with coverage >= 0.5
       core   = count of pixels with coverage >= 0.9 (solid stroke area)
       edge   = sum of coverage for 0.1 < coverage < 0.9 (antialiased edges)
     plus binarised IoU (coverage >= 0.5), local RMSE (gate scale 0..1) and the
     coverage-weighted centroid offset (PDF - Preview).
  5. Control: the same windows rendered from the same PDF by MuPDF (PDF vs PDF).
     Sensitivity: the PDF window moved by 1 px in each direction (no correction).
  6. Pooled ratios (sum PDF / sum Preview) with a bootstrap over LINES (words
     in one line are not independent). Words are never resampled alone.

Never fails the job; errors become notices.
Usage: diag_c6_ink_windows.py <artifacts_dir>
"""
import json
import os
import subprocess
import sys
import tempfile
import traceback
from collections import Counter

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_text_positions as tp  # noqa: E402  (word positions and matching)

W, H = 794, 1123  # gate render size
S = 4.0 / 3.0  # points to pixels at 96 dpi
PAD = 1  # px added around the Preview line box
RING = 2  # px ring used for background and leak checks
RING_MAX_COV = 0.10  # ink allowed in the ring (both sides)
BG_MIN = 200.0  # paper must be lighter than this (grey 0..255)
DARK = 0.5
CORE = 0.9
EDGE_LO = 0.1
POS_TOL_PT = 0.05  # verified: |dy| bound
EDGE_TOL_PT = 0.1  # verified: |dx| bound on both edges
RULE_MAX_PT = 4.0  # thin drawings are rules
BOOT = 2000
SEED = 0
SHIFTS = {'x+1': (1, 0), 'x-1': (-1, 0), 'y+1': (0, 1), 'y-1': (0, -1)}
REL_DIR = os.path.join('c6diag', 'ink_windows')
SUMMARY_TXT = 'ink_windows_summary.txt'
SUMMARY_JSON = 'ink_windows_summary.json'
BINS = (0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0001)


def _notice(title, lines):
    text = '\n'.join(lines)
    for i in range(0, len(text), 3000):
        chunk = text[i:i + 3000].replace('%', '%25').replace('\r', '%0D')
        chunk = chunk.replace('\n', '%0A')
        print(f'::notice title={title}::{chunk}')


# ------------------------------------------------------------- rasters

def _to_gray(arr):
    if arr.shape[2] >= 3:
        return arr[:, :, :3].mean(axis=2)
    return arr[:, :, 0]


def _fit(g, h=H, w=W):
    out = np.full((h, w), 255.0, np.float32)
    hh, ww = min(h, g.shape[0]), min(w, g.shape[1])
    out[:hh, :ww] = g[:hh, :ww]
    return out


def gray_from_png(path):
    pix = pymupdf.Pixmap(path)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
        pix.height, pix.width, pix.n).astype(np.float32)
    return _to_gray(arr), (pix.width, pix.height)


def gray_poppler(pdf_path, pno, tmpdir):
    """The gate's own renderer (pdftoppm -r 96)."""
    prefix = os.path.join(tmpdir, f'vec{pno}')
    subprocess.run(['pdftoppm', '-r', '96', '-png', '-singlefile',
                    '-f', str(pno), '-l', str(pno), pdf_path, prefix],
                   check=True, capture_output=True)
    return gray_from_png(prefix + '.png')


def gray_mupdf(doc, pno):
    """Control: the same PDF page rendered by MuPDF at the same scale."""
    pix = doc[pno - 1].get_pixmap(matrix=pymupdf.Matrix(S, S), alpha=False)
    arr = np.frombuffer(pix.samples, np.uint8).reshape(
        pix.height, pix.width, pix.n).astype(np.float32)
    return _fit(_to_gray(arr)), (pix.width, pix.height)


# ------------------------------------------------------------ geometry

def window_of(x0, x1, top, bottom):
    """Integer window [xa, xb) x [ya, yb) in pixels around a box in points."""
    xa = int(np.floor(x0 * S)) - PAD
    xb = int(np.ceil(x1 * S)) + PAD
    ya = int(np.floor(top * S)) - PAD
    yb = int(np.ceil(bottom * S)) + PAD
    return xa, ya, xb, yb


def rects_overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def ring_values(g, win):
    xa, ya, xb, yb = win
    h, w = g.shape
    x0, y0 = max(xa - RING, 0), max(ya - RING, 0)
    x1, y1 = min(xb + RING, w), min(yb + RING, h)
    block = g[y0:y1, x0:x1]
    mask = np.ones(block.shape, dtype=bool)
    mask[ya - y0:yb - y0, xa - x0:xb - x0] = False
    return block[mask]


def side_coverage(g, win):
    """(bg, ring_coverage_max, coverage) for one side, or (None, ...) on failure."""
    xa, ya, xb, yb = win
    ring = ring_values(g, win)
    bg = float(np.median(ring))
    if bg < BG_MIN:
        return None, None, None
    ring_cov = float(np.clip((bg - ring) / bg, 0, 1).max())
    cov = np.clip((bg - g[ya:yb, xa:xb]) / bg, 0, 1)
    return bg, ring_cov, cov


def metrics(cov):
    return {
        'mass': float(cov.sum()),
        'dark': float((cov >= DARK).sum()),
        'core': float((cov >= CORE).sum()),
        'edge': float(cov[(cov > EDGE_LO) & (cov < CORE)].sum()),
    }


def centroid(cov):
    ys, xs = np.mgrid[0:cov.shape[0], 0:cov.shape[1]]
    total = cov.sum()
    if total <= 0:
        return 0.0, 0.0
    return float((cov * xs).sum() / total), float((cov * ys).sum() / total)


def binary_iou(a, b):
    ma, mb = a >= DARK, b >= DARK
    union = np.logical_or(ma, mb).sum()
    return float(np.logical_and(ma, mb).sum() / union) if union else 1.0


def dark_histogram(cov):
    counts, _ = np.histogram(cov, bins=BINS)
    return [int(c) for c in counts]


# ----------------------------------------------------------- per page

def analyse_page(pno, gp, gq, gm, pdf_words, prev_words, pairs, obstacles):
    """Returns (records, excluded Counter, candidates int)."""
    excluded = Counter()
    records = []
    verified = {}
    for i, j, _ in pairs:
        q, p = pdf_words[i], prev_words[j]
        if (abs(q['baseline'] - p['baseline']) <= POS_TOL_PT
                and abs(q['x0'] - p['left']) <= EDGE_TOL_PT
                and abs(q['x1'] - p['right']) <= EDGE_TOL_PT):
            verified[j] = i
    pw_rects = [window_of(q['x0'], q['x1'], q['y0'], q['y1'])
                for q in pdf_words]
    pv_wins = []
    for p in prev_words:
        top = p['baseline'] - p['inner_asc']
        bottom = p['baseline'] + p['inner_desc']
        pv_wins.append(window_of(p['left'], p['right'], top, bottom))
    candidates = len(verified)
    for j, i in sorted(verified.items()):
        win = pv_wins[j]
        xa, ya, xb, yb = win
        if xa <= 0 or ya <= 0 or xb >= W or yb >= H:
            excluded['frame_edge'] += 1
            continue
        if any(k != j and rects_overlap(win, pv_wins[k])
               for k in range(len(prev_words))):
            excluded['neighbour_preview_window'] += 1
            continue
        if any(k != i and rects_overlap(win, pw_rects[k])
               for k in range(len(pdf_words))):
            excluded['neighbour_pdf_word'] += 1
            continue
        if any(rects_overlap(win, r) for r in obstacles):
            excluded['rule_or_image'] += 1
            continue
        bg_p, ring_p, cov_p = side_coverage(gp, win)
        bg_q, ring_q, cov_q = side_coverage(gq, win)
        if bg_p is None:
            excluded['paper_not_white_pdf'] += 1
            continue
        if bg_q is None:
            excluded['paper_not_white_preview'] += 1
            continue
        if ring_p > RING_MAX_COV:
            excluded['ring_ink_pdf'] += 1
            continue
        if ring_q > RING_MAX_COV:
            excluded['ring_ink_preview'] += 1
            continue
        bg_m, _, cov_m = side_coverage(gm, win)
        if cov_m is None or cov_m.shape != cov_p.shape:
            excluded['control_missing'] += 1
            continue
        if cov_p.shape != cov_q.shape or cov_p.size == 0:
            excluded['shape_mismatch'] += 1
            continue
        cxp, cyp = centroid(cov_p)
        cxq, cyq = centroid(cov_q)
        gpw = gp[ya:yb, xa:xb]
        gqw = gq[ya:yb, xa:xb]
        rec = {
            'page': pno,
            'font': prev_words[j]['font'],
            'rtl': bool(prev_words[j]['rtl']),
            'line': f'{pno}:{round(prev_words[j]["baseline"], 2)}',
            'text': prev_words[j]['text'],
            'pixels': int(cov_p.size),
            'pdf': metrics(cov_p),
            'prev': metrics(cov_q),
            'ctl': metrics(cov_m),
            'iou': binary_iou(cov_p, cov_q),
            'rmse': float(np.sqrt(np.mean(((gpw - gqw) / 255.0) ** 2))),
            'cx': cxp - cxq,
            'cy': cyp - cyq,
            'hist_pdf': dark_histogram(cov_p),
            'hist_prev': dark_histogram(cov_q),
            'shift': {},
        }
        for name, (dx, dy) in SHIFTS.items():
            sw = (xa + dx, ya + dy, xb + dx, yb + dy)
            if sw[0] < 0 or sw[1] < 0 or sw[2] > W or sw[3] > H:
                rec['shift'][name] = None
                continue
            _, _, cov_s = side_coverage(gp, sw)
            rec['shift'][name] = metrics(cov_s)['mass'] if cov_s is not None else None
        records.append(rec)
    return records, excluded, candidates



# ------------------------------------------------------------- stats

def pooled(num, den, line_idx, n_lines, idx):
    """Pooled ratio sum(num)/sum(den) with a line-cluster bootstrap CI."""
    num_l = np.bincount(line_idx, weights=num, minlength=n_lines)
    den_l = np.bincount(line_idx, weights=den, minlength=n_lines)
    if den_l.sum() <= 0:
        return None, None
    est = float(num_l.sum() / den_l.sum())
    if n_lines < 3:
        return est, None
    bn = num_l[idx].sum(axis=1)
    bd = den_l[idx].sum(axis=1)
    with np.errstate(divide='ignore', invalid='ignore'):
        r = bn / bd
    r = r[np.isfinite(r)]
    lo, hi = np.percentile(r, [2.5, 97.5])
    return est, [float(lo), float(hi)]


def group_summary(records):
    if not records:
        return {'n_words': 0}
    lines = sorted({r['line'] for r in records})
    pos = {k: n for n, k in enumerate(lines)}
    line_idx = np.array([pos[r['line']] for r in records])
    L = len(lines)
    rng = np.random.default_rng(SEED)
    idx = rng.integers(0, L, size=(BOOT, L)) if L >= 3 else None

    def arr(path):
        vals = []
        for r in records:
            v = r
            for k in path:
                v = v[k]
            vals.append(np.nan if v is None else float(v))
        return np.array(vals, dtype=float)

    out = {'n_words': len(records), 'n_lines': L}
    for name in ('mass', 'dark', 'core', 'edge'):
        est, ci = pooled(arr(('pdf', name)), arr(('prev', name)),
                         line_idx, L, idx)
        out[f'R_{name}'] = {'est': est, 'ci95': ci}
        est_c, ci_c = pooled(arr(('ctl', name)), arr(('pdf', name)),
                             line_idx, L, idx)
        out[f'MuPDF_over_poppler_{name}'] = {'est': est_c, 'ci95': ci_c}
    for sname in SHIFTS:
        vals = arr(('shift', sname))
        ok = np.isfinite(vals)
        if ok.sum() == 0:
            continue
        den = arr(('prev', 'mass'))[ok].sum()
        out[f'shift_{sname}_R_mass'] = float(vals[ok].sum() / den) if den else None
    out['median_iou'] = float(np.median(arr(('iou',))))
    out['median_rmse'] = float(np.median(arr(('rmse',))))
    out['median_cx_px'] = float(np.median(arr(('cx',))))
    out['median_cy_px'] = float(np.median(arr(('cy',))))
    out['excess_core_px_per_word'] = float(np.mean(arr(('pdf', 'core')) - arr(('prev', 'core'))))
    out['excess_edge_mass_per_word'] = float(np.mean(arr(('pdf', 'edge')) - arr(('prev', 'edge'))))
    return out


def group_records(records):
    groups = {'all': records}
    for font in sorted({r['font'] for r in records}):
        groups[f'font={font}'] = [r for r in records if r['font'] == font]
    for pno in sorted({r['page'] for r in records}):
        groups[f'page={pno}'] = [r for r in records if r['page'] == pno]
    return groups


def fmt_ci(v):
    if v is None:
        return 'n/a'
    est, ci = v['est'], v['ci95']
    if est is None:
        return 'n/a'
    if ci is None:
        return f'{est:.3f}'
    return f'{est:.3f} [{ci[0]:.3f}, {ci[1]:.3f}]'


def annotation_lines(summary):
    lines = []
    lines.append(f'candidates {summary["candidates"]}, accepted {summary["accepted"]}, '
                 f'excluded {summary["excluded"]}')
    for name, g in summary['groups'].items():
        if g.get('n_words', 0) == 0:
            continue
        lines.append(
            f'[{name}] words={g["n_words"]} lines={g["n_lines"]} '
            f'R_mass={fmt_ci(g["R_mass"])} R_dark={fmt_ci(g["R_dark"])} '
            f'R_core={fmt_ci(g["R_core"])} R_edge={fmt_ci(g["R_edge"])}')
        lines.append(
            f'   ctl MuPDF/poppler mass={fmt_ci(g["MuPDF_over_poppler_mass"])} '
            f'core={fmt_ci(g["MuPDF_over_poppler_core"])} '
            f'edge={fmt_ci(g["MuPDF_over_poppler_edge"])}')
        lines.append(
            f'   iou={g["median_iou"]:.3f} rmse={g["median_rmse"]:.4f} '
            f'cx={g["median_cx_px"]:.3f}px cy={g["median_cy_px"]:.3f}px '
            f'dCore/word={g["excess_core_px_per_word"]:.2f} '
            f'dEdge/word={g["excess_edge_mass_per_word"]:.3f}')
    return lines


def format_text(summary):
    lines = [
        'C6 ink inside verified word windows (non-gating; measurements only)',
        f'PAD={PAD}px RING={RING}px DARK>={DARK} CORE>={CORE} '
        f'bootstrap over lines, B={BOOT}, seed={SEED}',
        f'render sizes: {summary["sizes"]}',
        f'excluded reasons: {summary["excluded"]}',
    ]
    lines.extend(annotation_lines(summary))
    lines.append('--- full groups ---')
    for name, g in summary['groups'].items():
        lines.append(f'{name}: {json.dumps(g, ensure_ascii=False)}')
    return lines


# --------------------------------------------------------------- run

def run(artifacts):
    pdf_path = os.path.join(artifacts, 'vector.pdf')
    out_dir = os.path.join(artifacts, REL_DIR)
    prev_path = os.path.join(artifacts, 'c6diag', 'text_positions',
                             tp.PREVIEW_NAME)
    pngs = [os.path.join(artifacts, f'preview_page_{n}.png') for n in (1, 2)]
    if not (os.path.isfile(pdf_path) and os.path.isfile(prev_path)):
        _notice('C6 ink windows', ['skipped: missing vector.pdf or probe JSON'])
        return 0
    data = tp.load_preview(prev_path)
    prev_all, _ = tp.preview_word_records(data)
    pdf_pages = tp.extract_pdf_words(pdf_path)
    doc = pymupdf.open(pdf_path)
    records, excluded, candidates = [], Counter(), 0
    sizes = {}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            for pno in sorted(pdf_pages):
                png = pngs[pno - 1] if pno <= len(pngs) else None
                if png is None or not os.path.isfile(png):
                    sizes[pno] = 'preview png missing'
                    continue
                gq, sq = gray_from_png(png)
                gp_raw, sp = gray_poppler(pdf_path, pno, tmp)
                gm_raw, sm = gray_mupdf(doc, pno)
                sizes[pno] = {'preview': sq, 'poppler': sp, 'mupdf': sm}
                if sq != (W, H) or sp != (W, H):
                    sizes[pno]['note'] = 'not 794x1123; page skipped'
                    continue
                gp = _fit(gp_raw)
                gq = _fit(gq)
                gm = gm_raw
                pdf_words = pdf_pages[pno]['words']
                page_prev = [p for p in prev_all if p['page'] == pno]
                pairs = tp.match_words(pdf_words, page_prev)
                page = doc[pno - 1]
                obstacles = []
                for d in page.get_drawings():
                    r = d['rect']
                    if min(r.width, r.height) <= RULE_MAX_PT:
                        obstacles.append(window_of(r.x0, r.x1, r.y0, r.y1))
                for info in page.get_image_info():
                    b = info['bbox']
                    obstacles.append(window_of(b[0], b[2], b[1], b[3]))
                recs, exc, cand = analyse_page(pno, gp, gq, gm, pdf_words,
                                               page_prev, pairs, obstacles)
                records.extend(recs)
                excluded.update(exc)
                candidates += cand
    finally:
        doc.close()
    summary = {
        'schema': 'c6-ink-windows-v1',
        'sizes': {str(k): v for k, v in sizes.items()},
        'candidates': candidates,
        'accepted': len(records),
        'excluded': dict(excluded),
        'groups': {name: group_summary(recs)
                   for name, recs in group_records(records).items()},
    }
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, SUMMARY_JSON), 'w', encoding='utf-8') as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(out_dir, SUMMARY_TXT), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(format_text(summary)) + '\n')
    _notice('C6 ink windows (non-gating)', annotation_lines(summary))
    return 0


def main(argv):
    if len(argv) != 2:
        print('usage: diag_c6_ink_windows.py <artifacts_dir>')
        return 0
    try:
        return run(argv[1])
    except Exception:  # non-gating: report and exit 0
        _notice('C6 ink windows error', traceback.format_exc().splitlines())
        return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
