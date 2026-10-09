#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY element-level residual: decorations and floating shapes. Not for merge.

Diagnostic only. The text/math exclusion and the per-element zones are measurement masks.
Removing them from the RMSE is NOT a fix and NOT a pass of the official gate; the official
gate (Poppler, RMSE <= 0.02 on the full page) is unchanged.

For each decoration (border / divider) and floating element of each fixture page:
  - zone: stroke ring (border / framed / shape bbox ring) or filled rect (divider), minus text
    bands and math boxes;
  - SSE and ink (Preview vs PDF) inside the zone;
  - edge positions: left/right/top/bottom ink centroids (PDF - Preview, px) from masked
    1-D profiles, and stroke thickness (ink per unit length) ratio.
Totals: page RMSE before and after excluding the union of element zones (diagnostic only).
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
import diag_composition as dc  # noqa: E402

PT2PX = 96.0 / 72.0
CROP = 2


def say(line=''):
    dbm.say(line)


def zone_mask(kind, x0, y0, x1, y1, stroke_px, H, W):
    """Boolean mask of the element's own zone in cropped px coordinates."""
    yy, xx = np.mgrid[0:H, 0:W]
    if kind == 'divider':
        r = 2.0
        inside = (xx >= x0 - r) & (xx <= x1 + r) & (yy >= y0 - r) & (yy <= y1 + r)
        return inside
    r = max(2.0, stroke_px / 2.0 + 3.0)
    outer = (xx >= x0 - r) & (xx <= x1 + r) & (yy >= y0 - r) & (yy <= y1 + r)
    inner = (xx >= x0 + r) & (xx <= x1 - r) & (yy >= y0 + r) & (yy <= y1 - r)
    return outer & ~inner


def edge_stats(gp, gv, x0, y0, x1, y1, win=4):
    """Left/right/top/bottom edge centroid offsets (vec - pre, px) and thickness ratio."""
    H, W = gp.shape
    out = {}
    rows = slice(max(int(y0) + 2, 0), min(int(y1) - 2, H))
    cols = slice(max(int(x0) + 2, 0), min(int(x1) - 2, W))
    if rows.stop - rows.start < 4 or cols.stop - cols.start < 4:
        return None

    def centroid(profile, base):
        idx = np.arange(profile.size) + base
        s = profile.sum()
        return float((profile * idx).sum() / s) if s > 1e-9 else float('nan'), float(s)

    specs = {
        'left': ('col', int(round(x0)), 1),
        'right': ('col', int(round(x1)), 1),
        'top': ('row', int(round(y0)), 1),
        'bottom': ('row', int(round(y1)), 1),
    }
    for name, (axis, c, _) in specs.items():
        if axis == 'col':
            lo, hi = max(c - win, 0), min(c + win + 1, W)
            pp = gp[rows, lo:hi].sum(axis=0)
            vv = gv[rows, lo:hi].sum(axis=0)
            base = lo
            length = rows.stop - rows.start
        else:
            lo, hi = max(c - win, 0), min(c + win + 1, H)
            pp = gp[lo:hi, cols].sum(axis=1)
            vv = gv[lo:hi, cols].sum(axis=1)
            base = lo
            length = cols.stop - cols.start
        cp, sp = centroid(pp, base)
        cv, sv = centroid(vv, base)
        out[name] = {
            'd': cv - cp if (not math.isnan(cp) and not math.isnan(cv)) else float('nan'),
            'thk_pre': sp / max(length, 1),
            'thk_vec': sv / max(length, 1),
        }
    return out


def page_elements(page):
    els = []
    for d in page.get('decorations', []):
        els.append({'src': 'deco', 'kind': d.get('kind', '?'), 'type': d.get('kind', '?'),
                    'framed': None, 'stroke': float(d.get('stroke', 0.0)), 'rot': 0.0,
                    'x': d['x'], 'y': d['y'], 'w': d['w'], 'h': d['h']})
    for f in page.get('floats', []):
        els.append({'src': 'float', 'kind': 'border', 'type': f.get('type', '?'),
                    'framed': bool(f.get('framed', False)), 'stroke': float(f.get('stroke', 0.0)),
                    'rot': float(f.get('rotation', 0.0)),
                    'x': f['x'], 'y': f['y'], 'w': f['w'], 'h': f['h']})
    return els


def part_c8(art):
    manifest = json.load(open(os.path.join(art, 'manifest.json'), encoding='utf-8'))
    geo = json.load(open(os.path.join(art, 'diag_geometry.json'), encoding='utf-8'))
    pages_n = int(manifest['pageCount'])
    say('== C8 element residual (decorations, floating shapes). Zones exclude text bands and math.')
    say('C8 official gate untouched. "excl" RMSE removes element zones: diagnostic only, not a pass.')
    with tempfile.TemporaryDirectory() as tmp:
        prefix = os.path.join(tmp, 'vec')
        subprocess.run(['pdftoppm', '-r', '96', '-png', os.path.join(art, 'vector.pdf'), prefix], check=True)
        rendered = sorted(glob.glob(prefix + '-*.png'),
                          key=lambda p: int(re.search(r'-(\d+)\.png$', p).group(1)))
        agg = {}
        for index in range(pages_n):
            page = geo['pages'][index]
            pdark = rp.darkness(rp.gray_of(np.asarray(
                Image.open(os.path.join(art, f'preview_page_{index + 1}.png')).convert('RGB'), dtype=np.float64)))
            vdark = rp.darkness(rp.gray_of(np.asarray(
                Image.open(rendered[index]).convert('RGB'), dtype=np.float64)))
            gp = pdark[CROP:-CROP, CROP:-CROP]
            gv = vdark[CROP:-CROP, CROP:-CROP]
            hh, ww = min(gp.shape[0], gv.shape[0]), min(gp.shape[1], gv.shape[1])
            gp, gv = gp[:hh, :ww], gv[:hh, :ww]
            H, W = gp.shape
            bands = dbm.bands_of(page['words'], H, W, 'run')
            cats = dc.category_masks(page, bands, H, W)
            non_text = cats['outside']          # True where no text band and no math box
            union = np.zeros((H, W), bool)
            els = page_elements(page)
            rows_out = []
            for e in els:
                x0 = e['x'] * PT2PX - CROP
                y0 = e['y'] * PT2PX - CROP
                x1 = (e['x'] + e['w']) * PT2PX - CROP
                y1 = (e['y'] + e['h']) * PT2PX - CROP
                if x1 - x0 < 1 or y1 - y0 < 1:
                    continue
                stroke_px = e['stroke'] * PT2PX
                zone = zone_mask(e['kind'] if e['src'] == 'deco' else 'border',
                                 x0, y0, x1, y1, stroke_px, H, W)
                zone &= non_text
                if not zone.any():
                    continue
                union |= zone
                diff2 = (gp - gv) ** 2
                sse = float(diff2[zone].sum())
                ink_p = float(gp[zone].sum())
                ink_v = float(gv[zone].sum())
                st = None
                if e['src'] == 'deco' or (e['src'] == 'float' and abs(e['rot']) < 0.01):
                    gpm = gp * non_text
                    gvm = gv * non_text
                    st = edge_stats(gpm, gvm, x0, y0, x1, y1)
                key = (e['src'], e['type'], e['kind'], e['framed'])
                a = agg.setdefault(key, {'n': 0, 'sse': 0.0, 'ink_p': 0.0, 'ink_v': 0.0,
                                         'dl': [], 'dr': [], 'dt': [], 'db': [], 'tr': [],
                                         'strokes': set()})
                a['n'] += 1
                a['sse'] += sse
                a['ink_p'] += ink_p
                a['ink_v'] += ink_v
                a['strokes'].add(round(e['stroke'], 2))
                if st:
                    if not math.isnan(st['left']['d']):
                        a['dl'].append(st['left']['d'])
                    if not math.isnan(st['right']['d']):
                        a['dr'].append(st['right']['d'])
                    if not math.isnan(st['top']['d']):
                        a['dt'].append(st['top']['d'])
                    if not math.isnan(st['bottom']['d']):
                        a['db'].append(st['bottom']['d'])
                    tp = st['left']['thk_pre'] + st['right']['thk_pre']
                    tv = st['left']['thk_vec'] + st['right']['thk_vec']
                    if tp > 1e-6:
                        a['tr'].append(tv / tp)
                rows_out.append((sse, e, st))
            total = float(((gp - gv) ** 2).sum())
            n = gp.size
            sse_union = float(((gp - gv) ** 2)[union].sum())
            rmse_all = math.sqrt(total / n)
            rmse_excl = math.sqrt(max(total - sse_union, 0.0) / n)
            sse_nontext = float(((gp - gv) ** 2)[non_text].sum())
            say(f'C8 p{index + 1}: rmse={rmse_all:.4f} | excl element zones (diag)={rmse_excl:.4f} | '
                f'SSE share: element zones={sse_union / max(total, 1e-12):.2f} '
                f'non-text remainder={(sse_nontext - sse_union) / max(total, 1e-12):.2f} '
                f'text+math={1 - sse_nontext / max(total, 1e-12):.2f} | elements={len(rows_out)}')
            # Diagnostic exclusion scenarios (measurement only; none is a fix or a gate pass).
            diff2_all = (gp - gv) ** 2
            float_zone = np.zeros((H, W), bool)
            for e2 in els:
                if e2['src'] != 'float' or e2['type'] != 'shape' or not e2['framed'] or abs(e2['rot']) >= 0.01:
                    continue
                fx0 = e2['x'] * PT2PX - CROP
                fy0 = e2['y'] * PT2PX - CROP
                fx1 = (e2['x'] + e2['w']) * PT2PX - CROP
                fy1 = (e2['y'] + e2['h']) * PT2PX - CROP
                fz = zone_mask('border', fx0, fy0, fx1, fy1, e2['stroke'] * PT2PX, H, W) & non_text
                float_zone |= fz
            italic_m = cats['italic']
            math_m = cats['math']
            scen = [
                ('framed-float zones', float_zone),
                ('all element zones', union),
                ('element zones+italic bands', union | italic_m),
                ('element zones+italic+math', union | italic_m | math_m),
            ]
            parts = []
            for label, msk in scen:
                rem = float(diff2_all[~msk].sum())
                parts.append(f'{label}={math.sqrt(rem / n):.4f}')
            say(f'C8 p{index + 1} exclusion scenarios (diag only, RMSE over remaining pixels): ' + ' | '.join(parts))
            rows_out.sort(key=lambda r: -r[0])
            for sse, e, st in rows_out[:4]:
                desc = ''
                if st:
                    desc = (f" dL={st['left']['d']:+.2f} dR={st['right']['d']:+.2f} "
                            f"dT={st['top']['d']:+.2f} dB={st['bottom']['d']:+.2f} px")
                say(f"C8   p{index + 1} top {e['src']}/{e['type']} stroke={e['stroke']:.2f}pt "
                    f"rot={e['rot']:.0f} at x{e['x']:.1f} y{e['y']:.1f} {e['w']:.1f}x{e['h']:.1f}pt "
                    f"sse={sse:.2f}{desc}")
        say('C8 per class (all pages): n | SSE | ink vec/pre | median edge offset (vec-pre, px) L/R/T/B | '
            'thickness ratio vec/pre | strokes')
        total_sse = sum(a['sse'] for a in agg.values())
        for key, a in sorted(agg.items(), key=lambda kv: -kv[1]['sse']):
            med = lambda v: (f'{np.median(v):+.2f}' if v else 'na')  # noqa: E731
            ratio = a['ink_v'] / a['ink_p'] if a['ink_p'] > 1e-9 else float('nan')
            tr = f"{np.median(a['tr']):.2f}" if a['tr'] else 'na'
            say(f"C8 {key[0]}/{key[1]}/{key[2]}/framed={key[3]}: n={a['n']} "
                f"sse={a['sse']:.1f} ({a['sse'] / max(total_sse, 1e-12):.2f}) ink={ratio:.2f} "
                f"edges L{med(a['dl'])} R{med(a['dr'])} T{med(a['dt'])} B{med(a['db'])} "
                f"thk={tr} strokes={sorted(a['strokes'])[:4]}")


def main(art):
    try:
        part_c8(art)
    except Exception:  # noqa: BLE001
        say('C8 FAILED: ' + traceback.format_exc()[-700:].replace('\n', ' | '))
    dbm.flush('C6-ELEM')


if __name__ == '__main__':
    art_dir = sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'
    main(art_dir)
    sys.exit(0)
