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
def line_bands(words, H, W):
    lines = {}
    for w in words:
        lines.setdefault(round(w['y'], 2), []).append(w)
    rows = []
    for key, group in sorted(lines.items()):
        size = max(w['size'] for w in group)
        x0 = int(math.floor(min(w['x'] for w in group) * PT2PX)) - CROP - 2
        x1 = int(math.ceil(max(w['x'] + w['adv'] for w in group) * PT2PX)) - CROP + 2
        yc = key * PT2PX - CROP
        y0 = int(math.floor(yc - TEXT_UP * size * PT2PX))
        y1 = int(math.ceil(yc + TEXT_DOWN * size * PT2PX))
        x0, x1 = max(x0, M), min(x1, W - M)
        y0, y1 = max(y0, M), min(y1, H - M)
        if y1 - y0 < 8 or x1 - x0 < 8:
            continue
        rows.append({'key': key, 'group': group, 'size': size, 'x0': x0, 'x1': x1,
                     'y0': y0, 'y1': y1, 'yfull': key * PT2PX})
    return rows


def part_c(art, deltas, tmp):
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    pages_n = int(manifest['pageCount'])
    prefix = os.path.join(tmp, 'vec')
    subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix], check=True)
    rendered = sorted(glob.glob(prefix + '-*.png'))
    say('== C: fixture validation. Fb_obs = floor(y) - int_dy; Fb_pred = floor(y) + round(frac+d).')
    say('C line: p y frac lh font size bold ital scr | int_dy_obs dy_pred | ok')
    total_pred = total_ok = 0
    for index in range(pages_n):
        preview = load_rgb01(os.path.join(art, f'preview_page_{index + 1}.png'))
        vec = load_rgb01(rendered[index])
        pa = preview[CROP:-CROP, CROP:-CROP]
        va = vec[CROP:-CROP, CROP:-CROP]
        H, W = pa.shape[:2]
        gp, gv = pa.mean(axis=2), va.mean(axis=2)
        page_words = geo['pages'][index]['words']
        bands = line_bands(page_words, H, W)
        base_rmse = rp.rmse(pa, va)
        oracle = va.copy()
        model = va.copy()
        claimed_o = np.zeros((H, W), bool)
        claimed_m = np.zeros((H, W), bool)
        n_pred = n_ok = 0
        mismatches = []
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
            family = g0['font']
            tag = tag_of(family, g0['size'], g0['bold'], g0['italic'], g0['lh'] if g0['lh'] is not None else -1)
            floor_y = int(math.floor(b['yfull']))
            frac = b['yfull'] % 1.0
            mixed = len(set((w['font'], w['size'], w['bold'], w['italic'], w.get('lh'), w['rtl']) for w in b['group'])) > 1
            d = deltas.get((tag, scr))
            # Counterfactual integer shifts (dy only, dx=0). Band pixels claimed once.
            if dy_obs is not None:
                sl = (slice(y0, y1), slice(x0, x1))
                if not claimed_o[sl].any():
                    oracle[sl] = va[y0 + dy_obs:y1 + dy_obs, x0:x1]
                    claimed_o[sl] = True
            if d is not None and not mixed:
                pred_round = round_half_up(frac + d['mid'])
                dy_pred = -pred_round
                n_pred += 1
                ok = dy_pred == dy_obs
                if ok:
                    n_ok += 1
                else:
                    mismatches.append(b)
                sl = (slice(y0, y1), slice(x0, x1))
                if not claimed_m[sl].any():
                    model[sl] = va[y0 + dy_pred:y1 + dy_pred, x0:x1]
                    claimed_m[sl] = True
                mark = 'ok' if ok else 'XX'
                pred_txt = f'{dy_pred:+d}'
            else:
                mark, pred_txt = 'na', 'na'
                sl = (slice(y0, y1), slice(x0, x1))
                if not claimed_m[sl].any():
                    model[sl] = va[y0:y1, x0:x1]
                    claimed_m[sl] = True
            say(f"C p{index + 1} y{b['yfull']:.2f} f{frac:.2f} lh{g0['lh']} {family[:6]} "
                f"s{b['size']:.1f} b{int(bool(g0['bold']))} i{int(bool(g0['italic']))} {scr}"
                f"{' mix' if mixed else ''} | {dy_obs:+d} {pred_txt} | {mark}")
        total_pred += n_pred
        total_ok += n_ok
        r_o = rp.rmse(pa, oracle)
        r_m = rp.rmse(pa, model)
        say(f'C page {index + 1}: lines={len(bands)} predicted={n_pred} agree={n_ok} '
            f'rmse_orig={base_rmse:.6f} rmse_oracle_int={r_o:.6f} rmse_model_int={r_m:.6f} '
            f'(counterfactual; not a fix)')
    say(f'C total: predicted={total_pred} agree={total_ok}')


def main(art, bp):
    manifest = json.load(open(os.path.join(bp, 'manifest.json'), encoding='utf-8'))
    deltas = {}
    try:
        deltas = part_a(bp, manifest)
    except Exception:  # noqa: BLE001 - diagnostics must not mask other parts
        say('A FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL')
    try:
        part_b(bp, manifest)
    except Exception:  # noqa: BLE001
        say('B FAILED: ' + traceback.format_exc()[-900:].replace('\n', ' | '))
    flush('C6-MODEL-B')
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
