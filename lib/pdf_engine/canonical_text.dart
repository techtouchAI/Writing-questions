// Canonical PDF text emission primitive: one spaceless word whose ink is
// placed exactly where the replaced pw.Text put it, plus a trailing TJ
// correction that closes the viewer-executed advance onto canonical
// geometry. The caller's pw.Positioned carries the canonical origin (with
// the C1 baseline mapping in its top, untouched); this widget replicates
// the replaced path's widget-local ink geometry term-for-term:
//
// * widget height = the word's scaled max height, ink baseline = -ascent:
//   the same single-word line box and realigned span offset pw.Text
//   computes (zero pre-offset, line baseline = maximum word ascent), so
//   the box origin, the Td operator, and the ink land on identical bytes;
// * ink x = 0: the single-word line realigns to the origin in both
//   directions (RTL mirrors about its own advance, LTR translates by
//   zero), matching the replaced path;
// * shaping mirrors package:pdf's default dispatch (logical-to-visual for
//   RTL, raw otherwise), reusing the vendored shaper rather than
//   re-implementing it; the vendored-patch verifier guards the dispatch
//   snippet this mirrors so upstream drift fails loudly;
// * a trailing TJ number closes the viewer-executed advance onto
//   [canonicalAdvancePt]: N = (pdfAdvance - canonicalAdvance) * 1000 /
//   fontSize, derived mathematically from the embedded font's own advance
//   for the shaped word. Degenerate inputs (empty text, non-positive size
//   or canonical advance, non-finite or exactly-zero correction) emit the
//   historical TJ bytes, so words without a correction are byte-identical
//   to the uncorrected emission;
// * underline replicates pw.Text's single-underline decoration from the
//   same scaled word metrics over the same line offsets, anchored to the
//   box top edge exactly as the replaced path anchors it, with the same
//   stroke color, width (0.05 em), and font-descent offset.
//
// Italic is accepted and ignored exactly as today: package:pdf never reads
// TextStyle.fontStyle during PDF emission. Letter spacing has no producer
// anywhere (no data key, no code setter) and is asserted zero at the call
// site; CanonicalText takes none.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CanonicalText extends pw.StatelessWidget {
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

  /// Shaped emission text, mirroring package:pdf's default shaping dispatch.
  String shapedText() => rtl ? logicalToVisual(text) : text;

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
  pw.Widget build(pw.Context context) {
    if (text.isEmpty) {
      return pw.SizedBox.shrink();
    }
    final pdfFont = font.getFont(context);
    final shaped = shapedText();
    final correction = trailingTjAdjustment(pdfFont);
    // Same scaled word metrics pw.Text measures the single word with (zero
    // letter spacing): max height sizes the replicated line box, -ascent is
    // the replicated realigned span offset, and the underline span box
    // (-ascent + descent + maxHeight, anchored to the box top edge) plus
    // the font-descent offset reproduces the replaced decoration.
    final metrics = pdfFont.stringMetrics(shaped) * fontSizePt;
    final boxHeight = metrics.maxHeight;
    final inkBaselineY = -metrics.ascent;
    final underlineY = boxHeight +
        (-metrics.ascent + metrics.descent + metrics.maxHeight) -
        pdfFont.descent * fontSizePt / 2;
    return pw.CustomPaint(
      size: PdfPoint(canonicalAdvancePt, boxHeight),
      painter: (canvas, _) {
        canvas.setFillColor(color);
        canvas.drawString(
          pdfFont,
          fontSizePt,
          shaped,
          0,
          inkBaselineY,
          trailingTj: correction,
        );
        if (underline) {
          canvas
            ..setStrokeColor(color)
            ..setLineWidth(fontSizePt * 0.05)
            ..drawLine(
              metrics.left,
              underlineY,
              metrics.left + metrics.width,
              underlineY,
            )
            ..strokePath();
        }
      },
    );
  }
}
