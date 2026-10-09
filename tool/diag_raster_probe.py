#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY raster-floor probe analysis (not for merge).

Inputs (written by test/visual/raster_floor_probe_test.dart, one per size tag):
  raster_probe_<pt>.pdf            the glyphs and baseline emitted as a PDF
  raster_probe_flutter_<pt>.png    the same glyphs rendered by Flutter (96/72 px)

Each PDF is rasterized at 96 dpi by poppler (pdftoppm, the gate's renderer) and
by MuPDF, with a 1200 dpi MuPDF reference. A calibration rectangle is present in
both, so coverage gain or loss is measured against exact area. Results are
emitted as one ::notice annotation so they are readable from the check run.
"""
import glob
import os
import re
import subprocess
import sys

import numpy as np
import pymupdf
from PIL import Image

LINES = []


def say(line):
    LINES.append(line)


def flush():
    message = '\n'.join(LINES)
    message = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::notice title=C6-PROBE::{message}')


def gray_of(array):
    return array[:, :, :3].astype(np.float64).mean(axis=2)


def darkness(gray):
    return (255.0 - gray) / 255.0


def text_region(gray):
    """Text ink: x < 90 px (the calibration rectangle starts at x = 100)."""
    return darkness(gray)[:, :90]


def rect_ink(gray):
    return float(darkness(gray)[10:20, 100:120].sum())


def rmse(a, b):
    return float(np.sqrt(np.mean((a - b) ** 2)))


def sample_shifted(img, dy, dx):
    """Bilinear sample of a 2D image displaced by (dy, dx) px (same shape out)."""
    h, w = img.shape
    ys = np.arange(h, dtype=np.float64) + dy
    xs = np.arange(w, dtype=np.float64) + dx
    yi = np.clip(np.floor(ys).astype(int), 0, h - 2)
    xi = np.clip(np.floor(xs).astype(int), 0, w - 2)
    ty = (np.clip(ys, 0, h - 1) - yi)[:, None]
    tx = (np.clip(xs, 0, w - 1) - xi)[None, :]
    a = img[yi[:, None], xi[None, :]]
    b = img[yi[:, None], xi[None, :] + 1]
    c = img[yi[:, None] + 1, xi[None, :]]
    d = img[yi[:, None] + 1, xi[None, :] + 1]
    return (1 - ty) * (1 - tx) * a + (1 - ty) * tx * b + ty * (1 - tx) * c + ty * tx * d


def subpixel_fit(ref, mov, span=1.0, step=0.125):
    """Best continuous translation of mov onto ref. Returns (rmse, dx, dy)."""
    best = None
    for dy in np.arange(-span, span + 1e-9, step):
        for dx in np.arange(-span, span + 1e-9, step):
            value = rmse(ref, sample_shifted(mov, dy, dx))
            if best is None or value < best[0]:
                best = (value, float(dx), float(dy))
    return best


def hist_match_rmse(ref, mov):
    """RMSE after histogram specification of mov onto ref (tone-only bound)."""
    src = np.clip(np.round(mov * 255), 0, 255).astype(int).ravel()
    dst = np.clip(np.round(ref * 255), 0, 255).astype(int).ravel()
    hs = np.bincount(src, minlength=256).cumsum() / src.size
    hr = np.bincount(dst, minlength=256).cumsum() / dst.size
    lut = np.searchsorted(hr, hs, side='left').clip(0, 255) / 255.0
    matched = lut[np.clip(np.round(mov * 255), 0, 255).astype(int)]
    return rmse(ref, matched)


def probe(art, tag):
    pdf_path = os.path.join(art, f'raster_probe_{tag}.pdf')
    flutter_path = os.path.join(art, f'raster_probe_flutter_{tag}.png')
    if not (os.path.exists(pdf_path) and os.path.exists(flutter_path)):
        say(f'[C6-PROBE] {tag}pt inputs missing (pdf={os.path.exists(pdf_path)} '
            f'png={os.path.exists(flutter_path)})')
        return

    out_dir = os.path.join(art, 'probe')
    os.makedirs(out_dir, exist_ok=True)
    flutter = gray_of(np.asarray(Image.open(flutter_path).convert('RGB')))
    prefix = os.path.join(out_dir, f'pop_{tag}')
    subprocess.run(['pdftoppm', '-r', '96', '-png', pdf_path, prefix], check=True)
    pop_files = sorted(glob.glob(prefix + '*.png'))
    poppler = gray_of(np.asarray(Image.open(pop_files[0]).convert('RGB')))

    doc = pymupdf.open(pdf_path)
    pix = doc[0].get_pixmap(dpi=96, alpha=False)
    mupdf = gray_of(np.frombuffer(pix.samples, dtype=np.uint8).reshape(
        pix.height, pix.width, pix.n))
    ref_pix = doc[0].get_pixmap(dpi=1200, alpha=False)
    ref = gray_of(np.frombuffer(ref_pix.samples, dtype=np.uint8).reshape(
        ref_pix.height, ref_pix.width, ref_pix.n))
    scale = 1200 / 96
    ref_ink = float(darkness(ref)[:, : int(90 * scale)].sum()) / scale ** 2

    say(f'[C6-PROBE] size={tag}pt shapes flutter={flutter.shape} poppler={poppler.shape} '
        f'mupdf={mupdf.shape} linear-reference(mupdf 1200dpi)={ref_ink:.3f}')
    results = {}
    for name, gray in (('flutter', flutter), ('poppler', poppler), ('mupdf', mupdf)):
        if gray.shape != (60, 200):
            say(f'[C6-PROBE] {tag}pt {name} shape {gray.shape} != (60, 200)')
            continue
        region = text_region(gray)
        ink = float(region.sum())
        full = int((region >= 0.95).sum())
        partial = int(((region > 0.05) & (region < 0.95)).sum())
        results[name] = region
        say(f'[C6-PROBE] {tag}pt {name:8s} rect_ink(expect 200)={rect_ink(gray):8.3f} '
            f'text_ink={ink:8.3f} ratio_to_linear={ink / ref_ink:6.4f} '
            f'full_px={full} partial_px={partial}')
    if {'flutter', 'poppler'} <= results.keys():
        fl = results['flutter']
        po = results['poppler']
        zero = rmse(fl, po)
        best = subpixel_fit(fl, po)
        say(f'[C6-PROBE] {tag}pt fit flutter<-poppler: rmse0={zero:.6f} '
            f'subpixel_best={best[0]:.6f} at dx={best[1]:+.3f} dy={best[2]:+.3f} '
            f'tone_only(hist-match)={hist_match_rmse(fl, po):.6f}')
    if {'flutter', 'poppler', 'mupdf'} <= results.keys():
        say(f'[C6-PROBE] {tag}pt text rmse flutter-vs-poppler={rmse(results["flutter"], results["poppler"]):.6f} '
            f'flutter-vs-mupdf={rmse(results["flutter"], results["mupdf"]):.6f} '
            f'poppler-vs-mupdf={rmse(results["poppler"], results["mupdf"]):.6f}')


def main(art):
    tags = sorted({re.sub(r'^raster_probe_(.+)\.pdf$', r'\1', os.path.basename(p))
                   for p in glob.glob(os.path.join(art, 'raster_probe_*.pdf'))})
    if not tags:
        say('[C6-PROBE] no probe PDFs found; probe did not run')
        return 0
    for tag in tags:
        probe(art, tag)
    return 0


if __name__ == '__main__':
    code = main(sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity')
    flush()
    sys.exit(code)
