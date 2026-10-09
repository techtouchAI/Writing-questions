#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY fixture-composition investigation. Not for merge; removed in cleanup.

Diagnostic only: no production change, no threshold change, no expected-image change.
Every alignment below is an oracle measurement used to separate error sources; none of
them is a proposed correction.

  C0  checker calibration: PDF origins read back on hx ladder PDFs with known x (1/8 px steps)
  C1  controlled ladder2 (fixture style NotoNaskh 10.5/1.5): per-word and per-glyph PDF origins
      against Flutter word/glyph lefts, window-matched by position on the baseline (bidi-safe,
      punctuation-safe), plus image-level RMSE decomposition
  C2  fixture Preview-vs-PDF word origins (run-level paragraph lefts from geometry 'pv'/'rx')
  C3  fixture per-glyph check (word-level Flutter lefts 'gl') with the same window matching
  C4  fixture RMSE decomposition per page: geometry (per-run sub-pixel oracle), global tone
      (histogram match), and core/edge/background SSE shares
  C5  fixture per-run sub-pixel dx against the measured Preview-vs-PDF word offset, and
      composition classes (direction, digits, punctuation, mixed script, word count, runs/line)
  C6  italic: Flutter synthetic oblique vs upright Flutter on the identical upright PDF
  C7  anti-aliasing / rasterizer: Poppler vs MuPDF on the same PDF, and Flutter vs Poppler
      after geometric and tonal decomposition

Conventions: rp.sample_shifted(img, dy, dx): out[y, x] = img[y+dy, x+dx]. A fit of
mov onto ref returns (dy, dx) such that mov sampled at +(dy, dx) matches ref. Positive
dy means mov (vector / Flutter) content is lower than ref (poppler / preview) content.
"""
import glob
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import traceback

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_raster_probe as rp  # noqa: E402
import diag_baseline_model as dbm  # noqa: E402

PT2PX = 96.0 / 72.0
CROP = 2
CHAR_CACHE = {}


def say(line=''):
    dbm.say(line)


def flush(title):
    dbm.flush(title)


def chars_of(pdf_path, page_index):
    """Visible glyph origins (pt, top-left page space): list of (ox, oy, ch)."""
    key = (pdf_path, page_index)
    if key in CHAR_CACHE:
        return CHAR_CACHE[key]
    doc = rp.pymupdf.open(pdf_path)
    raw = doc[page_index].get_text('rawdict')
    doc.close()
    out = []
    for block in raw['blocks']:
        for line in block.get('lines', []):
            for span in line.get('spans', []):
                for ch in span.get('chars', []):
                    if not ch['c'].strip():
                        continue
                    ox, oy = ch['origin']
                    out.append((float(ox), float(oy), ch['c']))
    CHAR_CACHE[key] = out
    return out


def window_origins(chars, x0, x1, y, tol=0.6):
    """Origins whose x lies in [x0, x1] on the baseline y, sorted by x (visual order)."""
    return sorted(ox for ox, oy, _ in chars if abs(oy - y) < tol and x0 <= ox <= x1)


def median_abs(values):
    return float(np.median(np.abs(values))) if len(values) else float('nan')


def summarize(name, values, unit='pt', thr=0.05):
    if not len(values):
        say(f'{name}: n=0')
        return
    v = np.asarray(values, dtype=np.float64)
    a = np.abs(v)
    say(f'{name}: n={v.size} median|d|={np.median(a):.4f}{unit} p95={np.percentile(a, 95):.4f}{unit} '
        f'max|d|={a.max():.4f}{unit} >{thr}{unit}: {int(np.sum(a > thr))} signed-median={np.median(v):+.4f}')


def gray_arr(path):
    return np.asarray(Image.open(path).convert('L'), dtype=np.float64) / 255.0


def png_dark(path):
    """Flutter PNG as darkness (0 = paper, 1 = full ink), same as rp.darkness of gray."""
    return rp.darkness(np.asarray(Image.open(path).convert('L'), dtype=np.float64))


def sub_fit_band(gp, gv, y0, y1, x0, x1, span=1.0, step=0.125, pad=3):
    """Best sub-pixel (dy, dx) of gv onto gp inside one band; returns (rmse, dy, dx)."""
    H, W = gp.shape
    Y0, Y1 = max(y0 - pad, 0), min(y1 + pad, H)
    X0, X1 = max(x0 - pad, 0), min(x1 + pad, W)
    ref = gp[y0:y1, x0:x1]
    mov = gv[Y0:Y1, X0:X1]
    best = None
    for dy in np.arange(-span, span + 1e-9, step):
        for dx in np.arange(-span, span + 1e-9, step):
            cand = rp.sample_shifted(mov, dy, dx)[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0]
            v = rp.rmse(ref, cand)
            if best is None or v < best[0]:
                best = (v, float(dy), float(dx))
    return best


def aligned_gray(gv, bands, fits):
    """Apply per-band sub-pixel shifts (first claim wins). Diagnostic oracle only."""
    H, W = gv.shape
    out = gv.copy()
    claimed = np.zeros((H, W), bool)
    for b, (_, dy, dx) in zip(bands, fits):
        y0, y1, x0, x1 = b['y0'], b['y1'], b['x0'], b['x1']
        sl = (slice(y0, y1), slice(x0, x1))
        if claimed[sl].any():
            continue
        Y0, Y1 = max(y0 - 3, 0), min(y1 + 3, H)
        X0, X1 = max(x0 - 3, 0), min(x1 + 3, W)
        mov = gv[Y0:Y1, X0:X1]
        cand = rp.sample_shifted(mov, dy, dx)[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0]
        out[sl] = cand
        claimed[sl] = True
    return out


def sse_shares(ref, mov):
    core = (ref > 0.5) | (mov > 0.5)
    edge = ((ref > 0.05) | (mov > 0.05)) & ~core
    bg = ~(core | edge)
    d = (ref - mov) ** 2
    total = d.sum() if d.sum() > 0 else 1.0
    return (d[core].sum() / total, d[edge].sum() / total, d[bg].sum() / total)


# ---------------------------------------------------------------- C0 calibration
def part_c0(bp, man):
    say('== C0 checker calibration: PDF origin read-back on hx ladder (known x, baseline 30pt)')
    worst = {}
    for it in man.get('hx', []):
        chars = chars_of(it['pdf'], 0)
        exp = it['x'] * 0.75
        ys = [oy for _, oy, _ in chars]
        y = float(np.median(ys)) if ys else float('nan')
        origins = window_origins(chars, exp - 0.5, exp + 300, y)
        err = origins[0] - exp if origins else float('nan')
        key = it['text']
        worst.setdefault(key, []).append((err, y))
    for text, vals in worst.items():
        errs = [e for e, _ in vals if not math.isnan(e)]
        ys = sorted({round(y, 3) for _, y in vals})
        say(f'C0 {text!r}: n={len(vals)} max|x err|={max(abs(e) for e in errs):.5f}pt '
            f'baseline_y={ys}')


# ---------------------------------------------------------------- C1 controlled ladder2
def part_c1(bp, man, tmp):
    say('== C1 controlled ladder2 (NotoNaskh 10.5/1.5, f=0): PDF vs Flutter (positions only)')
    say('C1 word = window origin error of the leftmost glyph; glyph = PDF origins vs Flutter lefts')
    left_pt = 20 * 0.75
    total_words, total_glyph_pairs, glyph_err = 0, 0, []
    for it in man.get('ladder2', []):
        chars = chars_of(it['pdf'], 0)
        ys = [oy for _, oy, _ in chars]
        y = float(np.median(ys))
        word_err, g_err, matched, mismatched = [], [], 0, 0
        for w in it['words']:
            x = left_pt + w['x']
            cand = window_origins(chars, x - 0.5, x + w['adv'] + 0.5, y)
            total_words += 1
            if not cand:
                word_err.append(float('nan'))
                continue
            word_err.append(cand[0] - x)
            gl = w['gl']
            if len(cand) == len(gl):
                matched += 1
                pairs = [(c - (x + g)) for c, g in zip(cand, gl)]
                g_err.extend(pairs)
                glyph_err.extend(pairs)
                total_glyph_pairs += len(pairs)
            else:
                mismatched += 1
        we = [e for e in word_err if not math.isnan(e)]
        ge = np.asarray(g_err) if g_err else np.zeros(0)
        gmax = float(np.max(np.abs(ge))) if ge.size else float('nan')
        gmed = float(np.median(np.abs(ge))) if ge.size else float('nan')
        say(f"C1 {it['text']!r}: words={len(it['words'])} word max|err|={max(abs(e) for e in we):.4f}pt "
            f'glyph-words matched={matched} count-mismatch={mismatched} '
            f'glyph median|err|={gmed:.4f}pt max|err|={gmax:.4f}pt')
    if glyph_err:
        ge = np.abs(np.asarray(glyph_err))
        say(f'C1 all ladder2 glyph pairs: n={ge.size} median={np.median(ge):.4f}pt '
            f'max={ge.max():.4f}pt >0.1pt={int(np.sum(ge > 0.1))}')
    say(f'C1 words checked={total_words} glyph pairs={total_glyph_pairs}')

    say('C1 image: Flutter vs Poppler on ladder2 (rmse0 | geometric oracle dy,dx -> rmse | tone floor | ink fl/pop)')
    for it in man.get('ladder2', []):
        fl = png_dark(it['png'])
        pp = rp.darkness(dbm.poppler_gray(it['pdf'], 0, tmp))
        r0 = rp.rmse(pp, fl)
        fit = rp.subpixel_fit(pp, fl, span=1.0, step=0.125)
        hist = rp.hist_match_rmse(pp, fl)
        say(f"C1 img {it['text']!r}: {r0:.4f} | {fit[0]:.4f} dx={fit[1]:+.3f} dy={fit[2]:+.3f} | "
            f'{hist:.4f} | ink {fl.sum() / max(pp.sum(), 1e-9):.3f}')


# ---------------------------------------------------------------- C2 fixture word origins
def fixture_rows(art):
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    vec_pdf = os.path.join(art, 'vector.pdf')
    rows = []
    missed = 0
    for pi, page in enumerate(geo['pages']):
        chars = chars_of(vec_pdf, pi)
        run_count = {}
        for w in page['words']:
            run_count[w.get('run')] = run_count.get(w.get('run'), 0) + 1
        for w in page['words']:
            if not w['t'].strip():
                continue
            x, adv, y = w['x'], w['adv'], w['y']
            cand = window_origins(chars, x - 0.5, x + adv + 0.5, y)
            if not cand:
                missed += 1
                continue
            pv = w.get('pv', -1.0)
            rx = w.get('rx')
            prev_left = (rx + pv) if (rx is not None and pv is not None and pv >= 0) else None
            rows.append({
                'page': pi + 1, 't': w['t'], 'rtl': bool(w['rtl']), 'run': w.get('run'),
                'y': y, 'x': x, 'font': w['font'], 'size': w['size'], 'lh': w['lh'],
                'bold': bool(w['bold']), 'italic': bool(w['italic']),
                'nrun': run_count.get(w.get('run'), 1), 'pdf_left': cand[0],
                'd_can': cand[0] - x,
                'd_pv': (cand[0] - prev_left) if prev_left is not None else None,
                'd_pc': (prev_left - x) if prev_left is not None else None,
            })
    return rows, missed


def part_c2(art):
    rows, missed = fixture_rows(art)
    say('== C2 fixture word origins (window-matched). d_can = PDF - canonical; d_pv = PDF - Preview run paragraph')
    say(f'C2 words checked={len(rows)} PDF-not-found={missed}')
    summarize('C2 d_can (PDF vs canonical word.x)', [r['d_can'] for r in rows])
    pv_rows = [r for r in rows if r['d_pv'] is not None]
    say(f'C2 Preview-located words={len(pv_rows)} of {len(rows)}')
    summarize('C2 d_pv (PDF vs Preview paragraph)', [r['d_pv'] for r in pv_rows])
    summarize('C2 d_pc (Preview paragraph vs canonical)', [r['d_pc'] for r in pv_rows])
    for label, flag in (('rtl', True), ('ltr', False)):
        sub = [r['d_pv'] for r in pv_rows if r['rtl'] == flag]
        summarize(f'C2 d_pv {label}', sub)
    bins = {'1 word': lambda n: n == 1, '2-3 words': lambda n: 2 <= n <= 3, '4+ words': lambda n: n >= 4}
    for name, cond in bins.items():
        sub = [r['d_pv'] for r in pv_rows if cond(r['nrun'])]
        summarize(f'C2 d_pv runs with {name}', sub)
    worst = sorted(pv_rows, key=lambda r: -abs(r['d_pv']))[:10]
    say('C2 largest |d_pv| words (page, text, rtl, run words, font size lh, d_pv pt, d_can pt):')
    for r in worst:
        say(f"C2   p{r['page']} {r['t'][:14]!r} rtl={int(r['rtl'])} n={r['nrun']} {r['font'][:6]} "
            f"s{r['size']:.1f} lh{r['lh']} d_pv={r['d_pv']:+.3f} d_can={r['d_can']:+.3f}")
    return rows


# ---------------------------------------------------------------- C3 fixture per-glyph check
def part_c3(art):
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    vec_pdf = os.path.join(art, 'vector.pdf')
    diffs, matched, mismatched, worst = [], 0, 0, []
    for pi, page in enumerate(geo['pages']):
        chars = chars_of(vec_pdf, pi)
        for w in page['words']:
            gl = w.get('gl') or []
            if not w['t'].strip() or not gl:
                continue
            x, adv, y = w['x'], w['adv'], w['y']
            cand = window_origins(chars, x - 0.5, x + adv + 0.5, y)
            if len(cand) != len(gl):
                mismatched += 1
                continue
            matched += 1
            d = np.asarray(cand) - (x + np.asarray(gl))
            diffs.extend(np.abs(d).tolist())
            worst.append((float(np.abs(d).max()), pi + 1, w['t'][:14], bool(w['rtl'])))
    say('== C3 fixture per-glyph (Flutter word-level lefts vs PDF origins, window-matched)')
    say(f'C3 words matched={matched} count-mismatch={mismatched}')
    if diffs:
        g = np.asarray(diffs)
        say(f'C3 glyphs={g.size} median={np.median(g):.4f}pt p95={np.percentile(g, 95):.4f}pt '
            f'max={g.max():.4f}pt >0.1pt={int(np.sum(g > 0.1))}')
    worst.sort(reverse=True)
    for mx, p, t, rtl in worst[:6]:
        say(f'C3   worst max={mx:.3f}pt p{p} {t!r} rtl={int(rtl)}')


# ---------------------------------------------------------------- C4 decomposition per page
def part_c4(art):
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    pages_n = int(manifest['pageCount'])
    with tempfile.TemporaryDirectory() as tmp:
        prefix = os.path.join(tmp, 'vec')
        subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix], check=True)
        rendered = sorted(glob.glob(prefix + '-*.png'),
                          key=lambda p: int(re.search(r'-(\d+)\.png$', p).group(1)))
        say('== C4 fixture decomposition per page (darkness; diagnostic oracles, not corrections)')
        say('C4 orig = as-is; geo = per-run sub-pixel oracle; tone = histogram match of vector to preview;'
            ' geo+tone = both. SSE shares core|edge|bg for orig and geo.')
        for index in range(pages_n):
            pdark = rp.darkness(rp.gray_of(np.asarray(
                Image.open(os.path.join(art, f'preview_page_{index + 1}.png')).convert('RGB'), dtype=np.float64)))
            vdark = rp.darkness(rp.gray_of(np.asarray(
                Image.open(rendered[index]).convert('RGB'), dtype=np.float64)))
            gp = pdark[CROP:-CROP, CROP:-CROP]
            gv = vdark[CROP:-CROP, CROP:-CROP]
            H, W = gp.shape
            bands = dbm.bands_of(geo['pages'][index]['words'], H, W, 'run')
            fits = [sub_fit_band(gp, gv, b['y0'], b['y1'], b['x0'], b['x1']) for b in bands]
            ga = aligned_gray(gv, bands, fits)
            tone = rp.hist_match_rmse(gp, gv)
            tone_geo = rp.hist_match_rmse(gp, ga)
            orig = rp.rmse(gp, gv)
            geo_r = rp.rmse(gp, ga)
            sh_o = sse_shares(gp, gv)
            sh_g = sse_shares(gp, ga)
            say(f'C4 p{index + 1}: orig={orig:.4f} geo={geo_r:.4f} tone={tone:.4f} geo+tone={tone_geo:.4f} '
                f'| SSE core/edge/bg orig={sh_o[0]:.2f}/{sh_o[1]:.2f}/{sh_o[2]:.2f} '
                f'geo={sh_g[0]:.2f}/{sh_g[1]:.2f}/{sh_g[2]:.2f} | runs={len(bands)}')
            CHAR_CACHE.setdefault('c4_fits', {})[index] = (bands, fits)


# ---------------------------------------------------------------- C5 composition classes
DIGITS = set('0123456789٠١٢٣٤٥٦٧٨٩')
PUNCT = set('()[]{}.,:;/-!?؟،؛«»"\'')


def is_arabic(ch):
    return '\u0600' <= ch <= '\u06ff'


def is_latin(ch):
    return ('a' <= ch.lower() <= 'z')


def part_c5(art, rows):
    say('== C5 fixture composition: per-run sub-pixel dx/dy vs Preview-vs-PDF word offset (run-level)')
    if 'c4_fits' not in CHAR_CACHE:
        say('C5 skipped: C4 fits unavailable')
        return
    per_run_dpv = {}
    for r in rows:
        if r['d_pv'] is None:
            continue
        per_run_dpv.setdefault((r['page'], r['run']), []).append(r['d_pv'])
    recs = []
    for index, (bands, fits) in CHAR_CACHE['c4_fits'].items():
        for b, (rmse_v, dy, dx) in zip(bands, fits):
            g0 = b['group'][0]
            text = ' '.join(w['t'] for w in b['group'])
            key = (index + 1, g0.get('run'))
            dpv = per_run_dpv.get(key)
            recs.append({
                'rtl': bool(g0['rtl']),
                'digits': any(ch in DIGITS for ch in text),
                'punct': any(ch in PUNCT for ch in text),
                'mixed': any(is_arabic(ch) for ch in text) and any(is_latin(ch) for ch in text),
                'nw': len(b['group']),
                'multirun': sum(1 for c in bands if abs(c['yfull'] - b['yfull']) < 0.01) > 1,
                'italic': bool(g0['italic']), 'bold': bool(g0['bold']),
                'dx': dx, 'dy': dy, 'res': rmse_v,
                'dpv_px': (float(np.median(dpv)) * PT2PX) if dpv else None,
            })

    def cls(name, pred):
        sub = [r for r in recs if pred(r)]
        if not sub:
            say(f'C5 {name}: n=0')
            return
        dx = np.asarray([r['dx'] for r in sub])
        dy = np.asarray([r['dy'] for r in sub])
        res = np.asarray([r['res'] for r in sub])
        say(f'C5 {name}: n={len(sub)} median dx={np.median(dx):+.3f} dy={np.median(dy):+.3f} '
            f'res={np.median(res):.4f} p90res={np.percentile(res, 90):.4f}')

    cls('all runs', lambda r: True)
    cls('rtl', lambda r: r['rtl'])
    cls('ltr', lambda r: not r['rtl'])
    cls('rtl digits', lambda r: r['rtl'] and r['digits'])
    cls('rtl punct', lambda r: r['rtl'] and r['punct'])
    cls('mixed script', lambda r: r['mixed'])
    cls('1 word', lambda r: r['nw'] == 1)
    cls('2-3 words', lambda r: 2 <= r['nw'] <= 3)
    cls('4+ words', lambda r: r['nw'] >= 4)
    cls('line with >1 run', lambda r: r['multirun'])
    cls('single run on line', lambda r: not r['multirun'])
    cls('italic', lambda r: r['italic'])
    cls('upright', lambda r: not r['italic'])
    cls('bold', lambda r: r['bold'])

    pairs = [(r['dpv_px'], r['dx']) for r in recs if r['dpv_px'] is not None]
    if len(pairs) >= 3:
        p = np.asarray(pairs)
        corr = float(np.corrcoef(p[:, 0], p[:, 1])[0, 1]) if np.std(p[:, 0]) > 0 and np.std(p[:, 1]) > 0 else float('nan')
        resid = np.abs(p[:, 1] - p[:, 0])
        say(f'C5 runs with Preview-vs-PDF offset: n={len(pairs)} corr(dx_image, d_pv_px)={corr:+.3f} '
            f'median|dx-d_pv|={np.median(resid):.3f}px  median|dx|={np.median(np.abs(p[:, 1])):.3f}px '
            f'median|d_pv|={np.median(np.abs(p[:, 0])):.3f}px')
    else:
        say('C5 runs with Preview-vs-PDF offset: n<3')


# ---------------------------------------------------------------- C6 italic
def part_c6(bp, man, tmp):
    say('== C6 italic: Flutter synthetic oblique vs upright Flutter, same PDF (f=0)')
    say('C6 cols: rmse0 | geo(dx,dy)->rmse | tone | ink ratio vs Poppler')
    by = {(e['tag'], e['script']): e for e in man['sweep']}
    done = 0
    for (tag, script), e in sorted(by.items()):
        if not re.search(r'_[br]i_lh', tag):
            continue
        up = by.get((re.sub(r'_([br])i_lh', r'_\1n_lh', tag), script))
        if up is None:
            continue
        pp = rp.darkness(dbm.poppler_gray(e['pdf'], 0, tmp))
        cols = []
        for ent in (up, e):
            fl = png_dark(ent['png'][0])
            r0 = rp.rmse(pp, fl)
            fit = rp.subpixel_fit(pp, fl, span=1.0, step=0.125)
            tone = rp.hist_match_rmse(pp, fl)
            ink = fl.sum() / max(pp.sum(), 1e-9)
            cols.append(f'{r0:.4f} ({fit[1]:+.3f},{fit[2]:+.3f})->{fit[0]:.4f} {tone:.4f} {ink:.3f}')
        say(f'C6 {tag} {script} | upright {cols[0]} | italic {cols[1]}')
        done += 1
    say(f'C6 pairs compared={done}')


# ---------------------------------------------------------------- C7 anti-aliasing / rasterizer
def part_c7(bp, man, tmp):
    say('== C7 AA / rasterizer: upright lat and ar at f=0; Poppler vs MuPDF and Flutter vs Poppler')
    say('C7 cols: rmse0 | geo(dy,dx)->rmse | tone | ink ratio')
    pm_geo, pm_tone, fp_geo, fp_tone, fp_ink, fp_r0, ar_geo, ar_r0 = [], [], [], [], [], [], [], []
    for e in man['sweep']:
        if '_n_lh' not in e['tag'] or e['script'] != 'lat':
            continue
        pdf = e['pdf']
        pp = rp.darkness(dbm.poppler_gray(pdf, 0, tmp))
        doc = rp.pymupdf.open(pdf)
        mu = rp.darkness(dbm.mupdf_gray(doc, 0))
        doc.close()
        fl = png_dark(e['png'][0])
        pm = rp.subpixel_fit(pp, mu, span=1.0, step=0.125)
        pm_geo.append(pm[0])  # poppler vs mupdf after geometric oracle
        pm_tone.append(rp.hist_match_rmse(pp, mu))
        fp = rp.subpixel_fit(pp, fl, span=1.0, step=0.125)
        fp_geo.append(fp[0])
        fp_tone.append(rp.hist_match_rmse(pp, fl))
        fp_ink.append(fl.sum() / max(pp.sum(), 1e-9))
        fp_r0.append(rp.rmse(pp, fl))
    for e in man['sweep']:
        if '_n_lh' not in e['tag'] or e['script'] != 'ar':
            continue
        pp = rp.darkness(dbm.poppler_gray(e['pdf'], 0, tmp))
        fl = png_dark(e['png'][0])
        ar_r0.append(rp.rmse(pp, fl))
        ar_geo.append(rp.subpixel_fit(pp, fl, span=1.0, step=0.125)[0])
    if pm_geo:
        say(f'C7 Latin upright n={len(pm_geo)} medians: poppler-vs-mupdf rmse0 n/a, geo={np.median(pm_geo):.4f} '
            f'tone={np.median(pm_tone):.4f} | flutter-vs-poppler rmse0={np.median(fp_r0):.4f} '
            f'geo={np.median(fp_geo):.4f} tone={np.median(fp_tone):.4f} ink={np.median(fp_ink):.3f} '
            f'(min {np.min(fp_ink):.3f} max {np.max(fp_ink):.3f})')
    if ar_r0:
        say(f'C7 Arabic upright n={len(ar_r0)} medians: flutter-vs-poppler rmse0={np.median(ar_r0):.4f} '
            f'geo={np.median(ar_geo):.4f}')


def main(art, bp):
    man = json.load(open(os.path.join(bp, 'manifest.json'), encoding='utf-8'))
    with tempfile.TemporaryDirectory() as tmp:
        for name, fn, args in (
            ('C0', part_c0, (bp, man)),
            ('C1', part_c1, (bp, man, tmp)),
        ):
            try:
                fn(*args)
            except Exception:  # noqa: BLE001
                say(f'{name} FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        flush('C6-COMP-A')
        rows = []
        try:
            rows = part_c2(art)
        except Exception:  # noqa: BLE001
            say('C2 FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        try:
            part_c3(art)
        except Exception:  # noqa: BLE001
            say('C3 FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        flush('C6-COMP-B')
        try:
            part_c4(art)
        except Exception:  # noqa: BLE001
            say('C4 FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        try:
            part_c5(art, rows)
        except Exception:  # noqa: BLE001
            say('C5 FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        flush('C6-COMP-C')
        for name, fn, args in (
            ('C6', part_c6, (bp, man, tmp)),
            ('C7', part_c7, (bp, man, tmp)),
        ):
            try:
                fn(*args)
            except Exception:  # noqa: BLE001
                say(f'{name} FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
        flush('C6-COMP-D')


if __name__ == '__main__':
    art_dir = sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'
    main(art_dir, os.path.join(art_dir, 'bprobe'))
    sys.exit(0)
