"""Audit EACH of the three historical C6 tight-centre findings against paint.

No threshold/exclusion change. Same source font, original native pixels and
actual PDF glyph outlines/origins, not ToUnicode aliases' fictitious boxes.
Independent HarfBuzz is NOT a captured Flutter glyph stream. This bounded audit
cannot close general raster parity or substitute for opened original images.
"""
import argparse
from collections import Counter
import hashlib
from io import BytesIO
import json
import math
from pathlib import Path

WORDS = {'الْكَوْثَرَ': 2, 'أَعْطَيْنَاكَ': 1}


def outline(font, gid):
    glyph = font['glyf'][font.getGlyphName(gid)]
    if not glyph.numberOfContours:
        return 'empty'
    points, contours, flags = glyph.getCoordinates(font['glyf'])
    return hashlib.sha256(json.dumps([list(map(list, points)), list(contours), list(flags)],
                                    separators=(',', ':')).encode()).hexdigest()


def image_ink(image, window, scale):
    """Literal non-white ink; no fitted gamma/registration/coverage threshold."""
    import numpy as np
    from PIL import Image
    pixels = np.asarray(image.convert('RGB').crop(window))
    ys, xs = np.where(np.any(pixels != 255, axis=2))
    if not len(xs):
        raise ValueError('Original review window contains no visible ink')
    bounds = [(int(xs.min()) + window[0]) / scale, (int(ys.min()) + window[1]) / scale,
              (int(xs.max()) + 1 + window[0]) / scale, (int(ys.max()) + 1 + window[1]) / scale]
    return bounds, Image.fromarray(pixels)


def audit(root, font_path, output):
    import pymupdf
    import uharfbuzz as hb
    from fontTools.ttLib import TTFont
    from fontTools.pens.boundsPen import BoundsPen
    from PIL import Image
    source = json.loads((root/'preview_positions.json').read_text())
    gate = json.loads((root/'geometry_gate.json').read_text())
    originals = {'vector.pdf', 'preview_positions.json', 'geometry_gate.json',
                 *(f'preview_page_{page["page"]}.png' for page in source['pages'])}
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in originals}
    for name, expected in source['provenance']['artifactSha256'].items():
        if hashes.get(name) != expected:
            raise ValueError('Native/PDF source hashes do not match original position provenance')
    pdf = pymupdf.open(root/'vector.pdf')
    from audit_pdf_opentype import audit_source_text
    source_counts = audit_source_text(pdf)['actualTextSourceCounts']
    if {word: source_counts.get(word) for word in WORDS} != WORDS:
        raise ValueError('Actual PDF source metadata does not account for all three words')
    historical = list(gate['historical_tight_centre_violations'])
    if Counter(row['word'] for row in historical) != Counter(WORDS):
        raise ValueError('Original historical findings inventory is incomplete')
    font_bytes = font_path.read_bytes()
    reference = TTFont(BytesIO(font_bytes))
    face = hb.Face(font_bytes); font = hb.Font(face);font.scale = (face.upem, face.upem)
    scale = source['scalePxPerPt']
    rows = []
    for page in source['pages']:
        number = page['page']
        pdf_page = pdf[number - 1]
        spans = pdf_page.get_texttrace()
        font_ref = next(row[0] for row in pdf.get_page_fonts(number-1) if row[3] == 'Amiri-Regular') if any(
            row[3] == 'Amiri-Regular' for row in pdf.get_page_fonts(number-1)) else None
        subset = TTFont(BytesIO(pdf.extract_font(font_ref)[3])) if font_ref is not None else None
        preview = Image.open(root/f'preview_page_{number}.png').convert('RGB')
        pix = pdf_page.get_pixmap(matrix=pymupdf.Matrix(scale,scale), alpha=False)
        painted = Image.frombytes('RGB',(pix.width,pix.height),pix.samples)
        for line in page['lines']:
            for run in line['runs']:
                word = run['text']
                if word not in WORDS:
                    continue
                if run['fontFamily'] != 'Amiri' or subset is None:
                    raise ValueError('Historical source no longer uses the audited font')
                # Match physical spans using ORIGINAL baseline/edge bounds.
                # A displaced word fails; it is never discarded as an outlier.
                expected_right = run['xPt'] + run['widthPt']
                candidates = [span for span in spans if span['font'] == 'Amiri-Regular'
                    and abs(span['size']-run['fontSizePt']) < 1e-6
                    and abs(span['chars'][0][2][1]-line['baselinePt']) <= gate['bounds']['baseline_pt']
                    and abs(span['bbox'][2]-expected_right) <= gate['bounds']['word_edge_pt']
                    and abs(span['bbox'][0]-run['xPt']) <= gate['bounds']['word_edge_pt']]
                if len(candidates) != 1:
                    raise ValueError(f'{run["id"]}: missing/ambiguous physical glyph span')
                actual = candidates[0]
                # GID -1 is MuPDF's additional Unicode alias for ONE physical
                # CID, NOT another painted glyph. Record its count explicitly.
                chars = [char for char in actual['chars'] if char[1] >= 0]
                buffer = hb.Buffer();buffer.add_str(word);buffer.guess_segment_properties();hb.shape(font,buffer)
                infos, positions = buffer.glyph_infos, buffer.glyph_positions
                outlines_match = [outline(subset,char[1]) for char in chars] == [outline(reference,info.codepoint) for info in infos]
                if not outlines_match or len(chars) != len(positions):
                    raise ValueError(f'{run["id"]}: actual PDF outlines differ from source font shaping')
                pen = 0; errors = []; glyph_bounds = []
                for char, position in zip(chars, positions):
                    x = run['xPt'] + (pen + position.x_offset) / face.upem * run['fontSizePt']
                    y = line['baselinePt'] - position.y_offset / face.upem * run['fontSizePt']
                    errors.append(max(abs(char[2][0]-x),abs(char[2][1]-y)))
                    bounds = BoundsPen(reference.getGlyphSet())
                    reference.getGlyphSet()[reference.getGlyphName(infos[len(errors)-1].codepoint)].draw(bounds)
                    if bounds.bounds:
                        x0,y0,x1,y1 = bounds.bounds
                        unit = run['fontSizePt'] / face.upem
                        glyph_bounds.append((x+x0*unit,y-y1*unit,x+x1*unit,y-y0*unit))
                    pen += position.x_advance
                # PDF decimal serialization and MuPDF float32 coordinates;
                # same1e-4pt bound used by the original actual-PDF drag tests.
                if max(errors) > 1e-4:
                    raise ValueError(f'{run["id"]}: actual painted glyph origin moved {max(errors)}pt')
                left = math.floor((run['xPt']-1)*scale)
                right = math.ceil((run['xPt']+max(run['widthPt'],run['painterWidthPt'])+1)*scale)
                reference_paint_bounds = [min(b[0] for b in glyph_bounds),min(b[1] for b in glyph_bounds),
                    max(b[2] for b in glyph_bounds),max(b[3] for b in glyph_bounds)]
                # Actual outline bounds, not font ascent/descent: the latter
                # can include the NEXT line's ink and falsely imply a match.
                top = math.floor(reference_paint_bounds[1]*scale)-1
                bottom = math.ceil(reference_paint_bounds[3]*scale)+1
                window = (left,top,right,bottom)
                native_ink, native_crop = image_ink(preview,window,scale)
                pdf_ink, pdf_crop = image_ink(painted,window,scale)
                edge_error = max(abs(native_ink[i]-pdf_ink[i]) for i in (0,2))
                if edge_error > gate['bounds']['word_edge_pt']:
                    raise ValueError(f'{run["id"]}: actual ink edge differs {edge_error}pt')
                index = len(rows)+1
                native_crop.save(output/f'historical-word-{index}-preview.png')
                pdf_crop.save(output/f'historical-word-{index}-pdf.png')
                previous = next(row for row in historical if row['word'] == word)
                historical.remove(previous)
                rows.append(dict(historicalFindingOriginal=previous,id=run['id'],word=word,page=number,sourceXPt=run['xPt'],
                    sourceBaselinePt=line['baselinePt'],sourceFontSizePt=run['fontSizePt'],
                    actualPdfGlyphCount=len(chars),unicodeAliasCharacters=len(actual['chars'])-len(chars),
                    independentGlyphs=[info.codepoint for info in infos],sameOutlineSequence=outlines_match,
                    maxActualGlyphOriginErrorPt=max(errors),referenceWordPaintBoundsPt=reference_paint_bounds,
                    nativeReviewWindowInkBoundsPt=native_ink,pdfReviewWindowInkBoundsPt=pdf_ink,
                    reviewWindowScope="Identical physical word interval; adjacent bracket ink may enter. Not an isolated glyph mask.",
                    maxHorizontalInkEdgeDifferencePt=edge_error,reviewCropPx=window,
                    historicalFinding='tight-centre character-box extent is not physical glyph origin/ink',
                    manualVisualReview=False))
    if Counter(row['word'] for row in rows) != Counter(WORDS):
        raise ValueError('Must audit all three historical rows, including both occurrences')
    return dict(originalSha256=hashes,fontSha256=hashlib.sha256(font_bytes).hexdigest(),
                independentVersions=dict(pymupdf=pymupdf.VersionBind,harfbuzz=hb.version_string()),
                rows=rows,allThreeBoundedPaintChecksPassed=True,
                limits='Independent font shaper, not captured Flutter glyph IDs. '
                       'Original PNG/PDF must be opened. Raw raster RMSE and all other C6 checks remain unchanged.')


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--font',type=Path,default=Path('assets/fonts/Amiri-Regular.ttf'))
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    result=audit(args.root,args.font,args.output)
    (args.output/'quran-word-geometry.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))
