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

    #: How far outside a word box a glyph's centre may still belong to it.
    #: First and last glyphs are inset by their side bearing on the ink side,
    #: so a strict containment would call every word missing its edge glyph.
    assign_tol: float = 3.0

    #: How far apart two lines' baselines may be and still be *the same line*.
    #: This decides pairing only -- the acceptance bound is `baseline_pt`, which
    #: reports the distance once the pair is known. Floating headers and labels
    #: are placed by their own box, so a wider window here keeps a moved line a
    #: `BASELINE` finding instead of a confusing missing/extra pair.
    line_window_pt: float = 14.0

    #: Fraction of a word's letters that may differ between the two sides
    #: before it counts as different text. Shaping explains a dropped mark or a
    #: presentation-form substitution; it does not explain a substituted word.
    content_ratio: float = 0.34


# --------------------------------------------------------------- PDF reading
@dataclass
class PdfChar:
    """One extracted character: its ink box and its own baseline.

    Characters, not words. PyMuPDF's own tokenisation follows the extraction
    heuristics (and the writer emits whole words with no space bytes), so any
    word-level pairing here would fail for reasons that have nothing to do with
    the layout. The gate pairs *characters* with the Preview's word boxes, which
    is why Arabic clusters and ligatures cannot break it.
    """
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
    chars: list = field(default_factory=list)
    rules: list = field(default_factory=list)
    images: list = field(default_factory=list)


def _cluster_lines(chars, tol=0.5):
    """Group PDF characters into lines by baseline (y down, no sign flip)."""
    lines = []
    for char in sorted(chars, key=lambda c: (c.baseline, c.x0)):
        if lines and abs(char.baseline - lines[-1][0]) <= tol:
            lines[-1][1].append(char)
            lines[-1][0] = (lines[-1][0] * (len(lines[-1][1]) - 1) +
                            char.baseline) / len(lines[-1][1])
        else:
            lines.append([char.baseline, [char]])
    return [(baseline, sorted(group, key=lambda c: c.x0))
            for baseline, group in lines]


def read_pdf_pages(path):
    """Read a PDF into the small model above. The only PyMuPDF dependency."""
    import pymupdf  # imported here so the comparison core stays testable

    pages = []
    with pymupdf.open(path) as doc:
        for index, page in enumerate(doc):
            chars = []
            raw = page.get_text('rawdict')
            for block in raw.get('blocks', []):
                for line in block.get('lines', []):
                    for span in line.get('spans', []):
                        size = float(span.get('size', 0.0))
                        font = span.get('font', '')
                        baseline = float(span.get('origin', (0, 0))[1])
                        for char in span.get('chars', []):
                            text = char.get('c', '')
                            if not text or text.isspace():
                                continue
                            bbox = char.get('bbox') or (0, 0, 0, 0)
                            chars.append(PdfChar(text, float(bbox[0]),
                                                 float(bbox[2]), baseline, size,
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
                                 chars, rules, images))
    return pages


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


BRACKETS = '()\uff08\uff09'


def _bracket_sequence(chars):
    """Bracket characters in visual order (left to right)."""
    return ''.join(c.text for c in sorted(chars, key=lambda c: c.x0)
                   if c.text in BRACKETS)


def _bracket_text(text):
    return ''.join(ch for ch in text if ch in BRACKETS)


def _is_closer(text):
    return text in (')', '\uff09')


def _letters(text):
    """Letter identity, shaped-agnostic: NFKC, no marks, no spaces."""
    text = unicodedata.normalize('NFKC', text)
    return ''.join(ch for ch in text if unicodedata.category(ch)[0] in 'LN')


def _assign(preview_words, chars, tol):
    """Pair each PDF character with the Preview word box that owns it.

    Containment by the character's centre, expanded by `tol` for the ink inset
    of the first and last glyph. A character that fits no box is *outside* the
    layout's words -- which is what a moved or an extra glyph looks like from
    here -- and is reported, never dropped.
    """
    owned = [[] for _ in preview_words]
    outside = []
    for char in chars:
        centre = (char.x0 + char.x1) / 2
        best = None
        for index, word in enumerate(preview_words):
            if word.x0 - tol <= centre <= word.x1 + tol:
                distance = min(abs(centre - word.x0), abs(centre - word.x1))
                if best is None or distance < best[1]:
                    best = (index, distance)
        if best is None:
            outside.append(char)
        else:
            owned[best[0]].append(char)
    return owned, outside


def compare(preview, pages, bounds=None, max_report=40):
    """Return (violations, samples, coverage) for the whole document."""
    bounds = bounds or Bounds()
    samples = {name: [] for name in ('baseline', 'word_left', 'word_right',
                                     'size', 'math_rect', 'content')}
    violations = []
    coverage = {'pages': 0, 'lines': 0, 'words': 0, 'chars': 0,
                'rtl_lines': 0, 'bracket_lines': 0, 'math_runs': 0,
                'underlines': 0, 'skipped_math_only': 0}

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
        pairs, unmatched, extra = _match_lines(lines, _cluster_lines(page.chars),
                                               bounds.line_window_pt)
        for line, baseline, group in pairs:
            delta = abs(baseline - line.baseline)
            if line.words:
                coverage['lines'] += 1
                samples['baseline'].append(delta)
                if delta > bounds.baseline_pt:
                    violations.append(Violation(
                        page_index, 'BASELINE',
                        f'baseline moved {delta:.2f}pt: '
                        f'{_text_of(line)[:40]!r}', delta))
                _compare_line(page_index, line, group, page, bounds, samples,
                              violations, coverage)
            else:
                coverage['skipped_math_only'] += 1
                _check_math(page_index, line, group, page, bounds, samples,
                            violations, coverage)
                _check_underline(page_index, line, page, violations, coverage)
        for line in unmatched:
            violations.append(Violation(
                page_index, 'LINE-MISSING',
                f'no PDF line within {bounds.line_window_pt}pt of baseline '
                f'{line.baseline:.2f} with overlapping x: '
                f'{_text_of(line)[:40]!r}'))
        for baseline, group in extra:
            violations.append(Violation(
                page_index, 'LINE-EXTRA',
                f'PDF line with no Preview line at baseline {baseline:.2f}: '
                f'{"".join(c.text for c in group)[:40]!r}'))
    # A vacuous run must never read as a pass: no paired line means the tool
    # measured nothing, whatever it printed above.
    if coverage['lines'] == 0:
        violations.append(Violation(
            0, 'NO-LINES', 'no Preview line was paired with a PDF line; '
                           'the artifacts are empty or unreadable'))
    return violations, samples, coverage


def _text_of(line):
    return ''.join(word.text for word in line.words)


def _line_extent(line):
    if line.words:
        return (min(w.x0 for w in line.words), max(w.x1 for w in line.words))
    extents = [(float(r['xPt']), float(r['xPt']) + float(r.get('widthPt', 0)))
               for r in line.runs if r.get('xPt') is not None]
    if not extents:
        return (0.0, 0.0)
    return (min(e[0] for e in extents), max(e[1] for e in extents))


def _match_lines(lines, pdf_lines, window):
    """Pair Preview lines with PDF lines by baseline, then by x overlap.

    Baseline decides first (the nearest unused line inside `window`); when two
    candidates are equally close, the one whose x range actually overlaps the
    line wins. Pairing is deliberately more generous than acceptance: a line
    that moved should be reported as a moved line (`BASELINE`), not as one line
    lost and another invented.
    """
    used = set()
    pairs, unmatched = [], []
    for line in sorted(lines, key=lambda l: l.baseline):
        left, right = _line_extent(line)
        best = None
        for position, (baseline, group) in enumerate(pdf_lines):
            if position in used:
                continue
            delta = abs(baseline - line.baseline)
            if delta > window:
                continue
            g_left = min(c.x0 for c in group) if group else 0.0
            g_right = max(c.x1 for c in group) if group else 0.0
            overlap = max(0.0, min(right, g_right) - max(left, g_left))
            key = (delta, -overlap)
            if best is None or key < best[0]:
                best = (key, position, baseline, group)
        if best is None:
            unmatched.append(line)
        else:
            used.add(best[1])
            pairs.append((line, best[2], best[3]))
    extra = [(baseline, group) for position, (baseline, group)
             in enumerate(pdf_lines) if position not in used]
    return pairs, unmatched, extra


def _multiset_difference(left, right):
    '''How many entries of `right` are missing from `left` (both sorted).'''
    missing = 0
    index = 0
    for item in right:
        while index < len(left) and left[index] < item:
            index += 1
        if index < len(left) and left[index] == item:
            index += 1
        else:
            missing += 1
    return missing


def _compare_line(page_index, line, chars, page, bounds, samples, violations,
                  coverage):
    preview_words = sorted(line.words, key=lambda w: (w.x0, w.x1))
    owned, outside = _assign(preview_words, chars, bounds.assign_tol)
    coverage['words'] += len(preview_words)
    coverage['chars'] += len(chars)
    if line.words and line.words[0].rtl:
        coverage['rtl_lines'] += 1

    for word, mine in zip(preview_words, owned):
        if not mine:
            violations.append(Violation(
                page_index, 'WORD-MISSING',
                f'no glyphs inside {word.text[:24]!r} at '
                f'x={word.x0:.2f}..{word.x1:.2f} (deleted, moved away or '
                f'reordered)'))
            continue
        left = abs(min(c.x0 for c in mine) - word.x0)
        right = abs(max(c.x1 for c in mine) - word.x1)
        samples['word_left'].append(left)
        samples['word_right'].append(right)
        if left > bounds.word_edge_pt or right > bounds.word_edge_pt:
            violations.append(Violation(
                page_index, 'WORD-POSITION',
                f'{word.text[:24]!r} left d={left:.2f}pt right d={right:.2f}pt',
                max(left, right)))
        size = max(abs(c.size - word.size) for c in mine)
        samples['size'].append(size)
        if size > bounds.size_pt:
            violations.append(Violation(
                page_index, 'SIZE',
                f'{word.text[:24]!r} size {word.size:.2f} vs '
                f'{mine[0].size:.2f}pt', size))
        # Letters, not glyph shapes: shaping substitutes presentation forms and
        # can drop a mark, so the comparison is on letter multisets with a
        # measured allowance; substituting or reordering a word changes most of
        # its letters, which the allowance cannot absorb.
        mine_letters = sorted(_letters(''.join(c.text for c in mine)))
        want_letters = sorted(_letters(word.text))
        difference = _multiset_difference(mine_letters, want_letters)
        ratio = difference / max(1, len(want_letters))
        samples['content'].append(ratio)
        if ratio > bounds.content_ratio:
            violations.append(Violation(
                page_index, 'WORD-CONTENT',
                f'box {word.text[:24]!r} holds '
                f'{"".join(mine_letters)[:24]!r} ({ratio:.0%} different)',
                ratio))

    if outside:
        text = ''.join(c.text for c in sorted(outside, key=lambda c: c.x0))
        violations.append(Violation(
            page_index, 'WORD-EXTRA',
            f'{len(outside)} glyph(s) outside every Preview word box: '
            f'{text[:40]!r}'))

    # Brackets: same count on both sides by visual position, and -- on an RTL
    # line -- the leftmost bracket is a closer. The second half is the
    # mirroring property; this gate observes it, it never edits the text.
    pdf_brackets = _bracket_sequence(chars)
    preview_brackets = _bracket_text(''.join(w.text for w in preview_words))
    if pdf_brackets or preview_brackets:
        coverage['bracket_lines'] += 1
        if len(pdf_brackets) != len(preview_brackets):
            violations.append(Violation(
                page_index, 'BRACKET-COUNT',
                f'preview {preview_brackets!r} vs pdf {pdf_brackets!r}'))
        elif line.words[0].rtl and not _is_closer(pdf_brackets[0]):
            violations.append(Violation(
                page_index, 'BRACKET-ORDER',
                f'leftmost bracket of an RTL line is not a closer: '
                f'{pdf_brackets!r}'))

    _check_underline(page_index, line, page, violations, coverage)
    _check_math(page_index, line, chars, page, bounds, samples, violations,
                coverage)


def _check_underline(page_index, line, page, violations, coverage):
    if page is None:
        return
    for run in line.runs:
        if not run.get('underline'):
            continue
        coverage['underlines'] += 1
        if not [r for r in page.rules if abs(r.y - line.baseline) <= 6.0]:
            violations.append(Violation(
                page_index, 'UNDERLINE-MISSING',
                f'no rule near baseline {line.baseline:.2f} for '
                f'{run.get("text", "")[:24]!r}'))


def _check_math(page_index, line, chars, page, bounds, samples, violations,
                coverage):
    """A maths run is placed as an image *or* emitted as text -- both are legal.

    The exporter falls back to readable text when no snapshot host is mounted,
    so demanding an image would fail a correct document. What matters is that
    the run's box is filled on the page: glyphs inside it, or an image rect at
    it. Neither is a defect.
    """
    for run in line.runs:
        if not run.get('isMath'):
            continue
        coverage['math_runs'] += 1
        x = float(run['xPt'])
        width = float(run.get('widthPt', 0))
        inside = [c for c in chars if c.x0 >= x - 2 and c.x1 <= x + width + 2]
        if inside:
            left = abs(min(c.x0 for c in inside) - x)
            span = abs((max(c.x1 for c in inside) - x) - width)
            samples['math_rect'].append(max(left, span))
            if left > bounds.math_rect_pt or span > bounds.math_rect_pt:
                violations.append(Violation(
                    page_index, 'MATH-IMAGE',
                    f'maths text {run.get("text", "")[:20]!r} left '
                    f'd={left:.2f}pt width d={span:.2f}pt', max(left, span)))
            continue
        candidates = [img for img in page.images
                      if img.x0 < x + width and img.x1 > x]
        if not candidates:
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths run {run.get("text", "")[:20]!r} is neither text nor '
                f'an image at x={x:.2f}..{x + width:.2f}'))
            continue
        image = min(candidates, key=lambda i: abs(i.x0 - x))
        left = abs(image.x0 - x)
        span = abs((image.x1 - image.x0) - width)
        samples['math_rect'].append(max(left, span))
        if left > bounds.math_rect_pt or span > bounds.math_rect_pt:
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths image {run.get("text", "")[:20]!r} left d={left:.2f}pt '
                f'width d={span:.2f}pt', max(left, span)))


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
    'content': 'content_ratio',
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
    # The counts alone cannot be acted on: name the first few of each kind so
    # the next run says *which* line moved, not only that something did.
    for category in sorted(counts):
        shown = [v for v in violations if v.category == category][:4]
        for violation in shown:
            lines.append(f'  {category} p{violation.page}: {violation.detail}')
        if counts[category] > len(shown):
            lines.append(f'  {category} ... and {counts[category] - len(shown)} more')
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
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - the step must be able to say
        import traceback
        traceback.print_exc()
        print(f'::error title=C6 geometry::cannot measure: '
              f'{type(error).__name__}: {error}')
        sys.exit(2)
