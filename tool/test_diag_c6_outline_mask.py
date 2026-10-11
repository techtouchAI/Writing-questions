"""Tests for tool/diag_c6_outline_mask.py (C6-DIAG-12). Synthetic PDFs only, diagnostic.

Each case has its expected number of clean columns written in diag_c6_outline_mask._case_pages,
derived from the geometry before any run. The assertions are exact equalities, not inequalities.
Run from the repository root:  python3 -m unittest discover -s tool -p 'test_diag_c6_*.py'
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_outline_mask as om  # noqa: E402
import diag_c6_rule_geometry as rg  # noqa: E402

PW, PH = om.PW, om.PH
SHAPE = (rg.H, rg.W)
_TMP = tempfile.mkdtemp(prefix="c6om_")  # tests never write into the repository
SCALES = {"sx": rg.W / PW, "sy": rg.H / PH}


def _band_and_span():
    centre = om.RULE_Y * rg.H / PH
    lo, hi = int(np.floor(centre)) - rg.BAND, int(np.floor(centre)) + rg.BAND
    c0 = int(np.floor(om.RULE_X0 * rg.W / PW)) + rg.END_TRIM
    c1 = int(np.ceil(om.RULE_X1 * rg.W / PW)) - rg.END_TRIM
    return lo, hi, c0, c1


class ExpectedSpanTest(unittest.TestCase):
    def test_span_is_the_predetermined_389_columns(self):
        _, _, c0, c1 = _band_and_span()
        self.assertEqual(c1 - c0, om.EXPECTED_SPAN)


class OutlineCases(unittest.TestCase):
    """Each case: exact expected clean columns (outline mask), and the DIAG-9 bbox comparison."""

    def test_all_cases_match_predetermined_counts(self):
        rows, lines = om.synthetic_report(_TMP)
        failed = [r["case"] for r in rows if not r["pass"]]
        self.assertEqual(failed, [], "\n".join(lines))
        for r in rows:
            self.assertEqual(r["observed_outline"], r["expected_outline"], r["case"])
            if r["expected_bbox"] is not None:
                self.assertEqual(r["observed_bbox"], r["expected_bbox"], r["case"])

    def test_white_fill_adds_no_interior_and_grey_fill_does(self):
        rows = {r["case"]: r for r in om.synthetic_report(_TMP)[0]}
        self.assertEqual(rows["C2 white fill over band"]["fill_interiors"], 0)
        self.assertEqual(rows["C3 grey fill over band"]["fill_interiors"], 1)

    def test_curve_is_counted_as_bbox_fallback(self):
        rows = {r["case"]: r for r in om.synthetic_report(_TMP)[0]}
        self.assertEqual(rows["C5 curve (bbox fallback)"]["fallback_bbox"], 1)
        self.assertEqual(rows["C4 hollow thick rect, centre empty"]["fallback_bbox"], 0)

    def test_text_is_not_a_drawing(self):
        d = pymupdf.open()
        p = d.new_page(width=PW, height=PH)
        p.insert_text((100, 300), "Text near the band", fontname="helv", fontsize=12)
        mask, st = om.outline_other_mask(p, SHAPE, SCALES)
        self.assertFalse(mask.any())
        self.assertEqual(st["drawings"], 0)
        d.close()


class ClassificationTest(unittest.TestCase):
    def test_rule_classification_matches_extract_rules(self):
        d = pymupdf.open()
        p = d.new_page(width=PW, height=PH)
        p.draw_line((100, 300), (400, 300), color=(0, 0, 0), width=0.8)  # rule
        p.draw_rect(pymupdf.Rect(90, 500, 300, 560), color=(0, 0, 0), width=0.6)  # 4 rule edges
        p.draw_rect(pymupdf.Rect(10, 10, 60, 90), color=(0, 0, 0), width=5)  # thick, not rules
        p.draw_rect(pymupdf.Rect(200, 700, 330, 702), color=None, fill=(0, 0, 0))  # thin filled rule
        rules, _ = rg.extract_rules(p)
        n_rules_new = sum(om.classify_items(dr)[0] for dr in p.get_drawings())
        self.assertEqual(n_rules_new, len(rules))
        d.close()


if __name__ == "__main__":
    unittest.main()
