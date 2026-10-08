import 'package:pdf/pdf.dart';

import '../layout/canonical/layout_document.dart';

/// PDF-side vertical text geometry for single-line canonical runs.
///
/// The canonical [LayoutDocument] records each line's absolute baseline. The
/// Flutter measurement backend resolves that baseline with Flutter font
/// metrics, but the Vector-PDF painter emits text through package:pdf, which
/// places the emitted text operator by its own accumulation:
///
/// * Word spans are created with a pre-realign vertical offset of zero
///   (`wd.offset = PdfPoint(offsetX, -offsetY + baseline)` with `offsetY =
///   0` on the first line and no span baseline shift).
/// * `_Line.realign` then shifts every span by `-baseline`, where the line
///   baseline is `bottom`: the maximum per-word ascent from
///   `PdfFont.stringMetrics`.
/// * `RichText.paint` draws each span at `box.top + offset.y`, and the
///   `pw.Stack` bottom-up origin resolves `box.top` to
///   `stackHeight - top`, so the widget height cancels out and the emitted
///   baseline lands exactly one maximum word ascent below the widget top.
///
/// [baselineOffsetFromTop] replicates that maximum-ascent accumulation with
/// the same public inputs package:pdf uses (per-word string metrics over
/// the run text), so the painter can invert it:
/// `top = line.baseline - offset`. No constant is guessed: every value
/// comes from the embedded font itself.
///
/// Note: package:pdf shapes RTL runs (presentation forms) before measuring.
/// Presentation forms share outlines — and therefore ascents — with their
/// nominal codepoints in the embedded fonts, so measuring the raw run words
/// yields the same maximum ascent.
abstract final class PdfTextMetrics {
  /// Vertical distance in points from the top edge of the single-line text
  /// widget to the emitted text baseline, for [text] set in [font] at
  /// [fontSizePt] with [letterSpacingPt].
  static double baselineOffsetFromTop({
    required PdfFont font,
    required double fontSizePt,
    required String text,
    double letterSpacingPt = 0,
  }) {
    if (text.isEmpty || fontSizePt <= 0) {
      return 0;
    }
    var bottom = 0.0;
    final scaledSpacing = letterSpacingPt / fontSizePt;
    for (final match in canonicalWordPattern.allMatches(text)) {
      final metrics =
          font.stringMetrics(match.group(0)!, letterSpacing: scaledSpacing) *
              fontSizePt;
      if (metrics.ascent > bottom) {
        bottom = metrics.ascent;
      }
    }
    // The emitted baseline sits one maximum word ascent below the widget
    // top (span pre-offset 0, realign shift -bottom, paint at box.top).
    return bottom;
  }

  /// Per-glyph Tc tracking in points that closes [wordText] to exactly
  /// [canonicalAdvancePt] when rendered by [font] at [fontSizePt]: the
  /// package:pdf advance is measured from the embedded font itself and the
  /// residual is distributed uniformly over the word's runes. Tc applies to
  /// every shown glyph, so dividing by the rune count is exact whenever the
  /// shaper emits one glyph per rune; ligature words (lam-alef class) keep a
  /// bounded residual of roughly one glyph share, far inside the natural-gap
  /// range the parity gate asserts.
  static double wordTrackingPt({
    required PdfFont font,
    required double fontSizePt,
    required String wordText,
    required double canonicalAdvancePt,
  }) {
    if (wordText.isEmpty || fontSizePt <= 0) {
      return 0;
    }
    final glyphShares = wordText.runes.length;
    if (glyphShares == 0) {
      return 0;
    }
    final pdfAdvancePt =
        font.stringMetrics(wordText).advanceWidth * fontSizePt;
    return (canonicalAdvancePt - pdfAdvancePt) / glyphShares;
  }
}
