#!/usr/bin/env python3
"""Search for a comparison that stays inside the current contract.

The ceiling stays 0.02. The reference images stay. The gate is not changed
here. A candidate is reported only when, on the actual fixture bytes:

  * two PDF rasterizers of the same vector.pdf score at or under 0.02
    (identical content must be able to pass);
  * a 1 px shift, a deleted content band, and a 4 px underline move each
    score above 0.02, both on the preview against itself and across the two
    rasterizers (the defect must still fail the same ceiling).

Anything else is printed and not proposed. This tool never edits the gate.
"""
import os
import sys

import c6_visual_calibration as cal

CEILING = 0.02
DEFECTS = ('shift_1px', 'delete_band', 'underline_4px')
NORMS = (
    ('raw', ()),
    ('blur0.5', ('-blur', '0x0.5')),
    ('blur1', ('-blur', '0x1')),
    ('blur1.5', ('-blur', '0x1.5')),
    ('blur2', ('-blur', '0x2')),
    ('resize50', ('-resize', '50%')),
    ('resize25', ('-resize', '25%')),
    ('blur1-resize50', ('-blur', '0x1', '-resize', '50%')),
)


def notice(title, lines):
    text = '\n'.join(lines)
    for start in range(0, max(len(text), 1), 3000):
        chunk = (text[start:start + 3000]
                 .replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A'))
        print(f'::notice title={title}::{chunk}')


def apply_norm(convert, source, target, ops):
    if not ops:
        if os.path.abspath(source) != os.path.abspath(target):
            cal.run([convert, source, target])
        return target
    cal.run([convert, source, *ops, target])
    return target


def candidate(floor, gate, same_defects, cross_defects, ceiling=CEILING):
    """A method may be reported only if identical content passes and every
    required defect still fails, on every page, for both same-image and
    cross-renderer injections.
    """
    reasons = []
    if any(value > ceiling for value in floor.values()):
        reasons.append('floor above ceiling')
    for name, value in {**same_defects, **cross_defects}.items():
        if value <= ceiling:
            reasons.append(f'{name} not detected')
    return {
        'acceptable': not reasons,
        'reasons': reasons,
        'floor_max': max(floor.values()) if floor else None,
        'gate_max': max(gate.values()) if gate else None,
    }


def main(argv=None):
    artifacts = (argv or sys.argv[1:])[0]
    compare = cal.which('compare')
    convert = cal.which('convert', 'magick')
    pdftoppm = cal.which('pdftoppm')
    mutool = cal.which('mutool')
    if not (compare and convert and pdftoppm and mutool):
        print('::warning title=C6 fair compare::needs compare, convert, '
              'pdftoppm, and mutool; not measured')
        return 2
    vector = os.path.join(artifacts, 'vector.pdf')
    previews = sorted(
        os.path.join(artifacts, name) for name in os.listdir(artifacts)
        if name.startswith('preview_page_') and name.endswith('.png'))
    if not (os.path.exists(vector) and previews):
        print('::warning title=C6 fair compare::artifacts missing')
        return 2

    out = os.path.join(artifacts, 'c6diag', 'fair_compare')
    os.makedirs(out, exist_ok=True)
    width, height = cal.image_size(previews[0])
    poppler = cal.render_poppler(pdftoppm, vector, os.path.join(out, 'poppler'))
    other = cal.render_mupdf(mutool, vector, os.path.join(out, 'mupdf'))
    pages = []
    for index, (left, right, preview) in enumerate(zip(poppler, other, previews), 1):
        pop = cal.gate_shaped(convert, left, os.path.join(out, f'p{index}-pop.png'),
                              width, height)
        mup = cal.gate_shaped(convert, right, os.path.join(out, f'p{index}-mup.png'),
                              width, height)
        ref = cal.gate_shaped(convert, preview, os.path.join(out, f'p{index}-ref.png'),
                              width, height)
        defects = {}
        for kind in DEFECTS:
            defects[kind] = cal.perturb(
                convert, ref, os.path.join(out, f'p{index}-{kind}.png'), kind,
                *cal.image_size(ref))
        # A content shift on the poppler side, compared with the other
        # rasterizer: the defect the gate would have to see.
        defects['cross_shift_1px'] = cal.perturb(
            convert, pop, os.path.join(out, f'p{index}-cross-shift.png'),
            'shift_1px', *cal.image_size(pop))
        pages.append((index, pop, mup, ref, defects))

    header = (f'fair-compare search on vector.pdf sha256 {cal.sha256(vector)} '
              f'preview {width}x{height} dpi {cal.DPI} ceiling {CEILING} '
              f'(not adopted)')
    lines = [header, 'method floor_max gate_max shift delete underline cross_shift verdict']
    acceptable = []
    for name, ops in NORMS:
        floor, gate = {}, {}
        same, cross = {}, {}
        for index, pop, mup, ref, defects in pages:
            folder = os.path.join(out, name)
            os.makedirs(folder, exist_ok=True)
            npop = apply_norm(convert, pop, os.path.join(folder, f'p{index}-pop.png'), ops)
            nmup = apply_norm(convert, mup, os.path.join(folder, f'p{index}-mup.png'), ops)
            nref = apply_norm(convert, ref, os.path.join(folder, f'p{index}-ref.png'), ops)
            floor[index] = cal.rmse(compare, npop, nmup)
            gate[index] = cal.rmse(compare, npop, nref)
            for kind in DEFECTS:
                nd = apply_norm(convert, defects[kind],
                                os.path.join(folder, f'p{index}-{kind}.png'), ops)
                same[(index, kind)] = cal.rmse(compare, nref, nd)
            ncross = apply_norm(convert, defects['cross_shift_1px'],
                                os.path.join(folder, f'p{index}-cross.png'), ops)
            cross[index] = cal.rmse(compare, nmup, ncross)
        verdict = candidate(floor, gate, same, cross)
        mark = 'CANDIDATE' if verdict['acceptable'] else 'no'
        if verdict['acceptable']:
            acceptable.append(name)
        lines.append(
            f'{name} floor {verdict["floor_max"]:.4f} gate {verdict["gate_max"]:.4f} '
            + ' '.join(
                f'p{index}:{floor[index]:.4f}/{gate[index]:.4f}/'
                f'{same[(index, "shift_1px")]:.4f}/'
                f'{same[(index, "delete_band")]:.4f}/'
                f'{same[(index, "underline_4px")]:.4f}/'
                f'{cross[index]:.4f}'
                for index, *_ in pages)
            + f' {mark}')
        if not verdict['acceptable']:
            lines.append(f'  rejected: {", ".join(verdict["reasons"][:8])}')
    if acceptable:
        lines.append('CANDIDATES (not adopted, gate unchanged): ' + ', '.join(acceptable))
    else:
        lines.append('NO CANDIDATE. No tested normalisation passes identical '
                     'vector content at 0.02 and still rejects shift, deletion, '
                     'and underline movement. Gate and ceiling unchanged.')
    notice('C6 fair compare', lines)
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        import traceback
        traceback.print_exc()
        print(f'::warning title=C6 fair compare::failed: {type(error).__name__}: {error}')
        sys.exit(2)
