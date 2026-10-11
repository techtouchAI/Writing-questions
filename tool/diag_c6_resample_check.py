"""C6 probe: does the gate's ImageMagick resize + 2 px crop move text ink outside the mask?

Non-gating synthetic probe. It builds the text-only page used by
diag_c6_mask_validity, strips its text, renders both versions with MuPDF at a
chosen native scale (default 4/3, the 96 dpi scale the gate uses), then applies
the same steps as tool/verify_visual_parity.sh to the rendered PNG:
    convert <raster> -resize 794x1123! ... -crop 790x1119+2+2 +repage
and measures changed pixels outside the exact text mask with
diag_c6_mask_pixels.analyse.

A non-identity native scale makes the resize do real resampling; the default
scale makes it an identity, so it tests nothing about resampling.

Usage (from the repository root or from tool/):
    python tool/diag_c6_resample_check.py [--scale 1.31] [--workdir DIR]

Requires ImageMagick `convert` on PATH. Writes only under --workdir (a fresh
temporary directory by default). Prints counts only, not per-pixel lists.
"""
import argparse
import os
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import pymupdf  # noqa: E402

import diag_c6_mask_pixels as mp  # noqa: E402
import diag_c6_mask_validity as mv  # noqa: E402
import diag_c6_text_residual as resid  # noqa: E402

W, H = 794, 1123  # gate raster size
CW, CH, CO = 790, 1119, 2  # gate crop: 790x1119 at +2+2


def render_native(pdf_path, out_png, scale):
    doc = pymupdf.open(pdf_path)
    pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
    pix.save(out_png)
    doc.close()
    return pix.width, pix.height


def gate_steps(src_png, dst_png):
    tmp = dst_png + ".resized.png"
    subprocess.run(["convert", src_png, "-resize", f"{W}x{H}!", tmp], check=True)
    subprocess.run(
        ["convert", tmp, "-crop", f"{CW}x{CH}+{CO}+{CO}", "+repage", dst_png],
        check=True,
    )
    os.remove(tmp)


def run(scale, workdir):
    pdf = os.path.join(workdir, "text.pdf")
    notext = os.path.join(workdir, "notext.pdf")
    mv.build_text_page(pdf)
    resid.write_pdf_stripped(pdf, notext)
    dims = {}
    for name, src in (("full", pdf), ("notext", notext)):
        native = os.path.join(workdir, f"{name}_native.png")
        dims[name] = render_native(src, native, scale)
        gate_steps(native, os.path.join(workdir, f"{name}_gate.png"))
    r = mp.analyse(
        pdf,
        os.path.join(workdir, "full_gate.png"),
        os.path.join(workdir, "notext_gate.png"),
    )
    dists = [p["dist_to_glyph_box_px"] for p in r["pixels"]]
    known = [d for d in dists if d is not None]
    return {
        "scale": scale,
        "native_px": dims["full"],
        "changed_total": r["changed_total"],
        "changed_outside_exact": r["changed_outside_exact"],
        "changed_outside_px43": r["changed_outside_px43"],
        "classes_outside_exact": r["classes_outside_exact"],
        "max_dist_outside_exact_px": max(known) if known else None,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scale", type=float, nargs="+", default=[4 / 3])
    ap.add_argument("--workdir", default=None)
    args = ap.parse_args(argv)
    for s in args.scale:
        if args.workdir:
            wd = os.path.join(args.workdir, f"scale_{s:.4f}")
            os.makedirs(wd, exist_ok=True)
            print(run(s, wd))
        else:
            with tempfile.TemporaryDirectory() as wd:
                print(run(s, wd))


if __name__ == "__main__":
    main()
