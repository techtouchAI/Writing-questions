"""Mechanism probes: does each engine honour ActualText / invisible text?

These are *diagnostic* PDFs, not candidate solutions. Each page isolates one
PDF mechanism so the four extractors' behaviour can be attributed:

  A. ActualText over a Latin word            - support probe with an ASCII value,
                                               so bidi cannot explain the result.
  B. ActualText over Arabic glyphs           - the same with an Arabic value.
  C. Invisible (`3 Tr`) duplicate run        - is hidden text extracted?
  D. Artifact-marked visual glyphs           - is /Artifact text skipped?
  E. Visual glyphs whose CIDs carry no
     ToUnicode entry                          - what do engines emit for them?

Run:
    python3 tool/prototype_semantic_pdf/probe_mechanisms.py --out DIR
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from pdfwriter import FontEncoder, PdfWriter, sha256  # noqa: E402
from run_prototype import extract_pages  # noqa: E402
from shaping import PrototypeFont  # noqa: E402
from strategies import PlacedWord, layout_line  # noqa: E402

REPO = HERE.parent.parent
FONT = REPO / 'assets' / 'fonts' / 'NotoNaskhArabic-Regular.ttf'
SIZE = 20.0


def _span(text: str) -> str:
    payload = text.encode('utf-16-be').hex().upper()
    return f'/Span<</ActualText<FEFF{payload}>>>BDC '


def build(out: Path) -> dict:
    font = PrototypeFont(str(FONT))
    encoder = FontEncoder(font)
    word = layout_line(font, 'سَلَامٌ', SIZE, left=60, right=535, y=700)[0]
    latin = layout_line(font, 'TEST', SIZE, left=60, right=535, y=700)[0]

    cids_arabic = [encoder.cid(gid, word.payload(idx, 'decomposed_visual'))
                   for gid, _, idx, _ in word.glyphs]
    cids_latin = [encoder.cid(gid, latin.payload(idx, 'decomposed_visual'))
                  for gid, _, idx, _ in latin.glyphs]
    tj_arabic = f'[{encoder.hex_text(cids_arabic)}] TJ'
    tj_latin = f'[{encoder.hex_text(cids_latin)}] TJ'
    head = f'BT /F1 {SIZE:g} Tf 1 0 0 1 60 700 Tm'

    cids_empty = [encoder.cid(gid, '') for gid, _, _, _ in word.glyphs]
    tj_empty = f'[{encoder.hex_text(cids_empty)}] TJ'
    logical_cids = [encoder.cid(gid, word.payload(idx, 'decomposed'))
                    for gid, _, idx, _ in sorted(word.glyphs, key=lambda i: i[2])]
    tj_logical = f'[{encoder.hex_text(logical_cids)}] TJ'

    pages = {
        'A_actualtext_latin': f'{_span("HELLO")}{head} {tj_latin} ET EMC',
        'B_actualtext_arabic': f'{_span("سَلَامٌ")}{head} {tj_arabic} ET EMC',
        'C_invisible_duplicate': (f'{head} {tj_arabic} ET '
                                  f'BT /F1 {SIZE:g} Tf 3 Tr 1 0 0 1 60 700 Tm '
                                  f'{tj_logical} 0 Tr ET'),
        'D_artifact': f'/Artifact BMC {head} {tj_arabic} ET EMC',
        'E_no_tounicode': f'{head} {tj_empty} ET',
        'F_explicit_empty': (
            f'{head} '
            + '['
            + encoder.hex_text([
                encoder.cid(gid, '' if index == 2 else word.payload(idx, 'decomposed_visual'))
                for index, (gid, _, idx, _) in enumerate(word.glyphs)
            ])
            + '] TJ ET'),
    }
    data = PdfWriter(encoder).build(list(pages.values()))
    out.mkdir(parents=True, exist_ok=True)
    pdf = out / 'mechanisms.pdf'
    pdf.write_bytes(data)
    result = {'pdfSha256': sha256(data), 'pages': {}}
    page_names = list(pages)
    for engine in ('mupdf', 'pdfium', 'pdfminer', 'pypdf'):
        texts = extract_pages(pdf, engine, len(pages))
        for name, text in zip(page_names, texts):
            result['pages'].setdefault(name, {})[engine] = text
    (out / 'mechanisms.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, by_engine in result['pages'].items():
        print(f'{name}:')
        for engine, text in by_engine.items():
            print(f'   {engine:9s} {text!r}')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    build(parser.parse_args().out)
