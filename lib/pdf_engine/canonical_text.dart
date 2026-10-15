// Canonical PDF text emission primitive: one spaceless word whose ink is
// placed exactly where the replaced pw.Text put it, plus a trailing TJ
// correction that closes the viewer-executed advance onto canonical
// geometry. The caller's pw.Positioned carries the canonical origin (with
// the C1 baseline mapping in its top, untouched); this widget replicates
// the replaced path's widget-local ink geometry term-for-term, as a direct
// pw.Widget so no carrier widget contributes wrapper operators:
//
// * layout box = (0, 0, canonicalAdvancePt, word max height): the same
//   single-word line box pw.Text computes (origin box, height = maximum
//   ascent minus minimum descent), except the width, which is the
//   canonical advance by construction instead of the font advance. The
//   width feeds no placement (the caller's Positioned sets left/top only,
//   never right/bottom/width) and no probe (words are read from Td/TJ),
//   so the intended width delta moves no ink;
// * the box clip pw.Text applies for TextOverflow.clip is the floor, not the
//   ceiling: the clip is the union of that line box with the shaped word's
//   true glyph ink extents. The legacy box is the font advance by
//   `hhea` ascent-descent, and `hhea` is not a bound for every font in the
//   bundle — Tajawal's box is exactly 1.000 em while U+FE9B (ث initial)
//   reaches 0.739 em above the baseline and U+FE94 (ة final) 0.697 em, so the
//   top of those letters, of hamzas, of maddas and of harakat was removed from
//   the printed page. `PdfFontMetrics.append` already accumulates the real
//   bounds from the font's own `glyf` boxes (min xMin/yMin, max xMax/yMax), so
//   the union costs nothing extra to compute. It can only ever paint more ink
//   than before — never less — so the verified ink geometry is preserved and
//   the removed content returns;
// * ink Td = (0, boxHeight - ascent): the replaced path paints its span
//   at (box.left, box.top) plus the realigned span offset (0, -ascent),
//   i.e. (0, boxHeight - ascent) in Positioned-local space; this widget
//   emits the same operator in the same space, so the box origin, the Td
//   bytes, and the viewer-composed ink position are identical. Ink x = 0
//   because the single-word line realigns to the origin in both
//   directions (RTL mirrors about its own advance, LTR translates by
//   zero), matching the replaced path;
// * shaping mirrors package:pdf's default dispatch (logical-to-visual for
//   RTL, raw otherwise), reusing the vendored shaper rather than
//   re-implementing it; the vendored-patch verifier guards the dispatch
//   snippet this mirrors so upstream drift fails loudly;
// * fill color, stroke color, and underline replicate the replaced
//   single-underline decoration from the same scaled word metrics over
//   the same span offsets: underline y = boxHeight - ascent + descent -
//   fontDescent * fontSize / 2 with endpoints (left, left + width), line
//   width 0.05 em, stroked after the TJ exactly as the replaced
//   foreground decoration;
// * a trailing TJ number closes the viewer-executed advance onto
//   [canonicalAdvancePt]: N = (pdfAdvance - canonicalAdvance) * 1000 /
//   fontSize, derived mathematically from the embedded font's own advance
//   for the shaped word. Degenerate inputs (empty text, non-positive size
//   or canonical advance, non-finite or exactly-zero correction) emit the
//   historical TJ bytes, so words without a correction are byte-identical
//   to the uncorrected emission.
//
// Italic is accepted and ignored exactly as today: package:pdf never reads
// TextStyle.fontStyle during PDF emission. Letter spacing has no producer
// anywhere (no data key, no code setter) and is asserted zero at the call
// site; CanonicalText takes none.
import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CanonicalText extends pw.Widget {
  CanonicalText({
    required this.text,
    required this.font,
    required this.fontSizePt,
    required this.color,
    required this.canonicalAdvancePt,
    required this.rtl,
    required this.underline,
  });

  final String text;
  final pw.Font font;
  final double fontSizePt;
  final PdfColor color;
  final double canonicalAdvancePt;
  final bool rtl;
  final bool underline;

  /// Characters that swap glyph under a right-to-left level (UAX #9 rule L4).
  static const Map<int, int> _mirroredCharacters = <int, int>{
    0x0028: 0x0029, // ( )
    0x0029: 0x0028,
    0x003C: 0x003E, // < >
    0x003E: 0x003C,
    0x005B: 0x005D, // [ ]
    0x005D: 0x005B,
    0x007B: 0x007D, // { }
    0x007D: 0x007B,
    0x00AB: 0x00BB, // « »
    0x00BB: 0x00AB,
    0x2039: 0x203A, // ‹ ›
    0x203A: 0x2039,
  };

  /// True for the characters that pin a token to a left-to-right run: Latin
  /// letters and European digits. Arabic-Indic digits (U+0660–U+0669) are bidi
  /// class AN and stay with the surrounding right-to-left direction.
  static bool _isLeftToRightTokenRune(int rune) =>
      (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x0030 && rune <= 0x0039) ||
      (rune >= 0x00C0 && rune <= 0x024F);

  /// Applies rule L4 to [input] before it is reordered: a mirrored character
  /// becomes its mirror image when it resolves to a right-to-left level.
  ///
  /// The vendored shaper reorders (`logicalToVisual`) but carries no mirror
  /// map, so the PDF printed "(" wherever the preview printed ")" — a wrong
  /// character on the page, not a rendering nuance. Direction is decided per
  /// whitespace-separated token rather than per emission, because each
  /// canonical word is emitted on its own: a bracket arrives as a run of one
  /// character, and the surrounding line — not the run — is what gives it its
  /// level. A token that carries Latin letters or European digits is an
  /// embedded left-to-right run, and its brackets are left exactly as written.
  static String mirrorInRightToLeft(String input) {
    if (input.isEmpty) {
      return input;
    }
    // `split(' ')` followed by a single-space join is the exact inverse, so
    // the original whitespace is rebuilt verbatim and only tokens change.
    final tokens = input.split(' ');
    final buffer = StringBuffer();
    for (var index = 0; index < tokens.length; index++) {
      if (index > 0) {
        buffer.write(' ');
      }
      final token = tokens[index];
      final leftToRight = token.runes.any(_isLeftToRightTokenRune);
      buffer.write(
        leftToRight
            ? token
            : String.fromCharCodes(
                token.runes.map((rune) => _mirroredCharacters[rune] ?? rune),
              ),
      );
    }
    return buffer.toString();
  }

  /// Shaped emission text: rule L4 mirroring first (a character substitution,
  /// independent of reordering), then package:pdf's default shaping dispatch.
  String shapedText() {
    final mirrored = mirrorInRightToLeft(text);
    return rtl ? logicalToVisual(mirrored) : mirrored;
  }

  /// Trailing TJ adjustment in viewer-executed thousandths of an em, or null
  /// when there is no correction: the executed word advance (font advance
  /// plus the viewer-applied adjustment) lands exactly on
  /// [canonicalAdvancePt].
  double? trailingTjAdjustment(PdfFont pdfFont) {
    if (text.isEmpty || fontSizePt <= 0 || canonicalAdvancePt <= 0) {
      return null;
    }
    final pdfAdvancePt =
        pdfFont.stringMetrics(shapedText()).advanceWidth * fontSizePt;
    final correction =
        (pdfAdvancePt - canonicalAdvancePt) * 1000 / fontSizePt;
    if (correction == 0 || !correction.isFinite) {
      return null;
    }
    return correction;
  }

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    if (text.isEmpty) {
      box = const PdfRect(0, 0, 0, 0);
      return;
    }
    // Same scaled word metrics pw.Text measures the single word with (zero
    // letter spacing); the height replicates its line box.
    final metrics =
        font.getFont(context).stringMetrics(shapedText()) * fontSizePt;
    box = PdfRect(
      0,
      0,
      constraints.constrainWidth(canonicalAdvancePt),
      constraints.constrainHeight(metrics.maxHeight),
    );
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (text.isEmpty) {
      return;
    }
    final pdfFont = font.getFont(context);
    final shaped = shapedText();
    final correction = trailingTjAdjustment(pdfFont);
    // Same scaled word metrics pw.Text measures the single word with (zero
    // letter spacing). The clip box is the replaced line box (font advance
    // by max height); the ink Td and the underline replicate its span point
    // plus realigned offset term-for-term.
    final metrics = pdfFont.stringMetrics(shaped) * fontSizePt;
    final boxHeight = metrics.maxHeight;
    final pdfAdvancePt = metrics.advanceWidth;
    final inkY = boxHeight - metrics.ascent;
    final underlineY = boxHeight -
        metrics.ascent +
        metrics.descent -
        pdfFont.descent * fontSizePt / 2;
    // Clip = the legacy line box (advance by max height, the box pw.Text
    // clips to) unioned with the shaped word's real ink extents. The glyph
    // outlines live in font units with y increasing upwards from the
    // baseline, while this canvas measures y downwards from the box top, so
    // the ink lands between `inkY - bottom` and `inkY - top`, where `top` is
    // the minimum yMin and `bottom` the maximum yMax of the shaped word.
    final clipLeft = math.min(0.0, metrics.left);
    final clipRight = math.max(pdfAdvancePt, metrics.right);
    final clipTop = math.min(0.0, inkY - metrics.bottom);
    final clipBottom = math.max(boxHeight, inkY - metrics.top);
    final canvas = context.canvas;
    canvas
      ..saveContext()
      ..drawRect(
        clipLeft,
        clipTop,
        clipRight - clipLeft,
        clipBottom - clipTop,
      )
      ..clipPath()
      ..setFillColor(color)
      ..drawString(
        pdfFont,
        fontSizePt,
        shaped,
        0,
        inkY,
        // The replaced path always passes its (zero) letter spacing, so the
        // same explicit `0 Tc` is emitted.
        charSpace: 0,
        trailingTj: correction,
      );
    // The replaced foreground decoration always sets the stroke color and
    // width, then draws (and strokes) the line only for underlined text.
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(fontSizePt * 0.05);
    if (underline) {
      canvas
        ..drawLine(
          metrics.left,
          underlineY,
          metrics.left + metrics.width,
          underlineY,
        )
        ..strokePath();
    }
    canvas.restoreContext();
  }
}
