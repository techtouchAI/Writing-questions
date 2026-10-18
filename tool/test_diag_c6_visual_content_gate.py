"""Negative tests for the vector content gate.

The metric must accept matching ink, including a heavier copy of the same
shapes, and reject a 1 px shift, a deleted band, and a 4 px rule move.
It must not treat page-level RMSE as the verdict.

Two families live here and are kept separate on purpose:

* SYNTHETIC scenes (this file's default) prove the metric's sensitivity on
  inputs whose cause is known by construction: a deleted text line, and a
  deleted small-but-meaningful equation (the class of ink a 19 px speck floor
  must never swallow).
* REAL-ARTIFACT injections (`RealArtifacts`, skipped without `C6_ARTIFACTS`)
  repeat the deletions on the actual fixture raster: proof that the gate
  rejects text and small-equation deletions on the real page imagery, not
  only on this model.
"""
import json
import os
import struct
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import visual_content_gate as gate  # noqa: E402


def write_png(path, width, height, gray):
    def chunk(tag, payload):
        return (struct.pack('>I', len(payload)) + tag + payload
                + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(gray[y * width:(y + 1) * width])
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b''))
    with open(path, 'wb') as handle:
        handle.write(png)


def scene(width=240, height=160, dx=0, delete=False, rule_dy=0):
    gray = [255] * (width * height)
    for i in range(6):
        y = 20 + i * 22
        if delete and i in (2, 3):
            continue
        for n in range(12):
            x0 = 30 + dx + n * 10
            for yy in range(y, y + 8):
                for x in range(x0, x0 + 4):
                    if 0 <= x < width:
                        gray[yy * width + x] = 0
    rule = 18 + rule_dy
    for x in range(30, 180):
        gray[rule * width + x] = 0
    return width, height, gray


class ContentGate(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _png(self, name, **kwargs):
        path = f'{self.tmp}/{name}.png'
        width, height, gray = scene(**kwargs)
        write_png(path, width, height, gray)
        return path

    def test_matching_pages_pass_and_reject_defects(self):
        path = self._png('a')
        status, line = gate.score_files(path, path)
        self.assertEqual(status, 0, line)
        self.assertIn('defects rejected', line)

    def test_a_one_pixel_shift_fails(self):
        status, line = gate.score_files(self._png('a'), self._png('b', dx=1))
        self.assertEqual(status, 1, line)
        self.assertIn('shift', line)

    def test_a_deleted_band_fails(self):
        status, line = gate.score_files(self._png('a'), self._png('b', delete=True))
        self.assertEqual(status, 1, line)
        self.assertTrue('strip' in line or 'rule' in line, line)

    def test_an_underline_move_fails(self):
        status, line = gate.score_files(
            self._png('a'), self._png('b', rule_dy=4))
        self.assertEqual(status, 1, line)
        self.assertTrue('rule' in line or 'strip' in line, line)

    def test_a_heavier_copy_of_the_same_shapes_passes(self):
        # Thicker stems: dilate the ink, which is what a heavier rasterizer
        # does, without moving the shapes.
        width, height, gray = scene()
        mask = [value < gate.INK_MAX for value in gray]
        thick = gate.dilate(mask, width, height, 1)
        heavier = [0 if value else 255 for value in thick]
        path_a = f'{self.tmp}/a.png'
        path_b = f'{self.tmp}/b.png'
        write_png(path_a, width, height, gray)
        write_png(path_b, width, height, heavier)
        status, line = gate.score_files(path_a, path_b, prove=False)
        self.assertEqual(status, 0, line)

    def test_a_page_without_a_rule_still_proves_an_underline(self):
        width, height, gray = scene()
        for x in range(width):
            gray[18 * width + x] = 255
        path = f'{self.tmp}/norule.png'
        write_png(path, width, height, gray)
        status, line = gate.score_files(path, path)
        self.assertEqual(status, 0, line)
        self.assertIn('defects rejected', line)
        self.assertNotIn('underline_absent', line)

    def test_a_19_pixel_speck_does_not_fail_the_page(self):
        width, height, gray = scene()
        other = list(gray)
        # A sparse strip can report a high uncovered fraction from a speck.
        # Official page 2 failed on 19 such pixels. That is not a deletion.
        for n in range(19):
            other[40 * width + (200 + n)] = 0
        path_a = f'{self.tmp}/a.png'
        path_b = f'{self.tmp}/b.png'
        write_png(path_a, width, height, gray)
        write_png(path_b, width, height, other)
        status, line = gate.score_files(path_a, path_b, prove=False)
        self.assertEqual(status, 0, line)

    def test_blank_pages_match_without_pretending_to_prove_defects(self):
        path = f'{self.tmp}/blank.png'
        write_png(path, 32, 32, [255] * (32 * 32))
        status, line = gate.score_files(path, path)
        self.assertEqual(status, 0, line)
        self.assertIn('no ink', line)


# --------------------------------------------------------------------------
# SYNTHETIC — حذف النصوص والمعادلات الصغيرة ذات الدلالة.
# --------------------------------------------------------------------------

def text_line_scene(with_equation=True):
    """Three text-like lines (broken stems, as words are) plus one small
    meaningful equation: a compact fraction glyph isolated between lines.

    The equation is deliberately small (~110 ink px in a 20x19 px box) but
    well above the speck floor (STRIP_MISS_PIXELS=80): the deletion of meaning
    must not be dismissed as rasteriser noise.
    """
    width, height = 240, 160
    gray = [255] * (width * height)

    def box(x0, y0, x1, y1, value=0):
        for y in range(y0, y1):
            for x in range(x0, x1):
                gray[y * width + x] = value

    # Rule row (kept from the standard scene: a page proves its underline).
    for x in range(30, 180):
        gray[12 * width + x] = 0
    # Text lines: stems 4x8 with 6 px gaps -- rows of broken ink like words.
    for y in (20, 64, 108):
        for n in range(12):
            box(30 + n * 10, y, 34 + n * 10, y + 8)
    # The small meaningful equation: a fraction (numerator, bar, denominator).
    if with_equation:
        box(150, 40, 154, 46)   # numerator stem
        box(157, 40, 161, 46)   # numerator stem
        box(149, 48, 167, 49)   # fraction bar
        box(150, 52, 154, 58)   # denominator stem
        box(157, 52, 161, 58)   # denominator stem
    return width, height, gray


class TextAndEquationDeletionTests(unittest.TestCase):
    """حذف نص كامل وحذف معادلة صغيرة ذات دلالة يُرفضان كليهما."""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, name, gray, width=240, height=160):
        path = f'{self.tmp}/{name}.png'
        write_png(path, width, height, gray)
        return path

    def test_deleting_a_text_line_is_rejected(self):
        width, height, full = text_line_scene()
        deleted = list(full)
        # The middle text line (y=64..71) erased entirely.
        for y in range(60, 76):
            for x in range(width):
                deleted[y * width + x] = 255
        status, line = gate.score_files(
            self._write('full', full), self._write('del', deleted))
        self.assertEqual(status, 1, 'حذف سطر نص كامل يجب أن يُرفض: ' + line)
        self.assertTrue('strip' in line or 'shift' in line, line)

    def test_deleting_a_small_meaningful_equation_is_rejected(self):
        width, height, full = text_line_scene()
        deleted = list(full)
        # Only the equation's ink removed: numerator, bar, denominator.
        for y in range(38, 60):
            for x in range(147, 169):
                deleted[y * width + x] = 255
        # The deletion itself is small: the speck floor must not swallow it.
        removed_ink = sum(
            1 for a, b in zip(full, deleted) if a < gate.INK_MAX <= b)
        self.assertGreaterEqual(
            removed_ink, gate.STRIP_MISS_PIXELS,
            'الحذف أقل من أرضية النقطة — المعادلة يجب أن تبقى صغيرة ولكن فوق الأرضية.')
        self.assertLessEqual(removed_ink, 220, 'المعادلة المفترضة صغيرة.')

        status, line = gate.score_files(
            self._write('eq-full', full), self._write('eq-del', deleted))
        self.assertEqual(
            status, 1,
            'حذف معادلة صغيرة ذات دلالة يجب ألا يُعامل كضجيج: ' + line)
        self.assertIn('strip', line)

    def test_the_speck_floor_still_ignores_noise(self):
        # الوجه الآخر للحد نفسه: نقطة ضجيج تحت الأرضية لا تُسقط صفحة.
        width, height, full = text_line_scene()
        noisy = list(full)
        for n in range(19):
            noisy[88 * width + (210 + n)] = 0
        status, line = gate.score_files(
            self._write('clean', full), self._write('noise', noisy), prove=False)
        self.assertEqual(status, 0, line)


def _text_line_band(gray, width, height):
    """(y0, y1) of the topmost dense text-like band of rows, or None."""
    rows = [
        sum(1 for x in range(width) if gray[y * width + x] < gate.INK_MAX)
        for y in range(height)
    ]
    band_start = None
    for y, ink in enumerate(rows):
        dense = ink >= max(24, width // 40)
        if dense and band_start is None:
            band_start = y
        elif not dense and band_start is not None:
            if 6 <= y - band_start <= 40:
                total = sum(rows[band_start:y])
                if total >= 300:
                    return band_start, y
            band_start = None
    return None


class RealArtifacts(unittest.TestCase):
    """Deletion injections on the fixture's own preview raster.

    Skipped locally without `C6_ARTIFACTS`; in CI these erase a real text
    line and a real small equation from the produced page imagery, so the
    gate's rejection is proven on the real form, not only on a model.
    """

    def _root(self):
        root = os.environ.get('C6_ARTIFACTS', 'build/visual_parity')
        if not os.path.exists(os.path.join(root, 'preview_page_1.png')):
            self.skipTest('real artifacts not available')
        return root

    def _score(self, gray, deleted, width, height):
        mask_a = gate.ink_mask(gray, width, height)
        mask_b = gate.ink_mask(deleted, width, height)
        return gate.score_masks(mask_a, mask_b, width, height)

    def test_real_text_line_deletion_is_rejected(self):
        root = self._root()
        width, height, gray = gate.read_png(
            os.path.join(root, 'preview_page_1.png'))
        band = _text_line_band(gray, width, height)
        self.assertIsNotNone(band, 'fixture page 1 has no measurable text band')
        y0, y1 = band
        deleted = list(gray)
        for y in range(max(0, y0 - 1), min(height, y1 + 1)):
            for x in range(width):
                deleted[y * width + x] = 255
        result = self._score(gray, deleted, width, height)
        self.assertFalse(
            result['ok'],
            'حذف سطر نص حقيقي من صفحة التركيبة يجب أن يُرفض: '
            + '; '.join(result['reasons']))

    def test_real_small_equation_deletion_is_rejected(self):
        root = self._root()
        positions = os.path.join(
            root, 'c6diag', 'text_positions', 'preview_positions.json')
        if not os.path.exists(positions):
            self.skipTest('positions probe not available')
        with open(positions, encoding='utf-8') as handle:
            data = json.load(handle)
        checked = 0
        for page in data.get('pages', []):
            page_no = int(page['page'])
            preview = os.path.join(root, f'preview_page_{page_no}.png')
            if not os.path.exists(preview):
                continue
            width, height, gray = gate.read_png(preview)
            sx = width / float(page['widthPt'])
            sy = height / float(page['heightPt'])
            for record in page.get('lines', []):
                baseline = float(record['baselinePt']) * sy
                for run in record.get('runs', []):
                    if not run.get('isMath'):
                        continue
                    run_width = max(2.0, float(run['widthPt']) * sx)
                    height_pt = float(run.get('heightPt') or 0) or (
                        float(run.get('fontSizePt') or 12) * 1.2)
                    run_height = height_pt * sy
                    if run_width > 140 or run_height > 60:
                        continue  # ليست معادلة صغيرة
                    x0 = int(float(run['xPt']) * sx) - 2
                    x1 = int(float(run['xPt']) * sx + run_width) + 2
                    y0 = int(baseline - run_height * 1.1) - 2
                    y1 = int(baseline + run_height * 0.5) + 2
                    x0, y0 = max(0, x0), max(0, y0)
                    x1, y1 = min(width, x1), min(height, y1)
                    if x1 - x0 < 3 or y1 - y0 < 3:
                        continue
                    deleted = list(gray)
                    for y in range(y0, y1):
                        for x in range(x0, x1):
                            deleted[y * width + x] = 255
                    ink_here = sum(
                        1 for y in range(y0, y1) for x in range(x0, x1)
                        if gray[y * width + x] < gate.INK_MAX)
                    if not 80 <= ink_here <= 800:
                        continue  # تحت أرضية الحساسية أو ليست «صغيرة»
                    result = self._score(gray, deleted, width, height)
                    self.assertFalse(
                        result['ok'],
                        f'حذف معادلة صغيرة حقيقية (صفحة {page_no}، '
                        f'حبر {ink_here} بكسل) يجب أن يُرفض: '
                        + '; '.join(result['reasons']))
                    checked += 1
                    if checked >= 3:
                        return
        if checked == 0:
            self.skipTest('fixture has no small equation in the sensitivity band')


if __name__ == '__main__':
    unittest.main()
