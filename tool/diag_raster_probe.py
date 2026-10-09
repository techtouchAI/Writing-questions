#!/usr/bin/env python3
"""[C6-DIAG] TEMPORARY raster-floor probe analysis (not for merge).

Inputs (written by test/visual/raster_floor_probe_test.dart):
  raster_probe_flutter.png  Flutter Text at 11pt (96/72 px) on white
  raster_probe.pdf          the same glyphs and baseline emitted as a PDF

The PDF is rasterized at 96 dpi by poppler (pdftoppm, the gate's renderer) and
by MuPDF, plus a 1200 dpi MuPDF reference. A calibration rectangle is present
in both, so coverage gain/loss is measured against exact area.
"""
import glob
import os
import subprocess
import sys

import numpy as np
import pymupdf
from PIL import Image


def gray_of(array):
    return array[:, :, :3].astype(np.float64).mean(axis=2)


def darkness(gray):
    return (255.0 - gray) / 255.0


def regions(gray):
    d = darkness(gray)
    text = d[:, :90]
    text_ink = float(text.sum())
    rect_ink = float(d[10:20, 100:120].sum())
    return text_ink, rect_ink, text


def histogram(region):
    partial = region[(region > 0.05) & (region < 0.95)]
    full = region[region >= 0.95]
    return int(full.size), int(partial.size)


def rmse(a, b):
    return float(np.sqrt(np.mean((a - b) ** 2)))


def main(art):
    out_dir = os.path.join(art, 'probe')
    os.makedirs(out_dir, exist_ok=True)
    pdf_path = os.path.join(art, 'raster_probe.pdf')
    flutter_path = os.path.join(art, 'raster_probe_flutter.png')
    if not (os.path.exists(pdf_path) and os.path.exists(flutter_path)):
        print('[C6-PROBE] inputs missing; probe did not run')
        return 0

    flutter = gray_of(np.asarray(Image.open(flutter_path).convert('RGB')))
    prefix = os.path.join(out_dir, 'pop')
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
    # Text-only reference: same x-range as the 96-dpi text region (x < 90 px).
    ref_ink = float(darkness(ref)[:, : int(90 * 1200 / 96)].sum()) / (1200 / 96) ** 2

    shapes = {'flutter': flutter.shape, 'poppler': poppler.shape, 'mupdf': mupdf.shape}
    print(f'[C6-PROBE] shapes={shapes} reference(mupdf 1200dpi, px-equiv)={ref_ink:.3f}')

    rows = {}
    for name, gray in (('flutter', flutter), ('poppler', poppler), ('mupdf', mupdf)):
        if gray.shape != (60, 200):
            print(f'[C6-PROBE] {name} shape {gray.shape} != (60, 200)')
            continue
        text_ink, rect_ink, text = regions(gray)
        full, partial = histogram(text)
        rows[name] = (text_ink, rect_ink, text, full, partial)
        print(f'[C6-PROBE] {name:8s} calibration_rect_ink(expect 200)={rect_ink:8.3f} '
              f'text_ink={text_ink:8.3f} ratio_to_ref={text_ink / ref_ink:6.4f} '
              f'full_px={full} partial_px={partial}')

    if 'flutter' in rows and 'poppler' in rows:
        print(f'[C6-PROBE] text rmse flutter-vs-poppler={rmse(rows["flutter"][2], rows["poppler"][2]):.6f} '
              f'flutter-vs-mupdf={rmse(rows["flutter"][2], rows["mupdf"][2]):.6f} '
              f'poppler-vs-mupdf={rmse(rows["poppler"][2], rows["mupdf"][2]):.6f}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'build/visual_parity'))
