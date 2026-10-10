"""Unit tests for the C6 text-geometry diagnostic (synthetic PDFs and arrays only).

Run: python -m unittest tool/test_diag_c6_text_geometry.py
Controls: the same-geometry pair must read slope 1 and intercept 0; a known
3% scale must read slope ~1.03 with intercept ~0; darker edges with no
geometry change must read slope ~1 with a positive intercept (bleed), not a
size change. These are validity checks of the method, not fixture tuning.
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_text_geometry as g  # noqa: E402


def _doc(words, mult=1.0):
    d = pymupdf.open()
    p = d.new_page(width=595.28, height=841.89)
    for x, y, text, size, colour in words:
        p.insert_text((x, y), text, fontsize=size * mult, fontname="helv", color=colour)
    return d


def _render(d):
    pg = d[0]
    sx, sy = g.transform(pg.rect.width, pg.rect.height)
    return g.mupdf_render(pg, sx, sy).astype(np.float64) / 255.0


def _gamma(rgb, gamma):
    """Same geometry, darker antialiasing: coverage**gamma on black ink over white."""
    white = np.ones(3)
    black = np.zeros(3)
    a = np.clip((rgb - white) @ (black - white) / ((black - white) @ (black - white)), 0, 1)
    return white + (a ** gamma)[..., None] * (black - white)


# A 60-word layout with rows 40 pt apart, so that word windows do not touch.
_RNG = np.random.default_rng(1)
_TXT = ["Hello", "world", "Sphinx", "quick", "brown", "jumps", "over", "lazy", "dog", "pack", "my", "box", "with", "five", "dozen", "liquor"]
LAYOUT = []
for _k in range(60):
    LAYOUT.append(
        (
            40 + (_k % 3) * 190 + float(_RNG.uniform(0, 6)),
            60 + (_k // 3) * 40.0 + float(_RNG.uniform(0, 2)),
            _TXT[_k % len(_TXT)],
            float(_RNG.integers(10, 22)),
            (0, 0, 0),
        )
    )


class TransformTest(unittest.TestCase):
    def test_scale_is_the_resize_not_four_thirds(self):
        sx, sy = g.transform(595.28, 841.89)
        self.assertAlmostEqual(sx, 794 / 595.28)
        self.assertAlmostEqual(sy, 1123 / 841.89)
        self.assertNotAlmostEqual(sx, 4 / 3, places=4)

    def test_crop_offset_and_box(self):
        sx, sy = g.transform(100, 200)
        self.assertEqual(g.to_crop(0, 0, sx, sy), (-2.0, -2.0))
        box = g.box_to_crop((10, 20, 30, 40), sx, sy)
        self.assertAlmostEqual(box[0], 10 * sx - 2)
        self.assertAlmostEqual(box[3], 40 * sy - 2)

    def test_window_leaves_image(self):
        self.assertIsNone(g.window_of((0, 0, 10, 10), 3, (100, 100)))
        self.assertEqual(g.window_of((10, 10, 20, 20), 3, (100, 100)), (7, 23, 7, 23))


class CoverageTest(unittest.TestCase):
    def test_recovers_known_alpha(self):
        bg = np.array([0.9, 0.9, 0.9])
        fg = np.array([0.1, 0.2, 0.6])
        alpha = np.linspace(0, 1, 12).reshape(3, 4)
        img = bg + alpha[..., None] * (fg - bg)
        cov = g.coverage(img, bg, fg)
        np.testing.assert_allclose(cov, alpha, atol=1e-9)

    def test_no_contrast_is_none(self):
        c = np.array([0.5, 0.5, 0.5])
        self.assertIsNone(g.coverage(np.zeros((2, 2, 3)), c, c))


class RunsExtentTest(unittest.TestCase):
    def test_subpixel_edges_of_a_single_run(self):
        p = [0, 0, 0.2, 0.6, 1.0, 0.6, 0.2, 0, 0]
        ext = g.extent(p, 0.5)
        # Crossings: between pixels 2 and 3 (index 2.75) and between 5 and 6 (index 5.25).
        self.assertAlmostEqual(ext[0], 2.75 + 0.5)
        self.assertAlmostEqual(ext[1], 5.25 + 0.5)

    def test_hard_block_width_is_exact(self):
        p = np.zeros(40)
        p[10:30] = 1.0
        ext = g.extent(p, 0.5)
        self.assertAlmostEqual(ext[1] - ext[0], 20.0)

    def test_half_covered_edge_pixels_count_as_half(self):
        p = np.zeros(40)
        p[10:30] = 1.0
        p[9] = 0.5
        p[30] = 0.5
        ext = g.extent(p, 0.5)
        self.assertAlmostEqual(ext[1] - ext[0], 21.0)

    def test_two_runs_are_reported_separately(self):
        p = [0, 1, 1, 0, 0, 1, 1, 0]
        runs, touches = g.runs_extent(p, 0.5)
        self.assertFalse(touches)
        self.assertEqual(len(runs), 2)

    def test_run_touching_border_is_flagged(self):
        runs, touches = g.runs_extent([1, 1, 0, 0], 0.5)
        self.assertTrue(touches)
        self.assertIsNone(g.extent([1, 1, 0, 0], 0.5))


class OverhangTest(unittest.TestCase):
    def test_ink_beyond_box(self):
        cov = np.zeros((10, 10))
        cov[2:8, 1:9] = 1.0  # ink columns 1..8, rows 2..7 (inclusive)
        o = g.overhang(cov, (3, 3, 7, 7))  # box columns 3..6, rows 3..6 (edges at 3 and 7)
        self.assertEqual(o["left"], 2.0)  # ink edge 1, box edge 3
        self.assertEqual(o["right"], 2.0)  # ink edge 9 (last pixel 8 + 1), box edge 7
        self.assertEqual(o["top"], 1.0)  # ink edge 2, box edge 3
        self.assertEqual(o["bottom"], 1.0)  # ink edge 8, box edge 7


class RegressionTest(unittest.TestCase):
    def test_scale_has_slope_and_no_intercept(self):
        x = np.linspace(20, 90, 30)
        s, i, n = g.regression(np.stack([x, 1.03 * x], axis=1))
        self.assertAlmostEqual(s, 1.03, places=9)
        self.assertAlmostEqual(i, 0.0, places=6)

    def test_bleed_has_intercept_and_unit_slope(self):
        x = np.linspace(20, 90, 30)
        s, i, n = g.regression(np.stack([x, x + 0.4], axis=1))
        self.assertAlmostEqual(s, 1.0, places=9)
        self.assertAlmostEqual(i, 0.4, places=6)

    def test_bootstrap_is_reproducible(self):
        rows = np.arange(10, dtype=float)
        a = g.boot_ci(rows, lambda z: float(np.mean(z)), b=50)
        b = g.boot_ci(rows, lambda z: float(np.mean(z)), b=50)
        self.assertEqual(a, b)


class PdfWordsTest(unittest.TestCase):
    def test_words_split_at_spaces(self):
        d = _doc([(40, 100, "Ab cd", 12, (0, 0, 0))])
        words = g.pdf_words(d[0])
        self.assertEqual([w["text"] for w in words], ["Ab", "cd"])
        self.assertEqual(words[0]["script"], "latin")
        self.assertEqual(len(words[0]["color"]), 3)

    def test_colour_change_splits_a_word(self):
        d = pymupdf.open()
        p = d.new_page(width=300, height=300)
        p.insert_text((20, 100), "Ab", fontsize=12, fontname="helv", color=(1, 0, 0))
        p.insert_text((50, 100), "cd", fontsize=12, fontname="helv", color=(0, 0, 1))
        words = g.pdf_words(p)
        self.assertEqual(len(words), 2)
        self.assertNotEqual(words[0]["color"], words[1]["color"])


class MeasureTest(unittest.TestCase):
    def test_block_width_and_height_exact(self):
        cov = np.zeros((30, 40))
        cov[5:15, 10:30] = 1.0
        m = g.measure_side(cov)
        self.assertAlmostEqual(m["w"][0.5], 20.0)
        self.assertAlmostEqual(m["h"][0.5], 10.0)
        self.assertAlmostEqual(m["ink"], 200.0)

    def test_bounds_touching_window_edge_give_none(self):
        cov = np.zeros((30, 40))
        cov[:, 0:5] = 1.0
        m = g.measure_side(cov)
        self.assertIsNone(m["w"][0.5])


class AnalyseTest(unittest.TestCase):
    def _pair_arrays(self, words_pt, mult=1.0):
        ref_doc = _doc(words_pt, 1.0)
        sub_doc = _doc(words_pt, mult)
        ref = _render(ref_doc)
        sub = _render(sub_doc)
        pg = ref_doc[0]
        words, drawings, images, (sx, sy), _ = g.page_inputs(pg)
        return words, drawings, images, ref, sub

    def test_neighbour_words_are_excluded(self):
        words = [
            (60, 120, "Hello", 16, (0, 0, 0)),
            (61, 121, "world", 16, (0, 0, 0)),  # overlaps the first word's box
        ]
        w, dr, im, ref, sub = self._pair_arrays(words)
        recs, reasons = g.analyse_pair(w, dr, im, ref, sub)
        self.assertEqual(reasons["neighbour_word"], 2)
        self.assertTrue(all(r["excluded"] == "neighbour_word" for r in recs))

    def test_blank_reference_is_low_ink(self):
        words = [(60, 120, "Hello", 16, (0, 0, 0))]
        w, dr, im, ref, sub = self._pair_arrays(words)
        blank = np.ones_like(ref)
        recs, reasons = g.analyse_pair(w, dr, im, blank, sub)
        self.assertEqual(reasons["low_ink"], 1)

    def test_identical_pair_gives_unit_ratios(self):
        words = [(60, 120, "Hello", 16, (0, 0, 0)), (200, 120, "world", 16, (0, 0, 0)), (60, 200, "Sphinx", 16, (0, 0, 0))]
        w, dr, im, ref, sub = self._pair_arrays(words)
        recs, reasons = g.analyse_pair(w, dr, im, ref, sub)
        self.assertEqual(sum(1 for r in recs if r["excluded"] is None), 3)
        s = g.summarise(recs, g.line_measures(recs, w, ref, sub), [], "same")
        self.assertAlmostEqual(s["words"]["all"]["w_ratio"][0], 1.0)

    def test_colour_without_contrast_is_excluded(self):
        words = [(60, 120, "Hello", 16, (1, 1, 1))]  # white ink on white
        w, dr, im, ref, sub = self._pair_arrays(words)
        recs, reasons = g.analyse_pair(w, dr, im, ref, sub)
        self.assertEqual(reasons["colour_no_contrast"], 1)


class SyntheticValidityTest(unittest.TestCase):
    """Known geometry in, known measurement out. Uses the 60-word layout."""

    @classmethod
    def setUpClass(cls):
        base = _doc(LAYOUT)
        cls.words, cls.drawings, cls.images, _, _ = g.page_inputs(base[0])
        cls.ref = _render(base)

    def _summary(self, sub):
        recs, _ = g.analyse_pair(self.words, self.drawings, self.images, self.ref, sub)
        return g.summarise(recs, g.line_measures(recs, self.words, self.ref, sub), [], "t")

    def test_same_geometry_control(self):
        s = self._summary(self.ref)
        reg = s["words"]["all"]["reg_w"]
        self.assertAlmostEqual(reg[0], 1.0, places=6)
        self.assertAlmostEqual(reg[1], 0.0, places=4)
        self.assertEqual(s["words_valid"], len(LAYOUT))

    def test_known_scale_is_recovered_as_slope(self):
        s = self._summary(_render(_doc(LAYOUT, 1.03)))
        reg = s["words"]["all"]["reg_w"]
        self.assertAlmostEqual(reg[0], 1.03, delta=0.01)
        self.assertLess(abs(reg[1]), 0.5)  # no bleed term for a pure scale

    def test_darker_edges_are_bleed_not_geometry(self):
        s = self._summary(_gamma(self.ref, 0.6))
        reg = s["words"]["all"]["reg_w"]
        self.assertAlmostEqual(reg[0], 1.0, delta=0.01)  # no size change
        self.assertGreater(reg[1], 0.2)  # bleed term is positive

    def test_known_scale_glyph_span_is_recovered(self):
        # Centre-to-centre spacing of glyph runs is invariant to edge darkness,
        # so it is the glyph-level check for a size change. Latin words only.
        s = self._summary(_render(_doc(LAYOUT, 1.03)))
        span = s["glyph"]["advance_span_ratio_med"]
        self.assertIsNotNone(span)
        self.assertAlmostEqual(span, 1.03, delta=0.01)

    def test_darker_edges_do_not_change_glyph_span(self):
        s = self._summary(_gamma(self.ref, 0.6))
        span = s["glyph"]["advance_span_ratio_med"]
        self.assertIsNotNone(span)
        self.assertAlmostEqual(span, 1.0, delta=0.005)


class LineSpacingTest(unittest.TestCase):
    def test_spacing_scales_with_size(self):
        # Scaling about each line's baseline keeps the centroid gap at 1.03 x spacing.
        words = [(60, 120, "Hello", 16, (0, 0, 0)), (60, 160, "Sphinx", 16, (0, 0, 0))]
        ref_doc = _doc(words)
        sub_doc = _doc(words, 1.0)
        ref = _render(ref_doc)
        sub = _render(sub_doc)
        w, dr, im, _, _ = g.page_inputs(ref_doc[0])
        recs, _ = g.analyse_pair(w, dr, im, ref, sub)
        lrs = g.line_measures(recs, w, ref, sub)
        spc = g.line_spacing(lrs)
        self.assertEqual(len(spc), 1)
        self.assertAlmostEqual(spc[0]["ratio"], 1.0, delta=0.02)

    def test_spacing_detects_a_shifted_line(self):
        words = [(60, 120, "Hello", 16, (0, 0, 0)), (60, 160, "Sphinx", 16, (0, 0, 0))]
        ref = _render(_doc(words))
        moved = [(60, 120, "Hello", 16, (0, 0, 0)), (60, 163, "Sphinx", 16, (0, 0, 0))]
        sub = _render(_doc(moved))
        w, dr, im, _, _ = g.page_inputs(_doc(words)[0])
        recs, _ = g.analyse_pair(w, dr, im, ref, sub)
        spc = g.line_spacing(g.line_measures(recs, w, ref, sub))
        self.assertEqual(len(spc), 1)
        self.assertAlmostEqual(spc[0]["ratio"], 43.0 / 40.0, delta=0.03)


if __name__ == "__main__":
    unittest.main()
