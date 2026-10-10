"""Unit tests for the C6 coverage-profile diagnostic (synthetic arrays and synthetic PDFs only).

These check the classes, the mass identity, the ratios, the bootstrap, and the discrimination
between darker edges and larger geometry. They are validation of the method, not evidence about
the real fixture.
Run: cd tool && python -m unittest test_diag_c6_coverage_profile
"""
import os
import sys
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_coverage_profile as cp  # noqa: E402
import diag_c6_text_geometry as geo  # noqa: E402

PRIMARY = cp.PRIMARY


def square(n, ring=0.5, pad=3):
    """An n x n full square with a one-pixel partial ring of coverage `ring`."""
    cov = np.zeros((n + 2 * pad, n + 2 * pad))
    cov[pad - 1 : pad + n + 1, pad - 1 : pad + n + 1] = ring
    cov[pad : pad + n, pad : pad + n] = 1.0
    return cov


def rec_pair(ref_cov, pdf_cov, thr=PRIMARY):
    return {
        "i": 0,
        "font": "F",
        "script": "latin",
        "cy": 100.0,
        "ref": cp.window_stats(ref_cov, *thr),
        "pdf": cp.window_stats(pdf_cov, *thr),
    }


class ClassTest(unittest.TestCase):
    def test_known_block_with_one_partial_row(self):
        cov = np.zeros((7, 7))
        cov[2:5, 2:5] = 1.0
        cov[1, 2:5] = 0.5
        s = cp.window_stats(cov, *PRIMARY)
        self.assertEqual(s["n_int"], 1)  # the centre of the 3x3 block has eight full neighbours
        self.assertEqual(s["n_bnd"], 8)
        self.assertEqual(s["n_edge"], 3)
        self.assertAlmostEqual(s["mass_edge"], 1.5)
        self.assertAlmostEqual(s["mass_full"], 9.0)
        self.assertEqual(s["n_bg"], 49 - 9 - 3)

    def test_mass_identity(self):
        rng = np.random.default_rng(1)
        cov = rng.random((20, 30))
        cov[rng.random(cov.shape) < 0.4] = 0.0
        s = cp.window_stats(cov, *PRIMARY)
        self.assertAlmostEqual(s["mass_total"], s["mass_bg"] + s["mass_edge"] + s["mass_full"], places=9)
        self.assertEqual(s["n_bg"] + s["n_edge"] + s["n_int"] + s["n_bnd"], cov.size)

    def test_histogram_counts_edge_pixels_only(self):
        cov = np.array([[0.03, 0.10, 0.50, 0.96, 1.0]])
        s = cp.window_stats(cov, *PRIMARY)
        self.assertEqual(s["n_edge"], 2)  # 0.10 and 0.50; 0.03 is background, 0.96 and 1.0 full
        self.assertEqual(sum(s["hist"]), 2)

    def test_threshold_pairs_move_edge_pixels(self):
        cov = np.array([[0.03, 0.5, 1.0]])
        self.assertEqual(cp.window_stats(cov, 0.05, 0.95)["n_edge"], 1)
        self.assertEqual(cp.window_stats(cov, 0.02, 0.98)["n_edge"], 2)

    def test_word_coverage_refuses_no_contrast(self):
        win = np.full((5, 5, 3), 0.5)
        self.assertIsNone(cp.word_coverage(win, (0.5, 0.5, 0.5)))


class RatioTest(unittest.TestCase):
    def test_identical_sides_give_unit_ratios(self):
        recs = [rec_pair(square(8), square(8)) for _ in range(5)]
        a = cp.aggregate(recs, boot=200)
        self.assertAlmostEqual(a["ratio_total_mass"], 1.0)
        self.assertAlmostEqual(a["ratio_edge_mass"], 1.0)
        self.assertAlmostEqual(a["tv_edge_hist"], 0.0)
        self.assertTrue(np.isnan(a["share_delta_edge"]))
        self.assertEqual(a["ci"]["ratio_edge_mass"], [1.0, 1.0])

    def test_edge_mass_shares_sum_to_one(self):
        recs = [rec_pair(square(8, 0.5), square(8, 0.7)) for _ in range(4)]
        a = cp.aggregate(recs, boot=0)
        self.assertAlmostEqual(a["share_delta_edge"] + a["share_delta_full"] + a["share_delta_bg"], 1.0, places=9)
        self.assertAlmostEqual(a["share_delta_edge"], 1.0)  # only the ring changed

    def test_bootstrap_is_deterministic(self):
        rng = np.random.default_rng(3)
        recs = [rec_pair(square(6, 0.5), square(6, rng.uniform(0.4, 0.8))) for _ in range(12)]
        a1 = cp.aggregate(recs, boot=100, seed=7)
        a2 = cp.aggregate(recs, boot=100, seed=7)
        self.assertEqual(a1["ci"], a2["ci"])

    def test_empty_group(self):
        self.assertEqual(cp.aggregate([]), {"n_words": 0})


class DiscriminationTest(unittest.TestCase):
    """Darker edges must not look like larger geometry, and larger geometry must not look like darker edges."""

    def setUp(self):
        self.ref = square(10, 0.5)

    def test_darker_edges_change_edge_mass_not_interior(self):
        dark = square(10, 0.5 ** 0.6)  # same geometry, darker partial pixels
        a = cp.aggregate([rec_pair(self.ref, dark)], boot=0)
        self.assertAlmostEqual(a["ratio_n_int"], 1.0)
        self.assertAlmostEqual(a["ratio_full_mass"], 1.0)
        self.assertAlmostEqual(a["ratio_n_edge"], 1.0)
        self.assertGreater(a["ratio_edge_mass"], 1.2)
        self.assertAlmostEqual(a["share_delta_full"], 0.0, places=9)

    def test_larger_geometry_changes_interior_count(self):
        big = square(11, 0.5)  # one pixel larger all round, same edge darkness
        a = cp.aggregate([rec_pair(self.ref, big)], boot=0)
        self.assertEqual(a["n_int_ref"], 64)
        self.assertEqual(a["n_int_pdf"], 81)
        self.assertAlmostEqual(a["ratio_n_int"], 81 / 64)
        self.assertGreater(a["share_delta_full"], a["share_delta_edge"])

    def test_edge_count_alone_does_not_read_as_size(self):
        dark = square(10, 0.5 ** 0.6)
        a = cp.aggregate([rec_pair(self.ref, dark)], boot=0)
        self.assertAlmostEqual(a["ratio_n_edge"], 1.0)  # same ring pixels, darker


class GroupTest(unittest.TestCase):
    def test_thirds_and_groups(self):
        self.assertEqual(cp.third_of(0.0), 0)
        self.assertEqual(cp.third_of(cp.CH / 2), 1)
        self.assertEqual(cp.third_of(cp.CH - 1), 2)
        recs = [
            {"i": 0, "font": "A", "script": "latin", "cy": 10.0, "ref": {}, "pdf": {}},
            {"i": 1, "font": "B", "script": "arabic", "cy": cp.CH - 5, "ref": {}, "pdf": {}},
        ]
        g = cp.groups(recs)
        self.assertEqual([r["i"] for r in g["font:A"]], [0])
        self.assertEqual([r["i"] for r in g["script:arabic"]], [1])
        self.assertEqual([r["i"] for r in g["third:top"]], [0])
        self.assertEqual([r["i"] for r in g["third:bottom"]], [1])


class EndToEndTest(unittest.TestCase):
    """Synthetic PDF with a known grid of words, rendered through the real word and window path."""

    @classmethod
    def setUpClass(cls):
        d = pymupdf.open()
        p = d.new_page(width=595.28, height=841.89)
        names = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]
        # Bold 22 pt: stems several pixels wide, so the interior class is populated.
        # (11 pt regular Helvetica has no interior pixels at these thresholds: n_int is 0.)
        for row in range(10):
            for col in range(3):
                p.insert_text((40 + col * 190, 70 + row * 75), names[(row + col) % 6], fontname="hebo", fontsize=22)
        cls.doc = d
        words, drawings, images, (sx, sy), _ = geo.page_inputs(p)
        cls.words, cls.drawings, cls.images = words, drawings, images
        cls.ref = geo.load_float(geo.mupdf_render(p, sx, sy))

    def _records(self, sub):
        recs, _ = geo.analyse_pair(self.words, self.drawings, self.images, self.ref, sub)
        valid = cp.valid_windows(self.words, recs, self.ref.shape[:2])
        imgs = {"a": self.ref, "b": sub}
        return cp.comparison_records(self.words, valid, imgs, "a", "b"), len(valid)

    def test_identical_render_is_unit_ratio_on_real_word_path(self):
        per_thr, n = self._records(self.ref)
        self.assertGreaterEqual(n, 25)
        a = cp.aggregate(per_thr[PRIMARY], boot=0)
        self.assertAlmostEqual(a["ratio_edge_mass"], 1.0)
        self.assertAlmostEqual(a["ratio_total_mass"], 1.0)

    def test_darker_partial_pixels_inflate_interior_count(self):
        # Documented confound, not a pass condition for size: darkening only partial pixels
        # pushes near-full pixels across the HI threshold, so the interior count grows even
        # though no glyph got larger. Edge mass and totals move in the same direction.
        dark = np.clip(self.ref, 0, 1) ** 1.6
        per_thr, n = self._records(dark)
        a = cp.aggregate(per_thr[PRIMARY], boot=0)
        self.assertGreater(a["ratio_total_mass"], 1.03)
        self.assertGreater(a["ratio_n_int"], 1.1)

if __name__ == "__main__":
    unittest.main()
