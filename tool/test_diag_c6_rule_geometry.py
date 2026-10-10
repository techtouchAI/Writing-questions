"""Unit tests for the C6 page-rule geometry diagnostic (synthetic PDFs and arrays only).

Rendering here uses MuPDF. Its anti-aliasing quantises edge coverage to about 0.2 px,
so these tests allow about 0.1 px. They establish the method's behaviour on known
inputs. They say nothing about Poppler or the Flutter Preview.
Run: cd tool && python -m unittest test_diag_c6_rule_geometry
"""
import os
import sys
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_rule_geometry as rg  # noqa: E402

PW, PH = 595.28, 841.89


def _pdf(draw):
    d = pymupdf.open()
    p = d.new_page(width=PW, height=PH)
    draw(p)
    return d


def _render(doc):
    """Full-frame MuPDF raster at the canonical transform (exactly 794x1123 for this page)."""
    r = doc[0].rect
    sx, sy = 794.0 / r.width, 1123.0 / r.height
    pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(sx, sy), alpha=False)
    assert (pix.width, pix.height) == (794, 1123), (pix.width, pix.height)
    arr = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, 3)
    return arr.astype(np.float64) / 255.0


def _cov_rows(cc, t, lo, hi):
    """Exact area coverage of rows [i, i+1) by [cc - t/2, cc + t/2]."""
    rows = np.arange(lo, hi + 1, dtype=np.float64)
    return np.clip(np.minimum(rows + 1, cc + t / 2) - np.maximum(rows, cc - t / 2), 0, None)


class ExtractTest(unittest.TestCase):
    def test_stroke_line_horizontal_and_vertical(self):
        d = _pdf(lambda p: (p.draw_line((50, 300.25), (500, 300.25), color=(0, 0, 0), width=1.2),
                            p.draw_line((120.0, 100), (120.0, 400), color=(0, 0, 0), width=0.8)))
        rules, _ = rg.extract_rules(d[0])
        self.assertEqual(len(rules), 2)
        h = [r for r in rules if r["orient"] == "h"][0]
        v = [r for r in rules if r["orient"] == "v"][0]
        self.assertAlmostEqual(h["across_pt"], 300.25, places=3)
        self.assertAlmostEqual(h["start_pt"], 50, places=3)
        self.assertAlmostEqual(h["end_pt"], 500, places=3)
        self.assertAlmostEqual(h["thick_pt"], 1.2, places=3)
        self.assertEqual(h["src"], "stroke_line")
        self.assertAlmostEqual(v["across_pt"], 120.0, places=3)
        self.assertAlmostEqual(v["thick_pt"], 0.8, places=3)

    def test_short_line_and_block_are_not_rules(self):
        d = _pdf(lambda p: (p.draw_line((50, 200), (60, 200), color=(0, 0, 0), width=1),
                            p.draw_rect(pymupdf.Rect(100, 300, 200, 400), color=None, fill=(0, 0, 0))))
        rules, other = rg.extract_rules(d[0])
        self.assertEqual(rules, [])
        self.assertEqual(len(other), 2)

    def test_thin_fill_rect_is_a_rule_with_its_height(self):
        d = _pdf(lambda p: p.draw_rect(pymupdf.Rect(50, 400, 500, 401), color=None, fill=(0, 0, 0)))
        rules, _ = rg.extract_rules(d[0])
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0]["orient"], "h")
        self.assertEqual(rules[0]["src"], "fill_rect")
        self.assertAlmostEqual(rules[0]["across_pt"], 400.5, places=3)
        self.assertAlmostEqual(rules[0]["thick_pt"], 1.0, places=3)

    def test_stroked_rectangle_gives_four_edges(self):
        d = _pdf(lambda p: p.draw_rect(pymupdf.Rect(50, 500, 300, 600), color=(0, 0, 0), width=0.8))
        rules, _ = rg.extract_rules(d[0])
        self.assertEqual(sorted(r["orient"] for r in rules), ["h", "h", "v", "v"])
        self.assertTrue(all(r["src"] == "stroke_rect" for r in rules))
        self.assertTrue(all(abs(r["thick_pt"] - 0.8) < 1e-3 for r in rules))


class TransformTest(unittest.TestCase):
    def test_canonical_and_pdftoppm_scales(self):
        d = pymupdf.open()
        p = d.new_page(width=PW, height=PH)
        a, b = rg.analytic_scales(p, 794, 1123)
        self.assertAlmostEqual(a["sx"], 794 / p.rect.width, places=9)
        self.assertAlmostEqual(a["sy"], 1123 / p.rect.height, places=9)
        self.assertAlmostEqual(b["sx"], 96 / 72, places=9)
        self.assertAlmostEqual(b["sy"], 96 / 72, places=9)

    def test_raw_size_one_pixel_short_enters_the_stretch(self):
        d = pymupdf.open()
        p = d.new_page(width=PW, height=PH)
        _, b = rg.analytic_scales(p, 793, 1122)  # the gate stretches the raw render to 794x1123
        self.assertAlmostEqual(b["sx"], 96 / 72 * 794 / 793, places=9)
        self.assertAlmostEqual(b["sy"], 96 / 72 * 1123 / 1122, places=9)

    def test_analytic_centre_and_thickness(self):
        rule = {"orient": "h", "across_pt": 100.0, "start_pt": 0, "end_pt": 10, "thick_pt": 1.0}
        sc = {"sx": 2.0, "sy": 3.0}
        self.assertAlmostEqual(rg.analytic_centre(rule, sc), 300.0)  # horizontal: sy
        self.assertAlmostEqual(rg.analytic_thick(rule, sc), 3.0)
        v = dict(rule, orient="v")
        self.assertAlmostEqual(rg.analytic_centre(v, sc), 200.0)  # vertical: sx


class ProfileTest(unittest.TestCase):
    def test_expected_profile_is_exact_area(self):
        e = rg.expected_profile(5.8, 1.5, 0, 10)
        np.testing.assert_allclose(e, _cov_rows(5.8, 1.5, 0, 10))
        self.assertAlmostEqual(e.sum(), 1.5)

    def test_edge_method_recovers_centre_and_thickness_exactly(self):
        for cc, t in ((100.8, 1.5), (50.25, 2.4), (30.5, 3.0), (7.13, 1.2)):
            lo = int(cc) - 5
            prof = _cov_rows(cc, t, lo, lo + 10)
            m = rg.measure_side(prof, lo)
            self.assertEqual(m["method"], "edges", (cc, t))
            self.assertAlmostEqual(m["centre"], cc, places=9)
            self.assertAlmostEqual(m["thick"], t, places=9)

    def test_quantised_coverage_moves_the_centre_by_at_most_about_a_tenth_px(self):
        cc, t = 400.5045, 1.6007
        lo = 394
        q = np.round(_cov_rows(cc, t, lo, lo + 11) * 5) / 5  # 0.2 px quantisation
        m = rg.measure_side(q, lo)
        self.assertEqual(m["method"], "edges")
        self.assertLess(abs(m["centre"] - cc), 0.1)

    def test_one_full_pixel_rule_is_unresolved_not_guessed(self):
        m = rg.measure_side(np.array([0, 0, 1.0, 0, 0]), 0)
        self.assertIsNone(m["centre"])
        self.assertEqual(m["method"], "single_or_none")

    def test_partial_interior_is_refused(self):
        m = rg.measure_side(np.array([0, 0.3, 0.6, 0.3, 0]), 0)
        self.assertEqual(m["method"], "partial_interior")
        self.assertIsNone(m["centre"])

    def test_run_touching_band_edge_is_refused(self):
        self.assertEqual(rg.measure_side(np.array([0.5, 1.0, 1.0, 0.0]), 0)["method"], "band_truncated")

    def test_nan_row_in_run_is_refused(self):
        self.assertEqual(rg.measure_side(np.array([0, 0.5, np.nan, 0.5, 0]), 0)["method"], "nan_in_run")

    def test_contaminated_columns_are_excluded(self):
        cov = np.zeros((20, 40))
        cov[8:11, :] = 1.0
        cont = np.zeros_like(cov, dtype=bool)
        cont[:, 10:30] = True  # usable columns 6..33 (28); 20 contaminated -> 8 clean < MIN_CLEAN
        prof, ncl, _ = rg.profile(cov, cont, {"orient": "h"}, (0.0, 40.0), (6, 12))
        self.assertTrue(np.all(np.isnan(prof)))
        self.assertTrue(np.all(ncl == 8))

    def test_vertical_profile_reads_columns(self):
        cov = np.zeros((40, 20))
        cov[:, 8:11] = 1.0  # a vertical band in columns 8..10
        cont = np.zeros_like(cov, dtype=bool)
        prof, _, _ = rg.profile(cov, cont, {"orient": "v"}, (0.0, 40.0), (6, 12))
        np.testing.assert_allclose(prof, [0, 0, 1, 1, 1, 0, 0])


class RuleMeasureTest(unittest.TestCase):
    """End to end on a synthetic page: the method must recover known displacements."""

    @classmethod
    def setUpClass(cls):
        y, t = 300.25, 1.2

        def draw(p):
            p.draw_line((50, y), (500, y), color=(0, 0, 0), width=t)
            p.draw_line((120.0, 100), (120.0, 400), color=(0, 0, 0), width=0.8)

        cls.doc = _pdf(draw)
        cls.pdf = _render(cls.doc)

    def _analyse(self, prev):
        return rg.analyse_page(self.doc[0], prev, self.pdf, (794, 1123), (794, 1123), "", "", "p1")

    def _h(self, res):
        return [r for r in res["rules"] if r.get("orient") == "h"][0]

    def test_isolated_rule_pdf_matches_analytic_within_raster_precision(self):
        h = self._h(self._analyse(self.pdf))
        self.assertFalse(h["grouped"])
        self.assertIsNotNone(h["disp"])
        self.assertLess(abs(h["disp"]["pdf_minus_A"]), 0.1)
        self.assertLess(abs(h["disp"]["thick_pdf_minus_A"]), 0.1)
        self.assertLess(abs(h["disp"]["prev_minus_pdf"]), 1e-9)  # identical renders

    def test_known_preview_offset_is_recovered(self):
        # Move the rule itself 1.0 device px down in the PDF (a matrix translation would
        # move the pixmap origin too, and so cancel out).
        sy = 1123.0 / PH
        shifted = _pdf(lambda p: p.draw_line((50, 300.25 + 1.0 / sy), (500, 300.25 + 1.0 / sy),
                                             color=(0, 0, 0), width=1.2))
        h = self._h(self._analyse(_render(shifted)))
        self.assertAlmostEqual(h["disp"]["prev_minus_pdf"], 1.0, delta=0.12)
        self.assertAlmostEqual(h["disp"]["prev_minus_A"], 1.0, delta=0.12)
        self.assertLess(abs(h["disp"]["pdf_minus_A"]), 0.1)

    def test_crossing_vertical_rule_removes_its_footprint_columns(self):
        h = self._h(self._analyse(self.pdf))
        span_px = h["span_A"][1] - h["span_A"][0]
        removed = (span_px - 2 * rg.END_TRIM) - h["clean_cols"]
        self.assertTrue(2 <= removed <= 8, removed)

    def test_parallel_rules_within_band_are_grouped(self):
        def draw(p):
            p.draw_line((50, 500.0), (500, 500.0), color=(0, 0, 0), width=1.0)
            p.draw_line((50, 501.5), (500, 501.5), color=(0, 0, 0), width=1.0)

        d = _pdf(draw)
        pdf = _render(d)
        res = rg.analyse_page(d[0], pdf, pdf, (794, 1123), (794, 1123), "", "", "p1")
        self.assertTrue(res["rules"])
        for r in res["rules"]:
            self.assertTrue(r["grouped"])
            self.assertIsNone(r["disp"])
            self.assertIn("expected_sse", r)


if __name__ == "__main__":
    unittest.main()
