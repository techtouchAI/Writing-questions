#!/usr/bin/env python3
"""[C6-DIAG-7] TEMPORARY diagnostic: Preview ink outside the text mask. Not for merge.

Question: the text-residual report (C6-DIAG-5) found Preview ink outside the
text mask (page 1: 8444.6 darkness units vs 7535.4 in the PDF). Is that
(a) missing mask coverage, i.e. the Preview's text lying just outside the glyph
boxes, or (b) a genuine non-text rendering difference (drawings, images, rules)?

Method (diagnostic only; the mask is never changed; production files untouched):
  1. Text mask from the EXACT point-to-pixel map (794/page_width, 1123/page_height),
     not the 4/3 approximation used by C6-DIAG-5. The size of that difference is reported.
  2. Validation: the text-removed render (C6-DIAG-5 stripping, same render path)
     must change no pixel outside this mask.
  3. Preview-only ink: darkness(Preview) - darkness(PDF) > EXC, outside the mask.
  4. Each Preview-only pixel is placed by its distance to the nearest text-mask
     pixel (Chebyshev), and by whether it lies inside a PDF drawing or image.
     A genuine rendering difference is far from text or sits on a drawing.
  5. Connected Preview-only regions are listed with bbox, excess, nearest glyph
     and class: text_adjacent (<= 3 px from the mask), drawing_adjacent,
     image, or unexplained.

Never fails the job; errors become notices.
Usage: diag_c6_nontext_excess.py <artifacts_dir>
"""
import json
import os
import sys
import traceback

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_pdf_frame as frame_diag  # noqa: E402
import diag_c6_text_geometry as geo  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

CW, CH, CO = resid.CW, resid.CH, resid.CO
EXC = 0.15  # darkness difference that counts as Preview-only ink
ADJ = 3  # px from the text mask that counts as text-adjacent
DIST_MAX = 32
BUCKETS = [(1, 1), (2, 2), (3, 3), (4, 6), (7, 12), (13, 24), (25, DIST_MAX), (DIST_MAX + 1, 10**9)]


def char_boxes_pt(page):
    """(nominal char box in pt, font name, rtl flag) for every non-space glyph."""
    out = []
    for ln in resid.text_lines(page):
        for c in ln["chars"]:
            out.append((tuple(c["bbox"]), c.get("font", ""), ln["rtl"]))
    return out


def mask_from_pt(shape, boxes_pt, sx, sy):
    """Boolean mask in cropped pixels (floor/ceil of exact transform)."""
    m = np.zeros(shape, dtype=bool)
    h, w = shape
    for x0, y0, x1, y1 in boxes_pt:
        a = int(np.floor(x0 * sx - CO))
        b = int(np.ceil(x1 * sx - CO))
        c = int(np.floor(y0 * sy - CO))
        d = int(np.ceil(y1 * sy - CO))
        a, c = max(a, 0), max(c, 0)
        b, d = min(b, w), min(d, h)
        if b > a and d > c:
            m[c:d, a:b] = True
    return m


def chebyshev_distance(mask, maxd=DIST_MAX):
    """Distance in px to the nearest True pixel (capped at maxd+1)."""
    dist = np.full(mask.shape, maxd + 1, dtype=np.int32)
    dist[mask] = 0
    cur = mask.copy()
    for d in range(1, maxd + 1):
        grown = cur.copy()
        grown[1:, :] |= cur[:-1, :]
        grown[:-1, :] |= cur[1:, :]
        g2 = grown.copy()
        g2[:, 1:] |= grown[:, :-1]
        g2[:, :-1] |= grown[:, 1:]
        new = g2 & (dist > maxd)
        dist[new] = d
        cur = g2
    return dist


def label_components(mask):
    """8-connected components. Returns a list of (N x 2 array of (y, x))."""
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    comps = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        cid = len(comps) + 1
        lab[y0, x0] = cid
        stack = [(y0, x0)]
        pix = []
        while stack:
            y, x = stack.pop()
            pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = cid
                        stack.append((yy, xx))
        comps.append(np.array(pix, dtype=np.int32))
    return comps


def analyse_page(page, prev_f, pdf_f, notext_f, sx, sy, exc=EXC):
    """Non-text analysis of one page. prev_f, pdf_f, notext_f: float 0..1 HxWx3 (cropped)."""
    shape = prev_f.shape[:2]
    res = {}
    chars = char_boxes_pt(page)
    text_pt = [c[0] for c in chars]
    t_mask = mask_from_pt(shape, text_pt, sx, sy)
    old_mask = resid.box_mask(shape, text_pt)  # the C6-DIAG-5 mask (4/3 map)
    res["mask_px"] = int(t_mask.sum())
    res["mask_exact_vs_4_3_symdiff"] = int(np.sum(t_mask ^ old_mask))
    res["mask_exact_vs_4_3_note"] = "C6-DIAG-5 used a 4/3 point-to-pixel map; the exact map is 794/page_width and 1123/page_height"

    # Validation: text removal may change pixels only inside this mask.
    diff_any = np.any(pdf_f != notext_f, axis=2)
    res["validation_outside_changed"] = int(np.sum(diff_any & ~t_mask))
    res["validation_inside_changed"] = int(np.sum(diff_any & t_mask))

    drawings, images, backgrounds = geo.page_boxes_pt(page)
    d_mask = np.zeros(shape, dtype=bool)
    for b in drawings:
        d_mask |= _box_px_mask(shape, b, sx, sy)
    i_mask = np.zeros(shape, dtype=bool)
    for b in images:
        i_mask |= _box_px_mask(shape, b, sx, sy)
    d_mask_g = _grow(d_mask, 1)
    d_mask_adj = _grow(d_mask, ADJ)  # drawing adjacency: within ADJ px of a drawing
    res["drawing_boxes"] = len(drawings)
    res["image_boxes"] = len(images)
    res["page_background_drawings"] = backgrounds

    ink_p = 1.0 - prev_f.mean(axis=2)
    ink_v = 1.0 - pdf_f.mean(axis=2)
    outside = ~t_mask
    res["ink_outside_prev"] = float(ink_p[outside].sum())
    res["ink_outside_pdf"] = float(ink_v[outside].sum())
    excess = outside & ((ink_p - ink_v) > exc)
    res["excess_pixels"] = int(excess.sum())
    res["excess_mass"] = float((ink_p - ink_v)[excess].sum())
    res["excess_thresholds"] = {}
    for e in (0.05, 0.10, 0.15, 0.25, 0.40):
        m = outside & ((ink_p - ink_v) > e)
        res["excess_thresholds"][str(e)] = {"pixels": int(m.sum()), "mass": float((ink_p - ink_v)[m].sum())}

    # SSE of the gate render vs Preview, by class of outside pixels.
    se = ((pdf_f.astype(np.float64) - prev_f.astype(np.float64)) ** 2).sum(axis=2)
    res["sse_total"] = float(se.sum())
    res["sse_text"] = float(se[t_mask].sum())
    res["sse_outside"] = float(se[outside].sum())

    dist = chebyshev_distance(t_mask)
    res["distance_buckets"] = []
    for lo, hi in BUCKETS:
        b = outside & (dist >= lo) & (dist <= hi)
        ex = b & ((ink_p - ink_v) > exc)
        res["distance_buckets"].append(
            {
                "range": f"{lo}-{hi if hi < 10**9 else 'inf'}",
                "pixels": int(b.sum()),
                "sse": float(se[b].sum()),
                "ink_prev": float(ink_p[b].sum()),
                "ink_pdf": float(ink_v[b].sum()),
                "excess_pixels": int(ex.sum()),
                "excess_mass": float((ink_p - ink_v)[ex].sum()),
            }
        )
    cum = {}
    total_ex = float((ink_p - ink_v)[excess].sum())
    for dcut in (1, 2, 3, 4, 6, 8, 12, 16, 24, DIST_MAX):
        m = excess & (dist <= dcut)
        cum[str(dcut)] = (float((ink_p - ink_v)[m].sum()) / total_ex) if total_ex > 0 else None
    res["excess_cum_within_px"] = cum

    res["by_class_outside"] = {
        "drawing": {"pixels": int((outside & d_mask_g).sum()), "sse": float(se[outside & d_mask_g].sum())},
        "image": {"pixels": int((outside & i_mask & ~d_mask_g).sum()), "sse": float(se[outside & i_mask & ~d_mask_g].sum())},
        "other": {"pixels": int((outside & ~d_mask_g & ~i_mask).sum()), "sse": float(se[outside & ~d_mask_g & ~i_mask].sum())},
    }

    # Connected Preview-only regions.
    comps = label_components(excess)
    rows = []
    char_px = np.zeros((0, 4))
    if chars:
        char_arr = np.array([c[0] for c in chars], dtype=np.float64)
        char_px = np.stack(
            [char_arr[:, 0] * sx - CO, char_arr[:, 1] * sy - CO, char_arr[:, 2] * sx - CO, char_arr[:, 3] * sy - CO],
            axis=1,
        )
    for pix in comps:
        ys, xs = pix[:, 0], pix[:, 1]
        mass = float((ink_p - ink_v)[ys, xs].sum())
        dmin = int(dist[ys, xs].min())
        frac_d = float(d_mask_adj[ys, xs].mean())
        frac_i = float(i_mask[ys, xs].mean())
        if dmin <= ADJ:
            cls = "text_adjacent"
        elif frac_d >= 0.5:
            cls = "drawing_adjacent"
        elif frac_i >= 0.5:
            cls = "image"
        else:
            cls = "unexplained"
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        near = None
        if len(char_px):
            cx, cy = (bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0
            ddx = np.maximum(np.maximum(char_px[:, 0] - cx, cx - char_px[:, 2]), 0)
            ddy = np.maximum(np.maximum(char_px[:, 1] - cy, cy - char_px[:, 3]), 0)
            j = int(np.argmin(np.hypot(ddx, ddy)))
            near = {"font": chars[j][1], "distance_px": float(np.hypot(ddx[j], ddy[j]))}
        rows.append(
            {
                "bbox": bbox,
                "area": int(len(pix)),
                "mass": mass,
                "min_text_distance": dmin,
                "frac_in_drawing": frac_d,
                "frac_in_image": frac_i,
                "class": cls,
                "nearest_char_font": near["font"] if near else None,
                "nearest_char_distance_px": near["distance_px"] if near else None,
            }
        )
    rows.sort(key=lambda r: -r["mass"])
    res["components"] = len(rows)
    res["component_top"] = rows[:15]
    res["component_class_mass"] = {}
    for r in rows:
        res["component_class_mass"][r["class"]] = res["component_class_mass"].get(r["class"], 0.0) + r["mass"]
    return res


def _box_px_mask(shape, box_pt, sx, sy):
    return mask_from_pt(shape, [box_pt], sx, sy)


def _grow(mask, n):
    m = mask.copy()
    for _ in range(n):
        g = m.copy()
        g[1:, :] |= m[:-1, :]
        g[:-1, :] |= m[1:, :]
        h = g.copy()
        h[:, 1:] |= g[:, :-1]
        h[:, :-1] |= g[:, 1:]
        m = h
    return m


def fmt_result(tag, r):
    out = [
        f"{tag} text mask: pixels={r['mask_px']} exact-vs-4/3 mask symmetric difference={r['mask_exact_vs_4_3_symdiff']} px",
        f"{tag} validation (exact mask): text removal changed {r['validation_outside_changed']} pixels outside (must be 0), {r['validation_inside_changed']} inside",
        f"{tag} Preview ink outside mask={r['ink_outside_prev']:.1f} PDF={r['ink_outside_pdf']:.1f}; Preview-only excess (> {EXC}) pixels={r['excess_pixels']} mass={r['excess_mass']:.1f}",
        f"{tag} excess mass by threshold: " + ", ".join(f"{k}: {v['mass']:.1f}" for k, v in r["excess_thresholds"].items()),
        f"{tag} SSE: total={r['sse_total']:.1f} text={r['sse_text']:.1f} outside={r['sse_outside']:.1f}",
        f"{tag} outside pixels by class: " + ", ".join(f"{k}: px={v['pixels']} sse={v['sse']:.1f}" for k, v in r["by_class_outside"].items()),
        f"{tag} cumulative share of Preview-only mass within d px of text: "
        + ", ".join(f"{k}px={(v if v is not None else float('nan')):.3f}" for k, v in r["excess_cum_within_px"].items()),
    ]
    for b in r["distance_buckets"]:
        out.append(
            f"  dist {b['range']:>7}: px={b['pixels']} sse={b['sse']:.1f} ink prev={b['ink_prev']:.1f} pdf={b['ink_pdf']:.1f} "
            f"excess px={b['excess_pixels']} mass={b['excess_mass']:.1f}"
        )
    out.append(f"{tag} Preview-only regions (> {EXC}): {r['components']}; mass by class: " + json.dumps({k: round(v, 1) for k, v in r['component_class_mass'].items()}))
    for c in r["component_top"]:
        out.append(
            f"  region bbox={c['bbox']} area={c['area']} mass={c['mass']:.1f} min_text_dist={c['min_text_distance']} "
            f"in_drawing={c['frac_in_drawing']:.2f} in_image={c['frac_in_image']:.2f} class={c['class']} "
            f"nearest_font={c['nearest_char_font']} nearest_dist={c['nearest_char_distance_px'] if c['nearest_char_distance_px'] is None else round(c['nearest_char_distance_px'], 2)}"
        )
    return out


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag", "nontext_excess")
    os.makedirs(out, exist_ok=True)
    lines = ["[C6-DIAG-7] Preview ink outside the text mask (diagnostic, non-gating)"]
    summaries = {}
    try:
        import json as _json

        manifest = _json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
        pages = int(manifest["pageCount"])
        vector = os.path.join(d, "vector.pdf")
        stripped = os.path.join(out, "notext.pdf")
        resid.write_pdf_stripped(vector, stripped)
        full_pngs = resid.render(vector, os.path.join(out, "full"))
        text_pngs = resid.render(stripped, os.path.join(out, "notext"))
        if len(full_pngs) != pages or len(text_pngs) != pages:
            raise RuntimeError(f"expected {pages} pages")
        doc = pymupdf.open(vector)
        for i in range(pages):
            pno = i + 1
            tag = f"p{pno}"
            page = doc[i]
            sx, sy = geo.transform(page.rect.width, page.rect.height)
            full_n = os.path.join(out, f"{tag}_full.png")
            text_n = os.path.join(out, f"{tag}_notext.png")
            prev_n = os.path.join(out, f"{tag}_preview.png")
            resid.normalise(full_pngs[i], full_n)
            resid.normalise(text_pngs[i], text_n)
            resid.reference(os.path.join(d, f"preview_page_{pno}.png"), prev_n)
            pdf_rgb, _, _ = resid.load_rgb(full_n)
            notext_rgb, _, _ = resid.load_rgb(text_n)
            prev_rgb, _, _ = resid.load_rgb(prev_n)
            pdf_f = pdf_rgb.astype(np.float64) / 255.0
            prev_f = prev_rgb.astype(np.float64) / 255.0
            notext_f = notext_rgb.astype(np.float64) / 255.0
            r = analyse_page(page, prev_f, pdf_f, notext_f, sx, sy)
            lines.extend(fmt_result(tag, r))
            summaries[tag] = {k: v for k, v in r.items() if k != "component_top"}
            # Overlay for review: red = Preview-only ink outside the mask, grey = text mask.
            ink_p = 1.0 - prev_f.mean(axis=2)
            ink_v = 1.0 - pdf_f.mean(axis=2)
            t_mask = mask_from_pt(prev_f.shape[:2], [c[0] for c in char_boxes_pt(page)], sx, sy)
            exc = (~t_mask) & ((ink_p - ink_v) > EXC)
            img = np.full(prev_f.shape, 255, dtype=np.uint8)
            img[t_mask] = (200, 200, 200)
            img[exc] = (255, 0, 0)
            pm = pymupdf.Pixmap(pymupdf.csRGB, img.shape[1], img.shape[0], img.tobytes(), False)
            pm.save(os.path.join(out, f"{tag}_excess_overlay.png"))
    except Exception:  # noqa: BLE001 - diagnostics must not fail the job
        lines.append("non-text excess ERROR " + traceback.format_exc()[-1500:])
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summaries, f, ensure_ascii=False, indent=1, default=lambda o: None if o is None else float(o))
    frame_diag.notice("C6-DIAG-7 non-text excess", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
