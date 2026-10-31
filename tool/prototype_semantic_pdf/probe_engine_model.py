"""Decisive probe: is each extractor stream-ordered, position-ordered, or bidi?

Diagnostic only. Six pages isolate the three possible ordering policies:

  P1 stream_vs_position  Latin glyphs "ABCD" emitted in stream order but placed
                         right-to-left by `Tm`; stream answer "ABCD", position
                         answer "DCBA".
  P2 visuals, no marks   Arabic "سلم" drawn visually, logical payloads.
  P3 logical stream      the same glyphs emitted in logical order.
  P4 visuals with marks  "سَلَم" drawn visually, logical payloads.
  P5 logical with marks  the same glyphs in logical stream order.
  P6 ligature + inner mark "وَلَا": a mark inside the lam-alef ligature, which
                         no per-glyph mapping can interleave.

Run:
    python3 tool/prototype_semantic_pdf/probe_engine_model.py --out DIR
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


def _fmt(value: str) -> str:
    return ' '.join(f'{ord(char):04X}' for char in value if char.strip())


def build(out: Path) -> dict:
    font = PrototypeFont(str(FONT))
    encoder = FontEncoder(font)
    pages: dict[str, str] = {}

    latin = layout_line(font, 'ABCD', SIZE, left=60, right=535, y=700)[0]
    cids = [encoder.cid(g.gid, g.payload_logical) for g, _, _, _ in latin.glyphs]
    # Emit in stream order A B C D but place them right-to-left.
    ops = ['BT /F1 %g Tf' % SIZE]
    xs = [400, 380, 360, 340]
    for cid, x in zip(cids, xs):
        ops.append(f'1 0 0 1 {x} 700 Tm {encoder.hex_text([cid])} Tj')
    ops.append('ET')
    pages['P1_stream_vs_position'] = ' '.join(ops)

    def word_page(text: str, logical_stream: bool) -> str:
        word = layout_line(font, text, SIZE, left=60, right=535, y=700)[0]
        head = f'BT /F1 {SIZE:g} Tf'
        if logical_stream:
            body = []
            for glyph, _, _, x in sorted(word.glyphs, key=lambda i: i[2]):
                cid = encoder.cid(glyph.gid, glyph.payload_logical)
                body.append(f'1 0 0 1 {x:.4f} 700 Tm {encoder.hex_text([cid])} Tj')
            return f'{head} ' + ' '.join(body) + ' ET'
        cids = [encoder.cid(g.gid, g.payload_logical) for g, _, _, _ in word.glyphs]
        return (f'{head} 1 0 0 1 {word.x:.4f} 700 Tm '
                f'[{encoder.hex_text(cids)}] TJ ET')

    pages['P2_visual_simple'] = word_page('سلم', logical_stream=False)
    pages['P3_logical_simple'] = word_page('سلم', logical_stream=True)
    pages['P4_visual_marks'] = word_page('سَلَم', logical_stream=False)
    pages['P5_logical_marks'] = word_page('سَلَم', logical_stream=True)
    pages['P6_visual_ligature'] = word_page('وَلَا', logical_stream=False)
    pages['P7_logical_ligature'] = word_page('وَلَا', logical_stream=True)

    data = PdfWriter(encoder).build(list(pages.values()))
    out.mkdir(parents=True, exist_ok=True)
    pdf = out / 'engine_model.pdf'
    pdf.write_bytes(data)
    result = {'pdfSha256': sha256(data), 'pages': {}}
    names = list(pages)
    for engine in ('mupdf', 'pdfium', 'pdfminer', 'pypdf'):
        texts = extract_pages(pdf, engine, len(pages))
        for name, text in zip(names, texts):
            result['pages'].setdefault(name, {})[engine] = {
                'text': text,
                'codepoints': _fmt(text),
            }
    (out / 'engine_model.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, by_engine in result['pages'].items():
        print(f'{name}')
        for engine, row in by_engine.items():
            print(f'   {engine:9s} {row["text"]!r}')
            print(f'             {row["codepoints"]}')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    build(parser.parse_args().out)
