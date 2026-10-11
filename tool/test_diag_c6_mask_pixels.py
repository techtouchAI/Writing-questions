"""Tests for tool/diag_c6_mask_pixels.py (C6-DIAG-13). Synthetic known-answer cases only.

Expectations are written down before the run. A failing case means the attribution rule is
wrong for that case, and the rule is not to be changed to make the case pass.
Run from the repository root:  python3 -m unittest discover -s tool -p 'test_diag_c6_*.py'
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_mask_pixels as mp  # noqa: E402
import diag_c6_mask_validity as mv  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

CO, CW, CH = resid.CO, resid.CW, resid.CH


def save_crop(arr01, path):
    arr = np.clip(np.round(arr01 * 255.0), 0, 255).astype(np.uint8)
    pix = pymupdf.Pixmap(pymupdf.csRGB, CW, CH, arr.tobytes(), False)
    pix.save(path)
    return path


class PixelAttributionKnownCases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="c6mp_")
        t = cls.tmp
        # K1: text only.
        cls.k1_pdf = mv.build_text_page(os.path.join(t, "k1.pdf"))
        cls.k1_full = mv.render_gate(pymupdf.open(cls.k1_pdf))
        resid.write_pdf_stripped(cls.k1_pdf, os.path.join(t, "k1_s.pdf"))
        cls.k1_notext = mv.render_gate(pymupdf.open(os.path.join(t, "k1_s.pdf")))
        cls.k1_full_png = save_crop(cls.k1_full, os.path.join(t, "k1_full.png"))
        cls.k1_notext_png = save_crop(cls.k1_notext, os.path.join(t, "k1_notext.png"))
        cls.k1 = mp.analyse(cls.k1_pdf, cls.k1_full_png, cls.k1_notext_png)

        # K2: non-text rectangle inside BT..ET.
        cls.k2_pdf = mv.build_bt_painting_page(os.path.join(t, "k2.pdf"))
        resid.write_pdf_stripped(cls.k2_pdf, os.path.join(t, "k2_s.pdf"))
        cls.k2_full = mv.render_gate(pymupdf.open(cls.k2_pdf))
        cls.k2_notext = mv.render_gate(pymupdf.open(os.path.join(t, "k2_s.pdf")))
        cls.k2 = mp.analyse(
            cls.k2_pdf,
            save_crop(cls.k2_full, os.path.join(t, "k2_full.png")),
            save_crop(cls.k2_notext, os.path.join(t, "k2_notext.png")),
        )

    def test_k1_text_only_has_no_nontext_or_unexplained_leaks(self):
        c = self.k1["classes_outside_exact"]
        self.assertEqual(c["non_text_drawing"], 0)
        self.assertEqual(c["unexplained"], 0)
        # Every leak is a boundary effect within AA_TOL of a nominal glyph box.
        for p in self.k1["pixels"]:
            self.assertEqual(p["class"], "aa_boundary")
            self.assertLessEqual(p["dist_to_glyph_box_px"], mp.AA_TOL)

    def test_k2_nontext_inside_bt_is_attributed_to_drawing(self):
        # Every changed pixel outside the exact mask is the removed rectangle: all must
        # fall in its drawing footprint, none unexplained.
        self.assertGreater(self.k2["changed_outside_exact"], 1000)
        self.assertEqual(self.k2["classes_outside_exact"]["unexplained"], 0)
        self.assertEqual(self.k2["classes_outside_exact"]["aa_boundary"], 0)
        self.assertEqual(self.k2["classes_outside_exact"]["non_text_drawing"], self.k2["changed_outside_exact"])

    def test_k3_planted_pixel_far_from_text_is_unexplained(self):
        t = self.tmp
        notext = self.k1_notext.copy()
        notext[5, 5] = notext[5, 5] * 0.5  # far from any glyph, outside the text mask
        p_notext = save_crop(notext, os.path.join(t, "k3_notext.png"))
        r = mp.analyse(self.k1_pdf, self.k1_full_png, p_notext)
        self.assertEqual(r["classes_outside_exact"]["unexplained"], 1)
        unexpl = [p for p in r["pixels"] if p["class"] == "unexplained"]
        self.assertEqual((unexpl[0]["x_gate"], unexpl[0]["y_gate"]), (5, 5))

    def test_k4_pixel_two_px_from_a_glyph_box_is_unexplained(self):
        # Plant one changed pixel 2 device px to the right of a glyph box, on a row inside it.
        pdf = self.k1_pdf
        page = pymupdf.open(pdf)[0]
        sx = resid.W / page.rect.width
        sy = resid.H / page.rect.height
        chars = [c for ln in resid.text_lines(page) for c in ln["chars"]]
        boxes = [c["bbox"] for c in chars]
        # Use the right-most glyph: nothing follows it on its line, so the pixel 2 px to the
        # right of its box lies in no other glyph box (checked below, not assumed).
        x0, y0, x1, y1 = max(boxes, key=lambda b: b[2])
        gx = int(np.ceil(x1 * sx)) + 2 - CO  # 2 px beyond the box edge
        gy = int((y0 + y1) / 2 * sy) - CO
        self.assertGreaterEqual(mp._nearest_box_px(gx, gy, boxes, sx, sy), 1.0)  # precondition
        notext = self.k1_notext.copy()
        notext[gy, gx] = [0.0, 0.0, 0.0]
        p_notext = save_crop(notext, os.path.join(self.tmp, "k4_notext.png"))
        r = mp.analyse(pdf, self.k1_full_png, p_notext)
        hit = [p for p in r["pixels"] if (p["x_gate"], p["y_gate"]) == (gx, gy)]
        self.assertEqual(len(hit), 1)
        self.assertEqual(hit[0]["class"], "unexplained")
        self.assertGreaterEqual(hit[0]["dist_to_glyph_box_px"], 1.0)

    def test_k5_transform_px_only_matches_independent_count(self):
        page = pymupdf.open(self.k1_pdf)[0]
        sx, sy = resid.W / page.rect.width, resid.H / page.rect.height
        chars = [c for ln in resid.text_lines(page) for c in ln["chars"]]
        boxes = [c["bbox"] for c in chars]
        m_exact = mv.exact_mask((CH, CW), boxes, sx, sy, CO)
        m_px = resid.box_mask((CH, CW), boxes)
        diff = np.any(self.k1_full != self.k1_notext, axis=2)
        expected = int((diff & m_exact & ~m_px).sum())
        self.assertEqual(self.k1["transform_px_only"], expected)

    def test_k6_exact_outside_count_matches_mask_validity_module(self):
        # Same pair of renders and same exact mask as DIAG-10's T1: the counts must agree.
        page = pymupdf.open(self.k1_pdf)[0]
        sx, sy = resid.W / page.rect.width, resid.H / page.rect.height
        boxes = [c["bbox"] for ln in resid.text_lines(page) for c in ln["chars"]]
        m_exact = mv.exact_mask((CH, CW), boxes, sx, sy, CO)
        diff = np.any(self.k1_full != self.k1_notext, axis=2)
        self.assertEqual(self.k1["changed_outside_exact"], int((diff & ~m_exact).sum()))


if __name__ == "__main__":
    unittest.main()
