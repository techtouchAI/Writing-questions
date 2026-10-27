"""Read-only, same-font PDF outline audit (not an application dependency).

Install PyMuPDF, fontTools, uharfbuzz in an isolated review environment.
The HarfBuzz result is an independent reference, NOT captured Flutter glyph IDs.
We compare resolved glyf outlines, not ToUnicode characters or font filenames.
"""
import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path


HEADER_WORDS = frozenset(('بسم', 'الله', 'الرحمن', 'الرحيم'))


def outline_check(report):
    """Bounded diagnostic: all four fixture words, exact outline sequences.

    This does not validate GPOS positions, mixed BiDi, or Flutter's glyph stream.
    Advances are reported, not gated: natural glyph advances alone cannot
    validate a renderer's explicitly positioned glyphs.
    """
    rows = report.get('words', [])
    return (len(rows) == len(HEADER_WORDS)
            and {row.get('text') for row in rows} == HEADER_WORDS
            and all(row.get('sameOutlineSequence') is True for row in rows))


def audit(pdf_path, font_path, *, page=0, font_name='Amiri-Regular', size=17):
    import pymupdf
    import uharfbuzz as hb
    import fontTools
    from fontTools.ttLib import TTFont

    raw = font_path.read_bytes()
    original = TTFont(BytesIO(raw))
    document = pymupdf.open(pdf_path)
    xref = next(row[0] for row in document.get_page_fonts(page) if row[3] == font_name)
    _, _, _, subset_bytes = document.extract_font(xref)
    subset = TTFont(BytesIO(subset_bytes))
    subset_order = subset.getGlyphOrder()

    def outline(font, name):
        glyph = font['glyf'][name]
        if not glyph.numberOfContours:
            return 'empty'
        points, contours, flags = glyph.getCoordinates(font['glyf'])
        serial = [list(map(list, points)), list(contours), list(flags)]
        return hashlib.sha256(json.dumps(serial, separators=(',', ':')).encode()).hexdigest()

    by_outline = {}
    for index, name in enumerate(original.getGlyphOrder()):
        by_outline.setdefault(outline(original, name), []).append(index)
    unicode_glyphs = {original.getGlyphID(name) for name in original.getBestCmap().values()}
    face = hb.Face(raw)
    font = hb.Font(face)
    font.scale = (face.upem, face.upem)
    rows = []
    for span in document[page].get_texttrace():
        if span['font'] != font_name or abs(span['size'] - size) > 1e-6:
            continue
        # This diagnostic targets individual Arabic header words emitted by
        # CanonicalAbsoluteText. They have no intervening mixed bidi islands.
        text = ''.join(chr(char[0]) for char in span['chars'])[::-1]
        buffer = hb.Buffer()
        buffer.add_str(text)
        buffer.guess_segment_properties()
        hb.shape(font, buffer)
        hb_glyphs = [info.codepoint for info in buffer.glyph_infos]
        pdf_glyphs = [char[1] for char in span['chars']]
        actual = [outline(subset, subset_order[index]) for index in pdf_glyphs]
        reference = [outline(original, original.getGlyphName(index)) for index in hb_glyphs]
        rows.append(dict(text=text,
            pdfOriginalGlyphCandidates=[by_outline.get(value, []) for value in actual],
            independentHarfBuzzGlyphs=hb_glyphs,
            independentGlyphsWithoutUnicodeCmap=[gid for gid in hb_glyphs if gid not in unicode_glyphs],
            sameOutlineSequence=actual == reference,
            sameOutlineAtVisualPosition=[a == b for a, b in zip(actual, reference)],
            pdfNaturalAdvancePt=sum(subset['hmtx'][subset_order[index]][0] for index in pdf_glyphs)
                / subset['head'].unitsPerEm * span['size'],
            independentHarfBuzzAdvancePt=sum(position.x_advance for position in buffer.glyph_positions)
                / face.upem * span['size']))
    if not rows:
        raise ValueError('No matching words; refusing empty audit success')
    return dict(pdfSha256=hashlib.sha256(pdf_path.read_bytes()).hexdigest(),
        fontSha256=hashlib.sha256(raw).hexdigest(), subsetSha256=hashlib.sha256(subset_bytes).hexdigest(),
        pageIndex=page, font=font_name, sizePt=size,
        versions=dict(harfbuzz=hb.version_string(), fontTools=fontTools.__version__, pymupdf=pymupdf.VersionBind),
        limitation='Independent reference, not captured Flutter glyph IDs or a replacement for actual image review.',
        words=rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pdf', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true',
        help='Fail unless all four fixture header words match reference outlines; not full parity validation')
    args = parser.parse_args()
    report = audit(args.pdf, args.font)
    report['boundedOutlineCheckPassed'] = outline_check(report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if args.check and not report['boundedOutlineCheckPassed']:
        raise SystemExit(1)
