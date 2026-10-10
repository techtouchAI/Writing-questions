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
        try:
            out.extend(frame_clip_report(doc, page))
        except Exception:  # noqa: BLE001
            out.append("  frame_clip_report ERROR " + traceback.format_exc()[-400:])
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


TOKEN = re.compile(
    rb"\[[^\]]*\]|\((?:\\.|[^\\)])*\)|<[^<>]*>|/[^\s/\[\]()<>{}]*"
    rb"|[-+]?(?:\d+\.?\d*|\.\d+)|[A-Za-z'\"*]+"
)
NUMBER = re.compile(rb"[-+]?(?:\d+\.?\d*|\.\d+)")
STROKE_OPS = {"S", "s", "B", "B*", "b", "b*"}
PAINT_OPS = STROKE_OPS | {"f", "F", "f*", "n"}


def _mul(m, n):
    return (
        m[0] * n[0] + m[1] * n[2],
        m[0] * n[1] + m[1] * n[3],
        m[2] * n[0] + m[3] * n[2],
        m[2] * n[1] + m[3] * n[3],
        m[4] * n[0] + m[5] * n[2] + n[4],
        m[4] * n[1] + m[5] * n[3] + n[5],
    )


def _pt(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


def _bbox(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return (min(xs), min(ys), max(xs), max(ys))


def _overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _contains(a, b):
    return a[0] <= b[0] and a[1] <= b[1] and a[2] >= b[2] and a[3] >= b[3]


def trace_content(doc, page, raw, ctm0, depth, state, clips0=(), lw0=1.0):
    """Walk one content stream. Records paint ops and the clips active at each."""
    ctm = ctm0
    stack = []
    clips = list(clips0)
    lw = lw0
    pend_clip = False
    pts = []
    args = []
    for tok in TOKEN.findall(raw):
        if NUMBER.fullmatch(tok):
            args.append(float(tok))
            continue
        if tok[:1] in (b"/", b"(", b"<", b"["):
            args.append(tok)
            continue
        op = tok.decode("latin-1")
        nums = [a for a in args if isinstance(a, float)]
        if op == "q":
            stack.append((ctm, list(clips), lw))
        elif op == "Q":
            if stack:
                ctm, clips, lw = stack.pop()
        elif op == "cm" and len(nums) >= 6:
            ctm = _mul(tuple(nums[-6:]), ctm)
        elif op == "w" and nums:
            lw = nums[-1]
        elif op == "re" and len(nums) >= 4:
            x, y, w, h = nums[-4:]
            for cx, cy in ((x, y), (x + w, y), (x + w, y + h), (x, y + h)):
                pts.append(_pt(ctm, cx, cy))
        elif op in ("m", "l") and len(nums) >= 2:
            pts.append(_pt(ctm, nums[-2], nums[-1]))
        elif op == "c" and len(nums) >= 6:
            for i in (0, 2, 4):
                pts.append(_pt(ctm, nums[-6 + i], nums[-5 + i]))
        elif op in ("v", "y") and len(nums) >= 4:
            for i in (0, 2):
                pts.append(_pt(ctm, nums[-4 + i], nums[-3 + i]))
        elif op in ("W", "W*"):
            pend_clip = True
        elif op == "Do" and depth < 4:
            name = args[-1][1:].decode("latin-1") if args and isinstance(args[-1], bytes) else ""
            xref = state["xobjects"].get(name)
            if xref is not None and _is_image(doc, xref):
                # An image occupies the unit square in user space.
                state["records"].append(
                    {
                        "op": "Do:image",
                        "bbox": _bbox([_pt(ctm, 0, 0), _pt(ctm, 1, 0), _pt(ctm, 1, 1), _pt(ctm, 0, 1)]),
                        "dev_w": None,
                        "clips": list(clips),
                        "depth": depth,
                    }
                )
            elif xref is None:
                state["unresolved"] += 1
                state.setdefault("unresolved_names", []).append(name)
                state["records"].append(
                    {
                        "op": "Do:unresolved",
                        "bbox": _bbox([_pt(ctm, 0, 0), _pt(ctm, 1, 0), _pt(ctm, 1, 1), _pt(ctm, 0, 1)]),
                        "dev_w": None,
                        "clips": list(clips),
                        "depth": depth,
                    }
                )
            else:
                fm = _form_matrix(doc, xref)
                trace_content(
                    doc,
                    page,
                    doc.xref_stream(xref) or b"",
                    _mul(fm, ctm),
                    depth + 1,
                    state,
                    clips,
                    lw,
                )
                state["forms"] += 1
        elif op in PAINT_OPS:
            bbox = _bbox(pts) if pts else None
            if pend_clip and bbox:
                clips.append(bbox)
            if bbox and not pend_clip:
                dev_w = lw * abs(ctm[0] * ctm[3] - ctm[1] * ctm[2]) ** 0.5
                state["records"].append(
                    {
                        "op": op,
                        "bbox": bbox,
                        "dev_w": dev_w if op in STROKE_OPS else None,
                        "clips": list(clips),
                        "depth": depth,
                    }
                )
            pend_clip = False
            pts = []
        args = []
    return ctm


def _is_image(doc, xref):
    try:
        return doc.xref_get_key(xref, "Subtype")[1] == "/Image"
    except Exception:  # noqa: BLE001
        return False


def _form_matrix(doc, xref):
    try:
        kind, val = doc.xref_get_key(xref, "Matrix")
        if kind == "array":
            nums = [float(v) for v in val.strip("[] ").split()]
            if len(nums) == 6:
                return tuple(nums)
    except Exception:  # noqa: BLE001
        pass
    return (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


FRAME_CHECK_PT = (87.76, 221.77, 177.76, 289.27)


def frame_clip_report(doc, page):
    """Which clip paths partly cut the frame stroke, in top-origin page points."""
    H = page.mediabox.y1
    state = {"xobjects": {}, "records": [], "forms": 0, "unresolved": 0}
    for entry in page.get_xobjects():
        state["xobjects"][entry[7]] = entry[0]
    for entry in page.get_images(full=True):
        state["xobjects"].setdefault(entry[7], entry[0])
    raw = page.read_contents() or b""
    trace_content(doc, page, raw, (1.0, 0.0, 0.0, 1.0, 0.0, 0.0), 0, state)

    def top(b):
        return (b[0], H - b[3], b[2], H - b[1])

    fx0, fy0, fx1, fy1 = FRAME_CHECK_PT
    frame = (fx0 - 4, fy0 - 4, fx1 + 4, fy1 + 4)
    lines = [
        f"  trace: page H={H:.2f} forms={state['forms']} unresolved_Do={state['unresolved']} "
        f"unresolved_names={state.get('unresolved_names', [])} "
        f"xobjects={sorted(state['xobjects'])} paint_ops={len(state['records'])}"
    ]
    for rec in state["records"]:
        b = top(rec["bbox"])
        if not _overlap(b, frame):
            continue
        if rec["op"].startswith("Do:"):
            lines.append(
                f"  frame {rec['op']} d={rec['depth']} bbox=({b[0]:.2f},{b[1]:.2f},{b[2]:.2f},{b[3]:.2f})"
            )
            continue
        half = (rec["dev_w"] or 0.0) / 2.0  # a stroke reaches half its width past the path
        ext = (b[0] - half, b[1] - half, b[2] + half, b[3] + half)
        cutters = [top(c) for c in rec["clips"] if _overlap(top(c), ext) and not _contains(top(c), ext)]
        lines.append(
            f"  frame op={rec['op']} d={rec['depth']} bbox=({b[0]:.2f},{b[1]:.2f},{b[2]:.2f},{b[3]:.2f}) "
            f"dev_w={rec['dev_w'] if rec['dev_w'] is None else round(rec['dev_w'], 3)} "
            f"clips_active={len(rec['clips'])} partial_cutters={len(cutters)}"
        )
        for c in cutters[:12]:
            lines.append(f"    cutter ({c[0]:.2f},{c[1]:.2f},{c[2]:.2f},{c[3]:.2f})")
    return lines


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


def _edge_ink(pm, x0, y0, x1, y1):
    """Ink per edge (px) of the box x0..x1, y0..y1 (already in px)."""
    pad = 6
    rows = range(y0 + 6, y1 - 6)
    cols = range(x0 + 6, x1 - 6)
    res = {}
    for name, xs in (("left", range(x0 - pad, x0 + pad)), ("right", range(x1 - pad, x1 + pad))):
        res[name] = sum(sum(_ink(pm, x, y) for y in rows) / len(rows) for x in xs)
    for name, ys in (("top", range(y0 - pad, y0 + pad)), ("bottom", range(y1 - pad, y1 + pad))):
        res[name] = sum(sum(_ink(pm, x, y) for x in cols) / len(cols) for y in ys)
    return res


def poppler_stroke_probe(out_dir):
    """Render isolated 2 pt rectangles with the gate's pdftoppm (Poppler).

    Same size and page as the fixture frame (90 x 67.5 pt). Cases: unclipped at
    three x offsets, and clipped to its own box. Ink per edge in px at 96 dpi
    (centred 2 pt stroke ~ 2.67 px; clipped ~ 1.33 px).
    """
    import glob
    import shutil
    import subprocess

    import pymupdf

    if shutil.which("pdftoppm") is None:
        return ["poppler probe: pdftoppm not on PATH"]
    W, H = 595.0, 842.0
    w, h, y0 = 90.0, 67.5, 200.0
    cases = [
        ("unclipped dx0", 100.0, False),
        ("unclipped dx0.25", 100.25, False),
        ("unclipped dx0.5", 100.5, False),
        ("clipped dx0", 100.0, True),
    ]
    doc = pymupdf.open()
    for _name, x, clip in cases:
        page = doc.new_page(width=W, height=H)
        if clip:
            body = (
                f"q {x} {y0} {w} {h} re W n 0 0 0 RG 2 w {x} {y0} {w} {h} re S Q\n"
            )
        else:
            body = f"q 0 0 0 RG 2 w {x} {y0} {w} {h} re S Q\n"
        xref = doc.get_new_xref()
        doc.update_object(xref, "<<>>")
        doc.update_stream(xref, body.encode("ascii"))
        page.set_contents(xref)
    pdf = os.path.join(out_dir, "c6diag", "poppler_stroke.pdf")
    os.makedirs(os.path.dirname(pdf), exist_ok=True)
    doc.save(pdf)
    prefix = os.path.join(out_dir, "c6diag", "poppler_stroke")
    subprocess.run(["pdftoppm", "-r", "96", "-png", pdf, prefix], check=True)
    pngs = sorted(glob.glob(prefix + "-*.png"))
    lines = [f"poppler probe: {len(pngs)} pages, box {w}x{h} pt at y={y0}"]
    k = 4.0 / 3.0
    for (name, x, _clip), png in zip(cases, pngs):
        pm = pymupdf.Pixmap(png)
        x0, x1 = round(x * k), round((x + w) * k)
        y_top = round((H - (y0 + h)) * k)
        y_bot = round((H - y0) * k)
        e = _edge_ink(pm, x0, y_top, x1, y_bot)
        lines.append(
            f"  {name}: left={e['left']:.2f} right={e['right']:.2f} "
            f"top={e['top']:.2f} bottom={e['bottom']:.2f} px"
        )
    return lines


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
        lines.extend(poppler_stroke_probe(d))
    except Exception:  # noqa: BLE001
        lines.append("poppler probe ERROR " + traceback.format_exc()[-600:])
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
