"""Probe: does *operator isolation* decouple paint order from semantic order?

The earlier matrix emitted every word inside a single `BT`/`ET` pair. That is not
neutral for the extractors: `pypdf` accumulates one "run" per `BT` block and
prepends every RTL character, so a logical-order run inside one `BT` is reversed
back into visual order. `pypdf`'s `_handle_bt` flushes the accumulated run
(`text_extraction/_text_extractor.py`), which means **one `BT` per glyph** gives
each glyph its own run and removes the reversal entirely.

This probe measures the four combinations that were never measured:

* order  : visual (shipped) vs logical (source order)
* ops    : `single` (one `BT` per word, `Tm` per glyph, as shipped) vs
           `isolated` (one `BT`/`ET` per glyph)
* payload: `segment` (each glyph carries the source characters it renders) vs
           `cluster` (the base glyph carries its whole source cluster, marks
           carry nothing - only possible with isolation)

Like every other prototype strategy these are ink candidates: every glyph is
placed at its absolute production position with the same advance, so the page
raster must stay identical. Nothing here touches production code.
"""
from __future__ import annotations

import argparse
import itertools
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare import judge  # noqa: E402
from corpus import CORPUS, reference  # noqa: E402
from pdfwriter import FontEncoder, PdfWriter, sha256  # noqa: E402
from run_prototype import coverage, extract_engines, pixmaps  # noqa: E402
from shaping import PrototypeFont, is_mark, shape_logical  # noqa: E402
from strategies import PlacedWord, layout_line  # noqa: E402

HERE = Path(__file__).resolve().parent
FONT = str((HERE / '../../assets/fonts/NotoNaskhArabic-Regular.ttf').resolve())

ORDERS = ('visual', 'logical')
OPS = ('single', 'isolated')
PAYLOADS = ('segment', 'cluster')

ITEMS = ('salatun', 'multi_mark', 'waw_lam_alef', 'short_phrase', 'mixed')


def cluster_payloads(word: PlacedWord) -> dict[int, str]:
    """Source cluster per logical index: the base carries base+marks, marks ''."""
    cluster_text: dict[int, str] = {}
    for gid, cluster, idx, _ in word.glyphs:
        cluster_text[cluster] = cluster_text.get(cluster, '') + word.payload(idx, 'segment')
    result: dict[int, str] = {}
    for gid, cluster, idx, _ in word.glyphs:
        code = word.code_of[idx]
        if is_mark(code):
            result[idx] = ''
        else:
            result[idx] = cluster_text[cluster]
    return result


def payload_of(word: PlacedWord, view: str, idx: int) -> str:
    if view == 'segment':
        return word.payload(idx, 'segment')
    return cluster_payloads(word)[idx]


def emit(encoder, word: PlacedWord, order: str, ops: str, view: str) -> str:
    entries = word.ordered() if order == 'logical' else list(word.glyphs)
    cids = [(encoder.cid(gid, payload_of(word, view, idx)), x)
            for gid, _, idx, x in entries]
    head = f'BT /F1 {word.size:g} Tf'
    if ops == 'single':
        seq = [f'1 0 0 1 {word.x:.4f} {word.y:.4f} Tm']
        for cid, x in cids:
            seq.append(f'1 0 0 1 {x:.4f} {word.y:.4f} Tm {encoder.hex_text([cid])} Tj')
        return f'{head} {" ".join(seq)} ET'
    return ' '.join(f'{head} 1 0 0 1 {x:.4f} {word.y:.4f} Tm {encoder.hex_text([cid])} Tj ET'
                    for cid, x in cids)


def build(item: dict, order: str, ops: str, view: str, dest: Path) -> Path:
    font = PrototypeFont(FONT)
    encoder = FontEncoder(font)
    pages = []
    for line in item['lines']:
        words = layout_line(font, line, 16.0, 60.0, 520.0, 700.0)
        pages.append('\n'.join(emit(encoder, w, order, ops, view) for w in words))
    dest.write_bytes(PdfWriter(encoder).build(pages))
    return dest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='artifacts/isolated-ops')
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    wanted = [item for item in CORPUS if item['id'] in ITEMS]
    report = {'items': {}, 'matrix': [], 'engines': {}}

    # Baseline raster/coverage: shipped visual + single-BT emission.
    baselines: dict[str, list[bytes]] = {}
    for item in wanted:
        pdf = build(item, 'visual', 'single', 'segment', out / f"baseline-{item['id']}.pdf")
        baselines[item['id']] = pixmaps(pdf)

    for item in wanted:
        entry = {'why': item['why'], 'reference': reference(item), 'combos': []}
        for order, ops, view in itertools.product(ORDERS, OPS, PAYLOADS):
            name = f"{item['id']}-{order}-{ops}-{view}"
            pdf = build(item, order, ops, view, out / f'{name}.pdf')
            texts = extract_engines(pdf)
            identical = pixmaps(pdf) == baselines[item['id']]
            combo = {
                'name': name,
                'pdfSha256': sha256(pdf.read_bytes()),
                'pageIdentical': identical,
                'engines': {},
            }
            for engine, text in texts.items():
                verdict = judge(text, reference(item))
                combo['engines'][engine] = {
                    'flat_match': verdict['flat_match'],
                    'extracted_flat': verdict['extracted_flat'],
                }
            entry['combos'].append(combo)
            report['matrix'].append({
                'item': item['id'], 'order': order, 'ops': ops, 'payload': view,
                'mupdf': combo['engines']['mupdf']['flat_match'],
                'pdfium': combo['engines']['pdfium']['flat_match'],
                'pdfminer': combo['engines']['pdfminer']['flat_match'],
                'pypdf': combo['engines']['pypdf']['flat_match'],
                'pageIdentical': identical,
            })
        report['items'][item['id']] = entry

    (out / 'isolated_ops.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    header = f"{'item':14} {'order':8} {'ops':9} {'payload':8} {'mupdf':6} {'pdfium':7} " \
             f"{'pdfminer':9} {'pypdf':6} {'page'}"
    print(header)
    for row in report['matrix']:
        print(f"{row['item']:14} {row['order']:8} {row['ops']:9} {row['payload']:8} "
              f"{'PASS' if row['mupdf'] else 'fail':6} {'PASS' if row['pdfium'] else 'fail':7} "
              f"{'PASS' if row['pdfminer'] else 'fail':9} {'PASS' if row['pypdf'] else 'fail':6} "
              f"{'same' if row['pageIdentical'] else 'DIFF'}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
