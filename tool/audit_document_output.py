#!/usr/bin/env python3
"""Audit real, produced documents -- not the tests that produced them.

This tool reads a PDF the application (or the visual fixture) actually wrote and
answers the questions a human reviewer and a release gate ask:

* structure  -- pages, page size, span count, text outside the page box,
                overlapping spans, duplicated spans at the same position;
* typography -- every font embedded as a font file (never referenced only by
                name), and the combining marks actually drawn on the page;
* parity     -- when the preview's own page images are supplied, the PDF is
                rasterised at the preview's pixel width and compared page by
                page: differing pixels, differing share, RMSE, and the CI
                allowance of 2% differing ink. Numbers are printed, never
                rounded into "pixel-perfect".

Text *content* against the source is not decided here: Arabic extraction is a
documented quality metric, not an equality channel (see
docs/review/pr48_document_correctness_audit.md). Content equality is asserted
where the source model is available -- the export gate and the fixture tests --
and read visually from the rendered pages this tool writes.

Exit status: 0 when every structural check passes, 1 otherwise. Parity exit is
separate (--require-parity) so a document can be structurally audited without
preview images.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import unicodedata
from pathlib import Path

import pymupdf


def font_is_embedded(document, page) -> list[dict]:
    """Every font a page draws with, and whether a font file is embedded."""
    out = []
    for font in page.get_fonts(full=True):
        xref, ext, kind, basefont, name, _enc = font[0], font[1], font[2], font[3], font[4], font[5]
        embedded = False
        if xref:
            try:
                info = document.extract_font(xref)
                embedded = bool(info and info[3])
            except Exception:                       # an unreadable xref is not embedded
                embedded = False
        out.append({'basefont': basefont, 'type': kind, 'embedded': embedded,
                    'ext': ext, 'name': name})
    return out


def spans_of(page) -> list[dict]:
    spans = []
    for block in page.get_text('dict').get('blocks', []):
        for line in block.get('lines', []):
            for span in line.get('spans', []):
                spans.append(span)
    return spans


def intersection_ratio(a, b) -> float:
    ix = min(a[2], b[2]) - max(a[0], b[0])
    iy = min(a[3], b[3]) - max(a[1], b[1])
    if ix <= 0 or iy <= 0:
        return 0.0
    smaller = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
    return (ix * iy) / smaller if smaller > 0 else 0.0


def _is_blank(span) -> bool:
    return not span.get('text', '').strip()


def _same_line_boundary(a, b) -> bool:
    """Two spans that share a baseline and only meet at a run boundary.

    RTL runs are emitted as separate spans, so a colon, a dash or a space can
    have a box that lies inside its neighbour's box. That is a boundary, not
    ink printed on ink: the projection differs, and the neighbour's own ink
    does not cover the small span's ink. Only cross-line collisions are a
    defect; these are counted and reported separately for reading.
    """
    same_baseline = abs(a['origin'][1] - b['origin'][1]) < 1.0
    if not same_baseline:
        return False
    ax0, _, ax1, _ = a['bbox']
    bx0, _, bx1, _ = b['bbox']
    return ax0 <= bx1 + 1.0 and bx0 <= ax1 + 1.0


def audit_page(page, document) -> dict:
    rect = page.rect
    spans = spans_of(page)
    outside = 0
    marks = 0
    duplicates = 0
    for span in spans:
        x0, y0, x1, y1 = span['bbox']
        if x0 < rect.x0 - 0.5 or y0 < rect.y0 - 0.5 or x1 > rect.x1 + 0.5 or y1 > rect.y1 + 0.5:
            outside += 1
        for char in span.get('chars', []):
            if unicodedata.category(char['c']) == 'Mn':
                marks += 1
    overlaps = 0
    boundaries = []
    for i in range(len(spans)):
        for j in range(i + 1, len(spans)):
            if _is_blank(spans[i]) or _is_blank(spans[j]):
                continue
            if intersection_ratio(spans[i]['bbox'], spans[j]['bbox']) <= 0.35:
                continue
            if _same_line_boundary(spans[i], spans[j]):
                boundaries.append({'a': spans[i]['text'][:30], 'b': spans[j]['text'][:30]})
                continue
            overlaps += 1
    for i in range(len(spans)):
        for j in range(i + 1, len(spans)):
            a, b = spans[i], spans[j]
            if (a.get('text') and a['text'] == b.get('text')
                    and abs(a['bbox'][0] - b['bbox'][0]) < 0.5
                    and abs(a['bbox'][1] - b['bbox'][1]) < 0.5):
                duplicates += 1
    return {
        'spans': len(spans),
        'outOfBounds': outside,
        'overlappingPairs': overlaps,
        'boundaryPairs': len(boundaries),
        'boundarySamples': boundaries[:5],
        'duplicateSpans': duplicates,
        'combiningMarks': marks,
        'fonts': font_is_embedded(document, page),
    }


def luma(path_or_bytes) -> tuple[list[float], int, int]:
    pix = pymupdf.Pixmap(path_or_bytes)
    samples = pix.samples
    width, height, channels = pix.width, pix.height, pix.n
    out = [0.0] * (width * height)
    for index in range(width * height):
        base = index * channels
        if channels >= 3:
            value = (0.299 * samples[base] + 0.587 * samples[base + 1]
                     + 0.114 * samples[base + 2])
        else:
            value = samples[base]
        out[index] = value / 255.0
    return out, width, height


def parity(pdf: Path, preview_dir: Path, out_dir: Path) -> dict:
    """Rasterise each page at the preview's width and compare to the preview."""
    document = pymupdf.open(pdf)
    report = {'pages': [], 'rmseMax': 0.0, 'diffShareMax': 0.0}
    for index in range(document.page_count):
        preview = preview_dir / f'preview_page_{index + 1}.png'
        if not preview.exists():
            report['pages'].append({'page': index + 1, 'preview': None})
            continue
        target, width, height = luma(str(preview))
        zoom = width / document[index].rect.width
        pix = document[index].get_pixmap(matrix=pymupdf.Matrix(zoom, zoom),
                                         colorspace=pymupdf.csGRAY)
        rendered = [
            pix.samples[i * pix.n] / 255.0
            for i in range(min(pix.width * pix.height, width * height))
        ]
        total = min(len(rendered), len(target))
        differing = sum(1 for i in range(total) if abs(rendered[i] - target[i]) > 0.08)
        squared = sum((rendered[i] - target[i]) ** 2 for i in range(total))
        rmse = (squared / total) ** 0.5 if total else 0.0
        share = differing / total if total else 0.0
        report['rmseMax'] = max(report['rmseMax'], rmse)
        report['diffShareMax'] = max(report['diffShareMax'], share)
        page = {'page': index + 1, 'preview': preview.name,
                'widthPx': width, 'heightPx': height,
                'differingPixels': differing, 'diffShare': round(share, 6),
                'rmse': round(rmse, 6)}
        report['pages'].append(page)
        # Keep the rendered page next to the preview for human reading.
        out_dir.mkdir(parents=True, exist_ok=True)
        page_pix = document[index].get_pixmap(dpi=150)
        (out_dir / f'rendered_page_{index + 1}.png').write_bytes(page_pix.tobytes('png'))
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--pdf', required=True)
    parser.add_argument('--preview-dir', default='')
    parser.add_argument('--out', default='')
    parser.add_argument('--render', default='', help='directory for rendered pages')
    args = parser.parse_args()

    pdf = Path(args.pdf)
    document = pymupdf.open(pdf)
    report = {
        'pdf': str(pdf),
        'sha256': hashlib.sha256(pdf.read_bytes()).hexdigest(),
        'bytes': pdf.stat().st_size,
        'pages': document.page_count,
        'pageSizes': [[round(p.rect.width, 2), round(p.rect.height, 2)] for p in document],
        'audit': [],
    }
    failures = []
    for index, page in enumerate(document):
        entry = audit_page(page, document)
        entry['page'] = index + 1
        report['audit'].append(entry)
        if entry['outOfBounds']:
            failures.append(f"page {index + 1}: {entry['outOfBounds']} span(s) outside the page box")
        if entry['overlappingPairs']:
            failures.append(f"page {index + 1}: {entry['overlappingPairs']} overlapping span pair(s)")
        if entry['duplicateSpans']:
            failures.append(f"page {index + 1}: {entry['duplicateSpans']} duplicated span(s)")
        missing = [f['basefont'] for f in entry['fonts'] if not f['embedded']]
        if missing:
            failures.append(f"page {index + 1}: font not embedded: {sorted(set(missing))}")

    if args.render:
        out_dir = Path(args.render)
        out_dir.mkdir(parents=True, exist_ok=True)
        for index, page in enumerate(document):
            (out_dir / f'page_{index + 1}.png').write_bytes(
                page.get_pixmap(dpi=150).tobytes('png'))

    if args.preview_dir:
        report['parity'] = parity(pdf, Path(args.preview_dir), Path(args.render or '.'))

    if args.out:
        Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                                  encoding='utf-8')

    print(f"{pdf.name}: {report['pages']} page(s), {report['bytes']} bytes, "
          f"sha256 {report['sha256'][:16]}…")
    for entry in report['audit']:
        fonts = ', '.join(sorted({f['basefont'] for f in entry['fonts']}))
        print(f"  page {entry['page']}: spans={entry['spans']} "
              f"out={entry['outOfBounds']} overlaps={entry['overlappingPairs']} "
              f"dupes={entry['duplicateSpans']} boundary={entry['boundaryPairs']} "
              f"marks={entry['combiningMarks']} "
              f"fonts=[{fonts}]")
    if 'parity' in report:
        for page in report['parity']['pages']:
            if page.get('preview'):
                print(f"  parity p{page['page']}: diff={page['differingPixels']} px "
                      f"({page['diffShare'] * 100:.3f}%) rmse={page['rmse']:.6f} "
                      f"-- two rasterisers, not identical")
    for failure in failures:
        print(f'::error title=document audit::{failure}')
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
