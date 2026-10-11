#!/usr/bin/env python3
"""[C6-POS] TEMPORARY diagnostic (non-gating): PDF vs Preview text positions.

Not for merge. Changes no production file and no gate. Never fails the job.

Question: after the Preview and the vector PDF are both laid out from the same
LayoutDocument, where do they disagree, in layout points, for each word and
each line baseline? The earlier pixel residuals cannot say whether the cause is
position, size, or coverage. This measures positions directly.

Three position sources per word, all in PDF points (top-left origin):
  * layout  : LayoutWord.x, the value the PDF writer is given.
  * preview : TextPainter word boxes in the Preview's own paint
              (tool input: build/visual_parity/c6diag/text_positions/
              preview_positions.json, written by
              test/visual/diag_c6_text_positions_test.dart).
  * pdf     : the glyph origins and word boxes that PyMuPDF reads from
              build/visual_parity/vector.pdf, which is the gate's own PDF.

Matching: a PDF word and a Preview word are paired when their baselines are
within BASELINE_TOL_PT and their x-intervals have IoU >= MIN_IOU. Pairing is
one-to-one, greedy by IoU. Unmatched words are counted, not dropped silently.

Reported per group (all, per font, per direction, per page): n, median, IQR,
mean |x|, and a 95% bootstrap CI of the median (seeded, BOOT resamples).

Evidence rules: this script reports measurements only. Do not read a
synthetic test as evidence about the real fixture. Its unit tests are tool
tests (tool/test_diag_c6_text_positions.py).

Usage: diag_c6_text_positions.py <artifacts_dir>
"""
import json
import os
import sys
import traceback
from collections import Counter

import numpy as np
import pymupdf

BASELINE_TOL_PT = 2.0
MIN_IOU = 0.3
BOOT = 2000
SEED = 0
SCHEMA = 'c6-preview-positions-v1'
REL_DIR = os.path.join('c6diag', 'text_positions')
PREVIEW_NAME = 'preview_positions.json'
SUMMARY_TXT = 'text_positions_summary.txt'
SUMMARY_JSON = 'text_positions_summary.json'

METRICS = (
    'dy_pdf_preview',
    'dx_left_pdf_preview',
    'dx_right_pdf_preview',
    'width_ratio',
    'size_ratio',
    'top_ratio',
    'bottom_ratio',
    'dx_pdf_layout',
    'dx_preview_layout',
    'dy_preview_layout',
)


def _notice(title, lines):
    text = '\n'.join(lines)
    for i in range(0, len(text), 3000):
        chunk = text[i:i + 3000].replace('%', '%25').replace('\r', '%0D')
        chunk = chunk.replace('\n', '%0A')
        print(f'::notice title={title}::{chunk}')


# ------------------------------------------------------------------ inputs

def load_preview(path):
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    if data.get('schema') != SCHEMA:
        raise ValueError(f'unexpected schema {data.get("schema")!r}')
    return data


def preview_word_records(data):
    """Flatten measured Preview word boxes. Math and unmeasured runs are counted."""
    recs = []
    math_runs = 0
    unmeasured_runs = 0
    for page in data['pages']:
        pno = page['page']
        for line in page['lines']:
            for run in line['runs']:
                if run.get('isMath'):
                    math_runs += 1
                    continue
                if not run.get('measured'):
                    unmeasured_runs += 1
                    continue
                layout_words = run.get('layoutWords', [])
                for pw in run.get('previewWords', []):
                    k = pw['index']
                    layout_x = None
                    if pw.get('countsMatchLayout') and k < len(layout_words):
                        layout_x = layout_words[k]['xPt']
                    recs.append({
                        'page': pno,
                        'source': line['source'],
                        'baseline': run['previewBaselinePt'],
                        'line_baseline': line['baselinePt'],
                        'left': pw['leftPt'],
                        'right': pw['rightPt'],
                        'text': pw['text'],
                        'font': run['fontFamily'],
                        'size': run['fontSizePt'],
                        'rtl': bool(run['rtl']),
                        'inner_asc': run['innerAscentPt'],
                        'inner_desc': run['innerDescentPt'],
                        'layout_x': layout_x,
                    })
    return recs, {'math_runs': math_runs, 'unmeasured_runs': unmeasured_runs}


def extract_pdf_words(pdf_path):
    """Per page: word boxes from PyMuPDF plus baseline, size and font from chars.

    PyMuPDF words are whitespace tokens, the same tokens the PDF writer emits
    (one text object per word). Horizontal extents are advance-based. The
    baseline is the median origin y of the glyph origins inside the box.
    """
    doc = pymupdf.open(pdf_path)
    try:
        result = {}
        for pno, page in enumerate(doc, start=1):
            chars = []
            raw = page.get_text('rawdict')
            for block in raw.get('blocks', []):
                for line in block.get('lines', []):
                    for span in line.get('spans', []):
                        for ch in span.get('chars', []):
                            ox, oy = ch['origin']
                            chars.append((ox, oy, span['size'], span['font']))
            words = []
            without_chars = 0
            for w in page.get_text('words'):
                x0, y0, x1, y1, text = w[0], w[1], w[2], w[3], w[4]
                members = [c for c in chars
                           if x0 - 0.5 <= c[0] <= x1 + 0.5 and y0 <= c[1] <= y1]
                if not members:
                    without_chars += 1
                    continue
                baseline = float(np.median([c[1] for c in members]))
                size = float(np.median([c[2] for c in members]))
                font = Counter(c[3] for c in members).most_common(1)[0][0]
                words.append({
                    'page': pno,
                    'x0': float(x0), 'x1': float(x1),
                    'y0': float(y0), 'y1': float(y1),
                    'text': text,
                    'baseline': baseline,
                    'size': size,
                    'font': font,
                    'asc': float(y0 - baseline),
                    'desc': float(y1 - baseline),
                })
            result[pno] = {
                'width_pt': float(page.rect.width),
                'height_pt': float(page.rect.height),
                'words': words,
                'words_without_chars': without_chars,
            }
        return result
    finally:
        doc.close()


# ---------------------------------------------------------------- matching

def interval_iou(a0, a1, b0, b1):
    inter = min(a1, b1) - max(a0, b0)
    if inter <= 0:
        return 0.0
    union = max(a1, b1) - min(a0, b0)
    return inter / union if union > 0 else 0.0


def match_words(pdf_words, prev_words):
    """One-to-one greedy matching. Returns (pdf_index, preview_index, iou) list."""
    cands = []
    for j, p in enumerate(prev_words):
        for i, q in enumerate(pdf_words):
            if abs(q['baseline'] - p['baseline']) > BASELINE_TOL_PT:
                continue
            iou = interval_iou(q['x0'], q['x1'], p['left'], p['right'])
            if iou >= MIN_IOU:
                cands.append((iou, i, j))
    cands.sort(key=lambda c: (-c[0], c[1], c[2]))
    used_i, used_j, pairs = set(), set(), []
    for iou, i, j in cands:
        if i in used_i or j in used_j:
            continue
        used_i.add(i)
        used_j.add(j)
        pairs.append((i, j, iou))
    return pairs


def pair_metrics(q, p):
    width_p = p['right'] - p['left']
    width_q = q['x1'] - q['x0']
    m = {
        'dy_pdf_preview': q['baseline'] - p['baseline'],
        'dx_left_pdf_preview': q['x0'] - p['left'],
        'dx_right_pdf_preview': q['x1'] - p['right'],
        'width_ratio': width_q / width_p if width_p > 0 else None,
        'size_ratio': q['size'] / p['size'] if p['size'] > 0 else None,
        'top_ratio': (-q['asc']) / p['inner_asc'] if p['inner_asc'] else None,
        'bottom_ratio': q['desc'] / p['inner_desc'] if p['inner_desc'] else None,
        'dx_pdf_layout': None,
        'dx_preview_layout': None,
        'dy_preview_layout': p['baseline'] - p['line_baseline'],
    }
    if p['layout_x'] is not None:
        m['dx_pdf_layout'] = q['x0'] - p['layout_x']
        m['dx_preview_layout'] = p['left'] - p['layout_x']
    return m


# ------------------------------------------------------------------- stats

def stats(values):
    arr = np.asarray([v for v in values if v is not None and np.isfinite(v)],
                     dtype=float)
    n = int(arr.size)
    if n == 0:
        return {'n': 0}
    out = {
        'n': n,
        'median': float(np.median(arr)),
        'p25': float(np.percentile(arr, 25)),
        'p75': float(np.percentile(arr, 75)),
        'mean_abs': float(np.mean(np.abs(arr))),
    }
    if n >= 3:
        rng = np.random.default_rng(SEED)
        idx = rng.integers(0, n, size=(BOOT, n))
        meds = np.median(arr[idx], axis=1)
        out['ci95'] = [float(np.percentile(meds, 2.5)),
                       float(np.percentile(meds, 97.5))]
    return out


def run_analysis(pdf_pages, prev_words, preview_meta, layout_pages):
    matched = []
    per_page = {}
    for pno, pdf in pdf_pages.items():
        page_prev = [p for p in prev_words if p['page'] == pno]
        pairs = match_words(pdf['words'], page_prev)
        for i, j, iou in pairs:
            q, p = pdf['words'][i], page_prev[j]
            rec = {'page': pno, 'font_preview': p['font'], 'font_pdf': q['font'],
                   'rtl': p['rtl'], 'text_pdf': q['text'], 'text_preview': p['text'],
                   'iou': iou, 'size_pdf': q['size'], 'size_preview': p['size']}
            rec.update(pair_metrics(q, p))
            matched.append(rec)
        per_page[pno] = {
            'pdf_words': len(pdf['words']),
            'pdf_words_without_chars': pdf['words_without_chars'],
            'preview_words': len(page_prev),
            'matched': len(pairs),
            'unmatched_preview': len(page_prev) - len(pairs),
            'unmatched_pdf': len(pdf['words']) - len(pairs),
        }

    groups = {'all': matched}
    for key in sorted({r['font_preview'] for r in matched}):
        groups[f'font={key}'] = [r for r in matched if r['font_preview'] == key]
    groups['rtl=True'] = [r for r in matched if r['rtl']]
    groups['rtl=False'] = [r for r in matched if not r['rtl']]
    for pno in sorted(per_page):
        groups[f'page={pno}'] = [r for r in matched if r['page'] == pno]

    summary = {
        'schema': 'c6-text-positions-summary-v1',
        'baseline_tol_pt': BASELINE_TOL_PT,
        'min_iou': MIN_IOU,
        'boot': BOOT,
        'preview_meta': preview_meta,
        'page_size_check': {},
        'per_page': per_page,
        'groups': {},
    }
    for pno, pdf in pdf_pages.items():
        lp = layout_pages.get(pno)
        if lp:
            summary['page_size_check'][str(pno)] = {
                'pdf_wh_pt': [pdf['width_pt'], pdf['height_pt']],
                'layout_wh_pt': [lp['widthPt'], lp['heightPt']],
                'max_abs_diff_pt': max(abs(pdf['width_pt'] - lp['widthPt']),
                                       abs(pdf['height_pt'] - lp['heightPt'])),
            }
    for name, recs in groups.items():
        summary['groups'][name] = {m: stats([r[m] for r in recs]) for m in METRICS}
        summary['groups'][name]['_count'] = len(recs)
    return summary


def format_text(summary):
    lines = [
        'C6 PDF vs Preview text positions (non-gating; measurements only)',
        f'baseline tol {BASELINE_TOL_PT} pt, min IoU {MIN_IOU}, bootstrap {BOOT} (seed {SEED})',
        'top/bottom ratios: MuPDF word-box extent vs Flutter ascent/descent; '
        'font-derived, NOT the PDF clip rectangle',
        f'preview meta: {summary["preview_meta"]}',
    ]
    for pno, s in sorted(summary['per_page'].items()):
        lines.append(f'page {pno}: {s}')
    for pno, s in sorted(summary['page_size_check'].items()):
        lines.append(f'page {pno} size check: {s}')
    lines.append('group | metric | n | median [95% CI] | p25..p75 | mean|x|')
    for name, g in summary['groups'].items():
        for m in METRICS:
            s = g[m]
            if not s.get('n'):
                continue
            ci = s.get('ci95')
            ci_txt = f' [{ci[0]:.4f}, {ci[1]:.4f}]' if ci else ''
            lines.append(
                f'{name} | {m} | {s["n"]} | {s["median"]:.4f}{ci_txt} | '
                f'{s["p25"]:.4f}..{s["p75"]:.4f} | {s["mean_abs"]:.4f}')
    return lines


KEY_METRICS = (
    'dy_pdf_preview',
    'dx_left_pdf_preview',
    'width_ratio',
    'size_ratio',
    'top_ratio',
    'dx_pdf_layout',
    'dy_preview_layout',
)


def annotation_lines(summary):
    """Condensed view for the job annotations; full table is in the artifact."""
    lines = [f'matched per page: {summary["per_page"]}']
    for name, g in summary['groups'].items():
        if not (name == 'all' or name.startswith(('rtl=', 'font='))):
            continue
        lines.append(f'[{name}] n={g["_count"]}')
        for m in KEY_METRICS:
            s = g[m]
            if not s.get('n'):
                continue
            ci = s.get('ci95')
            ci_txt = f' CI [{ci[0]:.4f}, {ci[1]:.4f}]' if ci else ''
            lines.append(f'  {m}: n={s["n"]} med={s["median"]:.4f}{ci_txt} '
                         f'mean|x|={s["mean_abs"]:.4f}')
    return lines


def run(artifacts):
    pdf_path = os.path.join(artifacts, 'vector.pdf')
    out_dir = os.path.join(artifacts, REL_DIR)
    prev_path = os.path.join(out_dir, PREVIEW_NAME)
    if not os.path.isfile(pdf_path) or not os.path.isfile(prev_path):
        _notice('C6 text positions', [
            'skipped: missing input',
            f'vector.pdf: {os.path.isfile(pdf_path)}',
            f'preview json: {os.path.isfile(prev_path)}',
        ])
        return 0
    data = load_preview(prev_path)
    prev_words, meta = preview_word_records(data)
    layout_pages = {p['page']: p for p in data['pages']}
    pdf_pages = extract_pdf_words(pdf_path)
    summary = run_analysis(pdf_pages, prev_words, meta, layout_pages)
    lines = format_text(summary)
    with open(os.path.join(out_dir, SUMMARY_JSON), 'w', encoding='utf-8') as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(out_dir, SUMMARY_TXT), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    _notice('C6 text positions (non-gating)', annotation_lines(summary))
    return 0


def main(argv):
    if len(argv) != 2:
        print('usage: diag_c6_text_positions.py <artifacts_dir>')
        return 0
    try:
        return run(argv[1])
    except Exception:  # non-gating: report and exit 0
        _notice('C6 text positions error', traceback.format_exc().splitlines())
        return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
