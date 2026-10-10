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
        raw = b"".join(page.read_contents() or [b""])
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
    os.makedirs(os.path.join(d, "c6diag"), exist_ok=True)
    with open(os.path.join(d, "c6diag", "pdf_frame.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    notice("C6-DIAG-3 pdf frame", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
