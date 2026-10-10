#!/usr/bin/env python3
"""[C6-DIAG-6] TEMPORARY diagnostic: text geometry vs coverage. Not for merge.

Question: is the dominant Preview-vs-Vector-PDF text residual a difference in
glyph/line GEOMETRY (size, advance, spacing, position), or in COVERAGE (how
dark the antialiased edges are, i.e. rasterisation and gamma)?

Method (diagnostic only; production files are never touched):
  1. Same render path as the gate: pdftoppm -r 96, convert -resize 794x1123!,
     crop 2 px. The exact point-to-pixel map is 794/page_width and
     1123/page_height (the resize stretches the page), NOT 4/3.
  2. Correspondence: one PDF word = one text object = one PyMuPDF word (the
     writer emits spaceless words). A word is compared only inside its own
     window (nominal box + PAD px). Words are excluded, with a reason, when the
     window touches another word, a drawing or an image, when the colour has no
     contrast, when ink reaches the window border, or when ink is too low.
     Nothing is excluded by how large its offset or ratio is.
  3. Coverage per pixel: alpha = projection of (pixel - background) on
     (ink colour - background), using the PDF span colour for BOTH sides.
  4. Geometry from coverage, separately from darkness: widths and heights at
     several coverage levels (0.25, 0.5, 0.75) with sub-pixel crossings, and
     the edges at level 0.5. Slant is not measured: a horizontal scale reads as
     slant under every shear fit tried (see the report).
     Edge bleed (darker antialiasing) adds the same offset at every level; a
     size change multiplies. So the pooled regression of PDF width on Preview
     width over levels separates slope (scale) from intercept (bleed).
  5. Controls: MuPDF direct and MuPDF 2x-supersampled renders of the same PDF
     (same geometry, different rasterisers). Their ratios show what
     rasterisation alone does to the same measurements.
  6. Glyph level: only Latin words whose ink splits into the same number of
     column runs on both sides. Arabic is cursive, so it is not split.

Never fails the job; errors become notices. Uses no fitted correction.
Usage: diag_c6_text_geometry.py <artifacts_dir>
"""
import json
import os
import sys
import traceback
from collections import Counter

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_pdf_frame as frame_diag  # noqa: E402  (notice helper only)
import diag_c6_text_residual as resid  # noqa: E402  (render and normalise helpers)

W, H = resid.W, resid.H  # 794 x 1123, the gate's reference size
CW, CH, CO = resid.CW, resid.CH, resid.CO  # 790 x 1119, crop 2 px
LEVELS = (0.25, 0.5, 0.75)
PAD = 3  # px around the nominal word box
MIN_INK = 2.0  # coverage sum a window must hold on each side
BORDER_MAX = 0.05  # coverage allowed on the window border ring
BOOT = 1000
SEED = 0


# ----------------------------------------------------------------- transforms


def transform(page_w_pt, page_h_pt):
    """Points to cropped gate pixels: the resize maps the page onto W x H."""
    return W / page_w_pt, H / page_h_pt


def to_crop(x_pt, y_pt, sx, sy):
    return x_pt * sx - CO, y_pt * sy - CO


def box_to_crop(box_pt, sx, sy):
    x0, y0 = to_crop(box_pt[0], box_pt[1], sx, sy)
    x1, y1 = to_crop(box_pt[2], box_pt[3], sx, sy)
    return (x0, y0, x1, y1)


def window_of(box, pad, shape):
    """Integer window (a, b, c, d) around a box in cropped pixels, or None if it leaves the image."""
    h, w = shape
    a = int(np.floor(box[0])) - pad
    b = int(np.ceil(box[2])) + pad
    c = int(np.floor(box[1])) - pad
    d = int(np.ceil(box[3])) + pad
    if a < 0 or c < 0 or b > w or d > h:
        return None
    return a, b, c, d


def boxes_touch(p, q, gap=0.0):
    return not (p[2] + gap <= q[0] or q[2] + gap <= p[0] or p[3] + gap <= q[1] or q[3] + gap <= p[1])


# ----------------------------------------------------------------- PDF words


def _script(text):
    if any("\u0600" <= ch <= "\u06ff" for ch in text):
        return "arabic"
    if any(("a" <= ch.lower() <= "z") for ch in text):
        return "latin"
    return "other"


def pdf_words(page):
    """Words as PyMuPDF's rawdict shows them: split at spaces, font and colour changes.

    Returns dicts with the nominal word box (pt), text, font, colour (0..1 RGB),
    script, and the (block, line) key used for line grouping.
    """
    words = []
    data = page.get_text("rawdict")
    for bi, block in enumerate(data["blocks"]):
        if block.get("type") != 0:
            continue
        for li, line in enumerate(block["lines"]):
            cur = None

            def flush():
                nonlocal cur
                if cur and cur["chars"]:
                    text = "".join(cur["chars"])
                    words.append(
                        {
                            "box_pt": tuple(cur["box"]),
                            "text": text,
                            "font": cur["font"],
                            "color": cur["color"],
                            "script": _script(text),
                            "line": (bi, li),
                        }
                    )
                cur = None

            for span in line["spans"]:
                key = (span["font"], span["color"])
                for ch in span["chars"]:
                    if ch["c"].isspace():
                        flush()
                        continue
                    if cur is None or cur["key"] != key:
                        flush()
                        c = span["color"]
                        cur = {
                            "key": key,
                            "chars": [],
                            "box": list(ch["bbox"]),
                            "font": span["font"],
                            "color": (
                                ((c >> 16) & 255) / 255.0,
                                ((c >> 8) & 255) / 255.0,
                                (c & 255) / 255.0,
                            ),
                        }
                    cur["chars"].append(ch["c"])
                    b = ch["bbox"]
                    cur["box"] = [min(cur["box"][0], b[0]), min(cur["box"][1], b[1]), max(cur["box"][2], b[2]), max(cur["box"][3], b[3])]
            flush()
    return words


def page_boxes_pt(page):
    """Drawings and images in pt. Drawings covering more than half the page are page
    backgrounds, not content; they are counted but not used as exclusions."""
    page_area = page.rect.width * page.rect.height
    drawings, backgrounds = [], 0
    for d in page.get_drawings():
        r = d.get("rect")
        if r is None:
            continue
        if r.width * r.height > 0.5 * page_area:
            backgrounds += 1
            continue
        drawings.append(tuple(r))
    images = [tuple(info["bbox"]) for info in page.get_image_info()]
    return drawings, images, backgrounds


# ----------------------------------------------------------------- coverage


def load_float(samples_u8):
    return samples_u8.astype(np.float64) / 255.0


def coverage(rgb, bg, fg):
    """Per-pixel alpha in 0..1 for ink fg on background bg. None if no contrast."""
    vec = fg - bg
    den = float(vec @ vec)
    if den < 1e-3:
        return None
    a = ((rgb - bg) @ vec) / den
    return np.clip(a, 0.0, 1.0)


def ring_median(rgb):
    ring = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]], axis=0)
    return np.median(ring, axis=0)


def ring_cov_max(rgb, bg, fg):
    cov = coverage(rgb, bg, fg)
    if cov is None:
        return None
    ring = np.concatenate([cov[0], cov[-1], cov[:, 0], cov[:, -1]])
    return float(ring.max())


# ----------------------------------------------------------------- profiles


def runs_extent(profile, level):
    """Coverage runs above level along a 1-D profile, with sub-pixel edges.

    Pixel index i has its centre at i + 0.5. Returns (runs, touches_border):
    runs is a list of (left, right) in continuous coordinates. A run touching
    either end of the profile is flagged, because its edge is not inside the window.
    """
    p = np.asarray(profile, dtype=np.float64)
    n = len(p)
    above = p >= level
    if not above.any():
        return [], False
    starts = np.where(above & ~np.concatenate([[False], above[:-1]]))[0]
    ends = np.where(above & ~np.concatenate([above[1:], [False]]))[0]
    runs = []
    touches = False
    for s, e in zip(starts, ends):
        if s == 0 or e == n - 1:
            touches = True
            continue
        left = (s - 1) + (level - p[s - 1]) / (p[s] - p[s - 1]) + 0.5
        right = e + (p[e] - level) / (p[e] - p[e + 1]) + 0.5
        runs.append((float(left), float(right)))
    return runs, touches


def extent(profile, level):
    """(left, right) of the outermost run at level, or None if absent or touching the border."""
    runs, touches = runs_extent(profile, level)
    if not runs or touches:
        return None
    return runs[0][0], runs[-1][1]


def measure_side(cov, ox=0.0, oy=0.0):
    """Geometry and mass of one side's coverage in a window (None if not measurable).

    ox, oy: the window's top-left in cropped-image pixels. Centroids and edges
    are returned in image coordinates, so that different windows can be compared
    (line spacing); differences within one window are the same either way.
    """
    colmax = cov.max(axis=0)
    rowmax = cov.max(axis=1)
    out = {"w": {}, "h": {}}
    for lv in LEVELS:
        ex = extent(colmax, lv)
        ey = extent(rowmax, lv)
        out["w"][lv] = None if ex is None else ex[1] - ex[0]
        out["h"][lv] = None if ey is None else ey[1] - ey[0]
    total = float(cov.sum())
    xs = np.arange(cov.shape[1]) + 0.5
    ys = np.arange(cov.shape[0]) + 0.5
    out["ink"] = total
    out["peak"] = float(cov.max())
    out["cx"] = float((cov.sum(axis=0) * xs).sum() / total) + ox if total > 0 else None
    out["cy"] = float((cov.sum(axis=1) * ys).sum() / total) + oy if total > 0 else None
    # Edges at the 0.5 level (outermost run), for the translation/scale decomposition.
    ex = extent(colmax, 0.5)
    ey = extent(rowmax, 0.5)
    out["edges"] = None if (ex is None or ey is None) else (ex[0] + ox, ex[1] + ox, ey[0] + oy, ey[1] + oy)
    return out


def overhang(cov, box_win, thr=0.05):
    """Ink beyond the nominal box, per side, in px (window coordinates). None if no ink."""
    ys, xs = np.nonzero(cov > thr)
    if len(xs) == 0:
        return None
    x0, y0, x1, y1 = box_win
    return {
        "left": float(max(0.0, x0 - xs.min())),
        "right": float(max(0.0, (xs.max() + 1) - x1)),
        "top": float(max(0.0, y0 - ys.min())),
        "bottom": float(max(0.0, (ys.max() + 1) - y1)),
    }


def segments_of(cov, level=0.25):
    """Latin glyph candidates: column runs of ink at level, as (left, right) pairs."""
    runs, touches = runs_extent(cov.max(axis=0), level)
    if touches:
        return None
    return runs


def _centre_span(segs):
    if not segs:
        return None
    return (segs[-1][0] + segs[-1][1]) / 2.0 - (segs[0][0] + segs[0][1]) / 2.0


# ----------------------------------------------------------------- analysis


def analyse_pair(words, drawings_px, images_px, ref_rgb, sub_rgb, pad=PAD):
    """Measure each word on two renders of the same page in cropped pixels.

    words: dicts with box_px (cropped px), color (0..1), script, line, text, font.
    ref_rgb: reference render (the Preview in the real run), float 0..1, HxWx3.
    sub_rgb: render being compared (the PDF render), same shape.
    Returns (records, line_records, reasons).
    """
    shape = ref_rgb.shape[:2]
    records = []
    reasons = Counter()
    for i, wd in enumerate(words):
        rec = {"i": i, "font": wd["font"], "script": wd["script"], "line": wd["line"], "text": wd["text"]}
        box = wd["box_px"]
        why = None
        win = window_of(box, pad, shape)
        if win is None:
            why = "window_outside_image"
        else:
            a, b, c, d = win
            wbox = (a, c, b, d)
            # Neighbours: nominal boxes, not padded windows. Arabic word gaps are a few px,
            # so a padded test would exclude most words; neighbour ink that reaches this
            # word's window is caught by the pixel border check below.
            for j, other in enumerate(words):
                if j != i and boxes_touch(box, other["box_px"]):
                    why = "neighbour_word"
                    break
            if why is None and any(boxes_touch(wbox, box_to_crop_list(dr)) for dr in drawings_px):
                why = "non_text_drawing"
            if why is None and any(boxes_touch(wbox, box_to_crop_list(im)) for im in images_px):
                why = "image_overlap"
            if why is None and wd.get("color_contrast", True) is False:
                why = "colour_no_contrast"
        if why is None:
            a, b, c, d = win
            fg = np.array(wd["color"], dtype=np.float64)
            ref_w = ref_rgb[c:d, a:b]
            sub_w = sub_rgb[c:d, a:b]
            bg_r = ring_median(ref_w)
            bg_s = ring_median(sub_w)
            cr = coverage(ref_w, bg_r, fg)
            cs = coverage(sub_w, bg_s, fg)
            if cr is None or cs is None:
                why = "colour_no_contrast"
            else:
                mr = ring_cov_max(ref_w, bg_r, fg)
                ms = ring_cov_max(sub_w, bg_s, fg)
                local = (box[0] - a, box[1] - c, box[2] - a, box[3] - c)
                rec["over_ref_all"] = overhang(cr, local)
                rec["over_sub_all"] = overhang(cs, local)
                if mr > BORDER_MAX or ms > BORDER_MAX:
                    why = "ink_at_window_border"
                elif cr.sum() < MIN_INK or cs.sum() < MIN_INK:
                    why = "low_ink"
                else:
                    mref = measure_side(cr, a, c)
                    msub = measure_side(cs, a, c)
                    rec["ref"] = mref
                    rec["sub"] = msub
                    local = (box[0] - a, box[1] - c, box[2] - a, box[3] - c)
                    rec["over_ref"] = overhang(cr, local)
                    rec["over_sub"] = overhang(cs, local)
                    if wd["script"] == "latin":
                        sr = segments_of(cr)
                        ss = segments_of(cs)
                        if sr is None or ss is None or len(sr) != len(ss) or len(sr) < 2:
                            rec["glyph"] = None
                            rec["glyph_reason"] = "segment_count_mismatch_or_border"
                        else:
                            rec["glyph"] = {
                                "ref_w": [r[1] - r[0] for r in sr],
                                "sub_w": [s[1] - s[0] for s in ss],
                                "ref_span": _centre_span(sr),
                                "sub_span": _centre_span(ss),
                            }
                    else:
                        rec["glyph"] = None
                        rec["glyph_reason"] = "arabic_cursive_not_split"
        if why is not None:
            rec["excluded"] = why
            reasons[why] += 1
        else:
            rec["excluded"] = None
        records.append(rec)
    return records, reasons


def box_to_crop_list(box):
    return tuple(box)


def line_measures(records, words, ref_rgb, sub_rgb, pad=PAD):
    """Line-level measures, for lines whose words are all valid and whose union window is clean."""
    shape = ref_rgb.shape[:2]
    by_line = {}
    for rec in records:
        by_line.setdefault(rec["line"], []).append(rec)
    out = []
    for key, members in by_line.items():
        if any(m["excluded"] for m in members):
            continue
        boxes = [words[m["i"]]["box_px"] for m in members]
        union = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        win = window_of(union, pad, shape)
        if win is None:
            continue
        a, b, c, d = win
        # No word outside this line may touch the union of its boxes.
        others = [w for w in words if w["line"] != key]
        if any(boxes_touch(union, w["box_px"]) for w in others):
            continue
        # A line-level colour is only defined if all its words share one colour.
        colours = {words[m["i"]]["color"] for m in members}
        if len(colours) != 1:
            continue
        fg = np.array(next(iter(colours)), dtype=np.float64)
        ref_w = ref_rgb[c:d, a:b]
        sub_w = sub_rgb[c:d, a:b]
        bg_r = ring_median(ref_w)
        bg_s = ring_median(sub_w)
        cr = coverage(ref_w, bg_r, fg)
        cs = coverage(sub_w, bg_s, fg)
        if cr is None or cs is None:
            continue
        if ring_cov_max(ref_w, bg_r, fg) > BORDER_MAX or ring_cov_max(sub_w, bg_s, fg) > BORDER_MAX:
            continue
        out.append({"line": key, "ref": measure_side(cr, a, c), "sub": measure_side(cs, a, c), "n_words": len(members)})
    return out


def line_spacing(line_recs):
    """Centroid spacing between each valid line and the nearest line below it.

    Pairing is geometric, not by PyMuPDF block: a line is paired with the nearest
    line below whose horizontal extent overlaps by at least half of the narrower
    one. Pairs are counted; no gap cap is applied (line spacing is not known in advance).
    """
    items = []
    for lr in line_recs:
        ref, sub = lr["ref"], lr["sub"]
        if None in (ref["cy"], sub["cy"]) or not ref["edges"] or not sub["edges"]:
            continue
        items.append(lr)
    out = []
    for a in items:
        best = None
        ra = a["ref"]
        for b in items:
            rb = b["ref"]
            if rb["cy"] <= ra["cy"]:
                continue
            ax0, ax1 = ra["edges"][0], ra["edges"][1]
            bx0, bx1 = rb["edges"][0], rb["edges"][1]
            overlap = min(ax1, bx1) - max(ax0, bx0)
            if overlap < 0.5 * min(ax1 - ax0, bx1 - bx0):
                continue
            gap = rb["cy"] - ra["cy"]
            if best is None or gap < best[0]:
                best = (gap, b)
        if best is None:
            continue
        b = best[1]
        ds_ref = b["ref"]["cy"] - a["ref"]["cy"]
        ds_sub = b["sub"]["cy"] - a["sub"]["cy"]
        if ds_ref > 0:
            out.append({"ref": ds_ref, "sub": ds_sub, "ratio": ds_sub / ds_ref})
    return out


# ----------------------------------------------------------------- statistics


def _nanmedian(x):
    x = np.asarray(x, dtype=np.float64)
    x = x[np.isfinite(x)]
    return float(np.median(x)) if x.size else None


def boot_ci(rows, stat, seed=SEED, b=BOOT):
    """Percentile 95% CI for stat(rows) by resampling rows (words or lines)."""
    rows = np.asarray(rows)
    n = len(rows)
    if n < 3:
        return None, None, None
    rng = np.random.default_rng(seed)
    point = stat(rows)
    vals = []
    for _ in range(b):
        idx = rng.integers(0, n, n)
        v = stat(rows[idx])
        if v is not None and np.isfinite(v):
            vals.append(v)
    if not vals:
        return point, None, None
    lo, hi = np.percentile(vals, [2.5, 97.5])
    return float(point) if point is not None else None, float(lo), float(hi)


def regression(xs_ys):
    """OLS of y on x over pooled (x, y) pairs. Returns (slope, intercept, n)."""
    arr = np.asarray(xs_ys, dtype=np.float64)
    if arr.ndim != 2 or len(arr) < 3:
        return None
    x, y = arr[:, 0], arr[:, 1]
    vx = np.var(x)
    if vx <= 0:
        return None
    slope = float(np.cov(x, y, bias=True)[0, 1] / vx)
    return slope, float(y.mean() - slope * x.mean()), int(len(x))


def reg_boot(rows, kp, kv):
    """Pooled OLS of sub on ref over (word, level) pairs, with a bootstrap over words.

    Returns (slope, intercept, n, slope_lo, slope_hi, intercept_lo, intercept_hi).
    """
    mat = np.array([x[kp] + x[kv] for x in rows], dtype=np.float64)  # n x 6
    base = regression(_pairs(mat))
    if base is None:
        return None
    rng = np.random.default_rng(SEED)
    sl, ic = [], []
    for _ in range(BOOT):
        idx = rng.integers(0, len(mat), len(mat))
        r = regression(_pairs(mat[idx]))
        if r is not None:
            sl.append(r[0])
            ic.append(r[1])
    lo_s, hi_s = np.percentile(sl, [2.5, 97.5]) if sl else (None, None)
    lo_i, hi_i = np.percentile(ic, [2.5, 97.5]) if ic else (None, None)
    return base + (lo_s, hi_s, lo_i, hi_i)


def _pairs(mat):
    k = mat.shape[1] // 2
    ref = mat[:, :k].ravel()
    sub = mat[:, k:].ravel()
    ok = np.isfinite(ref) & np.isfinite(sub)
    return np.stack([ref[ok], sub[ok]], axis=1)


def overhang_summary(records):
    """Median ink overhang (px beyond the nominal box) per side, over all words with a window."""
    out = {}
    for side in ("ref", "sub"):
        vals = {k: [] for k in ("left", "right", "top", "bottom")}
        for r in records:
            o = r.get("over_" + side + "_all")
            if o:
                for k in vals:
                    vals[k].append(o[k])
        out[side] = {k: (_nanmedian(v), float(np.percentile(v, 95)) if v else None, len(v)) for k, v in vals.items()}
    return out


def summarise(records, line_recs, spacing, label):
    """Summary dict for one comparison. Ratios are sub / ref (PDF / Preview)."""
    valid = [r for r in records if r["excluded"] is None]
    s = {"label": label, "words_total": len(records), "words_valid": len(valid), "excluded": dict(Counter(r["excluded"] for r in records if r["excluded"]))}

    # Per word, at level 0.5: ratios and offsets.
    per = []
    for r in valid:
        ref, sub = r["ref"], r["sub"]
        row = {
            "script": r["script"],
            "font": r["font"],
            "w_ratio": (sub["w"][0.5] / ref["w"][0.5]) if ref["w"][0.5] and sub["w"][0.5] else np.nan,
            "h_ratio": (sub["h"][0.5] / ref["h"][0.5]) if ref["h"][0.5] and sub["h"][0.5] else np.nan,
            "dx": (sub["cx"] - ref["cx"]) if sub["cx"] is not None and ref["cx"] is not None else np.nan,
            "dy": (sub["cy"] - ref["cy"]) if sub["cy"] is not None and ref["cy"] is not None else np.nan,
            "dl": (sub["edges"][0] - ref["edges"][0]) if ref["edges"] and sub["edges"] else np.nan,
            "dr": (sub["edges"][1] - ref["edges"][1]) if ref["edges"] and sub["edges"] else np.nan,
            "dt": (sub["edges"][2] - ref["edges"][2]) if ref["edges"] and sub["edges"] else np.nan,
            "db": (sub["edges"][3] - ref["edges"][3]) if ref["edges"] and sub["edges"] else np.nan,
            "ink_ratio": (sub["ink"] / ref["ink"]) if ref["ink"] > 0 else np.nan,
            "peak_ref": ref["peak"],
            "peak_sub": sub["peak"],
            "wp": [ref["w"][lv] if ref["w"][lv] is not None else np.nan for lv in LEVELS],
            "wv": [sub["w"][lv] if sub["w"][lv] is not None else np.nan for lv in LEVELS],
            "hp": [ref["h"][lv] if ref["h"][lv] is not None else np.nan for lv in LEVELS],
            "hv": [sub["h"][lv] if sub["h"][lv] is not None else np.nan for lv in LEVELS],
        }
        per.append(row)
    s["per_word_rows"] = per

    def arr(key, rows=per):
        return np.array([x[key] for x in rows], dtype=np.float64)

    def groups():
        out = {"all": per}
        for sc in sorted({x["script"] for x in per}):
            out[sc] = [x for x in per if x["script"] == sc]
        # Per font, for fonts with enough words to say anything (min 5, see report).
        fonts = Counter(x["font"] for x in per)
        for fn in sorted(fonts):
            if fonts[fn] >= 5:
                out["font:" + str(fn)] = [x for x in per if x["font"] == fn]
        return out

    stats = {}
    for gname, rows in groups().items():
        g = {"n": len(rows)}
        if rows:
            wr = np.array([x["w_ratio"] for x in rows])
            hr = np.array([x["h_ratio"] for x in rows])
            g["w_ratio"] = boot_ci(wr, lambda z: _nanmedian(z))
            g["h_ratio"] = boot_ci(hr, lambda z: _nanmedian(z))
            g["dx_med"] = boot_ci(np.array([x["dx"] for x in rows]), lambda z: _nanmedian(z))
            g["dy_med"] = boot_ci(np.array([x["dy"] for x in rows]), lambda z: _nanmedian(z))
            g["ink_ratio"] = boot_ci(np.array([x["ink_ratio"] for x in rows]), lambda z: _nanmedian(z))
            g["dl_med"] = boot_ci(np.array([x["dl"] for x in rows]), lambda z: _nanmedian(z))
            g["dr_med"] = boot_ci(np.array([x["dr"] for x in rows]), lambda z: _nanmedian(z))
            g["dt_med"] = boot_ci(np.array([x["dt"] for x in rows]), lambda z: _nanmedian(z))
            g["db_med"] = boot_ci(np.array([x["db"] for x in rows]), lambda z: _nanmedian(z))
            g["peak_ref_med"] = _nanmedian([x["peak_ref"] for x in rows])
            g["peak_sub_med"] = _nanmedian([x["peak_sub"] for x in rows])
            g["reg_w"] = reg_boot(rows, "wp", "wv")
            g["reg_h"] = reg_boot(rows, "hp", "hv")
        stats[gname] = g
    s["words"] = stats

    # Lines and spacing (all scripts).
    lr = []
    for lrow in line_recs:
        ref, sub = lrow["ref"], lrow["sub"]
        if ref["w"][0.5] and sub["w"][0.5] and ref["h"][0.5] and sub["h"][0.5]:
            lr.append((sub["w"][0.5] / ref["w"][0.5], sub["h"][0.5] / ref["h"][0.5], sub["cy"] - ref["cy"]))
    lr = np.array(lr) if lr else np.zeros((0, 3))
    s["lines"] = {
        "n": int(len(lr)),
        "w_ratio": boot_ci(lr[:, 0], lambda z: _nanmedian(z)) if len(lr) else None,
        "h_ratio": boot_ci(lr[:, 1], lambda z: _nanmedian(z)) if len(lr) else None,
        "dy_med": boot_ci(lr[:, 2], lambda z: _nanmedian(z)) if len(lr) else None,
    }
    sp = np.array([x["ratio"] for x in spacing]) if spacing else np.zeros(0)
    s["spacing"] = {"n": int(len(sp)), "ratio": boot_ci(sp, lambda z: _nanmedian(z)) if len(sp) else None}

    # Glyph level (Latin, equal run counts only).
    gw, gs, gn = [], [], 0
    for r in valid:
        g = r.get("glyph")
        if not g:
            continue
        gn += 1
        for a, b in zip(g["ref_w"], g["sub_w"]):
            if a > 0:
                gw.append(b / a)
        if g["ref_span"] and g["ref_span"] > 0 and g["sub_span"] is not None:
            gs.append(g["sub_span"] / g["ref_span"])
    s["glyph"] = {
        "words": gn,
        "segments": len(gw),
        "width_ratio_med": _nanmedian(gw),
        "advance_span_ratio_med": _nanmedian(gs),
        "advance_span_n": len(gs),
    }
    s["overhang"] = overhang_summary(records)
    s["label"] = label
    return s


def fmt_ci(t, nd=4):
    if t is None or t[0] is None:
        return "n/a"
    p, lo, hi = t
    if lo is None:
        return f"{p:.{nd}f}"
    return f"{p:.{nd}f} [{lo:.{nd}f},{hi:.{nd}f}]"


def fmt_reg(r):
    if r is None:
        return "n/a"
    return (
        f"slope={r[0]:.4f} [{r[3]:.4f},{r[4]:.4f}] intercept={r[1]:.4f} [{r[5]:.4f},{r[6]:.4f}] n={r[2]}"
    )


def summary_lines(tag, s):
    out = [f"{tag} {s['label']}: words valid {s['words_valid']}/{s['words_total']}; excluded {json.dumps(s['excluded'], ensure_ascii=False)}"]
    font_groups = sorted(k for k in s["words"] if k.startswith("font:"))
    for g in ("all", "arabic", "latin") + tuple(font_groups):
        if g not in s["words"]:
            continue
        x = s["words"][g]
        if not x.get("n"):
            continue
        out.append(
            f"  [{g}] n={x['n']} W50 ratio {fmt_ci(x.get('w_ratio'))}  H50 ratio {fmt_ci(x.get('h_ratio'))}  "
            f"dx med {fmt_ci(x.get('dx_med'), 3)}  dy med {fmt_ci(x.get('dy_med'), 3)}"
        )
        if g.startswith("font:"):  # per-font: the width and height line only
            continue
        out.append(
            f"       edges dl {fmt_ci(x.get('dl_med'), 3)} dr {fmt_ci(x.get('dr_med'), 3)} "
            f"dt {fmt_ci(x.get('dt_med'), 3)} db {fmt_ci(x.get('db_med'), 3)}"
        )
        out.append(
            f"       reg W {fmt_reg(x.get('reg_w'))} | reg H {fmt_reg(x.get('reg_h'))} | "
            f"ink ratio {fmt_ci(x.get('ink_ratio'), 3)} | peak ref {(x.get('peak_ref_med') or 0):.3f} sub {(x.get('peak_sub_med') or 0):.3f}"
        )
    ln = s["lines"]
    out.append(f"  [lines] n={ln['n']} W50 ratio {fmt_ci(ln['w_ratio'])}  H50 ratio {fmt_ci(ln['h_ratio'])}  dy med {fmt_ci(ln['dy_med'], 3)}")
    sp = s["spacing"]
    out.append(f"  [spacing] n={sp['n']} centroid spacing ratio {fmt_ci(sp['ratio'])}")
    oh = s.get("overhang", {})
    for side in ("ref", "sub"):
        if side in oh:
            parts = [f"{k} med {v[0]:.2f} p95 {v[1]:.2f}" for k, v in oh[side].items() if v[0] is not None and v[1] is not None]
            out.append(f"  [overhang {side}] " + "; ".join(parts))
    gl = s["glyph"]
    out.append(f"  [glyph latin] words={gl['words']} segments={gl['segments']} width ratio med={gl['width_ratio_med']} advance-span ratio med={gl['advance_span_ratio_med']} (n={gl['advance_span_n']})")
    return out


# ----------------------------------------------------------------- driver


def page_inputs(page):
    """Words in cropped pixels plus drawing and image boxes, with a colour-contrast flag."""
    sx, sy = transform(page.rect.width, page.rect.height)
    words = []
    for wd in pdf_words(page):
        box = box_to_crop(wd["box_pt"], sx, sy)
        wd = dict(wd)
        wd["box_px"] = box
        wd["color_contrast"] = True
        words.append(wd)
    drawings, images, backgrounds = page_boxes_pt(page)
    drawings_px = [box_to_crop(b, sx, sy) for b in drawings]
    images_px = [box_to_crop(b, sx, sy) for b in images]
    return words, drawings_px, images_px, (sx, sy), backgrounds


def mupdf_render(page, sx, sy, scale=1):
    """Same PDF rasterised by MuPDF at the gate size (scale>1 supersamples, then box-averages)."""
    pix = page.get_pixmap(matrix=pymupdf.Matrix(sx * scale, sy * scale), alpha=False)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)[..., :3]
    if scale > 1:
        h, w = arr.shape[0] // scale, arr.shape[1] // scale
        arr = arr[: h * scale, : w * scale].reshape(h, scale, w, scale, 3).mean(axis=(1, 3))
    return arr[CO : CO + CH, CO : CO + CW].astype(np.uint8)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag", "text_geometry")
    os.makedirs(out, exist_ok=True)
    lines = ["[C6-DIAG-6] text geometry vs coverage (diagnostic, non-gating)"]
    summaries = {}
    try:
        import json as _json

        manifest = _json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
        pages = int(manifest["pageCount"])
        vector = os.path.join(d, "vector.pdf")
        full_pngs = resid.render(vector, os.path.join(out, "poppler"))
        if len(full_pngs) != pages:
            raise RuntimeError(f"expected {pages} pages, got {len(full_pngs)}")
        doc = pymupdf.open(vector)
        for i in range(pages):
            pno = i + 1
            tag = f"p{pno}"
            page = doc[i]
            words, drawings_px, images_px, (sx, sy), backgrounds = page_inputs(page)
            lines.append(
                f"{tag} page {page.rect.width:.2f}x{page.rect.height:.2f} pt; scale sx={sx:.6f} sy={sy:.6f} px/pt; "
                f"words={len(words)} drawings={len(drawings_px)} images={len(images_px)} page-background drawings skipped={backgrounds}"
            )
            norm = os.path.join(out, f"{tag}_poppler.png")
            resid.normalise(full_pngs[i], norm)
            pdf_rgb, _, note_a = resid.load_rgb(norm)
            prev_png = os.path.join(out, f"{tag}_preview.png")
            resid.reference(os.path.join(d, f"preview_page_{pno}.png"), prev_png)
            prev_rgb, _, note_p = resid.load_rgb(prev_png)
            if pdf_rgb.shape != (CH, CW, 3) or prev_rgb.shape != pdf_rgb.shape:
                raise RuntimeError(f"unexpected shapes {pdf_rgb.shape} {prev_rgb.shape}")
            pdf_f = load_float(pdf_rgb)
            prev_f = load_float(prev_rgb)
            lines.append(f"{tag} inputs: Preview{note_p}; PDF render{note_a}")

            mu_direct = load_float(mupdf_render(page, sx, sy))
            mu_2x = load_float(mupdf_render(page, sx, sy, scale=2))
            comparisons = [
                ("preview_vs_pdf_poppler", prev_f, pdf_f),
                ("control_poppler_vs_mupdf_direct", pdf_f, mu_direct),
                ("control_mupdf_direct_vs_mupdf_2x", mu_direct, mu_2x),
            ]
            for label, ref_f, sub_f in comparisons:
                recs, reasons = analyse_pair(words, drawings_px, images_px, ref_f, sub_f)
                lrs = line_measures(recs, words, ref_f, sub_f)
                spc = line_spacing(lrs)
                s = summarise(recs, lrs, spc, label)
                summaries[f"{tag}:{label}"] = {k: v for k, v in s.items() if k != "per_word_rows"}
                lines.extend(summary_lines(tag, s))
                # Per-word table, for the record (pure numbers, no images).
                with open(os.path.join(out, f"{tag}_{label}_words.json"), "w", encoding="utf-8") as f:
                    _json.dump(
                        [
                            {k: v for k, v in r.items() if k in ("i", "font", "script", "text", "excluded")} | {"w50_ref": (r["ref"]["w"][0.5] if r.get("ref") else None), "w50_sub": (r["sub"]["w"][0.5] if r.get("sub") else None)}
                            for r in recs
                        ],
                        f,
                        ensure_ascii=False,
                        indent=0,
                    )
    except Exception:  # noqa: BLE001 - diagnostics must not fail the job
        lines.append("text geometry ERROR " + traceback.format_exc()[-1500:])
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summaries, f, ensure_ascii=False, indent=1, default=lambda o: None if o is None else float(o))
    frame_diag.notice("C6-DIAG-6 text geometry", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
