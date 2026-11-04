"""Encoding strategies under test, all ink-invariant.

Every strategy receives the same glyph ids at the same absolute positions with
the same advances, and changes only the semantic channel:

1.  visual_legacy_payload    - shipped production emission: visual stream,
                               decomposed payload, ligature letters reversed.
2.  visual_logical_payload   - visual stream, decomposed payload in logical order.
3.  visual_segment_payload   - visual stream, *source-segment* payload in visual
                               order (a lam-alef glyph carries "اَل", including a
                               mark written between lam and alef); marks whose
                               character is owned by a ligature carry nothing.
4.  logical_segment_payload  - the same source segments emitted in **logical**
                               order, each glyph placed by its own `Tm`.
5.  logical_decomposed       - logical order, decomposed payloads.
6.  logical_segment_actual   - (4) + word-level `/ActualText`.
7.  visual_segment_actual    - (3) + word-level `/ActualText`.
8.  word_payload_single_cid  - whole word payload on the first CID, no mapping
                               for the rest (recorded, rejected).
9.  visual_plus_invisible    - visible glyphs unmapped + invisible logical run
                               (recorded, rejected).

Payload views
-------------
decomposed        Unicode base letters of the glyph's presentation form, logical
decomposed_visual the same, reversed to visual order (the shipped ligature rule)
segment           the exact source characters the glyph renders; a ligature owns
                  the marks written inside its source span
segment_visual    the same segment reversed
"""
from __future__ import annotations

from outline import glyph_path
from shaping import PrototypeFont, align_source, shape_logical, visual_order

ARABIC_RANGES = ((0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF),
                 (0xFB50, 0xFDFF), (0xFE70, 0xFEFF))


def has_arabic(text: str) -> bool:
    return any(any(lo <= ord(c) <= hi for lo, hi in ARABIC_RANGES) for c in text)


def _source_indices(shaped: str, visual: str) -> list[int]:
    pools: dict[str, list[int]] = {}
    for index, char in enumerate(shaped):
        pools.setdefault(char, []).append(index)
    used: dict[str, int] = {}
    order: list[int] = []
    for char in visual:
        position = used.get(char, 0)
        order.append(pools[char][position])
        used[char] = position + 1
    return order


def _base_payload(char: str) -> str:
    import unicodedata
    code = ord(char)
    if 0xFB50 <= code <= 0xFEFE or 0xFE70 <= code <= 0xFEFF:
        raw = unicodedata.decomposition(char)
        parts = [p for p in raw.split() if not p.startswith('<')]
        return ''.join(chr(int(p, 16)) for p in parts) if parts else char
    return char


def _is_mark_char(char: str) -> bool:
    from shaping import is_mark
    return is_mark(ord(char))


class PlacedWord:
    """One drawn word: glyph placement plus its logical source bookkeeping."""

    def __init__(self, font: PrototypeFont, text: str, x: float, y: float, size: float):
        self.text = text
        self.font_path = font.path
        self.rtl = has_arabic(text)
        self.size = size
        self.x = x
        self.y = y
        shaped = shape_logical(text) if self.rtl else text
        visual = visual_order(shaped, base_dir='R') if self.rtl else text
        if self.rtl:
            index_of = _source_indices(shaped, visual)
            segments = align_source(text, shaped)
        else:
            index_of = list(range(len(shaped)))
            segments = {index: char for index, char in enumerate(text)}
        cluster_of = []
        current = 0
        for index, char in enumerate(shaped):
            if index and not _is_mark_char(char):
                current += 1
            cluster_of.append(current)

        self.glyphs: list[tuple[int, int, int, float]] = []  # gid, cluster, logical idx, x
        self.code_of: dict[int, int] = {}
        pen = x
        for char, logical_index in zip(visual, index_of):
            code = ord(char)
            gid = font.gid(code)
            advance = 0 if _is_mark_char(char) else font.advance(gid)
            self.glyphs.append((gid, cluster_of[logical_index], logical_index, pen))
            self.code_of[logical_index] = code
            pen += advance * size / font.units_per_em
        self.width = pen - x

        self.payloads: dict[str, dict[int, str]] = {
            'decomposed': {}, 'decomposed_visual': {},
            'segment': {}, 'segment_visual': {},
        }
        for logical_index in range(len(shaped)):
            char = shaped[logical_index]
            base = _base_payload(char)
            segment = segments[logical_index]
            self.payloads['decomposed'][logical_index] = base
            self.payloads['decomposed_visual'][logical_index] = (
                ''.join(reversed(base)) if len(base) > 1 else base)
            self.payloads['segment'][logical_index] = segment
            self.payloads['segment_visual'][logical_index] = ''.join(reversed(segment))

        self.clusters: dict[int, str] = {}
        for logical_index in sorted(range(len(shaped))):
            key = cluster_of[logical_index]
            self.clusters[key] = self.clusters.get(key, '') + segments[logical_index]

    # -- helpers ---------------------------------------------------------
    def payload(self, logical_index: int, view: str) -> str:
        return self.payloads[view][logical_index]

    def ordered(self) -> list[tuple[int, int, int, float]]:
        return sorted(self.glyphs, key=lambda item: item[2])


def _word_geometry(font: PrototypeFont, word: str, size: float,
                   rtl: bool) -> float:
    shaped = shape_logical(word) if rtl else word
    width = 0.0
    for char in shaped:
        if _is_mark_char(char):
            continue
        width += font.advance(font.gid(ord(char))) * size / font.units_per_em
    return width


def layout_line(font: PrototypeFont, line: str, size: float,
                left: float, right: float, y: float) -> list[PlacedWord]:
    """Lay an RTL or LTR line out; words keep logical order in the line."""
    rtl_line = has_arabic(line)
    space = font.advance(font.gid(0x20)) * size / font.units_per_em
    words = [w for w in line.split(' ') if w]
    widths = [_word_geometry(font, w, size, has_arabic(w)) for w in words]
    placed: list[PlacedWord] = []
    cursor = right if rtl_line else left
    for word, width in zip(words, widths):
        if rtl_line:
            placed.append(PlacedWord(font, word, cursor - width, y, size))
            cursor -= width + space
        else:
            placed.append(PlacedWord(font, word, cursor, y, size))
            cursor += width + space
    return placed


def _tj(encoder, cids: list[int]) -> str:
    return f'[{encoder.hex_text(cids)}] TJ'


def _span(text: str) -> str:
    payload = text.encode('utf-16-be').hex().upper()
    return f'/Span<</ActualText<FEFF{payload}>>>BDC '


def _visual_run(encoder, word: PlacedWord, view: str) -> str:
    return _tj(encoder, [encoder.cid(gid, word.payload(idx, view))
                         for gid, _, idx, _ in word.glyphs])


def _logical_run(encoder, word: PlacedWord, view: str) -> str:
    ops = []
    for gid, _, idx, x in word.ordered():
        cid = encoder.cid(gid, word.payload(idx, view))
        ops.append(f'1 0 0 1 {x:.4f} {word.y:.4f} Tm {encoder.hex_text([cid])} Tj')
    return ' '.join(ops)


def emit_word(encoder, word: PlacedWord, strategy: str) -> str:
    head = f'BT /F1 {word.size:g} Tf 1 0 0 1 {word.x:.4f} {word.y:.4f} Tm'
    tail = 'ET'
    if strategy == 'visual_legacy_payload':
        return f'{head} {_visual_run(encoder, word, "decomposed_visual")} {tail}'
    if strategy == 'visual_logical_payload':
        return f'{head} {_visual_run(encoder, word, "decomposed")} {tail}'
    if strategy == 'visual_segment_payload':
        return f'{head} {_visual_run(encoder, word, "segment_visual")} {tail}'
    if strategy == 'logical_segment_payload':
        return f'{head} {_logical_run(encoder, word, "segment")} {tail}'
    if strategy == 'logical_decomposed':
        return f'{head} {_logical_run(encoder, word, "decomposed")} {tail}'
    if strategy == 'logical_segment_actual':
        return f'{_span(word.text)}{head} {_logical_run(encoder, word, "segment")} {tail} EMC'
    if strategy == 'visual_segment_actual':
        return (f'{_span(word.text)}{head} {_visual_run(encoder, word, "segment_visual")} '
                f'{tail} EMC')
    if strategy == 'visual_segment_outlined_marks':
        # Marks owned by a ligature are drawn as outlines: their characters are
        # already inside the ligature's payload, so they must not enter the text
        # channel a second time.
        text_glyphs = [(gid, idx) for gid, _, idx, _ in word.glyphs
                       if word.payload(idx, 'segment_visual')]
        cids = [encoder.cid(gid, word.payload(idx, 'segment_visual'))
                for gid, idx in text_glyphs]
        outlined = [(gid, x) for gid, _, idx, x in word.glyphs
                    if not word.payload(idx, 'segment_visual')]
        ops = [f'{head} {_tj(encoder, cids)} {tail}']
        for gid, x in outlined:
            ops.append(glyph_path(word.font_path, gid, x, word.y, word.size))
            ops.append('f')
        return '\n'.join(ops)
    if strategy == 'visual_cluster_outlined_marks':
        # One CID per *base* glyph carrying its whole source cluster (base plus
        # the marks written on it) in visual order; every combining mark is an
        # outline, so the text channel holds no zero-advance glyph at all.
        text_glyphs: list[tuple[int, str]] = []
        cluster_text: dict[int, str] = {}
        for _, cluster, idx, _ in word.glyphs:
            if word.payload(idx, 'segment'):
                cluster_text[cluster] = cluster_text.get(cluster, '') + \
                    word.payload(idx, 'segment')
        for gid, cluster, idx, x in word.glyphs:
            segment = word.payload(idx, 'segment')
            if not segment:
                continue
            if _is_mark_char(chr(word.code_of[idx])):
                continue
            text_glyphs.append((gid, ''.join(reversed(cluster_text[cluster]))))
        cids = [encoder.cid(gid, payload) for gid, payload in text_glyphs]
        outlined = [(gid, x) for gid, _, idx, x in word.glyphs
                    if _is_mark_char(chr(word.code_of[idx])) or not word.payload(idx, 'segment')]
        ops = [f'{head} {_tj(encoder, cids)} {tail}']
        for gid, x in outlined:
            ops.append(glyph_path(word.font_path, gid, x, word.y, word.size))
            ops.append('f')
        return '\n'.join(ops)
    if strategy == 'word_payload_single_cid':
        cids = [encoder.cid(gid, word.text if index == 0 else '')
                for index, (gid, _, _, _) in enumerate(word.glyphs)]
        return f'{head} {_tj(encoder, cids)} {tail}'
    if strategy == 'visual_plus_invisible':
        visible = [encoder.cid(gid, '') for gid, _, _, _ in word.glyphs]
        logical = _logical_run(encoder, word, 'segment')
        return (f'{head} {_tj(encoder, visible)} {tail} '
                f'BT /F1 {word.size:g} Tf 3 Tr {logical} 0 Tr {tail}')
    raise ValueError(f'unknown strategy {strategy}')


def emit_line(encoder, words: list[PlacedWord], strategy: str) -> str:
    return '\n'.join(emit_word(encoder, word, strategy) for word in words)


STRATEGIES = (
    'visual_legacy_payload',
    'visual_segment_outlined_marks',
    'visual_cluster_outlined_marks',
    'visual_logical_payload',
    'visual_segment_payload',
    'logical_segment_payload',
    'logical_decomposed',
    'logical_segment_actual',
    'visual_segment_actual',
    'word_payload_single_cid',
    'visual_plus_invisible',
)
