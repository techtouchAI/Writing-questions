"""Driver: generate the prototype PDFs, extract with four engines, compare.

Run:
    python3 tool/prototype_semantic_pdf/run_prototype.py --out /path/to/artifacts

Artifacts (never committed): one PDF per strategy, per-page PNGs, raw extraction
per engine, and `report.json` with every SHA256.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from compare import judge  # noqa: E402
from corpus import CORPUS, reference  # noqa: E402
from pdfwriter import FontEncoder, PdfWriter, sha256  # noqa: E402
from shaping import PrototypeFont  # noqa: E402
from strategies import STRATEGIES, emit_line, layout_line  # noqa: E402

REPO = HERE.parent.parent
FONT = REPO / 'assets' / 'fonts' / 'NotoNaskhArabic-Regular.ttf'
ENGINES = ('mupdf', 'pdfium', 'pdfminer', 'pypdf')
SIZE = 20.0


def build_pdf(strategy: str, dest: Path) -> Path:
    font = PrototypeFont(str(FONT))
    encoder = FontEncoder(font)
    pages: list[str] = []
    for item in CORPUS:
        ops = []
        y = 700.0
        for line in item['lines']:
            words = layout_line(font, line, SIZE, left=60.0, right=535.0, y=y)
            ops.append(emit_line(encoder, words, strategy))
            y -= 60.0
        pages.append('\n'.join(ops))
    data = PdfWriter(encoder).build(pages)
    dest.write_bytes(data)
    return dest


def extract_engines(pdf: Path) -> dict[str, str]:
    from pdf_source_diagnostic import extract
    out = {}
    for engine in ENGINES:
        text, _ = extract(pdf, engine)
        out[engine] = text
    return out


def render_pages(pdf: Path, out_dir: Path) -> list[str]:
    import pymupdf
    hashes = []
    out_dir.mkdir(parents=True, exist_ok=True)
    with pymupdf.open(pdf) as document:
        for index, page in enumerate(document):
            pixmap = page.get_pixmap(dpi=150)
            path = out_dir / f'page-{index + 1}.png'
            path.write_bytes(pixmap.tobytes('png'))
            hashes.append(sha256(pixmap.samples))
    return hashes


def coverage(pdf: Path) -> list[bytes]:
    """Binarised ink coverage per page: geometry, independent of anti-aliasing."""
    import pymupdf
    out = []
    with pymupdf.open(pdf) as document:
        for page in document:
            pixmap = page.get_pixmap(dpi=150, colorspace=pymupdf.csGRAY)
            out.append(bytes(1 if value < 128 else 0 for value in pixmap.samples))
    return out


def pixmaps(pdf: Path) -> list[bytes]:
    import pymupdf
    out = []
    with pymupdf.open(pdf) as document:
        for page in document:
            out.append(page.get_pixmap(dpi=150).samples)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    report = {'strategies': {}, 'influence': {}, 'pages': len(CORPUS)}
    baseline_pix: list[bytes] | None = None
    baseline_cov: list[bytes] | None = None
    baseline_name = STRATEGIES[0]

    for strategy in STRATEGIES:
        strategy_dir = args.out / strategy
        strategy_dir.mkdir(parents=True, exist_ok=True)
        pdf = build_pdf(strategy, strategy_dir / 'prototype.pdf')
        pdf_sha = sha256(pdf.read_bytes())
        page_hashes = render_pages(pdf, strategy_dir / 'pages')
        pix = pixmaps(pdf)
        cov = coverage(pdf)
        if baseline_pix is None:
            baseline_pix = pix
            baseline_cov = cov
            ink_delta = [0] * len(pix)
            coverage_delta = [0] * len(cov)
        else:
            coverage_delta = [
                sum(1 for a, b in zip(base, other) if a != b)
                if len(base) == len(other) else -1
                for base, other in zip(baseline_cov, cov)
            ]
            ink_delta = [
                sum(1 for a, b in zip(base, other) if a != b)
                if len(base) == len(other) else -1
                for base, other in zip(baseline_pix, pix)
            ]
        extracted = extract_engines(pdf)
        item_results = {}
        page_texts = extracted['mupdf'] if False else None
        # Split extracted text per page: re-extract per page for every engine so
        # a page's verdict cannot be diluted by neighbours.
        per_engine_pages: dict[str, list[str]] = {}
        import pymupdf
        with pymupdf.open(pdf) as document:
            page_count = len(document)
        for engine in ENGINES:
            per_engine_pages[engine] = extract_pages(pdf, engine, page_count)
            (strategy_dir / f'{engine}.txt').write_text(
                '\n\n'.join(per_engine_pages[engine]), encoding='utf-8')
        for index, item in enumerate(CORPUS):
            ref = reference(item)
            item_results[item['id']] = {
                engine: judge(per_engine_pages[engine][index], ref)
                for engine in ENGINES
            }
        passed = {
            engine: [item['id'] for item in CORPUS
                     if item_results[item['id']][engine]['flat_match']]
            for engine in ENGINES
        }
        report['strategies'][strategy] = {
            'pdfSha256': pdf_sha,
            'pagePixmapSha256': page_hashes,
            'inkDeltaPixelsVsBaseline': ink_delta,
            'coverageDeltaPixelsVsBaseline': coverage_delta,
            'items': item_results,
            'flatMatchesPerEngine': {engine: len(ids) for engine, ids in passed.items()},
            'passingItemsPerEngine': passed,
            'allEnginesAllItemsFlatMatch': all(
                len(ids) == len(CORPUS) for ids in passed.values()),
        }
        print(f'[{strategy}] sha={pdf_sha[:12]} '
              f'matches={ {e: len(v) for e, v in passed.items()} }')

    (args.out / 'report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('wrote', args.out / 'report.json')
    return 0


def extract_pages(pdf: Path, engine: str, page_count: int) -> list[str]:
    """Extract one page at a time with the requested engine."""
    if engine == 'mupdf':
        import pymupdf
        with pymupdf.open(pdf) as document:
            return [page.get_text() for page in document]
    if engine == 'pdfium':
        import pypdfium2
        document = pypdfium2.PdfDocument(pdf)
        try:
            pages = []
            for index in range(len(document)):
                page = document[index]
                try:
                    textpage = page.get_textpage()
                    try:
                        pages.append(textpage.get_text_range())
                    finally:
                        textpage.close()
                finally:
                    page.close()
            return pages
        finally:
            document.close()
    if engine == 'pdfminer':
        from pdfminer.high_level import extract_text
        return [extract_text(str(pdf), page_numbers=[index])
                for index in range(page_count)]
    if engine == 'pypdf':
        from pypdf import PdfReader
        reader = PdfReader(str(pdf))
        return [page.extract_text() for page in reader.pages]
    raise ValueError(engine)


if __name__ == '__main__':
    raise SystemExit(main())
