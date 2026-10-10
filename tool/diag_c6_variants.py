#!/usr/bin/env python3
"""[C6-DIAG-4] TEMPORARY diagnostic: whole-page RMSE of PDF variants. Not for merge.

Uses the gate's own Vector PDF and Preview PNGs and the gate's comparison steps
(pdftoppm -r 96; convert -resize WxH!; crop 2 px; compare -metric RMSE), so the
baseline must reproduce the gate's numbers before any variant is read.

Variants (diagnostic copies only, written to build/visual_parity/c6diag/variants):
  base      the gate's Vector PDF as produced
  ring      page 1 frame stroke replaced by a filled even-odd ring (same colour,
            same outer/inner bounds as the 2 pt centred stroke). Page 2 has no
            frame and is a control.
  shift_x/y whole page translated by +-0.25 and +-0.5 pt (text registration probe).

Never fails the job; errors become notices.
Usage: diag_c6_variants.py <out_dir>
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import traceback

import pymupdf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_pdf_frame as frame_diag  # noqa: E402  (same directory)

W, H = 794, 1123
CW, CH, CO = 790, 1119, 2
RING_RGB = "0.0667 0.0941 0.1529"  # #111827, the frame's colour in the PDF
FRAME_W, FRAME_H = 90.0, 67.5  # frame box in pt (120 x 90 px fixture)
RE_STROKE = re.compile(
    rb"([-+]?\d*\.?\d+) ([-+]?\d*\.?\d+) ([-+]?\d*\.?\d+) ([-+]?\d*\.?\d+) re\s+S\b"
)


def _im(tool):
    if shutil.which(tool):
        return [tool]
    return ["magick", tool]


def rmse(a, b):
    r = subprocess.run(
        _im("compare") + ["-metric", "RMSE", a, b, "null:"],
        capture_output=True,
        text=True,
    )
    raw = r.stdout + r.stderr
    m = re.search(r"\(([0-9.eE+-]+)\)", raw)
    if not m:
        raise RuntimeError("no RMSE in compare output: " + raw[-200:])
    return float(m.group(1))


def render(pdf, prefix):
    subprocess.run(["pdftoppm", "-r", "96", "-png", pdf, prefix], check=True)
    files = glob.glob(prefix + "-*.png")
    return sorted(files, key=lambda q: int(q.rsplit("-", 1)[1].split(".")[0]))


def page_rmse(rendered, preview, work, tag):
    """Same steps as tool/verify_visual_parity.sh for one page."""
    norm = os.path.join(work, f"{tag}_norm.png")
    ref = os.path.join(work, f"{tag}_ref.png")
    subprocess.run(
        _im("convert")
        + [rendered, "-resize", f"{W}x{H}!", "-crop", f"{CW}x{CH}+{CO}+{CO}", "+repage", norm],
        check=True,
    )
    subprocess.run(
        _im("convert") + [preview, "-crop", f"{CW}x{CH}+{CO}+{CO}", "+repage", ref],
        check=True,
    )
    return rmse(norm, ref)


def ring_content(raw):
    """Replace the single 90 x 67.5 pt stroked rectangle with a filled ring.

    Signed sizes are accepted (a flipped CTM gives a negative height). The ring
    is built from the normalised rectangle, 1 pt outside and inside its edges.
    Returns (content, matches), or (content, 0) with candidates when not unique.
    """
    hits = []
    cands = []
    for m in RE_STROKE.finditer(raw):
        x, y, w, h = (float(v) for v in m.groups())
        if abs(abs(w) - FRAME_W) < 0.05 and abs(abs(h) - FRAME_H) < 0.05:
            hits.append(m)
        if max(abs(w), abs(h)) > 40 and len(cands) < 6:
            before = raw[max(0, m.start() - 60):m.start()].decode("latin-1").replace("\n", " | ")
            cands.append(f"{x:.2f} {y:.2f} {w:.2f} {h:.2f} re S <- [{before}]")
    if len(hits) != 1:
        return raw, f"{len(hits)} matches; large re S candidates: {cands}"
    m = hits[0]
    x, y, w, h = (float(v) for v in m.groups())
    x0 = x if w > 0 else x + w
    y0 = y if h > 0 else y + h
    W, H = abs(w), abs(h)
    rep = (
        f"q {RING_RGB} rg {x0 - 1:.4f} {y0 - 1:.4f} {W + 2:.4f} {H + 2:.4f} re "
        f"{x0 + 1:.4f} {y0 + 1:.4f} {W - 2:.4f} {H - 2:.4f} re f* Q"
    ).encode("ascii")
    return raw[: m.start()] + rep + raw[m.end():], 1


def write_pdf(src, dst, transform):
    doc = pymupdf.open(src)
    report = []
    for page in doc:
        raw = page.read_contents() or b""
        new, info = transform(raw)
        report.append(info)
        xref = doc.get_new_xref()
        doc.update_object(xref, "<<>>")
        doc.update_stream(xref, new)
        page.set_contents(xref)
    doc.save(dst)
    return report


def shift_transform(dx, dy):
    def transform(raw):
        return (f"q 1 0 0 1 {dx} {dy} cm\n".encode("ascii") + raw + b"\nQ\n"), "shifted"

    return transform


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag")
    work = os.path.join(out, "variants")
    os.makedirs(work, exist_ok=True)
    lines = [f"tools: {_im('compare')[-1]} / {_im('convert')[-1]}, pdftoppm -r 96, resize {W}x{H}, crop {CO}px"]
    try:
        pages = int(json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))["pageCount"])
        src = os.path.join(d, "vector.pdf")
        previews = {i: os.path.join(d, f"preview_page_{i}.png") for i in range(1, pages + 1)}

        variants = [("base", src)]
        ring_pdf = os.path.join(work, "ring.pdf")
        ring_info = write_pdf(src, ring_pdf, ring_content)
        lines.append(f"ring: frame stroke matches per page = {ring_info}")
        variants.append(("ring", ring_pdf))
        for axis in ("x", "y"):
            for amt in (-0.5, -0.25, 0.25, 0.5):
                dx, dy = (amt, 0.0) if axis == "x" else (0.0, amt)
                name = f"shift_{axis}{amt:+.2f}"
                dst = os.path.join(work, name + ".pdf")
                write_pdf(src, dst, shift_transform(dx, dy))
                variants.append((name, dst))

        base_vals = None
        for name, pdf in variants:
            rendered = render(pdf, os.path.join(work, name))
            vals = [
                page_rmse(rendered[i - 1], previews[i], work, f"{name}_p{i}")
                for i in range(1, pages + 1)
            ]
            per_page = ", ".join(f"p{i + 1}={v:.7f}" for i, v in enumerate(vals))
            if name == "base":
                base_vals = vals
                lines.append(f"base: RMSE {per_page}  (gate: p1=0.0683264 p2=0.079265)")
            else:
                delta = ", ".join(f"{v - b:+.7f}" for v, b in zip(vals, base_vals))
                lines.append(f"{name}: RMSE {per_page}  delta {delta}")
            if name in ("base", "ring"):
                pm = pymupdf.Pixmap(rendered[0])
                k = 4.0 / 3.0
                x0, y0, x1, y1 = (v * k for v in frame_diag.FRAME_PT)
                e = frame_diag._edge_ink(pm, round(x0), round(y0), round(x1), round(y1))
                lines.append(
                    f"  {name} p1 frame edge ink px: left={e['left']:.2f} right={e['right']:.2f} "
                    f"top={e['top']:.2f} bottom={e['bottom']:.2f}"
                )
    except Exception:  # noqa: BLE001 - diagnostics must not fail the job
        lines.append("variants ERROR " + traceback.format_exc()[-900:])
    with open(os.path.join(out, "variants.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    frame_diag.notice("C6-DIAG-4 variants", lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
