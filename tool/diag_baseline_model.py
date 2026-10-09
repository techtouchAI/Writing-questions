#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY baseline-model analysis. Not for merge; removed in cleanup.

Inputs (written by test/visual/baseline_model_probe_test.dart and the fixture):
  build/visual_parity/bprobe/manifest.json   sweep (font x size x bold x italic x lh x script) + ladder
  build/visual_parity/bprobe/*.png / *.pdf   Flutter (pt-mode, production _paintText) and PDF (C1 mapping)
  build/visual_parity/{manifest.json,diag_geometry.json,preview_page_N.png,vector.pdf}

Parts:
  A  frac sweep per style: Flutter bottom (px) vs Poppler (pdftoppm -r 96) and MuPDF.
     Rounding model  Fb = floor(D) + round(f + delta)     (delta per style)
     Floor model     Pb = floor(D) + floor(f + delta)     (Poppler check)
  B  text ladder at a fixed style: free sub-pixel translation, tone-only floor.
  C  fixture validation: predicted vs observed integer baseline per line, and a
     counterfactual page RMSE with the observed vs model integer shifts applied.
     This is an upper-bound diagnostic. It does not change any expected image.

Sign conventions:
  rp.subpixel_fit(ref, mov): mov sampled at y+dy matches ref at y.
  Probe A/B: Flutter relative to Poppler. dy > 0 means Flutter lower.
  Fixture C: int_dy > 0 means vector (Poppler) lower than preview.
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


def say(line=''):
    LINES.append(line)


def flush(title):
    """Emit LINES as <=3500-byte ::notice chunks (GitHub caps annotations at 10 per step)."""
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
    """Ink bottom (exclusive) and top, using rows above 2% of the max row profile."""
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
    for d in np.arange(-1.0, 1.0, 0.005):
        viol = sum(1 for f, u in zip(fracs, us) if round_half_up(f + d) != u)
        if best is None or viol < best[0]:
            best = (viol, float(d))
    return best


def tag_of(family, size, bold, italic, lh):
    return f"{family}_s{round(size * 100)}_{'b' if bold else 'r'}{'i' if italic else 'n'}_lh{round(lh * 100)}"


# ---------------------------------------------------------------- A: sweep
def part_a(bp, manifest):
    fracs = manifest['fracs']
    deltas = {}
    say('== A: frac sweep. u = bottom - floor(40+f). Rounding model u=round(f+d); Poppler check floor(f+d).')
    say('A key: tag|script  u-seq (f=0..0.9)  rnd-delta[lo,hi)  consistent?  mu-delta  pop-floor[lo,hi)  ink(fl/mu)')
    with tempfile.TemporaryDirectory() as tmp:
        for entry in manifest['sweep']:
            pdf = entry['pdf']
            doc = rp.pymupdf.open(pdf)
            fl_us, mu_us, pp_us, ratios = [], [], [], []
            for i in range(len(fracs)):
                fl = load_gray(entry['png'][i])
                pp = poppler_gray(pdf, i, tmp)
                mu = mupdf_gray(doc, i)
                fb, _ = bottom_of(fl)
                pb, _ = bottom_of(pp)
                mb, _ = bottom_of(mu)
                base = 40
                fl_us.append(fb - base)
                pp_us.append(pb - base)
                mu_us.append(mb - base)
                ratios.append(ink(fl) / max(ink(mu), 1e-9))
            fr = fracs
            lo, hi = delta_interval_round(fr, fl_us)
            ok = lo < hi
            best = None if ok else best_delta_round(fr, fl_us)
            mlo, mhi = delta_interval_round(fr, mu_us)
            plo, phi = delta_interval_floor(fr, pp_us)
            key = f"{entry['tag']}|{entry['script']}"
            seq = ''.join(str(u) for u in fl_us)
            if ok:
                dstr = f'[{lo:+.3f},{hi:+.3f}) ok'
                mid = (lo + hi) / 2
            else:
                dstr = f'NO-CONST viol={best[0]} d*={best[1]:+.3f}'
                mid = best[1]
            mstr = f'[{mlo:+.3f},{mhi:+.3f})' if mlo < mhi else 'NO-CONST'
            pstr = f'[{plo:+.3f},{phi:+.3f})' if plo < phi else 'NO-CONST'
            say(f"A {key} u={seq} rnd {dstr} | mu {mstr} | pop {pstr} | ink {np.mean(ratios):.3f}")
            deltas[(entry['tag'], entry['script'])] = {
                'mid': mid, 'ok': ok, 'lo': lo, 'hi': hi, 'best': best, 'viol_free': best is not None,
            }
            doc.close()
    ok_n = sum(1 for v in deltas.values() if v['ok'])
    say(f'A summary: {ok_n}/{len(deltas)} style-script combos admit a constant rounding delta.')
    return deltas


# ---------------------------------------------------------------- B: ladder
def part_b(bp, manifest):
    lad = manifest['ladder']
    say(f"== B: ladder {lad['family']} {lad['size']}pt lh{lad['lh']} at f=0.")
    say('B i text | Fb Pb | rmse0 | sub(dx,dy,rmse) | hist-floor | ink fl/pop | dy>0 => Flutter lower')
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


# ---------------------------------------------------------------- C: fixture
def run_bands(words, H, W):
    """One band per (baseline, run): Preview paints each run at its own TextPainter."""
    runs = {}
    for w in words:
        runs.setdefault((round(w['y'], 2), w.get('run')), []).append(w)
    rows = []
    for key, group in sorted(runs.items(), key=lambda kv: (kv[0][0], str(kv[0][1]))):
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


def part_c(art, deltas, tmp):
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    pages_n = int(manifest['pageCount'])
    prefix = os.path.join(tmp, 'vec')
    subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix], check=True)
    rendered = sorted(glob.glob(prefix + '-*.png'))
    say('== C: fixture validation, per run. Fb_obs = floor(y) - int_dy; Fb_pred = floor(y) + round(frac+d).')
    say('C run: p y frac lh font size b i scr | int_dy_obs | pred_same pred_latd | ok_same ok_latd')
    say('C pred_latd uses the Latin (flat-bottom lI) delta for the same style: script-independent baseline.')
    totals = {'runs': 0, 'pred': 0, 'ok_same': 0, 'ok_lat': 0, 'ital': 0, 'ital_ok_lat': 0}
    for index in range(pages_n):
        preview = load_rgb01(os.path.join(art, f'preview_page_{index + 1}.png'))
        vec = load_rgb01(rendered[index])
        pa = preview[CROP:-CROP, CROP:-CROP]
        va = vec[CROP:-CROP, CROP:-CROP]
        H, W = pa.shape[:2]
        gp, gv = pa.mean(axis=2), va.mean(axis=2)
        bands = run_bands(geo['pages'][index]['words'], H, W)
        base_rmse = rp.rmse(pa, va)
        oracle = va.copy()
        model = va.copy()
        claimed_o = np.zeros((H, W), bool)
        claimed_m = np.zeros((H, W), bool)
        page = {'runs': 0, 'pred': 0, 'ok_same': 0, 'ok_lat': 0, 'ital': 0, 'ital_ok_lat': 0}
        for b in bands:
            y0, y1, x0, x1 = b['y0'], b['y1'], b['x0'], b['x1']
            ref = gp[y0:y1, x0:x1]
            best = None
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    v = rp.rmse(ref, gv[y0 + dy:y1 + dy, x0 + dx:x1 + dx])
                    if best is None or v < best[0]:
                        best = (v, dx, dy)
            dy_obs = best[2]
            g0 = b['group'][0]
            scr = 'ar' if g0['rtl'] else 'lat'
            tag = tag_of(g0['font'], g0['size'], g0['bold'], g0['italic'], g0['lh'])
            frac = b['yfull'] % 1.0
            sl = (slice(y0, y1), slice(x0, x1))
            if not claimed_o[sl].any():
                oracle[sl] = va[y0 + dy_obs:y1 + dy_obs, x0:x1]
                claimed_o[sl] = True
            d_same = deltas.get((tag, scr))
            d_lat = deltas.get((tag, 'lat'))
            page['runs'] += 1
            pred_same = pred_lat = 'na'
            ok_same = ok_lat = 'na'
            if d_lat is not None:
                pred_lat_v = -round_half_up(frac + d_lat['mid'])
                pred_lat = f'{pred_lat_v:+d}'
                ok_lat = pred_lat_v == dy_obs
                page['pred'] += 1
                page['ok_lat'] += int(ok_lat)
                if g0['italic']:
                    page['ital'] += 1
                    page['ital_ok_lat'] += int(ok_lat)
                if not claimed_m[sl].any():
                    model[sl] = va[y0 + pred_lat_v:y1 + pred_lat_v, x0:x1]
                    claimed_m[sl] = True
                ok_lat = 'ok' if ok_lat else 'XX'
            if d_same is not None:
                pred_same_v = -round_half_up(frac + d_same['mid'])
                pred_same = f'{pred_same_v:+d}'
                ok_same = pred_same_v == dy_obs
                page['ok_same'] += int(ok_same)
                ok_same = 'ok' if ok_same else 'XX'
            if not claimed_m[sl].any():
                model[sl] = va[y0:y1, x0:x1]
                claimed_m[sl] = True
            ital = ' i' if g0['italic'] else ''
            say(f"C p{index + 1} y{b['yfull']:.2f} f{frac:.2f} lh{g0['lh']} {g0['font'][:6]} "
                f"s{b['size']:.1f} b{int(bool(g0['bold']))}{ital} {scr} | {dy_obs:+d} | "
                f"{pred_same} {pred_lat} | {ok_same} {ok_lat}")
        for k in totals:
            totals[k] += page[k]
        r_o = rp.rmse(pa, oracle)
        r_m = rp.rmse(pa, model)
        say(f"C page {index + 1}: runs={page['runs']} predicted={page['pred']} "
            f"agree_latd={page['ok_lat']} agree_same={page['ok_same']} italic={page['ital']}"
            f"(agree {page['ital_ok_lat']}) rmse_orig={base_rmse:.6f} "
            f"rmse_oracle_int={r_o:.6f} rmse_model_latd_int={r_m:.6f} (counterfactual, not a fix)")
    say(f"C total: runs={totals['runs']} predicted={totals['pred']} agree_latd={totals['ok_lat']} "
        f"agree_same={totals['ok_same']} italic_agree={totals['ital_ok_lat']}/{totals['ital']}")


def round_half_up_wrap(x):
    return x - math.floor(x + 0.5)


# ---------------------------------------------------------------- D: mechanism
def part_d(manifest):
    """Does the style delta follow from Flutter line metrics (pt-space rounding)?"""
    say('== D: delta (Latin, mod 1) vs metric-rounding candidates. Candidates are device-px offsets.')
    say('D style | d_lat | base_px frac | cand pt-round pt-floor pt-ceil px-round | best')
    for entry in manifest['sweep']:
        if entry['script'] != 'lat':
            continue
        d = None
        # Latin delta per style, from part A (computed earlier, stored in manifest order).
        d = DELTA_CACHE.get((entry['tag'], 'lat'))
        if d is None:
            continue
        m = entry['metrics']
        base_pt = m['baseline_pt']
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
        say(f"D {entry['tag']} {dmod:+.3f} | {base_px:.3f} {base_px % 1:.3f} | "
            + ' '.join(f"{k}={round_half_up_wrap(v):+.3f}" for k, v in cands.items())
            + f" | {best} err={errs[best]:.3f}")


DELTA_CACHE = {}


def main(art, bp):
    manifest = json.load(open(os.path.join(bp, 'manifest.json'), encoding='utf-8'))
    deltas = {}
    try:
        deltas = part_a(bp, manifest)
        DELTA_CACHE.update(deltas)
    except Exception:  # noqa: BLE001 - diagnostics must not mask other parts
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
        with tempfile.TemporaryDirectory() as tmp:
            part_c(art, deltas, tmp)
    except Exception:  # noqa: BLE001
        say('C FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-C')


if __name__ == '__main__':
    art_dir = sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'
    main(art_dir, os.path.join(art_dir, 'bprobe'))
    sys.exit(0)
