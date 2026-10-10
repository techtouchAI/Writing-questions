#!/usr/bin/env python3
"""C6-DIAG-8: glyph-edge coverage profile, Preview vs the gate's PDF raster (diagnostic, non-gating).

Question: where does the extra text ink of the PDF sit? In glyph interiors (more fully
covered pixels, which would suggest larger or heavier glyphs), in the glyph boundary
(full pixels next to partial ones), or in the partial-coverage edge pixels themselves
(edge darkness: rasterisation, gamma or coverage rules)?

Method (no fitting; every threshold is fixed before the data are seen)
  * Words are the ones valid in the existing Preview-vs-PDF geometry comparison
    (diag_c6_text_geometry.analyse_pair). Windows, exclusions and coverage are the
    geometry diagnostic's own. The same words are used for every comparison.
  * Coverage is the projection onto each word's ink colour against the window's ring
    median (geo.coverage). It is a coverage measure, not the RMSE.
  * Pixel classes: background (cov <= lo), edge (lo < cov < hi), full (cov >= hi).
    A full pixel is interior when all eight neighbours are full, otherwise boundary.
    Primary (lo, hi) = (0.05, 0.95). Sensitivity pairs: (0.02, 0.98) and (0.10, 0.90).
  * Per word and side: class counts, coverage sums per class, and the edge-coverage
    histogram (NBINS equal bins over lo..hi). Identity: total = bg + edge + full.
  * Paired PDF/Preview ratios, the share of the extra mass in each class, the total-variation
    distance between normalised edge histograms, and word-level bootstrap intervals.
  * Controls: poppler vs MuPDF direct, and MuPDF direct vs MuPDF 2x (same geometry, different
    rasterisers). They show what renderer differences alone do to these statistics.
  * Darkness dose response: the PDF raster raised to fixed gammas (1.2 to 2.0). Same geometry,
    darker partial pixels only. It shows how the statistics respond to darkness alone. It is
    a reference curve for reading the Preview-vs-PDF row, not a correction and not a fit.
    Known confound: darkening also pushes near-full pixels over the full threshold, which
    inflates the interior count. The validation tests document this.
  * Groups: all words, per script, per font (fonts with fewer than MIN_FONT_N valid words
    are marked indicative), and per vertical third of the page.

Inputs are read only; their SHA-256 hashes are checked before and after.
Run: python tool/diag_c6_coverage_profile.py build/visual_parity
"""

import hashlib
import json
import os
import sys
import traceback

import numpy as np
import pymupdf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import diag_c6_pdf_frame as frame_diag  # noqa: E402  (notice helper only)
import diag_c6_text_geometry as geo  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

CW, CH = resid.CW, resid.CH
PRIMARY = (0.05, 0.95)
SENS = [(0.02, 0.98), (0.10, 0.90)]
THRESHOLDS = [PRIMARY] + SENS
NBINS = 10
BOOT = 1000
SEED = 0
MIN_FONT_N = 30
MASS_KEYS = ["n_bg", "n_edge", "n_int", "n_bnd", "mass_bg", "mass_edge", "mass_full", "mass_total"]
COMPARISONS = [
    ("preview_vs_pdf_poppler", "prev", "pdf"),
    ("control_poppler_vs_mupdf_direct", "pdf", "mu1"),
    ("control_mupdf_direct_vs_mupdf_2x", "mu1", "mu2"),
]
GAMMAS = [1.2, 1.4, 1.6, 2.0]  # darkness-only dose response on the PDF raster (reference curve, not a correction)
STAT_NAMES = [
    "ratio_total_mass",
    "ratio_edge_mass",
    "ratio_full_mass",
    "ratio_n_edge",
    "ratio_n_int",
    "mean_edge_ref",
    "mean_edge_pdf",
    "tv_edge_hist",
    "share_delta_edge",
    "share_delta_full",
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ----------------------------------------------------------------- pixel classes


def classify(cov, lo, hi):
    """Boolean class maps for one window."""
    bg = cov <= lo
    full = cov >= hi
    edge = ~bg & ~full
    pad = np.pad(full, 1, constant_values=False)
    h, w = full.shape
    all_nb = np.ones_like(full)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                all_nb &= pad[1 + dy : 1 + dy + h, 1 + dx : 1 + dx + w]
    interior = full & all_nb
    boundary = full & ~interior
    return bg, edge, interior, boundary


def window_stats(cov, lo, hi):
    """Counts, coverage sums and the edge histogram of one window at thresholds (lo, hi)."""
    bg, edge, interior, boundary = classify(cov, lo, hi)
    full = interior | boundary
    e = cov[edge]
    hist, _ = np.histogram(e, bins=np.linspace(lo, hi, NBINS + 1))
    return {
        "n_bg": int(bg.sum()),
        "n_edge": int(e.size),
        "n_int": int(interior.sum()),
        "n_bnd": int(boundary.sum()),
        "mass_bg": float(cov[bg].sum()),
        "mass_edge": float(e.sum()),
        "mass_full": float(cov[full].sum()),
        "mass_total": float(cov.sum()),
        "hist": hist.astype(int).tolist(),
    }


def word_coverage(rgb_win, fg):
    """Coverage in a window against its own ring median, or None without colour contrast."""
    return geo.coverage(rgb_win, geo.ring_median(rgb_win), np.asarray(fg, dtype=np.float64))


# ----------------------------------------------------------------- aggregation


def _arrays(recs, side):
    A = np.array([[r[side][k] for k in MASS_KEYS] for r in recs], dtype=np.float64).reshape(len(recs), len(MASS_KEYS))
    H = np.array([r[side]["hist"] for r in recs], dtype=np.float64).reshape(len(recs), NBINS)
    return A, H


def _nan_div(a, b):
    return float(a / b) if b != 0 else float("nan")


def stats_from_sums(sr, sp, hr, hp):
    """Ratios and shares from summed reference (sr, hr) and PDF (sp, hp) arrays."""
    k = {name: i for i, name in enumerate(MASS_KEYS)}
    pr = hr / hr.sum() if hr.sum() > 0 else np.full(NBINS, np.nan)
    pp = hp / hp.sum() if hp.sum() > 0 else np.full(NBINS, np.nan)
    d_total = sp[k["mass_total"]] - sr[k["mass_total"]]
    share = (lambda key: _nan_div(sp[k[key]] - sr[k[key]], d_total)) if abs(d_total) > 1e-9 else (lambda key: float("nan"))
    return {
        "ratio_total_mass": _nan_div(sp[k["mass_total"]], sr[k["mass_total"]]),
        "ratio_edge_mass": _nan_div(sp[k["mass_edge"]], sr[k["mass_edge"]]),
        "ratio_full_mass": _nan_div(sp[k["mass_full"]], sr[k["mass_full"]]),
        "ratio_n_edge": _nan_div(sp[k["n_edge"]], sr[k["n_edge"]]),
        "ratio_n_int": _nan_div(sp[k["n_int"]], sr[k["n_int"]]),
        "ratio_n_bnd": _nan_div(sp[k["n_bnd"]], sr[k["n_bnd"]]),
        "mean_edge_ref": _nan_div(sr[k["mass_edge"]], sr[k["n_edge"]]),
        "mean_edge_pdf": _nan_div(sp[k["mass_edge"]], sp[k["n_edge"]]),
        "tv_edge_hist": float(0.5 * np.abs(pr - pp).sum()),
        "share_delta_edge": share("mass_edge"),
        "share_delta_full": share("mass_full"),
        "share_delta_bg": share("mass_bg"),
        "delta_total": float(d_total),
        "delta_bg": float(sp[k["mass_bg"]] - sr[k["mass_bg"]]),
        "delta_edge": float(sp[k["mass_edge"]] - sr[k["mass_edge"]]),
        "delta_full": float(sp[k["mass_full"]] - sr[k["mass_full"]]),
        "n_edge_ref": int(sr[k["n_edge"]]),
        "n_edge_pdf": int(sp[k["n_edge"]]),
        "n_int_ref": int(sr[k["n_int"]]),
        "n_int_pdf": int(sp[k["n_int"]]),
    }


def aggregate(recs, boot=BOOT, seed=SEED):
    """Point estimates, plus word-level bootstrap 95% intervals, for one group of words."""
    n = len(recs)
    out = {"n_words": n}
    if n == 0:
        return out
    Ar, Hr = _arrays(recs, "ref")
    Ap, Hp = _arrays(recs, "pdf")
    out.update(stats_from_sums(Ar.sum(0), Ap.sum(0), Hr.sum(0), Hp.sum(0)))
    if boot and n >= 3:
        rng = np.random.default_rng(seed)
        idx = rng.integers(0, n, size=(boot, n))
        samples = {name: [] for name in STAT_NAMES}
        for ii in idx:
            s = stats_from_sums(Ar[ii].sum(0), Ap[ii].sum(0), Hr[ii].sum(0), Hp[ii].sum(0))
            for name in STAT_NAMES:
                samples[name].append(s[name])
        ci = {}
        for name in STAT_NAMES:
            v = np.array(samples[name], dtype=np.float64)
            v = v[np.isfinite(v)]
            ci[name] = [float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))] if v.size else None
        out["ci"] = ci
    return out


def third_of(cy, height=CH):
    return min(int(3 * cy / height), 2)


def groups(recs):
    out = {"all": recs}
    for sc in sorted({r["script"] for r in recs}):
        out["script:" + sc] = [r for r in recs if r["script"] == sc]
    for fn in sorted({str(r["font"]) for r in recs}):
        out["font:" + fn] = [r for r in recs if str(r["font"]) == fn]
    for name, t in (("top", 0), ("middle", 1), ("bottom", 2)):
        out["third:" + name] = [r for r in recs if third_of(r["cy"]) == t]
    return out


# ----------------------------------------------------------------- per page


def valid_windows(words, recs, shape):
    """(word index, window) for every word the geometry comparison kept."""
    out = []
    for r in recs:
        if r["excluded"] is None:
            win = geo.window_of(words[r["i"]]["box_px"], geo.PAD, shape)
            if win is not None:
                out.append((r["i"], win))
    return out


def comparison_records(words, valid, imgs, a, b):
    """Per-word stats at every threshold pair for one comparison (a = reference, b = PDF side)."""
    per_thr = {thr: [] for thr in THRESHOLDS}
    for i, (x0, x1, y0, y1) in valid:
        fg = words[i]["color"]
        ca = word_coverage(imgs[a][y0:y1, x0:x1], fg)
        cb = word_coverage(imgs[b][y0:y1, x0:x1], fg)
        if ca is None or cb is None:
            continue
        base = {"i": i, "font": words[i]["font"], "script": words[i]["script"], "cy": 0.5 * (y0 + y1)}
        for thr in THRESHOLDS:
            per_thr[thr].append(dict(base, ref=window_stats(ca, *thr), pdf=window_stats(cb, *thr)))
    return per_thr


def analyse_page(words, drawings_px, images_px, prev_f, pdf_f, mu1_f, mu2_f):
    shape = prev_f.shape[:2]
    recs, reasons = geo.analyse_pair(words, drawings_px, images_px, prev_f, pdf_f)
    valid = valid_windows(words, recs, shape)
    imgs = {"prev": prev_f, "pdf": pdf_f, "mu1": mu1_f, "mu2": mu2_f}
    summary = {}
    dose = {}
    for g in GAMMAS:
        dark = np.clip(pdf_f, 0.0, 1.0) ** g
        per_thr = comparison_records(words, valid, {"a": pdf_f, "b": dark}, "a", "b")
        s_all = aggregate(per_thr[PRIMARY], boot=0)
        dose[f"gamma{g}"] = {k: s_all.get(k) for k in ("n_words", "ratio_total_mass", "ratio_n_int", "ratio_edge_mass", "ratio_n_edge", "ratio_full_mass")}
    for label, a, b in COMPARISONS:
        per_thr = comparison_records(words, valid, imgs, a, b)
        summary[label] = {name: aggregate(rs) for name, rs in groups(per_thr[PRIMARY]).items()}
        summary[label]["_sensitivity"] = {f"{lo}-{hi}": aggregate(per_thr[(lo, hi)], boot=0) for lo, hi in SENS}
    return {
        "words_total": len(words),
        "words_valid": len(valid),
        "excluded": dict(reasons),
        "summary": summary,
        "darkness_dose_response": dose,
    }


# ----------------------------------------------------------------- report


def _f(v, ci=None, nd=3):
    if v is None or (isinstance(v, float) and not np.isfinite(v)):
        return "n/a"
    s = f"{v:.{nd}f}"
    if ci:
        s += f" [{ci[0]:.{nd}f},{ci[1]:.{nd}f}]"
    return s


def report_lines(tag, res):
    out = [
        "  note: class mass shares are not reported in text; they are unstable when the total change is small (see summary.json).",
        f"{tag} words valid {res['words_valid']}/{res['words_total']}; excluded {json.dumps(res['excluded'], ensure_ascii=False)}",
        f"{tag} classes: bg cov<=lo, edge lo<cov<hi, full cov>=hi (interior: full with 8 full neighbours); primary {PRIMARY}; sensitivity {SENS}",
    ]
    for label, _a, _b in COMPARISONS:
        s = res["summary"][label]
        out.append(f"  {label}")
        a = s["all"]
        if not a.get("n_words"):
            out.append("    no valid words")
            continue
        ci = a.get("ci", {})
        out.append(
            f"    [all] n={a['n_words']} edge px {a['n_edge_ref']}/{a['n_edge_pdf']} | mass ratio PDF/ref: "
            f"total {_f(a['ratio_total_mass'], ci.get('ratio_total_mass'))} "
            f"edge {_f(a['ratio_edge_mass'], ci.get('ratio_edge_mass'))} "
            f"full {_f(a['ratio_full_mass'], ci.get('ratio_full_mass'))}"
        )
        out.append(
            f"    counts ratio PDF/ref: edge px {_f(a['ratio_n_edge'], ci.get('ratio_n_edge'))} "
            f"interior px {_f(a['ratio_n_int'], ci.get('ratio_n_int'))} | mean edge coverage "
            f"ref {_f(a['mean_edge_ref'])} pdf {_f(a['mean_edge_pdf'])}"
        )
        n_all = a["n_words"]
        out.append(
            f"    mass change PDF-ref per word: bg {a['delta_bg'] / n_all:+.2f} edge {a['delta_edge'] / n_all:+.2f} "
            f"full {a['delta_full'] / n_all:+.2f} (total {a['delta_total'] / n_all:+.2f}) | "
            f"edge-histogram TV {_f(a['tv_edge_hist'], ci.get('tv_edge_hist'))}"
        )
        for name, g in s.items():
            if name == "all" or name.startswith("_") or not g.get("n_words"):
                continue
            flag = " indicative" if name.startswith("font:") and g["n_words"] < MIN_FONT_N else ""
            out.append(
                f"    [{name}]{flag} n={g['n_words']} edge px {g['n_edge_ref']}/{g['n_edge_pdf']} "
                f"ratio total {_f(g['ratio_total_mass'])} edge {_f(g['ratio_edge_mass'])} "
                f"n_int {_f(g['ratio_n_int'])} TV {_f(g['tv_edge_hist'])}"
            )
        sens = s["_sensitivity"]
        out.append(
            "    sensitivity (edge-mass ratio / edge-px ratio): "
            + "; ".join(f"{k}: {_f(sens[k]['ratio_edge_mass'])} / {_f(sens[k]['ratio_n_edge'])}" for k in sens)
        )
    dose = res.get("darkness_dose_response", {})
    for name, d in dose.items():
        if d.get("n_words"):
            out.append(
                f"  darkness dose response (PDF^g; reference, not a correction) {name}: total x{_f(d['ratio_total_mass'])} "
                f"interior px x{_f(d['ratio_n_int'])} edge mass x{_f(d['ratio_edge_mass'])} edge px x{_f(d['ratio_n_edge'])}"
            )
    return out


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "build/visual_parity"
    out = os.path.join(d, "c6diag", "coverage_profile")
    os.makedirs(out, exist_ok=True)
    lines = ["[C6-DIAG-8] glyph-edge coverage profile, Preview vs PDF (diagnostic, non-gating)"]
    summary = {"pages": {}, "inputs_unchanged": None}
    try:
        with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
            pages = int(json.load(f)["pageCount"])
        vector = os.path.join(d, "vector.pdf")
        preview_pngs = [os.path.join(d, f"preview_page_{p}.png") for p in range(1, pages + 1)]
        inputs = [vector, os.path.join(d, "manifest.json")] + preview_pngs
        before = {p: sha256(p) for p in inputs}

        full_pngs = resid.render(vector, os.path.join(out, "poppler"))
        if len(full_pngs) != pages:
            raise RuntimeError(f"expected {pages} pages, got {len(full_pngs)}")
        doc = pymupdf.open(vector)
        for i in range(pages):
            pno = i + 1
            tag = f"p{pno}"
            page = doc[i]
            words, drawings_px, images_px, (sx, sy), backgrounds = geo.page_inputs(page)
            norm = os.path.join(out, f"{tag}_poppler.png")
            resid.normalise(full_pngs[i], norm)
            pdf_rgb, _, note_a = resid.load_rgb(norm)
            prev_png = os.path.join(out, f"{tag}_preview.png")
            resid.reference(preview_pngs[i], prev_png)
            prev_rgb, _, note_p = resid.load_rgb(prev_png)
            if pdf_rgb.shape != (CH, CW, 3) or prev_rgb.shape != pdf_rgb.shape:
                raise RuntimeError(f"unexpected shapes {pdf_rgb.shape} {prev_rgb.shape}")
            res = analyse_page(
                words,
                drawings_px,
                images_px,
                geo.load_float(prev_rgb),
                geo.load_float(pdf_rgb),
                geo.load_float(geo.mupdf_render(page, sx, sy)),
                geo.load_float(geo.mupdf_render(page, sx, sy, scale=2)),
            )
            res["inputs"] = f"Preview{note_p}; PDF render{note_a}; page-background drawings skipped={backgrounds}"
            summary["pages"][tag] = res
            lines.append(f"{tag} inputs: {res['inputs']}")
            lines += report_lines(tag, res)

        summary["inputs_unchanged"] = before == {p: sha256(p) for p in inputs}
        lines.append(f"inputs unchanged (sha256 before/after): {summary['inputs_unchanged']}")
    except Exception:
        lines.append("coverage profile ERROR " + traceback.format_exc()[-1500:])
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    frame_diag.notice("C6-DIAG-8 coverage profile", lines)


if __name__ == "__main__":
    main()
