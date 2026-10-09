#!/usr/bin/env python3
"""[C6-DIAG-2] TEMPORARY analysis for the three diagnostic probes.

Not for merge; removed in the cleanup commit. Diagnostic only: it reads what the
probes wrote and reports numbers. It never fails the job; each part is wrapped and
errors are reported as notices.

Usage: diag_c6_analysis.py <out_dir>   (default build/visual_parity)
Inputs (written by test/visual/diag_c6_*_probe_test.dart):
  c6diag/contract_pump_only.json, c6diag/contract_pump_yield.json
  c6diag/frame_manifest.json  (+ PNG/PDF files)
  c6diag/italic_manifest.json (+ PNG/PDF files)
"""
import json
import os
import subprocess
import sys
import traceback

import numpy as np
from PIL import Image

PT_TO_PX = 4.0 / 3.0  # 96 dpi: the same pixel grid as the gate
EPS = 1e-9


def notice(title, lines):
    """Emit the lines as ::notice annotations, chunked under the size limit."""
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
        body = "\n".join(c)
        body = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        suffix = f" ({i}/{len(chunks)})" if len(chunks) > 1 else ""
        print(f"::notice title={title}{suffix}::{body}", flush=True)


def ink_of_png(path):
    a = np.asarray(Image.open(path).convert("L"), dtype=np.float64)
    return (255.0 - a) / 255.0


def render_pdf(pdf, base):
    subprocess.run(
        ["pdftoppm", "-r", "96", "-png", "-singlefile", "-f", "1", "-l", "1", pdf, base],
        check=True,
        capture_output=True,
    )
    return base + ".png"


def fmt(v):
    return "nan" if v is None or np.isnan(v) else f"{v:+.2f}"


# ---------------------------------------------------------------- contract
def part_contract(d):
    lines = ["Contract lifecycle probe (production PdfMathRasters.rasterize, host via MaterialApp.builder)"]
    results = {}
    for name in ("contract_nohost.json", "contract_pump_only.json", "contract_pump_yield.json"):
        p = os.path.join(d, "c6diag", name)
        if not os.path.exists(p):
            lines.append(f"{name}: MISSING (probe did not write output)")
            continue
        with open(p, encoding="utf-8") as f:
            r = json.load(f)
        results[name] = r
        lines.append(
            f"{r['mode']}: done={r['done']} pumps={r['pumps']} "
            f"rasters={r['rasters']}/{r['formulas']}"
        )
        lines.append(f"  sizes={r['sizes']}")
        lines.append(f"  hashes={r['hashes']}")
        if r.get("lastFailure"):
            lines.append(f"  lastFailure={str(r['lastFailure'])[:300]}")
    if "contract_pump_only.json" in results and "contract_pump_yield.json" in results:
        a, b = results["contract_pump_only.json"], results["contract_pump_yield.json"]
        if a["rasters"] and b["rasters"]:
            lines.append(f"host pump-only vs pump+yield identical: {a['hashes'] == b['hashes']}")
        else:
            lines.append("host pump-only vs pump+yield: not comparable (pump-only produced no rasters)")
    return lines


# ---------------------------------------------------------------- frames
def _edge_stats(ip, iv, r0, r1, c0, c1, axis):
    """Centroid offset (PDF - Preview) and ink ratio of one edge window."""
    ps = ip[r0:r1, c0:c1]
    vs = iv[r0:r1, c0:c1]
    prof_p = ps.sum(axis=0 if axis == "v" else 1)
    prof_v = vs.sum(axis=0 if axis == "v" else 1)
    idx = np.arange(prof_p.size)
    cp = (idx * prof_p).sum() / prof_p.sum() if prof_p.sum() > EPS else np.nan
    cv = (idx * prof_v).sum() / prof_v.sum() if prof_v.sum() > EPS else np.nan
    off = cv - cp
    ratio = vs.sum() / ps.sum() if ps.sum() > EPS else np.nan
    return off, ratio, ps.sum(), vs.sum()


def part_frames(d):
    lines = [
        "Frame matrix (PDF minus Preview, px at 96 dpi). Offsets are centroid shifts: "
        "+x right, +y down. Ratios are PDF ink / Preview ink (1.00 = same).",
        "id | variant | stroke | dL dR dT dB | thkRatio(avgEdges) | outerRatio | perimRatio | interiorMean(bg) | boxSSE",
    ]
    mpath = os.path.join(d, "c6diag", "frame_manifest.json")
    with open(mpath, encoding="utf-8") as f:
        cases = json.load(f)["cases"]
    worst = []
    for c in cases:
        ip = ink_of_png(c["png"])
        base = os.path.join(d, "c6diag", "pdfframe_" + c["id"])
        iv = ink_of_png(render_pdf(c["pdfPath"], base))
        H, W = ip.shape
        S = c["stroke"] * PT_TO_PX
        X0, Y0 = c["x"] * PT_TO_PX, c["y"] * PT_TO_PX
        X1, Y1 = X0 + c["w"] * PT_TO_PX, Y0 + c["h"] * PT_TO_PX
        pad = int(np.ceil(S)) + 4
        r0, r1 = int(round(Y0)) + 4, int(round(Y1)) - 4
        c0, c1 = int(round(X0)) + 4, int(round(X1)) - 4
        xl, xr, yt, yb = int(round(X0)), int(round(X1)), int(round(Y0)), int(round(Y1))
        offL, rL, _, _ = _edge_stats(ip, iv, r0, r1, xl - pad, xl + pad + 1, "v")
        offR, rR, _, _ = _edge_stats(ip, iv, r0, r1, xr - pad, xr + pad + 1, "v")
        offT, rT, _, _ = _edge_stats(ip, iv, yt - pad, yt + pad + 1, c0, c1, "h")
        offB, rB, _, _ = _edge_stats(ip, iv, yb - pad, yb + pad + 1, c0, c1, "h")
        thk = np.nanmean([rL, rR, rT, rB])
        # outer half of the centred stroke (cut by a clip would show as ratio ~0)
        ob = int(np.ceil(S / 2)) + 3
        outers = []
        for (a, b, axis_rows) in [
            (xl - ob, xl - 1, True), (xr + 1, xr + ob, True),
            (yt - ob, yt - 1, False), (yb + 1, yb + ob, False),
        ]:
            if axis_rows:
                sp, sv = ip[r0:r1, max(a, 0):min(b, W)].sum(), iv[r0:r1, max(a, 0):min(b, W)].sum()
            else:
                sp, sv = ip[max(a, 0):min(b, H), c0:c1].sum(), iv[max(a, 0):min(b, H), c0:c1].sum()
            outers.append(sv / sp if sp > EPS else np.nan)
        outer = np.nanmean(outers)
        perim_p = ip[r0:r1, xl - pad:xl + pad + 1].sum() + ip[r0:r1, xr - pad:xr + pad + 1].sum()
        perim_v = iv[r0:r1, xl - pad:xl + pad + 1].sum() + iv[r0:r1, xr - pad:xr + pad + 1].sum()
        perim_p += ip[yt - pad:yt + pad + 1, c0:c1].sum() + ip[yb - pad:yb + pad + 1, c0:c1].sum()
        perim_v += iv[yt - pad:yt + pad + 1, c0:c1].sum() + iv[yb - pad:yb + pad + 1, c0:c1].sum()
        perim = perim_v / perim_p if perim_p > EPS else np.nan
        interior = np.nan
        if c["bg"]:
            ia, ib = int(round(X0 + 8)), int(round(X1 - 8))
            ja, jb = int(round(Y0 + 8)), int(round(Y1 - 8))
            interior = iv[ja:jb, ia:ib].mean()
        y0b, y1b = max(int(X0 - S - 4), 0), min(int(X1 + S + 4), W)
        ya, yb2 = max(int(Y0 - S - 4), 0), min(int(Y1 + S + 4), H)
        sse = float(((ip[ya:yb2, y0b:y1b] - iv[ya:yb2, y0b:y1b]) ** 2).sum())
        lines.append(
            f"{c['id']} | {c['variant']} | {c['stroke']} | "
            f"{fmt(offL)} {fmt(offR)} {fmt(offT)} {fmt(offB)} | "
            f"{thk:.2f} | {outer:.2f} | {perim:.2f} | "
            f"{'' if np.isnan(interior) else f'{interior:.3f}'} | {sse:.1f}"
        )
        worst.append((sse, c["id"]))
    worst.sort(reverse=True)
    lines.append("Highest box SSE: " + ", ".join(f"{i}={s:.1f}" for s, i in worst[:6]))
    return lines


# ---------------------------------------------------------------- italic
def _centroid(a):
    s = a.sum()
    if s <= EPS:
        return np.nan, np.nan
    ys, xs = np.indices(a.shape)
    return (ys * a).sum() / s, (xs * a).sum() / s


def _aligned_rmse(a, b):
    """RMSE after integer centroid alignment (b shifted to a's centroid)."""
    ca, cb = _centroid(a), _centroid(b)
    if np.isnan(ca[0]) or np.isnan(cb[0]):
        return float("nan")  # an empty band has no centroid: report, do not crash
    dy, dx = int(round(ca[0] - cb[0])), int(round(ca[1] - cb[1]))
    bs = np.roll(np.roll(b, dy, axis=0), dx, axis=1)
    return float(np.sqrt(((a - bs) ** 2).mean()))


def _lean(a):
    """Weighted slope dx/dy of ink centroid per row. Positive = top leans right."""
    rows = a.sum(axis=1)
    ys = np.arange(a.shape[0])
    xs_c = []
    keep = []
    for y in ys:
        if rows[y] > 0.5:
            xs_c.append((np.arange(a.shape[1]) * a[y]).sum() / rows[y])
            keep.append(y)
    if len(keep) < 3:
        return np.nan
    yk = np.array(keep, dtype=np.float64)
    xk = np.array(xs_c)
    slope = np.polyfit(yk, xk, 1, w=np.sqrt(rows[keep]))[0]
    return -float(slope)


def part_italic(d):
    lines = [
        "Italic isolation (Preview: TextPainter with lineHeight 1.45 assumed; PDF: regular TTF).",
        "rmse columns are after centroid alignment; lean = px per px, positive means top-right slant.",
    ]
    with open(os.path.join(d, "c6diag", "italic_manifest.json"), encoding="utf-8") as f:
        man = json.load(f)
    variants = {v["variant"]: v for v in man["variants"]}
    pv_up = ink_of_png(variants["pv_up"]["png"])
    pv_it = ink_of_png(variants["pv_it"]["png"])
    pdf_up = ink_of_png(render_pdf(variants["pdf_up"]["pdfPath"], os.path.join(d, "c6diag", "italic_pdf_up")))
    pdf_it = ink_of_png(render_pdf(variants["pdf_it"]["pdfPath"], os.path.join(d, "c6diag", "italic_pdf_it")))
    H, W = pv_up.shape
    for line in man["lines"]:
        top = int(round(line["y"] * PT_TO_PX))
        bot = min(int(round((line["y"] + 30) * PT_TO_PX)), H)
        band = lambda img: img[top:bot, :]  # noqa: E731
        bu, bi = band(pv_up), band(pv_it)
        ink_ratio = bi.sum() / bu.sum() if bu.sum() > EPS else np.nan
        line_id = line["id"]
        if not line["pdf"]:
            lines.append(
                f"{line_id} (Preview only): lean upright={_lean(bu):+.3f} italic={_lean(bi):+.3f} "
                f"inkRatio(it/up)={ink_ratio:.3f} rmse(up,it)={_aligned_rmse(bu, bi):.4f}"
            )
            continue
        du, di = band(pdf_up), band(pdf_it)
        lines.append(
            f"{line_id}: rmse(pdf_up,pdf_it)={_aligned_rmse(du, di):.6f} "
            f"rmse(pv_up,pdf_up)={_aligned_rmse(bu, du):.4f} "
            f"rmse(pv_it,pdf_up)={_aligned_rmse(bi, du):.4f} "
            f"rmse(pv_up,pv_it)={_aligned_rmse(bu, bi):.4f}"
        )
        lines.append(
            f"  lean pv_up={_lean(bu):+.3f} pv_it={_lean(bi):+.3f} "
            f"pdf_up={_lean(du):+.3f} pdf_it={_lean(di):+.3f} "
            f"inkRatio(pv it/up)={ink_ratio:.3f}"
        )
    return lines


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    os.makedirs(os.path.join(d, "c6diag"), exist_ok=True)
    parts = [
        ("C6-DIAG-2 contract", part_contract),
        ("C6-DIAG-2 frames", part_frames),
        ("C6-DIAG-2 italic", part_italic),
    ]
    for title, fn in parts:
        try:
            lines = fn(d)
        except Exception:  # noqa: BLE001 - diagnostics must not fail the job
            lines = ["ERROR: " + traceback.format_exc()[-1500:]]
        name = title.replace(" ", "_").replace("/", "_") + ".txt"
        with open(os.path.join(d, "c6diag", name), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        notice(title, lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
