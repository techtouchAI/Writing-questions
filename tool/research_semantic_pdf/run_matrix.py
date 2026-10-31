"""Controlled experiments for the strict Option-A target (research only).

Reference PDF
-------------
`REFERENCE` below reproduces the *shipped* semantic emission exactly (visual
paint order, one `BT` per word, the production "decomposed visual" payload rule).
It is the pixel reference: every candidate design must produce a raster that is
bit-identical to this reference at the same DPI/colour space, and the reference
itself is never modified.

Factors (documented factorial, one factor changed at a time)
------------------------------------------------------------
order       visual | logical      - paint (and therefore stream) order
ops         single | isolated     - one `BT` per word vs one `BT` per glyph
payload     legacy | segment      - `/ToUnicode` payload ownership
actualText  none   | word | cluster

Nothing here touches production code: the module only imports the prototype
writer (`tool/prototype_semantic_pdf`) and the extractor libraries.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROTOTYPE = (HERE / '../prototype_semantic_pdf').resolve()
sys.path.insert(0, str(PROTOTYPE))
sys.path.insert(0, str(HERE))

from compare import judge  # noqa: E402
from corpus_r import CORPUS, describe, reference  # noqa: E402
from pdfwriter import FontEncoder, PdfWriter  # noqa: E402
from shaping import PrototypeFont  # noqa: E402
from layout_r import emission_order, place_line  # noqa: E402
from strategies import has_arabic  # noqa: E402
from strategies import PlacedWord  # noqa: E402

FONT = str((HERE / '../../assets/fonts/NotoNaskhArabic-Regular.ttf').resolve())

REFERENCE = {'order': 'visual', 'ops': 'line', 'payload': 'legacy', 'actualText': 'none'}
ORDERS = ('visual', 'logical')
OPS = ('line', 'single', 'isolated')
PAYLOADS = ('legacy', 'segment')
ACTUAL = ('none', 'word', 'cluster')


def _span(text: str) -> tuple[str, str]:
    payload = text.encode('utf-16-be').hex().upper()
    return f'/Span<</ActualText<FEFF{payload}>>>BDC', 'EMC'


def _entries(word: PlacedWord, order: str) -> list[tuple[int, int, int, float]]:
    return word.ordered() if order == 'logical' else list(word.glyphs)


def _payload(word: PlacedWord, idx: int, view: str) -> str:
    return word.payload(idx, 'decomposed_visual' if view == 'legacy' else 'segment')


def _text_ops(encoder, word: PlacedWord, gid: int, idx: int, x: float,
              ops: str, view: str) -> str:
    cid = encoder.cid(gid, _payload(word, idx, view))
    head = f'BT /F1 {word.size:g} Tf 1 0 0 1 {x:.4f} {word.y:.4f} Tm'
    return f'{head} {encoder.hex_text([cid])} Tj ET'


def emit_variant(encoder, word: PlacedWord, variant: dict[str, str]) -> str:
    order, ops, view, actual = (variant['order'], variant['ops'],
                                variant['payload'], variant['actualText'])
    entries = _entries(word, order)

    if ops == 'single':
        pieces: list[str] = []
        if actual == 'word':
            begin, end = _span(word.text)
            pieces.append(begin)
        pieces.append(f'BT /F1 {word.size:g} Tf 1 0 0 1 {word.x:.4f} {word.y:.4f} Tm')
        current_cluster = None
        for gid, cluster, idx, x in entries:
            if actual == 'cluster' and cluster != current_cluster:
                if current_cluster is not None:
                    pieces.append('EMC')
                begin, _ = _span(word.clusters[cluster])
                pieces.append(begin)
                current_cluster = cluster
            pieces.append(f'1 0 0 1 {x:.4f} {word.y:.4f} Tm'
                          f' {encoder.hex_text([encoder.cid(gid, _payload(word, idx, view))])} Tj')
        if actual == 'cluster' and current_cluster is not None:
            pieces.append('EMC')
        pieces.append('ET')
        if actual == 'word':
            pieces.append(end)
        return ' '.join(pieces)

    pieces = []
    if actual == 'word':
        begin, end = _span(word.text)
        pieces.append(begin)
    current_cluster = None
    for gid, cluster, idx, x in entries:
        if actual == 'cluster' and cluster != current_cluster:
            if current_cluster is not None:
                pieces.append('EMC')
            begin, _ = _span(word.clusters[cluster])
            pieces.append(begin)
            current_cluster = cluster
        pieces.append(_text_ops(encoder, word, gid, idx, x, ops, view))
    if actual == 'cluster' and current_cluster is not None:
        pieces.append('EMC')
    if actual == 'word':
        pieces.append(end)
    return '\n'.join(pieces)


def emit_line_variant(encoder, words: list, variant: dict[str, str],
                      rtl: bool = True) -> str:
    """Production-like emission: one `BT`/`Tj` for the whole line, one CID per glyph."""
    ordered = emission_order(words, variant['order'], rtl)
    entries: list[tuple[int, int, object]] = []
    for word in ordered:
        for gid, _, idx, _ in _entries(word, variant['order']):
            entries.append((gid, idx, word))
    if not entries:
        return 'BT ET'
    first = ordered[0]
    cids = [encoder.cid(gid, _payload(word, idx, variant['payload']))
            for gid, idx, word in entries]
    head = f'BT /F1 {first.size:g} Tf 1 0 0 1 {first.x:.4f} {first.y:.4f} Tm'
    return f'{head} {encoder.hex_text(cids)} Tj ET'


def build(item: dict, variant: dict[str, str], dest: Path) -> Path:
    font = PrototypeFont(FONT)
    encoder = FontEncoder(font)
    pages = []
    for line in item['lines']:
        words = place_line(font, line, 16.0, 60.0, 520.0, 700.0)
        rtl = has_arabic(line)
        if variant['ops'] == 'line':
            pages.append(emit_line_variant(encoder, words, variant, rtl))
        else:
            ordered = emission_order(words, variant['order'], rtl)
            pages.append('\n'.join(emit_variant(encoder, w, variant) for w in ordered))
    dest.write_bytes(PdfWriter(encoder).build(pages))
    return dest


# ---------------------------------------------------------------- extraction
def extract_engines(pdf: Path) -> dict[str, str]:
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
    reader = PdfReader(pdf)
    out['pypdf'] = '\n'.join(page.extract_text() or '' for page in reader.pages)
    return out


def raster(pdf: Path) -> list[bytes]:
    import pymupdf
    with pymupdf.open(pdf) as document:
        return [page.get_pixmap(dpi=150, colorspace=pymupdf.csGRAY).samples
                for page in document]


def pixel_diff(a: list[bytes], b: list[bytes]) -> int:
    total = 0
    for left, right in zip(a, b):
        total += sum(1 for x, y in zip(left, right) if x != y)
    return total


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(items: list[dict], variants: list[dict[str, str]], out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    report: dict = {'fontSha256': sha256(Path(FONT)), 'items': {},
                    'matrix': [], 'engines': {}}
    reference_rasters: dict[str, list[bytes]] = {}
    for item in items:
        pdf = build(item, REFERENCE, out / f"ref-{item['id']}.pdf")
        reference_rasters[item['id']] = raster(pdf)
        report['items'][item['id']] = dict(
            describe(item),
            referencePdf=f"ref-{item['id']}.pdf",
            referencePdfSha256=sha256(pdf),
            referencePageCount=len(reference_rasters[item['id']]),
            variants={},
        )

    for item, variant in itertools.product(items, variants):
        name = '-'.join(f"{k}={v}" for k, v in variant.items())
        pdf = build(item, variant, out / f"{item['id']}--{name}.pdf")
        texts = extract_engines(pdf)
        identical = pixel_diff(raster(pdf), reference_rasters[item['id']]) == 0
        entry = {'name': name, 'pdfSha256': sha256(pdf), 'pixelIdentical': identical,
                 'engines': {}}
        for engine, text in texts.items():
            verdict = judge(text, reference(item))
            entry['engines'][engine] = {
                'match': verdict['flat_match'],
                'rawSha256': hashlib.sha256(text.encode('utf-8')).hexdigest(),
                'raw': text,
            }
        report['items'][item['id']]['variants'][name] = entry
        report['matrix'].append({
            'item': item['id'], **variant,
            'mupdf': entry['engines']['mupdf']['match'],
            'pdfium': entry['engines']['pdfium']['match'],
            'pdfminer': entry['engines']['pdfminer']['match'],
            'pypdf': entry['engines']['pypdf']['match'],
            'pixelIdentical': identical,
            'allFour': all(entry['engines'][e]['match'] for e in ('mupdf', 'pdfium', 'pdfminer', 'pypdf')),
            'target': all(entry['engines'][e]['match'] for e in ('mupdf', 'pdfium', 'pdfminer', 'pypdf'))
            and identical,
        })
    return report


def variants_all() -> list[dict[str, str]]:
    return [dict(order=o, ops=s, payload=p, actualText=a)
            for o, s, p, a in itertools.product(ORDERS, OPS, PAYLOADS, ACTUAL)
            if not (a == 'cluster' and o == 'logical')  # documented exclusion: see report
            ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='research-artifacts/matrix')
    parser.add_argument('--items', default='')
    parser.add_argument('--variants', default='all',
                        help='comma list of order:ops:payload:actualText')
    args = parser.parse_args()
    wanted = [i for i in CORPUS if not args.items or i['id'] in args.items.split(',')]
    if args.variants == 'all':
        variants = variants_all()
    else:
        variants = []
        for spec in args.variants.split(','):
            order, ops, payload, actual = spec.split(':')
            variants.append(dict(order=order, ops=ops, payload=payload, actualText=actual))
    report = run(wanted, variants, Path(args.out))
    (Path(args.out) / 'report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    header = (f"{'item':18} {'order':8} {'ops':9} {'payload':8} {'actual':8} "
              f"{'mupdf':6} {'pdfium':7} {'pdfminer':9} {'pypdf':6} {'px':6} {'TARGET'}")
    print(header)
    for row in report['matrix']:
        print(f"{row['item']:18} {row['order']:8} {row['ops']:9} {row['payload']:8} "
              f"{row['actualText']:8} {'PASS' if row['mupdf'] else 'fail':6} "
              f"{'PASS' if row['pdfium'] else 'fail':7} {'PASS' if row['pdfminer'] else 'fail':9} "
              f"{'PASS' if row['pypdf'] else 'fail':6} "
              f"{'same' if row['pixelIdentical'] else 'DIFF':6} "
              f"{'YES' if row['target'] else '-'}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
