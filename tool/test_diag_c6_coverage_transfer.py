"""Tests for tool/diag_c6_coverage_transfer.py (C6-DIAG-11, synthetic, diagnostic only).

Run from the repository root:  python3 -m unittest discover -s tool -p 'test_diag_c6_*.py'
The assertions check the definitions of the truth transforms and the signature
panel. They do not check any agreement with a real reference image.
"""
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_coverage_transfer as ct  # noqa: E402
import diag_c6_mask_validity as mv  # noqa: E402


class PanelDefinitionTest(unittest.TestCase):
    def test_identity_gives_unit_ratios(self):
        B = np.zeros((40, 40), np.float32)
        B[10:20, 10:14] = 1.0
        B[10:20, 14] = 0.5
        s = ct.signature(B, B.copy())
        for k in ("total_ink_ratio", "edge_px_ratio", "full_px_ratio", "full_mass_ratio", "edge_mean_ratio"):
            self.assertAlmostEqual(s[k], 1.0, places=9)
        self.assertAlmostEqual(s["centroid_dx_px"], 0.0, places=9)

    def test_gain_scales_total_ink_exactly(self):
        B = np.zeros((40, 40), np.float32)
        B[5:30, 5:12] = 0.9
        B[5:30, 12] = 0.3
        s = ct.signature(B, ct.v_gain(B, 0.77))
        self.assertAlmostEqual(s["total_ink_ratio"], 1 / 0.77, places=6)

    def test_no_full_pixels_on_other_side_gives_none_not_huge_number(self):
        B = np.zeros((20, 20), np.float32)
        B[5:10, 5:10] = 1.0
        s = ct.signature(B, ct.v_gain(B, 0.77))  # other side has no pixel >= 0.95
        self.assertIsNone(s["full_px_ratio"])
        self.assertIsNone(s["full_mass_ratio"])

    def test_blur_conserves_ink(self):
        B = np.zeros((30, 30), np.float32)
        B[10:15, 10:15] = 0.7
        self.assertAlmostEqual(float(ct.v_blur(B).sum()), float(B.sum()), places=4)

    def test_gamma_leaves_full_pixels_alone(self):
        B = np.array([[0.0, 0.5, 1.0]], np.float32)
        G = ct.v_gamma(B, 2.0)
        self.assertEqual(float(G[0, 2]), 1.0)
        self.assertAlmostEqual(float(G[0, 1]), 0.25, places=6)


class SyntheticVariantTest(unittest.TestCase):
    """One grid phase, a small word set. Checks the variable each truth transform changes."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="c6ct_")
        cls.v = ct.variants(cls.tmp, ct.WORDS_T, "tst", 0.0)

    def sig(self, name):
        B, R = self.v[name]
        return ct.signature(B, R)

    def test_control_is_identity(self):
        s = self.sig("control_identity")
        self.assertAlmostEqual(s["total_ink_ratio"], 1.0, places=9)
        self.assertAlmostEqual(s["centroid_dx_px"], 0.0, places=9)

    def test_gain_changes_total_not_geometry(self):
        s = self.sig("gain_0.77")
        self.assertAlmostEqual(s["total_ink_ratio"], 1 / 0.77, places=3)
        # Float32 accumulation leaves ~1e-5 px; the geometry is unchanged.
        self.assertAlmostEqual(s["centroid_dx_px"], 0.0, delta=1e-3)

    def test_shift_moves_centroid_by_quarter_pixel_and_keeps_ink(self):
        s = self.sig("shift_0.25px_x")
        self.assertAlmostEqual(s["total_ink_ratio"], 1.0, delta=0.005)
        self.assertAlmostEqual(s["centroid_dx_px"], -0.25, delta=0.05)

    def test_font_size_changes_ink_by_area(self):
        s = self.sig("font_size_0.97")
        self.assertAlmostEqual(s["total_ink_ratio"], 1 / (0.97 ** 2), delta=0.01)

    def test_equal_total_size_variant_moves_edges(self):
        s = self.sig("EQ_font_size_0.88")
        self.assertAlmostEqual(s["total_ink_ratio"], 1 / (0.88 ** 2), delta=0.02)
        self.assertGreater(s["edge_px_ratio"], 1.05)  # a size change adds boundary pixels

    def test_embolden_makes_other_side_heavier(self):
        s = self.sig("embolden_0.2pt_other_side_heavier")
        self.assertLess(s["total_ink_ratio"], 1.0)


class CoverageRenderTest(unittest.TestCase):
    def test_render_is_gate_frame_and_in_unit_range(self):
        tmp = tempfile.mkdtemp(prefix="c6ctr_")
        pdf = ct.build_pdf(os.path.join(tmp, "p.pdf"), ct.WORDS_T)
        cov = ct.render_cov(pdf)
        self.assertEqual(cov.shape, (mv.CH, mv.CW))
        self.assertGreaterEqual(float(cov.min()), 0.0)
        self.assertLessEqual(float(cov.max()), 1.0 + 1e-6)
        self.assertGreater(float(cov.sum()), 100.0)


if __name__ == "__main__":
    unittest.main()
