#!/usr/bin/env python3
"""[C6-DIAG-5] TEMPORARY diagnostic: text-only residual isolation. Not for merge.

Question: how much of the Vector PDF vs Preview RMSE lies on text pixels, and
what the text residual looks like (ink, fonts, direction, per-line positioning).

Method (diagnostic copies only; production files are never touched):
  1. Gate-identical render: pdftoppm -r 96, convert -resize 794x1123!, crop 2 px.
     Baseline RMSE is computed with ImageMagick (official) and with numpy
     (for the decomposition); the two must agree.
  2. Text-removed copy: every BT..ET text object is removed from the page
     content stream. Everything else is copied byte for byte. Its render is the
     non-text reference. Validity check: outside the text mask, the full render
     and the text-removed render must be identical pixel for pixel.
  3. Text mask: union of PyMuPDF glyph boxes (rawdict chars), converted to
     render pixels. The same pixel mask is applied to the Preview and the PDF
     render, so both sides use the same pixel population.
  4. Decomposition: squared error is split into text, image and other pixels.
     Parts add up exactly to RMSE^2 of the whole page.
  5. Evidence only: per-font and per-direction local RMSE, ink ratio, and a
     per-line integer-shift search. No shift is applied to anything.

Never fails the job; errors become notices.
Usage: diag_c6_text_residual.py <out_dir>
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import traceback

import numpy as np
import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_pdf_frame as frame_diag  # noqa: E402  (notice helper only)

W, H = 794, 1123  # gate render size (96 dpi, same as the Preview PNG)
CW, CH, CO = 790, 1119, 2  # gate crop (2 px from each side)
PX = 4.0 / 3.0  # PDF points to pixels at 96 dpi

TOKEN = re.compile(
    rb"\[[^\]]*\]|\((?:\\.|[^\\)])*\)|<[^<>]*>|/[^\s/\[\]()<>{}]*"
    rb"|[-+]?(?:\d+\.?\d*|\.\d+)|[A-Za-z'\"*]+"
)
NUMBER = re.compile(rb"[-+]?(?:\d+\.?\d*|\.\d+)")
SHOW_OPS = {"Tj", "TJ", "'", '"'}


def im(tool):
    return [tool] if shutil.which(tool) else ["magick", tool]


def strip_text(raw):
    """Remove every BT..ET text object. Returns (new_content, stats).

    Stats record what was removed: text objects, text-showing operators inside
    them, the fonts selected by Tf (anywhere in the stream), bytes removed, and
    inline images (BI), which the tokenizer does not parse.
    """
    spans = []
    start = None
    st = {
        "text_objects": 0,
        "show_ops_removed": 0,
        "unclosed_BT": 0,
        "inline_images": 0,
        "fonts_tf": {},
        "dropped_bytes": 0,
        "content_bytes": len(raw),
    }
    args = []
    pending_shows = 0  # show ops inside the current BT; counted only if it closes
    for mt in TOKEN.finditer(raw):
        tok = mt.group(0)
        if NUMBER.fullmatch(tok) or tok[:1] in (b"/", b"(", b"<", b"["):
            args.append(tok)
            continue
        op = tok.decode("latin-1")
        if op == "Tf" and len(args) >= 2:
            name = args[-2].decode("latin-1")
            st["fonts_tf"][name] = st["fonts_tf"].get(name, 0) + 1
        if op == "BI":
            st["inline_images"] += 1
        if op == "BT":
            start = mt.start()
            pending_shows = 0
        elif op == "ET" and start is not None:
            spans.append((start, mt.end()))
            st["text_objects"] += 1
            st["show_ops_removed"] += pending_shows
            start = None
            pending_shows = 0
        elif op in SHOW_OPS and start is not None:
            pending_shows += 1
        args = []
    if start is not None:
        st["unclosed_BT"] += 1
    out = []
    pos = 0
    for a, b in spans:
        out.append(raw[pos:a])
        pos = b
    out.append(raw[pos:])
    new = b"".join(out)
    st["dropped_bytes"] = len(raw) - len(new)
    return new, st


def write_pdf_stripped(src, dst):
    """Copy of src whose page content streams have the text objects removed."""
    doc = pymupdf.open(src)
    stats = []
    for page in doc:
        raw = page.read_contents() or b""
        new, st = strip_text(raw)
        stats.append(st)
        xref = doc.get_new_xref()
        doc.update_object(xref, "<<>>")
        doc.update_stream(xref, new)
        page.set_contents(xref)
    doc.save(dst)
    return stats


def text_lines(page):
    """Text lines of a page with their chars (PyMuPDF rawdict, top-origin pt)."""
    lines = []
    data = page.get_text("rawdict")
    for block in data["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block["lines"]:
            rtl = line["dir"][0] < 0
            chars = []
            for span in line["spans"]:
                for ch in span["chars"]:
                    if ch["c"].isspace():
                        continue
                    chars.append({"bbox": tuple(ch["bbox"]), "font": span["font"]})
            if chars:
                lines.append({"bbox": tuple(line["bbox"]), "rtl": rtl, "chars": chars})
    return lines


def image_boxes(page):
    return [tuple(info["bbox"]) for info in page.get_image_info()]


def box_mask(shape, boxes_pt, dilate=0):
    """Boolean mask in cropped gate coordinates for boxes given in pt."""
    m = np.zeros(shape, dtype=bool)
    h, w = shape
    for x0, y0, x1, y1 in boxes_pt:
        a = int(np.floor(x0 * PX)) - CO - dilate
        b = int(np.ceil(x1 * PX)) - CO + dilate
        c = int(np.floor(y0 * PX)) - CO - dilate
        d = int(np.ceil(y1 * PX)) - CO + dilate
        a, c = max(a, 0), max(c, 0)
        b, d = min(b, w), min(d, h)
        if b > a and d > c:
            m[c:d, a:b] = True
    return m


def sse_map(v, p):
    """Per-pixel sum of squared differences over all channels (as ImageMagick does)."""
    return ((v - p) ** 2).sum(axis=2)


def decompose(v, p, masks):
    """Split SSE into disjoint masks. masks: name -> bool HxW, must be disjoint."""
    n = v.shape[0] * v.shape[1] * v.shape[2]
    per = sse_map(v.astype(np.float64), p.astype(np.float64))
    total = float(per.sum())
    out = {"rmse_total": (total / n) ** 0.5, "parts": {}}
    covered = np.zeros(per.shape, dtype=bool)
    for name, m in masks.items():
        if np.any(covered & m):
            raise ValueError(f"mask {name} overlaps an earlier mask")
        covered |= m
        sse = float(per[m].sum())
        pix = int(m.sum())
        out["parts"][name] = {
            "pixels": pix,
            "sse": sse,
            "share": (sse / total) if total else 0.0,
            "rmse_part": (sse / n) ** 0.5,
            "local_rmse": (sse / (v.shape[2] * pix)) ** 0.5 if pix else 0.0,
        }
    return out


def ink(img):
    """Darkness per pixel in 0..1 (1 - gray) from the first three channels."""
    return 1.0 - img[..., :3].mean(axis=2)


def line_shift_probe(v, p, boxes, maxs=3, pad=2):
    """Per-line integer-shift search of v against p. Evidence only, never applied.

    Returns per-line rows (err at zero shift, best err, best dx, best dy) and
    pooled numbers. A pooled best-shift improvement is an optimistic bound
    because each line is fitted separately.
    """
    h, w = p.shape[:2]
    rows = []
    for x0, y0, x1, y1 in boxes:
        a, b = int(np.floor(x0)) + pad, int(np.ceil(x1)) - pad
        c, d = int(np.floor(y0)) + pad, int(np.ceil(y1)) - pad
        if a - maxs < 0 or c - maxs < 0 or b + maxs > w or d + maxs > h or b <= a or d <= c:
            continue
        pr = p[c:d, a:b]
        if ink(pr).sum() < 1.0:  # skip lines with almost no ink
            continue
        best = None
        err0 = None
        for dy in range(-maxs, maxs + 1):
            for dx in range(-maxs, maxs + 1):
                vs = v[c + dy:d + dy, a + dx:b + dx]
                err = float(((vs - pr) ** 2).mean())
                if dx == 0 and dy == 0:
                    err0 = err
                if best is None or err < best[0]:
                    best = (err, dx, dy)
        rows.append({"err0": err0, "best": best[0], "dx": best[1], "dy": best[2]})
    return rows


def pooled_probe(rows):
    if not rows:
        return {"lines": 0}
    e0 = np.array([r["err0"] for r in rows])
    eb = np.array([r["best"] for r in rows])
    dx = np.array([r["dx"] for r in rows])
    dy = np.array([r["dy"] for r in rows])
    return {
        "lines": len(rows),
        "zero_is_best": int(np.sum((dx == 0) & (dy == 0))),
        "median_dx": float(np.median(dx)),
        "median_dy": float(np.median(dy)),
        "pooled_mse_zero": float(e0.mean()),
        "pooled_mse_best_per_line": float(eb.mean()),
        "pooled_rmse_zero": float(np.sqrt(e0.mean())),
        "pooled_rmse_best_per_line": float(np.sqrt(eb.mean())),
        "optimistic_reduction": float(1 - eb.sum() / e0.sum()) if e0.sum() else 0.0,
    }


def rmse_im(a, b, work, tag):
    raw = subprocess.run(
        im("compare") + ["-metric", "RMSE", a, b, "null:"],
        capture_output=True,
        text=True,
    )
    text = raw.stdout + raw.stderr
    m = re.search(r"\(([0-9.eE+-]+)\)", text)
    if not m:
        raise RuntimeError("no RMSE in compare output: " + text[-200:])
    return float(m.group(1))


def load_rgb(png):
    pm = pymupdf.Pixmap(png)
    arr = np.frombuffer(pm.samples, dtype=np.uint8).reshape(pm.height, pm.width, pm.n)
    alpha_note = ""
    if pm.n == 4 and not np.all(arr[..., 3] == 255):
        alpha_note = " (non-opaque alpha present)"
    return arr.copy(), (pm.width, pm.height), alpha_note


def render(pdf, prefix):
    subprocess.run(["pdftoppm", "-r", "96", "-png", pdf, prefix], check=True)
    files = glob.glob(prefix + "-*.png")
    return sorted(files, key=lambda q: int(q.rsplit("-", 1)[1].split(".")[0]))


def normalise(src, dst):
    """The gate's steps: resize to the reference size, then crop 2 px per side."""
    subprocess.run(
        im("convert") + [src, "-resize", f"{W}x{H}!", "-crop", f"{CW}x{CH}+{CO}+{CO}", "+repage", dst],
        check=True,
    )


def reference(src, dst):
    subprocess.run(
        im("convert") + [src, "-crop", f"{CW}x{CH}+{CO}+{CO}", "+repage", dst],
        check=True,
    )


def fmt_part(name, p):
    return (
        f"{name}: pixels={p['pixels']} share_of_SSE={p['share']:.4f} "
        f"rmse_part={p['rmse_part']:.6f} local_rmse={p['local_rmse']:.6f}"
    )


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag", "text_residual")
    os.makedirs(out, exist_ok=True)
    lines = [
        "[C6-DIAG-5] text-only residual isolation (diagnostic, non-gating)",
        f"commands: pdftoppm -r 96 -png <pdf> <prefix>; convert <png> -resize {W}x{H}! "
        f"-crop {CW}x{CH}+{CO}+{CO} +repage <norm>; compare -metric RMSE <norm> <ref> null:",
    ]
    try:
        vector = os.path.join(d, "vector.pdf")
        pages = int(json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))["pageCount"])

        stripped = os.path.join(out, "notext.pdf")
        strip_stats = write_pdf_stripped(vector, stripped)
        for i, st in enumerate(strip_stats, 1):
            lines.append(
                f"p{i} strip: text_objects={st['text_objects']} show_ops_removed={st['show_ops_removed']} "
                f"unclosed_BT={st['unclosed_BT']} inline_images={st['inline_images']} "
                f"dropped_bytes={st['dropped_bytes']}/{st['content_bytes']} fonts_Tf={st['fonts_tf']}"
            )

        full_pngs = render(vector, os.path.join(out, "full"))
        text_pngs = render(stripped, os.path.join(out, "notext"))
        if len(full_pngs) != pages or len(text_pngs) != pages:
            raise RuntimeError(f"expected {pages} pages, got {len(full_pngs)} and {len(text_pngs)}")

        doc = pymupdf.open(vector)
        for i in range(pages):
            page = doc[i]
            pno = i + 1
            tag = f"p{pno}"
            full_n = os.path.join(out, f"{tag}_full.png")
            text_n = os.path.join(out, f"{tag}_notext.png")
            ref_n = os.path.join(out, f"{tag}_preview.png")
            normalise(full_pngs[i], full_n)
            normalise(text_pngs[i], text_n)
            reference(os.path.join(d, f"preview_page_{pno}.png"), ref_n)

            full, _, note_a = load_rgb(full_n)
            notext, _, note_b = load_rgb(text_n)
            prev, _, note_p = load_rgb(ref_n)
            if full.shape != (CH, CW, 3) or prev.shape != full.shape:
                raise RuntimeError(f"unexpected shapes {full.shape} {prev.shape}")

            # Validation: official RMSE (ImageMagick) against numpy on the same pair.
            official = rmse_im(full_n, ref_n, out, tag)
            fv = full.astype(np.float32) / 255.0
            pv = prev.astype(np.float32) / 255.0
            tv = notext.astype(np.float32) / 255.0
            numpy_rmse = float(np.sqrt(((fv - pv) ** 2).mean()))
            channels = fv.shape[2]
            lines.append(
                f"{tag} validation: RMSE official={official:.7f} numpy={numpy_rmse:.7f} "
                f"(gate reference {'0.0683264' if pno == 1 else '0.079265'}) alpha{note_p}"
                f"{note_a}{note_b}"
            )

            # Masks, in cropped gate coordinates.
            shape = (CH, CW)
            chars = [c for ln in text_lines(page) for c in ln["chars"]]
            t_mask = box_mask(shape, [c["bbox"] for c in chars])
            img_mask = box_mask(shape, image_boxes(page)) & ~t_mask
            other = ~(t_mask | img_mask)

            # Validity: removing text may only change pixels inside the text mask.
            diff_any = np.any(full != notext, axis=2)
            outside_changed = int(np.sum(diff_any & ~t_mask))
            inside_changed = int(np.sum(diff_any & t_mask))
            lines.append(
                f"{tag} mask validity: pixels changed by text removal outside text mask={outside_changed} "
                f"(must be 0); inside text mask={inside_changed}; text pixels={int(t_mask.sum())} "
                f"image pixels={int(img_mask.sum())} other pixels={int(other.sum())}"
            )

            # Decomposition: the full render (what the gate compares) vs the Preview.
            dec = decompose(fv, pv, {"text": t_mask, "image": img_mask, "other": other})
            lines.append(f"{tag} gate decomposition (full render vs Preview), RMSE={dec['rmse_total']:.7f}")
            for name, part in dec["parts"].items():
                lines.append("  " + fmt_part(name, part))
            # Cross-check: outside the text mask, the text-removed render gives the same SSE.
            dec_nt = decompose(tv, pv, {"text": t_mask, "image": img_mask, "other": other})
            lines.append(
                f"{tag} text-removed render vs Preview: RMSE={dec_nt['rmse_total']:.7f} "
                + "; ".join(f"{k} sse={v['sse']:.4f}" for k, v in dec_nt["parts"].items())
            )
            lines.append(
                f"{tag} non-text SSE cross-check (full vs text-removed, outside text): "
                f"{dec['parts']['image']['sse'] + dec['parts']['other']['sse']:.6f} vs "
                f"{dec_nt['parts']['image']['sse'] + dec_nt['parts']['other']['sse']:.6f}"
            )

            # Ink: how much darkness each side puts on text pixels, and where Preview ink lies.
            ink_p = ink(pv)
            ink_v = ink(fv)
            ink_p_t = float(ink_p[t_mask].sum())
            ink_v_t = float(ink_v[t_mask].sum())
            ink_p_out = float(ink_p[~t_mask].sum())
            ink_v_out = float(ink_v[~t_mask].sum())
            lines.append(
                f"{tag} ink (darkness sum): on text pixels Preview={ink_p_t:.1f} PDF={ink_v_t:.1f} "
                f"ratio PDF/Preview={ink_v_t / ink_p_t if ink_p_t else 0:.4f}; "
                f"outside text pixels Preview={ink_p_out:.1f} PDF={ink_v_out:.1f} "
                f"(graphics and images; a text mask miss would show as a Preview excess here)"
            )

            # Per font and per direction: local RMSE only (masks may touch, so no shares).
            se = sse_map(fv, pv)
            by_font = {}
            for c in chars:
                by_font.setdefault(c["font"], []).append(c["bbox"])
            for font, boxes in sorted(by_font.items()):
                m = box_mask(shape, boxes)
                pix = int(m.sum())
                lines.append(
                    f"  font {font}: chars={len(boxes)} pixels={pix} local_rmse={(float(se[m].sum()) / (channels * pix)) ** 0.5 if pix else 0:.6f}"
                )
            rtl_boxes = {True: [], False: []}
            for ln in text_lines(page):
                rtl_boxes[ln["rtl"]].extend(c["bbox"] for c in ln["chars"])
            for flag, boxes in rtl_boxes.items():
                m = box_mask(shape, boxes)
                pix = int(m.sum())
                lines.append(
                    f"  direction {'RTL' if flag else 'LTR'}: chars={len(boxes)} pixels={pix} "
                    f"local_rmse={(float(se[m].sum()) / (channels * pix)) ** 0.5 if pix else 0:.6f}"
                )

            # Positioning evidence: per-line integer-shift search, both sides.
            line_boxes = []
            for ln in text_lines(page):
                x0 = min(c["bbox"][0] for c in ln["chars"]) * PX - CO
                y0 = min(c["bbox"][1] for c in ln["chars"]) * PX - CO
                x1 = max(c["bbox"][2] for c in ln["chars"]) * PX - CO
                y1 = max(c["bbox"][3] for c in ln["chars"]) * PX - CO
                line_boxes.append((x0, y0, x1, y1))
            probe = pooled_probe(line_shift_probe(fv, pv, line_boxes))
            lines.append(f"{tag} per-line integer-shift search (+-3 px, evidence only): " + json.dumps(probe))

            fonts = [f"{f[3]}({f[1]},{f[2]})" for f in page.get_fonts()]
            lines.append(f"{tag} embedded fonts: " + ", ".join(fonts))
    except Exception:  # noqa: BLE001 - diagnostics must not fail the job
        lines.append("text residual ERROR " + traceback.format_exc()[-1200:])
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    frame_diag.notice("C6-DIAG-5 text residual", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
