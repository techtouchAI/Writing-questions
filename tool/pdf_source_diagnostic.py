"""Read-only, exact Unicode/extractor compatibility diagnostic; NOT PDF validation.

No normalization, bidi reversal, mark sorting, source substitution, or PDF edits.
An exact reference must occur as a complete text segment, not a substring of a
longer word (e.g. an accidentally repeated combining-mark suffix). A failure is
an extractor/reference mismatch, not by itself proof of invalid PDF structure.
The Android acceptance checks remain separate and unchanged.
"""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import unicodedata


def codepoints(text):
    return [f'U+{ord(char):04X}' for char in text]


def _continues_text(char):
    return bool(char) and (unicodedata.category(char)[0] in 'LMN' or char in '\u200c\u200d')


def exact_segment_count(text, reference):
    """Count whole, byte-for-byte-equivalent Unicode segments, never substrings."""
    if not reference:
        raise ValueError('An empty reference cannot establish source preservation')
    count, offset = 0, 0
    while True:
        start = text.find(reference, offset)
        if start < 0:
            return count
        end = start + len(reference)
        left = text[start - 1] if start else ''
        right = text[end] if end < len(text) else ''
        if not _continues_text(left) and not _continues_text(right):
            count += 1
        offset = start + 1


def extract(pdf, engine):
    # Imports are lazy so pure comparison tests need no native PDF dependencies.
    if engine == 'mupdf':
        import pymupdf
        with pymupdf.open(pdf) as document:
            return '\n'.join(page.get_text() for page in document), {
                'binding': pymupdf.VersionBind, 'core': pymupdf.VersionFitz}
    if engine == 'pdfium':
        import pypdfium2
        pages = []
        document = pypdfium2.PdfDocument(pdf)
        try:
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
        finally:
            document.close()
        return '\n'.join(pages), {
            'binding': importlib.metadata.version('pypdfium2'),
            'core': str(pypdfium2.PDFIUM_INFO)}
    if engine == 'pdfminer':
        from pdfminer.high_level import extract_text
        return extract_text(pdf), {'binding': importlib.metadata.version('pdfminer.six')}
    if engine == 'pypdf':
        from pypdf import PdfReader
        return '\n'.join(page.extract_text() for page in PdfReader(pdf).pages), {
            'binding': importlib.metadata.version('pypdf')}
    raise ValueError('Unknown extraction engine: ' + engine)


def diagnose(pdf, reference, output, engines, expected_count=1):
    if not reference or expected_count < 1 or len(engines) < 2 or len(set(engines)) != len(engines):
        raise ValueError('Require a nonempty reference, positive count, and distinct independent engines')
    output.mkdir(parents=True, exist_ok=True)
    report = dict(kind='Exact-reference extractor compatibility, NOT PDF syntax validation or full-document acceptance',
                  pdfSha256=hashlib.sha256(pdf.read_bytes()).hexdigest(),
                  reference=reference, referenceCodepoints=codepoints(reference),
                  expectedCount=expected_count, engines={})
    for engine in engines:
        text, version = extract(pdf, engine)
        raw = text.encode('utf-8')
        (output / f'{engine}.txt').write_bytes(raw)
        count = exact_segment_count(text, reference)
        report['engines'][engine] = dict(version=version,
            rawTextSha256=hashlib.sha256(raw).hexdigest(), rawCodepoints=len(text),
            substringCount=text.count(reference), delimitedExactCount=count,
            exactReferencePassed=count == expected_count)
    report['allRequestedEnginesMatch'] = all(row['exactReferencePassed'] for row in report['engines'].values())
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pdf', type=Path)
    parser.add_argument('--reference', required=True)
    parser.add_argument('--expected-count', type=int, default=1)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--engines', nargs='+', choices=['mupdf', 'pdfium', 'pdfminer', 'pypdf'],
                        default=['mupdf', 'pdfium', 'pdfminer', 'pypdf'])
    args = parser.parse_args()
    report = diagnose(args.pdf, args.reference, args.output, args.engines, args.expected_count)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['allRequestedEnginesMatch'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
