#!/usr/bin/env python3
"""TEMP C6 probe (not for merge): dump decisive properties of the real
vector.pdf so they can be read through check-run annotations.

Every section is independently guarded: one failure must not hide the rest.
"""
import json
import os
import sys
import traceback
import collections

import pymupdf


def notice(title, lines):
    text = "\n".join(str(x) for x in lines)
    for i in range(0, len(text), 3000):
        chunk = (
            text[i : i + 3000]
            .replace("%", "%25")
            .replace("\r", "%0D")
            .replace("\n", "%0A")
        )
        print(f"::notice title={title}::{chunk}")


def guard(title, fn):
    try:
        return fn()
    except Exception:
        notice(title + " CRASH", traceback.format_exc().splitlines()[-6:])
        return None


HARAKAT = set(range(0x064B, 0x0653)) | {0x0670, 0x0653, 0x0654, 0x0655, 0x0656}
ORNAMENT = {0xFD3E, 0xFD3F}
BASE_ARABIC = lambda c: 0x0621 <= c <= 0x064A
PRES_FORM = lambda c: 0xFE70 <= c <= 0xFEFF


def chars_of(page):
    out = []
    for block in page.get_text("rawdict")["blocks"]:
        if block["type"] != 0:
            continue
        for line in block["lines"]:
            for span in line["spans"]:
                for ch in span["chars"]:
                    out.append((ch["c"], span, ch))
    return out


def main():
    art = sys.argv[1]
    doc = pymupdf.open(os.path.join(art, "vector.pdf"))
    man = json.load(open(os.path.join(art, "manifest.json"), encoding="utf-8"))
    notice("PROBE geometry", [f"pages={doc.page_count} manifest={man}"])

    for pno in range(doc.page_count):
        page = doc[pno]

        def encoding(_page=page, _pno=pno):
            chars = chars_of(_page)
            text = "".join(c for c, _, _ in chars)
            counts = collections.Counter()
            counts["chars"] = len(text)
            counts["baseArabic"] = sum(1 for c in text if BASE_ARABIC(ord(c)))
            counts["presentationForms"] = sum(1 for c in text if PRES_FORM(ord(c)))
            counts["harakat"] = sum(1 for c in text if ord(c) in HARAKAT)
            counts["ornateBrackets"] = sum(1 for c in text if ord(c) in ORNAMENT)
            counts["parens"] = text.count("(") + text.count(")")
            notice(
                f"PROBE p{_pno + 1} encoding",
                [str(dict(counts)), "text[:260]=" + repr(text[:260])],
            )
            notice(
                f"PROBE p{_pno + 1} codepoints",
                [
                    " ".join(f"{ord(c):04X}" for c in text[:200]),
                    " ".join(f"{ord(c):04X}" for c in text[200:400]),
                ],
            )
            # per-line (grouped by baseline) bracket inventory
            by_base = collections.defaultdict(list)
            for c, span, ch in chars:
                if c in "()":
                    by_base[round(span["origin"][1], 1)].append((c, ch["bbox"][0]))
            for y, items in sorted(by_base.items())[:8]:
                items.sort(key=lambda t: t[1])
                notice(
                    f"PROBE p{_pno + 1} bracketline y={y}",
                    ["visual L->R: " + " ".join(f"{c}@{x:.1f}" for c, x in items)],
                )
            # harakat context strings
            chars_only = [c for c, _, _ in chars]
            ctx = []
            for i, c in enumerate(chars_only):
                if ord(c) in HARAKAT:
                    ctx.append(
                        "".join(chars_only[max(0, i - 8) : i + 5])
                        + f" [{ord(c):04X}]"
                    )
                    if len(ctx) >= 8:
                        break
            notice(f"PROBE p{_pno + 1} harakat context", ctx or ["none"])

        guard(f"PROBE p{pno + 1} encoding", encoding)

        def clips(_page=page, _pno=pno):
            stream = _page.read_contents().decode("latin-1")
            res = [ln for ln in stream.split("\n") if ln.rstrip().endswith(" re")]
            notice(
                f"PROBE p{_pno + 1} clips",
                [
                    f"re ops={len(res)}  'W n'={stream.count('W n')}  streamBytes={len(stream)}",
                    "first8: " + " | ".join(res[:8]),
                    "last4 : " + " | ".join(res[-4:]),
                    "sample: " + " | ".join(stream.split("\n")[:14]),
                ],
            )

        guard(f"PROBE p{pno + 1} clips", clips)

    notice(
        "PROBE preview json",
        [str(sorted(os.listdir(os.path.join(art, "c6diag", "text_positions")))) ]
        if os.path.isdir(os.path.join(art, "c6diag", "text_positions"))
        else ["missing"],
    )


if __name__ == "__main__":
    main()
