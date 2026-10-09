#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY element-probe analysis (frames / dividers / borders). Not for merge.

Reads build/visual_parity/eprobe/manifest.json written by test/visual/element_probe_test.dart.
Each case: Preview PNG (Flutter, mirrors production paint) vs PDF (Poppler, -r 96).
Reports per case: edge offsets PDF-Preview in px (L/R/T/B), thickness ratio, ink ratio, SSE.
Positive offset: PDF edge lies further right / lower than the Preview edge.
Diagnostic only. The official gate is not touched.
"""
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
import diag_raster_probe as rp  # noqa: E402
import diag_baseline_model as dbm  # noqa: E402
import diag_elements as de  # noqa: E402

PT2PX = 96.0 / 72.0


def say(line=''):
    dbm.say(line)


def dark_of(path):
    return rp.darkness(rp.gray_of(np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)))


def bar_centroid(g, x0, x1, y0, y1):
    """Vertical centroid of a thin horizontal bar (rows y0-4..y1+4, columns inside the bar)."""
    H, W = g.shape
    ys = slice(max(int(y0) - 4, 0), min(int(math.ceil(y1)) + 5, H))
    xs = slice(max(int(x0) + 4, 0), min(int(x1) - 4, W))
    prof = g[ys, xs].sum(axis=1)
    idx = np.arange(prof.size) + ys.start
    s = prof.sum()
    return float((prof * idx).sum() / s) if s > 1e-9 else float('nan'), float(s)


def part_probe(art):
    man_path = os.path.join(art, 'eprobe', 'manifest.json')
    if not os.path.exists(man_path):
        say('P FAILED: eprobe manifest missing')
        return
    man = json.load(open(man_path, encoding='utf-8'))
    say('== P element probe: Preview (Flutter) vs PDF (Poppler), each condition isolated')
    say('P cols: edges PDF-Preview px L/R/T/B | thickness vec/pre | ink vec/pre | SSE')
    with tempfile.TemporaryDirectory() as tmp:
        for c in man['cases']:
            try:
                prefix = os.path.join(tmp, c['id'])
                subprocess.run(['pdftoppm', '-r', '96', '-png', '-singlefile', c['pdfPath'], prefix], check=True)
                gv = rp.darkness(rp.gray_of(np.asarray(Image.open(prefix + '.png').convert('RGB'),
                                                          dtype=np.float64)))
                gp = dark_of(c['png'])
                hh, ww = min(gp.shape[0], gv.shape[0]), min(gp.shape[1], gv.shape[1])
                gp, gv = gp[:hh, :ww], gv[:hh, :ww]
                x0 = c['x'] * PT2PX
                y0 = c['y'] * PT2PX
                x1 = (c['x'] + c['w']) * PT2PX
                y1 = (c['y'] + c['h']) * PT2PX
                sse = float(((gp - gv) ** 2).sum())
                ink = float(gv.sum() / max(gp.sum(), 1e-9))
                if c['preview'] == 'divider':
                    cp, sp = bar_centroid(gp, x0, x1, y0, y1)
                    cv, sv = bar_centroid(gv, x0, x1, y0, y1)
                    say(f"P {c['id']}: bar centroid vec-pre={cv - cp:+.3f}px (pre {cp:.2f}, vec {cv:.2f}) "
                        f"thickness ink vec/pre={sv / max(sp, 1e-9):.3f} sse={sse:.2f} ink={ink:.3f} "
                        f"[expected 1.2pt = {c['h'] * PT2PX:.2f}px tall]")
                    continue
                st = de.edge_stats(gp, gv, x0, y0, x1, y1)
                if st is None:
                    say(f"P {c['id']}: edge stats unavailable")
                    continue
                thk = (st['left']['thk_vec'] + st['right']['thk_vec']) / max(
                    st['left']['thk_pre'] + st['right']['thk_pre'], 1e-9)
                say(f"P {c['id']} [{c['preview']}->{c['pdf']} stroke {c['stroke']}pt, half={c['stroke'] * PT2PX / 2:.2f}px]: "
                    f"L{st['left']['d']:+.2f} R{st['right']['d']:+.2f} T{st['top']['d']:+.2f} B{st['bottom']['d']:+.2f} | "
                    f"thk {thk:.2f} | ink {ink:.3f} | sse {sse:.2f}")
            except Exception:  # noqa: BLE001
                say(f"P {c.get('id')} FAILED: " + traceback.format_exc()[-300:].replace('\n', ' | '))


def main(art):
    try:
        part_probe(art)
    except Exception:  # noqa: BLE001
        say('P FAILED: ' + traceback.format_exc()[-500:].replace('\n', ' | '))
    dbm.flush('C6-EPROBE')


if __name__ == '__main__':
    art_dir = sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'
    main(art_dir)
    sys.exit(0)
