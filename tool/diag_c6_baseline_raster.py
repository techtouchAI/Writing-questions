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
  5. (v5) Measures the sub-pixel bottom ink edge of the flat-bottomed glyph
     'H' (edge = last inked row + its darkness), fits edge = round(B + delta)
     + const per font and rasterizer, and compares the preview delta with the
     prediction wrap(-inner_px) from Flutter's own inner baseline. Reports
     whole-pixel steps by fraction. Probe only: no link to the RMSE gate.

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
        # Dart writes these as doubles (for example 16.0); slices need ints.
        x0 = int(round(ln.get('winX0', WIN_X0)))
        x1 = int(round(ln.get('winX1', WIN_X1)))
        cp, ep = centroid_y(preview_dark, ln['baselinePx'], x0, x1)
        cq, eq = centroid_y(pdf_dark, ln['baselinePx'], x0, x1)
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


# ---- v5: sub-pixel bottom edge of a flat-bottomed glyph ('H') ----
EDGE_INK_MIN = 0.02  # PROVISIONAL: darkness that counts as ink on a bottom row
DELTA_GRID = [i / 200.0 - 0.5 for i in range(200)]  # delta in [-0.5, 0.5)
DELTA_TOL_PX = 0.05  # PROVISIONAL: fitted vs predicted delta agreement
SNAP_STEP_PX = 0.5  # PROVISIONAL: a jump this large between rows is a step


def _median(values):
    vals = sorted(values)
    n = len(vals)
    if not n:
        return float('nan')
    mid = n // 2
    return vals[mid] if n % 2 else (vals[mid - 1] + vals[mid]) / 2.0


def wrap(x):
    """Map x to [-0.5, 0.5)."""
    return x - math.floor(x + 0.5)


def bottom_edge(dark, baseline_px, x0, x1, ref_rows=2):
    """Sub-pixel bottom ink edge (device px) of a flat-bottomed glyph.

    r_max is the lowest inked row in the window. Only columns inked on r_max
    are used: a counter or crossbar column ends higher and would bias the
    edge upwards (verified on a real Tajawal 'H': median 57.4 vs true 60).
    A pixel's darkness is horizontal x vertical coverage, so the vertical
    coverage of r_max is taken as dark[r_max] / dark[r_max - ref_rows] (the
    same column, a fully covered row inside the stem). Returns
    (edge, columns_used); NaN if the window has no ink.
    """
    base = int(math.floor(baseline_px))
    lo = max(base - WIN_UP, 0)
    hi = min(base + WIN_DOWN, len(dark) - 1)
    r_max = None
    for r in range(hi, lo - 1, -1):
        if any(dark[r][x] > EDGE_INK_MIN for x in range(x0, x1)):
            r_max = r
            break
    if r_max is None or r_max - ref_rows < lo:
        return float('nan'), 0
    edges = []
    for x in range(x0, x1):
        bottom = dark[r_max][x]
        ref = dark[r_max - ref_rows][x]
        if bottom <= EDGE_INK_MIN or ref <= EDGE_INK_MIN:
            continue
        cover = min(max(bottom / ref, 0.0), 1.0)
        edges.append(r_max + cover)
    return _median(edges), len(edges)


def fit_delta(edges, baselines):
    """Best (delta, const, std) for edge = round(B + delta) + const.

    Searches DELTA_GRID. Every grid point with the minimal residual std is
    feasible; delta is the circular midpoint of the feasible set. The
    resolution is about half the spacing of the fractions (0.025 px for the
    20 probe fractions). A NaN edge gives a NaN fit, never a fake result.
    """
    nan = float('nan')
    if any(math.isnan(e) for e in edges):
        return {'delta': nan, 'const': nan, 'std': nan, 'feasibleSpan': nan}
    scored = []
    for delta in DELTA_GRID:
        resid = [e - math.floor(b + delta + 0.5)
                 for e, b in zip(edges, baselines)]
        scored.append((_std(resid), delta))
    best_std = min(std for std, _ in scored)
    feasible = [delta for std, delta in scored if std <= best_std + 1e-9]
    sx = sum(math.cos(2 * math.pi * d_) for d_ in feasible)
    sy = sum(math.sin(2 * math.pi * d_) for d_ in feasible)
    centre = wrap(math.atan2(sy, sx) / (2 * math.pi))
    resid = [e - math.floor(b + centre + 0.5) for e, b in zip(edges, baselines)]
    return {'delta': centre, 'const': sum(resid) / len(resid),
            'std': _std(resid), 'feasibleSpan': len(feasible) * 0.005}


def predict_delta(inner_px):
    """Preview model: the paint origin B - inner is rounded to whole px, so
    the sub-pixel part of the rounding is wrap(-inner_px) (mod 1)."""
    return wrap(-inner_px)


def edge_steps(prev_offsets, fractions):
    """Fraction intervals where the preview edge offset jumps by >= 0.5 px."""
    out = []
    for i in range(1, len(prev_offsets)):
        if abs(prev_offsets[i] - prev_offsets[i - 1]) >= SNAP_STEP_PX:
            out.append(f'{fractions[i - 1]:.3f}..{fractions[i]:.3f}')
    return out


def edge_analysis(sub, prev_list, pdf_list, scale):
    """v5 per-group measurement: edges, rounding fits, prediction check."""
    rows, baselines, inners = [], [], []
    for ln in sub:
        b = ln['baselinePx']
        baselines.append(b)
        x0 = int(round(ln.get('winX0', WIN_X0)))
        x1 = int(round(ln.get('winX1', WIN_X1)))
        ep, np_ = bottom_edge(prev_list, b, x0, x1)
        eq, nq = bottom_edge(pdf_list, b, x0, x1)
        inner_px = float(ln.get('previewInnerBaselinePt', float('nan'))) * scale
        inners.append(inner_px)
        rows.append({'fraction': ln['fraction'], 'baselinePx': b,
                     'prevEdge': ep, 'pdfEdge': eq,
                     'prevEdgeMinusB': ep - b, 'pdfEdgeMinusB': eq - b,
                     'prevCols': np_, 'pdfCols': nq,
                     'innerPx': inner_px})
    prev_fit = fit_delta([r['prevEdge'] for r in rows], baselines)
    pdf_fit = fit_delta([r['pdfEdge'] for r in rows], baselines)
    finite_inner = [v for v in inners if not math.isnan(v)]
    inner_mean = sum(finite_inner) / len(finite_inner) if finite_inner else float('nan')
    inner_std = _std(finite_inner)
    pred = predict_delta(inner_mean) if finite_inner else float('nan')
    if math.isnan(pred) or math.isnan(prev_fit['delta']):
        err = float('nan')
    else:
        err = wrap(prev_fit['delta'] - pred)
    steps = edge_steps([r['prevEdgeMinusB'] for r in rows],
                       [r['fraction'] for r in rows])
    return {'rows': rows, 'prevFit': prev_fit, 'pdfFit': pdf_fit,
            'innerPxMean': inner_mean, 'innerPxStd': inner_std,
            'predictedDelta': pred, 'predictionError': err,
            'prevSteps': steps}


SNAP_SUFFIX = '+snap'  # group name of the diagnostic columns (see Dart v6)


def snap_analysis(sub, prev_list, pdf_list):
    """v6: bottom edges relative to floor(B) for the snapped columns.

    floor(B) is the whole device pixel that the paint baseline is snapped to.
    If integer snapping removes the mismatch, the preview edge equals floor(B)
    at every fraction (constant, offset 0), like the PDF edge.
    """
    rows = []
    for ln in sub:
        b = ln['baselinePx']
        fb = math.floor(b)
        x0 = int(round(ln.get('winX0', WIN_X0)))
        x1 = int(round(ln.get('winX1', WIN_X1)))
        ep, _ = bottom_edge(prev_list, b, x0, x1)
        eq, _ = bottom_edge(pdf_list, b, x0, x1)
        rows.append({'fraction': ln['fraction'], 'baselinePx': b,
                     'floorB': fb, 'prevEdge': ep, 'pdfEdge': eq,
                     'prevMinusFloor': ep - fb, 'pdfMinusFloor': eq - fb})
    pm = [r['prevMinusFloor'] for r in rows]
    qm = [r['pdfMinusFloor'] for r in rows]
    nan = any(math.isnan(v) for v in pm + qm)
    return {'rows': rows,
            'prevMeanMinusFloor': float('nan') if nan else sum(pm) / len(pm),
            'prevStdMinusFloor': float('nan') if nan else _std(pm),
            'pdfMeanMinusFloor': float('nan') if nan else sum(qm) / len(qm),
            'pdfStdMinusFloor': float('nan') if nan else _std(qm)}


def decide_snap(snap_results):
    """PRE-DECLARED v6 decision (probe only, thresholds provisional).

    SNAP_MATCHES_PDF_FLOOR: in every font the snapped preview edge minus
        floor(B) is constant (std <= FIT_STD_PX) and within DELTA_TOL_PX of 0.
    SNAP_DOES_NOT_MATCH: some font fails that test.
    INCONCLUSIVE: missing ink or no snapped groups.
    This tests a candidate mechanism on the probe. It is not a production
    change and does not establish the RMSE cause.
    """
    if not snap_results:
        return 'INCONCLUSIVE - no snapped groups (probe only)'
    for name, res in snap_results.items():
        if math.isnan(res['prevMeanMinusFloor']) or math.isnan(res['prevStdMinusFloor']):
            return 'INCONCLUSIVE - NaN snapped edge in %s (probe only)' % name
    for res in snap_results.values():
        if (res['prevStdMinusFloor'] > FIT_STD_PX
                or abs(res['prevMeanMinusFloor']) > DELTA_TOL_PX):
            return 'SNAP_DOES_NOT_MATCH (probe only)'
    return 'SNAP_MATCHES_PDF_FLOOR (probe only, not RMSE)'


def decide_rounding(results):
    """PRE-DECLARED decision for v5 (probe only, thresholds provisional).

    PREVIEW_ROUNDING_PREDICTED: in every font the preview edge fits
        round(B + delta) + const (std <= FIT_STD_PX), the fit has at least one
        whole-pixel step, and the fitted delta matches wrap(-inner_px) within
        DELTA_TOL_PX.
    PREVIEW_NOT_ROUNDING: some font's preview edge does not fit the model.
    PREVIEW_NO_STEP_UNCONFIRMED: the model fits but some font shows no step,
        so the delta cannot be located.
    PREVIEW_ROUNDING_MISPREDICTED: the model fits with steps but a predicted
        delta differs by more than DELTA_TOL_PX.
    INCONCLUSIVE: anything else (NaN, missing ink, too few lines).
    Does not establish the RMSE cause.
    """
    edges = [res['edge'] for res in results.values() if 'edge' in res]
    if len(edges) != len(results) or not edges:
        return 'INCONCLUSIVE - edge measurement missing (probe only)'
    for e in edges:
        vals = [e['prevFit']['std'], e['pdfFit']['std'], e['predictionError']]
        if any(math.isnan(v) for v in vals):
            return 'INCONCLUSIVE - NaN edge or prediction (probe only)'
    if any(e['prevFit']['std'] > FIT_STD_PX for e in edges):
        return 'PREVIEW_NOT_ROUNDING (probe only)'
    if any(not e['prevSteps'] for e in edges):
        return 'PREVIEW_NO_STEP_UNCONFIRMED (probe only)'
    if any(abs(e['predictionError']) > DELTA_TOL_PX for e in edges):
        return 'PREVIEW_ROUNDING_MISPREDICTED (probe only)'
    return 'PREVIEW_ROUNDING_PREDICTED (probe only, not RMSE)'


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


def _main(argv):
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
    scale = float(probe.get('scalePxPerPt', 1.0))
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
        res['edge'] = edge_analysis(sub, prev_list, pdf_list, scale)
        if sub and sub[0].get('snapped'):
            res['snap'] = snap_analysis(sub, prev_list, pdf_list)
        results[name] = res
    snapped = {k: v for k, v in results.items() if 'snap' in v}
    plain = {k: v for k, v in results.items() if 'snap' not in v}
    if set(results) == {'A', 'B'}:
        control = pdf_control_max_diff(results)
        decision = decide_height(results, control)
        snap_decision = 'not applicable (height groups)'
    else:
        control = float('nan')
        decision = decide_rounding(plain)
        snap_decision = decide_snap({k: v['snap'] for k, v in snapped.items()})
    with open(os.path.join(out_dir, 'raster_results.json'), 'w',
              encoding='utf-8') as fh:
        json.dump({'groups': results, 'pdfControlMaxDiffPx': control,
                   'decision': decision}, fh, indent=2)

    out = [
        '## C6 baseline sub-pixel probe (non-gating, provisional thresholds)',
        'Real measurement. Groups are the probe factor: font family (v5, glyph H) '
        'or preview TextStyle.height (v3, groups A and B).',
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
            f"Edge (H bottom) preview: delta={res['edge']['prevFit']['delta']:+.3f} "
            f"std={res['edge']['prevFit']['std']:.3f} steps={res['edge']['prevSteps']} "
            f"inner={res['edge']['innerPxMean']:.3f}px "
            f"predicted={res['edge']['predictedDelta']:+.3f} "
            f"error={res['edge']['predictionError']:+.3f}",
            f"Edge (H bottom) pdf: delta={res['edge']['pdfFit']['delta']:+.3f} "
            f"std={res['edge']['pdfFit']['std']:.3f}",
        ]
        if 'snap' in res:
            sn = res['snap']
            out.append(
                f"Snap preview-floor(B): mean {sn['prevMeanMinusFloor']:+.3f} "
                f"std {sn['prevStdMinusFloor']:.3f} | pdf-floor(B): mean "
                f"{sn['pdfMeanMinusFloor']:+.3f} std {sn['pdfStdMinusFloor']:.3f}")
    out += [
        '',
        (f'PDF control (max |pdf - floor(B)| gap between groups, equal '
         f'fractions): {control:.3f} px') if control == control else
        'PDF control: not applicable (font groups)',
        f'DECISION (pre-declared rule): {decision}',
        f'SNAP DECISION (v6 diagnostic columns, pre-declared rule): {snap_decision}',
    ]
    _emit(out)
    print(f"::notice title=C6-RASTER verdict::{decision}")
    for name in sorted(results):
        _annotate(f'C6-RASTER data {name}',
                  _data_lines(results[name], pw_, ph_, qw_, qh_))
    return 0



def main(argv):
    """Entry point. Any unexpected exception is published as a notice so that
    a crash cannot disappear silently from the CI annotations. Never fails."""
    print('::notice title=C6-RASTER::analyser started (non-gating)')
    try:
        return _main(argv)
    except Exception:  # noqa: BLE001 - diagnostics must not fail CI
        import traceback
        last = traceback.format_exc().strip().splitlines()[-3:]
        print('::notice title=C6-RASTER::analyser crashed (non-gating): '
              + ' | '.join(last).replace('\n', ' '))
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


def decide_fonts(results):
    """PRE-DECLARED decision for the v4 single factor: the font family.

    Thresholds unchanged. Each font has 20 rows at the same fractions.
    NO_MISMATCH_IN_PROBE      every font's pdf-preview delta std <= FIT_STD_PX.
    MISMATCH_FONT_INDEPENDENT every font's delta std >= SEPARATION_PX, and the
                              spread of delta std and of delta mean across
                              fonts is < SEPARATION_PX.
    MISMATCH_FONT_DEPENDENT   the mismatch is present in every font, but its
                              std or mean differs across fonts by >= SEPARATION_PX.
    Otherwise INCONCLUSIVE. Probe only; does not establish the RMSE cause.
    """
    names = sorted(results)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ca = [r['previewCentroid'] for r in results[a]['rows']]
            cb = [r['previewCentroid'] for r in results[b]['rows']]
            if len(ca) == len(cb) and ca and all(
                    abs(x - y) < 1e-9 for x, y in zip(ca, cb)):
                return ('INVALID_MEASUREMENT - groups %s and %s have identical '
                        'preview centroids (window or render problem)' % (a, b))
    stds = [res['deltaStdPx'] for res in results.values()]
    means = [res['deltaMeanPx'] for res in results.values()]
    if any(math.isnan(v) for v in stds + means):
        return 'INCONCLUSIVE - a font has a NaN delta (probe only)'
    if all(v <= FIT_STD_PX for v in stds):
        return 'NO_MISMATCH_IN_PROBE (all fonts constant, probe only)'
    if all(v >= SEPARATION_PX for v in stds):
        spread_std = max(stds) - min(stds)
        spread_mean = max(means) - min(means)
        if spread_std < SEPARATION_PX and spread_mean < SEPARATION_PX:
            return 'MISMATCH_FONT_INDEPENDENT (probe only)'
        return 'MISMATCH_FONT_DEPENDENT (probe only)'
    return 'INCONCLUSIVE - mixed across fonts (probe only)'


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
           'line|frac|baselinePx|prevCentroid|pdfCentroid|delta|emittedErrPt|prevEdge-B|pdfEdge-B|innerPx']
    edge_rows = result['edge']['rows']
    for r, er in zip(result['rows'], edge_rows):
        e = r.get('emittedErrorPt', float('nan'))
        out.append(f"{r['index']}|{r['fraction']:.3f}|{r['baselinePx']:.2f}|"
                   f"{r['previewCentroid']:.3f}|{r['pdfCentroid']:.3f}|"
                   f"{r['delta']:+.3f}|{e:+.4f}|"
                   f"{er['prevEdgeMinusB']:+.3f}|{er['pdfEdgeMinusB']:+.3f}|"
                   f"{er['innerPx']:.3f}")
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
