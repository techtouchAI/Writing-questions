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
// * the box clip pw.Text applies for TextOverflow.clip is replicated with
//   the replaced path's exact box (font advance by max height), so ink
//   outside the line box (stacked-mark tips above the top edge) is
//   treated byte-for-byte as before;
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
    final canvas = context.canvas;
    canvas
      ..saveContext()
      ..drawRect(0, 0, pdfAdvancePt, boxHeight)
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
    canvas.restoreContext();
  }
}
