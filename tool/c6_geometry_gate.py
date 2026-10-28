#!/usr/bin/env python3
"""Two-tier visual contract, tier 1: geometry from the PDF's own coordinates.

The pixel gate compares two rasterisers, so its number carries the renderer's
antialiasing with it. This gate does not rasterise at all: it reads the text
origins, glyph boxes, image rectangles and underline rules out of `vector.pdf`
and compares them, in points, with the geometry the Preview says it paints
(the same `LayoutDocument`, measured by TextPainter in
`test/visual/visual_parity_fixture_test.dart` (the standalone reconstructed
probe is retained separately, never substituted for this live-plan evidence)). A renderer cannot move a
number here; only layout, shaping, styling or emission can, which is exactly
what the ceiling is supposed to catch.

The comparison uses the intervals the writer was given (`layoutWords`: visual
left plus the word's own advance) and the PDF glyph origin, not the tight ink
box. A tight-box disagreement that the caret comparison does not repeat is
published as a diagnostic with cause `extraction`. It is not the verdict.
`--mode enforce` exists and is tested, and is not the CI mode.

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
import hashlib
from pathlib import Path
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

    `word_edge_pt`: 6.5 pt, from the measured distribution, not from taste.
    Two independent shapers (Skia/HarfBuzz for the Preview, the vendored shaper
    for the PDF) produce slightly different word advances; the writer closes
    each word with a trailing TJ onto the canonical advance, so edges agree at
    the median (measured p50 = 0.000 pt) and drift by a few points at the tail
    (p95 = 3.77, p99 = 6.15, max = 11.58 on the fixture). A bound below p99
    would name the shapers' disagreement as a defect; 6.5 pt sits just above
    p99 and still catches the defects this tier exists for (a 4 px underline
    displacement is caught by its own gate at 3 pt, a moved word by 8.7 px and
    up here). When the distribution changes, this number changes with it -- and
    the change is quoted in the same commit.

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
    word_edge_pt: float = 6.5
    size_pt: float = 0.25
    math_rect_pt: float = 2.0
    underline_span_pt: float = 2.0

    #: How far outside a word box a glyph's centre may still belong to it. It
    #: must be at least the measured edge disagreement (`word_edge_pt`), or a
    #: two-point-wide word such as ':' is orphaned by the same shaper drift
    #: that wide words absorb -- which is exactly what happened: 92 words
    #: "missing" were punctuation boxes a few points away from their glyphs.
    assign_tol: float = 6.5

    #: How far apart two lines' baselines may be and still be *the same line*.
    #: This decides pairing only -- the acceptance bound is `baseline_pt`, which
    #: reports the distance once the pair is known.
    line_window_pt: float = 14.0

    #: The same window for lines that come from a float (header, basmala, text
    #: box). The PDF lays those out inside a padded `Positioned` box with
    #: `pw.Text` while the Preview paints their label lines at absolute
    #: baselines, so their displacement is larger by construction; the wider
    #: window makes them one `BASELINE(FLOAT)` finding instead of a
    #: missing/extra pair. It does not excuse the displacement.
    float_window_pt: float = 28.0

    #: How far a line's outer ink edges may sit from the Preview's line extent.
    #: Per-word edges carry each glyph's side bearing, so they need the wide
    #: bound above; the *line's* two outer edges are what a whole-line shift
    #: moves. Measured on the fixture: p95 = 2.81, p99 = 3.49, max = 3.49 pt --
    #: the bearing of the line's first and last glyph -- so 4.0 sits just above
    #: the measurement and still catches a displacement of half a line.
    line_center_pt: float = 2.0
    line_edge_pt: float = 4.0

    #: Fraction of a word's letters that may differ between the two sides
    #: before it counts as different text, from the measured distribution
    #: (p95 = 0.167, p99 = 0.333). Shaping explains a dropped mark or a
    #: presentation-form substitution; it does not explain a substituted word,
    #: which changes most of its letters.
    content_ratio: float = 0.40


# --------------------------------------------------------------- PDF reading
@dataclass
class PdfChar:
    """One extracted character: its ink box, its baseline, and its origin.

    Characters, not words. PyMuPDF's own tokenisation follows the extraction
    heuristics (and the writer emits whole words with no space bytes), so any
    word-level pairing here would fail for reasons that have nothing to do with
    the layout. The gate pairs *characters* with the Preview's word boxes, which
    is why Arabic clusters and ligatures cannot break it.

    `origin_x` is the PDF text origin (the point the writer placed), not the
    centre of the ink box. Italic shear and side bearings move the ink without
    moving the origin. None means the caller did not supply one; assignment
    then falls back to the ink centre, which is what the synthetic tests use.
    """
    text: str
    x0: float
    x1: float
    baseline: float
    size: float
    font: str = ''
    origin_x: float | None = None


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


def _cluster_lines(chars, tol=0.5, gap=40.0):
    """Group PDF characters into lines by baseline *and* horizontal reach.

    Baseline alone is not enough: a header, a page number and a table cell can
    share a baseline while sitting hundreds of points apart, and merging them
    into one "line" makes every word of it look missing (measured: a single
    cluster spanning 352 pt beyond its Preview line). `gap` is the largest gap
    inside one line -- wider than a word space, narrower than any two
    independent pieces of page furniture.
    """
    def by_baseline():
        rows = []
        for char in sorted(chars, key=lambda c: (c.baseline, c.x0)):
            if rows and abs(char.baseline - rows[-1][0]) <= tol:
                rows[-1][1].append(char)
                rows[-1][0] = (rows[-1][0] * (len(rows[-1][1]) - 1) +
                               char.baseline) / len(rows[-1][1])
            else:
                rows.append([char.baseline, [char]])
        return rows

    lines = []
    for baseline, group in by_baseline():
        group.sort(key=lambda c: c.x0)
        run = [group[0]]
        for char in group[1:]:
            if char.x0 - run[-1].x1 > gap:
                lines.append((baseline, run))
                run = [char]
            else:
                run.append(char)
        lines.append((baseline, run))
    return lines


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
                            origin = char.get('origin')
                            origin_x = float(origin[0]) if origin else None
                            chars.append(PdfChar(text, float(bbox[0]),
                                                 float(bbox[2]), baseline, size,
                                                 font, origin_x))
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


def bind_rendered_source(data, root):
    """Bind files emitted by the live-plan fixture, never a re-resolved plan.

    The fixture asserts in-memory LayoutDocument identity for PNG/PDF/positions.
    This post-fixture binding adds file digests, not a claim that a digest alone
    proves in-memory identity. It must not be used to refresh stale evidence.
    """
    root = Path(root)
    provenance = data.get('provenance', {})
    if provenance.get('kind') != 'rendered-canonical-preview-plan':
        raise ValueError('C6 positions did not come from the actual rendered preview plan')
    if 'artifactSha256' in provenance:
        raise ValueError('C6 evidence is already bound; refusing to refresh its identity')
    expected = {'vector.pdf', *(f'preview_page_{i+1}.png' for i in range(len(data['pages'])))}
    lengths = data.get('artifactByteLengths', {})
    if set(lengths) != expected or not data['pages']:
        raise ValueError('C6 fixture must account for PDF and every captured preview page')
    hashes = {}
    for name in sorted(expected):
        raw = (root / name).read_bytes()
        if len(raw) != lengths[name]:
            raise ValueError(f'C6 fixture byte identity mismatch: {name}')
        hashes[name] = hashlib.sha256(raw).hexdigest()
    provenance['artifactSha256'] = hashes
    provenance['binding'] = 'CI post-fixture hashes; in-memory plan identity asserted by fixture'


def validate_rendered_source(data, root):
    provenance = data.get('provenance', {})
    if provenance.get('kind') != 'rendered-canonical-preview-plan':
        raise ValueError('C6 positions did not come from the actual rendered preview plan')
    expected = {'vector.pdf', *(f'preview_page_{i+1}.png' for i in range(len(data['pages'])))}
    hashes = provenance.get('artifactSha256', {})
    if set(hashes) != expected or not data['pages']:
        raise ValueError('C6 source inventory is missing a PDF/preview identity')
    for name in sorted(expected):
        if hashlib.sha256((Path(root) / name).read_bytes()).hexdigest() != hashes[name]:
            raise ValueError(f'C6 source checksum mismatch: {name}')


def _tight_words(run, baseline):
    words = []
    for word in run.get('previewWords') or []:
        words.append(PreviewWord(
            text=word['text'],
            x0=float(word['leftPt']),
            x1=float(word['rightPt']),
            baseline=baseline,
            size=float(run['fontSizePt']),
            rtl=bool(run.get('rtl')),
        ))
    return words


def _caret_words(run, baseline):
    """Caret intervals the PDF emitter actually positions.

    `LayoutWord.x` is the visual left edge and `textAdvance` is the shaped
    width the writer executes. Tight `getBoxesForSelection` boxes omit side
    bearings and shear with the ink; they are not the emission contract.
    """
    words = []
    for word in run.get('layoutWords') or []:
        x = float(word['xPt'])
        width = float(word.get('textAdvancePt') or 0.0)
        if width <= 0:
            width = abs(float(word.get('advancePt') or 0.0))
        words.append(PreviewWord(
            text=word.get('text') or '',
            x0=x,
            x1=x + width,
            baseline=baseline,
            size=float(run.get('fontSizePt') or 0.0),
            rtl=bool(run.get('rtl')),
        ))
    return words


def preview_lines(data, boxes='caret'):
    """Flatten the probe's pages into comparable lines.

    A preview line is comparable iff at least one run was measured (math runs
    are painted as images and carry no text metrics); its words are the union
    of its runs' word boxes, in x order, tagged with the run they came from.

    `boxes='caret'` uses the layout word intervals the PDF writer positions,
    and falls back to tight ink boxes only when a run has no layout words.
    `boxes='tight'` is the historical comparison (ink boxes). It is still
    reported, so a mismatch that exists only there is an extraction finding,
    not a silent pass.
    """
    if boxes not in ('caret', 'tight'):
        raise ValueError(f'unknown box source {boxes!r}')
    lines = []
    for page in data.get('pages', []):
        for record in page.get('lines', []):
            runs = record.get('runs', [])
            measured = [r for r in runs if r.get('measured')]
            baseline = float(record['baselinePt'])
            words = []
            source = boxes
            for run in measured:
                if boxes == 'caret':
                    chosen = _caret_words(run, baseline)
                    # A zero-width interval cannot hold an origin. An artifact
                    # that predates textAdvancePt must not be judged against it.
                    if not chosen or any(word.x1 <= word.x0 for word in chosen):
                        chosen = _tight_words(run, baseline)
                        if chosen:
                            source = 'tight-fallback'
                else:
                    chosen = _tight_words(run, baseline)
                words.extend(chosen)
            words.sort(key=lambda w: (w.x0, w.x1))
            lines.append(PreviewLine(
                page=int(page['page']),
                baseline=baseline,
                source=record.get('source', 'block'),
                words=words,
                runs=runs,
                width=float(page['widthPt']),
                height=float(page['heightPt']),
                box_source=source,
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

    @property
    def width(self):
        return self.x1 - self.x0


@dataclass
class PreviewLine:
    page: int
    baseline: float
    source: str
    words: list
    runs: list
    width: float
    height: float
    box_source: str = 'given'


# ------------------------------------------------------------------ verdicts
@dataclass
class Violation:
    page: int
    category: str
    detail: str
    magnitude: float = 0.0
    source: str = 'block'   # 'block' or 'float': different PDF code paths
    word: str = ''
    cause: str = ''         # filled by classify_causes; empty until then


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


def _anchor(char, kind='origin'):
    """The point that decides which word a glyph belongs to.

    The writer places an origin. The ink box centre moves with shear and with
    side bearings, so it is the wrong point once an origin is known: a narrow
    neighbour such as '/' or a tight ink box can contain the centre while the
    origin still sits in the word that was emitted. `kind='centre'` is the
    historical comparison only, kept so that list can still be named.
    """
    if kind == 'centre' or char.origin_x is None:
        return (char.x0 + char.x1) / 2
    return char.origin_x


def _assign(preview_words, chars, tol, anchor_kind='origin'):
    """Pair each PDF character with the Preview word box nearest to its anchor.

    Nearest, not first-containing: word boxes are adjacent, so a glyph a few
    points off (the shapers disagree by up to 6 pt at p99) can sit inside its
    neighbour's box, and a narrow box such as '/' would otherwise absorb the
    glyphs of the word after it. Ties go to the narrower box, which is the more
    specific claim. A character farther than `tol` from every box is *outside*
    the layout's words -- what a moved or an extra glyph looks like from here --
    and is reported, never dropped.
    """
    owned = [[] for _ in preview_words]
    outside = []
    for char in chars:
        anchor = _anchor(char, anchor_kind)
        best = None
        for index, word in enumerate(preview_words):
            if word.x0 <= anchor <= word.x1:
                distance = 0.0
            else:
                distance = min(abs(anchor - word.x0), abs(anchor - word.x1))
            key = (distance, word.x1 - word.x0)
            if best is None or key < best[0]:
                best = (key, index)
        if best is None or best[0][0] > tol:
            outside.append(char)
        else:
            owned[best[1]].append(char)
    return owned, outside


def compare(preview, pages, bounds=None, max_report=40, edges='ink',
            anchor='origin'):
    """Return (violations, samples, coverage) for the whole document."""
    bounds = bounds or Bounds()
    samples = {name: [] for name in ('baseline', 'word_left', 'word_right',
                                     'size', 'math_rect', 'content',
                                     'line_edge', 'line_center')}
    violations = []
    coverage = {'pages': 0, 'lines': 0, 'words': 0, 'chars': 0,
                'rtl_lines': 0, 'bracket_lines': 0, 'math_runs': 0,
                'underlines': 0, 'skipped_math_only': 0, 'math_only_lines': 0}

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
        # An image-only formula has no PDF text baseline to pair. Verify its
        # typed math paint directly; do not drop it or pretend LINE-MISSING is
        # intended. A missing/moved/resized image still fails MATH-IMAGE.
        math_only = [line for line in lines if not line.words and
                     any(run.get('isMath') for run in line.runs)]
        text_lines = [line for line in lines if line not in math_only]
        fallback_chars = set()
        for line in math_only:
            coverage['math_only_lines'] += 1
            near = [c for c in page.chars if abs(c.baseline - line.baseline) <= bounds.line_window_pt]
            start = len(violations)
            _check_math(page_index, line, near, page, bounds, samples, violations, coverage)
            _check_underline(page_index, line, page, violations, coverage)
            _tag(violations, line.source, start)
            for run in line.runs:
                if not run.get('isMath') or run.get('renderMode') == 'image':
                    continue
                x, width = float(run['xPt']), float(run.get('widthPt', 0))
                fallback_chars.update(id(c) for c in near if c.x0 >= x - 2 and c.x1 <= x + width + 2)
        pairs, unmatched, extra = _match_lines(
            text_lines, _cluster_lines([c for c in page.chars if id(c) not in fallback_chars]),
            bounds.line_window_pt, bounds.float_window_pt)
        for line, baseline, group in pairs:
            delta = abs(baseline - line.baseline)
            if line.words:
                coverage['lines'] += 1
                samples['baseline'].append(delta)
                if delta > bounds.baseline_pt:
                    violations.append(Violation(
                        page_index, 'BASELINE',
                        f'baseline moved {delta:.2f}pt: '
                        f'{_text_of(line)[:40]!r}', delta, line.source))
                _compare_line(page_index, line, group, page, bounds, samples,
                              violations, coverage, edges=edges, anchor=anchor)
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
                f'{_text_of(line)[:40]!r}', 0.0, line.source))
        for baseline, group in extra:
            violations.append(Violation(
                page_index, 'LINE-EXTRA',
                f'PDF line with no Preview line at baseline {baseline:.2f}: '
                f'{"".join(c.text for c in group)[:40]!r}'))
    # A vacuous run must never read as a pass: no paired line means the tool
    # measured nothing, whatever it printed above.
    if coverage['lines'] == 0 and coverage['math_only_lines'] == 0:
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


def _match_lines(lines, pdf_lines, window, float_window=None):
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
        limit = (float_window if (float_window and line.source == 'float')
                 else window)
        best = None
        for position, (baseline, group) in enumerate(pdf_lines):
            if position in used:
                continue
            delta = abs(baseline - line.baseline)
            if delta > limit:
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
                  coverage, edges='ink', anchor='origin'):
    source = line.source
    preview_words = sorted(line.words, key=lambda w: (w.x0, w.x1))
    first = len(violations)
    # A whole-line displacement, measured on the outer ink edges: the per-word
    # bound is wide enough to absorb shaper drift, so the line's two ends are
    # checked on their own.
    if chars:
        line_left = abs(min(c.x0 for c in chars) - preview_words[0].x0)
        line_right = abs(max(c.x1 for c in chars) - preview_words[-1].x1)
        samples['line_edge'].append(max(line_left, line_right))
        centre = abs((min(c.x0 for c in chars) + max(c.x1 for c in chars)) / 2
                     - (preview_words[0].x0 + preview_words[-1].x1) / 2)
        samples['line_center'].append(centre)
        if centre > bounds.line_center_pt:
            violations.append(Violation(
                page_index, 'LINE-SHIFT',
                f'line centre moved {centre:.2f}pt', centre, line.source,
                word=_text_of(line)[:24]))
        if max(line_left, line_right) > bounds.line_edge_pt:
            violations.append(Violation(
                page_index, 'LINE-SHIFT',
                f'line edges moved left d={line_left:.2f}pt '
                f'right d={line_right:.2f}pt', max(line_left, line_right),
                line.source, word=_text_of(line)[:24]))

    # Glyphs inside a maths run's box belong to that run: the Preview paints
    # the formula (as an image or as readable text), it does not claim to have
    # those characters as words, so they are neither missing nor extra here --
    # the maths check measures that box on its own.
    math_regions = [(float(run['xPt']),
                     float(run['xPt']) + float(run.get('widthPt', 0)))
                    for run in line.runs if run.get('isMath')]

    def in_math(char):
        centre = (char.x0 + char.x1) / 2
        return any(start - 1 <= centre <= end + 1 for start, end in math_regions)

    owned, outside = _assign(preview_words, chars, bounds.assign_tol, anchor)
    outside = [c for c in outside if not in_math(c)]
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
                f'reordered)',
                word=word.text[:24]))
            continue
        left = abs(min(c.x0 for c in mine) - word.x0)
        right = abs(max(c.x1 for c in mine) - word.x1)
        samples['word_left'].append(left)
        samples['word_right'].append(right)
        # Ink edges are not the emission contract. The writer places an origin
        # inside [x, x + textAdvance]; the ink box is inset by side bearings
        # and the trailing TJ correction closes the cursor, not the ink. An
        # inset of ~7 pt with the origin still inside the interval is a
        # representation difference. A position finding is an origin outside
        # that interval. The ink deltas stay in the distribution either way.
        if edges == 'origin':
            outside_pt = 0.0
            for char in mine:
                point = _anchor(char, 'origin')
                if point < word.x0:
                    outside_pt = max(outside_pt, word.x0 - point)
                elif point > word.x1:
                    outside_pt = max(outside_pt, point - word.x1)
            if outside_pt > bounds.word_edge_pt:
                violations.append(Violation(
                    page_index, 'WORD-POSITION',
                    f'{word.text[:24]!r} origin outside the interval by '
                    f'{outside_pt:.2f}pt (ink left d={left:.2f}pt '
                    f'right d={right:.2f}pt)',
                    outside_pt, word=word.text[:24]))
        elif left > bounds.word_edge_pt or right > bounds.word_edge_pt:
            violations.append(Violation(
                page_index, 'WORD-POSITION',
                f'{word.text[:24]!r} left d={left:.2f}pt right d={right:.2f}pt',
                max(left, right), word=word.text[:24]))
        size = max(abs(c.size - word.size) for c in mine)
        samples['size'].append(size)
        if size > bounds.size_pt:
            violations.append(Violation(
                page_index, 'SIZE',
                f'{word.text[:24]!r} size {word.size:.2f} vs '
                f'{mine[0].size:.2f}pt', size, word=word.text[:24]))
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
                ratio, word=word.text[:24]))

    if outside:
        text = ''.join(c.text for c in sorted(outside, key=lambda c: c.x0))
        violations.append(Violation(
            page_index, 'WORD-EXTRA',
            f'{len(outside)} glyph(s) outside every Preview word box: '
            f'{text[:40]!r}'))

    # Brackets: same count on both sides by visual position, and -- on an RTL
    # line -- the leftmost bracket is a closer. The second half is the
    # mirroring property; this gate observes it, it never edits the text.
    pdf_brackets = _bracket_sequence([c for c in chars if not in_math(c)])
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
    _tag(violations, source, first)


def _tag(violations, source, start):
    for violation in violations[start:]:
        if not violation.source or violation.source == 'block':
            violation.source = source


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
        if inside and run.get('renderMode') != 'image':
            # Text fallback: the emitted string is a readable rendering of the
            # formula, so its natural width is not the layout box's width. Only
            # the placement is comparable; the image path checks both.
            left = abs(min(c.x0 for c in inside) - x)
            samples['math_rect'].append(left)
            if left > bounds.math_rect_pt:
                violations.append(Violation(
                    page_index, 'MATH-IMAGE',
                    f'maths text {run.get("text", "")[:20]!r} left '
                    f'd={left:.2f}pt', left))
            continue
        height = float(run.get('heightPt', 0))
        top = (line.baseline - float(run['layoutBaselineOffsetPt'])
               if 'layoutBaselineOffsetPt' in run else None)
        candidates = list(page.images)
        if not candidates:
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths run {run.get("text", "")[:20]!r} is neither text nor '
                f'an image at x={x:.2f}..{x + width:.2f}'))
            continue
        def deltas(image):
            result = [abs(image.x0 - x), abs((image.x1 - image.x0) - width)]
            if top is not None:
                result.extend([abs(image.y0 - top), abs((image.y1 - image.y0) - height)])
            return result
        image = min(candidates, key=lambda candidate: max(deltas(candidate)))
        differences = deltas(image)
        samples['math_rect'].append(max(differences))
        if max(differences) > bounds.math_rect_pt:
            vertical = (f' top d={differences[2]:.2f}pt height d={differences[3]:.2f}pt'
                        if top is not None else '')
            violations.append(Violation(
                page_index, 'MATH-IMAGE',
                f'maths image {run.get("text", "")[:20]!r} left d={differences[0]:.2f}pt '
                f'width d={differences[1]:.2f}pt' + vertical, max(differences)))


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
    'line_edge': 'line_edge_pt',
    'line_center': 'line_center_pt',
}


def _page_chars(pages, page_index):
    if page_index < 1 or page_index > len(pages):
        return []
    return pages[page_index - 1].chars


def _letters_present(want, have):
    """True when every letter of `want` occurs in `have` at least as often."""
    return _multiset_difference(sorted(want), sorted(have)) == 0 and bool(want)


def classify_causes(violations, preview, pages):
    """Label each violation. Does not add or remove any.

    Labels, and only these:
      letters-absent-from-extract
                       the extracted text does not contain the word. This is
                       not proof the ink is absent: a font can draw a glyph
                       whose ToUnicode is empty. It is also what a real
                       deletion looks like, so the category stays WORD-MISSING.
      origin-outside-interval
                       an extracted origin is outside the caret interval by
                       more than the bound. Not yet a proven paint bug.
      representation   same letters, different split or ink-versus-advance
      extraction       the letters were extracted, and a different rectangle
                       is what disagreed
      unresolved       the evidence does not decide
    """
    by_page_words = {}
    for line in preview:
        by_page_words.setdefault(line.page, []).extend(line.words)

    for violation in violations:
        if violation.cause:
            continue
        word = violation.word
        if violation.category not in (
                'WORD-MISSING', 'WORD-CONTENT', 'WORD-POSITION'):
            continue
        if not word:
            violation.cause = 'unresolved'
            continue
        chars = _page_chars(pages, violation.page)
        want = _letters(word)
        have = _letters(''.join(c.text for c in chars))
        if violation.category == 'WORD-POSITION':
            # Glyphs were assigned, so something was emitted. Missing letters
            # in the extract do not make that a content defect.
            violation.cause = ('origin-outside-interval'
                               if 'origin outside' in violation.detail
                               else 'representation')
            continue
        if want and not _letters_present(want, have):
            violation.cause = 'letters-absent-from-extract'
            continue
        boxes = [w for w in by_page_words.get(violation.page, [])
                 if w.text == word]
        origins = [c for c in chars if set(_letters(c.text)) & set(want)]
        if not boxes or not origins:
            violation.cause = 'unresolved'
            continue
        nearest = min(min(abs(_anchor(c) - b.x0), abs(_anchor(c) - b.x1),
                          0.0 if b.x0 <= _anchor(c) <= b.x1 else 1e9)
                      for c in origins for b in boxes)
        if nearest > 6.5:
            violation.cause = 'origin-outside-interval'
            continue
        if nearest <= 0.5:
            violation.cause = 'extraction'
            continue
        violation.cause = 'representation'
    return violations


def classify_tight_against_caret(tight, caret, preview_caret, pages):
    """Explain historical tight-box violations using the caret comparison.

    If the caret comparison does not flag the same word, the tight box was
    the wrong rectangle (extraction). If both flag it, reuse the caret
    cause, which was decided from origins rather than from ink centres.
    """
    if not caret:
        for violation in tight:
            violation.cause = 'extraction'
        return tight
    caret_by_word = {}
    for violation in caret:
        if violation.word:
            caret_by_word.setdefault((violation.page, violation.word),
                                     []).append(violation)
    caret_clean_words = {(line.page, word.text)
                         for line in preview_caret for word in line.words}
    flagged = set(caret_by_word)
    for violation in tight:
        key = (violation.page, violation.word)
        if violation.word and key in caret_clean_words and key not in flagged:
            violation.cause = 'extraction'
            continue
        same = caret_by_word.get(key) or []
        if same and same[0].cause:
            violation.cause = same[0].cause
            continue
        violation.cause = violation.cause or 'unresolved'
    return tight


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
    counts, by_source = {}, {}
    for violation in violations:
        counts[violation.category] = counts.get(violation.category, 0) + 1
        key = (violation.category, violation.source)
        by_source[key] = by_source.get(key, 0) + 1
    lines.append('violations: ' + ', '.join(
        f'{k}={v}' + ('' if not by_source.get((k, 'float'))
                      else f' (float {by_source[(k, "float")]})')
        for k, v in sorted(counts.items())))
    # Every violation is named. A cap of four hid 20 of the 32 findings and
    # made the list unclassifiable from the annotation alone. Notices are
    # already chunked at 3000 characters.
    cause_counts = {}
    for violation in violations:
        if violation.cause:
            cause_counts[violation.cause] = cause_counts.get(violation.cause, 0) + 1
    if cause_counts:
        lines.append('causes: ' + ', '.join(
            f'{k}={v}' for k, v in sorted(cause_counts.items())))
    for category in sorted(counts):
        shown = sorted([v for v in violations if v.category == category],
                       key=lambda v: -v.magnitude)
        for violation in shown:
            cause = f' cause={violation.cause}' if violation.cause else ''
            lines.append(f'  {category} p{violation.page} [{violation.source}]: '
                         f'{violation.detail}{cause}')
    for source in ('block', 'float'):
        mine = [v for v in violations if v.source == source]
        if mine:
            lines.append(f'{source} lines: {len(mine)} violation(s)')
    if not any(v.source == 'block' for v in violations):
        lines.append('block lines: clean -- every block line agrees in baseline, '
                     'size, word edge, content and underline')
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
    parser.add_argument('--bind-rendered-source', action='store_true')
    parser.add_argument('--require-rendered-source', action='store_true')
    args = parser.parse_args(argv)

    preview_path = os.path.join(args.artifacts, PREVIEW_REL)
    pdf_path = os.path.join(args.artifacts, PDF_REL)
    missing = [p for p in (preview_path, pdf_path) if not os.path.exists(p)]
    if missing:
        print(f'::error title=C6 geometry::missing artifacts: {missing}')
        return 2

    data = read_preview(preview_path)
    if args.bind_rendered_source:
        bind_rendered_source(data, args.artifacts)
        Path(preview_path).write_text(json.dumps(data, ensure_ascii=False, indent=1))
    if args.require_rendered_source or args.bind_rendered_source:
        validate_rendered_source(data, args.artifacts)
    preview = preview_lines(data, boxes='caret')
    tight = preview_lines(data, boxes='tight')
    pages = read_pdf_pages(pdf_path)
    bounds = Bounds()
    # Verdict: the intervals the writer executed, judged by glyph origin.
    # Ink-edge disagreement with the origin still inside is published in the
    # distribution and is not a violation.
    violations, samples, coverage = compare(
        preview, pages, bounds, edges='origin', anchor='origin')
    classify_causes(violations, preview, pages)
    coverage['box_source'] = ','.join(sorted(
        {line.box_source for line in preview})) or 'none'
    coverage['edges'] = 'origin'
    # The historical 32 used tight ink boxes and glyph centres. Keep that
    # comparison, named and classified, so those rows are not dropped and
    # are not silently re-measured with a different anchor.
    historical, _, _ = compare(tight, pages, bounds, edges='ink', anchor='centre')
    classify_causes(historical, tight, pages)
    classify_tight_against_caret(historical, violations, preview, pages)

    lines = render_report(violations, samples, coverage, bounds, args.mode)
    notice('C6 geometry (PDF coordinates)', lines)
    print('\n'.join(lines))
    if any(line.box_source != 'tight' for line in preview):
        historical_lines = [
            'historical tight-box + glyph-centre diagnostic (not the verdict):']
        historical_lines.extend(render_report(
            historical, {},
            {'words': sum(len(line.words) for line in tight)},
            bounds, 'report'))
        notice('C6 geometry historical tight-box diagnostic', historical_lines)
        print('\n'.join(historical_lines))
        hist_counts = {}
        for violation in historical:
            hist_counts[violation.category] = hist_counts.get(violation.category, 0) + 1
        print('::notice title=C6 geometry historical count::'
              f'{len(historical)} tight-centre violation(s): '
              + ', '.join(f'{k}={v}' for k, v in sorted(hist_counts.items())))

    payload = {
        'mode': args.mode,
        'adopted_as_merge_gate': False,
        'sourceProvenance': data.get('provenance'),
        'bounds': bounds.__dict__,
        'coverage': coverage,
        'distribution': {k: distribution(v) for k, v in samples.items()},
        'violations': [v.__dict__ for v in violations],
        'historical_tight_centre_violations': [v.__dict__ for v in historical],
    }
    out = args.json or os.path.join(args.artifacts, JSON_OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as handle:
        json.dump(payload, handle, indent=1, ensure_ascii=False)

    if violations and args.mode == 'enforce':
        return 1
    if violations:
        # Report mode must never look like a pass.
        counts = {}
        for violation in violations:
            counts[violation.category] = counts.get(violation.category, 0) + 1
        print(f'::warning title=C6 geometry::WOULD FAIL: '
              f'{len(violations)} caret/origin violation(s) '
              f'({", ".join(f"{k}={v}" for k, v in sorted(counts.items()))}) '
              f'-- enforce mode is not enabled')
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
