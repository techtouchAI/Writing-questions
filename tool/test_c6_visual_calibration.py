#!/usr/bin/env python3
"""Tests for tool/c6_visual_calibration.py.

The tool's job is to refuse to invent a threshold. These tests pin that:
separation is only claimed when the smallest deliberate defect really is above
the measured floor, the proposal is a geometric mean *between* them, and
enforce mode cannot run without an explicit threshold.

The image tests use ImageMagick itself, which is the metric the gate uses, so
what is tested is the metric the merge decision would rest on.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import c6_visual_calibration as cal  # noqa: E402

HAVE_IM = bool(shutil.which('convert') and shutil.which('compare'))


def make_png(path, width, height, blank=False):
    if blank:
        subprocess.run(['convert', '-size', f'{width}x{height}', 'xc:white',
                        path], check=True)
    else:
        subprocess.run(['convert', '-size', f'{width}x{height}', 'xc:white',
                        '-fill', 'black', '-draw',
                        f'rectangle 10,40 {width - 10},44', path], check=True)
    return path


class Separation(unittest.TestCase):
    def test_separated_when_defect_is_above_the_floor(self):
        result = cal.separation({'a': 0.05, 'b': 0.06},
                                {'shift': 0.20, 'scale': 0.30})
        self.assertTrue(result['separated'])
        self.assertGreater(result['proposed'], result['floor_max'])
        self.assertLess(result['proposed'], min(result['detectable'].values()))
        self.assertAlmostEqual(result['proposed'], (0.06 * 0.20) ** 0.5)

    def test_small_defects_are_named_not_averaged_away(self):
        # The real shape of this fixture: big shifts separate, a deleted band
        # and a 4 px underline move do not. The result must say both.
        result = cal.separation({'vector': 0.0558},
                                {'shift_1px': 0.1128, 'delete_band': 0.0167,
                                 'underline_4px': 0.0383})
        self.assertTrue(result['separated'])
        self.assertEqual(set(result['invisible']),
                         {'delete_band', 'underline_4px'})
        self.assertEqual(set(result['detectable']), {'shift_1px'})
        self.assertGreater(result['proposed'], 0.0558)
        self.assertGreater(result['margin'], 1.0)

    def test_no_separation_when_every_defect_hides_in_the_floor(self):
        result = cal.separation({'a': 0.05}, {'tiny': 0.01})
        self.assertFalse(result['separated'])
        self.assertNotIn('proposed', result)
        self.assertEqual(set(result['invisible']), {'tiny'})

    def test_empty_inputs_propose_nothing(self):
        self.assertIsNone(cal.separation({}, {'x': 1.0}))
        self.assertIsNone(cal.separation({'x': 1.0}, {}))


@unittest.skipUnless(HAVE_IM, 'ImageMagick is required for the image tests')
class Images(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.convert = shutil.which('convert')
        self.compare = shutil.which('compare')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_image_size_reads_the_header(self):
        path = make_png(os.path.join(self.tmp, 'a.png'), 64, 48)
        self.assertEqual(cal.image_size(path), (64, 48))

    def test_identical_images_are_zero(self):
        a = make_png(os.path.join(self.tmp, 'a.png'), 64, 48)
        b = make_png(os.path.join(self.tmp, 'b.png'), 64, 48)
        self.assertEqual(cal.rmse(self.compare, a, b), 0.0)

    def test_half_pixel_blur_of_identical_images_is_zero(self):
        a = make_png(os.path.join(self.tmp, 'a.png'), 64, 48)
        blurred = cal.blur_half_pixel(
            self.convert, a, os.path.join(self.tmp, 'blur.png'))
        again = cal.blur_half_pixel(
            self.convert, a, os.path.join(self.tmp, 'blur2.png'))
        self.assertEqual(cal.rmse(self.compare, blurred, again), 0.0)

    def test_blur_excess_is_gate_minus_floor_and_not_a_ceiling(self):
        self.assertAlmostEqual(cal.blur_excess(0.0487676, 0.0165), 0.0322676)
        self.assertAlmostEqual(cal.blur_excess(0.0165, 0.0165), 0.0)

    def test_a_shift_is_detected_and_scales_with_distance(self):
        a = make_png(os.path.join(self.tmp, 'a.png'), 64, 48)
        one = cal.perturb(self.convert, a, os.path.join(self.tmp, 's1.png'),
                          'shift_1px', *cal.image_size(a))
        four = cal.perturb(self.convert, a, os.path.join(self.tmp, 's4.png'),
                           'shift_4px', *cal.image_size(a))
        r1 = cal.rmse(self.compare, a, one)
        r4 = cal.rmse(self.compare, a, four)
        self.assertGreater(r1, 0)
        self.assertGreater(r4, r1,
                           'a 4 px defect must be larger than a 1 px one')

    def test_deleted_band_and_underline_shift_are_both_measurable(self):
        a = make_png(os.path.join(self.tmp, 'a.png'), 64, 120)
        for kind in ('delete_band', 'underline_4px', 'scale_102'):
            target = cal.perturb(self.convert, a,
                                 os.path.join(self.tmp, f'{kind}.png'), kind,
                                 *cal.image_size(a))
            self.assertGreater(cal.rmse(self.compare, a, target), 0, kind)

    def test_gate_shaped_crops_the_gate_margin(self):
        a = make_png(os.path.join(self.tmp, 'a.png'), 64, 48)
        out = cal.gate_shaped(self.convert, a,
                              os.path.join(self.tmp, 'norm.png'), 64, 48)
        self.assertEqual(cal.image_size(out), (60, 44))


class Modes(unittest.TestCase):
    def test_enforce_without_a_threshold_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(cal.main([tmp, '--mode', 'enforce']), 2)

    def test_missing_tools_is_not_silent_success(self):
        original = cal.which
        cal.which = lambda *names: None
        try:
            with tempfile.TemporaryDirectory() as tmp:
                self.assertEqual(cal.main([tmp]), 2)
        finally:
            cal.which = original


class Manifest(unittest.TestCase):
    def test_the_settings_are_the_gate_s(self):
        self.assertEqual(cal.DPI, 96)
        self.assertEqual(cal.CROP_MARGIN, 2)
        self.assertIn('shift_4px', cal.REGRESSIONS)
        self.assertIn('underline_4px', cal.REGRESSIONS)


if __name__ == '__main__':
    unittest.main(verbosity=2)
