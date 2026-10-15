#!/usr/bin/env python3
"""TEMP C6 probe (not for merge): dump the decisive properties of the real
vector.pdf so they can be read through check-run annotations.

Reads only what the fixture wrote into <artifacts>; reports:
  * how Arabic is encoded (base letters vs presentation forms) and whether the
    harakat survive,
  * the bracket characters with their x positions, per line, in emission and
    in visual order,
  * the clip rectangles the canonical painter emitted,
  * page geometry vs the preview PNG size.
"""
import json
import os
import sys
import unicodedata

import pymupdf

HARAKAT = set(range(0x064B, 0x0653)) | {0x0670, 0x0653, 0x0654, 0x0655, 0x0656}
BASE_ARABIC = lambda c: 0x0621 <= c <= 0x064A
PRES_FORM = lambda c: 0xFE70 <= c <= 0xFEFF
ORNAMENT = {0xFD3E, 0xFD3F}


def notice(title, lines):
    text = "\n".join(lines)
    for i in range(0, len(text), 3000):
        chunk = (
            text[i : i + 3000]
            .replace("%", "%25")
            .replace("\r", "%0D")
            .replace("\n", "%0A")
        )
        print(f"::notice title={title}::{chunk}")


def main():
    art = sys.argv[1]
    doc = pymupdf.open(os.path.join(art, "vector.pdf"))
    man = json.load(open(os.path.join(art, "manifest.json"), encoding="utf-8"))

    lines = [f"pages={doc.page_count} manifest={man}"]
    notice("PROBE geometry", lines)

    for pno in range(doc.page_count):
        page = doc[pno]
        raw = page.get_text("rawdict")
        words = []
        for block in raw["blocks"]:
            if block["type"] != 0:
                continue
            for line in block["lines"]:
                for span in line["spans"]:
                    for ch in span["chars"]:
                        words.append((ch, span))
        # rebuild word-ish tokens by x gaps
        allchars = [c for c, _ in words]
        text = "".join(c for c, _ in allchars)
        base = sum(1 for c in text if BASE_ARABIC(ord(c)))
        pres = sum(1 for c in text if PRES_FORM(ord(c)))
        har = sum(1 for c in text if ord(c) in HARAKAT)
        orn = sum(1 for c in text if ord(c) in ORNAMENT)
        assyri = sum(1 for c in text if 0x0700 <= ord(c) <= 0x074F)
        notice(
            f"PROBE page{pno + 1} encoding",
            [
                f"chars={len(text)} baseArabic={base} presentationForms={pres} "
                f"harakat={har} ornateBrackets={orn} syriac={assyri}",
                f"pageRect={page.rect} previewWxH={man.get('widthPx')}x{man.get('heightPx')}",
                "text[:300]=" + repr(text[:300]),
                "codepoints[:160]=" + " ".join(f"{ord(c):04X}" for c in text[:160]),
            ],
        )

        # bracket inventory, with positions
        br = [(ord(c), ch.get("bbox"), c) for c, _ in allchars if c in "()"]
        rows = [
            f"{ch!r} code=U+{cp:04X} bbox=({b[0]:.1f},{b[1]:.1f},{b[2]:.1f},{b[3]:.1f})"
            for cp, b, ch in br
        ]
        notice(f"PROBE page{pno + 1} brackets (emission order)", rows[:60] or ["none"])

        # per line grouping: group chars by y (rounded)
        groups = {}
        for c, sp in allchars:
            if c not in "()":
                continue
            key = round(sp["origin"][1], 1)
            groups.setdefault(key, []).append((c, sp["origin"][0]))
        for key, items in sorted(groups.items())[:10]:
            items.sort(key=lambda t: t[1])
            notice(
                f"PROBE page{pno + 1} bracket line y={key}",
                ["visual L->R: " + " ".join(f"{c}@{x:.1f}" for c, x in items)],
            )

        # harakat context: show the source chars of 6 words containing harakat
        near = []
        for i, (c, _) in enumerate(allchars):
            if ord(c) in HARAKAT:
                near.append("".join(x for x, _ in allchars[max(0, i - 6) : i + 4]))
                if len(near) >= 6:
                    break
        notice(f"PROBE page{pno + 1} harakat context", near or ["none"])

    # clip rectangles: read the raw content stream
    for pno in range(doc.page_count):
        page = doc[pno]
        xref = page.get_contents()[0]
        stream = doc.xref_stream(xref).decode("latin-1")
        re_ops = [ln for ln in stream.split("\n") if ln.endswith(" re")]
        w_n = stream.count("W n")
        notice(
            f"PROBE page{pno + 1} clips",
            [f"re ops={len(re_ops)} W n={w_n}", *re_ops[:8], "...last:", *(re_ops[-4:] or [])],
        )


if __name__ == "__main__":
    main()
