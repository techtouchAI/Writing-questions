#!/usr/bin/env python3
"""C6-DIAG-9: rule geometry of the Vector PDF against the Preview (diagnostic, non-gating).

Question: do the rules that carry Preview-only residual sit at the same position and
thickness in the Preview raster as the PDF drawing does, and does the official Poppler
raster agree with the analytic position of that drawing?

Inputs (nothing is written to them; their hashes are checked before and after):
  build/visual_parity/vector.pdf, preview_page_N.png, manifest.json

Method
  1. Rules from PyMuPDF get_drawings(): stroke lines, the four edges of stroked
     rectangles, and thin filled rectangles. Only axis-aligned rules of at least
     MIN_LEN pt and at most MAX_THICK pt are kept. Other drawings are kept as
     contamination masks, not as rules.
  2. Two analytic transforms, both reported:
       A  canonical   : px/pt = W / page_w, H / page_h   (the Preview frame, DIAG-6/7)
       B  pdftoppm    : px/pt = (96/72) * W / raw_w, (96/72) * H / raw_h
          (96 dpi, then the gate's resize from the raw pdftoppm size)
  3. Rasters, full frame (no crop, so no crop offset enters): the Preview as stored,
     and the PDF as the gate resizes it (convert -resize WxH!).
  4. Per rule: ink profile across the rule, averaged over the along-rule columns
     that are not contaminated by text, other drawings, or perpendicular rules.
     Isolated rules (no parallel rule within the band): continuous centre and
     thickness from the outer edge crossings. Exact for a uniform rule whose
     interior rows are full. Otherwise the centroid, flagged as such.
     Grouped rules (a parallel rule inside the band): profile comparison only.
  5. Displacements and thickness differences: Preview - A, Preview - B, PDF - A,
     PDF - B, Preview - PDF. Also the excess ink (Preview minus PDF) inside each band.

Coordinates: continuous, pixel i covers [i, i+1). An analytic centre is across_pt * scale.
"""

import hashlib
import json
import os
import subprocess
import sys
import traceback

import numpy as np
import pymupdf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import diag_c6_nontext_excess as nt  # noqa: E402  (exact text mask, char boxes)
import diag_c6_pdf_frame as frame_diag  # noqa: E402  (notice helper only)
import diag_c6_text_residual as resid  # noqa: E402

W, H, CW, CH, CO = resid.W, resid.H, resid.CW, resid.CH, resid.CO
PT_96 = 96.0 / 72.0
MIN_LEN = 40.0  # pt, shortest rule
MAX_THICK = 4.0  # pt, thickest rule
END_TRIM = 6  # px trimmed at each rule end (caps, joins, crossings)
BAND = 5  # rows (or columns) either side of the analytic centre
MIN_CLEAN = 20  # clean along-rule columns needed for a profile value
GROUP_GAP = 3  # px: parallel rules closer than this form a group


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ----------------------------------------------------------------- rule extraction


def _line_rule(p1, p2, thick, src, col, pidx, out):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    if abs(dy) < 1e-3 and abs(dx) >= MIN_LEN and thick <= MAX_THICK:
        out.append(_rule("h", p1[1], min(p1[0], p2[0]), max(p1[0], p2[0]), thick, src, col, pidx))
    elif abs(dx) < 1e-3 and abs(dy) >= MIN_LEN and thick <= MAX_THICK:
        out.append(_rule("v", p1[0], min(p1[1], p2[1]), max(p1[1], p2[1]), thick, src, col, pidx))


def _rule(orient, across, start, end, thick, src, col, pidx):
    return {
        "orient": orient,
        "across_pt": float(across),
        "start_pt": float(start),
        "end_pt": float(end),
        "thick_pt": float(thick),
        "src": src,
        "color": [float(c) for c in col] if col is not None else [0.0, 0.0, 0.0],
        "path": int(pidx),
    }


def extract_rules(page):
    """Return (rules, other_bboxes). Coordinates in pt, top-left origin."""
    rules, other = [], []
    for pidx, d in enumerate(page.get_drawings()):
        stroke = d.get("color") is not None and d.get("width") is not None
        fill_col = d.get("fill")
        col = d.get("color") if stroke else fill_col
        is_rule_path = False
        found = []
        for it in d["items"]:
            op = it[0]
            if op == "l" and stroke:
                _line_rule(it[1], it[2], float(d["width"]), "stroke_line", col, pidx, found)
            elif op == "re":
                r = it[1]
                if stroke:
                    t = float(d["width"])
                    for o, a, s0, s1 in (
                        ("h", r.y0, r.x0, r.x1),
                        ("h", r.y1, r.x0, r.x1),
                        ("v", r.x0, r.y0, r.y1),
                        ("v", r.x1, r.y0, r.y1),
                    ):
                        if s1 - s0 >= MIN_LEN and t <= MAX_THICK:
                            found.append(_rule(o, a, s0, s1, t, "stroke_rect", col, pidx))
                elif fill_col is not None:
                    if r.height <= MAX_THICK and r.width >= MIN_LEN:
                        found.append(_rule("h", (r.y0 + r.y1) / 2, r.x0, r.x1, r.height, "fill_rect", col, pidx))
                    elif r.width <= MAX_THICK and r.height >= MIN_LEN:
                        found.append(_rule("v", (r.x0 + r.x1) / 2, r.y0, r.y1, r.width, "fill_rect", col, pidx))
        if found:
            is_rule_path = True
            rules.extend(found)
        if not is_rule_path:
            r = d.get("rect")
            if r is not None:
                other.append((pidx, tuple(r)))
        else:
            # The path may also contain non-rule items; keep its bbox as contamination
            # for the other drawings' perspective only if it is not thin.
            r = d.get("rect")
            if r is not None and (r.width > MAX_THICK * 3 and r.height > MAX_THICK * 3):
                other.append((pidx, tuple(r)))
    for k, ru in enumerate(rules):
        ru["id"] = k
    return rules, other


# ----------------------------------------------------------------- transforms


def analytic_scales(page, raw_w, raw_h):
    pw, ph = page.rect.width, page.rect.height
    a = {"sx": W / pw, "sy": H / ph}
    b = {"sx": PT_96 * W / raw_w, "sy": PT_96 * H / raw_h}
    return a, b


def analytic_centre(rule, scales):
    s = scales["sy"] if rule["orient"] == "h" else scales["sx"]
    return rule["across_pt"] * s


def analytic_span(rule, scales):
    if rule["orient"] == "h":
        return rule["start_pt"] * scales["sx"], rule["end_pt"] * scales["sx"]
    return rule["start_pt"] * scales["sy"], rule["end_pt"] * scales["sy"]


def analytic_thick(rule, scales):
    s = scales["sy"] if rule["orient"] == "h" else scales["sx"]
    return rule["thick_pt"] * s


# ----------------------------------------------------------------- coverage and contamination


def cov_of(rgb, fg):
    """Projection of (bg - pixel) onto (bg - fg) with white background (1,1,1)."""
    bg = np.ones(3)
    fg = np.asarray(fg, dtype=np.float64)
    vec = fg - bg
    den = float(vec @ vec)
    if den < 1e-6:  # white rule on white: no contrast
        return None
    return np.clip(((rgb - bg) @ vec) / den, 0.0, 1.0)


def rect_mask(shape, x0, y0, x1, y1, margin=1):
    m = np.zeros(shape, dtype=bool)
    a = max(int(np.floor(x0)) - margin, 0)
    b = min(int(np.ceil(x1)) + margin, shape[1])
    c = max(int(np.floor(y0)) - margin, 0)
    d = min(int(np.ceil(y1)) + margin, shape[0])
    if b > a and d > c:
        m[c:d, a:b] = True
    return m


def base_contamination(shape, text_boxes_pt, other_bboxes_pt, scales):
    """Text and non-rule drawings, on the canonical transform, 1 px margin."""
    m = nt.mask_from_pt(shape, text_boxes_pt, scales["sx"], scales["sy"])
    m = _dilate1(m)
    for _, (x0, y0, x1, y1) in other_bboxes_pt:
        m |= rect_mask(shape, x0 * scales["sx"], y0 * scales["sy"], x1 * scales["sx"], y1 * scales["sy"])
    return m


def _dilate1(m):
    out = m.copy()
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    out[:, 1:] |= m[:, :-1]
    out[:, :-1] |= m[:, 1:]
    return out


def groups_of(rules, scales):
    """Index sets of parallel rules whose bands (±BAND) overlap or come within GROUP_GAP."""
    cc = {r["id"]: analytic_centre(r, scales) for r in rules}
    grp = {r["id"]: {r["id"]} for r in rules}
    for r in rules:
        for q in rules:
            if q["id"] == r["id"] or q["orient"] != r["orient"]:
                continue
            if abs(cc[r["id"]] - cc[q["id"]]) <= 2 * BAND + GROUP_GAP:
                grp[r["id"]].add(q["id"])
    return grp


# ----------------------------------------------------------------- profile measurement


def band_rows(cc_a, cc_b):
    lo = int(np.floor(min(cc_a, cc_b))) - BAND
    hi = int(np.ceil(max(cc_a, cc_b))) + BAND
    return lo, hi


def profile(cov, cont, rule, span, rows):
    """Along-rule mean of ink per across-row, over clean columns (or rows for vertical).

    Returns (prof, ncl) with prof NaN where fewer than MIN_CLEAN clean columns exist.
    """
    if rule["orient"] == "v":
        cov, cont = cov.T, cont.T
    a0, a1 = span
    a = max(int(np.floor(a0)) + END_TRIM, 0)
    b = min(int(np.ceil(a1)) - END_TRIM, cov.shape[1])
    lo, hi = rows
    lo, hi = max(lo, 0), min(hi, cov.shape[0] - 1)
    prof = np.full(hi - lo + 1, np.nan)
    ncl = np.zeros(hi - lo + 1, dtype=int)
    for k, r in enumerate(range(lo, hi + 1)):
        clean = ~cont[r, a:b]
        n = int(clean.sum())
        ncl[k] = n
        if n >= MIN_CLEAN:
            prof[k] = float(cov[r, a:b][clean].mean())
    return prof, ncl, (lo, hi)


def expected_profile(cc, t, lo, hi):
    """Exact area coverage of rows [i, i+1) by [cc - t/2, cc + t/2]."""
    i = np.arange(lo, hi + 1, dtype=np.float64)
    top, bot = cc - t / 2, cc + t / 2
    return np.clip(np.minimum(i + 1, bot) - np.maximum(i, top), 0.0, None)


def measure_side(prof, lo):
    """Edge-crossing measure (continuous) for one side. Returns dict."""
    pr = np.nan_to_num(prof, nan=0.0)
    ink = np.where(pr > 0.02)[0]
    out = {"method": None, "centre": None, "thick": None, "centroid": None, "mass": float(pr.sum())}
    if ink.size:
        out["centroid"] = float(((np.arange(len(pr)) + lo + 0.5) * pr).sum() / pr.sum()) if pr.sum() > 0 else None
    if ink.size < 2:
        out["method"] = "single_or_none"
        return out
    i0, i1 = int(ink[0]), int(ink[-1])
    if i0 == 0 or i1 == len(pr) - 1:
        out["method"] = "band_truncated"
        return out
    if np.any(np.isnan(prof[i0 - 1 : i1 + 2])):
        out["method"] = "nan_in_run"
        return out
    if i1 - i0 >= 2 and np.any(pr[i0 + 1 : i1] < 0.9):
        out["method"] = "partial_interior"
        return out
    if pr[i0 - 1] > 0.02 or pr[i1 + 1] > 0.02:
        out["method"] = "band_truncated"
        return out
    top = (lo + i0) + (1.0 - pr[i0])
    bot = (lo + i1) + pr[i1]
    out["method"] = "edges"
    out["centre"] = float((top + bot) / 2)
    out["thick"] = float(bot - top)
    return out


def sse(a, b):
    m = ~np.isnan(a)
    return float(((a[m] - b[m]) ** 2).sum()), int(m.sum())


# ----------------------------------------------------------------- per-rule measurement


def measure_rule(rule, groups, rules, scales_a, scales_b, cov_p, cov_d, base_cont, shape):
    cc_a = analytic_centre(rule, scales_a)
    cc_b = analytic_centre(rule, scales_b)
    t_a = analytic_thick(rule, scales_a)
    t_b = analytic_thick(rule, scales_b)
    span_a = analytic_span(rule, scales_a)
    lo, hi = band_rows(cc_a, cc_b)
    rows = (lo, hi)
    # Contamination: base mask plus the crossing footprints of perpendicular rules,
    # restricted to the band (a crossing rule only touches the band where it crosses).
    limit = shape[0] if rule["orient"] == "h" else shape[1]
    if lo < 0 or hi >= limit:
        return {"id": rule["id"], "orient": rule["orient"], "skipped": "band outside image"}
    cont = base_cont.copy()
    rs0, rs1 = span_a
    for q in rules:
        if q["orient"] == rule["orient"] or q["id"] == rule["id"]:
            continue
        qc = analytic_centre(q, scales_a)
        qs0, qs1 = analytic_span(q, scales_a)
        if not (qs0 - 1 <= cc_a <= qs1 + 1 and rs0 <= qc <= rs1):
            continue
        if rule["orient"] == "h":  # q is vertical, crosses the band in columns near qc
            cont |= rect_mask(shape, qc - 2, lo, qc + 2, hi, 0)
        else:  # q is horizontal, crosses the band in rows near qc
            cont |= rect_mask(shape, lo, qc - 2, hi, qc + 2, 0)
    grouped = len(groups[rule["id"]]) > 1

    def side(cov):
        prof, ncl, (lo_, hi_) = profile(cov, cont, rule, span_a, rows)
        m = measure_side(prof, lo_)
        return prof, ncl, m

    prof_p, ncl_p, m_p = side(cov_p)
    prof_d, ncl_d, m_d = side(cov_d)
    # Expected profiles, for every rule (grouped or not), on both transforms.
    exp_a = expected_profile(cc_a, t_a, lo, hi)
    exp_b = expected_profile(cc_b, t_b, lo, hi)
    ex = {
        "sse_prev_A": sse(prof_p, exp_a)[0],
        "sse_prev_B": sse(prof_p, exp_b)[0],
        "sse_pdf_A": sse(prof_d, exp_a)[0],
        "sse_pdf_B": sse(prof_d, exp_b)[0],
    }
    # Excess ink inside the band over clean columns (Preview minus PDF, positive part).
    cp, cd = (cov_p.T, cov_d.T) if rule["orient"] == "v" else (cov_p, cov_d)
    cc_mask = (cont.T if rule["orient"] == "v" else cont)
    a0, a1 = span_a
    a = max(int(np.floor(a0)) + END_TRIM, 0)
    b = min(int(np.ceil(a1)) - END_TRIM, cp.shape[1])
    band_p = cp[lo : hi + 1, a:b]
    band_d = cd[lo : hi + 1, a:b]
    clean = ~cc_mask[lo : hi + 1, a:b]
    n_clean_cols = int(clean.all(axis=0).sum())
    diff = band_p - band_d
    excess = float(np.where(clean, np.maximum(diff, 0.0), 0.0).sum() / max(clean.shape[1], 1))
    pdf_only = float(np.where(clean, np.maximum(-diff, 0.0), 0.0).sum() / max(clean.shape[1], 1))
    res = {
        "id": rule["id"],
        "orient": rule["orient"],
        "src": rule["src"],
        "across_pt": rule["across_pt"],
        "start_pt": rule["start_pt"],
        "end_pt": rule["end_pt"],
        "thick_pt": rule["thick_pt"],
        "color": rule["color"],
        "grouped": grouped,
        "group_ids": sorted(groups[rule["id"]]),
        "cc_A": cc_a,
        "cc_B": cc_b,
        "thick_A": t_a,
        "thick_B": t_b,
        "phase_A": cc_a - np.floor(cc_a),
        "span_A": [span_a[0], span_a[1]],
        "band": [lo, hi],
        "clean_cols": n_clean_cols,
        "min_clean_per_row": int(ncl_p.min()) if ncl_p.size else 0,
        "prev": m_p,
        "pdf": m_d,
        "excess_prev_minus_pdf": excess,
        "pdf_minus_prev": pdf_only,
        "expected_sse": ex,
        "prof_prev": [None if np.isnan(v) else round(float(v), 4) for v in prof_p],
        "prof_pdf": [None if np.isnan(v) else round(float(v), 4) for v in prof_d],
    }
    if m_p["method"] == "edges" and m_d["method"] == "edges" and not grouped:
        res["disp"] = {
            "prev_minus_A": m_p["centre"] - cc_a,
            "prev_minus_B": m_p["centre"] - cc_b,
            "pdf_minus_A": m_d["centre"] - cc_a,
            "pdf_minus_B": m_d["centre"] - cc_b,
            "prev_minus_pdf": m_p["centre"] - m_d["centre"],
            "thick_prev_minus_A": m_p["thick"] - t_a,
            "thick_pdf_minus_A": m_d["thick"] - t_a,
            "thick_prev_minus_pdf": m_p["thick"] - m_d["thick"],
        }
    else:
        res["disp"] = None
    return res


# ----------------------------------------------------------------- page driver


def page_inputs_for_rules(page):
    """Text boxes (pt) and non-rule drawing boxes (pt) for the contamination masks."""
    text_boxes = [b for b, _f, _rtl in nt.char_boxes_pt(page)]
    return text_boxes


def tosub(out_dir, tag, src_png, dst_png):
    subprocess.run(resid.im("convert") + [src_png, "-resize", f"{W}x{H}!", dst_png], check=True)


def analyse_page(page, prev_full, pdf_full, raw_size, prev_size, prev_path, pdf_path, pidx_label):
    rules, other = extract_rules(page)
    raw_w, raw_h = raw_size
    scales_a, scales_b = analytic_scales(page, raw_w, raw_h)
    shape = prev_full.shape[:2]
    # Contrast on each rule's own colour; per rule we re-project below.
    text_boxes = page_inputs_for_rules(page)
    other_nonrule = [(i, b) for i, b in other]
    base_cont = base_contamination(shape, text_boxes, [(i, (b[0], b[1], b[2], b[3])) for i, b in other_nonrule], scales_a)
    groups = groups_of(rules, scales_a)
    out_rules = []
    for ru in rules:
        fg = ru["color"]
        cp = cov_of(prev_full, fg)
        cd = cov_of(pdf_full, fg)
        if cp is None or cd is None:
            out_rules.append({"id": ru["id"], "skipped": "no contrast for colour"})
            continue
        out_rules.append(measure_rule(ru, groups, rules, scales_a, scales_b, cp, cd, base_cont, shape))
    return {
        "page": pidx_label,
        "page_pt": [page.rect.width, page.rect.height],
        "raw_pdftoppm_px": list(raw_size),
        "preview_px": list(prev_size),
        "scales_A": scales_a,
        "scales_B": scales_b,
        "rules_found": len(rules),
        "other_drawings": len(other),
        "rules": out_rules,
    }


# ----------------------------------------------------------------- reporting


def fmt(x, nd=3):
    return "n/a" if x is None else f"{x:+.{nd}f}" if isinstance(x, float) else str(x)


def report_lines(tag, res):
    out = [
        f"{tag} page {res['page_pt'][0]:.2f}x{res['page_pt'][1]:.2f} pt; rules={res['rules_found']} "
        f"other drawings={res['other_drawings']}",
        f"{tag} raw pdftoppm px={res['raw_pdftoppm_px']} (gate resizes to {W}x{H}); Preview px={res['preview_px']}",
        f"{tag} px/pt A canonical sx={res['scales_A']['sx']:.6f} sy={res['scales_A']['sy']:.6f}; "
        f"B pdftoppm sx={res['scales_B']['sx']:.6f} sy={res['scales_B']['sy']:.6f}",
    ]
    for r in res["rules"]:
        if "skipped" in r:
            out.append(f"{tag} rule {r['id']} skipped: {r['skipped']}")
            continue
        head = (
            f"{tag} rule {r['id']} {r['orient']} {r['src']} across={r['across_pt']:.2f}pt "
            f"span={r['start_pt']:.1f}..{r['end_pt']:.1f}pt thick={r['thick_pt']:.3f}pt "
            f"cc_A={r['cc_A']:.2f} cc_B={r['cc_B']:.2f} phaseA={r['phase_A']:.2f} "
            f"{'GROUP' if r['grouped'] else 'isolated'} clean_cols={r['clean_cols']}"
        )
        out.append(head)
        d = r.get("disp")
        if d:
            out.append(
                f"    disp px: prev-A {d['prev_minus_A']:+.3f} prev-B {d['prev_minus_B']:+.3f} "
                f"pdf-A {d['pdf_minus_A']:+.3f} pdf-B {d['pdf_minus_B']:+.3f} prev-pdf {d['prev_minus_pdf']:+.3f}"
            )
            out.append(
                f"    thick px: analytic-A {r['thick_A']:.3f} prev {r['prev']['thick']:.3f} "
                f"pdf {r['pdf']['thick']:.3f} (prev-A {d['thick_prev_minus_A']:+.3f} pdf-A {d['thick_pdf_minus_A']:+.3f})"
            )
        else:
            out.append(f"    methods: prev={r['prev']['method']} pdf={r['pdf']['method']} (no edge measure)")
        e = r["expected_sse"]
        out.append(
            f"    profile SSE vs expected: prev A {e['sse_prev_A']:.4f} B {e['sse_prev_B']:.4f} | "
            f"pdf A {e['sse_pdf_A']:.4f} B {e['sse_pdf_B']:.4f} | excess prev>pdf {r['excess_prev_minus_pdf']:.3f} "
            f"pdf>prev {r['pdf_minus_prev']:.3f}"
        )
    return out


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag", "rule_geometry")
    os.makedirs(out, exist_ok=True)
    lines = ["[C6-DIAG-9] page rule geometry: Preview and PDF raster against the PDF drawing (diagnostic, non-gating)"]
    summary = {"pages": {}, "inputs_unchanged": None}
    try:
        manifest_path = os.path.join(d, "manifest.json")
        inputs = [os.path.join(d, "vector.pdf"), manifest_path]
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
        pages = int(manifest["pageCount"])
        inputs += [os.path.join(d, f"preview_page_{p}.png") for p in range(1, pages + 1)]
        before = {p: sha256(p) for p in inputs}

        vector = os.path.join(d, "vector.pdf")
        doc = pymupdf.open(vector)
        raw_pngs = resid.render(vector, os.path.join(out, "poppler"))
        if len(raw_pngs) != pages:
            raise RuntimeError(f"expected {pages} pages, got {len(raw_pngs)}")
        for i in range(pages):
            pno = i + 1
            tag = f"p{pno}"
            page = doc[i]
            raw_rgb, raw_size, _ = resid.load_rgb(raw_pngs[i])
            pdf_full_png = os.path.join(out, f"{tag}_pdf_full.png")
            tosub(out, tag, raw_pngs[i], pdf_full_png)
            pdf_full, pdf_size, _ = resid.load_rgb(pdf_full_png)
            prev_src = os.path.join(d, f"preview_page_{pno}.png")
            prev_rgb, prev_size, note = resid.load_rgb(prev_src)
            if prev_size != (W, H):
                prev_full_png = os.path.join(out, f"{tag}_preview_full.png")
                tosub(out, tag, prev_src, prev_full_png)
                prev_rgb, prev_size, note = resid.load_rgb(prev_full_png)
                lines.append(f"{tag} Preview stored {prev_size} resized to {W}x{H} for analysis (not the gate path)")
            if pdf_size != (W, H) or prev_size != (W, H):
                raise RuntimeError(f"unexpected full-frame sizes pdf={pdf_size} prev={prev_size}")
            res = analyse_page(
                page,
                prev_rgb.astype(np.float64) / 255.0,
                pdf_full.astype(np.float64) / 255.0,
                raw_size,
                prev_size,
                prev_src,
                vector,
                tag,
            )
            summary["pages"][tag] = res
            lines += report_lines(tag, res)

        after = {p: sha256(p) for p in inputs}
        summary["inputs_unchanged"] = before == after
        lines.append(f"inputs unchanged (sha256 before/after): {summary['inputs_unchanged']}")
    except Exception:
        lines.append("rule geometry ERROR " + traceback.format_exc()[-1500:])
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1, default=float)
    frame_diag.notice("C6-DIAG-9 rule geometry", lines)


if __name__ == "__main__":
    main()
