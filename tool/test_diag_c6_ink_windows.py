"""Tool tests for diag_c6_ink_windows.py (synthetic inputs).

These test the diagnostic's logic only. They are NOT evidence about the real
fixture: the real measurements are the CI notices of the visual-parity job.
The end-to-end test swaps pdftoppm for MuPDF at the same scale (a stand-in),
so it runs without poppler; the CI job uses pdftoppm itself.
"""
import json
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pymupdf  # noqa: E402

import diag_c6_ink_windows as ink  # noqa: E402
import diag_c6_text_positions as tp  # noqa: E402


def _black_block(size=40, block=(10, 10, 30, 30)):
    g = np.full((size, size), 255.0, np.float32)
    x0, y0, x1, y1 = block
    g[y0:y1, x0:x1] = 0.0
    return g


class GeometryAndCoverageTests(unittest.TestCase):
    def test_window_maps_points_to_pixels(self):
        # 3 pt = 4 px at 96 dpi; PAD adds 1 px on each side.
        self.assertEqual(ink.window_of(3.0, 6.0, 0.0, 3.0), (3, -1, 9, 5))

    def test_solid_block_mass_core_and_dark(self):
        g = _black_block()
        win = (10, 10, 30, 30)
        bg, ring_cov, cov = ink.side_coverage(g, win)
        self.assertAlmostEqual(bg, 255.0)
        self.assertAlmostEqual(ring_cov, 0.0)
        m = ink.metrics(cov)
        self.assertAlmostEqual(m['mass'], 400.0)
        self.assertEqual(m['core'], 400.0)
        self.assertEqual(m['dark'], 400.0)
        self.assertEqual(m['edge'], 0.0)

    def test_ring_ink_is_detected(self):
        g = _black_block(block=(10, 10, 30, 30))
        g[10:30, 8] = 0.0  # ink two pixels left of the window
        _, ring_cov, _ = ink.side_coverage(g, (10, 10, 30, 30))
        self.assertGreater(ring_cov, ink.RING_MAX_COV)

    def test_non_white_paper_is_refused(self):
        g = np.full((40, 40), 120.0, np.float32)
        bg, _, cov = ink.side_coverage(g, (10, 10, 30, 30))
        self.assertIsNone(bg)
        self.assertIsNone(cov)

    def test_binary_iou_and_edge_split(self):
        a = np.array([[1.0, 0.5, 0.0]])
        b = np.array([[1.0, 0.0, 0.0]])
        # masks at coverage >= 0.5: [1, 1, 0] and [1, 0, 0] -> IoU 1/2
        self.assertAlmostEqual(ink.binary_iou(a, b), 0.5)
        m = ink.metrics(a)
        self.assertAlmostEqual(m['edge'], 0.5)
        self.assertEqual(m['core'], 1.0)


class StatisticsTests(unittest.TestCase):
    def _record(self, line, pdf_mass, prev_mass):
        def block(mass):
            return {'mass': mass, 'dark': mass, 'core': mass, 'edge': 0.0}
        return {'page': 1, 'font': 'F', 'rtl': False, 'line': line,
                'text': 'w', 'pixels': 10, 'pdf': block(pdf_mass),
                'prev': block(prev_mass), 'ctl': block(pdf_mass),
                'iou': 1.0, 'rmse': 0.0, 'cx': 0.0, 'cy': 0.0,
                'hist_pdf': [], 'hist_prev': [],
                'shift': {name: pdf_mass for name in ink.SHIFTS}}

    def test_pooled_ratio_and_line_bootstrap(self):
        recs = [self._record('1:a', 12.0, 10.0), self._record('1:a', 12.0, 10.0),
                self._record('1:b', 12.0, 10.0), self._record('1:c', 12.0, 10.0)]
        g = ink.group_summary(recs)
        self.assertEqual(g['n_words'], 4)
        self.assertEqual(g['n_lines'], 3)
        self.assertAlmostEqual(g['R_mass']['est'], 1.2)
        lo, hi = g['R_mass']['ci95']
        self.assertLessEqual(lo, 1.2)
        self.assertGreaterEqual(hi, 1.2)

    def test_empty_group(self):
        self.assertEqual(ink.group_summary([]), {'n_words': 0})


class EndToEndTests(unittest.TestCase):
    def _make_inputs(self, tmp):
        artifacts = os.path.join(tmp, 'visual_parity')
        out_dir = os.path.join(artifacts, 'c6diag', 'text_positions')
        os.makedirs(out_dir)
        doc = pymupdf.open()
        # 794x1123 px at 96 dpi = 595.5 x 842.25 pt
        page = doc.new_page(width=595.5, height=842.25)
        words = [('Hello', 80.0, 120.0), ('World', 200.0, 120.0),
                 ('Second', 80.0, 300.0)]
        for text, x, y in words:
            page.insert_text((x, y), text, fontsize=12, fontname='helv')
        pdf_path = os.path.join(artifacts, 'vector.pdf')
        doc.save(pdf_path)
        doc.close()

        pdf_words = tp.extract_pdf_words(pdf_path)[1]['words']
        lines = {}
        for w in pdf_words:
            key = round(w['baseline'], 3)
            run = {
                'text': w['text'], 'measured': True, 'isMath': False,
                'fontFamily': 'Tajawal', 'fontSizePt': 12.0, 'bold': False,
                'rtl': False, 'previewBaselinePt': w['baseline'],
                'innerAscentPt': 9.0, 'innerDescentPt': 3.0,
                'previewWords': [{'index': 0, 'text': w['text'],
                                  'leftPt': w['x0'], 'rightPt': w['x1'],
                                  'boxCount': 1, 'countsMatchLayout': True}],
                'layoutWords': [{'text': w['text'], 'xPt': w['x0']}],
            }
            lines.setdefault(key, []).append(run)
        data = {
            'schema': tp.SCHEMA, 'scalePxPerPt': 4 / 3,
            'pages': [{'page': 1, 'widthPt': 595.5, 'heightPt': 842.25,
                       'lines': [{'source': 'block', 'baselinePt': b,
                                  'layoutAscentPt': 9.0,
                                  'layoutDescentPt': 3.0,
                                  'layoutLeadingPt': 0.0, 'runs': runs}
                                 for b, runs in sorted(lines.items())]}],
        }
        with open(os.path.join(out_dir, tp.PREVIEW_NAME), 'w',
                  encoding='utf-8') as fh:
            json.dump(data, fh)
        # Preview stand-in: the same PDF rendered at the same scale.
        doc = pymupdf.open(pdf_path)
        g, _ = ink.gray_mupdf(doc, 1)
        doc.close()
        arr = np.clip(g, 0, 255).astype(np.uint8)
        pymupdf.Pixmap(pymupdf.csGRAY, ink.W, ink.H, arr.tobytes(), False).save(
            os.path.join(artifacts, 'preview_page_1.png'))
        return artifacts, out_dir

    def test_run_on_identical_rasters_gives_unit_ratio(self):
        original = ink.gray_poppler
        try:
            def stand_in(pdf_path, pno, tmpdir):
                doc = pymupdf.open(pdf_path)
                try:
                    return ink.gray_mupdf(doc, pno)
                finally:
                    doc.close()
            ink.gray_poppler = stand_in
            with tempfile.TemporaryDirectory() as tmp:
                artifacts, _ = self._make_inputs(tmp)
                self.assertEqual(ink.run(artifacts), 0)
                out_dir = os.path.join(artifacts, ink.REL_DIR)
                with open(os.path.join(out_dir, ink.SUMMARY_JSON),
                          encoding='utf-8') as fh:
                    summary = json.load(fh)
        finally:
            ink.gray_poppler = original
        self.assertGreater(summary['accepted'], 0)
        g = summary['groups']['all']
        self.assertAlmostEqual(g['R_mass']['est'], 1.0, places=6)
        self.assertAlmostEqual(g['median_iou'], 1.0)
        self.assertAlmostEqual(g['median_rmse'], 0.0, places=6)

    def test_missing_inputs_is_non_gating(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ink.run(tmp), 0)
            self.assertEqual(ink.main(['prog', tmp]), 0)
            self.assertEqual(ink.main(['prog']), 0)


if __name__ == '__main__':
    unittest.main()
