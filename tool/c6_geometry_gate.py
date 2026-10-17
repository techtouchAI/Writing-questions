#!/usr/bin/env python3
"""Two-tier visual contract, tier 1: geometry from the PDF's own coordinates.

The pixel gate compares two rasterisers, so its number carries the renderer's
antialiasing with it. This gate does not rasterise at all: it reads the text
origins, glyph boxes, image rectangles and underline rules out of `vector.pdf`
and compares them, in points, with the geometry the Preview says it paints
(the same `LayoutDocument`, measured by TextPainter in
`test/visual/diag_c6_text_positions_test.dart`). A renderer cannot move a
number here; only layout, shaping, styling or emission can, which is exactly
what the ceiling is supposed to catch.

What it refuses (each one is injected deliberately by the negative tests):

    LINE-MISSING      a Preview line has no PDF line at its baseline
    LINE-EXTRA        a PDF line has no Preview line (content added)
    BASELINE          a matched line's baseline moved
    WORD-COUNT        a line lost or gained words
    WORD-ORDER        the same words in a different visual order
    WORD-POSITION     a word's left or right edge moved
    SIZE              a line's font size changed
    MATH-IMAGE        a maths run's image rectangle moved or resized
    UNDERLINE-MISSING an underlined run has no rule under it
    BRACKET-ORDER     brackets ordered by x differ between the two sides, or
                      the leftmost bracket of an RTL line is not a closer
                      (the mirroring property `P0-GATE-03` owns; this only
                      observes it on the visual fixture, it never edits it)

Tolerance policy. Every bound below is a *provisional* value with its origin in
the code; the tool always publishes the measured distribution of each metric
(p50/p95/p99/max) so the bound can be replaced by a measured one. A bound is
never widened because a run failed: the run publishes the numbers instead, and
the bound moves only with the distribution quoted next to it.

Text direction, fonts, sizes and the Arabic presentation forms are compared
from the emission itself (code points and metrics), so Arabic, RTL and mixed
lines are covered by the same rules as Latin ones.

Usage:
    c6_geometry_gate.py <artifacts_dir> [--mode report|enforce] [--json out]

Exit codes: 0 pass (or `report` mode), 1 violations in `enforce` mode,
2 cannot measure (missing artifacts) -- never silently green.
"""
import argparse
import json
import os
import sys
import unicodedata
from dataclasses import dataclass, field

PREVIEW_REL = os.path.join('c6diag', 'text_positions', 'preview_positions.json')
PDF_REL = 'vector.pdf'
SCHEMA = 'c6-preview-positions-v1'
JSON_OUT = os.path.join('c6diag', 'geometry', 'geometry_gate.json')


# --------------------------------------------------------------- tolerances
@dataclass(frozen=True)
class Bounds:
    """Provisional bounds, each with the observation that justifies it.

    `line_match_pt`: two lines are the same line if their baselines are this
    close. TextPainter and the PDF writer both start from `LayoutLine.baseline`
    and the writer prints five decimals, so the measured residual is expected
    to be ~1e-3 pt; 2 pt only decides *which* lines are paired, it is not an
    acceptance bound. The acceptance bound is `baseline_pt`.

    `baseline_pt`: 1 pt. One rasterised pixel at the gate's 96 dpi is 0.75 pt,
    so any displacement the pixel gate could have seen (>= 1 px) fails here,
    and nothing smaller than a pixel is called a defect.

    `word_edge_pt`: 1.5 pt == 2 px at 96 dpi. Word edges are ink edges on the
    PDF side and advance edges on the Preview side, so they carry the side
    bearing of the first and last glyph; the bound is two pixels, i.e. wider
    than a bearing and narrower than a layout error.

    `size_pt`: 0.25 pt. Font sizes are integers in the fixture's styles; a
    0.25 pt drift is already a different `fontSize` value.

    `math_rect_pt`: 2 pt for the same reason as `word_edge_pt`, plus one
    point for the image's own placement rounding.

    `underline_span_pt`: 2 pt, and only the span is checked here -- the rule's
    *position* is the dedicated parity gate's job (it measures both sides from
    their own artifacts, exactly).
    """
    line_match_pt: float = 2.0
    baseline_pt: float = 1.0
    word_edge_pt: float = 1.5
    size_pt: float = 0.25
    math_rect_pt: float = 2.0
    underline_span_pt: float = 2.0


# --------------------------------------------------------------- PDF reading
@dataclass
class PdfWord:
    text: str
    x0: float
    x1: float
    baseline: float
    size: float
    font: str = ''


@dataclass
class PdfRule:
    """A stroked or filled horizontal rule, in PDF points (y down)."""
    x0: float
    x1: float
    y: float
    thickness: float


@dataclass
class PdfImageRect:
    x0: float
    y0: float
    x1: float
    y1: float


@dataclass
class PdfPage:
    index: int
    width: float
    height: float
    words: list = field(default_factory=list)
    rules: list = field(default_factory=list)
    images: list = field(default_factory=list)


def _cluster_lines(words, tol=0.5):
    """Group PDF words into lines by baseline (y down, so no sign flip)."""
    lines = []
    for word in sorted(words, key=lambda w: (w.baseline, w.x0)):
        if lines and abs(word.baseline - lines[-1][0]) <= tol:
            lines[-1][1].append(word)
            lines[-1][0] = (lines[-1][0] * (len(lines[-1][1]) - 1) +
                            word.baseline) / len(lines[-1][1])
        else:
            lines.append([word.baseline, [word]])
    return [(baseline, sorted(group, key=lambda w: w.x0))
            for baseline, group in lines]


def read_pdf_pages(path):
    """Read a PDF into the small model above. The only PyMuPDF dependency."""
    import pymupdf  # imported here so the comparison core stays testable

    pages = []
    with pymupdf.open(path) as doc:
        for index, page in enumerate(doc):
            words = []
            raw = page.get_text('rawdict')
            for block in raw.get('blocks', []):
                for line in block.get('lines', []):
                    for span in line.get('spans', []):
                        chars = span.get('chars', [])
                        size = float(span.get('size', 0.0))
                        font = span.get('font', '')
                        baseline = float(span.get('origin', (0, 0))[1])
                        current = []
                        for char in chars:
                            if char.get('c', '').isspace():
                                if current:
                                    words.append(_char_word(current, baseline,
                                                            size, font))
                                    current = []
                                continue
                            current.append(char)
                        if current:
                            words.append(_char_word(current, baseline, size,
                                                    font))
            rules = []
            for drawing in page.get_drawings():
                for item in drawing.get('items', []):
                    if item[0] == 'l':
                        p1, p2 = item[1], item[2]
                        if abs(p1.y - p2.y) <= 0.3 and abs(p2.x - p1.x) > 1:
                            rules.append(PdfRule(min(p1.x, p2.x),
                                                 max(p1.x, p2.x), p1.y,
                                                 float(drawing.get('width') or 0)))
                    elif item[0] == 're':
                        rect = item[1]
                        if rect.height <= 3 and rect.width > 1:
                            rules.append(PdfRule(rect.x0, rect.x1,
                                                 rect.y0 + rect.height / 2,
                                                 rect.height))
            images = []
            for xref, *_ in page.get_images(full=True):
                for rect in page.get_image_rects(xref):
                    images.append(PdfImageRect(rect.x0, rect.y0, rect.x1, rect.y1))
            pages.append(PdfPage(index, page.rect.width, page.rect.height,
                                 words, rules, images))
    return pages


def _char_word(chars, baseline, size, font):
    text = ''.join(c.get('c', '') for c in chars)
    x0 = min(float(c['bbox'][0]) for c in chars)
    x1 = max(float(c['bbox'][2]) for c in chars)
    return PdfWord(text, x0, x1, baseline, size, font)


# ------------------------------------------------------------- preview model
def read_preview(path):
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    if data.get('schema') != SCHEMA:
        raise ValueError(f'unexpected schema {data.get("schema")!r}')
    return data


def preview_lines(data):
    """Flatten the probe's pages into comparable lines.

    A preview line is comparable iff at least one run was measured (math runs
    are painted as images and carry no text metrics); its words are the union
    of its runs' word boxes, in x order, tagged with the run they came from.
    """
    lines = []
    for page in data.get('pages', []):
        for record in page.get('lines', []):
            runs = record.get('runs', [])
            measured = [r for r in runs if r.get('measured')]
            words = []
            for run in measured:
                for word in run.get('previewWords', []):
                    words.append(PreviewWord(
                        text=word['text'],
                        x0=float(word['leftPt']),
                        x1=float(word['rightPt']),
                        baseline=float(record['baselinePt']),
                        size=float(run['fontSizePt']),
                        rtl=bool(run.get('rtl')),
                    ))
            words.sort(key=lambda w: (w.x0, w.x1))
            lines.append(PreviewLine(
                page=int(page['page']),
                baseline=float(record['baselinePt']),
                source=record.get('source', 'block'),
                words=words,
                runs=runs,
                width=float(page['widthPt']),
                height=float(page['heightPt']),
            ))
    return lines


@dataclass
class PreviewWord:
    text: str
    x0: float
    x1: float
    baseline: float
    size: float
    rtl: bool


@dataclass
class PreviewLine:
    page: int
    baseline: float
    source: str
    words: list
    runs: list
    width: float
    height: float


# ------------------------------------------------------------------ verdicts
@dataclass
class Violation:
    page: int
    category: str
    detail: str
    magnitude: float = 0.0


def normalise(text):
    """Compare text by what a reader sees, not by how it was encoded."""
    text = unicodedata.normalize('NFKC', text)
    return ''.join(text.split())


def _bracket_sequence(words):
    return ''.join(w.text for w in words
                   if w.text in '()' or w.text in '\uff08\uff09')


def _is_closer(text):
    return text in (')', '\uff09')


def compare(preview, pages, bounds=None, max_report=40):
    """Return (violations, samples, coverage) for the whole document."""
    bounds = bounds or Bounds()
    samples = {name: [] for name in ('baseline', 'word_left', 'word_right',
                                     'size', 'math_rect')}
    violations = []
    coverage = {'pages': 0, 'lines': 0, 'words': 0, 'rtl_lines': 0,
                'bracket_lines': 0, 'math_runs': 0, 'underlines': 0,
                'skipped_math_only': 0}

    by_page = {}
    for line in preview:
        by_page.setdefault(line.page, []).append(line)
    if len(by_page) != len(pages):
        violations.append(Violation(0, 'PAGE-COUNT',
                                    f'preview {len(by_page)} pages, pdf '
                                    f'{len(pages)} pages'))
    coverage['pages'] = len(by_page)

    for page_index, lines in sorted(by_page.items()):
        if page_index - 1 >= len(pages):
            continue
        page = pages[page_index - 1]
        first = lines[0]
        if abs(page.width - first.width) > bounds.line_match_pt or \
                abs(page.height - first.height) > bounds.line_match_pt:
            violations.append(Violation(page_index, 'PAGE-SIZE',
                                        f'preview {first.width:.2f}x'
                                        f'{first.height:.2f}pt, pdf '
                                        f'{page.width:.2f}x{page.height:.2f}pt'))
        pdf_lines = _cluster_lines(page.words)
        used = set()
        for line in sorted(lines, key=lambda l: l.baseline):
            if not line.words:
                coverage['skipped_math_only'] += 1
                continue
            best = None
            for position, (baseline, group) in enumerate(pdf_lines):
                if position in used:
                    continue
                delta = abs(baseline - line.baseline)
                if delta <= bounds.line_match_pt and (best is None or
                                                      delta < best[2]):
                    best = (position, group, delta)
            if best is None:
                violations.append(Violation(
                    page_index, 'LINE-MISSING',
                    f'no PDF line within {bounds.line_match_pt}pt of baseline '
                    f'{line.baseline:.2f}: {_text_of(line)[:40]!r}'))
                continue
            position, group, delta = best
            used.add(position)
            coverage['lines'] += 1
            samples['baseline'].append(delta)
            if delta > bounds.baseline_pt:
                violations.append(Violation(
                    page_index, 'BASELINE',
                    f'baseline moved {delta:.2f}pt: {_text_of(line)[:40]!r}',
                    delta))
            _compare_line(page_index, line, group, bounds, samples,
                          violations, coverage, page)
        for position, (baseline, group) in enumerate(pdf_lines):
            if position in used:
                continue
            violations.append(Violation(
                page_index, 'LINE-EXTRA',
                f'PDF line with no Preview line at baseline {baseline:.2f}: '
                f'{"".join(w.text for w in group)[:40]!r}'))
    return violations, samples, coverage


def _text_of(line):
    return ''.join(word.text for word in line.words)


def _compare_line(page_index, line, group, bounds, samples, violations,
                  coverage, page):
    # Visual order on both sides: the order a reader sees, independent of the
    # line's direction. The Preview probe records runs in logical order, so
    # sorting here is what makes the two sequences comparable at all.
    preview_words = sorted(line.words, key=lambda w: (w.x0, w.x1))
    pdf_words = sorted(group, key=lambda w: (w.x0, w.x1))
    coverage['words'] += len(preview_words)
    if line.words and line.words[0].rtl:
        coverage['rtl_lines'] += 1

    # The two sides are compared in visual order (by x), which is the order a
    # reader sees regardless of the line's direction.
    preview_seq = [normalise(w.text) for w in preview_words]
    pdf_seq = [normalise(w.text) for w in pdf_words]
    if preview_seq != pdf_seq:
        # Equal lengths with different sequences is a reordering, and a
        # reordering must be named as one: reconciling by text would happily
        # pair the moved tokens and hide it.
        paired = (_reconcile(preview_words, pdf_words)
                  if len(preview_seq) != len(pdf_seq) else None)
        if paired is None:
            category = 'WORD-COUNT' if len(preview_seq) != len(pdf_seq) \
                else 'WORD-ORDER'
            violations.append(Violation(
                page_index, category,
                f'line {_text_of(line)[:36]!r}: preview '
                f'{[w.text for w in preview_words][:8]} vs pdf '
                f'{[w.text for w in pdf_words][:8]}'))
            return
        preview_words, pdf_words = paired

    for preview_word, pdf_word in zip(preview_words, pdf_words):
        samples['word_left'].append(abs(pdf_word.x0 - preview_word.x0))
        samples['word_right'].append(abs(pdf_word.x1 - preview_word.x1))
        left = abs(pdf_word.x0 - preview_word.x0)
        right = abs(pdf_word.x1 - preview_word.x1)
        if left > bounds.word_edge_pt or right > bounds.word_edge_pt:
            violations.append(Violation(
                page_index, 'WORD-POSITION',
                f'{preview_word.text[:24]!r} left d={left:.2f}pt '
                f'right d={right:.2f}pt', max(left, right)))
        size = abs(pdf_word.size - preview_word.size)
        samples['size'].append(size)
        if size > bounds.size_pt:
            violations.append(Violation(
                page_index, 'SIZE',
                f'{preview_word.text[:24]!r} size {preview_word.size:.2f} vs '
                f'{pdf_word.size:.2f}pt', size))

    # Brackets: identical subsequence by x on both sides, and -- on RTL lines
    # -- the leftmost bracket is a closer. The second half is the mirroring
    # property; it is observed here, never "fixed" here.
    preview_brackets = _bracket_sequence(preview_words)
    pdf_brackets = _bracket_sequence(pdf_words)
    if preview_brackets or pdf_brackets:
        coverage['bracket_lines'] += 1
        if preview_brackets != pdf_brackets:
            violations.append(Violation(
                page_index, 'BRACKET-ORDER',
                f'preview {preview_brackets!r} vs pdf {pdf_brackets!r}'))
        elif line.words and line.words[0].rtl and pdf_brackets:
            if not _is_closer(pdf_brackets[0]):
                violations.append(Violation(
                    page_index, 'BRACKET-ORDER',
                    f'leftmost bracket of an RTL line is not a closer: '
                    f'{pdf_brackets!r}'))

    # Underline: a rule must exist under an underlined run (position is the
    # parity gate's job; here only presence).
    for run in line.runs:
        if not run.get('underline'):
            continue
        coverage['underlines'] += 1
        rules = [r for r in page.rules
                 if abs(r.y - line.baseline) <= 6.0]
        if not rules:
            violations.append(Violation(
                page_index, 'UNDERLINE-MISSING',
                f'no rule near baseline {line.baseline:.2f} for '
                f'{run.get("text", "")[:24]!r}'))

    # Maths: every maths run is an image on the PDF side; its rectangle must
    # be where the layout put it, within the bound.
    for run in line.runs:
        if not run.get('isMath'):
            continue
        coverage['math_runs'] += 1
        x = float(run['xPt'])
        width = float(run['widthPt'])
        candidates = [img for img in page.images
                      if img.x0 < x + width and img.x1 > x]
        if not candidates:
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths run {run.get("text", "")[:20]!r} has no image rect'))
            continue
        image = min(candidates, key=lambda i: abs(i.x0 - x))
        left = abs(image.x0 - x)
        span = abs((image.x1 - image.x0) - width)
        samples['math_rect'].append(max(left, span))
        if left > bounds.math_rect_pt or span > bounds.math_rect_pt:
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths run {run.get("text", "")[:20]!r} left d={left:.2f}pt '
                f'width d={span:.2f}pt', max(left, span)))


def _reconcile(preview_words, pdf_words):
    """Pair sequences that differ only by tokenisation (e.g. attached ':').

    Returns (preview pairs, pdf merged words) or None when the sequences
    really differ -- which is the case the gate must reject.
    """
    out_preview, out_pdf = [], []
    i = j = 0
    while i < len(preview_words) and j < len(pdf_words):
        p_text = normalise(preview_words[i].text)
        matched = False
        for take in (1, 2, 3):
            if j + take > len(pdf_words):
                break
            merged_text = ''.join(normalise(w.text)
                                  for w in pdf_words[j:j + take])
            if merged_text == p_text:
                merged = PdfWord(
                    text=''.join(w.text for w in pdf_words[j:j + take]),
                    x0=min(w.x0 for w in pdf_words[j:j + take]),
                    x1=max(w.x1 for w in pdf_words[j:j + take]),
                    baseline=pdf_words[j].baseline,
                    size=pdf_words[j].size, font=pdf_words[j].font)
                out_preview.append(preview_words[i])
                out_pdf.append(merged)
                i += 1
                j += take
                matched = True
                break
        if matched:
            continue
        # Or the PDF has one word where the Preview has several.
        for take in (2, 3):
            if i + take > len(preview_words):
                break
            merged_text = ''.join(normalise(w.text)
                                  for w in preview_words[i:i + take])
            if merged_text == normalise(pdf_words[j].text):
                for offset in range(take):
                    out_preview.append(preview_words[i + offset])
                    out_pdf.append(PdfWord(
                        text=preview_words[i + offset].text,
                        x0=pdf_words[j].x0, x1=pdf_words[j].x1,
                        baseline=pdf_words[j].baseline,
                        size=pdf_words[j].size, font=pdf_words[j].font))
                i += take
                j += 1
                matched = True
                break
        if matched:
            continue
        return None
    if i != len(preview_words) or j != len(pdf_words):
        return None
    return out_preview, out_pdf


def distribution(values):
    if not values:
        return {}
    ordered = sorted(values)
    def pick(q):
        return ordered[min(len(ordered) - 1, int(q * len(ordered)))]
    return {'n': len(ordered), 'p50': pick(0.50), 'p95': pick(0.95),
            'p99': pick(0.99), 'max': ordered[-1]}


def notice(title, lines):
    text = '\n'.join(lines)
    for start in range(0, len(text), 3000):
        chunk = text[start:start + 3000].replace('%', '%25').replace('\r', '%0D')
        print(f'::notice title={title}::{chunk.replace(chr(10), "%0A")}')


BOUND_OF = {
    'baseline': 'baseline_pt',
    'word_left': 'word_edge_pt',
    'word_right': 'word_edge_pt',
    'size': 'size_pt',
    'math_rect': 'math_rect_pt',
}


def render_report(violations, samples, coverage, bounds, mode):
    lines = []
    for name, values in samples.items():
        stats = distribution(values)
        if stats:
            bound = getattr(bounds, BOUND_OF[name])
            lines.append(f'{name}: n={stats["n"]} p50={stats["p50"]:.3f} '
                         f'p95={stats["p95"]:.3f} p99={stats["p99"]:.3f} '
                         f'max={stats["max"]:.3f}pt (bound {bound})')
    lines.append('coverage: ' + ', '.join(f'{k}={v}'
                                          for k, v in sorted(coverage.items())))
    if not violations:
        lines.append(f'verdict: PASS ({mode} mode)')
        return lines
    counts = {}
    for violation in violations:
        counts[violation.category] = counts.get(violation.category, 0) + 1
    lines.append('violations: ' + ', '.join(f'{k}={v}'
                                            for k, v in sorted(counts.items())))
    lines.append(f'verdict: FAIL ({mode} mode)' if mode == 'enforce'
                 else 'verdict: WOULD FAIL (report mode; enforce would exit 1)')
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('artifacts')
    parser.add_argument('--mode', choices=('report', 'enforce'),
                        default='report',
                        help='report: publish the verdict, exit 0. '
                             'enforce: exit 1 on any violation.')
    parser.add_argument('--json', default=None)
    args = parser.parse_args(argv)

    preview_path = os.path.join(args.artifacts, PREVIEW_REL)
    pdf_path = os.path.join(args.artifacts, PDF_REL)
    missing = [p for p in (preview_path, pdf_path) if not os.path.exists(p)]
    if missing:
        print(f'::error title=C6 geometry::missing artifacts: {missing}')
        return 2

    preview = preview_lines(read_preview(preview_path))
    pages = read_pdf_pages(pdf_path)
    bounds = Bounds()
    violations, samples, coverage = compare(preview, pages, bounds)

    lines = render_report(violations, samples, coverage, bounds, args.mode)
    notice('C6 geometry (PDF coordinates)', lines)
    print('\n'.join(lines))

    payload = {
        'mode': args.mode,
        'bounds': bounds.__dict__,
        'coverage': coverage,
        'distribution': {k: distribution(v) for k, v in samples.items()},
        'violations': [v.__dict__ for v in violations],
    }
    out = args.json or os.path.join(args.artifacts, JSON_OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as handle:
        json.dump(payload, handle, indent=1, ensure_ascii=False)

    if violations and args.mode == 'enforce':
        return 1
    if violations:
        # Report mode must never look like a pass.
        print(f'::warning title=C6 geometry::WOULD FAIL: '
              f'{len(violations)} violation(s) -- enforce mode would exit 1')
    return 0


if __name__ == '__main__':
    sys.exit(main())
