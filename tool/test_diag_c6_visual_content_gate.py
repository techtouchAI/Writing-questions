"""Negative tests for the vector content gate.

The metric must accept matching ink, including a heavier copy of the same
shapes, and reject a 1 px shift, a deleted band, and a 4 px rule move.
It must not treat page-level RMSE as the verdict.
"""
import struct
import unittest
import zlib

import visual_content_gate as gate


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


if __name__ == '__main__':
    unittest.main()
