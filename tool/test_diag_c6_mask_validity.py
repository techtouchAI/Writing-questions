"""Tests for tool/diag_c6_mask_validity.py (C6-DIAG-10, diagnostic only).

Run from the repository root:  python3 -m unittest discover -s tool -p 'test_diag_c6_*.py'
Synthetic PDFs only. Assertions state measured synthetic facts, not gate results.
"""
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_mask_pixels as mp  # noqa: E402  (AA_TOL, declared before any run)
import diag_c6_mask_validity as mv  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402


class StripCounterTest(unittest.TestCase):
    def test_painting_inside_bt_is_counted_and_removed(self):
        raw = b"BT /F1 12 Tf 10 10 Td (Hi) Tj 0 0 1 rg 5 5 3 3 re f ET\n1 0 0 rg 9 9 1 1 re f\n"
        new, st = resid.strip_text(raw)
        self.assertEqual(st["text_objects"], 1)
        self.assertEqual(st["nontext_ops_removed"], 2)  # re and f inside BT..ET
        self.assertNotIn(b" re f", new.split(b"\n")[0])
        self.assertIn(b"1 0 0 rg 9 9 1 1 re f", new)  # painting outside BT survives

    def test_no_painting_inside_bt_counts_zero(self):
        raw = b"BT /F1 12 Tf 10 10 Td (Hi) Tj ET\n0 0 1 rg 1 1 2 2 re f\n"
        _, st = resid.strip_text(raw)
        self.assertEqual(st["nontext_ops_removed"], 0)

    def test_string_literal_with_bt_et_is_not_an_operator(self):
        raw = b"BT /F1 12 Tf 10 10 Td (BT inside ET) Tj ET\n"
        new, st = resid.strip_text(raw)
        self.assertEqual(st["text_objects"], 1)
        self.assertEqual(new.strip(), b"")  # nothing left after removing the text object


class TransformTest(unittest.TestCase):
    def test_exact_mask_matches_gate_scale_not_px(self):
        # Right edge chosen so that ceil(x1*PX - CO) = 302 but ceil(x1*SX - CO) = 303:
        # the exact mask must include device column 302, the PX mask must not.
        x1 = (302 + mv.CO) / resid.PX
        boxes = [(0.0, 0.0, x1, 10.0)]
        shape = (mv.CH, mv.CW)
        ex = mv.exact_mask(shape, boxes)
        ap = resid.box_mask(shape, boxes)
        self.assertTrue(ex[0, 302])
        self.assertFalse(ap[0, 302])
        self.assertTrue(ap[0, 301])

    def test_px_mask_shrinks_relative_to_gate_at_far_edge(self):
        # The PX mask is smaller than the gate raster at the far page edge (sx > PX),
        # so its right edge falls short of the glyph edge.
        self.assertGreater(mv.SX, resid.PX)
        self.assertGreater(mv.SY, resid.PX)
        # Exact displacement at the far edge, from the gate size and the page size:
        # 794 - (4/3)*PW and 1123 - (4/3)*PH (not a tolerance chosen after seeing a result).
        self.assertAlmostEqual((mv.SX - resid.PX) * mv.PW, 794 - (4.0 / 3.0) * mv.PW, places=9)
        self.assertAlmostEqual((mv.SY - resid.PX) * mv.PH, 1123 - (4.0 / 3.0) * mv.PH, places=9)


class OutsideChangesTest(unittest.TestCase):
    def test_planted_pixel_outside_mask_is_found(self):
        shape = (20, 20)
        full = np.ones((20, 20, 3), np.float32)
        notext = full.copy()
        mask = np.zeros(shape, bool)
        mask[5:10, 5:10] = True
        notext[2, 3] = 0.9  # changed outside the mask
        notext[6, 6] = 0.5  # changed inside the mask (not counted)
        res = mv.outside_changes(full, notext, mask)
        self.assertEqual(res["count"], 1)
        self.assertEqual((res["pixels"][0]["x"], res["pixels"][0]["y"]), (3, 2))

    def test_identical_renders_give_zero(self):
        full = np.full((10, 10, 3), 0.5, np.float32)
        res = mv.outside_changes(full, full.copy(), np.zeros((10, 10), bool))
        self.assertEqual(res["count"], 0)


class SyntheticMaskCasesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="c6mv_")
        cls.res = mv.run_synthetic(out_dir=cls.tmp, work_dir=cls.tmp)

    def test_t1_exact_mask_leaves_fewer_outside_pixels_than_px_mask(self):
        t = self.res["T1_T2_text_only"]
        self.assertGreater(t["approx_mask"]["count"], t["exact_mask"]["count"])

    def test_t2_exact_mask_leaks_are_faint_and_at_the_boundary(self):
        # Residual leaks with the exact transform: faint AA, within 0.05 px of a box.
        for p in self.res["T1_T2_text_only"]["exact_mask"]["pixels"]:
            self.assertLess(p["darkness"], 0.01)  # faint anti-aliasing bound (stated here, not tuned)
            self.assertLessEqual(p["dist_px"], mp.AA_TOL)  # the a-priori tolerance of DIAG-13

    def test_t3_painting_inside_bt_is_removed_by_strip(self):
        t = self.res["T3_bt_painting"]
        self.assertGreater(t["blue_rect_px_before"], 0)
        self.assertEqual(t["blue_rect_px_after_strip"], 0)
        self.assertTrue(t["red_rect_kept_after_strip"])
        self.assertEqual(t["nontext_ops_removed"], 2)
        self.assertGreater(t["exact_mask"]["count"], 0)

    def test_t4_literal_bt_et_does_not_remove_painting(self):
        t = self.res["T4_literal_bt_et"]
        self.assertEqual(t["text_objects"], 1)
        self.assertEqual(t["nontext_ops_removed"], 0)
        self.assertTrue(t["blue_rect_kept"])


if __name__ == "__main__":
    unittest.main()
