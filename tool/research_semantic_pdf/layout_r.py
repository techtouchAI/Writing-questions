"""Layout that is faithful to production: space glyphs are painted too.

The older prototype split a line on spaces and drew words only, so a space
existed in no content stream at all. Production does not work that way: the
space rune is shaped and mapped like any other character and its glyph is
painted (with an advance and no ink). A research harness that omits it cannot
answer questions about extractor word separation, so this module places
`PlacedWord(' ')` objects between words at their exact visual positions.

Rendering is unaffected: a space glyph has no outline, so adding it changes no
pixel - and the reference PDF is built with the same layout, which keeps the
pixel comparison honest.
"""
from __future__ import annotations

import sys
from pathlib import Path

PROTOTYPE = (Path(__file__).resolve().parent / '../prototype_semantic_pdf').resolve()
sys.path.insert(0, str(PROTOTYPE))

from shaping import PrototypeFont  # noqa: E402
from strategies import PlacedWord, has_arabic  # noqa: E402


def place_line(font: PrototypeFont, line: str, size: float, left: float,
               right: float, y: float) -> list[PlacedWord]:
    """Return words **and their separating spaces** in logical order."""
    tokens = line.split(' ')
    space_width = font.advance(font.gid(0x20)) * size / font.units_per_em
    rtl = has_arabic(line)

    # Measure every word first so the line can be right- or left-aligned.
    words: list[str] = [token for token in tokens if token]
    widths = []
    for word in words:
        probe = PlacedWord(font, word, 0.0, y, size)
        widths.append(probe.width)

    placed: list[PlacedWord] = []
    cursor = right if rtl else left
    logical: list[PlacedWord] = []
    for index, (word, width) in enumerate(zip(words, widths)):
        if rtl:
            logical.append(PlacedWord(font, word, cursor - width, y, size))
            cursor -= width
            if index + 1 < len(words):
                space = PlacedWord(font, ' ', cursor - space_width, y, size)
                logical.append(space)
                cursor -= space_width
        else:
            logical.append(PlacedWord(font, word, cursor, y, size))
            cursor += width
            if index + 1 < len(words):
                space = PlacedWord(font, ' ', cursor, y, size)
                logical.append(space)
                cursor += space_width
    placed = logical
    return placed


def emission_order(words: list[PlacedWord], order: str,
                   rtl: bool = True) -> list[PlacedWord]:
    """Visual order reverses the word sequence on an RTL line only."""
    if order == 'logical' or not rtl:
        return words
    return list(reversed(words))


def total_width(words: list[PlacedWord]) -> float:
    if not words:
        return 0.0
    first, last = words[0], words[-1]
    left = min(first.x, last.x)
    right = max(first.x + first.width, last.x + last.width)
    return right - left
