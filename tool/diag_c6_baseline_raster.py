"""[C6-RASTER] TEMPORARY baseline sub-pixel probe analysis (non-gating).

Input (written by test/visual/diag_c6_baseline_raster_test.dart):
  <dir>/probe.json, <dir>/preview_raster.png, <dir>/baseline_probe.pdf

What it does:
  1. Rasterizes baseline_probe.pdf with poppler (pdftoppm -r 96), the same
     rasterizer family as the official gate.
  2. For every probe line, measures the vertical ink centroid in both rasters
     (Flutter preview and poppler PDF) inside a fixed window.
  3. Fits three candidate rules that map the intended baseline B (device px)
     to the rendered centroid:
       U  unsnapped:  centroid - B        is constant over the lines
       R  rounded:    centroid - round(B) is constant
       F  floored:    centroid - floor(B) is constant
     The rule whose residual has the smallest standard deviation is that
     rasterizer's rule.
  4. Reports whether the two rasterizers follow the same rule.

Every threshold below is PROVISIONAL and diagnostic only. They are not proven
scientific criteria and do not change the official RMSE gate (0.02).

Usage: diag_c6_baseline_raster.py <build/visual_parity/c6diag/baseline_raster>
Exit code is always 0: the probe must never fail the build it diagnoses.
"""
import json
import math
import os
import subprocess
import sys

MIN_LINES = 20  # PROVISIONAL: lines needed before a verdict is reported
FIT_STD_PX = 0.05  # PROVISIONAL: a rule "fits" if its residual std is <= this
SEPARATION_PX = 0.10  # PROVISIONAL: a rule is "rejected" if its std is >= this
WIN_X0, WIN_X1 = 60, 260  # columns of the probe text (device px)
WIN_UP, WIN_DOWN = 16, 10  # rows around floor(B)
EDGE_MASS_MAX = 0.01  # PROVISIONAL: ink on the window edge rows
RULES = ('U', 'R', 'F')


def _std(values):
    if not values:
        return float('nan')
    mean = sum(values) / len(values)
    return math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))


def centroid_y(dark, baseline_px, x0=WIN_X0, x1=WIN_X1):
    """Vertical ink centroid (device px) and edge-mass fraction in a window.

    dark: 2-D sequence [row][col] of darkness in [0, 1] (0 = white).
    Pixel row j is centred at j + 0.5. Returns (centroid, edge_fraction).
    """
    top = int(math.floor(baseline_px)) - WIN_UP
    bottom = int(math.floor(baseline_px)) + WIN_DOWN
    rows = range(max(top, 0), min(bottom + 1, len(dark)))
    weights = []
    for r in rows:
        weights.append(sum(dark[r][x0:x1]))
    total = sum(weights)
    if total <= 0:
        return float('nan'), float('nan')
    centroid = sum((r + 0.5) * w for r, w in zip(rows, weights)) / total
    edge = weights[:2] + weights[-2:]
    return centroid, sum(edge) / total


def residuals(centroids, baselines):
    """Residual lists for the three candidate rules."""
    out = {'U': [], 'R': [], 'F': []}
    for c, b in zip(centroids, baselines):
        out['U'].append(c - b)
        out['R'].append(c - math.floor(b + 0.5))
        out['F'].append(c - math.floor(b))
    return out


def fit_rule(centroids, baselines):
    """Return {'best': rule, 'std': {rule: std}} for one rasterizer."""
    res = residuals(centroids, baselines)
    stds = {rule: _std(res[rule]) for rule in RULES}
    best = min(RULES, key=lambda rule: stds[rule])
    return {'best': best, 'std': stds}


def verdict(preview_fit, pdf_fit, n_lines):
    """Hypothesis verdict. Returns (label, detail)."""
    if n_lines < MIN_LINES:
        return 'INCONCLUSIVE', f'only {n_lines} lines (< {MIN_LINES})'
    p_best, q_best = preview_fit['best'], pdf_fit['best']
    p_std = preview_fit['std'][p_best]
    q_std = pdf_fit['std'][q_best]
    # NaN compares false with everything, so it must be caught explicitly;
    # otherwise a missing measurement would fall through to SAME_RULE.
    if math.isnan(p_std) or math.isnan(q_std):
        return 'INCONCLUSIVE', 'residual std is undefined (missing ink)'
    if p_std > FIT_STD_PX or q_std > FIT_STD_PX:
        return 'NO_RULE_FITS', (
            f'best residual std preview={p_std:.3f}px pdf={q_std:.3f}px '
            f'(fit limit {FIT_STD_PX}px)')
    if p_best == q_best:
        return 'SAME_RULE', (
            f'both rasterizers follow rule {p_best} (std preview={p_std:.3f}, '
            f'pdf={q_std:.3f} px)')
    # Different rules. The hypothesis is supported only if each rule is
    # clearly rejected for the other rasterizer.
    p_on_q = pdf_fit['std'][p_best]
    q_on_p = preview_fit['std'][q_best]
    if p_on_q >= SEPARATION_PX and q_on_p >= SEPARATION_PX:
        return 'DIFFERENT_RULE', (
            f'preview follows {p_best} (std {p_std:.3f}px), pdf follows '
            f'{q_best} (std {q_std:.3f}px); each rule is rejected for the '
            f'other rasterizer (>= {SEPARATION_PX}px)')
    return 'INCONCLUSIVE', (
        f'rules differ but separation is weak: preview {p_best} on pdf '
        f'{p_on_q:.3f}px, pdf {q_best} on preview {q_on_p:.3f}px')


EMITTED_TOL_PT = 0.01  # PROVISIONAL: emitted baseline error counted as zero


def match_origins(intended_pt, spans, tol_pt=2.0):
    """Signed error (pt) of the emitted baseline versus each intended baseline.

    spans: [{'y': baseline_y_pt_topdown, ...}] read from the PDF content. Each
    intended baseline takes the nearest span within tol_pt. Missing = NaN.
    """
    out = []
    for b in intended_pt:
        best = None
        for sp in spans:
            dist = abs(sp['y'] - b)
            if dist <= tol_pt and (best is None or dist < abs(best - b)):
                best = sp['y']
        out.append(float('nan') if best is None else best - b)
    return out


def pdf_origin_spans(pdf_path):
    """Text spans of page 1 with their baseline origin (pt, top-left origin).

    Read from the PDF content (no rasterization), so this is the exact
    position the PDF asks the viewer to draw.
    """
    import pymupdf
    doc = pymupdf.open(pdf_path)
    spans = []
    for block in doc[0].get_text('dict')['blocks']:
        for line in block.get('lines', []):
            for span in line.get('spans', []):
                if span.get('text', '').strip():
                    spans.append({'text': span['text'],
                                  'x': span['origin'][0],
                                  'y': span['origin'][1],
                                  'size': span['size']})
    return spans


def analyse(preview_dark, pdf_dark, lines, emitted_pt=None):
    """Measure every probe line and compare the two rasterizers.

    emitted_pt: optional signed errors (pt) of the PDF's emitted baselines.
    """
    baselines = [ln['baselinePx'] for ln in lines]
    prev_c, pdf_c, rows = [], [], []
    for ln in lines:
        cp, ep = centroid_y(preview_dark, ln['baselinePx'])
        cq, eq = centroid_y(pdf_dark, ln['baselinePx'])
        prev_c.append(cp)
        pdf_c.append(cq)
        rows.append({
            'index': ln['index'],
            'fraction': ln['fraction'],
            'baselinePx': ln['baselinePx'],
            'previewCentroid': cp,
            'pdfCentroid': cq,
            'delta': cq - cp,
            'previewEdgeFraction': ep,
            'pdfEdgeFraction': eq,
        })
    preview_fit = fit_rule(prev_c, baselines)
    pdf_fit = fit_rule(pdf_c, baselines)
    deltas = [cq - cp for cq, cp in zip(pdf_c, prev_c)]
    missing = sum(1 for c in prev_c + pdf_c if math.isnan(c))
    if missing:
        label, detail = 'INCONCLUSIVE', (
            f'{missing} window(s) contain no ink; no verdict is reported')
    else:
        label, detail = verdict(preview_fit, pdf_fit, len(lines))
    edge_ok = all(
        (r['previewEdgeFraction'] <= EDGE_MASS_MAX and
         r['pdfEdgeFraction'] <= EDGE_MASS_MAX)
        for r in rows if not math.isnan(r['previewEdgeFraction']))
    if emitted_pt is not None:
        for r, e in zip(rows, emitted_pt):
            r['emittedErrorPt'] = e
    emitted_ok = None
    if emitted_pt:
        finite = [abs(e) for e in emitted_pt if not math.isnan(e)]
        emitted_ok = bool(finite) and max(finite) <= EMITTED_TOL_PT
    return {
        'rows': rows,
        'emittedOk': emitted_ok,
        'previewFit': preview_fit,
        'pdfFit': pdf_fit,
        'deltaMeanPx': sum(deltas) / len(deltas) if deltas else float('nan'),
        'deltaStdPx': _std(deltas),
        'windowEdgeOk': edge_ok,
        'verdict': label,
        'verdictDetail': detail,
    }


def _load_darkness(path):
    import fitz  # pymupdf
    import numpy as np
    pix = fitz.Pixmap(path)
    if pix.alpha:
        pix = fitz.Pixmap(pix, 0)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
        pix.height, pix.width, pix.n)
    gray = arr[:, :, :3].astype(float).mean(axis=2)
    return (255.0 - gray) / 255.0, pix.width, pix.height


def _to_list(dark):
    return dark.tolist()


def _rasterize_pdf(pdf_path, out_png):
    prefix = out_png[:-4]
    cmd = ['pdftoppm', '-r', '96', '-png', '-singlefile', pdf_path, prefix]
    subprocess.run(cmd, check=True, capture_output=True)
    return out_png


def _emit(lines_out):
    text = '\n'.join(lines_out)
    print(text)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as fh:
            fh.write(text + '\n')


def main(argv):
    if len(argv) != 2:
        print('usage: diag_c6_baseline_raster.py <dir>')
        return 0
    out_dir = argv[1]
    probe_path = os.path.join(out_dir, 'probe.json')
    if not os.path.exists(probe_path):
        print('::notice title=C6-RASTER::probe.json missing; the Flutter probe '
              'did not produce output (non-gating).')
        return 0
    with open(probe_path, encoding='utf-8') as fh:
        probe = json.load(fh)
    lines = probe['lines']
    try:
        prev_png = os.path.join(out_dir, 'preview_raster.png')
        pdf_png = _rasterize_pdf(os.path.join(out_dir, 'baseline_probe.pdf'),
                                 os.path.join(out_dir, 'pdf_raster.png'))
        prev_dark, pw_, ph_ = _load_darkness(prev_png)
        pdf_dark, qw_, qh_ = _load_darkness(pdf_png)
    except Exception as exc:  # noqa: BLE001 - diagnostics must not fail CI
        print(f'::notice title=C6-RASTER::raster step failed: {exc!r} (non-gating)')
        return 0
    # Emitted baseline error: read from the PDF content, no rasterization.
    try:
        spans = pdf_origin_spans(os.path.join(out_dir, 'baseline_probe.pdf'))
        emitted_pt = match_origins([ln['baselinePt'] for ln in lines], spans)
    except Exception as exc:  # noqa: BLE001 - diagnostics must not fail CI
        spans, emitted_pt = [], None
        print(f'::notice title=C6-RASTER::PDF span read failed: {exc!r}')
    prev_list, pdf_list = _to_list(prev_dark), _to_list(pdf_dark)
    emitted_all = emitted_pt
    results = {}
    for name, idxs in split_groups(lines).items():
        sub = [lines[i] for i in idxs]
        sub_emitted = [emitted_all[i] for i in idxs] if emitted_all else None
        res = analyse(prev_list, pdf_list, sub, emitted_pt=sub_emitted)
        res['group'] = name
        res['heightFactor'] = sub[0].get('heightFactor')
        res['pdfSpanCount'] = len(spans)
        res['sizes'] = {'preview': [pw_, ph_], 'pdf': [qw_, qh_]}
        res['synthetic'] = False
        results[name] = res
    control = pdf_control_max_diff(results) if set(results) == {'A', 'B'} \
        else float('nan')
    decision = decide_height(results, control) if set(results) == {'A', 'B'} \
        else 'INCONCLUSIVE - the two groups A and B are not both present'
    with open(os.path.join(out_dir, 'raster_results.json'), 'w',
              encoding='utf-8') as fh:
        json.dump({'groups': results, 'pdfControlMaxDiffPx': control,
                   'decision': decision}, fh, indent=2)

    out = [
        '## C6 baseline sub-pixel probe v3 (non-gating, provisional thresholds)',
        'Real measurement. Single factor: preview TextStyle.height '
        '(group A unset, group B = production lineHeightFactor).',
        f'Sizes preview={pw_}x{ph_}, pdf={qw_}x{qh_}.',
    ]
    for name in sorted(results):
        res = results[name]
        out += [
            '',
            f"### Group {name} (height={res['heightFactor']})",
            f"Preview rule: {res['previewFit']['best']} "
            f"(U={res['previewFit']['std']['U']:.3f} "
            f"R={res['previewFit']['std']['R']:.3f} "
            f"F={res['previewFit']['std']['F']:.3f})",
            f"PDF rule: {res['pdfFit']['best']} "
            f"(U={res['pdfFit']['std']['U']:.3f} "
            f"R={res['pdfFit']['std']['R']:.3f} "
            f"F={res['pdfFit']['std']['F']:.3f})",
            f"Delta pdf-preview: mean {res['deltaMeanPx']:+.3f} px, "
            f"std {res['deltaStdPx']:.3f} px",
            f"Verdict: {res['verdict']} - {res['verdictDetail']}",
        ]
    out += [
        '',
        f'PDF control (max |pdf - floor(B)| gap between groups, equal '
        f'fractions): {control:.3f} px',
        f'DECISION (pre-declared rule): {decision}',
    ]
    _emit(out)
    print(f"::notice title=C6-RASTER verdict::{decision}")
    for name in sorted(results):
        _annotate(f'C6-RASTER data {name}',
                  _data_lines(results[name], pw_, ph_, qw_, qh_))
    return 0


def split_groups(lines):
    """Map group name -> list of indices into lines (order preserved)."""
    groups = {}
    for i, ln in enumerate(lines):
        groups.setdefault(ln.get('group', 'A'), []).append(i)
    return groups


def pdf_control_max_diff(results):
    """Largest gap between groups in (pdf centroid - floor(B)) at equal
    fractions. The PDF side is produced identically in both groups, so this
    should be ~0. NaN if any row lacks ink or no fraction is shared."""
    def rel(res):
        return {round(r['fraction'], 3):
                r['pdfCentroid'] - math.floor(r['baselinePx'])
                for r in res['rows']}
    ra, rb = rel(results['A']), rel(results['B'])
    common = sorted(set(ra) & set(rb))
    vals = [abs(ra[k] - rb[k]) for k in common]
    if not vals or any(math.isnan(v) for v in vals):
        return float('nan')
    return max(vals)


def decide_height(results, control_diff):
    """PRE-DECLARED decision for the v3 single factor (thresholds unchanged).

    HEIGHT_EXPLAINS_PROBE_MISMATCH: the PDF control holds, group B's
        pdf-preview delta is constant (std <= FIT_STD_PX) and group A's
        delta depends on the fraction (std >= SEPARATION_PX).
    HEIGHT_DOES_NOT_EXPLAIN: the control holds and both groups still
        depend on the fraction (std >= SEPARATION_PX).
    NO_MISMATCH_IN_PROBE: the control holds and both groups are constant
        (std <= FIT_STD_PX): there is no fraction-dependent mismatch to explain.
    INVALID_CONTROL: the PDF side differed between groups, so the single
        factor is not isolated.
    Anything else is INCONCLUSIVE. This is a probe result only. It does not
    show that the official RMSE gate is explained.
    """
    a = results['A']['deltaStdPx']
    b = results['B']['deltaStdPx']
    if math.isnan(control_diff):
        return 'INCONCLUSIVE - PDF control not measurable (missing ink)'
    if control_diff > FIT_STD_PX:
        return 'INVALID_CONTROL - PDF side differs between groups'
    if math.isnan(a) or math.isnan(b):
        return 'INCONCLUSIVE - a delta is NaN'
    if b <= FIT_STD_PX and a >= SEPARATION_PX:
        return 'HEIGHT_EXPLAINS_PROBE_MISMATCH (probe only, not RMSE)'
    if a >= SEPARATION_PX and b >= SEPARATION_PX:
        return 'HEIGHT_DOES_NOT_EXPLAIN (probe only)'
    if a <= FIT_STD_PX and b <= FIT_STD_PX:
        return 'NO_MISMATCH_IN_PROBE (both groups constant, probe only)'
    return 'INCONCLUSIVE - mixed result (probe only)'


def _data_lines(result, pw_, ph_, qw_, qh_):
    """Compact per-line data for annotations (REAL measurements)."""
    out = [f'sizes preview={pw_}x{ph_} pdf={qw_}x{qh_} spans={result["pdfSpanCount"]}',
           'line|frac|baselinePx|prevCentroid|pdfCentroid|delta|emittedErrPt']
    for r in result['rows']:
        e = r.get('emittedErrorPt', float('nan'))
        out.append(f"{r['index']}|{r['fraction']:.3f}|{r['baselinePx']:.2f}|"
                   f"{r['previewCentroid']:.3f}|{r['pdfCentroid']:.3f}|"
                   f"{r['delta']:+.3f}|{e:+.4f}")
    p, q = result['previewFit'], result['pdfFit']
    out.append('fit preview U={:.3f} R={:.3f} F={:.3f} best={}'.format(
        p['std']['U'], p['std']['R'], p['std']['F'], p['best']))
    out.append('fit pdf U={:.3f} R={:.3f} F={:.3f} best={}'.format(
        q['std']['U'], q['std']['R'], q['std']['F'], q['best']))
    out.append(f"delta pdf-preview mean={result['deltaMeanPx']:+.3f} "
               f"std={result['deltaStdPx']:.3f}")
    out.append(f"emittedOk(tol {EMITTED_TOL_PT}pt)={result['emittedOk']}")
    return out


def _annotate(title, lines, limit=2800):
    """::notice annotations split between whole lines as [i/n] (see ink tool)."""
    parts, cur, size = [], [], 0
    for line in lines:
        if cur and size + len(line) + 1 > limit:
            parts.append(cur)
            cur, size = [], 0
        cur.append(line)
        size += len(line) + 1
    if cur:
        parts.append(cur)
    for i, part in enumerate(parts, 1):
        head = f'[{i}/{len(parts)}] ' if len(parts) > 1 else ''
        text = (head + '\n'.join(part)).replace('%', '%25').replace('\r', '%0D')
        print(f"::notice title={title}::{text.replace(chr(10), '%0A')}")


if __name__ == '__main__':
    sys.exit(main(sys.argv))
