"""Tests for diag_c6_resample_check (synthetic, needs ImageMagick convert)."""
import os
import shutil
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import diag_c6_mask_pixels as mp  # noqa: E402
import diag_c6_resample_check as rc  # noqa: E402

HAVE_CONVERT = shutil.which("convert") is not None


@unittest.skipUnless(HAVE_CONVERT, "ImageMagick convert not available")
class ResampleCheckTests(unittest.TestCase):
    def test_identity_scale_leaves_nothing_outside_mask(self):
        # 4/3 renders the A4 page at exactly 794x1123, so the gate's resize is
        # an identity and cannot move ink. Expected: 0 changed pixels outside.
        with tempfile.TemporaryDirectory() as wd:
            r = rc.run(4 / 3, wd)
        self.assertEqual(r["native_px"], (794, 1123))
        self.assertEqual(r["changed_outside_exact"], 0)
        self.assertGreater(r["changed_total"], 0)

    def test_non_identity_resize_spreads_ink_beyond_tolerance(self):
        # A real resample (native 780x1103 -> 794x1123) moves ink outside the
        # exact mask by up to ~0.65 px, which is above AA_TOL. This documents
        # that resampling is a candidate mechanism when native size != 794x1123.
        with tempfile.TemporaryDirectory() as wd:
            r = rc.run(1.31, wd)
        self.assertNotEqual(r["native_px"], (794, 1123))
        self.assertGreater(r["changed_outside_exact"], 0)
        self.assertIsNotNone(r["max_dist_outside_exact_px"])
        self.assertGreater(r["max_dist_outside_exact_px"], mp.AA_TOL)
        self.assertEqual(
            sum(r["classes_outside_exact"].values()), r["changed_outside_exact"]
        )


if __name__ == "__main__":
    unittest.main()
