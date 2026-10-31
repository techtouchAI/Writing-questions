"""Reproduction of the production Naskh text pipeline, outside the app.

The production PDF path for the Arabic body face (NotoNaskhArabic) is:

    logical word
      -> contextual shaping to Unicode presentation forms (lam-alef, Allah ...)
      -> UAX #9 visual reordering at paragraph level 1
      -> one CID per *visual* glyph, `/ToUnicode` derived from that glyph

This module reproduces exactly that character-level pipeline with
`arabic_reshaper` and `python-bidi`, so a prototype PDF can be compared with a
real application PDF at the *text* level. It is a prototype helper; the
application never imports it.

It also carries the missing piece the production encoder does not have: each
glyph keeps the **logical source text** it renders (base letter + its marks in
source order, or the several base letters of a ligature). Two payload views are
produced:

* `payload_logical`  - the source text of the glyph, in logical order.
* `payload_legacy`   - the same text as the shipped `shapeRtlRun` emits it
                       (ligature base letters reversed into visual order).

Nothing here normalises, sorts marks, or reverses text for comparison.
"""
from __future__ import annotations

import unicodedata
from dataclasses import dataclass
from functools import lru_cache

import arabic_reshaper
from bidi import get_display
from fontTools.ttLib import TTFont

# Arabic combining marks that carry no advance. The production encoder zeroes
# their width (`PdfTtfFont.glyphMetrics` under `useBidi`) so they sit on the
# preceding base letter; the prototype must position them identically.
MARK_RANGES = (
    (0x064B, 0x0652),
    (0x0653, 0x0655),
    (0x0670, 0x0670),
    (0x06D6, 0x06ED),
    (0x08E3, 0x08FF),
    (0xFC5E, 0xFC63),
    (0xFE70, 0xFE7F),  # presentation-form marks (e.g. U+FE7X alef marks)
)


def is_mark(code: int) -> bool:
    return any(lo <= code <= hi for lo, hi in MARK_RANGES)


@lru_cache(maxsize=1)
def _reshaper() -> arabic_reshaper.ArabicReshaper:
    # Same behaviour as the vendored bidi shaping: harakat are kept as separate
    # code points, lam-alef and word ligatures are formed.
    return arabic_reshaper.ArabicReshaper(configuration={'delete_harakat': False})


def _decomposition(code: int) -> str:
    """Unicode base letters of a presentation form, in logical order."""
    if 0xFB50 <= code <= 0xFEFE or 0xFE70 <= code <= 0xFEFF:
        raw = unicodedata.decomposition(chr(code))
        if raw and not raw.startswith('<'):
            return ''.join(chr(int(part, 16)) for part in raw.split())
        if raw:
            # compatibility decomposition such as "<isolated> 0627"
            parts = [p for p in raw.split() if not p.startswith('<')]
            return ''.join(chr(int(part, 16)) for part in parts)
    return chr(code)


@dataclass(frozen=True)
class Glyph:
    """One glyph in visual order plus the logical text it renders."""

    code: int          # original (logical) character or presentation form
    gid: int           # glyph id in the prototype font
    advance: int       # font units, already zeroed for marks
    payload_logical: str
    payload_legacy: str

    @property
    def is_mark(self) -> bool:
        return self.advance == 0


class PrototypeFont:
    def __init__(self, path: str):
        self.path = path
        self.ttf = TTFont(path)
        self.units_per_em = self.ttf['head'].unitsPerEm
        self.cmap = self.ttf.getBestCmap()
        self.hmtx = self.ttf['hmtx'].metrics
        self.glyph_order = self.ttf.getGlyphOrder()

    def gid(self, code: int) -> int:
        name = self.cmap[code]
        return self.glyph_order.index(name)

    def advance(self, gid: int) -> int:
        name = self.glyph_order[gid]
        return self.hmtx[name][0]


def shape_logical(text: str) -> str:
    """Contextual shaping to presentation forms, still in logical order."""
    return _reshaper().reshape(text)


def visual_order(text: str, base_dir: str = 'R') -> str:
    """UAX #9 reordering of an already-shaped run."""
    return get_display(text, base_dir=base_dir)


def logical_glyphs(font: PrototypeFont, word: str) -> list[Glyph]:
    """Glyphs of one word in **logical** order (source order preserved)."""
    shaped = shape_logical(word)
    glyphs: list[Glyph] = []
    for char in shaped:
        code = ord(char)
        base = _decomposition(code)
        gid = font.gid(code)
        advance = 0 if is_mark(code) else font.advance(gid)
        glyphs.append(
            Glyph(
                code=code,
                gid=gid,
                advance=advance,
                payload_logical=base,
                # Shipped `shapeRtlRun` reverses multi-letter decompositions
                # (lam-alef) so the payload is in visual order as well.
                payload_legacy=''.join(reversed(base)) if len(base) > 1 else base,
            )
        )
    return glyphs


def visual_glyphs(font: PrototypeFont, word: str, rtl: bool) -> list[Glyph]:
    """Glyphs in the order they are drawn (visual, left to right)."""
    if not rtl:
        return logical_glyphs(font, word)
    shaped = shape_logical(word)
    visual = visual_order(shaped, base_dir='R')
    if sorted(visual) != sorted(shaped):  # pragma: no cover - guard
        raise AssertionError('reordering changed the shaped character bag')
    glyphs: list[Glyph] = []
    for char in visual:
        code = ord(char)
        base = _decomposition(code)
        gid = font.gid(code)
        advance = 0 if is_mark(code) else font.advance(gid)
        glyphs.append(
            Glyph(
                code=code,
                gid=gid,
                advance=advance,
                payload_logical=base,
                payload_legacy=''.join(reversed(base)) if len(base) > 1 else base,
            )
        )
    return glyphs


def logical_reference(word: str) -> str:
    """Logical text a word must extract as (unshaped, marks in source order)."""
    out = []
    for char in shape_logical(word):
        code = ord(char)
        if is_mark(code):
            out.append(char)
        else:
            out.append(_decomposition(code))
    return ''.join(out)


def align_source(source: str, shaped: str) -> dict[int, str]:
    """Map every shaped character index to the **source segment** it renders.

    This is the missing link the production encoder never builds: a ligature
    glyph (lam-alef, Allah) renders several source characters, and a combining
    mark that sits *between* those characters stays a separate shaped character
    even though its character belongs to the ligature's source span. Walking the
    two strings once, in logical order, attributes each source character to
    exactly one shaped character:

    * a presentation form with k base letters consumes the next k base letters
      of the source together with every mark in between;
    * a mark consumes the next unconsumed source mark;
    * a mark that finds no unconsumed source mark is *swallowed*: its character
      was already consumed inside a preceding ligature span, so its segment is
      the empty string.
    """
    result: dict[int, str] = {}
    position = 0
    for index, char in enumerate(shaped):
        code = ord(char)
        if is_mark(code):
            if position < len(source) and is_mark(ord(source[position])):
                result[index] = source[position]
                position += 1
            else:
                result[index] = ''
            continue
        base = _decomposition(code)
        wanted = sum(1 for letter in base if not is_mark(ord(letter)))
        wanted = max(wanted, 1)
        segment: list[str] = []
        consumed = 0
        while position < len(source) and consumed < wanted:
            current = source[position]
            segment.append(current)
            position += 1
            if not is_mark(ord(current)):
                consumed += 1
        if wanted > 1:
            # A ligature owns the marks that follow its last base letter, so a
            # mark that was written *inside* the ligature source span cannot be
            # attributed to a separate glyph later.
            while position < len(source) and is_mark(ord(source[position])):
                segment.append(source[position])
                position += 1
        result[index] = ''.join(segment)
    if position < len(source):  # pragma: no cover - guard
        raise AssertionError(f'unconsumed source characters: {source[position:]!r}')
    return result
