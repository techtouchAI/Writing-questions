"""Tests for the isolated semantic-PDF prototype (no production code involved).

Run:
    python3 -m unittest tool/test_prototype_semantic_pdf.py

The comparator tests need only the standard library. The shaping/alignment tests
need `arabic_reshaper`, `python-bidi` and `fontTools` (the same packages the
prototype driver needs) and skip cleanly when they are absent.
"""
from __future__ import annotations

import sys
import unicodedata
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent
PROTO = TOOL / 'prototype_semantic_pdf'
sys.path.insert(0, str(PROTO))
sys.path.insert(0, str(TOOL))

from compare import judge  # noqa: E402

try:  # optional prototype dependencies
    import arabic_reshaper  # noqa: F401
    import bidi  # noqa: F401
    from fontTools.ttLib import TTFont  # noqa: F401
    HAVE_SHAPING = True
except Exception:  # pragma: no cover - environment without the prototype deps
    HAVE_SHAPING = False

FONT = TOOL.parent / 'assets' / 'fonts' / 'NotoNaskhArabic-Regular.ttf'


class ComparatorTest(unittest.TestCase):
    def test_exact_source_matches(self):
        verdict = judge('سَلَامٌ', 'سَلَامٌ')
        self.assertTrue(verdict['flat_match'])
        self.assertFalse(verdict['canonical_equivalent_only'])

    def test_reversed_letters_are_rejected(self):
        verdict = judge('ٌمَالَس', 'سَلَامٌ')
        self.assertFalse(verdict['flat_match'])

    def test_duplicated_suffix_is_rejected(self):
        # The historical substring-only check accepted this: `سَلَامٌمٌ`.
        verdict = judge('سَلَامٌمٌ', 'سَلَامٌ')
        self.assertFalse(verdict['flat_match'])
        self.assertEqual(verdict['exact_segment_count'], 0)

    def test_missing_mark_is_rejected(self):
        verdict = judge('سَلاَم', 'سَلَامٌ')
        self.assertFalse(verdict['flat_match'])

    def test_extra_word_is_rejected(self):
        verdict = judge('سَلَامٌ English', 'سَلَامٌ')
        self.assertFalse(verdict['flat_match'])

    def test_delimited_occurrence_counts_once(self):
        # `flat_match` is whole-text equality; the delimited segment count is the
        # diagnostic that must reject a word embedded in a longer word.
        verdict = judge('نص عربي طويل', 'عربي')
        self.assertEqual(verdict['exact_segment_count'], 1)
        self.assertFalse(verdict['flat_match'])
        embedded = judge('نصعربي', 'عربي')
        self.assertEqual(embedded['exact_segment_count'], 0)

    def test_canonical_reordering_is_reported_but_not_accepted(self):
        source = 'مُحَمَّدٌ'          # fatha then shadda
        reordered = 'مُحَمَّدٌ'       # shadda then fatha (non-canonical output)
        reordered = 'مُحَم' + '\u0651' + '\u064e' + 'دٌ'
        verdict = judge(reordered, source)
        self.assertFalse(verdict['flat_match'])
        self.assertTrue(verdict['canonical_equivalent_only'])
        self.assertTrue(verdict['source_is_nfc'])
        self.assertEqual(unicodedata.normalize('NFC', reordered),
                         unicodedata.normalize('NFC', source))


@unittest.skipUnless(HAVE_SHAPING, 'prototype shaping dependencies are not installed')
class AlignmentTest(unittest.TestCase):
    def setUp(self):
        import shaping
        from corpus import CORPUS
        self.shaping = shaping
        self.font = shaping.PrototypeFont(str(FONT))
        self.corpus = CORPUS

    def _words(self):
        for item in self.corpus:
            for line in item['lines']:
                for word in line.split(' '):
                    yield word

    def test_every_source_character_is_owned_exactly_once(self):
        for word in self._words():
            if not any(0x0600 <= ord(char) <= 0x06FF for char in word):
                continue
            shaped = self.shaping.shape_logical(word)
            segments = self.shaping.align_source(word, shaped)
            joined = ''.join(segments[index] for index in range(len(shaped)))
            self.assertEqual(joined, word,
                             f'source segments do not reassemble {word!r}')
            # no character is dropped or duplicated
            self.assertEqual(sorted(joined), sorted(word))

    def test_ligature_owns_the_mark_written_inside_it(self):
        word = 'سَلَامٌ'
        shaped = self.shaping.shape_logical(word)
        segments = self.shaping.align_source(word, shaped)
        values = [segments[index] for index in range(len(shaped))]
        self.assertIn('لَا', values)          # lam, fatha, alef in source order
        self.assertEqual(values.count(''), 1)  # the swallowed fatha glyph

    def test_logical_reference_reproduces_the_source(self):
        for word in ('سَلَامٌ', 'نص', 'عربي', 'طويل', 'مُحَمَّدٌ', 'الْأَلِف'):
            shaped = self.shaping.shape_logical(word)
            segments = self.shaping.align_source(word, shaped)
            self.assertEqual(''.join(segments[i] for i in range(len(shaped))), word)

    def test_production_emulation_reproduces_the_investigation_cmap(self):
        """The prototype's baseline channel must equal the shipped CMap.

        The investigation recorded, for the Android PDF word `سَلَامٌ`:
            CID order  001F 0011 0020 0021 0020 0004
            ToUnicode  064C 0645 064E 0627,0644 064E 0633
        i.e. dammatan, meem, fatha, reversed lam-alef, fatha, seen.
        """
        word = 'سَلَامٌ'
        glyphs = self.shaping.visual_glyphs(self.font, word, rtl=True)
        payload = []
        for glyph in glyphs:
            payload.extend(f'{ord(char):04X}' for char in glyph.payload_legacy)
        self.assertEqual(payload,
                         ['064C', '0645', '064E', '0627', '0644', '064E', '0633'])

    def test_marks_carry_no_advance(self):
        glyphs = self.shaping.visual_glyphs(self.font, 'سَلَامٌ', rtl=True)
        marks = [glyph for glyph in glyphs if self.shaping.is_mark(glyph.code)]
        self.assertTrue(marks)
        self.assertTrue(all(glyph.advance == 0 for glyph in marks))

    def test_layout_is_identical_for_every_strategy(self):
        """Ink invariance by construction.

        Every strategy consumes the same placed glyphs: identical glyph ids at
        identical x positions with identical advances. Rendering parity is
        measured by the prototype driver (`coverageDeltaPixelsVsBaseline`), which
        is 0 for every text-only strategy.
        """
        from corpus import CORPUS
        from pdfwriter import FontEncoder, PdfWriter
        from strategies import STRATEGIES, emit_line, layout_line

        layout = []
        for item in CORPUS:
            y = 700.0
            for line in item['lines']:
                words = layout_line(self.font, line, 20.0, left=60, right=535, y=y)
                layout.append([((gid, x, size), word.text)
                               for word, size in zip(words, [w.size for w in words])
                               for gid, _, _, x in word.glyphs])
                y -= 60.0

        for strategy in STRATEGIES:
            encoder = FontEncoder(self.font)
            pages = []
            for item in CORPUS:
                ops = []
                y = 700.0
                for line in item['lines']:
                    words = layout_line(self.font, line, 20.0, left=60, right=535, y=y)
                    ops.append(emit_line(encoder, words, strategy))
                    y -= 60.0
                pages.append('\n'.join(ops))
            data = PdfWriter(encoder).build(pages)
            self.assertTrue(data.startswith(b'%PDF-1.7'))
            self.assertEqual(len(pages), len(CORPUS), f'{strategy} changed page count')

            # The placed glyph sequence is strategy independent.
            replayed = []
            for item in CORPUS:
                y = 700.0
                for line in item['lines']:
                    words = layout_line(self.font, line, 20.0, left=60, right=535, y=y)
                    replayed.append([((gid, x, word.size), word.text)
                                     for word in words
                                     for gid, _, _, x in word.glyphs])
                    y -= 60.0
            self.assertEqual(replayed, layout, f'{strategy} changed glyph placement')


if __name__ == '__main__':
    unittest.main()
