#!/usr/bin/env python3
"""[C6-DIAG-13] Per-pixel attribution of text-mask leaks (diagnostic only, non-gating).

Question (C6 task 2). Removing text changes some pixels outside the text mask
(3 on page 1, 2 on page 2 in DIAG-7). Which cause explains each one?

Inputs are the same cropped gate rasters the residual diagnostic uses:
  --full     PDF render, normalised and cropped (what the gate compares)
  --notext   the same PDF with text objects removed, normalised and cropped
  --preview  the Preview PNG, cropped (optional; adds its value to each record)
and the vector PDF, which gives the glyph boxes and the drawings.

Rules, fixed before any run (not tuned to a result):
  E  exact mask: gate transform (W/page_w, H/page_h), 2 px crop. Used for the verdict.
  P  PX mask: the approximate PX = 4/3 mask of diag_c6_text_residual (as in DIAG-5/7).
  AA_TOL = 0.10 px: a pixel within this distance of a nominal glyph box is a boundary effect.
A changed pixel outside E is classified, in this order, as:
  non_text_drawing  inside the footprint of a non-text drawing (diag_c6_outline_mask);
  aa_boundary       within AA_TOL of a nominal glyph box;
  unexplained       anything else. It is reported, never removed.
A changed pixel inside E but outside P is counted as transform_px_only (PX-mask error).

Nothing here widens a mask or changes a validity condition. Outputs go to
build/visual_parity/c6diag/mask_pixels/ unless --out is given.
"""

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import diag_c6_mask_validity as mv  # noqa: E402
import diag_c6_outline_mask as om  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

import pymupdf  # noqa: E402

AA_TOL = 0.10  # device px
CO, CW, CH = resid.CO, resid.CW, resid.CH


def load_crop(path):
    """RGB array of a cropped gate raster, with a shape check."""
    arr, (w, h), note = resid.load_rgb(path)
    if arr.shape != (CH, CW, 3):
        raise RuntimeError(f"{path}: shape {arr.shape}, expected {(CH, CW, 3)}{note}")
    return arr.astype(np.float32) / 255.0


def _nearest_box_px(x, y, boxes_pt, sx, sy):
    """Distance (device px) from the pixel [x,x+1)x[y,y+1) to the nearest nominal glyph box."""
    best = None
    px, py = x + CO, y + CO  # full-frame coordinates of the pixel
    for x0, y0, x1, y1 in boxes_pt:
        ax0, ax1 = x0 * sx, x1 * sx
        ay0, ay1 = y0 * sy, y1 * sy
        dx = max(ax0 - (px + 1), px - ax1, 0.0)
        dy = max(ay0 - (py + 1), py - ay1, 0.0)
        d = float(np.hypot(dx, dy))
        best = d if best is None else min(best, d)
    return best


def analyse(pdf_path, full_png, notext_png, preview_png=None, page_index=0):
    doc = pymupdf.open(pdf_path)
    page = doc[page_index]
    pw, ph = page.rect.width, page.rect.height
    sx, sy = resid.W / pw, resid.H / ph
    full = load_crop(full_png)
    notext = load_crop(notext_png)
    prev = load_crop(preview_png) if preview_png else None

    chars = [c for ln in resid.text_lines(page) for c in ln["chars"]]
    boxes = [c["bbox"] for c in chars]
    shape = (CH, CW)
    m_exact = mv.exact_mask(shape, boxes, sx, sy, CO)
    m_px = resid.box_mask(shape, boxes)
    other_full, other_stats = om.outline_other_mask(page, (resid.H, resid.W), {"sx": sx, "sy": sy})
    other = other_full[CO : CO + CH, CO : CO + CW]

    diff = np.any(full != notext, axis=2)
    out_exact = diff & ~m_exact
    px_only = diff & m_exact & ~m_px

    records = []
    counts = {"non_text_drawing": 0, "aa_boundary": 0, "unexplained": 0}
    for y, x in np.argwhere(out_exact):
        d = _nearest_box_px(int(x), int(y), boxes, sx, sy)
        if other[y, x]:
            cls = "non_text_drawing"
        elif d is not None and d <= AA_TOL:
            cls = "aa_boundary"
        else:
            cls = "unexplained"
        counts[cls] += 1
        rec = {
            "x_gate": int(x),
            "y_gate": int(y),
            "x_full": int(x) + CO,
            "y_full": int(y) + CO,
            "class": cls,
            "dist_to_glyph_box_px": None if d is None else round(d, 4),
            "in_drawing_footprint": bool(other[y, x]),
            "in_px_mask": bool(m_px[y, x]),
            "full_rgb": [round(float(v), 4) for v in full[y, x]],
            "notext_rgb": [round(float(v), 4) for v in notext[y, x]],
        }
        if prev is not None:
            rec["preview_rgb"] = [round(float(v), 4) for v in prev[y, x]]
        records.append(rec)

    # Pixels that the PX approximation misses but the exact mask covers (transform error).
    px_only_count = int(px_only.sum())
    result = {
        "page": page_index,
        "page_size_pt": [round(float(pw), 4), round(float(ph), 4)],
        "scale": {"sx": sx, "sy": sy, "px": resid.PX},
        "text_chars": len(boxes),
        "text_mask_px_exact": int(m_exact.sum()),
        "text_mask_px_px43": int(m_px.sum()),
        "changed_total": int(diff.sum()),
        "changed_outside_exact": int(out_exact.sum()),
        "changed_outside_px43": int((diff & ~m_px).sum()),
        "transform_px_only": px_only_count,
        "classes_outside_exact": counts,
        "nontext_ops_removed_by_strip": None,  # filled by the caller when available
        "outline_stats": other_stats,
        "pixels": records,
        "aa_tol_px": AA_TOL,
    }
    doc.close()
    return result


def summary_lines(tag, r):
    lines = [
        f"[C6-DIAG-13] {tag} text-mask leak attribution (exact mask = verdict; PX = approximate)",
        f"  changed px total={r['changed_total']}; outside exact={r['changed_outside_exact']} (expected 0 for the gate); outside PX={r['changed_outside_px43']}",
        f"  transform_px_only (inside exact, outside PX)={r['transform_px_only']}",
        f"  classes outside exact: {r['classes_outside_exact']}",
    ]
    shown = r["pixels"][:20]  # the full list is in the JSON
    if len(r["pixels"]) > len(shown):
        lines.append(f"    ({len(r['pixels']) - len(shown)} more pixels in the JSON)")
    for p in shown:
        pv = f" preview={p['preview_rgb']}" if "preview_rgb" in p else ""
        lines.append(
            f"    gate({p['x_gate']},{p['y_gate']}) full({p['x_full']},{p['y_full']}) class={p['class']} "
            f"dist={p['dist_to_glyph_box_px']} inPX={p['in_px_mask']} footprint={p['in_drawing_footprint']} "
            f"full={p['full_rgb']} notext={p['notext_rgb']}{pv}"
        )
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--full", required=True)
    ap.add_argument("--notext", required=True)
    ap.add_argument("--preview")
    ap.add_argument("--tag", default="page")
    ap.add_argument("--page", type=int, default=0)
    ap.add_argument("--out", default=os.path.join("build", "visual_parity", "c6diag", "mask_pixels"))
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    r = analyse(a.pdf, a.full, a.notext, a.preview, a.page)
    with open(os.path.join(a.out, f"{a.tag}_mask_pixels.json"), "w", encoding="utf-8") as f:
        json.dump(r, f, indent=2, ensure_ascii=False)
    lines = summary_lines(a.tag, r)
    with open(os.path.join(a.out, f"{a.tag}_mask_pixels.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return r


if __name__ == "__main__":
    main()
