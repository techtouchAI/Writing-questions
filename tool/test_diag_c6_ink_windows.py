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
    def test_window_maps_points_to_pixels_and_pad(self):
        # 3 pt = 4 px at 96 dpi; PAD adds px on each side.
        self.assertEqual(ink.window_of(3.0, 6.0, 0.0, 3.0), (3, -1, 9, 5))
        self.assertEqual(ink.window_of(3.0, 6.0, 0.0, 3.0, pad=0), (4, 0, 8, 4))

    def test_gap_sign_and_touching(self):
        a = (0, 0, 10, 10)
        self.assertEqual(ink.gap_of(a, (10, 0, 20, 10)), 0)  # touching
        self.assertLess(ink.gap_of(a, (9, 0, 20, 10)), 0)  # overlap
        self.assertEqual(ink.gap_of(a, (13, 0, 20, 10)), 3)  # separated

    def test_solid_block_mass_core_and_dark(self):
        g = _black_block()
        bg, ring_cov, cov = ink.side_coverage(g, (10, 10, 30, 30))
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


class MeasureAndGridTests(unittest.TestCase):
    def test_grid_recovers_known_offset(self):
        # Preview block at x 10..30. PDF block is one pixel further right.
        gq = _black_block(block=(10, 10, 30, 30))
        gp = _black_block(block=(11, 10, 31, 30))
        gm = gp.copy()
        win = (8, 8, 33, 33)
        prev = {'font': 'F', 'rtl': False, 'baseline': 20.0, 'text': 'w'}
        pdf = {}
        rec, reason = ink._measure(win, gp, gq, gm, 1, prev, pdf)
        self.assertIsNone(reason)
        iou = {k: v['iou'] for k, v in rec['grid'].items() if v is not None}
        best = max(iou, key=iou.get)
        # The PDF window moved by (+1, 0) lands on the offset ink.
        self.assertEqual(best, '1,0')
        self.assertAlmostEqual(iou['1,0'], 1.0)
        self.assertLess(iou['0,0'], 1.0)

    def test_shift_outside_frame_is_none(self):
        gq = _black_block(block=(0, 0, 4, 4))
        gp = gq.copy()
        rec, _ = ink._measure((0, 0, 6, 6), gp, gq, gp.copy(), 1,
                              {'font': 'F', 'rtl': False, 'baseline': 1.0,
                               'text': 'w'}, {})
        self.assertIsNone(rec['grid']['-1,0'])
        self.assertIsNotNone(rec['grid']['0,0'])


class StatisticsTests(unittest.TestCase):
    def _record(self, line, pdf_mass, prev_mass):
        def block(mass):
            return {'mass': mass, 'dark': mass, 'core': mass, 'edge': 0.0}
        grid = {f'{dx},{dy}': dict(block(pdf_mass), iou=1.0)
                for dx, dy in ink.SHIFTS}
        return {'page': 1, 'font': 'F', 'rtl': False, 'line': line,
                'text': 'w', 'pixels': 10, 'pdf': block(pdf_mass),
                'prev': block(prev_mass), 'ctl': block(pdf_mass),
                'iou': 1.0, 'rmse': 0.0, 'cx': 0.0, 'cy': 0.0,
                'hist_pdf': [], 'hist_prev': [], 'grid': grid}

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
        self.assertEqual(len(g['grid']), len(ink.SHIFTS))
        self.assertAlmostEqual(g['grid'][4]['R_mass'], 1.2)

    def test_empty_group(self):
        self.assertEqual(ink.group_summary([]),
                         {'n_words': 0, 'n_lines': 0})


class VerdictTests(unittest.TestCase):
    def _g(self, words, lines, spread):
        grid = []
        for n, (dx, dy) in enumerate(ink.SHIFTS):
            grid.append({'dx': dx, 'dy': dy, 'R_mass': 1.2 + spread * n / 8,
                         'R_core': 1.5, 'R_edge': 1.0, 'R_dark': 1.2,
                         'median_iou': 0.5, 'n_valid': words})
        return {'n_words': words, 'n_lines': lines, 'grid': grid,
                'R_mass': {'est': 1.2, 'ci95': [1.1, 1.3]},
                'R_core': {'est': 1.5, 'ci95': [1.2, 1.8]},
                'R_edge': {'est': 1.0, 'ci95': [0.9, 1.1]}}

    def test_small_sample_is_inconclusive(self):
        self.assertTrue(ink.verdict(self._g(7, 4, 0.0)).startswith('INCONCLUSIVE'))

    def test_shift_sensitive_is_inconclusive(self):
        self.assertTrue(ink.verdict(self._g(50, 10, 0.5)).startswith('INCONCLUSIVE'))

    def test_stable_is_stable(self):
        self.assertTrue(ink.verdict(self._g(50, 10, 0.02)).startswith('STABLE'))

    def test_pattern_does_not_name_a_cause(self):
        text = ink.pattern(self._g(50, 10, 0.0))
        self.assertIn('solid-core excess', text)
        self.assertNotIn('stroke weight', text)
        self.assertNotIn('edge smoothing', text)


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
        return artifacts

    def test_run_on_identical_rasters(self):
        original = ink.gray_poppler

        def stand_in(pdf_path, pno, tmpdir):
            doc = pymupdf.open(pdf_path)
            try:
                return ink.gray_mupdf(doc, pno)
            finally:
                doc.close()

        old_summary = os.environ.get('GITHUB_STEP_SUMMARY')
        try:
            ink.gray_poppler = stand_in
            with tempfile.TemporaryDirectory() as tmp:
                summary_path = os.path.join(tmp, 'step_summary.md')
                os.environ['GITHUB_STEP_SUMMARY'] = summary_path
                artifacts = self._make_inputs(tmp)
                self.assertEqual(ink.run(artifacts), 0)
                out_dir = os.path.join(artifacts, ink.REL_DIR)
                with open(os.path.join(out_dir, ink.SUMMARY_JSON),
                          encoding='utf-8') as fh:
                    summary = json.load(fh)
                self.assertTrue(os.path.isfile(
                    os.path.join(out_dir, ink.SUMMARY_TXT)))
                with open(summary_path, encoding='utf-8') as fh:
                    self.assertIn('C6 ink windows', fh.read())
        finally:
            ink.gray_poppler = original
            if old_summary is None:
                os.environ.pop('GITHUB_STEP_SUMMARY', None)
            else:
                os.environ['GITHUB_STEP_SUMMARY'] = old_summary
        self.assertEqual(set(summary['groups_by_selection']), {'R', 'P0'})
        for name, grp in summary['groups_by_selection'].items():
            s = grp['summary']
            self.assertGreater(s['n_words'], 0, name)
            self.assertAlmostEqual(s['R_mass']['est'], 1.0, places=6, msg=name)
            self.assertAlmostEqual(s['median_iou'], 1.0, msg=name)
            centre = [r for r in s['grid'] if (r['dx'], r['dy']) == (0, 0)][0]
            self.assertAlmostEqual(centre['R_mass'], 1.0, places=6, msg=name)
            # Three words and two lines: the sample rule must say so.
            self.assertTrue(ink.verdict(s).startswith('INCONCLUSIVE'), name)
            self.assertTrue(grp['lines'])

    def test_missing_inputs_is_non_gating(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ink.run(tmp), 0)
            self.assertEqual(ink.main(['prog', tmp]), 0)
            self.assertEqual(ink.main(['prog']), 0)


class AuditTests(unittest.TestCase):
    """Checks added after the audit: sign convention, grid isolation, gating."""

    def _block_pair(self, dx, dy):
        # Preview block at x 10..30, y 10..30; PDF block offset by (dx, dy).
        gq = _black_block(block=(10, 10, 30, 30))
        gp = _black_block(block=(10 + dx, 10 + dy, 30 + dx, 30 + dy))
        return gp, gq

    def _measure_pair(self, dx, dy):
        gp, gq = self._block_pair(dx, dy)
        rec, _ = ink._measure((8, 8, 33, 33), gp, gq, gp.copy(), 1,
                              {'font': 'F', 'rtl': False, 'baseline': 20.0,
                               'text': 'w'}, {})
        return rec

    def test_dy_sign_ink_below_gives_positive_dy(self):
        rec = self._measure_pair(0, 1)  # PDF ink one row lower
        iou = {k: v['iou'] for k, v in rec['grid'].items() if v is not None}
        self.assertEqual(max(iou, key=iou.get), '0,1')

    def test_dy_sign_ink_above_gives_negative_dy(self):
        rec = self._measure_pair(0, -1)  # PDF ink one row higher
        iou = {k: v['iou'] for k, v in rec['grid'].items() if v is not None}
        self.assertEqual(max(iou, key=iou.get), '0,-1')

    def test_zero_shift_equals_base_measurement(self):
        rec = self._measure_pair(1, 0)
        self.assertAlmostEqual(rec['grid']['0,0']['mass'], rec['pdf']['mass'])
        self.assertAlmostEqual(rec['grid']['0,0']['core'], rec['pdf']['core'])

    def _records(self, n_lines, masses):
        return [StatisticsTests()._record(f'1:{k % n_lines}', m, 10.0)
                for k, m in enumerate(masses)]

    def test_base_statistics_do_not_depend_on_grid(self):
        recs = self._records(4, [12.0, 11.0, 13.0, 12.5, 11.5])
        with_grid = ink.group_summary(recs)
        stripped = []
        for r in recs:
            c = dict(r)
            c['grid'] = {}
            stripped.append(c)
        without = ink.group_summary(stripped)
        self.assertEqual(with_grid['R_mass']['est'], without['R_mass']['est'])
        self.assertEqual(with_grid['R_core']['est'], without['R_core']['est'])

    def test_grid_uses_only_words_valid_at_every_shift(self):
        recs = self._records(4, [12.0, 12.0, 12.0, 20.0, 20.0])
        recs[3]['grid'] = dict(recs[3]['grid'])
        recs[3]['grid']['1,0'] = None  # one word lost at one shift
        g = ink.group_summary(recs)
        rows = {(r['dx'], r['dy']): r for r in g['grid']}
        self.assertEqual(rows[(0, 0)]['n_valid'], 4)
        # recs[3] (lost at shift +1,0) is removed from EVERY row. The shared
        # sample is masses 12,12,12,20 against 10 each: (56 / 40) = 1.4.
        self.assertAlmostEqual(rows[(0, 0)]['R_mass'], 56.0 / 40.0)
        self.assertAlmostEqual(rows[(1, 0)]['R_mass'], 56.0 / 40.0)

    def test_drawing_overlap_is_counted_not_excluded(self):
        recs = self._records(4, [12.0, 11.0, 13.0, 12.5, 11.5])
        recs[0]['drawing_overlap'] = True
        g = ink.group_summary(recs)
        self.assertEqual(g['n_words'], 5)
        self.assertEqual(g['n_drawing_overlap'], 1)

    def test_verdict_crossing_one_is_inconclusive(self):
        g = VerdictTests()._g(50, 10, 0.0)
        g['grid'][0]['R_mass'] = 0.95  # one shift on the other side of 1.0
        g['grid'][1]['R_mass'] = 1.2
        self.assertTrue(ink.verdict(g).startswith('INCONCLUSIVE'))

    def test_pattern_is_not_assessed_when_inconclusive(self):
        g = VerdictTests()._g(7, 4, 0.0)
        self.assertEqual(ink.pattern(g), 'pattern: not assessed (verdict not STABLE)')


if __name__ == '__main__':
    unittest.main()
