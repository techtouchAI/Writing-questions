#!/usr/bin/env python3
"""Tests for tool/c6_geometry_gate.py -- including the deliberate regressions.

The gate is only worth merging if it *rejects* the defects the pixel gate used
to hide. Every category has an injection test here: the same fixture, one value
moved, and the gate must report that category. A gate that tolerates a shift is
not a gate.

Runs with the standard library only: the comparison core takes plain objects,
so no PyMuPDF and no rasteriser are needed. In CI the same tests also run
against the real artifacts (`--real`), which proves the injections behave the
same on the actual fixture and not only on this synthetic model.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import c6_geometry_gate as gate  # noqa: E402


def preview_word(text, x0, x1, baseline, size, rtl):
    return gate.PreviewWord(text=text, x0=x0, x1=x1, baseline=baseline,
                            size=size, rtl=rtl)


def preview_line(words, baseline, runs=None, page=1):
    return gate.PreviewLine(page=page, baseline=baseline, source='block',
                            words=words, runs=runs or [], width=595.0,
                            height=842.0)


def pdf_page(chars, index=1, rules=None, images=None):
    flat = [item for entry in chars
            for item in (entry if isinstance(entry, list) else [entry])]
    return gate.PdfPage(index=index, width=595.0, height=842.0, chars=flat,
                        rules=rules or [], images=images or [])


def pdf_chars(text, x0, x1, baseline, size=12.0):
    """One PdfChar per letter, spread evenly across [x0, x1]."""
    step = (x1 - x0) / max(1, len(text))
    return [gate.PdfChar(ch, x0 + k * step, x0 + (k + 1) * step, baseline,
                         size) for k, ch in enumerate(text)]


def pdf_word(text, x0, x1, baseline, size=12.0):
    return pdf_chars(text, x0, x1, baseline, size)


def arabic_line():
    """One RTL line as both sides see it: ](ﻝﺍﺆﺳ)[ with an underline."""
    words = [
        preview_word('ﺱ', 300.0, 312.0, 100.0, 12.0, True),
        preview_word('ﻝﺍﺆﺳ', 270.0, 298.0, 100.0, 12.0, True),
    ]
    runs = [{'text': 'سؤال', 'fontSizePt': 12.0, 'rtl': True,
             'isMath': False, 'measured': True, 'xPt': 270.0,
             'widthPt': 42.0, 'underline': True}]
    chars = pdf_word('\u0633', 300.0, 312.0, 100.0) + \
        pdf_word('\u0633\u0624\u0627\u0644', 270.0, 298.0, 100.0)
    rules = [gate.PdfRule(x0=270.0, x1=312.0, y=102.0, thickness=1.0)]
    return [preview_line(words, 100.0, runs)], pdf_page(chars, rules=rules)


class Core(unittest.TestCase):
    def test_agreeing_pair_passes(self):
        preview, page = arabic_line()
        violations, samples, coverage = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        self.assertEqual(coverage['lines'], 1)
        self.assertEqual(coverage['rtl_lines'], 1)
        self.assertEqual(coverage['underlines'], 1)
        self.assertEqual(samples['baseline'], [0.0])

    def test_normalise_ignores_encoding_not_content(self):
        self.assertEqual(gate.normalise('ﺳﺆﺍﻝ'), gate.normalise('سؤال'))
        self.assertEqual(gate.normalise('a b'), 'ab')
        self.assertNotEqual(gate.normalise('سؤال'), gate.normalise('سوال'))

    def test_attached_punctuation_is_reconciled_not_rejected(self):
        preview = [preview_line([preview_word('أجب:', 100.0, 130.0, 50.0, 12.0,
                                              False)], 50.0)]
        page = pdf_page([pdf_word('أجب', 100.0, 122.0, 50.0),
                         pdf_word(':', 122.0, 130.0, 50.0)])
        violations, _, coverage = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        self.assertEqual(coverage['words'], 1)

    def test_bound_is_inclusive_and_not_wider(self):
        preview, page = arabic_line()
        # Move only the rightmost glyph: its left edge stays inside the word,
        # so the word is still owned by its box and the defect is positional.
        edge = [c for c in page.chars if c.x0 >= 300.0][-1]
        edge.x1 += 1.5                 # exactly the bound: passes
        violations, _, _ = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        edge.x1 += 0.01                # past the bound: rejected
        violations, _, _ = gate.compare(preview, [page])
        self.assertEqual({v.category for v in violations}, {'WORD-POSITION'})


class Injections(unittest.TestCase):
    """Requirement: every real defect must be *rejected*, not tolerated.

    A rejection is asserted as: at least one violation, and -- where the
    category is unambiguous -- that specific category. A shift that lands a
    glyph inside its neighbour's box is still a rejection; the gate then names
    the content mismatch, which is what it is.
    """

    def assert_rejects(self, preview, page, *categories):
        violations, _, _ = gate.compare(preview, [page])
        self.assertTrue(violations, f'gate tolerated the defect: {categories}')
        if categories:
            self.assertTrue(
                set(categories) & {v.category for v in violations},
                f'gate named it {sorted({v.category for v in violations})}, '
                f'expected one of {categories}')

    def test_text_shift(self):
        preview, page = arabic_line()
        for char in page.chars:
            char.x0 += 3.0
            char.x1 += 3.0
        self.assert_rejects(preview, page, 'WORD-POSITION', 'WORD-MISSING',
                            'WORD-CONTENT')

    def test_line_shift(self):
        preview, page = arabic_line()
        for char in page.chars:
            char.baseline += 1.5
        self.assert_rejects(preview, page, 'BASELINE')

    def test_size_change(self):
        preview, page = arabic_line()
        for char in page.chars:
            char.size = 14.0
        self.assert_rejects(preview, page, 'SIZE')

    def test_deleted_word(self):
        preview, page = arabic_line()
        page.chars = [c for c in page.chars if c.x0 >= 300.0]
        self.assert_rejects(preview, page, 'WORD-MISSING')

    def test_reordered_words(self):
        preview, page = arabic_line()
        # Swap the two words' positions: same glyphs, other order.
        for char in page.chars:
            if char.x0 >= 300.0:
                char.x0 -= 30.0
                char.x1 -= 30.0
            else:
                char.x0 += 30.0
                char.x1 += 30.0
        self.assert_rejects(preview, page, 'WORD-CONTENT', 'WORD-MISSING',
                            'WORD-EXTRA')

    def test_deleted_line(self):
        preview, page = arabic_line()
        page.chars.clear()
        self.assert_rejects(preview, page, 'LINE-MISSING')

    def test_added_line(self):
        preview, page = arabic_line()
        page.chars.extend(pdf_word('extra', 400.0, 430.0, 300.0))
        self.assert_rejects(preview, page, 'LINE-EXTRA')

    def test_underline_removed(self):
        preview, page = arabic_line()
        page.rules.clear()
        self.assert_rejects(preview, page, 'UNDERLINE-MISSING')

    def test_maths_image_moved(self):
        words = [preview_word('x', 100.0, 112.0, 200.0, 12.0, False)]
        runs = [{'text': 'x^2', 'fontSizePt': 12.0, 'rtl': False,
                 'isMath': True, 'measured': False, 'xPt': 150.0,
                 'widthPt': 30.0, 'heightPt': 20.0, 'underline': False}]
        preview = [preview_line(words, 200.0, runs)]
        image = gate.PdfImageRect(x0=150.0, y0=180.0, x1=180.0, y1=200.0)
        page = pdf_page(pdf_word('x', 100.0, 112.0, 200.0), images=[image])
        violations, _, _ = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        image.x0 += 6.0
        image.x1 += 6.0
        self.assert_rejects(preview, page, 'MATH-IMAGE')

    def test_maths_emitted_as_text_is_legal(self):
        # When no snapshot host is mounted the exporter falls back to readable
        # text; demanding an image there would fail a correct document.
        words = [preview_word('x', 100.0, 112.0, 200.0, 12.0, False)]
        runs = [{'text': 'x^2', 'fontSizePt': 12.0, 'rtl': False,
                 'isMath': True, 'measured': False, 'xPt': 100.0,
                 'widthPt': 12.0, 'heightPt': 20.0, 'underline': False}]
        preview = [preview_line(words, 200.0, runs)]
        page = pdf_page(pdf_word('x', 100.0, 112.0, 200.0))
        violations, _, coverage = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        self.assertEqual(coverage['math_runs'], 1)

    def test_bracket_mirroring(self):
        words = [preview_word(')', 100.0, 106.0, 80.0, 12.0, True),
                 preview_word('(', 140.0, 146.0, 80.0, 12.0, True)]
        preview = [preview_line(words, 80.0)]
        page = pdf_page(pdf_word(')', 100.0, 106.0, 80.0) +
                        pdf_word('(', 140.0, 146.0, 80.0))
        violations, _, _ = gate.compare(preview, [page])
        self.assertEqual(violations, [])
        # Both sides agree, but the line now opens on the left: for an RTL
        # line the leftmost bracket must be the closer, so this is the
        # mirroring defect the gate has to name.
        mirrored_words = [preview_word('(', 100.0, 106.0, 80.0, 12.0, True),
                          preview_word(')', 140.0, 146.0, 80.0, 12.0, True)]
        mirrored_preview = [preview_line(mirrored_words, 80.0)]
        mirrored_pdf = pdf_page(pdf_word('(', 100.0, 106.0, 80.0) +
                                pdf_word(')', 140.0, 146.0, 80.0))
        self.assert_rejects(mirrored_preview, mirrored_pdf, 'BRACKET-ORDER')

    def test_page_count(self):
        preview, page = arabic_line()
        violations, _, _ = gate.compare(preview, [page, page])
        self.assertIn('PAGE-COUNT', [v.category for v in violations])


class Modes(unittest.TestCase):
    def _artifacts(self, tmp, preview, page):
        os.makedirs(os.path.join(tmp, os.path.dirname(gate.PREVIEW_REL)),
                    exist_ok=True)
        payload = {'schema': gate.SCHEMA, 'pages': [{
            'page': 1, 'widthPt': 595.0, 'heightPt': 842.0,
            'lines': [{'source': 'block', 'baselinePt': line.baseline,
                       'runs': line.runs} for line in preview]}]}
        with open(os.path.join(tmp, gate.PREVIEW_REL), 'w',
                  encoding='utf-8') as handle:
            json.dump(payload, handle)
        open(os.path.join(tmp, gate.PDF_REL), 'wb').close()

    def test_report_mode_never_exits_nonzero_but_says_it_would_fail(self):
        preview, page = arabic_line()
        page.chars[0].x0 += 5.0
        with tempfile.TemporaryDirectory() as tmp:
            self._artifacts(tmp, preview, page)
            with mock.patch.object(gate, 'read_pdf_pages', return_value=[page]):
                with contextlib.redirect_stdout(io.StringIO()):
                    code = gate.main([tmp, '--mode', 'report', '--json',
                                      os.path.join(tmp, 'out.json')])
                self.assertEqual(code, 0)

    def test_enforce_mode_exits_one(self):
        preview, page = arabic_line()
        page.chars[0].x0 += 5.0
        with tempfile.TemporaryDirectory() as tmp:
            self._artifacts(tmp, preview, page)
            with mock.patch.object(gate, 'read_pdf_pages', return_value=[page]):
                with contextlib.redirect_stdout(io.StringIO()):
                    code = gate.main([tmp, '--mode', 'enforce', '--json',
                                      os.path.join(tmp, 'out.json')])
                self.assertEqual(code, 1)

    def test_missing_artifacts_is_not_silent_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gate.main([tmp, '--mode', 'enforce']), 2)


class RealArtifacts(unittest.TestCase):
    """Injection on the gate's own artifacts, when they are present.

    Skipped locally (no Flutter); in CI these run against the real
    preview_positions.json and vector.pdf, so the negative tests prove the gate
    rejects defects in the actual fixture, not only in this model.
    """

    def _load(self):
        artifacts = os.environ.get('C6_ARTIFACTS', 'build/visual_parity')
        preview_path = os.path.join(artifacts, gate.PREVIEW_REL)
        pdf_path = os.path.join(artifacts, gate.PDF_REL)
        if not (os.path.exists(preview_path) and os.path.exists(pdf_path)):
            self.skipTest('real artifacts not available')
        return (gate.preview_lines(gate.read_preview(preview_path)),
                gate.read_pdf_pages(pdf_path))

    def test_real_shift_is_rejected(self):
        preview, pages = self._load()
        pages[0].chars = [gate.PdfChar(c.text, c.x0 + 4.0, c.x1 + 4.0,
                                       c.baseline, c.size, c.font)
                          for c in pages[0].chars]
        violations, _, _ = gate.compare(preview, pages)
        self.assertIn('WORD-POSITION', [v.category for v in violations])

    def test_real_deletion_is_rejected(self):
        preview, pages = self._load()
        if pages[0].chars:
            del pages[0].chars[0]
        violations, _, _ = gate.compare(preview, pages)
        self.assertTrue(violations, 'gate tolerated a deleted word')

    def test_real_underline_removal_is_rejected(self):
        preview, pages = self._load()
        underlined = any(run.get('underline') for line in preview
                         for run in line.runs)
        if not underlined:
            self.skipTest('fixture has no underlined run on page 1')
        pages[0].rules = []
        violations, _, _ = gate.compare(preview, pages)
        self.assertIn('UNDERLINE-MISSING', [v.category for v in violations])


if __name__ == '__main__':
    unittest.main(verbosity=2)
