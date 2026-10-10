"""Tests for tool/diag_c6_text_residual.py (C6-DIAG-5, diagnostic only).

Run: python3 -m unittest discover -s tool -p 'test_diag_c6_*.py'
They use synthetic PDFs and exact expected values. Rendering and ImageMagick are
not used here; the CI diagnostic step covers the real pipeline.
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_text_residual as d  # noqa: E402


class StripTextTest(unittest.TestCase):
    def test_removes_only_text_objects_byte_exact(self):
        before = b"q 1 0 0 1 10 10 cm 0 0 1 RG 2 w 0 0 50 50 re S Q "
        text = b"BT /F1 12 Tf 0 0 Td [<0024>] TJ ET "
        after = b"0 0 0 rg 5 5 10 10 re f"
        new, st = d.strip_text(before + text + after)
        # The span ends at ET; the space after ET stays, so the join has two spaces.
        self.assertEqual(new, before + b" " + after)
        self.assertEqual(st["text_objects"], 1)
        self.assertEqual(st["show_ops_removed"], 1)
        self.assertEqual(st["fonts_tf"], {"/F1": 1})
        self.assertEqual(st["dropped_bytes"], len(text.rstrip()))
        self.assertEqual(st["unclosed_BT"], 0)

    def test_two_text_objects_and_unclosed(self):
        raw = b"BT (a) Tj ET 1 0 0 rg BT (b) Tj (c) Tj ET BT (open) Tj"
        new, st = d.strip_text(raw)
        self.assertEqual(new, b" 1 0 0 rg  BT (open) Tj")
        self.assertEqual(st["text_objects"], 2)
        self.assertEqual(st["show_ops_removed"], 3)
        self.assertEqual(st["unclosed_BT"], 1)

    def test_no_text_is_identity(self):
        raw = b"0 0 1 RG 0 0 m 90 0 l S"
        new, st = d.strip_text(raw)
        self.assertEqual(new, raw)
        self.assertEqual(st["dropped_bytes"], 0)


class PdfTextTest(unittest.TestCase):
    def _pdf(self, path):
        doc = pymupdf.open()
        page = doc.new_page(width=595.28, height=841.89)
        page.insert_text((100, 100), "Hello", fontsize=12, fontname="helv")
        page.draw_rect(pymupdf.Rect(200, 200, 260, 240), color=(0, 0, 0), width=2)
        doc.save(path)
        doc.close()

    def test_strip_removes_text_keeps_graphics(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src.pdf")
            dst = os.path.join(tmp, "dst.pdf")
            self._pdf(src)
            before = pymupdf.open(src)[0]
            self.assertEqual(before.get_text().strip(), "Hello")
            self.assertGreater(len(before.get_drawings()), 0)
            stats = d.write_pdf_stripped(src, dst)
            self.assertEqual(len(stats), 1)
            self.assertGreaterEqual(stats[0]["text_objects"], 1)
            after = pymupdf.open(dst)[0]
            self.assertEqual(after.get_text().strip(), "")
            self.assertGreater(len(after.get_drawings()), 0)

    def test_text_lines_and_chars(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src.pdf")
            self._pdf(src)
            lines = d.text_lines(pymupdf.open(src)[0])
            self.assertEqual(len(lines), 1)
            chars = lines[0]["chars"]
            self.assertEqual(len(chars), 5)
            x0, y0, x1, y1 = chars[0]["bbox"]
            self.assertAlmostEqual(x0, 100, delta=2)
            self.assertLess(y0, 100)
            self.assertGreater(y1, 100 - 12)
            self.assertFalse(lines[0]["rtl"])


class MaskTest(unittest.TestCase):
    def test_box_mask_exact_pixels(self):
        shape = (1119, 790)
        m = d.box_mask(shape, [(10, 10, 20, 20)])
        # 10 pt -> 13.33 px, 20 pt -> 26.67 px; minus the 2 px crop.
        a, b = int(np.floor(10 * d.PX)) - d.CO, int(np.ceil(20 * d.PX)) - d.CO
        self.assertEqual((a, b), (11, 25))
        self.assertEqual(int(m.sum()), (b - a) ** 2)
        self.assertTrue(m[a:b, a:b].all())
        self.assertEqual(int(m[:a].sum()), 0)

    def test_box_mask_clipped_to_image(self):
        m = d.box_mask((50, 60), [(-10, -10, 1000, 1000)])
        self.assertEqual(int(m.sum()), 50 * 60)

    def test_box_mask_dilate(self):
        plain = d.box_mask((50, 60), [(30, 30, 40, 40)])
        grown = d.box_mask((50, 60), [(30, 30, 40, 40)], dilate=1)
        self.assertTrue(np.all(grown[plain]))
        self.assertGreater(int(grown.sum()), int(plain.sum()))


class DecomposeTest(unittest.TestCase):
    def test_parts_add_up_to_total(self):
        rng = np.random.default_rng(1)
        v = rng.random((40, 50, 3)).astype(np.float32)
        p = rng.random((40, 50, 3)).astype(np.float32)
        t = np.zeros((40, 50), bool)
        t[5:15, 5:20] = True
        img = np.zeros((40, 50), bool)
        img[20:30, 0:25] = True
        img &= ~t
        other = ~(t | img)
        out = d.decompose(v, p, {"text": t, "image": img, "other": other})
        total_sq = out["rmse_total"] ** 2
        parts_sq = sum(part["rmse_part"] ** 2 for part in out["parts"].values())
        self.assertAlmostEqual(total_sq, parts_sq, places=10)
        shares = sum(part["share"] for part in out["parts"].values())
        self.assertAlmostEqual(shares, 1.0, places=10)

    def test_matches_direct_rmse(self):
        v = np.zeros((4, 4, 3), np.float32)
        p = np.zeros((4, 4, 3), np.float32)
        p[0, 0, :] = 1.0  # one pixel, all channels wrong by 1
        full = np.ones((4, 4), bool)
        out = d.decompose(v, p, {"all": full})
        self.assertAlmostEqual(out["rmse_total"], np.sqrt(3 / 48), places=10)

    def test_overlapping_masks_rejected(self):
        v = np.zeros((4, 4, 3), np.float32)
        m = np.ones((4, 4), bool)
        with self.assertRaises(ValueError):
            d.decompose(v, v, {"a": m, "b": m})

    def test_text_removal_invariance_check_detects_leak(self):
        full = np.zeros((10, 10, 3), np.uint8)
        notext = full.copy()
        notext[0, 0] = 9  # a change outside the text mask
        t = np.zeros((10, 10), bool)
        t[5:, 5:] = True
        diff_any = np.any(full != notext, axis=2)
        self.assertEqual(int(np.sum(diff_any & ~t)), 1)


class LoadRgbTest(unittest.TestCase):
    def test_gray_png_expands_to_rgb(self):
        # pdftoppm writes gray PNGs for pages without colour; they must match RGB.
        with tempfile.TemporaryDirectory() as tmp:
            png = os.path.join(tmp, "gray.png")
            pix = pymupdf.Pixmap(pymupdf.csGRAY, pymupdf.IRect(0, 0, 4, 3), 0)
            pix.set_pixel(1, 1, (128,))
            pix.save(png)
            arr, size, note = d.load_rgb(png)
            self.assertEqual(arr.shape, (3, 4, 3))
            self.assertEqual(size, (4, 3))
            self.assertEqual(int(arr[1, 1, 0]), 128)
            self.assertTrue(np.all(arr[..., 0] == arr[..., 1]))
            self.assertTrue(np.all(arr[..., 1] == arr[..., 2]))
            self.assertIn("gray replicated", note)

    def test_rgba_drops_alpha_and_reports_opacity(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = os.path.join(tmp, "rgba.png")
            pix = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 2, 2), True)
            pix.clear_with(255)
            pix.save(png)
            arr, _, note = d.load_rgb(png)
            self.assertEqual(arr.shape, (2, 2, 3))
            self.assertIn("alpha all 255", note)


class ShiftProbeTest(unittest.TestCase):
    def test_finds_known_shift(self):
        rng = np.random.default_rng(7)
        p = rng.random((60, 80, 3)).astype(np.float32)
        v = np.roll(p, shift=(1, 2), axis=(0, 1))  # v[y, x] = p[y-1, x-2]
        rows = d.line_shift_probe(v, p, [(20, 20, 50, 40)], maxs=3, pad=2)
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["dx"], rows[0]["dy"]), (2, 1))
        self.assertAlmostEqual(rows[0]["best"], 0.0, places=7)
        self.assertGreater(rows[0]["err0"], 0.01)

    def test_zero_shift_identity(self):
        rng = np.random.default_rng(3)
        p = rng.random((60, 80, 3)).astype(np.float32)
        rows = d.line_shift_probe(p.copy(), p, [(20, 20, 50, 40)])
        self.assertEqual((rows[0]["dx"], rows[0]["dy"]), (0, 0))
        self.assertEqual(rows[0]["err0"], 0.0)

    def test_lines_too_close_to_edge_skipped(self):
        p = np.ones((20, 20, 3), np.float32) * 0.5
        self.assertEqual(d.line_shift_probe(p, p, [(0, 0, 10, 10)]), [])

    def test_pooled_summary(self):
        rows = [
            {"err0": 0.04, "best": 0.01, "dx": 1, "dy": 0},
            {"err0": 0.02, "best": 0.02, "dx": 0, "dy": 0},
        ]
        s = d.pooled_probe(rows)
        self.assertEqual(s["lines"], 2)
        self.assertEqual(s["zero_is_best"], 1)
        self.assertAlmostEqual(s["optimistic_reduction"], 1 - 0.03 / 0.06)


if __name__ == "__main__":
    unittest.main()
