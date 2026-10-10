"""Unit tests for the C6 non-text excess diagnostic (synthetic PDFs and arrays only).

Run: python -m unittest tool/test_diag_c6_nontext_excess.py
Controls: identical renders give no Preview-only ink. Injected Preview-only
differences must land in the right class: a halo next to glyphs is
text_adjacent; a thicker PDF rule is drawing_adjacent; a box with no PDF
counterpart is unexplained.
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_nontext_excess as nt  # noqa: E402
import diag_c6_text_geometry as geo  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

WORDS = [(60, 120, "Hello", 16), (200, 120, "world", 16), (60, 200, "Sphinx", 20), (60, 260, "quick", 14), (200, 260, "brown", 14)]
RULE_PT = ((40, 700), (500, 700))
BOX_PT = (400, 780, 430, 800)


def _build(preview):
    d = pymupdf.open()
    p = d.new_page(width=595.28, height=841.89)
    for x, y, t, fs in WORDS:
        p.insert_text((x, y), t, fontsize=fs, fontname="helv", color=(0, 0, 0))
    if not preview:
        p.draw_line(*RULE_PT, color=(0, 0, 0), width=0.8)
    else:
        p.draw_line(*RULE_PT, color=(0, 0, 0), width=1.6)  # thicker in the Preview
        p.draw_rect(pymupdf.Rect(*BOX_PT), color=None, fill=(0.5, 0.5, 0.5))  # no PDF counterpart
        for x, y, t, fs in WORDS:  # halo 1-2 px outside the glyph box
            w = len(t) * fs * 0.55
            p.draw_rect(pymupdf.Rect(x - 2.5, y - fs * 0.95, x + w + 1.5, y + fs * 0.3), color=(0.6, 0.6, 0.6), width=0.5)
    return d


def _pixels(doc):
    pg = doc[0]
    sx, sy = geo.transform(pg.rect.width, pg.rect.height)
    return geo.mupdf_render(pg, sx, sy).astype(np.float64) / 255.0, sx, sy


class ChebyshevTest(unittest.TestCase):
    def test_distance_is_chebyshev(self):
        m = np.zeros((11, 11), dtype=bool)
        m[5, 5] = True
        d = nt.chebyshev_distance(m, maxd=8)
        self.assertEqual(d[5, 9], 4)
        self.assertEqual(d[0, 0], 5)  # diagonal counts as one step
        self.assertEqual(d[5, 5], 0)

    def test_cap_reports_beyond_range(self):
        m = np.zeros((20, 20), dtype=bool)
        m[0, 0] = True
        d = nt.chebyshev_distance(m, maxd=4)
        self.assertEqual(d[19, 19], 5)


class ComponentTest(unittest.TestCase):
    def test_diagonal_touch_is_one_component(self):
        m = np.zeros((5, 5), dtype=bool)
        m[1, 1] = True
        m[2, 2] = True
        self.assertEqual(len(nt.label_components(m)), 1)

    def test_one_pixel_gap_separates_components(self):
        m = np.zeros((5, 7), dtype=bool)
        m[1, 1] = True
        m[1, 3] = True
        self.assertEqual(len(nt.label_components(m)), 2)


class MaskTest(unittest.TestCase):
    def test_exact_map_uses_page_scale(self):
        sx, sy = geo.transform(595.28, 841.89)
        m = nt.mask_from_pt((1119, 790), [(400, 400, 420, 420)], sx, sy)
        ys, xs = np.nonzero(m)
        self.assertEqual(xs.min(), int(np.floor(400 * sx - 2)))
        self.assertEqual(xs.max(), int(np.ceil(420 * sx - 2)) - 1)
        self.assertEqual(ys.min(), int(np.floor(400 * sy - 2)))

    def test_exact_map_differs_from_four_thirds_far_from_origin(self):
        sx, sy = geo.transform(595.28, 841.89)
        exact = nt.mask_from_pt((1119, 790), [(560, 800, 580, 820)], sx, sy)
        approx = resid.box_mask((1119, 790), [(560, 800, 580, 820)])
        self.assertGreater(int(np.sum(exact ^ approx)), 0)


class AnalysePageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        vec = os.path.join(cls.tmp, "vector.pdf")
        d = _build(False)
        d.save(vec)
        cls.stripped = os.path.join(cls.tmp, "notext.pdf")
        resid.write_pdf_stripped(vec, cls.stripped)
        cls.vector_doc = pymupdf.open(vec)
        cls.pdf_f, cls.sx, cls.sy = _pixels(cls.vector_doc)
        cls.notext_f, _, _ = _pixels(pymupdf.open(cls.stripped))
        cls.prev_f, _, _ = _pixels(_build(True))

    def _analyse(self, prev):
        return nt.analyse_page(self.vector_doc[0], prev, self.pdf_f, self.notext_f, self.sx, self.sy)

    def test_text_removal_changes_only_the_mask(self):
        r = self._analyse(self.pdf_f)
        self.assertEqual(r["validation_outside_changed"], 0)
        self.assertGreater(r["validation_inside_changed"], 0)

    def test_identical_preview_has_no_excess(self):
        r = self._analyse(self.pdf_f)
        self.assertEqual(r["excess_pixels"], 0)
        self.assertEqual(r["components"], 0)

    def test_injected_differences_land_in_their_classes(self):
        r = self._analyse(self.prev_f)
        mass = r["component_class_mass"]
        self.assertGreater(mass.get("text_adjacent", 0.0), 0.0)
        self.assertGreater(mass.get("drawing_adjacent", 0.0), 0.0)
        self.assertGreater(mass.get("unexplained", 0.0), 0.0)

    def test_box_mass_matches_its_ink(self):
        r = self._analyse(self.prev_f)
        x0, y0, x1, y1 = BOX_PT
        box_px = (x1 - x0) * self.sx * (y1 - y0) * self.sy
        expected = 0.5 * box_px  # grey 0.5 fill, ink 0.5 per pixel
        got = r["component_class_mass"].get("unexplained", 0.0)
        self.assertAlmostEqual(got / expected, 1.0, delta=0.15)

    def test_halo_is_next_to_text(self):
        r = self._analyse(self.prev_f)
        self.assertGreater(r["excess_cum_within_px"]["3"], 0.0)
        # The halo sits 1-2 pt outside each box, so its mass is within a few px.
        halo_share = r["excess_cum_within_px"]["8"]
        self.assertGreater(halo_share, 0.0)


if __name__ == "__main__":
    unittest.main()
