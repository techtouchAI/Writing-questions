#!/usr/bin/env python3
"""[C6-DIAG-3] TEMPORARY: read the gate's Vector PDF directly. Not for merge.

Reports, per PDF in <out_dir>: clip operators (W n / W* n) in the page content
stream, and stroked paths whose size matches the fixture's framed square
(120 x 90 pt or 160 x 120 px). Never fails the job; errors become notices.

Usage: diag_c6_pdf_frame.py <out_dir>
"""
import os
import re
import sys
import traceback

CLIP = re.compile(rb"W\*? n")


def notice(title, lines):
    chunks, chunk, size = [], [], 0
    for ln in lines:
        if size + len(ln) + 1 > 3000 and chunk:
            chunks.append(chunk)
            chunk, size = [], 0
        chunk.append(ln)
        size += len(ln) + 1
    if chunk:
        chunks.append(chunk)
    for i, c in enumerate(chunks, 1):
        body = "\n".join(c).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        suffix = f" ({i}/{len(chunks)})" if len(chunks) > 1 else ""
        print(f"::notice title={title}{suffix}::{body}", flush=True)


def inspect(path):
    import pymupdf  # PyMuPDF, installed by the workflow step

    out = [f"{os.path.basename(path)}:"]
    doc = pymupdf.open(path)
    out.append(f"  pages={doc.page_count}")
    for pno in range(min(doc.page_count, 2)):
        page = doc[pno]
        raw = page.read_contents() or b""  # bytes in PyMuPDF >= 1.2x
        clips = len(CLIP.findall(raw))
        out.append(f"  p{pno + 1}: content={len(raw)}B clip_ops={clips}")
        for dr in page.get_drawings():
            r = dr["rect"]
            near_frame = (80 <= r.width <= 140 and 60 <= r.height <= 110) or (
                110 <= r.width <= 210 and 80 <= r.height <= 160
            )
            if not near_frame:
                continue
            out.append(
                f"  p{pno + 1} path rect=({r.x0:.2f},{r.y0:.2f},{r.x1:.2f},{r.y1:.2f}) "
                f"w={dr.get('width')} fill={dr.get('fill')} color={dr.get('color')} "
                f"items={len(dr['items'])}"
            )
    return out


# Frame box from the Vector PDF (pt), page 1: (87.76, 221.77) - (177.76, 289.27).
# Rendered at 96 dpi, 1 pt = 4/3 px. Each window covers the edge zone, away from corners.
FRAME_PT = (87.76, 221.77, 177.76, 289.27)


def _ink(pm, x, y):
    n = pm.n
    i = (y * pm.width + x) * n
    ch = min(3, n)
    gray = sum(pm.samples[i:i + ch]) / ch
    return (255.0 - gray) / 255.0


def edge_thickness(path):
    """Ink per row or column for each frame edge, in px (centred 2 pt stroke ~ 2.67 px)."""
    import pymupdf

    pm = pymupdf.Pixmap(path)
    k = 4.0 / 3.0
    x0, y0, x1, y1 = (v * k for v in FRAME_PT)
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    pad = 6
    rows = range(y0 + 6, y1 - 6)
    cols = range(x0 + 6, x1 - 6)
    out = []
    for name, xs in (("left", range(x0 - pad, x0 + pad)), ("right", range(x1 - pad, x1 + pad))):
        ink = [sum(_ink(pm, x, y) for y in rows) / len(rows) for x in xs]
        out.append(f"{name} ink_sum={sum(ink):.2f} px")
    for name, ys in (("top", range(y0 - pad, y0 + pad)), ("bottom", range(y1 - pad, y1 + pad))):
        ink = [sum(_ink(pm, x, y) for x in cols) / len(cols) for y in ys]
        out.append(f"{name} ink_sum={sum(ink):.2f} px")
    return f"{os.path.basename(path)} {pm.width}x{pm.height}: " + "; ".join(out)


def rendered_frames(d):
    lines = []
    pngs = []
    for root, _dirs, files in os.walk(d):
        for f in files:
            if f.lower().endswith(".png"):
                pngs.append(os.path.join(root, f))
    lines.append(f"png files: {len(pngs)}")
    for path in sorted(pngs)[:30]:
        lines.append("  " + os.path.relpath(path, d))
    for path in sorted(pngs):
        rel = os.path.relpath(path, d).lower()
        if ("vector" in rel or "preview" in rel) and ("p1" in rel or "page-1" in rel or "page1" in rel or "-1." in rel or "_1." in rel or "1.png" in rel):
            try:
                lines.append(edge_thickness(path))
            except Exception:  # noqa: BLE001
                lines.append(f"{rel}: ERROR " + traceback.format_exc()[-300:])
    return lines


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    lines = []
    for name in sorted(os.listdir(d)):
        if not name.lower().endswith(".pdf"):
            continue
        try:
            lines.extend(inspect(os.path.join(d, name)))
        except Exception:  # noqa: BLE001 - diagnostics must not fail the job
            lines.append(f"{name}: ERROR " + traceback.format_exc()[-600:])
    if not lines:
        lines = ["no PDF found in " + d]
    try:
        lines.extend(rendered_frames(d))
    except Exception:  # noqa: BLE001
        lines.append("rendered_frames ERROR " + traceback.format_exc()[-600:])
    os.makedirs(os.path.join(d, "c6diag"), exist_ok=True)
    with open(os.path.join(d, "c6diag", "pdf_frame.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    notice("C6-DIAG-3 pdf frame", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
