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


class MainContractTests(unittest.TestCase):
    def test_missing_probe_is_non_fatal(self):
        # SYNTHETIC: the step must not fail the job when the probe is absent.
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(d.main(['x', tmp]), 0)


if __name__ == '__main__':
    unittest.main()
