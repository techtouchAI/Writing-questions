"""Two further semantic-channel mechanisms, measured and closed (research only).

The earlier matrix (`run_matrix.py`) varied order / text-showing operators /
`/ToUnicode` payload / `/ActualText`. It left exactly one family untested: make
the **drawn** layer extraction-silent so that a single invisible layer can carry
the whole logical string. That family is tested here, in two independent ways.

Experiment A - "silent drawn layer" via `/ToUnicode`
----------------------------------------------------
The drawn glyphs keep their exact positions and glyph ids (ink invariant) but
their CIDs are given either

* an **empty destination** (`<CID> <>` inside `beginbfchar`), or
* **no entry at all** in the CMap,

and an invisible (`3 Tr`) layer is drawn over the same positions carrying a
correct payload, once in logical and once in visual order.

Result: an empty destination does not silence anything - MuPDF, PDFium and pypdf
fall back to the raw code bytes and the document extracts as `\\x00\\x01\\x02...`
followed by the invisible layer. Absent entries behave the same. The family is
closed: a drawn glyph must map to *something* readable.

Experiment B - "silent drawn layer" via space mapping + detached layer
---------------------------------------------------------------------
Every drawn CID maps to U+0020 (a space: no ink, no control bytes) and the whole
logical text is written once into a single invisible run placed in the page
corner, laid out strictly left-to-right in logical order, so that the run's
x-order *is* the logical order.

Result: pdfminer - which never applies the bidi algorithm - jumps from 1/20 to
12/20, but MuPDF and PDFium reorder RTL runs themselves and collapse to 1-2/20,
and pypdf to 2/20. The total never exceeds the shipped design's 19/80. The two
engine classes want opposite orders in the same file, which is the incompatibility
already recorded in `docs/review/pr48_acceptance_impossibility_proof.md`; this
experiment shows it holds for a detached layer as well, not only for the drawn one.

Nothing here is imported by the application, and no production file changes.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROTOTYPE = (HERE / '../prototype_semantic_pdf').resolve()
sys.path.insert(0, str(PROTOTYPE))
sys.path.insert(0, str(HERE))

from compare import judge  # noqa: E402
from corpus_r import CORPUS, describe, reference  # noqa: E402
from layout_r import emission_order, place_line  # noqa: E402
from pdfwriter import FontEncoder, PdfWriter, _utf16_hex  # noqa: E402
from shaping import PrototypeFont  # noqa: E402
from strategies import has_arabic  # noqa: E402

FONT = str((HERE / '../../assets/fonts/NotoNaskhArabic-Regular.ttf').resolve())
SPACE = '\u0020'
ENGINES = ('mupdf', 'pdfium', 'pdfminer', 'pypdf')
SIZE = 16.0


class ProbeEncoder(FontEncoder):
    """`FontEncoder` that can emit empty `/ToUnicode` destinations."""

    def __init__(self, font: PrototypeFont, empty_destinations: bool = False):
        super().__init__(font)
        self.empty_destinations = empty_destinations

    def to_unicode(self) -> bytes:
        lines = [
            '/CIDInit /ProcSet findresource begin',
            '12 dict begin',
            'begincmap',
            '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def',
            '/CMapName /Adobe-Identity-UCS def',
            '/CMapType 2 def',
            '1 begincodespacerange',
            '<0000> <FFFF>',
            'endcodespacerange',
        ]
        # `None` = deliberately absent, `''` = present with an empty destination.
        entries: list[tuple[int, str | None]] = []
        for cid, (_, payload) in enumerate(self.pairs):
            if payload:
                entries.append((cid, payload))
            elif payload == '' and self.empty_destinations:
                entries.append((cid, None))
        for start in range(0, len(entries), 100):
            chunk = entries[start:start + 100]
            lines.append(f'{len(chunk)} beginbfchar')
            for cid, payload in chunk:
                destination = '<>' if payload is None else f'<{_utf16_hex(payload)}>'
                lines.append(f'<{cid:04X}> {destination}')
            lines.append('endbfchar')
        lines += ['endcmap', 'CMapName currentdict /CMap defineresource pop', 'end', 'end']
        return ('\n'.join(lines) + '\n').encode('latin-1')


def _line_words(font: PrototypeFont, item: dict) -> list[tuple[str, list]]:
    return [(line, place_line(font, line, SIZE, 60.0, 520.0, 700.0))
            for line in item['lines']]


def _drawn(encoder: FontEncoder, words: list, payload, rtl: bool) -> str:
    """The shipped ink geometry: one `BT` per line, one CID per drawn glyph."""
    ordered = emission_order(words, 'visual', rtl)
    entries = [(gid, idx, word) for word in ordered for gid, _, idx, _ in word.glyphs]
    if not entries:
        return 'BT ET'
    first = ordered[0]
    cids = [encoder.cid(gid, payload(word, idx)) for gid, idx, word in entries]
    return (f'BT /F1 {first.size:g} Tf 1 0 0 1 {first.x:.4f} {first.y:.4f} Tm '
            f'{encoder.hex_text(cids)} Tj ET')


def _overlay(encoder: FontEncoder, words: list, order: str, view: str,
             rtl: bool) -> str:
    """Invisible copy over the drawn positions (experiment A)."""
    pieces = []
    for word in emission_order(words, order, rtl):
        entries = word.ordered() if order == 'logical' else list(word.glyphs)
        cids = [encoder.cid(gid, word.payload(idx, view)) for gid, _, idx, _ in entries]
        pieces.append(f'BT /F1 {word.size:g} Tf 3 Tr 1 0 0 1 {word.x:.4f} {word.y:.4f} '
                      f'Tm {encoder.hex_text(cids)} Tj ET')
    return '\n'.join(pieces)


def _corner(encoder: FontEncoder, lines: list[list], view: str,
            top: float = 810.0, step: float = 20.0) -> str:
    """One invisible run per logical line, left-to-right logical order (experiment B)."""
    pieces = []
    y = top
    for words in lines:
        cids: list[int] = []
        for index, word in enumerate(words):
            if index:
                cids.append(encoder.cid(encoder.font.gid(0x20), SPACE))
            for gid, _, idx, _ in word.ordered():
                cids.append(encoder.cid(gid, word.payload(idx, view)))
        if cids:
            pieces.append(f'BT /F1 {SIZE:g} Tf 3 Tr 1 0 0 1 20 {y:.2f} Tm '
                          f'{encoder.hex_text(cids)} Tj ET')
            y -= step
    return '\n'.join(pieces)


def _legacy(word, idx) -> str:
    return word.payload(idx, 'decomposed_visual')


def _space(word, idx) -> str:
    return SPACE


def _variant_table() -> dict[str, dict]:
    """`drawn` is the payload of the drawn layer: 'payload' = shipped,
    '' = mapped to U+0020, None = left out of the `/ToUnicode` CMap."""
    return {
        'shipped': dict(drawn='payload', overlay=None, written='payload', empty=False),
        'a_empty_destinations': dict(drawn='', overlay=None, written='payload', empty=True),
        'a_absent_mappings': dict(drawn=None, overlay=None, written='payload', empty=False),
        'a_empty_plus_logical_overlay': dict(drawn='', overlay=('logical', 'decomposed'),
                                             written='payload', empty=True),
        'a_empty_plus_visual_overlay': dict(drawn='', overlay=('visual', 'decomposed_visual'),
                                            written='payload', empty=True),
        'b_space_plus_corner_logical': dict(drawn=' ', overlay=('corner', 'decomposed'),
                                            written='payload', empty=False),
        'b_space_plus_corner_segment': dict(drawn=' ', overlay=('corner', 'segment'),
                                            written='payload', empty=False),
    }


def build(item: dict, variant: dict, dest: Path) -> Path:
    font = PrototypeFont(FONT)
    encoder = ProbeEncoder(font, empty_destinations=variant['empty'])
    lines = _line_words(font, item)
    payload = _legacy if variant['drawn'] == 'payload' else (
        (lambda word, idx: variant['drawn']) if isinstance(variant['drawn'], str) else
        (lambda word, idx: None))
    overlay = variant['overlay']
    pages = []
    for line, words in lines:
        rtl = has_arabic(line)
        parts = [_drawn(encoder, words, payload, rtl)]
        if overlay and overlay[0] != 'corner':
            parts.append(_overlay(encoder, words, overlay[0], overlay[1], rtl=rtl))
        pages.append('\n'.join(parts))
    if overlay and overlay[0] == 'corner':
        pages[-1] = pages[-1] + '\n' + _corner(encoder, [w for _, w in lines], overlay[1])
    dest.write_bytes(PdfWriter(encoder).build(pages))
    return dest


def extract(pdf: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    import pymupdf
    with pymupdf.open(pdf) as document:
        out['mupdf'] = '\n'.join(page.get_text() for page in document)
    import pypdfium2
    document = pypdfium2.PdfDocument(pdf)
    try:
        out['pdfium'] = '\n'.join(page.get_textpage().get_text_range()
                                  for page in document)
    finally:
        document.close()
    from pdfminer.high_level import extract_text
    out['pdfminer'] = extract_text(pdf)
    from pypdf import PdfReader
    out['pypdf'] = '\n'.join(page.extract_text() or '' for page in PdfReader(pdf).pages)
    return out


def raster(pdf: Path) -> list[bytes]:
    import pymupdf
    with pymupdf.open(pdf) as document:
        return [page.get_pixmap(dpi=150, colorspace=pymupdf.csGRAY).samples
                for page in document]


def pixel_diff(left: list[bytes], right: list[bytes]) -> int:
    return sum(sum(1 for a, b in zip(x, y) if a != b) for x, y in zip(left, right))


def run(out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    variants = _variant_table()
    report: dict = {'font': FONT, 'items': {}, 'variants': {}, 'matrix': []}
    reference_raster: dict[str, list[bytes]] = {}
    for item in CORPUS:
        pdf = build(item, variants['shipped'], out / f"shipped-{item['id']}.pdf")
        reference_raster[item['id']] = raster(pdf)
        report['items'][item['id']] = describe(item)

    for name, variant in variants.items():
        counts = {engine: 0 for engine in ENGINES}
        worst = 0
        for item in CORPUS:
            pdf = build(item, variant, out / f"{item['id']}--{name}.pdf")
            texts = extract(pdf)
            diff = pixel_diff(raster(pdf), reference_raster[item['id']])
            worst = max(worst, diff)
            row = {'item': item['id'], 'variant': name, 'pixelDiff': diff}
            for engine in ENGINES:
                verdict = judge(texts[engine], reference(item))
                row[engine] = verdict['flat_match']
                row[f'{engine}Text'] = verdict['extracted_flat']
                counts[engine] += 1 if verdict['flat_match'] else 0
            report['matrix'].append(row)
        report['variants'][name] = {'perEngine': counts, 'total': sum(counts.values()),
                                    'maxPixelDiff': worst}
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='/tmp/semantic-layer-probe')
    parser.add_argument('--json', default='')
    args = parser.parse_args()
    out = Path(args.out)
    report = run(out)
    header = f"{'variant':32} " + ' '.join(f'{engine:>9}' for engine in ENGINES) + '   total  maxpx'
    print(header)
    for name, entry in report['variants'].items():
        cells = ' '.join(f"{entry['perEngine'][engine]:>9}" for engine in ENGINES)
        print(f"{name:32} {cells}   {entry['total']:>5}  {entry['maxPixelDiff']:>5}")
    if args.json:
        Path(args.json).write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
