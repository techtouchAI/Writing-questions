#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY baseline-model analysis. Not for merge; removed in cleanup.

Inputs (written by test/visual/baseline_model_probe_test.dart and the fixture):
  build/visual_parity/bprobe/manifest.json   sweep (style x script) + ladder + line metrics
  build/visual_parity/bprobe/*.png, *.pdf    Flutter (pt-mode, production _paintText) and PDF
  build/visual_parity/{manifest.json,diag_geometry.json,preview_page_N.png,vector.pdf}

Parts:
  A  frac sweep per style and script: Flutter ink bottom vs Poppler (pdftoppm -r 96) and MuPDF.
     Rounding model  Fb = floor(D) + round(f + d)   (D = 40 + f, so floor(D) = 40)
     Floor model     Pb = floor(D) + floor(f + d)   (Poppler check)
  B  text ladder at a fixed style: free sub-pixel translation and tone-only floor.
  C  fixture validation per run (Preview paints per run) using the Latin delta of the same
     style (flat bottom), plus a counterfactual page RMSE with integer shifts only.
  D  mechanism check: Latin delta against metric-rounding candidates.

Sign conventions:
  rp.subpixel_fit(ref, mov): mov sampled at y+dy matches ref at y.
  Probe A/B: Flutter relative to Poppler. dy > 0 means Flutter lower.
  Fixture C: int_dy > 0 means the vector (Poppler) is lower than the preview.
"""
import glob
import json
import math
import os
import subprocess
import sys
import tempfile
import traceback

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_raster_probe as rp  # noqa: E402  (pure helpers; main is guarded)

PT2PX = 96.0 / 72.0
CROP = 2
TEXT_UP = 1.0
TEXT_DOWN = 0.35
M = 8

LINES = []
DELTA_CACHE = {}


def say(line=''):
    LINES.append(line)


def flush(title):
    """Emit LINES as <=3500-byte ::notice chunks (GitHub caps annotations per step at 10)."""
    chunk, size, part = [], 0, 1

    def emit():
        nonlocal chunk, size, part
        if not chunk:
            return
        text = '\n'.join(chunk)
        text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::notice title={title} ({part})::{text}', flush=True)
        chunk, size, part = [], 0, part + 1

    for line in LINES:
        cost = len(line.encode('utf-8')) + 1
        if size + cost > 3500 and chunk:
            emit()
        chunk.append(line)
        size += cost
    emit()
    LINES.clear()


def load_gray(path, shape=(60, 420)):
    arr = np.asarray(Image.open(path).convert('L'), dtype=np.float64)
    if arr.shape != shape:
        raise RuntimeError(f'probe image {path} is {arr.shape}, expected {shape}')
    return arr


def load_rgb01(path):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float64) / 255.0


def poppler_gray(pdf, index, tmp):
    prefix = os.path.join(tmp, f'pp_{index}')
    subprocess.run(['pdftoppm', '-r', '96', '-gray', '-png', '-f', str(index + 1),
                    '-l', str(index + 1), '-singlefile', pdf, prefix], check=True)
    return load_gray(prefix + '.png')


def mupdf_gray(doc, index):
    pix = doc[index].get_pixmap(dpi=96, colorspace=rp.pymupdf.csGRAY, alpha=False)
    return np.frombuffer(pix.samples, np.uint8).reshape(pix.h, pix.w).astype(np.float64)


def bottom_of(gray):
    """Ink bottom (exclusive) and top: rows whose profile exceeds 2% of the peak row."""
    dark = rp.darkness(gray)
    prof = dark.sum(axis=1)
    peak = prof.max()
    if peak <= 0:
        return None, None
    rows = np.where(prof > 0.02 * peak)[0]
    return int(rows[-1]) + 1, int(rows[0])


def ink(gray):
    return float(rp.darkness(gray).sum())


def round_half_up(x):
    return int(math.floor(x + 0.5))


def round_half_up_wrap(x):
    return x - math.floor(x + 0.5)


def delta_interval_round(fracs, us):
    lo, hi = -9.0, 9.0
    for f, u in zip(fracs, us):
        lo = max(lo, u - 0.5 - f)
        hi = min(hi, u + 0.5 - f)
    return lo, hi


def delta_interval_floor(fracs, us):
    lo, hi = -9.0, 9.0
    for f, u in zip(fracs, us):
        lo = max(lo, u - f)
        hi = min(hi, u + 1.0 - f)
    return lo, hi


def best_delta_round(fracs, us):
    best = None
    for d in np.arange(-1.0, 1.0, 0.002):
        viol = sum(1 for f, u in zip(fracs, us) if round_half_up(f + d) != u)
        if best is None or viol < best[0]:
            best = (viol, float(d))
    return best


def tag_of(family, size, bold, italic, lh):
    return (f"{family}_s{round(size * 100)}_{'b' if bold else 'r'}"
            f"{'i' if italic else 'n'}_lh{round(lh * 100)}")


# ---------------------------------------------------------------- A: sweep
def part_a(bp, manifest):
    deltas = {}
    say('== A: frac sweep. u = bottom - 40. Rounding model u=round(f+d); Poppler check u=floor(f+d).')
    say('A key: tag|script  rnd-delta  | MuPDF rnd | Poppler floor | ink(fl/mu)')
    with tempfile.TemporaryDirectory() as tmp:
        for entry in manifest['sweep']:
            pdf = entry['pdf']
            fr = entry['fracs']
            doc = rp.pymupdf.open(pdf)
            fl_us, mu_us, pp_us, ratios = [], [], [], []
            for i in range(len(fr)):
                fl = load_gray(entry['png'][i])
                pp = poppler_gray(pdf, i, tmp)
                mu = mupdf_gray(doc, i)
                fb, _ = bottom_of(fl)
                pb, _ = bottom_of(pp)
                mb, _ = bottom_of(mu)
                fl_us.append(fb - 40)
                pp_us.append(pb - 40)
                mu_us.append(mb - 40)
                ratios.append(ink(fl) / max(ink(mu), 1e-9))
            doc.close()
            lo, hi = delta_interval_round(fr, fl_us)
            ok = lo < hi
            if ok:
                mid = (lo + hi) / 2
                dstr = f'[{lo:+.3f},{hi:+.3f}) ok'
            else:
                best = best_delta_round(fr, fl_us)
                mid = best[1]
                dstr = f'NO-CONST viol={best[0]} d*={best[1]:+.3f}'
            mlo, mhi = delta_interval_round(fr, mu_us)
            plo, phi = delta_interval_floor(fr, pp_us)
            mstr = f'[{mlo:+.3f},{mhi:+.3f})' if mlo < mhi else 'NO-CONST'
            pstr = f'[{plo:+.3f},{phi:+.3f})' if plo < phi else 'NO-CONST'
            say(f"A {entry['tag']}|{entry['script']} n={len(fr)} rnd {dstr} | mu {mstr} | pop {pstr} "
                f"| ink {np.mean(ratios):.3f}")
            deltas[(entry['tag'], entry['script'])] = {
                'mid': mid, 'ok': ok, 'lo': lo, 'hi': hi,
                'u': ''.join(str(u) for u in fl_us)}
    ok_n = sum(1 for v in deltas.values() if v['ok'])
    say(f'A summary: {ok_n}/{len(deltas)} style-script combos admit a constant rounding delta.')
    return deltas


# ---------------------------------------------------------------- B: ladder
def part_b(bp, manifest):
    lad = manifest['ladder']
    say(f"== B: ladder {lad['family']} {lad['size']}pt lh{lad['lh']} at f=0. dy>0 => Flutter lower.")
    say('B i text | Fb Pb | rmse0 | sub(dx,dy,rmse) | hist-floor | ink fl/pop')
    with tempfile.TemporaryDirectory() as tmp:
        for item in lad['items']:
            fl = load_gray(item['png'])
            pp = poppler_gray(item['pdf'], 0, tmp)
            dfl, dpp = rp.darkness(fl), rp.darkness(pp)
            fb, _ = bottom_of(fl)
            pb, _ = bottom_of(pp)
            r0 = rp.rmse(dfl, dpp)
            sub = rp.subpixel_fit(dpp, dfl, span=1.0, step=0.125)
            hist = rp.hist_match_rmse(dpp, dfl)
            say(f"B {item['i']} {item['text']!r} rtl={int(item['rtl'])} | {fb} {pb} | "
                f"{r0:.4f} | {sub[0]:.4f} dx={sub[1]:+.3f} dy={sub[2]:+.3f} | {hist:.4f} | "
                f"{ink(fl) / max(ink(pp), 1e-9):.3f}")


# ---------------------------------------------------------------- E: horizontal origin ladder
def part_e(bp, manifest):
    """Flutter vs PDF x-offset at 1/8 px origin steps. dx > 0 => Flutter right of PDF."""
    hx = manifest.get('hx', [])
    if not hx:
        return
    say('== E: horizontal origin ladder (Flutter vs PDF at 1/8 px origin steps). dx>0 => Flutter right.')
    say('E text k x_frac | best_dx rmse_at_best rmse_at_0 | pred if floor(x*4)/4: dx=-(frac(x*4)/4)')
    with tempfile.TemporaryDirectory() as tmp:
        for item in hx:
            fl = rp.darkness(load_gray(item['png']))
            pp = rp.darkness(poppler_gray(item['pdf'], 0, tmp))
            best = None
            for dx in np.arange(-1.0, 1.0 + 1e-9, 1.0 / 32):
                v = rp.rmse(pp, rp.sample_shifted(fl, 0.0, dx))
                if best is None or v < best[0]:
                    best = (v, float(dx))
            zero = rp.rmse(pp, fl)
            x = item['x']
            frac4 = (x * 4) % 1.0 / 4.0
            say(f"E {item['text']!r} k{item['k']} x{x - math.floor(x):.3f} | {best[1]:+.3f} "
                f"{best[0]:.4f} {zero:.4f} | {-frac4:+.3f}")


# ---------------------------------------------------------------- C: fixture
def bands_of(words, H, W, by):
    """Bands per (baseline, run) when by='run'; per baseline when by='line'."""
    groups = {}
    for w in words:
        k = (round(w['y'], 2), w.get('run')) if by == 'run' else (round(w['y'], 2),)
        groups.setdefault(k, []).append(w)
    rows = []
    for key, group in sorted(groups.items(), key=lambda kv: (kv[0][0], str(kv[0][1:]))):
        size = max(w['size'] for w in group)
        x0 = int(math.floor(min(w['x'] for w in group) * PT2PX)) - CROP - 2
        x1 = int(math.ceil(max(w['x'] + w['adv'] for w in group) * PT2PX)) - CROP + 2
        yc = key[0] * PT2PX - CROP
        y0 = int(math.floor(yc - TEXT_UP * size * PT2PX))
        y1 = int(math.ceil(yc + TEXT_DOWN * size * PT2PX))
        x0, x1 = max(x0, M), min(x1, W - M)
        y0, y1 = max(y0, M), min(y1, H - M)
        if y1 - y0 < 8 or x1 - x0 < 8:
            continue
        rows.append({'group': group, 'size': size, 'x0': x0, 'x1': x1,
                     'y0': y0, 'y1': y1, 'yfull': key[0] * PT2PX})
    return rows


def obs_dy(gp, gv, b):
    y0, y1, x0, x1 = b['y0'], b['y1'], b['x0'], b['x1']
    ref = gp[y0:y1, x0:x1]
    best = None
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            v = rp.rmse(ref, gv[y0 + dy:y1 + dy, x0 + dx:x1 + dx])
            if best is None or v < best[0]:
                best = (v, dx, dy)
    return best[2]


def style_of(b):
    g0 = b['group'][0]
    scr = 'ar' if g0['rtl'] else 'lat'
    tag = tag_of(g0['font'], g0['size'], g0['bold'], g0['italic'], g0['lh'])
    return g0, scr, tag


def counterfactual(pa, va, bands, dys, deltas):
    """Apply integer shifts per band: observed (oracle) and Latin-delta predicted (model)."""
    H, W = pa.shape[:2]
    oracle, model = va.copy(), va.copy()
    co, cm = np.zeros((H, W), bool), np.zeros((H, W), bool)
    for b, dy_obs in zip(bands, dys):
        y0, y1, x0, x1 = b['y0'], b['y1'], b['x0'], b['x1']
        sl = (slice(y0, y1), slice(x0, x1))
        if not co[sl].any():
            oracle[sl] = va[y0 + dy_obs:y1 + dy_obs, x0:x1]
            co[sl] = True
        _, _, tag = style_of(b)
        d = deltas.get((tag, 'lat'))
        dy_pred = -round_half_up(b['yfull'] % 1.0 + d['mid']) if d is not None else 0
        if not cm[sl].any():
            model[sl] = va[y0 + dy_pred:y1 + dy_pred, x0:x1]
            cm[sl] = True
    return rp.rmse(pa, oracle), rp.rmse(pa, model)


def part_c(art, deltas, tmp):
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    pages_n = int(manifest['pageCount'])
    prefix = os.path.join(tmp, 'vec')
    subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix], check=True)
    rendered = sorted(glob.glob(prefix + '-*.png'))
    say('== C: fixture per run. Fb_obs = floor(y) - int_dy; Fb_pred = floor(y) + round(frac + d_lat).')
    say('C XX rows (run-level, d_lat): page y frac lh font size b i scr | int_dy_obs | pred_lat pred_same')
    keys = ['runs', 'pred', 'ok_lat', 'ok_same', 'ital', 'ital_ok', 'ar', 'ar_ok', 'lat', 'lat_ok']
    totals = {k: 0 for k in keys}
    for index in range(pages_n):
        preview = load_rgb01(os.path.join(art, f'preview_page_{index + 1}.png'))
        vec = load_rgb01(rendered[index])
        pa = preview[CROP:-CROP, CROP:-CROP]
        va = vec[CROP:-CROP, CROP:-CROP]
        H, W = pa.shape[:2]
        gp, gv = pa.mean(axis=2), va.mean(axis=2)
        words = geo['pages'][index]['words']
        run_b = bands_of(words, H, W, 'run')
        line_b = bands_of(words, H, W, 'line')
        run_dy = [obs_dy(gp, gv, b) for b in run_b]
        line_dy = [obs_dy(gp, gv, b) for b in line_b]
        page = {k: 0 for k in keys}
        for b, dy_obs in zip(run_b, run_dy):
            g0, scr, tag = style_of(b)
            frac = b['yfull'] % 1.0
            d_lat = deltas.get((tag, 'lat'))
            d_same = deltas.get((tag, scr))
            page['runs'] += 1
            page[scr] += 1
            if d_lat is None:
                continue
            page['pred'] += 1
            p_lat = -round_half_up(frac + d_lat['mid'])
            ok_lat = p_lat == dy_obs
            page['ok_lat'] += int(ok_lat)
            page[scr + '_ok'] += int(ok_lat)
            if g0['italic']:
                page['ital'] += 1
                page['ital_ok'] += int(ok_lat)
            p_same = None
            if d_same is not None:
                p_same = -round_half_up(frac + d_same['mid'])
                page['ok_same'] += int(p_same == dy_obs)
            if not ok_lat:
                say(f"C XX p{index + 1} y{b['yfull']:.2f} f{frac:.2f} lh{g0['lh']} {g0['font'][:6]} "
                    f"s{b['size']:.1f} b{int(bool(g0['bold']))} i{int(bool(g0['italic']))} {scr} | "
                    f"{dy_obs:+d} | {p_lat:+d} {'na' if p_same is None else format(p_same, '+d')}")
        for k in keys:
            totals[k] += page[k]
        base = rp.rmse(pa, va)
        run_o, run_m = counterfactual(pa, va, run_b, run_dy, deltas)
        line_o, line_m = counterfactual(pa, va, line_b, line_dy, deltas)
        say(f"C page {index + 1}: runs={page['runs']} pred={page['pred']} agree_lat={page['ok_lat']} "
            f"agree_same={page['ok_same']} ar={page['ar_ok']}/{page['ar']} "
            f"lat={page['lat_ok']}/{page['lat']} italic={page['ital_ok']}/{page['ital']}")
        say(f"C page {index + 1} RMSE orig={base:.6f} | line-bands oracle={line_o:.6f} "
            f"model={line_m:.6f} | run-bands oracle={run_o:.6f} model={run_m:.6f} "
            f"(integer shifts only; counterfactual, not a fix)")
    say(f"C total: runs={totals['runs']} pred={totals['pred']} agree_lat={totals['ok_lat']} "
        f"agree_same={totals['ok_same']} ar={totals['ar_ok']}/{totals['ar']} "
        f"lat={totals['lat_ok']}/{totals['lat']} italic={totals['ital_ok']}/{totals['ital']}")


# ---------------------------------------------------------------- D: mechanism
def part_d(manifest):
    """Latin delta (mod 1) against metric-rounding candidates (device px)."""
    say('== D: Latin delta vs candidates. cand = offset that rounding baseline metric would add.')
    say('D style | d_lat(mod1) baseline_px frac | pt-round pt-floor pt-ceil px-round | best (|err|)')
    for entry in manifest['sweep']:
        if entry['script'] != 'lat':
            continue
        d = DELTA_CACHE.get((entry['tag'], 'lat'))
        if d is None:
            continue
        base_pt = entry['metrics']['baseline_pt']
        base_px = base_pt * PT2PX
        cands = {
            'pt-round': (round(base_pt) - base_pt) * PT2PX,
            'pt-floor': (math.floor(base_pt) - base_pt) * PT2PX,
            'pt-ceil': (math.ceil(base_pt) - base_pt) * PT2PX,
            'px-round': round(base_px) - base_px,
        }
        dmod = round_half_up_wrap(d['mid'])
        errs = {k: abs(round_half_up_wrap(v - dmod)) for k, v in cands.items()}
        best = min(errs, key=errs.get)
        say(f"D {entry['tag']} {dmod:+.3f} {base_px:.3f} {base_px % 1:.3f} | "
            + ' '.join(f"{round_half_up_wrap(v):+.3f}" for v in cands.values())
            + f" | {best} {errs[best]:.3f}")


def main(art, bp):
    manifest = json.load(open(os.path.join(bp, 'manifest.json'), encoding='utf-8'))
    try:
        DELTA_CACHE.update(part_a(bp, manifest))
    except Exception:  # noqa: BLE001 - diagnostics must not mask the other parts
        say('A FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL')
    try:
        part_b(bp, manifest)
    except Exception:  # noqa: BLE001
        say('B FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-B')
    try:
        part_d(manifest)
    except Exception:  # noqa: BLE001
        say('D FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-D')
    try:
        part_e(bp, manifest)
    except Exception:  # noqa: BLE001
        say('E FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-E')
    try:
        with tempfile.TemporaryDirectory() as tmp:
            part_c(art, DELTA_CACHE, tmp)
    except Exception:  # noqa: BLE001
        say('C FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-C')


if __name__ == '__main__':
    art_dir = sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'
    main(art_dir, os.path.join(art_dir, 'bprobe'))
    sys.exit(0)
