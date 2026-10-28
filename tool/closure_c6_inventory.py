"""Lossless inventory of the actual C6 verdict, not the historical diagnostic.

Annotations are an evidence transport only. All printed findings must reconcile
with the report's category counts; missing/truncated chunks are a hard error.
Classification is deliberately NOT inferred from a successful job exit or an
extractor's cause hint. Every finding starts inconclusive until individually
reviewed against native glyphs, PDF paint and source geometry.
"""
import argparse
from bisect import bisect_right
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

TITLE = 'C6 geometry (PDF coordinates)'
ROW = re.compile(r'  ([A-Z][A-Z-]+) p(\d+) \[([^]]+)\]: (.*)')
REVIEW = {
    'BASELINE': 'Compare the actual native baseline and PDF glyph origin; do not widen the 1pt bound.',
    'BRACKET-COUNT': 'Locate every source bracket in native ink, PDF paint and logical extraction; BiDi is not an exemption.',
    'LINE-EXTRA': 'Identify this PDF line against the complete native page; rule out duplicate or displaced content.',
    'LINE-MISSING': 'Locate this source line in the PDF, including floating content and clipping.',
    'LINE-SHIFT': 'Compare physical line edges/centre on identical page geometry; inspect neighbouring text and wrapping.',
    'MATH-IMAGE': 'Inspect the original equation glyph ink, MathStyle, asset and placement on both surfaces; an image rectangle alone is insufficient.',
    'WORD-CONTENT': 'Compare source code points, actual native glyphs, PDF outlines and ToUnicode/ActualText; extraction mismatch alone does not establish the painted defect.',
    'WORD-MISSING': 'Locate this exact source token and interval in native ink and PDF paint/extraction; whitespace requires advance/spacing proof, not an automatic exclusion.',
}


def inventory(annotations):
    selected = [r for r in annotations if r.get('title') == TITLE]
    messages = [r['message'] for r in selected]
    # Checks API returns these same-path annotations newest first. notice()
    # splits at character 3000, INCLUDING inside a word/row. Reassemble before
    # parsing, keeping the original API chunk indices as evidence references.
    order = list(range(len(messages)))
    if messages and (messages[-1].startswith('baseline:') or messages[-1].startswith('violations:')) and 'verdict: WOULD FAIL' in messages[0]:
        order.reverse()
    ordered = [messages[i] for i in order]
    text = ''.join(ordered)
    lines = text.splitlines()
    summaries = [line for line in lines if line.startswith('violations: ')]
    if len(summaries) != 1 or not any('verdict: WOULD FAIL' in line for line in lines):
        raise ValueError('Expected one complete actual WOULD FAIL report')
    counts = dict((k, int(v)) for k, v in re.findall(r'([A-Z][A-Z-]+)=(\d+)', summaries[0]))
    ends, total = [], 0
    for message in ordered:
        total += len(message)
        ends.append(total)
    findings, offset = [], 0
    for full_line in text.splitlines(keepends=True):
        line = full_line.rstrip('\r\n')
        match = ROW.fullmatch(line)
        if match:
            category, page, source, detail = match.groups()
            if category not in REVIEW:
                raise ValueError(f'Unreviewed category {category}')
            start_chunk = bisect_right(ends, offset)
            end_chunk = bisect_right(ends, offset + len(line) - 1)
            local_offset = offset - (ends[start_chunk - 1] if start_chunk else 0)
            findings.append(dict(id=f'C6-{len(findings) + 1:03d}', check=category,
                page=int(page), source=source, result='WOULD FAIL', detail=detail,
                classification='inconclusive', explanation=REVIEW[category],
                evidence=dict(annotationChunk=order[start_chunk] + 1,
                    annotationChunksCovered=[order[i] + 1 for i in range(start_chunk, end_chunk + 1)],
                    messageLine=ordered[start_chunk][:local_offset].count('\n') + 1,
                    rowSha256=hashlib.sha256(line.encode()).hexdigest())))
        offset += len(full_line)
    if Counter(r['check'] for r in findings) != Counter(counts):
        raise ValueError('Missing/truncated/duplicate annotation chunks: counts do not reconcile')
    return dict(verdict='WOULD FAIL', counts=counts, findingCount=len(findings),
                findings=findings, sourceAnnotationMessages=messages,
                reassembledChunkOrder=[i + 1 for i in order],
                classificationPolicy='No job-exit inference; no exclusions, tolerance changes or presumed extractor exemptions.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--annotations', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.sha) or not args.run.isdigit():
        raise ValueError('Exact source SHA and numeric run required')
    raw = args.annotations.read_bytes()
    result = inventory(json.loads(raw))
    result.update(sourceSha=args.sha, sourceRun=args.run,
                  annotationsSha256=hashlib.sha256(raw).hexdigest(),
                  evidenceUrl=f'https://github.com/techtouchAI/Writing-questions/actions/runs/{args.run}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'{result["findingCount"]} individually retained; {result["verdict"]}; classification remains inconclusive')


if __name__ == '__main__':
    main()
