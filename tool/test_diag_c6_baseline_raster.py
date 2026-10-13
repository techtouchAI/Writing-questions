"""Synthetic unit tests for tool/diag_c6_baseline_raster.py.

These tests use generated images, not the real probe. Their output is a
synthetic check of the measurement code only, never a real measurement.
"""
import math
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import diag_c6_baseline_raster as d  # noqa: E402

H, W = 1123, 794
SIGMA = 1.5


def _lines(n=20):
    out = []
    for i in range(n):
        b = 60 + 50 * i + (i % 10) / 10.0
        out.append({'index': i, 'fraction': (i % 10) / 10.0, 'baselinePx': b})
    return out


def _render(rule, lines, offset=0.37):
    """Dark image with one Gaussian ink band per line.

    rule: 'U' centre = B + offset, 'R' centre = round(B) + offset,
          'F' centre = floor(B) + offset. Exact (no noise).
    """
    dark = [[0.0] * W for _ in range(H)]
    for ln in lines:
        b = ln['baselinePx']
        if rule == 'U':
            centre = b + offset
        elif rule == 'R':
            centre = math.floor(b + 0.5) + offset
        else:
            centre = math.floor(b) + offset
        for r in range(int(centre) - 14, int(centre) + 14):
            if not 0 <= r < H:
                continue
            v = math.exp(-((r + 0.5 - centre) ** 2) / (2 * SIGMA * SIGMA))
            for x in range(100, 160):
                dark[r][x] = max(dark[r][x], v)
    return dark


class CentroidTests(unittest.TestCase):
    def test_centroid_recovers_subpixel_centre(self):
        # SYNTHETIC: a Gaussian band with a known continuous centre.
        for centre in (200.0, 200.25, 200.5, 200.8):
            dark = [[0.0] * W for _ in range(H)]
            for r in range(H):
                v = math.exp(-((r + 0.5 - centre) ** 2) / (2 * SIGMA * SIGMA))
                for x in range(100, 160):
                    dark[r][x] = v
            c, edge = d.centroid_y(dark, 200.0)
            self.assertAlmostEqual(c, centre, delta=0.02, msg=f'centre {centre}')
            self.assertLess(edge, d.EDGE_MASS_MAX)

    def test_edge_mass_flags_ink_crossing_window(self):
        # SYNTHETIC: ink centred on the bottom edge row of the window.
        b = 200.0
        dark = [[0.0] * W for _ in range(H)]
        for r in range(H):
            v = math.exp(-((r + 0.5 - (b + d.WIN_DOWN)) ** 2) / (2 * SIGMA * SIGMA))
            for x in range(100, 160):
                dark[r][x] = v
        _, edge = d.centroid_y(dark, b)
        self.assertGreater(edge, d.EDGE_MASS_MAX)


class RuleTests(unittest.TestCase):
    def test_each_rule_is_identified(self):
        # SYNTHETIC: the fit must recover the rule that generated the centroids.
        lines = _lines()
        for rule in ('U', 'R', 'F'):
            dark = _render(rule, lines)
            cs = [d.centroid_y(dark, ln['baselinePx'])[0] for ln in lines]
            fit = d.fit_rule(cs, [ln['baselinePx'] for ln in lines])
            self.assertEqual(fit['best'], rule, msg=str(fit))
            self.assertLess(fit['std'][rule], 0.02)


class VerdictTests(unittest.TestCase):
    def _verdict(self, rule_p, rule_q, n=20):
        lines = _lines(n)
        prev = _render(rule_p, lines)
        pdf = _render(rule_q, lines)
        return d.analyse(prev, pdf, lines)

    def test_same_rule_is_reported_same(self):
        # SYNTHETIC: identical rule on both sides.
        res = self._verdict('R', 'R')
        self.assertEqual(res['verdict'], 'SAME_RULE', msg=res['verdictDetail'])

    def test_different_rules_are_reported_different(self):
        # SYNTHETIC: preview rounds, pdf does not.
        res = self._verdict('R', 'U')
        self.assertEqual(res['verdict'], 'DIFFERENT_RULE',
                         msg=res['verdictDetail'])

    def test_floor_versus_round_is_detected(self):
        # SYNTHETIC: floor versus round.
        res = self._verdict('F', 'R')
        self.assertEqual(res['verdict'], 'DIFFERENT_RULE',
                         msg=res['verdictDetail'])

    def test_too_few_lines_is_inconclusive(self):
        # SYNTHETIC: sample-size guard (provisional MIN_LINES).
        res = self._verdict('R', 'U', n=10)
        self.assertEqual(res['verdict'], 'INCONCLUSIVE')
        self.assertIn('only 10 lines', res['verdictDetail'])

    def test_missing_ink_is_never_reported_as_same_rule(self):
        # SYNTHETIC: an empty PDF raster must not produce SAME_RULE (NaN guard).
        lines = _lines()
        empty = [[0.0] * W for _ in range(H)]
        res = d.analyse(_render('R', lines), empty, lines)
        self.assertEqual(res['verdict'], 'INCONCLUSIVE', msg=res['verdictDetail'])
        self.assertIn('no ink', res['verdictDetail'])

    def test_no_rule_fits_is_reported(self):
        # SYNTHETIC: deterministic jitter larger than the fit limit.
        lines = _lines()
        base_dark = _render('U', lines)
        jitter = [0.3 * math.sin(7.0 * i) for i in range(len(lines))]
        cs = []
        for ln, j in zip(lines, jitter):
            cs.append(d.centroid_y(base_dark, ln['baselinePx'])[0] + j)
        prev_fit = d.fit_rule(cs, [ln['baselinePx'] for ln in lines])
        good_fit = d.fit_rule(
            [d.centroid_y(base_dark, ln['baselinePx'])[0] for ln in lines],
            [ln['baselinePx'] for ln in lines])
        label, _ = d.verdict(prev_fit, good_fit, len(lines))
        self.assertEqual(label, 'NO_RULE_FITS')


class EmittedBaselineTests(unittest.TestCase):
    def test_exact_match_has_zero_error(self):
        # SYNTHETIC: spans exactly at the intended baselines.
        intended = [100.0, 150.25, 200.5]
        spans = [{'y': y} for y in intended]
        errs = d.match_origins(intended, spans)
        self.assertEqual(errs, [0.0, 0.0, 0.0])

    def test_offset_is_reported_with_sign(self):
        # SYNTHETIC: a -0.2 pt error on one line only.
        intended = [100.0, 150.0]
        spans = [{'y': 99.8}, {'y': 150.0}]
        errs = d.match_origins(intended, spans)
        self.assertAlmostEqual(errs[0], -0.2, places=9)
        self.assertEqual(errs[1], 0.0)

    def test_missing_span_is_nan_not_zero(self):
        # SYNTHETIC: no span near the intended baseline must not look like 0.
        errs = d.match_origins([100.0], [{'y': 300.0}])
        self.assertTrue(math.isnan(errs[0]))

    def test_emitted_ok_flag(self):
        # SYNTHETIC: analyse() reports emittedOk from the tolerance.
        lines = _lines()
        ok = d.analyse(_render('R', lines), _render('R', lines), lines,
                       emitted_pt=[0.0] * len(lines))
        bad = d.analyse(_render('R', lines), _render('R', lines), lines,
                        emitted_pt=[0.05] * len(lines))
        self.assertTrue(ok['emittedOk'])
        self.assertFalse(bad['emittedOk'])


class MainContractTests(unittest.TestCase):
    def test_missing_probe_is_non_fatal(self):
        # SYNTHETIC: the step must not fail the job when the probe is absent.
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(d.main(['x', tmp]), 0)



def _group_result(delta_std, rows=None):
    # SYNTHETIC: minimal result dict for the decision and control functions.
    return {'deltaStdPx': delta_std, 'rows': rows or []}


def _rows(pdf_offsets, fractions=None):
    # SYNTHETIC: rows with baselines on a 27 px grid and chosen pdf centroids.
    out = []
    for k, off in enumerate(pdf_offsets):
        frac = round(0.025 + 0.05 * k, 3) if fractions is None else fractions[k]
        base = 40 + 27 * k + frac
        out.append({'fraction': frac, 'baselinePx': base,
                    'pdfCentroid': math.floor(base) + off})
    return out


class GroupingAndDecisionTests(unittest.TestCase):
    def test_split_groups_keeps_order_and_defaults_to_a(self):
        # SYNTHETIC
        lines = [{'group': 'B'}, {}, {'group': 'A'}, {'group': 'B'}]
        self.assertEqual(d.split_groups(lines),
                         {'B': [0, 3], 'A': [1, 2]})

    def test_control_is_zero_when_pdf_sides_are_identical(self):
        # SYNTHETIC: identical PDF centroid relative to floor(B) in both groups
        rows = _rows([-3.7] * 20)
        rows_b = _rows([-3.7] * 20)
        for r in rows_b:
            r['baselinePx'] += 540
            r['pdfCentroid'] += 540
        res = {'A': {'rows': rows}, 'B': {'rows': rows_b}}
        self.assertAlmostEqual(d.pdf_control_max_diff(res), 0.0, places=9)

    def test_control_detects_a_pdf_side_difference(self):
        # SYNTHETIC: group B's PDF centroid is 0.2 px lower at one fraction
        rows = _rows([-3.7] * 20)
        rows_b = _rows([-3.7] * 20)
        for r in rows_b:
            r['baselinePx'] += 540
            r['pdfCentroid'] += 540
        rows_b[5]['pdfCentroid'] += 0.2
        res = {'A': {'rows': rows}, 'B': {'rows': rows_b}}
        self.assertAlmostEqual(d.pdf_control_max_diff(res), 0.2, places=9)

    def test_control_is_nan_without_ink(self):
        # SYNTHETIC: a missing centroid must not be reported as zero
        rows = _rows([-3.7] * 20)
        rows[3]['pdfCentroid'] = float('nan')
        rows_b = _rows([-3.7] * 20)
        res = {'A': {'rows': rows}, 'B': {'rows': rows_b}}
        self.assertTrue(math.isnan(d.pdf_control_max_diff(res)))

    def test_decision_height_explains(self):
        # SYNTHETIC: B constant (<=0.05), A fraction-dependent (>=0.10)
        res = {'A': _group_result(0.446), 'B': _group_result(0.02)}
        self.assertTrue(d.decide_height(res, 0.0).startswith(
            'HEIGHT_EXPLAINS_PROBE_MISMATCH'))

    def test_decision_height_does_not_explain(self):
        # SYNTHETIC: both groups fraction-dependent
        res = {'A': _group_result(0.3), 'B': _group_result(0.25)}
        self.assertTrue(d.decide_height(res, 0.0).startswith(
            'HEIGHT_DOES_NOT_EXPLAIN'))

    def test_decision_invalid_control_overrides(self):
        # SYNTHETIC: a PDF difference means the factor is not isolated
        res = {'A': _group_result(0.446), 'B': _group_result(0.02)}
        self.assertTrue(d.decide_height(res, 0.3).startswith(
            'INVALID_CONTROL'))

    def test_decision_mixed_is_inconclusive(self):
        # SYNTHETIC: B between the two limits
        res = {'A': _group_result(0.446), 'B': _group_result(0.08)}
        self.assertTrue(d.decide_height(res, 0.0).startswith(
            'INCONCLUSIVE'))

    def test_decision_no_mismatch_is_named(self):
        # SYNTHETIC: both groups constant -> no mismatch, not "mixed"
        res = {'A': _group_result(0.0), 'B': _group_result(0.01)}
        self.assertTrue(d.decide_height(res, 0.0).startswith(
            'NO_MISMATCH_IN_PROBE'))

    def test_decision_nan_control_is_not_called_invalid(self):
        # SYNTHETIC: missing ink in the control is inconclusive, not INVALID
        res = {'A': _group_result(0.446), 'B': _group_result(0.02)}
        self.assertTrue(d.decide_height(res, float('nan')).startswith(
            'INCONCLUSIVE'))


class FontDecisionTests(unittest.TestCase):
    def _res(self, std, mean=0.0):
        # SYNTHETIC: minimal result dict for decide_fonts.
        return {'deltaStdPx': std, 'deltaMeanPx': mean, 'rows': []}

    def test_all_constant_is_no_mismatch(self):
        # SYNTHETIC
        res = {f: self._res(0.01) for f in ('T', 'A', 'N', 'R')}
        self.assertTrue(d.decide_fonts(res).startswith('NO_MISMATCH_IN_PROBE'))

    def test_same_mismatch_in_all_fonts_is_independent(self):
        # SYNTHETIC: std ~0.45 everywhere, means nearly equal
        res = {f: self._res(0.45, -0.2) for f in ('T', 'A', 'N', 'R')}
        self.assertTrue(d.decide_fonts(res).startswith(
            'MISMATCH_FONT_INDEPENDENT'))

    def test_std_differing_across_fonts_is_dependent(self):
        # SYNTHETIC: all fonts mismatched, but std spread 0.3 px
        res = {'T': self._res(0.45), 'A': self._res(0.15),
               'N': self._res(0.40), 'R': self._res(0.45)}
        self.assertTrue(d.decide_fonts(res).startswith(
            'MISMATCH_FONT_DEPENDENT'))

    def test_mean_offset_differing_across_fonts_is_dependent(self):
        # SYNTHETIC: same std, but a 0.5 px constant offset in one font
        res = {'T': self._res(0.45, -0.2), 'A': self._res(0.45, 0.3),
               'N': self._res(0.45, -0.2), 'R': self._res(0.45, -0.2)}
        self.assertTrue(d.decide_fonts(res).startswith(
            'MISMATCH_FONT_DEPENDENT'))

    def test_mixed_is_inconclusive(self):
        # SYNTHETIC: one font constant, the others mismatched
        res = {'T': self._res(0.01), 'A': self._res(0.45),
               'N': self._res(0.45), 'R': self._res(0.45)}
        self.assertTrue(d.decide_fonts(res).startswith('INCONCLUSIVE'))

    def test_nan_is_not_reported_as_constant(self):
        # SYNTHETIC: a NaN delta must never become NO_MISMATCH
        res = {'T': self._res(float('nan')), 'A': self._res(0.01)}
        self.assertTrue(d.decide_fonts(res).startswith('INCONCLUSIVE'))


class PerLineWindowTests(unittest.TestCase):
    def test_per_line_window_is_used(self):
        # SYNTHETIC: ink only at columns 300..340. The default window (60..260)
        # sees nothing; a per-line window that covers it recovers the centroid.
        lines = []
        dark = [[0.0] * W for _ in range(H)]
        for k, b in enumerate([200.0, 260.3]):
            centre = math.floor(b) + 0.37
            for r in range(int(centre) - 12, int(centre) + 12):
                for x in range(300, 340):
                    dark[r][x] = max(dark[r][x], math.exp(
                        -((r + 0.5 - centre) ** 2) / (2 * SIGMA * SIGMA)))
            lines.append({'index': k, 'fraction': 0.3, 'baselinePx': b,
                          'winX0': 290, 'winX1': 350})
        res = d.analyse(dark, dark, lines)
        for row in res['rows']:
            self.assertFalse(math.isnan(row['previewCentroid']))
        default = [dict(ln) for ln in lines]
        for ln in default:
            ln.pop('winX0'); ln.pop('winX1')
        res_default = d.analyse(dark, dark, default)
        self.assertTrue(all(math.isnan(r['previewCentroid'])
                            for r in res_default['rows']))


class MeasurementValidityTests(unittest.TestCase):
    def _res(self, centroids, std=0.45):
        # SYNTHETIC: rows with given preview centroids.
        rows = [{'previewCentroid': c, 'fraction': 0.1} for c in centroids]
        return {'deltaStdPx': std, 'deltaMeanPx': 0.0, 'rows': rows}

    def test_identical_groups_are_invalid_not_a_result(self):
        # SYNTHETIC: two groups with identical centroids -> invalid measurement,
        # even though their deltas look like a clear mismatch
        c = [56.0 + 0.1 * i for i in range(20)]
        res = {'A': self._res(c), 'B': self._res(c)}
        self.assertTrue(d.decide_fonts(res).startswith('INVALID_MEASUREMENT'))

    def test_different_groups_are_not_flagged(self):
        # SYNTHETIC: groups with different centroids pass the validity check
        res = {'A': self._res([56.0 + 0.1 * i for i in range(20)]),
               'B': self._res([56.2 + 0.1 * i for i in range(20)])}
        self.assertFalse(d.decide_fonts(res).startswith('INVALID_MEASUREMENT'))


class CrashNoticeTests(unittest.TestCase):
    def test_unexpected_exception_is_published_not_silent(self):
        # SYNTHETIC: a crash inside the analyser must become a notice and must
        # not fail the step (exit 0), so it cannot vanish from the annotations.
        import contextlib
        import io
        real = d._main

        def boom(argv):
            raise RuntimeError('synthetic failure')

        d._main = boom
        try:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = d.main(['x', '.'])
        finally:
            d._main = real
        self.assertEqual(rc, 0)
        self.assertIn('analyser crashed', buf.getvalue())
        self.assertIn('synthetic failure', buf.getvalue())


class WindowTypeTests(unittest.TestCase):
    def test_float_window_bounds_are_accepted(self):
        # SYNTHETIC: Dart may write 16.0 / 166.0. The analyser must not crash
        # on float slice bounds (CI run 38467535469 failed with TypeError).
        dark = [[0.0] * W for _ in range(H)]
        b = 200.0
        centre = math.floor(b) + 0.37
        for r in range(int(centre) - 12, int(centre) + 12):
            for x in range(20, 80):
                dark[r][x] = math.exp(-((r + 0.5 - centre) ** 2) / (2 * SIGMA * SIGMA))
        lines = [{'index': 0, 'fraction': 0.37, 'baselinePx': b,
                  'winX0': 16.0, 'winX1': 166.0}]
        res = d.analyse(dark, dark, lines)
        self.assertFalse(math.isnan(res['rows'][0]['previewCentroid']))
        self.assertAlmostEqual(res['rows'][0]['previewCentroid'], centre, places=1)


def _bar(dark, edge, x0=100, x1=160, height=10.0):
    """SYNTHETIC flat-bottomed bar: ink above `edge`, partial bottom row."""
    top = edge - height
    for r in range(H):
        cover = min(max(min(r + 1, edge) - max(r, top), 0.0), 1.0)
        if cover > 0:
            for x in range(x0, x1):
                dark[r][x] = max(dark[r][x], cover)


class BottomEdgeTests(unittest.TestCase):
    def test_bottom_edge_recovers_subpixel_edge(self):
        # SYNTHETIC: a bar whose bottom edge is at a known fractional position.
        for edge in (200.0, 200.1, 200.37, 200.5, 200.93):
            dark = [[0.0] * W for _ in range(H)]
            _bar(dark, edge)
            got, cols = d.bottom_edge(dark, 200.0, 90, 170)
            self.assertAlmostEqual(got, edge, places=3, msg=f'edge {edge}')
            self.assertEqual(cols, 60)

    def test_no_ink_gives_nan_not_zero(self):
        # SYNTHETIC: an empty window must not produce a number.
        dark = [[0.0] * W for _ in range(H)]
        got, cols = d.bottom_edge(dark, 200.0, 90, 170)
        self.assertTrue(math.isnan(got))
        self.assertEqual(cols, 0)


class RoundingModelTests(unittest.TestCase):
    def test_wrap_maps_into_half_open_unit_interval(self):
        for x, want in ((0.0, 0.0), (0.4, 0.4), (0.6, -0.4), (-0.5, -0.5),
                        (1.25, 0.25), (-1.75, 0.25)):
            self.assertAlmostEqual(d.wrap(x), want, places=9, msg=str(x))

    def test_fit_recovers_delta_of_a_rounding_model(self):
        # SYNTHETIC: edge = round(B + delta) + 3 for several true deltas.
        baselines = [60.0 + 50 * i + 0.025 + 0.05 * i for i in range(20)]
        for true in (-0.3, 0.1, 0.35):
            edges = [math.floor(b + true + 0.5) + 3.0 for b in baselines]
            fit = d.fit_delta(edges, baselines)
            # Resolution is half the fraction spacing (0.05 / 2 = 0.025 px).
            self.assertLess(abs(d.wrap(fit['delta'] - true)), 0.026, msg=str(true))
            self.assertLess(fit['std'], 1e-9)

    def test_prediction_matches_rounded_paint_origin(self):
        # SYNTHETIC: the preview model is edge = round(B - inner) + inner.
        # The fitted delta must equal predict_delta(inner) (mod 1).
        baselines = [60.0 + 50 * i + 0.025 + 0.05 * i for i in range(20)]
        for inner in (0.2, 0.9, 13.37, 14.6):
            edges = [round(b - inner) + inner for b in baselines]
            fit = d.fit_delta(edges, baselines)
            err = d.wrap(fit['delta'] - d.predict_delta(inner))
            self.assertLess(abs(err), 0.026, msg=f'inner {inner} err {err}')

    def test_step_is_located_between_rows(self):
        # SYNTHETIC: offsets jump by 1 px between fractions 0.575 and 0.625.
        fr = [0.025 + 0.05 * i for i in range(20)]
        off = [-0.2 if f < 0.6 else -1.2 for f in fr]
        steps = d.edge_steps(off, fr)
        self.assertEqual(steps, ['0.575..0.625'])

    def test_no_step_is_reported_as_no_step(self):
        # SYNTHETIC: a constant offset has no step.
        fr = [0.025 + 0.05 * i for i in range(20)]
        self.assertEqual(d.edge_steps([-0.3] * 20, fr), [])


class EdgeEndToEndTests(unittest.TestCase):
    def _image(self, model, lines, inner):
        dark = [[0.0] * W for _ in range(H)]
        for ln in lines:
            b = ln['baselinePx']
            if model == 'rounded_origin':
                edge = round(b - inner) + inner
            elif model == 'unsnapped':
                edge = b
            else:  # 'floor': pdf-like, edge = floor(B) + 0.0
                edge = math.floor(b)
            _bar(dark, edge, 100 + 0 * 1, 160)
        return dark

    def _lines(self, inner_pt):
        out = []
        for i in range(20):
            out.append({'index': i, 'group': 'T', 'fraction': 0.025 + 0.05 * i,
                        'baselinePx': 60.0 + 50 * i + 0.025 + 0.05 * i,
                        'winX0': 96, 'winX1': 166,
                        'previewInnerBaselinePt': inner_pt})
        return out

    def test_rounded_origin_is_predicted_end_to_end(self):
        # SYNTHETIC: a preview that rounds its paint origin, with an inner
        # baseline of 0.7 px, must be predicted by edge_analysis.
        inner = 0.7
        lines = self._lines(inner)
        prev = self._image('rounded_origin', lines, inner)
        pdf = self._image('unsnapped', lines, inner)
        res = {'T': {'edge': d.edge_analysis(lines, prev, pdf, 1.0)}}
        e = res['T']['edge']
        self.assertLess(e['prevFit']['std'], 0.01)
        self.assertLess(abs(e['predictionError']), 0.026)
        self.assertTrue(e['prevSteps'])
        self.assertEqual(d.decide_rounding(res),
                         'PREVIEW_ROUNDING_PREDICTED (probe only, not RMSE)')

    def test_unsnapped_preview_is_not_rounding(self):
        # SYNTHETIC: a preview with no whole-pixel snapping must not be
        # called a rounding model. Its edge offset is constant (no step).
        lines = self._lines(0.7)
        prev = self._image('unsnapped', lines, 0.7)
        pdf = self._image('unsnapped', lines, 0.7)
        res = {'T': {'edge': d.edge_analysis(lines, prev, pdf, 1.0)}}
        self.assertEqual(res['T']['edge']['prevSteps'], [])
        self.assertTrue(d.decide_rounding(res).startswith(
            'PREVIEW_NOT_ROUNDING'))

    def test_wrong_inner_is_mispredicted(self):
        # SYNTHETIC: the rounding is real but the reported inner baseline is
        # wrong by 0.25 px: the prediction must be flagged, not accepted.
        lines = self._lines(0.7)
        prev = self._image('rounded_origin', lines, 0.7)
        pdf = self._image('unsnapped', lines, 0.7)
        wrong = self._lines(0.7 + 0.25)
        res = {'T': {'edge': d.edge_analysis(wrong, prev, pdf, 1.0)}}
        self.assertTrue(d.decide_rounding(res).startswith(
            'PREVIEW_ROUNDING_MISPREDICTED'))

    def test_missing_ink_is_inconclusive(self):
        # SYNTHETIC: an empty preview cannot produce a verdict.
        lines = self._lines(0.7)
        empty = [[0.0] * W for _ in range(H)]
        pdf = self._image('unsnapped', lines, 0.7)
        res = {'T': {'edge': d.edge_analysis(lines, empty, pdf, 1.0)}}
        self.assertTrue(d.decide_rounding(res).startswith('INCONCLUSIVE'))


if __name__ == '__main__':
    unittest.main()
