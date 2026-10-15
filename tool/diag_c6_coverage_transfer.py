"""[C6-DIAG-11] Coverage-transfer experiment (SYNTHETIC ONLY, diagnostic, non-gating).

Question. The real residual has PDF text carrying more ink than Preview text
(DIAG-5/DIAG-8). Which transformations of glyph coverage, or of glyph geometry,
produce that signature, and does the signature separate them?

Design (to avoid fitting a reference):
  * The "PDF" side is the base render B of a known synthetic page.
  * Each truth variant V is a transformation with a KNOWN definition (gain,
    gamma, blur, sub-pixel translation, font-size change, emboldening,
    supersampled rasterisation). R_V = V(B) is the stand-in for the other side.
  * For each V the signature panel is computed on B vs R_V, with exactly the same
    code. Nothing is fitted to any real reference image.
  * Two independent word sets: H (hypothesis-building, used to pick the metrics
    and check they are stable) and T (held out, the table reported).

Limits. MuPDF is the only rasteriser here. Poppler and Preview are not run, so none
of these numbers is a measurement of the C6 fixture. They show which signatures
each mechanism produces, so a real measurement can be interpreted.

Outputs: build/visual_parity/c6diag/coverage_transfer/ only.
"""

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diag_c6_mask_validity as mv  # noqa: E402  (scale, crop, render helpers)

import pymupdf  # noqa: E402

OUT_DIR = os.path.join("build", "visual_parity", "c6diag", "coverage_transfer")
EDGE_LO, EDGE_HI = 0.05, 0.95  # partial-coverage band for "edge" pixels
SS = 4  # supersampling factor for the rasteriser variant

# Word sets. H: hypothesis-building. T: held-out table set. Different words, sizes, rows.
# Latin only: the base-14 Helvetica used here has no Arabic glyphs.
WORDS_H = ["Hello", "Mask", "Check", "Alpha", "Beta", "Gamma", "Delta", "Water", "Mirror", "Plain"]
WORDS_T = ["Writing", "Glyph", "Offset", "Kernel", "Stroke", "Vector", "Raster", "Contour", "Pixel", "Frame"]


def content_for(words, size_scale=1.0, dx_pt=0.0, dy_pt=0.0, embolden_pt=0.0, seed_rows=16):
    """Content stream: black Helvetica words on a staggered grid (same geometry for all variants).

    embolden_pt > 0 uses text render mode 2 (fill + stroke) with that line width.
    """
    lines = []
    k = 0
    for row in range(seed_rows):
        for col in range(4):
            fs = [8, 9, 10, 11, 12, 14][(row * 3 + col) % 6] * size_scale
            x = 40 + col * 135 + dx_pt
            y = 60 + row * 48 + 0.37 * col + dy_pt  # top-origin baseline, converted below
            word = words[k % len(words)]
            k += 1
            mode = "2 Tr" if embolden_pt > 0 else "0 Tr"
            lw = f"{embolden_pt:.4f} w" if embolden_pt > 0 else ""
            # PyMuPDF y is top-origin; PDF content is bottom-origin.
            ypdf = mv.PH - y
            lines.append(f"0 g 0 G {mode} {lw} BT /F1 {fs:.3f} Tf 1 0 0 1 {x:.3f} {ypdf:.3f} Tm ({word}) Tj ET")
    return "\n".join(lines) + "\n"


def build_pdf(path, words, **kw):
    d = pymupdf.open()
    d.new_page(width=mv.PW, height=mv.PH)
    page = d[0]
    page.insert_font(fontname="helv")  # Helvetica base-14 font resource
    fname = page.get_fonts()[0][4]
    body = content_for(words, **kw).replace("/F1", f"/{fname}")
    xref = d.get_new_xref()
    d.update_object(xref, "<<>>")
    d.update_stream(xref, body.encode("latin-1"))
    page.set_contents(xref)
    d.save(path)
    d.close()
    return path


def render_cov(path, supersample=False):
    """Coverage in [0,1] (text is black on white), cropped to the gate frame."""
    doc = pymupdf.open(path)
    if supersample:
        pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(SS * mv.SX, SS * mv.SY), alpha=False)
        arr = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, 3)
        arr = arr[SS * mv.CO : SS * (mv.CO + mv.CH), SS * mv.CO : SS * (mv.CO + mv.CW)].astype(np.float32) / 255.0
        g = 1.0 - arr.mean(axis=2)
        return g.reshape(mv.CH, SS, mv.CW, SS).mean(axis=(1, 3))
    arr = mv.render_gate(doc)
    return 1.0 - arr.mean(axis=2)


# ---- truth transformations on coverage (post-process) ----

def v_gain(cov, g=0.77):
    return np.clip(cov * g, 0.0, 1.0)


def v_gamma(cov, gam=1.3):
    return np.clip(cov, 0.0, 1.0) ** gam


def v_blur(cov):
    p = np.pad(cov, 1, mode="edge")
    acc = np.zeros_like(cov)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            acc += p[dy : dy + cov.shape[0], dx : dx + cov.shape[1]]
    return acc / 9.0


# ---- signature panel: PDF side (B) vs other side (R) ----

def classes(c):
    """0 empty (< EDGE_LO), 1 partial (EDGE_LO..EDGE_HI), 2 full (>= EDGE_HI)."""
    return np.where(c >= EDGE_HI, 2, np.where(c > EDGE_LO, 1, 0))


def transitions(B, R):
    """3x3 counts: rows = class on the PDF side (B), columns = class on the other side (R)."""
    cb, cr = classes(B).ravel(), classes(R).ravel()
    m = np.zeros((3, 3), dtype=np.int64)
    np.add.at(m, (cb, cr), 1)
    return m


def signature(B, R):
    """Ratios PDF/other (matching the real direction: >1 means the PDF side is heavier)."""
    def stats(c):
        edge = (c > EDGE_LO) & (c < EDGE_HI)
        full = c >= EDGE_HI
        w = c.sum()
        ys, xs = np.indices(c.shape)
        cx = (c * xs).sum() / max(w, 1e-9)
        cy = (c * ys).sum() / max(w, 1e-9)
        return {
            "ink": float(w),
            "edge_px": int(edge.sum()),
            "full_px": int(full.sum()),
            "full_mass": float(c[full].sum()),
            "edge_mean": float(c[edge].mean()) if edge.any() else 0.0,
            "cx": float(cx),
            "cy": float(cy),
        }

    sb, sr = stats(B), stats(R)

    def ratio(a, b):
        return None if b <= 0 else a / b  # undefined when the other side has none

    tr = transitions(B, R)
    moved = int(tr.sum() - np.trace(tr))  # pixels whose coverage class differs between the sides
    return {
        "transitions": tr.tolist(),  # [[empty->empty, empty->partial, empty->full], ...]
        "class_moved_px": moved,
        "partial_px_pdf": sb["edge_px"],
        "partial_px_other": sr["edge_px"],
        "partial_mass_pdf": float(B[(B > EDGE_LO) & (B < EDGE_HI)].sum()),
        "partial_mass_other": float(R[(R > EDGE_LO) & (R < EDGE_HI)].sum()),
        "total_ink_ratio": ratio(sb["ink"], sr["ink"]),
        "edge_px_ratio": ratio(sb["edge_px"], sr["edge_px"]),
        "full_px_ratio": ratio(sb["full_px"], sr["full_px"]),
        "full_mass_ratio": ratio(sb["full_mass"], sr["full_mass"]),
        "edge_mean_ratio": ratio(sb["edge_mean"], sr["edge_mean"]),
        "centroid_dx_px": sb["cx"] - sr["cx"],
        "centroid_dy_px": sb["cy"] - sr["cy"],
        "pdf_px": {"edge": sb["edge_px"], "full": sb["full_px"]},
        "other_px": {"edge": sr["edge_px"], "full": sr["full_px"]},
    }


PHASES_PX = (0.0, 0.25, 0.5, 0.75)  # common sub-pixel grid phase applied to both sides


def variants(work, words, tag, phase_px=0.0):
    """Return {name: (B, R)} for one word set and one grid phase. B is the base render.

    The phase is a common x offset in device px applied to every build (both sides),
    so it is a nuisance factor, not a variable of the experiment.
    """
    ph = phase_px / mv.SX
    tg = f"{tag}_p{int(round(phase_px * 100)):03d}"
    base_pdf = build_pdf(os.path.join(work, f"{tg}_base.pdf"), words, dx_pt=ph)
    B = render_cov(base_pdf)
    out = {}
    out["control_identity"] = (B, B.copy())
    out["gain_0.77"] = (B, v_gain(B, 0.77))
    out["gamma_1.3"] = (B, v_gamma(B, 1.3))
    out["blur_3x3"] = (B, v_blur(B))
    out["supersample_4x_rasteriser"] = (B, render_cov(base_pdf, supersample=True))
    shift_pdf = build_pdf(os.path.join(work, f"{tg}_shift.pdf"), words, dx_pt=ph + 0.25 / mv.SX)
    out["shift_0.25px_x"] = (B, render_cov(shift_pdf))
    size_pdf = build_pdf(os.path.join(work, f"{tg}_size97.pdf"), words, size_scale=0.97, dx_pt=ph)
    out["font_size_0.97"] = (B, render_cov(size_pdf))
    size_up = build_pdf(os.path.join(work, f"{tg}_size103.pdf"), words, size_scale=1.03, dx_pt=ph)
    out["font_size_1.03"] = (B, render_cov(size_up))
    # Equal-total-ink variants: chosen so the total ink ratio is near the real p2 value
    # (1.297). They test whether the other signatures separate the mechanisms. Not fitted.
    eq_size = build_pdf(os.path.join(work, f"{tg}_size088.pdf"), words, size_scale=0.88, dx_pt=ph)
    out["EQ_font_size_0.88"] = (B, render_cov(eq_size))
    out["EQ_gamma_2.0"] = (B, v_gamma(B, 2.0))
    emb_pdf = build_pdf(os.path.join(work, f"{tg}_emb.pdf"), words, embolden_pt=0.2, dx_pt=ph)
    out["embolden_0.2pt_other_side_heavier"] = (B, render_cov(emb_pdf))
    return out


def run(out_dir=OUT_DIR, work_dir=None):
    os.makedirs(out_dir, exist_ok=True)
    work = work_dir or out_dir
    result = {"synthetic": True, "phases_px": list(PHASES_PX), "sets": {}}
    for tag, words in (("H", WORDS_H), ("T", WORDS_T)):
        per_phase = {}  # name -> list of signatures, one per phase
        for ph in PHASES_PX:
            for name, (B, R) in variants(work, words, tag, ph).items():
                per_phase.setdefault(name, []).append(signature(B, R))
        sigs = {}
        for name, lst in per_phase.items():
            agg = {"phase0_transitions": lst[0]["transitions"], "phase0_class_moved_px": lst[0]["class_moved_px"],
                   "phase0_partial_px": [lst[0]["partial_px_pdf"], lst[0]["partial_px_other"]],
                   "phase0_partial_mass": [round(lst[0]["partial_mass_pdf"], 3), round(lst[0]["partial_mass_other"], 3)]}
            for k in ("total_ink_ratio", "edge_px_ratio", "full_px_ratio", "full_mass_ratio", "edge_mean_ratio", "centroid_dx_px", "centroid_dy_px"):
                vals = [x[k] for x in lst if x[k] is not None]
                agg[k] = {
                    "mean": float(np.mean(vals)) if vals else None,
                    "min": float(np.min(vals)) if vals else None,
                    "max": float(np.max(vals)) if vals else None,
                    "n": len(vals),
                }
            sigs[name] = agg
        result["sets"][tag] = sigs
    with open(os.path.join(out_dir, "coverage_transfer_synthetic.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    return result


def _fmt(a):
    if a["mean"] is None:
        return "n/a".rjust(22)
    return f"{a['mean']:7.3f} [{a['min']:6.3f},{a['max']:6.3f}]"


def table_lines(result):
    keys = ["total_ink_ratio", "edge_px_ratio", "full_px_ratio", "full_mass_ratio", "edge_mean_ratio", "centroid_dx_px"]
    lines = [
        "[C6-DIAG-11] coverage-transfer, SYNTHETIC (MuPDF only; not Poppler, not Preview, not gate evidence)",
        "Signature = PDF side / other side (mean [min,max] over grid phases " + ", ".join(f"{p:.2f}" for p in result["phases_px"]) + " px).",
        "Set T = reported table. Set H = hypothesis-building set, shown only for stability.",
        "variant".ljust(34) + " | " + " | ".join(k[:22].rjust(22) for k in keys),
    ]
    for name in result["sets"]["T"]:
        t = result["sets"]["T"][name]
        h = result["sets"]["H"][name]
        lines.append(name.ljust(34) + " | " + " | ".join(_fmt(t[k]) for k in keys))
        lines.append("   H total/edge/full: " + " ".join(f"{h[k]['mean']:.3f}" if h[k]["mean"] is not None else "n/a" for k in keys[:3]))
        tr = t["phase0_transitions"]
        lines.append(f"   T phase0: moved px={t['phase0_class_moved_px']}; partial px (PDF,other)={t['phase0_partial_px']}; "
                     f"partial mass (PDF,other)={t['phase0_partial_mass']}; "
                     f"transitions empty->partial/full={tr[0][1]}/{tr[0][2]}, partial->empty/full={tr[1][0]}/{tr[1][2]}, full->empty/partial={tr[2][0]}/{tr[2][1]}")
    return lines


def main():
    res = run()
    lines = table_lines(res)
    with open(os.path.join(OUT_DIR, "coverage_transfer_synthetic.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
