"""[C6-DIAG-12] Outline-aware other-drawing mask for the rule-geometry diagnostic (DIAG-9).

Diagnostic only. It is not called by the CI diagnostic step and does not change the
DIAG-9 output. DIAG-9 currently removes each non-rule drawing's whole bounding box from
the clean along-rule columns. On real page 1 that leaves no clean column (clean_cols=0
on every rule), because the boxes of 35 and 4 drawings cover the rule bands.

This module keeps the same rule classification but removes only what the drawing
actually paints, on the canonical transform, with a 1 px margin:

  * a stroked line or stroked rectangle edge: its centre line, widened by half the
    stroke width plus 1 px;
  * a filled rectangle: its outline, plus its interior only when the fill is not white.
    A white fill does not change the background the rule coverage is measured against;
  * a curve or any other item: its bounding box, as before. These are counted as
    `fallback_bbox` so they are visible, not hidden.

A rule item (the same test as extract_rules) is never part of the mask.
The function returns the mask and the counts. It never changes a validity condition.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import diag_c6_rule_geometry as rg  # noqa: E402

SAMPLE_PX = 0.25  # spacing of points along a segment, device px
MARGIN_PX = 1  # added to every footprint


def _is_white(col):
    return col is not None and len(col) >= 3 and all(float(c) >= 0.99 for c in col[:3])


def line_rule_orient(p1, p2, width):
    """Same test as rg._line_rule: 'h', 'v' or None."""
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    if abs(dy) < 1e-3 and abs(dx) >= rg.MIN_LEN and width <= rg.MAX_THICK:
        return "h"
    if abs(dx) < 1e-3 and abs(dy) >= rg.MIN_LEN and width <= rg.MAX_THICK:
        return "v"
    return None


def classify_items(d):
    """Split one drawing into rule items (same decisions as extract_rules) and footprint items.

    Returns (n_rules, segments, fills, bboxes):
      segments: (p1, p2, halfwidth_pt) centre lines to widen by halfwidth;
      fills: (x0, y0, x1, y1) interiors painted with a non-white fill;
      bboxes: (x0, y0, x1, y1) for items without an exact footprint (curves, quads, polygons).
    """
    stroke = d.get("color") is not None and d.get("width") is not None
    fill_col = d.get("fill")
    paints_interior = fill_col is not None and not _is_white(fill_col)
    n_rules = 0
    segments, fills, bboxes = [], [], []
    has_rect = False
    has_poly = False
    for it in d["items"]:
        op = it[0]
        if op == "l":
            has_poly = True
            p1, p2 = (it[1].x, it[1].y), (it[2].x, it[2].y)
            if stroke:
                w = float(d["width"])
                if line_rule_orient(p1, p2, w):
                    n_rules += 1
                    continue
                segments.append((p1, p2, w / 2.0))
            else:
                segments.append((p1, p2, 0.0))
        elif op == "re":
            has_rect = True
            r = it[1]
            if stroke:
                t = float(d["width"])
                edges = (
                    ("h", r.y0, r.x0, r.x1),
                    ("h", r.y1, r.x0, r.x1),
                    ("v", r.x0, r.y0, r.y1),
                    ("v", r.x1, r.y0, r.y1),
                )
                for o, a, s0, s1 in edges:
                    if s1 - s0 >= rg.MIN_LEN and t <= rg.MAX_THICK:
                        n_rules += 1
                        continue
                    p1, p2 = ((s0, a), (s1, a)) if o == "h" else ((a, s0), (a, s1))
                    segments.append((p1, p2, t / 2.0))
                if paints_interior:
                    fills.append((r.x0, r.y0, r.x1, r.y1))
            elif fill_col is not None:
                thin_h = r.height <= rg.MAX_THICK and r.width >= rg.MIN_LEN
                thin_v = r.width <= rg.MAX_THICK and r.height >= rg.MIN_LEN
                if thin_h or thin_v:
                    n_rules += 1
                    continue
                segments += [((r.x0, r.y0), (r.x1, r.y0), 0.0), ((r.x1, r.y0), (r.x1, r.y1), 0.0),
                             ((r.x1, r.y1), (r.x0, r.y1), 0.0), ((r.x0, r.y1), (r.x0, r.y0), 0.0)]
                if paints_interior:
                    fills.append((r.x0, r.y0, r.x1, r.y1))
        else:
            # Curves, quads and any other item: bounding box of its points (conservative).
            pts = []
            for p in it[1:]:
                if hasattr(p, "x"):
                    pts.append((p.x, p.y))
                elif hasattr(p, "rect"):  # Quad
                    rr = p.rect
                    pts += [(rr.x0, rr.y0), (rr.x1, rr.y1)]
                elif hasattr(p, "x0"):
                    pts += [(p.x0, p.y0), (p.x1, p.y1)]
            if pts:
                has_poly = True
                xs = [q[0] for q in pts]
                ys = [q[1] for q in pts]
                bboxes.append((min(xs), min(ys), max(xs), max(ys)))
    # A filled polygon (not a rectangle) paints its interior, which is not known exactly here.
    # Use the path bounding box as a conservative fallback and count it.
    if paints_interior and has_poly and not has_rect and d.get("rect") is not None:
        rr = d["rect"]
        bboxes.append((rr.x0, rr.y0, rr.x1, rr.y1))
    return n_rules, segments, fills, bboxes


def _stamp_points(m, p1, p2, sx, sy):
    """Mark the device pixels crossed by a segment (canonical transform, device px)."""
    x1, y1 = p1[0] * sx, p1[1] * sy
    x2, y2 = p2[0] * sx, p2[1] * sy
    length = math.hypot(x2 - x1, y2 - y1)
    n = max(int(length / SAMPLE_PX) + 1, 1)
    t = np.linspace(0.0, 1.0, n)
    xs = x1 + (x2 - x1) * t
    ys = y1 + (y2 - y1) * t
    h, w = m.shape
    ix = np.clip(np.floor(xs).astype(int), 0, w - 1)
    iy = np.clip(np.floor(ys).astype(int), 0, h - 1)
    m[iy, ix] = True


def _dilate_square(m, r):
    """Square dilation by r pixels using shifted ORs (r small)."""
    if r <= 0:
        return m.copy()
    out = m.copy()
    h, w = m.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy == 0 and dx == 0:
                continue
            ys = slice(max(dy, 0), h + min(dy, 0))
            yd = slice(max(-dy, 0), h + min(-dy, 0))
            xs = slice(max(dx, 0), w + min(dx, 0))
            xd = slice(max(-dx, 0), w + min(-dx, 0))
            out[ys, xs] |= m[yd, xd]
    return out


def _box(m, x0, y0, x1, y1, sx, sy, margin=0):
    a = max(int(math.floor(x0 * sx)) - margin, 0)
    b = min(int(math.ceil(x1 * sx)) + margin, m.shape[1])
    c = max(int(math.floor(y0 * sy)) - margin, 0)
    e = min(int(math.ceil(y1 * sy)) + margin, m.shape[0])
    if b > a and e > c:
        m[c:e, a:b] = True


def outline_other_mask(page, shape, scales):
    """Footprint of all non-rule drawings on the canonical transform. Returns (mask, stats).

    `shape` is the full-frame raster (H, W). `scales` = {"sx": W/pw, "sy": H/ph}, as in DIAG-9.
    The mask is the union of: segment footprints (each widened by its own half stroke width
    plus MARGIN_PX), rectangle outlines and non-white interiors, and bounding boxes of items
    without an exact footprint (counted in stats["fallback_bbox"]).
    """
    sx, sy = scales["sx"], scales["sy"]
    stats = {"drawings": 0, "rule_items": 0, "segments": 0, "fill_interiors": 0, "fallback_bbox": 0}
    by_radius = {}  # radius in px -> centre-line mask
    m_box = np.zeros(shape, dtype=bool)
    for d in page.get_drawings():
        stats["drawings"] += 1
        n_rules, segs, fills, bboxes = classify_items(d)
        stats["rule_items"] += n_rules
        for p1, p2, hw in segs:
            stats["segments"] += 1
            r = int(math.ceil(hw * max(sx, sy))) + MARGIN_PX
            if r not in by_radius:
                by_radius[r] = np.zeros(shape, dtype=bool)
            _stamp_points(by_radius[r], p1, p2, sx, sy)
        for x0, y0, x1, y1 in fills:
            stats["fill_interiors"] += 1
            _box(m_box, x0, y0, x1, y1, sx, sy, MARGIN_PX)
        for x0, y0, x1, y1 in bboxes:
            stats["fallback_bbox"] += 1
            _box(m_box, x0, y0, x1, y1, sx, sy, MARGIN_PX)  # same 1 px margin as DIAG-9 boxes
    mask = m_box.copy()
    for r, m in by_radius.items():
        mask |= _dilate_square(m, r)
    stats["radii_px"] = sorted(by_radius)
    return mask, stats


def clean_columns(contaminated, row_lo, row_hi, col_lo, col_hi):
    """Columns in [col_lo, col_hi) with no contaminated pixel in rows [row_lo, row_hi]. Count."""
    band = contaminated[row_lo : row_hi + 1, col_lo:col_hi]
    return int((~band.any(axis=0)).sum())


# ----------------------------------------------------------------- synthetic report

PW, PH = 595.28, 841.89
RULE_Y, RULE_X0, RULE_X1 = 300.0, 100.0, 400.0


# Expected clean columns, derived from the geometry BEFORE the run (not from the output).
# span: c0 = floor(100*sx)+END_TRIM = 139, c1 = ceil(400*sx)-END_TRIM = 528 -> 389 columns.
# A 5 pt stroke: half width 3.33 px, footprint radius 5 px -> 11 columns per line.
EXPECTED_SPAN = 389


def _case_pages():
    """(name, builder(page), expected_clean_outline, expected_clean_bbox_method, expected_note).

    expected_* are clean columns in the rule span and band. None means "not asserted".
    """
    import pymupdf

    def rule(p):
        p.draw_line((RULE_X0, RULE_Y), (RULE_X1, RULE_Y), color=(0, 0, 0), width=0.8)

    def c1(p):
        rule(p)
        p.draw_polyline([(50, 250), (50, 320), (420, 320)], color=(0, 0, 0), width=5)

    def c2(p):
        rule(p)
        p.draw_rect(pymupdf.Rect(90, 290, 410, 310), color=None, fill=(1, 1, 1))

    def c3(p):
        rule(p)
        p.draw_rect(pymupdf.Rect(90, 290, 410, 310), color=None, fill=(0.9, 0.9, 0.9))

    def hollow(p):
        rule(p)
        p.draw_rect(pymupdf.Rect(200, 250, 260, 350), color=(0, 0, 0), width=5)

    def c5(p):
        rule(p)
        p.draw_bezier((150, 260), (200, 330), (250, 260), (300, 330), color=(0, 0, 0), width=0.5)

    def c6(p):
        rule(p)
        p.draw_line((100, 500), (400, 500), color=(0, 0, 0), width=0.6)

    def c7(p):
        p.insert_text((100, 300), "Text near the band", fontname="helv", fontsize=12)

    def s1(p):
        rule(p)
        p.draw_line((200, 250), (200, 350), color=(0, 0, 0), width=5)

    def s2(p):
        rule(p)
        p.draw_line((200, 250), (200, 350), color=(0, 0, 0), width=5)
        p.draw_line((150, 280), (250, 280), color=(0, 0, 0), width=5)

    def s3(p):
        rule(p)
        p.draw_line((200, 250), (200, 350), color=(0, 0, 0), width=5)
        p.draw_line((204, 250), (204, 350), color=(0, 0, 0), width=5)

    def s4(p):
        rule(p)
        p.draw_line((100, 250), (100, 350), color=(0, 0, 0), width=5)

    return [
        ("C1 L-shape, bbox covers band", c1, 389, 0),
        ("C2 white fill over band", c2, 389, 0),
        ("C3 grey fill over band", c3, 0, 0),
        ("C4 hollow thick rect, centre empty", hollow, 367, 306),
        ("C5 curve (bbox fallback)", c5, 186, 186),
        ("C6 rules only", c6, 389, 389),
        ("C7 text only", c7, 389, 389),
        ("S1 single thick line across band", s1, 378, None),
        ("S2 two thick lines crossing", s2, 378, None),
        ("S3 two thick lines overlapping", s3, 372, None),
        ("S4 thick line adjacent, outside span", s4, 389, None),
    ]


def synthetic_report(out_dir):
    """Run the cases; write a table with expected and observed values. Returns (rows, lines)."""
    import pymupdf

    os.makedirs(out_dir, exist_ok=True)
    rows = []
    scales = {"sx": rg.W / PW, "sy": rg.H / PH}
    for name, build, exp_outline, exp_bbox in _case_pages():
        d = pymupdf.open()
        p = d.new_page(width=PW, height=PH)
        build(p)
        mask, st = outline_other_mask(p, (rg.H, rg.W), scales)
        _, other = rg.extract_rules(p)
        bbox_m, _, _ = rg.base_contamination((rg.H, rg.W), [], list(other), scales, parts=True)
        centre = RULE_Y * rg.H / PH
        lo, hi = int(np.floor(centre)) - rg.BAND, int(np.floor(centre)) + rg.BAND
        c0 = int(np.floor(RULE_X0 * rg.W / PW)) + rg.END_TRIM
        c1 = int(np.ceil(RULE_X1 * rg.W / PW)) - rg.END_TRIM
        obs_outline = clean_columns(mask, lo, hi, c0, c1)
        obs_bbox = clean_columns(bbox_m, lo, hi, c0, c1)
        rows.append(
            {
                "case": name,
                "span_cols": c1 - c0,
                "expected_outline": exp_outline,
                "observed_outline": obs_outline,
                "expected_bbox": exp_bbox,
                "observed_bbox": obs_bbox,
                "pass": (obs_outline == exp_outline) and (exp_bbox is None or obs_bbox == exp_bbox),
                "rule_items": st["rule_items"],
                "segments": st["segments"],
                "fill_interiors": st["fill_interiors"],
                "fallback_bbox": st["fallback_bbox"],
            }
        )
        d.close()
    lines = [
        "[C6-DIAG-12] outline-aware other-drawing mask, SYNTHETIC (not gate evidence)",
        f"span = {rows[0]['span_cols']} columns (expected {EXPECTED_SPAN}); band rows +/-{rg.BAND} px around the rule centre",
        f"{'case':40s} {'exp_out':>7s} {'obs_out':>7s} {'exp_bbox':>8s} {'obs_bbox':>8s} {'pass':>5s} {'rules':>5s} {'fill':>4s} {'fallbk':>6s}",
    ]
    for r in rows:
        eb = "-" if r["expected_bbox"] is None else str(r["expected_bbox"])
        lines.append(
            f"{r['case']:40s} {r['expected_outline']:7d} {r['observed_outline']:7d} {eb:>8s} {r['observed_bbox']:8d} "
            f"{'PASS' if r['pass'] else 'FAIL':>5s} {r['rule_items']:5d} {r['fill_interiors']:4d} {r['fallback_bbox']:6d}"
        )
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "outline_mask_synthetic.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return rows, lines


if __name__ == "__main__":
    _rows, _lines = synthetic_report(os.path.join("build", "visual_parity", "c6diag", "outline_mask"))
    print("\n".join(_lines))
