"""[C6-DIAG-10] Text-mask validity: which pixels change when text is removed, and why.

Diagnostic only. Production code, the official gate, the expected images, the
mask and the RMSE pipeline are not touched. Nothing here widens the text mask.

Background. The residual report (C6-DIAG-5) asserts that removing text changes no
pixel outside the text mask. On the real fixture the exact-mask check counted 3
such pixels on page 1 and 2 on page 2 (C6-DIAG-7), where 0 is expected.

Candidate causes tested here, each on SYNTHETIC PDFs whose content is known:
  T1. Transform error. The mask in diag_c6_text_residual.box_mask uses PX = 4/3,
      but the gate's raster scale is 794/page_width horizontally and
      1123/page_height vertically. Compare the PX mask with the exact-transform mask.
  T2. Anti-aliasing at the mask boundary. Glyph ink that touches a pixel just
      outside the nominal character box. Expected: very faint (darkness of a few
      per mille) and within a fraction of a pixel of the box.
  T3. Non-text painting inside BT..ET. strip_text removes the whole BT..ET span,
      so a rectangle or rule drawn inside a text object disappears with the text.
      Those pixels are non-text and lie outside the mask, so they would be counted
      as text-mask leaks. The counter nontext_ops_removed detects this case.
  T4. Literal strings containing "BT"/"ET". Must not confuse the tokenizer.

Outputs go to build/visual_parity/c6diag/mask_validity/ only (see main()).
"""

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_text_residual as resid  # noqa: E402

import pymupdf  # noqa: E402

PW, PH = 595.28, 841.89
CO, CW, CH = resid.CO, resid.CW, resid.CH
SX, SY = 794.0 / PW, 1123.0 / PH  # canonical gate scale (the page is 794x1123 after resize)
OUT_DIR = os.path.join("build", "visual_parity", "c6diag", "mask_validity")


def exact_mask(shape, boxes_pt, sx=SX, sy=SY, co=CO):
    """Mask from pt boxes with the gate's own scale (not the PX approximation)."""
    m = np.zeros(shape, dtype=bool)
    h, w = shape
    for x0, y0, x1, y1 in boxes_pt:
        a = max(int(np.floor(x0 * sx)) - co, 0)
        b = min(int(np.ceil(x1 * sx)) - co, w)
        c = max(int(np.floor(y0 * sy)) - co, 0)
        d = min(int(np.ceil(y1 * sy)) - co, h)
        if b > a and d > c:
            m[c:d, a:b] = True
    return m


def outside_changes(full, notext, mask, boxes_pt=None, sx=SX, sy=SY, co=CO, limit=20):
    """Pixels that differ between full and text-removed renders outside `mask`.

    Returns count, the darkness (1 - mean RGB of the full render; text is dark), and
    the distance in device pixels from each pixel to the nearest nominal box.
    """
    diff = np.any(full != notext, axis=2)
    bad = np.argwhere(diff & ~mask)
    rows = []
    for y, x in bad[:limit]:
        dark = float(1.0 - full[y, x].mean())
        dist = None
        if boxes_pt:
            best = None
            for x0, y0, x1, y1 in boxes_pt:
                ax0, ax1 = x0 * sx - co, x1 * sx - co
                ay0, ay1 = y0 * sy - co, y1 * sy - co
                dx = max(ax0 - (x + 1), x - ax1, 0.0)
                dy = max(ay0 - (y + 1), y - ay1, 0.0)
                dd = float(np.hypot(dx, dy))
                best = dd if best is None else min(best, dd)
            dist = best
        rows.append({"x": int(x), "y": int(y), "darkness": round(dark, 5), "dist_px": None if dist is None else round(dist, 3)})
    return {"count": int(bad.shape[0]), "pixels": rows}


def render_gate(doc):
    """Full-frame canonical render, then the gate crop (CO px each side)."""
    pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(SX, SY), alpha=False)
    arr = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, 3)
    return arr[CO : CO + CH, CO : CO + CW].astype(np.float32) / 255.0


def _strip_render(src, dst_dir, name):
    dst = os.path.join(dst_dir, name + "_stripped.pdf")
    stats = resid.write_pdf_stripped(src, dst)
    full = render_gate(pymupdf.open(src))
    notext = render_gate(pymupdf.open(dst))
    return full, notext, stats[0]


def build_text_page(path):
    """Text-only page: Helvetica at sizes 8-14 pt, staggered rows (C6-like density)."""
    d = pymupdf.open()
    p = d.new_page(width=PW, height=PH)
    names = ["Hello", "World", "Mask", "Check", "Alpha", "Beta", "Gamma", "Delta"]
    k = 0
    for row in range(16):
        for col in range(4):
            fs = [8, 9, 10, 11, 12, 14][(row + col) % 6]
            p.insert_text((40 + col * 135, 60 + row * 48 + 0.37 * col), names[k % len(names)], fontname="helv", fontsize=fs)
            k += 1
    d.save(path)
    d.close()
    return path


def build_bt_painting_page(path):
    """Text plus a filled rectangle drawn inside a BT..ET block (T3 case) and one outside."""
    d = pymupdf.open()
    p = d.new_page(width=PW, height=PH)
    p.insert_text((100, 100), "A", fontname="helv", fontsize=12)
    fname = p.get_fonts()[0][4]
    stream = (
        f"BT /{fname} 12 Tf 100 700 Td (Hello) Tj 0 0 1 rg 200 600 100 40 re f ET\n"
        "1 0 0 rg 300 500 100 40 re f\n"
    )
    d.update_stream(p.get_contents()[0], stream.encode("latin-1"))
    d.save(path)
    d.close()
    return path


def build_bt_literal_page(path):
    """A blue rectangle and a text string whose literal contains 'BT' and 'ET' (T4 case)."""
    d = pymupdf.open()
    p = d.new_page(width=PW, height=PH)
    p.insert_text((100, 100), "A", fontname="helv", fontsize=12)
    fname = p.get_fonts()[0][4]
    stream = f"0 0 1 rg 200 600 100 40 re f\nBT /{fname} 12 Tf 100 700 Td (BT inside ET text) Tj ET\n"
    d.update_stream(p.get_contents()[0], stream.encode("latin-1"))
    d.save(path)
    d.close()
    return path


def run_synthetic(out_dir=OUT_DIR, work_dir=None):
    """Run T1-T4 on synthetic PDFs. Returns a dict of results (all synthetic)."""
    os.makedirs(out_dir, exist_ok=True)
    work = work_dir or out_dir
    res = {
        "scale": {
            "sx": SX,
            "sy": SY,
            "approx_px": resid.PX,
            # Displacement of the PX mask relative to the gate raster, at the far page edge.
            "edge_shift_x_px": (SX - resid.PX) * PW,
            "edge_shift_y_px": (SY - resid.PX) * PH,
        }
    }

    # T1 + T2: text-only page, approximate vs exact mask.
    src = build_text_page(os.path.join(work, "t12_text.pdf"))
    full, notext, st = _strip_render(src, work, "t12")
    boxes = [c["bbox"] for ln in resid.text_lines(pymupdf.open(src)[0]) for c in ln["chars"]]
    shape = (CH, CW)
    m_approx = resid.box_mask(shape, boxes)
    m_exact = exact_mask(shape, boxes)
    res["T1_T2_text_only"] = {
        "chars": len(boxes),
        "changed_total": int(np.any(full != notext, axis=2).sum()),
        "approx_mask": outside_changes(full, notext, m_approx, boxes),
        "exact_mask": outside_changes(full, notext, m_exact, boxes),
        "strip": {k: st[k] for k in ("text_objects", "show_ops_removed", "nontext_ops_removed")},
    }

    # T3: painting inside BT..ET.
    src = build_bt_painting_page(os.path.join(work, "t3_bt_paint.pdf"))
    full, notext, st = _strip_render(src, work, "t3")
    blue = (full[..., 2] > 0.9) & (full[..., 0] < 0.1) & (full[..., 1] < 0.1)
    blue_after = (notext[..., 2] > 0.9) & (notext[..., 0] < 0.1) & (notext[..., 1] < 0.1)
    red_after = (notext[..., 0] > 0.9) & (notext[..., 1] < 0.1) & (notext[..., 2] < 0.1)
    boxes3 = [c["bbox"] for ln in resid.text_lines(pymupdf.open(src)[0]) for c in ln["chars"]]
    m3 = exact_mask((CH, CW), boxes3)
    res["T3_bt_painting"] = {
        "blue_rect_px_before": int(blue.sum()),
        "blue_rect_px_after_strip": int(blue_after.sum()),
        "red_rect_kept_after_strip": bool(red_after.any()),
        "nontext_ops_removed": st["nontext_ops_removed"],
        "exact_mask": outside_changes(full, notext, m3, boxes3),
    }

    # T4: literal strings with BT/ET.
    src = build_bt_literal_page(os.path.join(work, "t4_literal.pdf"))
    full, notext, st = _strip_render(src, work, "t4")
    blue_after4 = (notext[..., 2] > 0.9) & (notext[..., 0] < 0.1) & (notext[..., 1] < 0.1)
    res["T4_literal_bt_et"] = {
        "text_objects": st["text_objects"],
        "nontext_ops_removed": st["nontext_ops_removed"],
        "blue_rect_kept": bool(blue_after4.any()),
    }

    with open(os.path.join(out_dir, "mask_validity_synthetic.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, indent=2, ensure_ascii=False)
    return res


def summary_lines(res):
    t12 = res["T1_T2_text_only"]
    ap, ex = t12["approx_mask"], t12["exact_mask"]
    t3 = res["T3_bt_painting"]
    t4 = res["T4_literal_bt_et"]
    lines = [
        "[C6-DIAG-10] text-mask validity, SYNTHETIC PDFs (not gate evidence)",
        f"scale: gate sx={SX:.6f} sy={SY:.6f}; box_mask PX={resid.PX:.6f}; PX-mask displacement at the far page edge: x {(SX - resid.PX) * PW:+.3f} px, y {(SY - resid.PX) * PH:+.3f} px",
        f"T1 text-only page ({t12['chars']} chars): changed px total={t12['changed_total']}",
        f"   PX=4/3 mask: changed outside={ap['count']}",
        f"   exact mask:  changed outside={ex['count']}",
    ]
    for p in ex["pixels"]:
        lines.append(f"     exact-mask outside px x={p['x']} y={p['y']} darkness={p['darkness']} dist={p['dist_px']}")
    lines += [
        f"T3 painting inside BT..ET: blue rect px before={t3['blue_rect_px_before']} after strip={t3['blue_rect_px_after_strip']}; "
        f"nontext_ops_removed={t3['nontext_ops_removed']}; red (outside BT) kept={t3['red_rect_kept_after_strip']}; "
        f"exact-mask outside={t3['exact_mask']['count']}",
        f"T4 literal BT/ET: text_objects={t4['text_objects']}, nontext_ops_removed={t4['nontext_ops_removed']}, blue rect kept={t4['blue_rect_kept']}",
    ]
    return lines


def main():
    res = run_synthetic()
    lines = summary_lines(res)
    with open(os.path.join(OUT_DIR, "mask_validity_synthetic.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
