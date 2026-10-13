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


def analyse(preview_dark, pdf_dark, lines):
    """Measure every probe line and compare the two rasterizers."""
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
    return {
        'rows': rows,
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
    result = analyse(_to_list(prev_dark), _to_list(pdf_dark), lines)
    result['sizes'] = {'preview': [pw_, ph_], 'pdf': [qw_, qh_]}
    result['synthetic'] = False
    with open(os.path.join(out_dir, 'raster_results.json'), 'w',
              encoding='utf-8') as fh:
        json.dump(result, fh, indent=2)

    out = [
        '## C6 baseline sub-pixel probe (non-gating, provisional thresholds)',
        f'Real measurement: poppler vs Flutter raster of the same probe page '
        f'(sizes preview={pw_}x{ph_}, pdf={qw_}x{qh_}).',
        '',
        '| line | frac px | baseline px | preview centroid | pdf centroid | delta |',
        '|---|---|---|---|---|---|',
    ]
    for r in result['rows']:
        out.append(
            f"| {r['index']} | {r['fraction']:.1f} | {r['baselinePx']:.2f} | "
            f"{r['previewCentroid']:.3f} | {r['pdfCentroid']:.3f} | "
            f"{r['delta']:+.3f} |")
    out += [
        '',
        f"Preview rule: {result['previewFit']['best']} "
        f"(std {result['previewFit']['std'][result['previewFit']['best']]:.3f} px); "
        f"U={result['previewFit']['std']['U']:.3f} R={result['previewFit']['std']['R']:.3f} "
        f"F={result['previewFit']['std']['F']:.3f}",
        f"PDF rule: {result['pdfFit']['best']} "
        f"(std {result['pdfFit']['std'][result['pdfFit']['best']]:.3f} px); "
        f"U={result['pdfFit']['std']['U']:.3f} R={result['pdfFit']['std']['R']:.3f} "
        f"F={result['pdfFit']['std']['F']:.3f}",
        f"Delta pdf-preview: mean {result['deltaMeanPx']:+.3f} px, "
        f"std {result['deltaStdPx']:.3f} px",
        f"Window edge check ok: {result['windowEdgeOk']}",
        f"VERDICT (baseline rounding differs between rasterizers): "
        f"{result['verdict']} - {result['verdictDetail']}",
    ]
    _emit(out)
    print(f"::notice title=C6-RASTER verdict::{result['verdict']} - "
          f"{result['verdictDetail']}")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
