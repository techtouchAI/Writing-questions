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
