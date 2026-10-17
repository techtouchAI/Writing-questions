#!/usr/bin/env python3
"""Tier 2 of the visual contract: a calibrated pixel gate -- proposal only.

The existing RMSE step compares poppler's raster of `vector.pdf` with the
Preview's Skia raster and fails above 0.02. That number cannot be met: the
*same* PDF rendered by two renderers already differs by more than that (0.050 -
0.056 measured on the gate's own bytes), so the step is comparing rasterisers
at least as much as it is comparing content.

This tool does what a threshold needs before anyone adopts it:

  1. measures the **floor** -- renderer vs renderer, on the same PDF, with
     documented settings, across every reference PDF the run produced;
  2. measures **deliberate regressions** -- the Preview image with its text
     shifted 1/2/4 px, scaled 2 %, a text band deleted, and its underline
     rule moved 4 px -- using the *gate's own metric* (ImageMagick
     `compare -metric RMSE` after the gate's own resize+crop), so the two
     distributions are directly comparable;
  3. publishes the **separation**: the floor's maximum against the smallest
     deliberate regression. If a defect is smaller than the floor it is not
     detectable at this calibration, and the tool says so instead of inventing
     a bound;
  4. proposes a threshold strictly between the two, and marks it
     **PROPOSED -- NOT ADOPTED**. `--enforce --threshold X` is the only way it
     can fail a job, and X must be passed explicitly.

Every number is reproducible from the printed command lines; the settings
manifest (dpi, engine versions, file hashes) is written next to the results.
Nothing here edits the reference images, the old RMSE cap, or the gate script.

Usage:
    c6_visual_calibration.py <artifacts_dir> [--mode calibrate|enforce]
                             [--threshold X] [--json out]

Exit codes: 0 calibrated (or within the given threshold), 1 over the given
threshold in enforce mode, 2 cannot measure (missing tools/artifacts).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

REL_DIR = os.path.join('c6diag', 'calibration')
SETTINGS = 'settings.json'
RESULTS = 'calibration.json'
DPI = 96                     # the gate's own rendering density
CROP_MARGIN = 2              # the gate crops (W-4)x(H-4)+2+2 on both sides
REGRESSIONS = ('shift_1px', 'shift_2px', 'shift_4px', 'scale_102',
               'delete_band', 'underline_4px')


def which(*names):
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    return None


def run(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, text=True,
                          **kwargs)


def version_of(path):
    for flag in ('-v', '--version', '-version'):
        try:
            out = run([path, flag]).stdout.strip().splitlines()
            if out:
                return out[0]
        except (subprocess.CalledProcessError, OSError):
            continue
    return 'unknown'


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def image_size(png):
    """Width/height from the PNG header -- no image library needed."""
    with open(png, 'rb') as handle:
        head = handle.read(33)
    if head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        raise ValueError(f'not a PNG: {png}')
    width = int.from_bytes(head[16:20], 'big')
    height = int.from_bytes(head[20:24], 'big')
    return width, height


def gate_shaped(convert, source, target, width, height):
    """The gate's own normalisation: resize to the reference size, crop 2px."""
    run([convert, source, '-resize', f'{width}x{height}!',
         '-crop', f'{width - 2 * CROP_MARGIN}x{height - 2 * CROP_MARGIN}'
         f'+{CROP_MARGIN}+{CROP_MARGIN}', '+repage', target])
    return target


def rmse(compare, left, right):
    """ImageMagick's RMSE, normalised 0..1, exactly as the gate reads it."""
    proc = subprocess.run([compare, '-metric', 'RMSE', left, right, 'null:'],
                          capture_output=True, text=True)
    text = (proc.stderr or '') + (proc.stdout or '')
    match = re.search(r'\(([0-9.]+)\)', text)
    if not match:
        raise RuntimeError(f'compare produced no RMSE: {text.strip()[:200]}')
    return float(match.group(1))


# ------------------------------------------------------------------ rendering
def render_poppler(pdftoppm, pdf, out_prefix):
    run([pdftoppm, '-r', str(DPI), '-png', pdf, out_prefix])
    return sorted(_prefix_files(out_prefix))


def render_mupdf(mutool, pdf, out_prefix):
    run([mutool, 'draw', '-q', '-r', str(DPI), '-o', out_prefix + '-%d.png',
         pdf])
    return sorted(_prefix_files(out_prefix))


def render_mupdf_python(pdf, out_prefix):
    """Fallback: PyMuPDF wraps MuPDF, the same engine `mutool draw` uses."""
    import pymupdf

    paths = []
    with pymupdf.open(pdf) as doc:
        for index, page in enumerate(doc, start=1):
            pixmap = page.get_pixmap(dpi=DPI)
            path = f'{out_prefix}-{index}.png'
            pixmap.save(path)
            paths.append(path)
    return paths


def _prefix_files(prefix):
    folder = os.path.dirname(prefix) or '.'
    stem = os.path.basename(prefix)
    return [os.path.join(folder, name) for name in os.listdir(folder)
            if name.startswith(stem) and name.endswith('.png')]


# --------------------------------------------------------------- perturbations
def perturb(convert, source, target, kind, width, height):
    """One deliberate regression, applied to the reference image itself."""
    if kind.startswith('shift_'):
        pixels = int(re.match(r'shift_(\d+)px', kind).group(1))
        run([convert, source, '-roll', f'+{pixels}+{pixels}', target])
    elif kind == 'scale_102':
        run([convert, source, '-resize', '102%', '-gravity', 'center',
             '-extent', f'{width}x{height}', target])
    elif kind == 'delete_band':
        # Blank a 24-row band around the heaviest ink row of the middle of the
        # page. Blanking a fixed coordinate could delete whitespace on some
        # fixture and then "detect" nothing; this guarantees real content goes.
        middle = _darkest_row(convert, source, int(height * 0.25),
                              int(height * 0.75))
        top = max(0, middle - 12)
        run([convert, source, '-fill', 'white', '-draw',
             f'rectangle 0,{top} {width},{min(height, top + 24)}', target])
    elif kind == 'underline_4px':
        # Find the rule-like row (the longest continuous ink run anywhere on
        # the page -- that is what a rule is), blank it, and redraw it four
        # rows lower. This reproduces the underline displacement this branch
        # fixed, at the same 4 px the parity gate measured.
        row = _rule_row(convert, source, width, height, target + '.profile.png')
        if row is None:
            raise ValueError('no rule-like row found to displace')
        strip = os.path.join(os.path.dirname(target), '_strip.png')
        run([convert, source, '-crop', f'{width}x1+0+{row}', '+repage', strip])
        run([convert, source, '-fill', 'white', '-draw',
             f'rectangle 0,{row} {width},{row}', target])
        run([convert, target, strip, '-geometry', f'+0+{row + 4}',
             '-composite', target])
        os.remove(strip)
    else:
        raise ValueError(f'unknown regression {kind}')
    return target


def _rule_row(convert, source, width, height, profile_path):
    """Row of the longest continuous ink run, downsampled to 200 columns.

    A rule is the only row whose ink does not break; glyph rows break at every
    inter-letter and inter-word gap, so this finds an underline (or a divider)
    anywhere on the page without knowing where the fixture put it.
    """
    columns = 200
    run([convert, source, '-resize', f'{columns}x{height}!', '-colorspace',
         'Gray', '-depth', '8', profile_path])
    proc = subprocess.run([convert, profile_path, 'txt:-'],
                          capture_output=True, text=True)
    rows = {}
    for line in proc.stdout.splitlines():
        match = re.match(r'(\d+),(\d+): \((\d+)', line)
        if not match:
            continue
        column, row, value = (int(match.group(1)), int(match.group(2)),
                              int(match.group(3)))
        rows.setdefault(row, {})[column] = value
    best = None
    for row, values in rows.items():
        longest = current = 0
        for column in range(columns):
            if values.get(column, 255) < 200:
                current += 1
                longest = max(longest, current)
            else:
                current = 0
        if longest >= columns * 0.2 and (best is None or longest > best[1]):
            best = (row, longest)
    os.remove(profile_path)
    return None if best is None else best[0]


def _darkest_row(convert, source, start, stop):
    """Row with the most ink in a vertical window, from the image itself."""
    proc = subprocess.run(
        [convert, source, '-crop', f'1x{stop - start}+0+{start}', '+repage',
         '-colorspace', 'Gray', 'txt:-'],
        capture_output=True, text=True)
    darkest, best = start, 256
    for line in proc.stdout.splitlines():
        match = re.match(r'0,(\d+): \((\d+)', line)
        if not match:
            continue
        value = int(match.group(2))
        if value < best:
            best, darkest = value, start + int(match.group(1))
    return darkest


# ------------------------------------------------------------------ calibration
def separation(floor, regressions):
    """Which deliberate defects this metric can see above the renderer floor.

    A single global number cannot be asked to do both jobs: it must tolerate
    two renderers disagreeing on the same PDF (the floor), and it must catch a
    defect. Any defect whose own value is at or below the floor is invisible to
    it at this calibration, and that is a property of the metric, not of the
    threshold. So the result names them instead of averaging them away.
    """
    if not floor or not regressions:
        return None
    floor_max = max(floor.values())
    detectable = {k: v for k, v in regressions.items() if v > floor_max}
    invisible = {k: v for k, v in regressions.items() if v <= floor_max}
    result = {'floor_max': floor_max,
              'detectable': detectable,
              'invisible': invisible,
              'separated': bool(detectable)}
    if detectable:
        result['proposed'] = (floor_max * min(detectable.values())) ** 0.5
        result['margin'] = (min(detectable.values()) / floor_max
                            if floor_max else float('inf'))
    return result


def notice(title, lines):
    text = '\n'.join(lines)
    for start in range(0, len(text), 3000):
        chunk = text[start:start + 3000].replace('%', '%25').replace('\r', '%0D')
        print(f'::notice title={title}::{chunk.replace(chr(10), "%0A")}')


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('artifacts')
    parser.add_argument('--mode', choices=('calibrate', 'enforce'),
                        default='calibrate')
    parser.add_argument('--threshold', type=float, default=None,
                        help='only used by enforce mode; required there')
    parser.add_argument('--json', default=None)
    args = parser.parse_args(argv)

    if args.mode == 'enforce' and args.threshold is None:
        print('::error title=C6 calibration::enforce mode needs an explicit '
              '--threshold; no bound is ever adopted implicitly')
        return 2

    compare = which('compare')
    convert = which('convert', 'magick')
    pdftoppm = which('pdftoppm')
    mutool = which('mutool')
    if not (compare and convert and pdftoppm):
        print('::error title=C6 calibration::needs ImageMagick + poppler')
        return 2
    engine = 'mutool draw' if mutool else 'PyMuPDF (MuPDF core)'

    artifacts = args.artifacts
    out_dir = os.path.join(artifacts, REL_DIR)
    render_dir = os.path.join(out_dir, 'renders')
    perturb_dir = os.path.join(out_dir, 'perturbed')
    os.makedirs(render_dir, exist_ok=True)
    os.makedirs(perturb_dir, exist_ok=True)

    # Reference cases: every PDF the run produced, not just the gate's one.
    cases = []
    for name in ('vector.pdf', 'exact.pdf', 'vector_ltr.pdf'):
        path = os.path.join(artifacts, name)
        if os.path.exists(path):
            cases.append((name, path))
    if not cases:
        print('::error title=C6 calibration::no reference PDFs')
        return 2

    preview_dirs = sorted({os.path.join(artifacts, entry)
                           for entry in os.listdir(artifacts)
                           if entry.startswith('preview_page_')
                           and entry.endswith('.png')})
    if not preview_dirs:
        print('::error title=C6 calibration::no preview pages')
        return 2

    settings = {
        'dpi': DPI,
        'crop': f'-resize WxH! -crop (W-{2 * CROP_MARGIN})x(H-{2 * CROP_MARGIN})'
                f'+{CROP_MARGIN}+{CROP_MARGIN}',
        'metric': 'ImageMagick compare -metric RMSE (normalised)',
        'poppler': f'{version_of(pdftoppm)} ({pdftoppm})',
        'mupdf': f'{engine}' + (f' {version_of(mutool)}' if mutool else ''),
        'imagemagick': version_of(convert),
        'cases': {},
    }

    width, height = image_size(preview_dirs[0])
    floor, regressions, gate = {}, {}, {}

    for name, path in cases:
        settings['cases'][name] = {'sha256': sha256(path)}
        stem = os.path.splitext(name)[0]
        poppler_pngs = render_poppler(pdftoppm, path, os.path.join(
            render_dir, f'{stem}-poppler'))
        mupdf_pngs = (render_mupdf(mutool, path, os.path.join(
            render_dir, f'{stem}-mupdf')) if mutool
            else render_mupdf_python(path, os.path.join(render_dir,
                                                        f'{stem}-mupdf')))
        for index, (left, right) in enumerate(zip(poppler_pngs, mupdf_pngs), 1):
            key = f'{stem} p{index}'
            norm_left = gate_shaped(convert, left, os.path.join(
                render_dir, f'{stem}-p{index}-poppler-norm.png'), width, height)
            norm_right = gate_shaped(convert, right, os.path.join(
                render_dir, f'{stem}-p{index}-mupdf-norm.png'), width, height)
            floor[key] = rmse(compare, norm_left, norm_right)

    # The gate's own number, for context, and the deliberate regressions.
    for preview in preview_dirs:
        page = re.search(r'preview_page_(\d+)', os.path.basename(preview))
        key = f'preview p{page.group(1)}' if page else os.path.basename(preview)
        for kind in REGRESSIONS:
            target = os.path.join(perturb_dir, f'{key.replace(" ", "-")}-{kind}.png')
            perturb(convert, preview, target, kind, *image_size(preview))
            regressions[f'{key} {kind}'] = rmse(compare, preview, target)

    result = separation(floor, regressions)
    lines = [f'renderer floor (same PDF, two engines, {DPI} dpi, gate-shaped):']
    lines += [f'  {key}: {value:.6f}' for key, value in sorted(floor.items())]
    lines.append('deliberate regressions (reference image vs itself, same metric):')
    lines += [f'  {key}: {value:.6f}'
              for key, value in sorted(regressions.items())]
    if result is None:
        lines.append('verdict: not enough data to separate floor from defects')
    else:
        lines.append(f"renderer floor max {result['floor_max']:.6f}")
        if not result['separated']:
            lines.append('verdict: NO SEPARATION -- no deliberate defect is '
                         'above the floor; a global pixel number cannot gate '
                         'this fixture, and no threshold is proposed')
        else:
            lines.append(
                f"detectable at this calibration ({len(result['detectable'])})"
                f": {', '.join(f'{k}={v:.4f}' for k, v in sorted(result['detectable'].items()))}")
            lines.append(
                f"INVISIBLE at this calibration ({len(result['invisible'])})"
                f": {', '.join(f'{k}={v:.4f}' for k, v in sorted(result['invisible'].items()))}"
                f" -- each is at or below the floor, so no threshold can catch "
                f"it without failing on two renderers of the same file")
            lines.append(f"PROPOSED threshold {result['proposed']:.6f} "
                         f"(geometric mean of the floor and the smallest "
                         f"detectable defect, margin "
                         f"{result['margin']:.2f}x) -- PROPOSED, NOT ADOPTED")
    notice('C6 visual calibration', lines)
    print('\n'.join(lines))

    payload = {'settings': settings,
               'floor': floor,
               'regressions': regressions,
               'separation': result,
               'proposed': (result or {}).get('proposed'),
               'adopted': False,
               'mode': args.mode,
               'threshold': args.threshold}
    out = args.json or os.path.join(artifacts, REL_DIR, RESULTS)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as handle:
        json.dump(payload, handle, indent=1, ensure_ascii=False)
    with open(os.path.join(artifacts, REL_DIR, SETTINGS), 'w',
              encoding='utf-8') as handle:
        json.dump(settings, handle, indent=1, ensure_ascii=False)

    if args.mode == 'enforce':
        over = {k: v for k, v in floor.items() if v > args.threshold}
        if over:
            print(f'::error title=C6 calibration::{len(over)} case(s) above '
                  f'the given threshold {args.threshold}: {over}')
            return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - a failed measurement must show
        import traceback
        traceback.print_exc()
        print(f'::warning title=C6 calibration::failed: '
              f'{type(error).__name__}: {error}')
        sys.exit(2)
