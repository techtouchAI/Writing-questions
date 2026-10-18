#!/usr/bin/env python3
"""Isolate what the visual RMSE number is made of. Diagnostic only.

Does not change the 0.02 ceiling, the reference images, or the gate.
Prints every command-equivalent setting so a number can be reproduced.

Two modes:
  synthetic   known pages (blank, geometry, Latin, Arabic, embedded image),
              rasterised by MuPDF and PDFium, then scored with the gate's
              ImageMagick RMSE after the gate's resize+crop.
  artifacts   the fixture files in <dir>, if present. Records provenance and
              recomputes the gate number. Never required for the gate.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

WIDTH = 794
HEIGHT = 1123
DPI = 96
CROP = 2
# A4 in points, the same formula as LayoutUnits.a4.
A4_W = 210 * 72 / 25.4
A4_H = 297 * 72 / 25.4
# Page size whose 96 dpi raster is exactly the canvas, if the renderer
# multiplies by 96/72 and rounds to nearest.
EXACT_W = WIDTH * 72 / DPI
EXACT_H = HEIGHT * 72 / DPI

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, 'assets', 'fonts')
LATIN_FONT = os.path.join(FONTS, 'Tajawal-Regular.ttf')
ARABIC_FONT = os.path.join(FONTS, 'NotoNaskhArabic-Regular.ttf')


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True)


def rmse(a, b):
    """Gate metric: ImageMagick compare -metric RMSE, parenthesised 0..1."""
    proc = subprocess.run(
        ['compare', '-metric', 'RMSE', a, b, 'null:'],
        capture_output=True, text=True)
    raw = (proc.stderr or '') + (proc.stdout or '')
    if '(' in raw and ')' in raw:
        return float(raw.split('(')[1].split(')')[0]), raw.strip()
    token = raw.split()[0] if raw.split() else '0'
    return float(token) / 65535.0, raw.strip()


def identify(path):
    proc = subprocess.run(
        ['identify', '-format',
         '%w %h %m %[channels] %[bit-depth] %[colorspace] %[profile:icc]\n',
         path],
        capture_output=True, text=True, check=True)
    return proc.stdout.strip()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b''):
            digest.update(chunk)
    return digest.hexdigest()


def gate_norm(src, dst, width=WIDTH, height=HEIGHT):
    """The gate's normalisation: resize to the reference, then crop 2 px."""
    crop = f'{width - 4}x{height - 4}+{CROP}+{CROP}'
    run(['convert', src, '-resize', f'{width}x{height}!',
         '-crop', crop, '+repage', dst])


def write_png(path, draw):
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (WIDTH, HEIGHT), 'white')
    draw(ImageDraw.Draw(image), image)
    image.save(path)


def render_mupdf(pdf, png, dpi=DPI):
    import pymupdf
    doc = pymupdf.open(pdf)
    page = doc[0]
    pix = page.get_pixmap(dpi=dpi, alpha=False, colorspace=pymupdf.csRGB)
    pix.save(png)
    return {'renderer': f'MuPDF {pymupdf.version[0]}',
            'page_pt': [round(page.rect.width, 4), round(page.rect.height, 4)],
            'px': [pix.width, pix.height], 'dpi': dpi, 'alpha': False,
            'colorspace': 'RGB'}


def render_pdfium(pdf, png, dpi=DPI):
    import pypdfium2 as pdfium
    doc = pdfium.PdfDocument(pdf)
    page = doc.get_page(0)
    width_pt, height_pt = page.get_size()
    bitmap = page.render(scale=dpi / 72)
    image = bitmap.to_pil()
    if image.mode != 'RGB':
        image = image.convert('RGB')
    image.save(png)
    page.close()
    doc.close()
    return {'renderer': 'PDFium via pypdfium2',
            'page_pt': [round(width_pt, 4), round(height_pt, 4)],
            'px': [image.width, image.height], 'dpi': dpi, 'alpha': False,
            'colorspace': 'RGB'}


def new_pdf(path, width, height, draw):
    import pymupdf
    doc = pymupdf.open()
    page = doc.new_page(width=width, height=height)
    draw(page)
    doc.save(path)
    doc.close()


def font(page, path, name):
    return page.insert_font(fontname=name, fontfile=path)


def experiment_pipeline(out):
    """Measurement-tool checks. No PDF, no second renderer."""
    rows = []
    blank = os.path.join(out, 'blank.png')
    write_png(blank, lambda d, im: None)
    rows.append(('identical PNGs', *rmse(blank, blank), 'pipeline'))

    copy = os.path.join(out, 'blank_copy.png')
    shutil.copy(blank, copy)
    rows.append(('recompressed copy', *rmse(blank, copy), 'pipeline'))

    resized = os.path.join(out, 'resized.png')
    run(['convert', blank, '-resize', f'{WIDTH}x{HEIGHT}!', resized])
    rows.append(('resize already-correct size', *rmse(blank, resized),
                 'pipeline'))

    cropped_a = os.path.join(out, 'crop_a.png')
    cropped_b = os.path.join(out, 'crop_b.png')
    gate_norm(blank, cropped_a)
    gate_norm(blank, cropped_b)
    rows.append(('symmetric crop of identical pages',
                 *rmse(cropped_a, cropped_b), 'pipeline'))

    # A 1 px gray border on one side only, then the gate crop.
    bordered = os.path.join(out, 'bordered.png')
    write_png(bordered, lambda d, im: d.rectangle(
        [0, 0, WIDTH - 1, HEIGHT - 1], outline=(229, 231, 235)))
    raw_border = rmse(blank, bordered)
    norm_blank = os.path.join(out, 'norm_blank.png')
    norm_border = os.path.join(out, 'norm_border.png')
    gate_norm(blank, norm_blank)
    gate_norm(bordered, norm_border)
    rows.append(('1px border, before crop', *raw_border, 'pipeline'))
    rows.append(('1px border, after symmetric 2px crop',
                 *rmse(norm_blank, norm_border), 'pipeline'))

    # Alpha versus flattened white. Flutter snapshots are often RGBA.
    rgba = os.path.join(out, 'rgba.png')
    from PIL import Image
    Image.new('RGBA', (WIDTH, HEIGHT), (255, 255, 255, 255)).save(rgba)
    rows.append(('RGBA opaque white vs RGB white', *rmse(blank, rgba),
                 'pipeline'))
    transparent = os.path.join(out, 'transparent.png')
    Image.new('RGBA', (WIDTH, HEIGHT), (255, 255, 255, 0)).save(transparent)
    rows.append(('RGBA transparent vs RGB white', *rmse(blank, transparent),
                 'pipeline'))

    offwhite = os.path.join(out, 'offwhite.png')
    Image.new('RGB', (WIDTH, HEIGHT), (254, 254, 254)).save(offwhite)
    rows.append(('white vs 254,254,254', *rmse(blank, offwhite), 'pipeline'))

    # Defects the gate must still see, on a page with a rule and a bar.
    def scene(d, im, shift=0, delete=False, rule_dy=0):
        d.rectangle([80, 200 + shift, 400, 260 + shift], fill=(0, 0, 0))
        if not delete:
            d.rectangle([80, 400, 500, 424], fill=(20, 20, 20))
        d.rectangle([80, 700 + rule_dy, 500, 701 + rule_dy], fill=(0, 0, 0))

    base = os.path.join(out, 'scene.png')
    write_png(base, lambda d, im: scene(d, im))
    for name, kwargs in (
            ('shift 1px', {'shift': 1}),
            ('shift 4px', {'shift': 4}),
            ('delete band', {'delete': True}),
            ('underline +4px', {'rule_dy': 4}),
    ):
        path = os.path.join(out, name.replace(' ', '_') + '.png')
        write_png(path, lambda d, im, kw=kwargs: scene(d, im, **kw))
        value, raw = rmse(base, path)
        rows.append((name + ' (same raster, no crop)', value, raw, 'defect'))
        na, nb = path + '.n.png', base + '.n.png'
        gate_norm(path, na)
        gate_norm(base, nb)
        value, raw = rmse(na, nb)
        rows.append((name + ' after gate crop', value, raw, 'defect'))
    return rows


def experiment_renderers(out):
    rows = []
    pages = []

    def add(name, width, height, draw):
        pdf = os.path.join(out, name + '.pdf')
        new_pdf(pdf, width, height, draw)
        pages.append((name, pdf, width, height))

    add('blank_a4', A4_W, A4_H, lambda page: None)
    add('blank_exact_px', EXACT_W, EXACT_H, lambda page: None)

    def shapes(page):
        page.draw_rect(pymupdf_rect(60, 80, 200, 140), color=(0, 0, 0),
                       fill=(0, 0, 0), width=0)
        page.draw_rect(pymupdf_rect(60, 180, 260, 260), color=(0, 0, 0),
                       width=2)
        page.draw_line(pymupdf_point(60, 300), pymupdf_point(300, 300),
                       color=(0, 0, 0), width=1)
        page.draw_circle(pymupdf_point(120, 380), 30, color=(0, 0, 0),
                         fill=(0.2, 0.2, 0.2))

    add('shapes_a4', A4_W, A4_H, shapes)

    def latin(page):
        face = font(page, LATIN_FONT, 'Tajawal')
        page.insert_text(pymupdf_point(72, 120), 'Pick one: Vocabulary',
                         fontname='Tajawal', fontsize=18, color=(0, 0, 0))

    def arabic(page):
        face = font(page, ARABIC_FONT, 'Noto')
        page.insert_text(pymupdf_point(72, 160), 'الفائدة الأولى ٢٠٢٧',
                         fontname='Noto', fontsize=18, color=(0, 0, 0))

    def both(page):
        latin(page)
        arabic(page)

    add('latin_a4', A4_W, A4_H, latin)
    add('arabic_a4', A4_W, A4_H, arabic)
    add('text_a4', A4_W, A4_H, both)

    # Embedded image: a known PNG placed on the page, not a substitute for
    # the product's vector output. This only tests the raster round-trip.
    from PIL import Image, ImageDraw
    chip = os.path.join(out, 'chip.png')
    image = Image.new('RGB', (120, 40), 'white')
    ImageDraw.Draw(image).rectangle([4, 4, 116, 36], outline='black', width=2)
    ImageDraw.Draw(image).text((12, 12), 'chip', fill='black')
    image.save(chip)

    def embedded(page):
        page.insert_image(pymupdf_rect(72, 72, 192, 112), filename=chip)

    add('embedded_image', EXACT_W, EXACT_H, embedded)

    # Defects inside the PDF, same renderer on both sides, and cross-renderer.
    def text_shifted(page):
        font(page, LATIN_FONT, 'Tajawal')
        page.insert_text(pymupdf_point(76, 120), 'Pick one: Vocabulary',
                         fontname='Tajawal', fontsize=18)
    def text_deleted(page):
        font(page, LATIN_FONT, 'Tajawal')
        page.insert_text(pymupdf_point(72, 120), 'Pick one:',
                         fontname='Tajawal', fontsize=18)
    def underline_moved(page):
        font(page, LATIN_FONT, 'Tajawal')
        page.insert_text(pymupdf_point(72, 120), 'Pick one: Vocabulary',
                         fontname='Tajawal', fontsize=18)
        page.draw_line(pymupdf_point(72, 128), pymupdf_point(280, 128),
                       color=(0, 0, 0), width=0.8)
    def underline_base(page):
        font(page, LATIN_FONT, 'Tajawal')
        page.insert_text(pymupdf_point(72, 120), 'Pick one: Vocabulary',
                         fontname='Tajawal', fontsize=18)
        page.draw_line(pymupdf_point(72, 124), pymupdf_point(280, 124),
                       color=(0, 0, 0), width=0.8)

    add('underline_base', A4_W, A4_H, underline_base)
    add('text_shifted_4pt', A4_W, A4_H, text_shifted)
    add('text_deleted', A4_W, A4_H, text_deleted)
    add('underline_moved', A4_W, A4_H, underline_moved)

    meta = {}
    for name, pdf, width, height in pages:
        mupdf_png = os.path.join(out, name + '_mupdf.png')
        pdfium_png = os.path.join(out, name + '_pdfium.png')
        meta[name] = {
            'pdf_sha256': sha256(pdf),
            'page_requested_pt': [round(width, 4), round(height, 4)],
            'mupdf': render_mupdf(pdf, mupdf_png),
            'pdfium': render_pdfium(pdf, pdfium_png),
            'mupdf_identify': identify(mupdf_png),
            'pdfium_identify': identify(pdfium_png),
        }
        na = os.path.join(out, name + '_mupdf_norm.png')
        nb = os.path.join(out, name + '_pdfium_norm.png')
        gate_norm(mupdf_png, na)
        gate_norm(pdfium_png, nb)
        value, raw = rmse(na, nb)
        kind = 'renderer' if 'text' not in name and 'latin' not in name \
            and 'arabic' not in name and 'underline' not in name \
            and 'shifted' not in name and 'deleted' not in name else 'renderer-text'
        if name.startswith('blank') or name.startswith('shapes') or name.startswith('embedded'):
            kind = 'renderer-nontext'
        rows.append((f'{name}: MuPDF vs PDFium after gate norm', value, raw, kind))
        value, raw = rmse(mupdf_png, pdfium_png)
        rows.append((f'{name}: MuPDF vs PDFium raw', value, raw, kind + '-raw'))

    # Same-renderer defect detection, and cross-renderer defect detection.
    def pair(label, left, right, kind):
        value, raw = rmse(os.path.join(out, left), os.path.join(out, right))
        rows.append((label, value, raw, kind))

    for engine in ('mupdf', 'pdfium'):
        pair(f'shift 4pt vs base ({engine})',
             f'latin_a4_{engine}_norm.png',
             f'text_shifted_4pt_{engine}_norm.png', 'defect-same-renderer')
        pair(f'delete word vs base ({engine})',
             f'latin_a4_{engine}_norm.png',
             f'text_deleted_{engine}_norm.png', 'defect-same-renderer')
        pair(f'underline move vs base ({engine})',
             f'underline_base_{engine}_norm.png',
             f'underline_moved_{engine}_norm.png', 'defect-same-renderer')
    pair('cross-renderer floor (latin)',
         'latin_a4_mupdf_norm.png', 'latin_a4_pdfium_norm.png', 'floor')
    pair('cross-renderer + 4pt shift',
         'latin_a4_mupdf_norm.png', 'text_shifted_4pt_pdfium_norm.png',
         'defect-cross-renderer')
    pair('cross-renderer + deletion',
         'latin_a4_mupdf_norm.png', 'text_deleted_pdfium_norm.png',
         'defect-cross-renderer')
    pair('cross-renderer + underline move',
         'underline_base_mupdf_norm.png', 'underline_moved_pdfium_norm.png',
         'defect-cross-renderer')

    # Embedded image versus the chip placed at a known pixel position is not
    # a full-page match; record the raster size only. Round-trip of a PDF
    # that is nothing but a full-page image is the Exact-PDF analogue.
    full = os.path.join(out, 'full_ref.png')
    write_png(full, lambda d, im: d.rectangle([40, 40, 200, 80], fill='black'))

    def full_image(page):
        page.insert_image(page.rect, filename=full)

    pdf = os.path.join(out, 'full_image.pdf')
    new_pdf(pdf, EXACT_W, EXACT_H, full_image)
    mupdf_png = os.path.join(out, 'full_image_mupdf.png')
    pdfium_png = os.path.join(out, 'full_image_pdfium.png')
    meta['full_image'] = {
        'mupdf': render_mupdf(pdf, mupdf_png),
        'pdfium': render_pdfium(pdf, pdfium_png),
    }
    for engine, png in (('mupdf', mupdf_png), ('pdfium', pdfium_png)):
        norm = png + '.norm.png'
        gate_norm(png, norm)
        ref_norm = os.path.join(out, 'full_ref_norm.png')
        gate_norm(full, ref_norm)
        value, raw = rmse(norm, ref_norm)
        rows.append((f'full-page image round-trip {engine} vs source PNG',
                     value, raw, 'roundtrip'))
    return rows, meta


def pymupdf_rect(x0, y0, x1, y1):
    import pymupdf
    return pymupdf.Rect(x0, y0, x1, y1)


def pymupdf_point(x, y):
    import pymupdf
    return pymupdf.Point(x, y)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'synthetic'
    out = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp(prefix='rmse-iso-')
    os.makedirs(out, exist_ok=True)
    print(f'out={out}')
    print(f'imagemagick={shutil.which("compare")}')
    print(subprocess.run(['compare', '-version'], capture_output=True,
                         text=True).stdout.splitlines()[0])
    print(f'A4 pt={A4_W:.4f}x{A4_H:.4f}  exact-px pt={EXACT_W:.4f}x{EXACT_H:.4f}')
    print(f'gate norm=resize {WIDTH}x{HEIGHT}! then crop '
          f'{WIDTH - 4}x{HEIGHT - 4}+{CROP}+{CROP}')
    print(f'metric=compare -metric RMSE, parenthesised quotient (0..1)')
    if mode == 'synthetic':
        rows = experiment_pipeline(out)
        render_rows, meta = experiment_renderers(out)
        rows.extend(render_rows)
        with open(os.path.join(out, 'provenance.json'), 'w') as handle:
            json.dump(meta, handle, indent=1)
        print('--- results ---')
        for name, value, raw, kind in rows:
            flag = 'FAIL' if value > 0.02 else 'ok'
            print(f'{flag:4} {value:.6f}  [{kind}]  {name}')
        return 0
    print('unknown mode', mode, file=sys.stderr)
    return 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        import traceback
        traceback.print_exc()
        sys.exit(2)
