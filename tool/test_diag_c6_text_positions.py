"""Tool tests for diag_c6_text_positions.py (synthetic inputs).

These test the diagnostic's logic only. They are NOT evidence about the real
fixture: the real measurements are the CI artifact, not these tests.
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pymupdf  # noqa: E402

import diag_c6_text_positions as d  # noqa: E402


def _pdf_word(x0, x1, baseline, size=10.0, font='F', text='w', page=1):
    return {'page': page, 'x0': x0, 'x1': x1, 'y0': baseline - 7.0,
            'y1': baseline + 2.0, 'text': text, 'baseline': baseline,
            'size': size, 'font': font, 'asc': -7.0, 'desc': 2.0}


def _prev_word(left, right, baseline, size=10.0, font='F', text='w', page=1):
    return {'page': page, 'source': 'block', 'baseline': baseline,
            'line_baseline': baseline, 'left': left, 'right': right,
            'text': text, 'font': font, 'size': size, 'rtl': False,
            'inner_asc': 7.0, 'inner_desc': 2.0, 'layout_x': left}


class MatchingTests(unittest.TestCase):
    def test_interval_iou(self):
        self.assertAlmostEqual(d.interval_iou(0, 10, 0, 10), 1.0)
        self.assertAlmostEqual(d.interval_iou(0, 10, 5, 15), 5 / 15)
        self.assertEqual(d.interval_iou(0, 1, 2, 3), 0.0)

    def test_match_is_one_to_one_and_prefers_higher_iou(self):
        pdf = [_pdf_word(0, 10, 100)]
        prev = [_prev_word(1, 11, 100), _prev_word(0, 10, 100)]
        pairs = d.match_words(pdf, prev)
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0][1], 1)

    def test_baseline_gap_beyond_tolerance_is_not_matched(self):
        pairs = d.match_words([_pdf_word(0, 10, 100)], [_prev_word(0, 10, 105)])
        self.assertEqual(pairs, [])

    def test_pair_metrics_signs(self):
        q = _pdf_word(10.5, 20.5, 101.0)
        p = _prev_word(10.0, 20.0, 100.0)
        m = d.pair_metrics(q, p)
        self.assertAlmostEqual(m['dy_pdf_preview'], 1.0)
        self.assertAlmostEqual(m['dx_left_pdf_preview'], 0.5)
        self.assertAlmostEqual(m['dx_right_pdf_preview'], 0.5)
        self.assertAlmostEqual(m['width_ratio'], 1.0)
        self.assertAlmostEqual(m['top_ratio'], 1.0)
        self.assertAlmostEqual(m['bottom_ratio'], 1.0)
        self.assertAlmostEqual(m['dx_pdf_layout'], 0.5)
        self.assertAlmostEqual(m['dy_preview_layout'], 0.0)

    def test_missing_layout_x_yields_none(self):
        p = _prev_word(10.0, 20.0, 100.0)
        p['layout_x'] = None
        m = d.pair_metrics(_pdf_word(10.0, 20.0, 100.0), p)
        self.assertIsNone(m['dx_pdf_layout'])
        self.assertIsNone(m['dx_preview_layout'])


class StatsTests(unittest.TestCase):
    def test_median_and_ci_bracket_the_median(self):
        s = d.stats(list(range(1, 11)))
        self.assertEqual(s['n'], 10)
        self.assertAlmostEqual(s['median'], 5.5)
        lo, hi = s['ci95']
        self.assertLessEqual(lo, 5.5)
        self.assertGreaterEqual(hi, 5.5)

    def test_empty_input_reports_zero(self):
        self.assertEqual(d.stats([None]), {'n': 0})


class PdfExtractionTests(unittest.TestCase):
    def test_round_trip_origin_size_and_word_tokens(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'v.pdf')
            doc = pymupdf.open()
            page = doc.new_page(width=595.28, height=841.89)
            page.insert_text((100.0, 200.0), 'Hello', fontsize=10, fontname='helv')
            page.insert_text((300.0, 200.0), 'World', fontsize=10, fontname='helv')
            doc.save(path)
            doc.close()

            got = d.extract_pdf_words(path)
            self.assertAlmostEqual(got[1]['width_pt'], 595.28, places=2)
            words = got[1]['words']
            self.assertEqual([w['text'] for w in words], ['Hello', 'World'])
            self.assertAlmostEqual(words[0]['x0'], 100.0, delta=0.05)
            self.assertAlmostEqual(words[0]['baseline'], 200.0, delta=0.05)
            self.assertAlmostEqual(words[1]['x0'], 300.0, delta=0.05)
            self.assertAlmostEqual(words[0]['size'], 10.0, delta=0.01)


class EndToEndTests(unittest.TestCase):
    def _write_inputs(self, tmp):
        artifacts = os.path.join(tmp, 'build', 'visual_parity')
        out_dir = os.path.join(artifacts, d.REL_DIR)
        os.makedirs(out_dir)
        doc = pymupdf.open()
        page = doc.new_page(width=595.28, height=841.89)
        page.insert_text((100.0, 200.0), 'Hello', fontsize=10, fontname='helv')
        page.insert_text((300.0, 200.0), 'World', fontsize=10, fontname='helv')
        doc.save(os.path.join(artifacts, 'vector.pdf'))
        doc.close()

        def word(index, text, left):
            return {'index': index, 'text': text, 'leftPt': left,
                    'rightPt': left + 10.0, 'boxCount': 1,
                    'countsMatchLayout': True}

        run = {
            'text': 'Hello World', 'xPt': 100.0, 'widthPt': 210.0,
            'advancePt': 210.0, 'layoutBaselineOffsetPt': 7.0,
            'fontFamily': 'Tajawal', 'fontSizePt': 10.0, 'bold': False,
            'italic': False, 'rtl': False, 'isMath': False, 'measured': True,
            'painterWidthPt': 210.0, 'innerBaselinePt': 7.0,
            'innerAscentPt': 7.0, 'innerDescentPt': 2.0,
            'innerHeightPt': 9.0, 'paintTopPt': 193.0,
            'previewBaselinePt': 200.0,
            'previewWords': [word(0, 'Hello', 100.0), word(1, 'World', 300.0)],
            'layoutWords': [
                {'text': 'Hello', 'xPt': 100.0, 'advancePt': 30.0,
                 'textAdvancePt': 30.0},
                {'text': 'World', 'xPt': 300.0, 'advancePt': 30.0,
                 'textAdvancePt': 30.0},
            ],
        }
        data = {
            'schema': d.SCHEMA,
            'scalePxPerPt': 4 / 3,
            'pages': [{
                'page': 1, 'widthPt': 595.28, 'heightPt': 841.89,
                'lines': [{'source': 'block', 'baselinePt': 200.0,
                           'layoutAscentPt': 7.0, 'layoutDescentPt': 2.0,
                           'layoutLeadingPt': 0.0, 'runs': [run]}],
            }],
        }
        with open(os.path.join(out_dir, d.PREVIEW_NAME), 'w',
                  encoding='utf-8') as fh:
            json.dump(data, fh)
        return artifacts, out_dir

    def test_run_writes_summary_with_two_matched_words(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifacts, out_dir = self._write_inputs(tmp)
            self.assertEqual(d.run(artifacts), 0)
            with open(os.path.join(out_dir, d.SUMMARY_JSON),
                      encoding='utf-8') as fh:
                summary = json.load(fh)
            self.assertEqual(summary['per_page']['1']['matched'], 2)
            self.assertEqual(summary['per_page']['1']['unmatched_pdf'], 0)
            dy = summary['groups']['all']['dy_pdf_preview']
            self.assertEqual(dy['n'], 2)
            self.assertAlmostEqual(dy['median'], 0.0, delta=0.05)

    def test_unmatched_reasons_are_counted(self):
        pdf = {1: {'width_pt': 10.0, 'height_pt': 10.0,
                   'words': [_pdf_word(0, 10, 100), _pdf_word(50, 60, 100),
                             _pdf_word(0, 10, 300)],
                   'words_without_chars': 0}}
        prev = [_prev_word(0, 10, 100),          # matched
                _prev_word(20, 30, 100),         # no pdf x-overlap on line
                _prev_word(0, 10, 500)]          # no pdf on baseline
        meta = {'math_runs': 0, 'unmeasured_runs': 0}
        layout = {1: {'page': 1, 'widthPt': 10.0, 'heightPt': 10.0}}
        summary = d.run_analysis(pdf, prev, meta, layout)
        dg = summary['diagnostics']
        self.assertEqual(dg['matched'], 1)
        self.assertEqual(dg['unmatched_preview_reasons'],
                         {'F|no_x_overlap': 1, 'F|no_pdf_word_on_baseline': 1})
        self.assertEqual(dg['unmatched_pdf_reasons'],
                         {'F|no_x_overlap': 1, 'F|no_preview_word_on_baseline': 1})

    def test_annotation_lines_are_condensed(self):
        summary = d.run_analysis(
            {1: {'width_pt': 595.28, 'height_pt': 841.89,
                 'words': [_pdf_word(0, 10, 100)], 'words_without_chars': 0}},
            [_prev_word(0, 10, 100)],
            {'math_runs': 0, 'unmeasured_runs': 0},
            {1: {'page': 1, 'widthPt': 595.28, 'heightPt': 841.89}},
        )
        lines = d.annotation_lines(summary)
        self.assertTrue(any(line.startswith('[all] n=1') for line in lines))
        self.assertTrue(any('dy_pdf_preview' in line for line in lines))
        self.assertFalse(any('page=1' in line for line in lines))

    def test_missing_inputs_is_non_gating(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(d.run(tmp), 0)
            self.assertEqual(d.main(['prog', tmp]), 0)
            self.assertEqual(d.main(['prog']), 0)

    def test_wrong_schema_is_non_gating(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifacts, out_dir = self._write_inputs(tmp)
            with open(os.path.join(out_dir, d.PREVIEW_NAME), 'w',
                      encoding='utf-8') as fh:
                json.dump({'schema': 'other'}, fh)
            self.assertEqual(d.main(['prog', artifacts]), 0)


if __name__ == '__main__':
    unittest.main()
