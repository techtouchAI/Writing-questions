"""Tests for check_underline_parity.py -- SYNTHETIC inputs only.

The real numbers come from the CI fixture; these tests pin the *logic* on
constructed pages whose rules are drawn at known offsets: a rule is found from
the file's own geometry, a rule is found in the pixels by its continuity, and
a disagreement of a known size is reported as such and fails the check. If
the detector cannot tell an agreeing case from a four-pixel disagreement on
inputs whose cause is known by construction, its verdict on the fixture means
nothing.

The REAL-artifact family (same check, the fixture's own printed underlining)
is kept separate in test_diag_c6_underline_real_artifacts.py -- synthetic and
real evidence must never be mistaken for each other.
"""
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_underline_parity as cu  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'check_underline_parity.py')


def build_artifacts(directory, pdf_offset_px, preview_offset_px, size=12.0,
                    text='Choose the correct answer'):
    """A page whose rule sits at a chosen offset in each source.

    `vector.pdf` carries the rule at `pdf_offset_px` below the baseline; the
    preview PNG is rendered from a second document whose rule sits at
    `preview_offset_px`. Two documents (rather than one) are what makes it
    possible to test a *disagreement*.
    """
    for name, offset_px in (('vector.pdf', pdf_offset_px),
                            ('_preview_src.pdf', preview_offset_px)):
        doc = pymupdf.open()
        page = doc.new_page(width=595.276, height=841.89)
        baseline = 120.0
        page.insert_text((60, baseline), text, fontsize=size)
        end = page.get_text('dict')['blocks'][0]['lines'][0]['spans'][0]
        y = baseline + offset_px * 72.0 / 96.0
        page.draw_line(pymupdf.Point(60, y),
                       pymupdf.Point(end['bbox'][2], y), width=0.6)
        doc.save(os.path.join(directory, name))
    source = pymupdf.open(os.path.join(directory, '_preview_src.pdf'))
    pix = source[0].get_pixmap(dpi=96)
    pix.save(os.path.join(directory, 'preview_page_1.png'))
    with io.open(os.path.join(directory, 'manifest.json'), 'w') as handle:
        json.dump({'pageCount': 1, 'widthPx': pix.width,
                   'heightPx': pix.height}, handle)


class SyntheticLongestRunTests(unittest.TestCase):
    """The discriminator between a glyph row and a rule row."""

    def test_single_stem_is_its_own_run(self):
        row = np.zeros(50, dtype=np.uint8)
        row[10:14] = 255
        self.assertEqual(cu.longest_run(row), 4)

    def test_broken_row_reports_the_longest_piece(self):
        row = np.zeros(50, dtype=np.uint8)
        row[5:9] = 255
        row[20:32] = 255
        self.assertEqual(cu.longest_run(row), 12)

    def test_empty_row_is_zero(self):
        self.assertEqual(cu.longest_run(np.zeros(20, dtype=np.uint8)), 0)

    def test_full_row_is_its_length(self):
        row = np.full(30, 255, dtype=np.uint8)
        self.assertEqual(cu.longest_run(row), 30)


class SyntheticPdfRuleTests(unittest.TestCase):
    """The rule and its owning baseline come from the file, not from pixels."""

    def setUp(self):
        self._tmp = tempfile.mkdtemp()
        build_artifacts(self._tmp, 5.3, 5.3)

    def test_rule_is_found_with_its_owning_line_and_offset(self):
        doc = pymupdf.open(os.path.join(self._tmp, 'vector.pdf'))
        rules = cu.rules_in_pdf(doc[0])
        self.assertEqual(len(rules), 1, rules)
        rule = rules[0]
        self.assertAlmostEqual(rule['offset_pt'], 5.3 * 72.0 / 96.0, places=1)
        self.assertIn('Choose the correct answer', rule['text'])
        self.assertGreater(rule['rule_x'][1] - rule['rule_x'][0], 20)

    def test_a_distant_line_is_not_an_owner(self):
        doc = pymupdf.open()
        page = doc.new_page(width=595.276, height=841.89)
        page.insert_text((60, 100), 'text', fontsize=12)
        page.draw_line(pymupdf.Point(60, 400), pymupdf.Point(300, 400))
        self.assertEqual(cu.rules_in_pdf(page), [])


class SyntheticPreviewRuleTests(unittest.TestCase):
    """The rule in the pixels is found by continuity, not by darkness."""

    def setUp(self):
        self._tmp = tempfile.mkdtemp()
        build_artifacts(self._tmp, 1.3, 1.3)
        self.luma = cu.load_luma(os.path.join(self._tmp, 'preview_page_1.png'))
        doc = pymupdf.open(os.path.join(self._tmp, 'vector.pdf'))
        self.rule = cu.rules_in_pdf(doc[0])[0]

    def test_rule_and_baseline_are_measured(self):
        scale = self.luma.shape[1] / 595.276
        measured = cu.preview_offset(self.luma, self.rule['bbox'], scale)
        self.assertIsNotNone(measured)
        self.assertGreaterEqual(measured['offset_px'], 0)
        self.assertLessEqual(measured['offset_px'], 3)
        self.assertGreater(measured['thickness_px'], 0)

    def test_a_region_without_a_rule_is_not_measured(self):
        scale = self.luma.shape[1] / 595.276
        blank = np.zeros((50, 50))
        self.assertIsNone(cu.preview_offset(blank, (0, 0, 20, 10), scale))


class SyntheticEndToEndTests(unittest.TestCase):
    """The check's exit status is the gate: agreement passes, a four-pixel
    offset fails, and the numbers it prints say both offsets."""

    def _run(self, directory):
        return subprocess.run([sys.executable, TOOL, directory],
                              capture_output=True, text=True)

    def test_agreeing_sources_pass(self):
        directory = tempfile.mkdtemp()
        build_artifacts(directory, 1.3, 1.3)
        proc = self._run(directory)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn('rule(s) compared', proc.stdout)

    def test_a_four_pixel_offset_fails_with_both_numbers(self):
        directory = tempfile.mkdtemp()
        build_artifacts(directory, 5.3, 1.3)
        proc = self._run(directory)
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn('UNDERLINE offset', proc.stdout)
        self.assertIn('pdf=', proc.stdout)
        self.assertIn('preview=', proc.stdout)

    def test_missing_preview_is_not_a_pass(self):
        directory = tempfile.mkdtemp()
        build_artifacts(directory, 1.3, 1.3)
        os.remove(os.path.join(directory, 'preview_page_1.png'))
        proc = self._run(directory)
        self.assertIn('no rule checked', proc.stdout)
        self.assertNotIn('UNDERLINE offset', proc.stdout)


if __name__ == '__main__':
    unittest.main()
