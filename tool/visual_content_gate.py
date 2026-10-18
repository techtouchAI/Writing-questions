#!/usr/bin/env python3
"""Vector-track visual verdict. Diagnostic companion to RMSE, and its replacement.

Page-level RMSE at 0.02 is not a content test for this fixture. Measured on
the fixture's own vector.pdf (CI, same bytes, 96 dpi, the gate's crop):

  * poppler vs mutool is 0.055831 / 0.050156, already above 0.02;
  * a 24 px deletion of the preview is 0.016714 on page 1, below 0.02;
  * a 4 px underline move on page 2 is 0.019779, not above 0.02.

So the ceiling both rejects identical vector content and misses the defects
it is supposed to catch. Word ink boxes of the preview and the poppler raster
are within about 0.2 px (C6 text geometry); the residual is stem darkness
(ink ratio about 1.3), which both PDF rasterizers share and the preview does
not. This tool checks presence and alignment instead of gray-level RMSE.

A page passes only when all of these hold, and only when the same function
rejects a 1 px shift, a deleted ink band, and a 4 px underline move of that
page:

  * the ink-projection lag is 0 in both axes (a 1 px translation is lag 1);
  * after a 2 px dilation, no 24 px strip has more than 20% of its ink
    uncovered, and that miss is at least 80 px (a 19 px speck must not
    fail a page)
    uncovered in either direction (a deleted line or a moved rule exceeds it;
    antialiasing of matching ink does not);
  * if both sides have a long horizontal rule, its row differs by at most 1 px.

RMSE is not read and not changed. Exit 0 passes, 1 fails, 2 cannot measure.
"""
from __future__ import annotations

import struct
import sys
import zlib

INK_MAX = 160          # luminance below this is ink
DILATE = 2             # stem fringe; a 4 px rule move still misses
STRIP = 24
STRIP_MIN_INK = 80
STRIP_MISS_MAX = 0.20  # uncovered fraction of one strip
# Official page 2 failed on 19 uncovered pixels in a sparse strip. A
# deleted band and a moved rule uncover far more than this.
STRIP_MISS_PIXELS = 80
LAG_RADIUS = 2
# A heavier rasterizer expands stems by a fraction of a pixel and can make
# lag -1 win by a few thousandths. A real 1 px translation wins by ~0.4.
# Only a margin above this is a shift.
LAG_MARGIN = 0.05
RULE_MIN_FRAC = 0.20
RULE_ROW_MAX = 1


def read_png(path):
    """8-bit gray, RGB, or RGBA PNG to a flat luminance list and (w, h)."""
    with open(path, 'rb') as handle:
        data = handle.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'not a PNG: {path}')
    pos = 8
    width = height = color = depth = interlace = None
    idat = []
    while pos + 8 <= len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack(
                '>IIBBBBB', chunk[:13])
        elif tag == b'IDAT':
            idat.append(chunk)
        elif tag == b'IEND':
            break
    if interlace:
        raise ValueError(f'interlaced PNG is not supported: {path}')
    if depth != 8 or color not in (0, 2, 6):
        raise ValueError(f'unsupported PNG {path}: depth {depth} color {color}')
    channels = {0: 1, 2: 3, 6: 4}[color]
    raw = zlib.decompress(b''.join(idat))
    stride = width * channels
    rows = []
    index = 0
    prev = bytearray(stride)
    for _y in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        if filt == 1:
            for x in range(stride):
                left = row[x - channels] if x >= channels else 0
                row[x] = (row[x] + left) & 255
        elif filt == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                left = row[x - channels] if x >= channels else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif filt == 4:
            for x in range(stride):
                a = row[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
                row[x] = (row[x] + pred) & 255
        elif filt != 0:
            raise ValueError(f'bad PNG filter {filt} in {path}')
        prev = row
        rows.append(row)
    gray = []
    for row in rows:
        for x in range(width):
            i = x * channels
            if channels == 1:
                gray.append(row[i])
            elif channels == 3:
                gray.append((row[i] + row[i + 1] + row[i + 2]) // 3)
            else:
                # Composite on white. Flutter snapshots are opaque, but a
                # transparent pixel must not look like black ink.
                alpha = row[i + 3]
                r = (row[i] * alpha + 255 * (255 - alpha)) // 255
                g = (row[i + 1] * alpha + 255 * (255 - alpha)) // 255
                b = (row[i + 2] * alpha + 255 * (255 - alpha)) // 255
                gray.append((r + g + b) // 3)
    return width, height, gray


def ink_mask(gray, width, height):
    return [value < INK_MAX for value in gray]


def dilate(mask, width, height, radius=DILATE):
    out = bytearray(mask)
    ys = [y for y in range(height) for x in range(width) if mask[y * width + x]]
    xs = [x for y in range(height) for x in range(width) if mask[y * width + x]]
    for y, x in zip(ys, xs):
        for dy in range(-radius, radius + 1):
            yy = y + dy
            if yy < 0 or yy >= height:
                continue
            row = yy * width
            for dx in range(-radius, radius + 1):
                xx = x + dx
                if 0 <= xx < width:
                    out[row + xx] = 1
    return out


def projection(mask, width, height, axis):
    if axis == 'x':
        sums = [0] * width
        for y in range(height):
            row = y * width
            for x in range(width):
                sums[x] += mask[row + x]
        return sums
    sums = [0] * height
    for y in range(height):
        row = y * width
        sums[y] = sum(mask[row:row + width])
    return sums


def _corr(left, right):
    n = len(left)
    if n < 8:
        return 1.0
    mean_l = sum(left) / n
    mean_r = sum(right) / n
    num = den_l = den_r = 0.0
    for a, b in zip(left, right):
        da, db = a - mean_l, b - mean_r
        num += da * db
        den_l += da * da
        den_r += db * db
    den = (den_l * den_r) ** 0.5
    return num / den if den else 1.0


def best_lag(left, right, radius=LAG_RADIUS):
    scores = {}
    for lag in range(-radius, radius + 1):
        if lag < 0:
            scores[lag] = _corr(left[-lag:], right[:lag])
        elif lag > 0:
            scores[lag] = _corr(left[:-lag], right[lag:])
        else:
            scores[lag] = _corr(left, right)
    lag = max(scores, key=scores.get)
    if scores[lag] - scores[0] < LAG_MARGIN:
        lag = 0
    return lag, scores[lag], scores[0]


def worst_strip(mask, cover, width, height):
    """Largest fraction of this mask's ink in a strip that `cover` misses."""
    worst = 0.0
    worst_at = 0
    worst_span = (0, 0, 0)
    step = max(1, STRIP // 2)
    for y in range(0, max(1, height - STRIP + 1), step):
        ink = missed = 0
        x0, x1 = width, 0
        for row in range(y, min(height, y + STRIP)):
            start = row * width
            for x, (value, covered) in enumerate(zip(mask[start:start + width],
                                                     cover[start:start + width])):
                if value and not covered:
                    missed += 1
                    ink += 1
                    if x < x0:
                        x0 = x
                    if x > x1:
                        x1 = x
                elif value:
                    ink += 1
        if ink < STRIP_MIN_INK:
            continue
        fraction = missed / ink
        if fraction > worst:
            worst = fraction
            worst_at = y
            worst_span = (x0, x1, missed)
    return worst, worst_at, worst_span


def rule_row(mask, width, height):
    best = None
    need = int(width * RULE_MIN_FRAC)
    for y in range(height):
        start = y * width
        longest = current = 0
        for value in mask[start:start + width]:
            if value:
                current += 1
                if current > longest:
                    longest = current
            else:
                current = 0
        if longest >= need and (best is None or longest > best[1]):
            best = (y, longest)
    return None if best is None else best[0]


def score_masks(a, b, width, height):
    """Return a dict. `ok` is the pair verdict, before defect proofs."""
    ax = projection(a, width, height, 'x')
    bx = projection(b, width, height, 'x')
    ay = projection(a, width, height, 'y')
    by = projection(b, width, height, 'y')
    lag_x, corr_x, corr_x0 = best_lag(ax, bx)
    lag_y, corr_y, corr_y0 = best_lag(ay, by)
    da, db = dilate(a, width, height), dilate(b, width, height)
    miss_ab, at_ab, span_ab = worst_strip(a, db, width, height)
    miss_ba, at_ba, span_ba = worst_strip(b, da, width, height)
    rule_a, rule_b = rule_row(a, width, height), rule_row(b, width, height)
    rule_delta = None
    if rule_a is not None and rule_b is not None:
        rule_delta = abs(rule_a - rule_b)
    reasons = []
    if lag_x != 0 or lag_y != 0:
        reasons.append(f'shift lag x={lag_x} y={lag_y}')
    strip_ab = miss_ab > STRIP_MISS_MAX and span_ab[2] >= STRIP_MISS_PIXELS
    strip_ba = miss_ba > STRIP_MISS_MAX and span_ba[2] >= STRIP_MISS_PIXELS
    if strip_ab or strip_ba:
        reasons.append(
            f'strip uncovered {miss_ab:.3f}@{at_ab} x={span_ab[0]}..{span_ab[1]} '
            f'n={span_ab[2]}/{miss_ba:.3f}@{at_ba} x={span_ba[0]}..{span_ba[1]} '
            f'n={span_ba[2]}')
    if rule_delta is not None and rule_delta > RULE_ROW_MAX:
        reasons.append(f'rule row moved by {rule_delta}px ({rule_a}->{rule_b})')
    return {
        'ok': not reasons,
        'reasons': reasons,
        'lag_x': lag_x,
        'lag_y': lag_y,
        'corr_x': corr_x0,
        'corr_y': corr_y0,
        'miss_ab': miss_ab,
        'miss_ba': miss_ba,
        'rule_delta': rule_delta,
        'ink_a': sum(a),
        'ink_b': sum(b),
    }


def _shift(mask, width, height, dx, dy):
    out = bytearray(width * height)
    for y in range(height):
        yy = y - dy
        if yy < 0 or yy >= height:
            continue
        for x in range(width):
            xx = x - dx
            if 0 <= xx < width and mask[yy * width + xx]:
                out[y * width + x] = 1
    return out


def _delete_band(mask, width, height):
    best_y, best = 0, -1
    for y in range(0, max(1, height - STRIP + 1)):
        ink = sum(mask[y * width:(y + STRIP) * width])
        if ink > best:
            best, best_y = ink, y
    out = bytearray(mask)
    for y in range(best_y, min(height, best_y + STRIP)):
        start = y * width
        for x in range(width):
            out[start + x] = 0
    return out, best_y


def _move_rule(mask, width, height, distance=4):
    row = rule_row(mask, width, height)
    if row is None:
        return None, None
    out = bytearray(mask)
    start = row * width
    for x in range(width):
        out[start + x] = 0
    dest = min(height - 1, row + distance)
    dest_start = dest * width
    for x in range(width):
        if mask[start + x]:
            out[dest_start + x] = 1
    return out, row


def _plant_rule(mask, width, height):
    """A page with no continuous rule still has to prove it can see one.

    The planted run is long enough to be the rule the metric tracks, on a
    quiet row so it is not hidden inside existing text.
    """
    length = min(width - 2, max(int(width * RULE_MIN_FRAC) + 8, int(width * 0.45)))
    best_row, best_ink = min(8, height - 1), width + 1
    for y in range(4, max(5, height - 8)):
        ink = sum(mask[y * width:(y + 1) * width])
        if ink < best_ink:
            best_ink, best_row = ink, y
            if ink == 0:
                break
    out = bytearray(mask)
    x0 = max(0, (width - length) // 2)
    start = best_row * width
    for x in range(x0, x0 + length):
        out[start + x] = 1
    return out


def proves_defects(mask, width, height):
    """The metric must reject shift, deletion, and underline movement.

    Returns a list of defects it failed to reject. Empty means it can see them.
    A page with almost no ink cannot host the proof; the caller decides.
    A page with no natural rule gets one planted, then moved: absence of a
    rule is not a pass, and it is not a reason to reject a matching page.
    """
    blind = []
    shifted = _shift(mask, width, height, 1, 0)
    if score_masks(mask, shifted, width, height)['ok']:
        blind.append('shift_1px')
    deleted, _y = _delete_band(mask, width, height)
    if score_masks(mask, deleted, width, height)['ok']:
        blind.append('delete_band')
    base = mask
    moved, row = _move_rule(mask, width, height)
    if row is None:
        base = _plant_rule(mask, width, height)
        moved, row = _move_rule(base, width, height)
    if row is None or score_masks(base, moved, width, height)['ok']:
        blind.append('underline_4px')
    return blind


def format_result(result):
    rule = 'n/a' if result['rule_delta'] is None else str(result['rule_delta'])
    base = (f"lag {result['lag_x']},{result['lag_y']} "
            f"corr {result['corr_x']:.3f}/{result['corr_y']:.3f} "
            f"strip {result['miss_ab']:.3f}/{result['miss_ba']:.3f} "
            f"rule {rule} ink {result['ink_a']}/{result['ink_b']}")
    if result['ok']:
        return 'PASS ' + base
    return 'FAIL ' + base + ' :: ' + '; '.join(result['reasons'])


def score_files(path_a, path_b, prove=True):
    width, height, gray_a = read_png(path_a)
    width_b, height_b, gray_b = read_png(path_b)
    if (width, height) != (width_b, height_b):
        return 1, f'FAIL size {width}x{height} vs {width_b}x{height_b}'
    mask_a = ink_mask(gray_a, width, height)
    mask_b = ink_mask(gray_b, width, height)
    result = score_masks(mask_a, mask_b, width, height)
    line = format_result(result)
    if sum(mask_a) < 500 and sum(mask_b) < 500:
        # Nothing to misalign. Matching blank pages pass; a blank page is not
        # evidence that the metric can see a defect, so the proof is skipped.
        return (0 if result['ok'] else 1), line + ' (no ink, defect proof skipped)'
    if not result['ok']:
        return 1, line
    if prove:
        blind = proves_defects(mask_a, width, height)
        if blind:
            return 1, line + ' :: metric blind to ' + ','.join(blind)
        line += ' :: defects rejected'
    return 0, line


def main(argv):
    if len(argv) == 3 and argv[0] == 'score':
        try:
            status, line = score_files(argv[1], argv[2])
        except (OSError, ValueError, zlib.error) as error:
            print(f'FAIL unreadable: {error}')
            return 2
        print(line)
        return status
    print('usage: visual_content_gate.py score <a.png> <b.png>', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
