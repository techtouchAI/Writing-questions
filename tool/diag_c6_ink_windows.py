#!/usr/bin/env python3
"""[C6-INK] TEMPORARY diagnostic (non-gating): ink inside verified word windows.

Not for merge. Changes no production file, no gate, no threshold, no image.

Question: is the PDF-vs-Preview ink excess (text ink ratio 1.23 / 1.29 in the
gate pages) caused by glyph shape, edge smoothing, stroke weight, or by a flaw
in how the comparison is made?

Method (measurement only):
  1. PDF raster = the gate's renderer: pdftoppm -r 96 (794x1123). Preview = the
     gate's preview_page_N.png (794x1123). Points map to pixels by 4/3.
  2. Only VERIFIED words are used: a Preview word paired with a PyMuPDF word,
     |dy| <= 0.05 pt and both edges within 0.1 pt (tool/diag_c6_text_positions.py).
  3. Three candidate-selection groups. They are reported separately and are
     never pooled into one statistic:
       R   reference: window = Preview line box + 1 px; neighbours = other
           Preview boxes and other PDF word boxes (the original criterion).
       P0  same as R with 0 px padding (tighter box, same neighbour rules).
       PB  window = PDF word box + 1 px; neighbours = other PDF word boxes only.
     A window is excluded (reason counted) when it touches the frame edge, a
     neighbour (overlap = negative gap; gap histogram kept), a rule or image,
     when the paper is not white, or when ink reaches the 2 px ring.
  4. Per window and side: coverage = clip((bg - gray) / bg, 0, 1), bg = median
     of the ring. Reported separately: mass (sum of coverage), dark (cov >= 0.5),
     core (cov >= 0.9), edge (0.1 < cov < 0.9), binary IoU (cov >= 0.5),
     local RMSE, and the coverage-weighted centroid offset (PDF - Preview).
  5. Control: the same windows rendered by MuPDF from the same PDF (PDF vs PDF).
  6. Shift sensitivity: the PDF window is sampled at (x+dx, y+dy) for each
     (dx, dy) in {-1,0,1}^2 (no correction applied to the data). dx is to the
     right, dy is DOWN (image rows grow downward). If the PDF ink lies k px
     lower than the Preview ink, the best match is at dy = +k; if it lies k px
     higher, at dy = -k. Only words valid at every shift enter the grid.
  7. Pooled ratios = sum(PDF) / sum(Preview) with a bootstrap over LINES (words
     in one line are not independent). Words are never resampled alone.
  8. Verdict per group (rule-based, see verdict()): INCONCLUSIVE when the sample
     is too small or the mass ratio moves more than SHIFT_TOL over the 3x3 grid.
     Attribution to stroke weight or edge smoothing is never made here; the
     pattern is only described.

Never fails the job; errors become notices. Writes to build/.../c6diag/ink_windows
and, when GITHUB_STEP_SUMMARY is set, appends a markdown summary to it.
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
RING = 2  # px ring used for background and leak checks
RING_MAX_COV = 0.10  # ink allowed in the ring (both sides)
BG_MIN = 200.0  # paper must be lighter than this (grey 0..255)
DARK = 0.5
CORE = 0.9
EDGE_LO = 0.1
POS_TOL_PT = 0.05  # verified: |dy| bound
EDGE_TOL_PT = 0.1  # verified: |dx| bound on both edges
RULE_MAX_PT = 4.0  # thin drawings are rules
LINE_TOL_PT = tp.BASELINE_TOL_PT  # same-line test for neighbour labels
BOOT = 2000
SEED = 0
SHIFTS = [(dx, dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
# PROVISIONAL thresholds (chosen by the agent, not validated scientifically).
MIN_WORDS = 30  # below this the sample is too small to generalise
MIN_LINES = 8
SHIFT_TOL = 0.10  # PROVISIONAL: max change of the mass ratio over the 3x3 grid
UNCHANGED_TOL = 1e-6  # mass ratio spread below this = the grid could not move it
# Only the two selections of this round run. Each one is reported on its own;
# their statistics are never pooled. PB was removed from this round (weaker
# neighbour protection: Preview neighbours are not checked, ring test only).
GROUPS = {
    'R': {'pad': 1, 'box': 'preview', 'neighbours': ('preview', 'pdf'),
          'label': 'reference: Preview box +1px; neighbours Preview+PDF'},
    'P0': {'pad': 0, 'box': 'preview', 'neighbours': ('preview', 'pdf'),
           'label': 'Preview box +0px; neighbours Preview+PDF'},
}
REL_DIR = os.path.join('c6diag', 'ink_windows')
SUMMARY_TXT = 'ink_windows_summary.txt'
SUMMARY_JSON = 'ink_windows_summary.json'
GAP_BINS = (-3, -2, -1, 0, 1, 2, 3)  # overlap gap in px, clipped to [-3, 3]


def _notice(title, lines, limit=3000):
    """Emit ::notice annotations. Splits only between whole lines and numbers
    each part as [i/n], so a reader can reassemble them in order."""
    parts, cur, size = [], [], 0
    for line in lines:
        if cur and size + len(line) + 1 > limit:
            parts.append(cur)
            cur, size = [], 0
        cur.append(line)
        size += len(line) + 1
    if cur:
        parts.append(cur)
    for i, part in enumerate(parts, 1):
        head = f'[{i}/{len(parts)}] ' if len(parts) > 1 else ''
        text = (head + '\n'.join(part)).replace('%', '%25').replace('\r', '%0D')
        print(f'::notice title={title}::{text.replace(chr(10), "%0A")}')


def _job_summary(lines):
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if not path:
        return
    try:
        with open(path, 'a', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')
    except OSError:
        pass


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

def window_of(x0, x1, top, bottom, pad=1):
    """Integer window [xa, xb) x [ya, yb) in pixels around a box in points."""
    xa = int(np.floor(x0 * S)) - pad
    xb = int(np.ceil(x1 * S)) + pad
    ya = int(np.floor(top * S)) - pad
    yb = int(np.ceil(bottom * S)) + pad
    return xa, ya, xb, yb


def shifted(win, dx, dy):
    xa, ya, xb, yb = win
    return (xa + dx, ya + dy, xb + dx, yb + dy)


def gap_of(a, b):
    """Separation in px between two windows. Negative = overlap."""
    sx = max(a[0] - b[2], b[0] - a[2])
    sy = max(a[1] - b[3], b[1] - a[3])
    return max(sx, sy)


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
    counts, _ = np.histogram(cov, bins=(0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0001))
    return [int(c) for c in counts]


# ----------------------------------------------------------- per page

def _line_key(pno, baseline):
    return f'{pno}:{round(baseline, 2)}'


def analyse_group(name, cfg, pno, gp, gq, gm, pdf_words, prev_words, pairs,
                  obstacles, drawings=()):
    """Candidates, accepted records and reason counts for one group."""
    pad = cfg['pad']
    verified = {}
    for i, j, _ in pairs:
        q, p = pdf_words[i], prev_words[j]
        if (abs(q['baseline'] - p['baseline']) <= POS_TOL_PT
                and abs(q['x0'] - p['left']) <= EDGE_TOL_PT
                and abs(q['x1'] - p['right']) <= EDGE_TOL_PT):
            verified[j] = i
    pw = [window_of(q['x0'], q['x1'], q['y0'], q['y1'], pad) for q in pdf_words]
    pv = []
    for p in prev_words:
        top = p['baseline'] - p['inner_asc']
        bottom = p['baseline'] + p['inner_desc']
        pv.append(window_of(p['left'], p['right'], top, bottom, pad))
    excluded = Counter()
    gaps = Counter()
    log = []  # one row per candidate: (line key, status, reason)
    records = []
    for j, i in sorted(verified.items()):
        p = prev_words[j]
        key = _line_key(pno, p['baseline'])
        win = pv[j] if cfg['box'] == 'preview' else pw[i]
        xa, ya, xb, yb = win
        reason = None
        if xa <= 0 or ya <= 0 or xb >= W or yb >= H:
            reason = 'frame_edge'
        if reason is None and 'preview' in cfg['neighbours']:
            for k, r in enumerate(pv):
                if k == j:
                    continue
                gap = gap_of(win, r)
                if gap < 0:
                    same = abs(prev_words[k]['baseline'] - p['baseline']) <= LINE_TOL_PT
                    reason = ('neighbour_preview_same_line' if same
                              else 'neighbour_preview_other_line')
                    gaps[max(-3, min(3, int(np.floor(gap))))] += 1
                    break
        if reason is None and 'pdf' in cfg['neighbours']:
            for k, r in enumerate(pw):
                if k == i:
                    continue
                gap = gap_of(win, r)
                if gap < 0:
                    same = abs(pdf_words[k]['baseline'] - p['baseline']) <= LINE_TOL_PT
                    reason = ('neighbour_pdf_same_line' if same
                              else 'neighbour_pdf_other_line')
                    gaps[max(-3, min(3, int(np.floor(gap))))] += 1
                    break
        if reason is None and any(rects_overlap(win, r) for r in obstacles):
            reason = 'rule_or_image'
        rec = None
        if reason is None:
            rec, reason = _measure(win, gp, gq, gm, pno, p, pdf_words[i])
        if rec is not None:
            rec['drawing_overlap'] = any(rects_overlap(win, d) for d in drawings)
            records.append(rec)
            log.append((key, 'accepted', ''))
        else:
            excluded[reason] += 1
            log.append((key, 'excluded', reason))
    return {'records': records, 'excluded': excluded, 'gaps': gaps,
            'candidates': len(verified), 'log': log}


def rects_overlap(win, r):
    return win[0] < r[2] and r[0] < win[2] and win[1] < r[3] and r[1] < win[3]


def _measure(win, gp, gq, gm, pno, p, q):
    """Returns (record, None) or (None, reason)."""
    bg_p, ring_p, cov_p = side_coverage(gp, win)
    bg_q, ring_q, cov_q = side_coverage(gq, win)
    if bg_p is None:
        return None, 'paper_not_white_pdf'
    if bg_q is None:
        return None, 'paper_not_white_preview'
    if ring_p > RING_MAX_COV:
        return None, 'ring_ink_pdf'
    if ring_q > RING_MAX_COV:
        return None, 'ring_ink_preview'
    bg_m, _, cov_m = side_coverage(gm, win)
    if cov_m is None or cov_m.shape != cov_p.shape:
        return None, 'control_missing'
    if cov_p.shape != cov_q.shape or cov_p.size == 0:
        return None, 'shape_mismatch'
    cxp, cyp = centroid(cov_p)
    cxq, cyq = centroid(cov_q)
    grid = {}
    for dx, dy in SHIFTS:
        sw = shifted(win, dx, dy)
        if sw[0] < 0 or sw[1] < 0 or sw[2] > W or sw[3] > H:
            grid[f'{dx},{dy}'] = None
            continue
        _, _, cov_s = side_coverage(gp, sw)
        if cov_s is None or cov_s.shape != cov_q.shape:
            grid[f'{dx},{dy}'] = None
            continue
        m = metrics(cov_s)
        m['iou'] = binary_iou(cov_s, cov_q)
        grid[f'{dx},{dy}'] = m
    return {
        'page': pno,
        'font': p['font'],
        'rtl': bool(p['rtl']),
        'line': _line_key(pno, p['baseline']),
        'text': p['text'],
        'pixels': int(cov_p.size),
        'pdf': metrics(cov_p),
        'prev': metrics(cov_q),
        'ctl': metrics(cov_m),
        'iou': binary_iou(cov_p, cov_q),
        'rmse': float(np.sqrt(np.mean(((gp[win[1]:win[3], win[0]:win[2]]
                                        - gq[win[1]:win[3], win[0]:win[2]])
                                       / 255.0) ** 2))),
        'cx': cxp - cxq,
        'cy': cyp - cyq,
        'hist_pdf': dark_histogram(cov_p),
        'hist_prev': dark_histogram(cov_q),
        'grid': grid,
    }, None


def page_obstacles(page):
    """(obstacles, drawings). Obstacles exclude windows (thin rules, images).
    Drawings are larger non-rule vector shapes: only COUNTED, never excluded,
    so the reference criterion is unchanged. Page-sized backgrounds are skipped."""
    obstacles, drawings = [], []
    page_area = float(page.rect.width * page.rect.height)
    for d in page.get_drawings():
        r = d['rect']
        if min(r.width, r.height) <= RULE_MAX_PT:
            obstacles.append(window_of(r.x0, r.x1, r.y0, r.y1, 1))
        elif r.width * r.height < 0.5 * page_area:
            drawings.append(window_of(r.x0, r.x1, r.y0, r.y1, 1))
    for info in page.get_image_info():
        b_ = info['bbox']
        obstacles.append(window_of(b_[0], b_[2], b_[1], b_[3], 1))
    return obstacles, drawings


# ------------------------------------------------------------- stats

def pooled(num, den, line_idx, n_lines, idx):
    """Pooled ratio sum(num)/sum(den) with a line-cluster bootstrap CI."""
    num_l = np.bincount(line_idx, weights=num, minlength=n_lines)
    den_l = np.bincount(line_idx, weights=den, minlength=n_lines)
    if den_l.sum() <= 0:
        return None, None
    est = float(num_l.sum() / den_l.sum())
    if idx is None:
        return est, None
    bn = num_l[idx].sum(axis=1)
    bd = den_l[idx].sum(axis=1)
    with np.errstate(divide='ignore', invalid='ignore'):
        r = bn / bd
    r = r[np.isfinite(r)]
    lo, hi = np.percentile(r, [2.5, 97.5])
    return est, [float(lo), float(hi)]


def _arr(records, path):
    vals = []
    for r in records:
        v = r
        for k in path:
            v = None if v is None else v[k]
        vals.append(np.nan if v is None else float(v))
    return np.array(vals, dtype=float)


def group_summary(records):
    if not records:
        return {'n_words': 0, 'n_lines': 0}
    lines = sorted({r['line'] for r in records})
    pos = {k: n for n, k in enumerate(lines)}
    line_idx = np.array([pos[r['line']] for r in records])
    L = len(lines)
    idx = None
    if L >= 3:
        idx = np.random.default_rng(SEED).integers(0, L, size=(BOOT, L))
    out = {'n_words': len(records), 'n_lines': L}
    for name in ('mass', 'dark', 'core', 'edge'):
        est, ci = pooled(_arr(records, ('pdf', name)), _arr(records, ('prev', name)),
                         line_idx, L, idx)
        out[f'R_{name}'] = {'est': est, 'ci95': ci}
        est_c, ci_c = pooled(_arr(records, ('ctl', name)), _arr(records, ('pdf', name)),
                             line_idx, L, idx)
        out[f'ctl_MuPDF_over_poppler_{name}'] = {'est': est_c, 'ci95': ci_c}
    out['median_iou'] = float(np.median(_arr(records, ('iou',))))
    out['median_rmse'] = float(np.median(_arr(records, ('rmse',))))
    out['median_cx_px'] = float(np.median(_arr(records, ('cx',))))
    out['median_cy_px'] = float(np.median(_arr(records, ('cy',))))
    out['mean_dcore_px_per_word'] = float(np.mean(_arr(records, ('pdf', 'core'))
                                                  - _arr(records, ('prev', 'core'))))
    out['mean_dedge_mass_per_word'] = float(np.mean(_arr(records, ('pdf', 'edge'))
                                                    - _arr(records, ('prev', 'edge'))))
    out['n_drawing_overlap'] = int(sum(bool(r.get('drawing_overlap')) for r in records))
    out['grid'] = shift_grid(records, line_idx, L, idx)
    out['iou_by_shift'] = _iou_by_shift(records)
    return out


def _iou_by_shift(records):
    """Median IoU per PDF-side shift over the words valid at that shift."""
    out = {}
    for dx, dy in SHIFTS:
        key = f'{dx},{dy}'
        vals = [r['grid'][key]['iou'] for r in records
                if r['grid'].get(key) is not None]
        out[key] = float(np.median(vals)) if vals else None
    return out


def best_shift(iou_by_shift):
    """(key, iou) with the highest median IoU. Ties prefer the smaller shift
    so that no direction is favoured by list order."""
    best = None
    for dx, dy in SHIFTS:
        key = f'{dx},{dy}'
        v = iou_by_shift.get(key)
        if v is None:
            continue
        rank = (v, -(abs(dx) + abs(dy)))
        if best is None or rank > best[0]:
            best = (rank, key, v)
    return (best[1], best[2]) if best else (None, None)


def shift_grid(records, line_idx, L, idx):
    """Pooled ratios and IoU for every PDF-side shift in SHIFTS (no correction).

    Only words whose window is valid at EVERY shift are used, so all rows share
    the same words and denominators (a shift near the frame edge cannot change
    the sample).
    """
    n = len(records)
    prev = {k: _arr(records, ('prev', k)) for k in ('mass', 'dark', 'core', 'edge')}
    per_shift = {}
    common = np.ones(n, dtype=bool)
    for dx, dy in SHIFTS:
        key = f'{dx},{dy}'
        cols = {k: np.full(n, np.nan) for k in ('mass', 'dark', 'core', 'edge', 'iou')}
        for n_i, r in enumerate(records):
            s_ = r['grid'].get(key)
            if s_ is not None:
                for k in cols:
                    cols[k][n_i] = float(s_[k])
        per_shift[key] = cols
        common &= np.isfinite(cols['mass'])
    rows = []
    for dx, dy in SHIFTS:
        cols = per_shift[f'{dx},{dy}']
        row = {'dx': dx, 'dy': dy, 'n_valid': int(common.sum())}
        if common.sum() == 0:
            rows.append(row)
            continue
        for name in ('mass', 'dark', 'core', 'edge'):
            est, _ = pooled(cols[name][common], prev[name][common],
                            line_idx[common],
                            int(np.unique(line_idx[common]).size), None)
            row[f'R_{name}'] = est
        row['median_iou'] = float(np.median(cols['iou'][common]))
        rows.append(row)
    return rows


def group_records(records):
    groups = {'all': records}
    for font in sorted({r['font'] for r in records}):
        groups[f'font={font}'] = [r for r in records if r['font'] == font]
    for pno in sorted({r['page'] for r in records}):
        groups[f'page={pno}'] = [r for r in records if r['page'] == pno]
    return groups


def verdict(g):
    """Rule-based verdict for one group. Never names a cause."""
    if g.get('n_words', 0) == 0:
        return 'INCONCLUSIVE: no accepted windows'
    if g['n_words'] < MIN_WORDS or g['n_lines'] < MIN_LINES:
        return (f'INCONCLUSIVE: sample too small (words {g["n_words"]}, '
                f'lines {g["n_lines"]}; need >= {MIN_WORDS} and {MIN_LINES})')
    masses = [row['R_mass'] for row in g['grid'] if row.get('R_mass') is not None]
    if len(masses) < len(SHIFTS):
        return 'INCONCLUSIVE: some shifts fall outside the frame'
    span = max(masses) - min(masses)
    if span <= UNCHANGED_TOL:
        # Every window holds all of its ink (the ring check enforces this), so
        # moving the window cannot change any coverage sum. The grid then
        # cannot test stability, and must not be read as evidence of it.
        return ('INCONCLUSIVE: 1px window shifts leave the mass ratio unchanged '
                f'(span {span:.1e}); this grid cannot test stability. IoU and '
                'centroid respond to shifts and are reported separately')
    if span > SHIFT_TOL:
        return (f'INCONCLUSIVE: mass ratio moves {span:.3f} over 1px shifts '
                f'(> {SHIFT_TOL})')
    if min(masses) < 1.0 < max(masses):
        return 'INCONCLUSIVE: mass ratio crosses 1.0 under a 1px shift'
    return f'STABLE over 1px shifts (mass ratio span {span:.3f})'


def pattern(g):
    """Descriptive pattern, only when the verdict is STABLE. Never a cause."""
    if not verdict(g).startswith('STABLE'):
        return 'pattern: not assessed (verdict not STABLE)'
    core, edge = g['R_core'], g['R_edge']
    if core['ci95'] is None or edge['ci95'] is None:
        return 'pattern: n/a (no CI)'
    core_up = core['ci95'][0] > 1.0
    edge_up = edge['ci95'][0] > 1.0
    if core_up and not edge_up:
        return 'pattern: solid-core excess, edge excess not established'
    if edge_up and not core_up:
        return 'pattern: edge excess, core excess not established'
    if core_up and edge_up:
        return 'pattern: both core and edge excess'
    return 'pattern: no excess established'


def _fmt_ci(v):
    if not v or v.get('est') is None:
        return 'n/a'
    est, ci = v['est'], v['ci95']
    if ci is None:
        return f'{est:.3f} (no CI)'
    return f'{est:.3f} [{ci[0]:.3f}, {ci[1]:.3f}]'


def _f(x):
    return 'n/a' if x is None else f'{x:.3f}'


def _group_block(name, g):
    lines = [f'{name}: words={g["n_words"]} lines={g["n_lines"]}']
    if g['n_words'] == 0:
        return lines
    lines.append(f'  verdict: {verdict(g)}; {pattern(g)}')
    lines.append(f'  non-rule drawings overlapping accepted windows (not excluded): '
                 f'{g.get("n_drawing_overlap", 0)}')
    lines.append(
        f'  R_mass={_fmt_ci(g["R_mass"])} R_dark={_fmt_ci(g["R_dark"])} '
        f'R_core={_fmt_ci(g["R_core"])} R_edge={_fmt_ci(g["R_edge"])}')
    lines.append(
        f'  ctl MuPDF/poppler mass={_fmt_ci(g["ctl_MuPDF_over_poppler_mass"])} '
        f'core={_fmt_ci(g["ctl_MuPDF_over_poppler_core"])} '
        f'edge={_fmt_ci(g["ctl_MuPDF_over_poppler_edge"])}')
    lines.append(
        f'  iou={g["median_iou"]:.3f} rmse={g["median_rmse"]:.4f} '
        f'cx={g["median_cx_px"]:.3f}px cy={g["median_cy_px"]:.3f}px '
        f'dCore/word={g["mean_dcore_px_per_word"]:.2f} '
        f'dEdge/word={g["mean_dedge_mass_per_word"]:.3f}')
    grid = ' | '.join(
        f'({r["dx"]:+d},{r["dy"]:+d}) mass={_f(r.get("R_mass"))} '
        f'core={_f(r.get("R_core"))} edge={_f(r.get("R_edge"))} '
        f'iou={_f(r.get("median_iou"))}'
        for r in g['grid'] if r.get('R_mass') is not None)
    lines.append(f'  shift grid: {grid}')
    return lines


def _line_stats_rows(lines):
    """One tuple per line with at least one accepted word.

    (line, words, R_mass, R_core, R_edge, IoU, cy, drawings, IoU@0,0,
     best shift, IoU@best). Single line: no bootstrap CI."""
    rows = []
    for key, g in lines.items():
        if g.get('n_words', 0) == 0:
            continue
        bk, bv = best_shift(g['iou_by_shift'])
        rows.append((key, g['n_words'], _f(g['R_mass']['est']), _f(g['R_core']['est']),
                     _f(g['R_edge']['est']), _f(g['median_iou']),
                     f'{g["median_cy_px"]:+.2f}', g.get('n_drawing_overlap', 0),
                     _f(g['iou_by_shift'].get('0,0')), bk or 'n/a', _f(bv)))
    return rows


def _line_combined(grp):
    """(line, accepted, excluded, reasons, stats-or-None) for every candidate line."""
    stats = {row[0]: row for row in _line_stats_rows(grp['lines'])}
    return [(key, a, e, why, stats.get(key))
            for key, a, e, why in _line_table(grp['log'])]


def _line_text(key, a, e, why, st):
    head = f'{key}: accepted={a} excluded={e} reasons: {why}'
    if st is None:
        return head
    _, n, rm, rc, re_, iou, cy, dr, iou0, bk, biou = st
    return (f'{head} || words={n} R_mass={rm} R_core={rc} R_edge={re_} '
            f'IoU={iou} IoU@0,0={iou0} best={bk} IoU_best={biou} '
            f'cy={cy}px drawings={dr}')


def _line_table(log):
    """Rows (page:baseline, accepted, excluded, reasons) from the candidate log."""
    acc, exc, why = Counter(), Counter(), {}
    for key, status, reason in log:
        if status == 'accepted':
            acc[key] += 1
        else:
            exc[key] += 1
            why.setdefault(key, Counter())[reason] += 1
    rows = []
    for key in sorted(set(acc) | set(exc), key=lambda k: (int(k.split(':')[0]), float(k.split(':')[1]))):
        reasons = ', '.join(f'{r}={n}' for r, n in sorted(why.get(key, Counter()).items()))
        rows.append((key, acc[key], exc[key], reasons or '-'))
    return rows


def _page_table(log):
    acc, exc, why = Counter(), Counter(), {}
    for key, status, reason in log:
        page = key.split(':')[0]
        if status == 'accepted':
            acc[page] += 1
        else:
            exc[page] += 1
            why.setdefault(page, Counter())[reason] += 1
    return [(pg, acc[pg], exc[pg], ', '.join(f'{r}={n}' for r, n in sorted(why.get(pg, Counter()).items())) or '-')
            for pg in sorted(set(acc) | set(exc))]


def _group_report(gname, grp):
    rows = []
    s = grp['summary']
    rows.append(f'== group {gname}: {GROUPS[gname]["label"]}')
    rows.append(f'  candidates={grp["candidates"]} accepted={s["n_words"]} '
                f'excluded={sum(grp["excluded"].values())} '
                f'reasons={dict(grp["excluded"])}')
    rows.append(f'  neighbour overlap gap histogram (px, clipped): '
                f'{dict(sorted(grp["gaps"].items()))}')
    rows.append(f'  verdict: {verdict(s)}; {pattern(s) if s["n_words"] else ""}')
    rows.extend(_group_block('all', s))
    for key, g in grp['groups'].items():
        if key == 'all' or g.get('n_words', 0) == 0:
            continue
        rows.extend(_group_block(key, g))
    for pg, a, e, why in _page_table(grp['log']):
        rows.append(f'  page {pg}: accepted={a} excluded={e} reasons: {why}')
    rows.append('  per line (single line: no CI; cy = PDF-Preview centroid, px):')
    for key, a, e, why, st in _line_combined(grp):
        rows.append('    ' + _line_text(key, a, e, why, st))
    return rows


def format_text(summary):
    lines = [
        'C6 ink inside verified word windows (non-gating; measurements only)',
        f'RING={RING}px DARK>={DARK} CORE>={CORE} bootstrap over lines, '
        f'B={BOOT}, seed={SEED}; sample rule: words>={MIN_WORDS}, lines>={MIN_LINES}; '
        f'shift tolerance {SHIFT_TOL}',
        f'render sizes: {summary["sizes"]}',
        f'verified pairs (from text-position matching): {summary["verified_pairs"]}',
        'shift key (dx,dy): PDF window sampled at x+dx, y+dy (dy down). '
        'Best match at dy=+k <=> PDF ink k px lower than Preview.',
    ]
    for gname, grp in summary['groups_by_selection'].items():
        lines.extend(_group_report(gname, grp))
    return lines


def annotation_lines(summary):
    lines = [f'verified pairs {summary["verified_pairs"]}, render {summary["sizes"]}']
    for gname, grp in summary['groups_by_selection'].items():
        s = grp['summary']
        lines.append(
            f'[{gname}] candidates {grp["candidates"]}, accepted {s["n_words"]}, '
            f'excluded {sum(grp["excluded"].values())} {dict(grp["excluded"])}')
        lines.append(f'   gap hist {dict(sorted(grp["gaps"].items()))}')
        if s['n_words']:
            lines.append(
                f'   R_mass={_fmt_ci(s["R_mass"])} R_core={_fmt_ci(s["R_core"])} '
                f'R_edge={_fmt_ci(s["R_edge"])} R_dark={_fmt_ci(s["R_dark"])}')
            lines.append(
                f'   ctl MuPDF/poppler mass={_fmt_ci(s["ctl_MuPDF_over_poppler_mass"])} '
                f'core={_fmt_ci(s["ctl_MuPDF_over_poppler_core"])} '
                f'edge={_fmt_ci(s["ctl_MuPDF_over_poppler_edge"])}')
            masses = ' '.join(f'({r["dx"]:+d},{r["dy"]:+d})={r["R_mass"]:.3f}'
                              for r in s['grid'] if r.get('R_mass') is not None)
            lines.append(f'   shift mass (unchanged by design, see verdict): {masses}')
            ious = ' '.join(f'({k})={_f(v)}' for k, v in s['iou_by_shift'].items())
            lines.append(f'   shift IoU (median over words): {ious}')
            lines.append(f'   verdict: {verdict(s)}; {pattern(s)}')
        for pg, acc_n, exc_n, why in _page_table(grp['log']):
            lines.append(f'   page {pg}: accepted={acc_n} excluded={exc_n} reasons={why}')
        for key, acc_n, exc_n, why, st in _line_combined(grp):
            lines.append('   line ' + _line_text(key, acc_n, exc_n, why, st))
    return lines


def _markdown(summary):
    out = ['## C6 ink windows (non-gating)', '',
           f'Verified pairs: {summary["verified_pairs"]}. Render: {summary["sizes"]}.', '',
           '| selection | accepted words / lines | excluded | mass R [95%] | core R | edge R | verdict |',
           '|---|---|---|---|---|---|---|']
    for gname, grp in summary['groups_by_selection'].items():
        s = grp['summary']
        out.append(
            f'| {gname} | {s["n_words"]} / {s["n_lines"]} | {sum(grp["excluded"].values())} '
            f'| {_fmt_ci(s["R_mass"])} | {_fmt_ci(s["R_core"])} | {_fmt_ci(s["R_edge"])} '
            f'| {verdict(s)} |')
    out.append('')
    for gname, grp in summary['groups_by_selection'].items():
        out.append(f'### {gname}: {GROUPS[gname]["label"]}')
        out.append('')
        out.append(f'- Exclusion reasons: `{dict(grp["excluded"])}`')
        out.append(f'- Neighbour gap histogram (px): `{dict(sorted(grp["gaps"].items()))}`')
        out.append('')
        out.append('| page | accepted | excluded | reasons |')
        out.append('|---|---|---|---|')
        for pg, a, e, why in _page_table(grp['log']):
            out.append(f'| {pg} | {a} | {e} | {why} |')
        out.append('')
        out.append('| line (page:baseline) | accepted | excluded | words | R_mass | R_core '
                   '| R_edge | IoU | IoU@0,0 | best shift | IoU@best | cy (px) | drawings '
                   '| reasons |')
        out.append('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        for key, a, e, why, st in _line_combined(grp):
            if st is None:
                out.append(f'| {key} | {a} | {e} | 0 | | | | | | | | | | {why} |')
            else:
                _, n, rm, rc, re_, iou, cy, dr, iou0, bk, biou = st
                out.append(f'| {key} | {a} | {e} | {n} | {rm} | {rc} | {re_} | {iou} '
                           f'| {iou0} | {bk} | {biou} | {cy} | {dr} | {why} |')
        out.append('')
        out.append('```')
        for key, g in grp['groups'].items():
            if g.get('n_words', 0):
                out.extend(_group_block(key, g))
        out.append('```')
        out.append('')
    return out


# --------------------------------------------------------------- run

def run(artifacts):
    pdf_path = os.path.join(artifacts, 'vector.pdf')
    out_dir = os.path.join(artifacts, REL_DIR)
    prev_path = os.path.join(artifacts, 'c6diag', 'text_positions', tp.PREVIEW_NAME)
    pngs = [os.path.join(artifacts, f'preview_page_{n}.png') for n in (1, 2)]
    if not (os.path.isfile(pdf_path) and os.path.isfile(prev_path)):
        _notice('C6 ink windows', ['skipped: missing vector.pdf or probe JSON'])
        return 0
    data = tp.load_preview(prev_path)
    prev_all, _ = tp.preview_word_records(data)
    pdf_pages = tp.extract_pdf_words(pdf_path)
    doc = pymupdf.open(pdf_path)
    per_group = {g: {'records': [], 'excluded': Counter(), 'gaps': Counter(),
                     'candidates': 0, 'log': []} for g in GROUPS}
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
                gm, sm = gray_mupdf(doc, pno)
                sizes[pno] = {'preview': sq, 'poppler': sp, 'mupdf': sm}
                if sq != (W, H) or sp != (W, H):
                    sizes[pno]['note'] = 'not 794x1123; page skipped'
                    continue
                gp = _fit(gp_raw)
                gq = _fit(gq)
                pdf_words = pdf_pages[pno]['words']
                page_prev = [p for p in prev_all if p['page'] == pno]
                pairs = tp.match_words(pdf_words, page_prev)
                obstacles, drawings = page_obstacles(doc[pno - 1])
                for gname, cfg in GROUPS.items():
                    res = analyse_group(gname, cfg, pno, gp, gq, gm, pdf_words,
                                        page_prev, pairs, obstacles, drawings)
                    acc = per_group[gname]
                    acc['records'].extend(res['records'])
                    acc['excluded'].update(res['excluded'])
                    acc['gaps'].update(res['gaps'])
                    acc['candidates'] += res['candidates']
                    acc['log'].extend(res['log'])
    finally:
        doc.close()
    groups_by_selection = {}
    for gname, acc in per_group.items():
        recs = acc['records']
        groups_by_selection[gname] = {
            'candidates': acc['candidates'],
            'excluded': dict(acc['excluded']),
            'gaps': dict(sorted(acc['gaps'].items())),
            'summary': group_summary(recs),
            'groups': {name: group_summary(sub)
                       for name, sub in group_records(recs).items()},
            'lines': {key: group_summary([r for r in recs if r['line'] == key])
                      for key in sorted({r['line'] for r in recs},
                                        key=lambda k: (int(k.split(':')[0]),
                                                       float(k.split(':')[1])))},
            'log': acc['log'],
        }
    # log is large; keep it in the text file only
    summary_json = {
        'schema': 'c6-ink-windows-v2',
        'sizes': {str(k): v for k, v in sizes.items()},
        'verified_pairs': per_group['R']['candidates'],
        'groups_by_selection': {
            g: {k: v for k, v in d.items() if k != 'log'}
            for g, d in groups_by_selection.items()},
    }
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, SUMMARY_JSON), 'w', encoding='utf-8') as fh:
        json.dump(summary_json, fh, ensure_ascii=False, indent=1)
    text_summary = dict(summary_json)
    text_summary['groups_by_selection'] = groups_by_selection
    with open(os.path.join(out_dir, SUMMARY_TXT), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(format_text(text_summary)) + '\n')
    _notice('C6 ink windows (non-gating)', annotation_lines(text_summary))
    _job_summary(_markdown(text_summary))
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
