import 'package:pdf/pdf.dart';

/// PDF-side vertical text geometry for single-line canonical runs.
///
/// The canonical [LayoutDocument] records each line's absolute baseline. The
/// Flutter measurement backend resolves that baseline with Flutter font
/// metrics, but the Vector-PDF painter emits text through package:pdf whose
/// line box follows its own rules:
///
/// * `pw.Stack` uses a bottom-up origin: `Positioned(top: t)` places the
///   child box at `stackHeight - t - childHeight`.
/// * Single-line `pw.Text` sizes its box to the word-accumulated line box
///   (`bottom - top`, where `bottom` is the maximum word ascent and `top`
///   the minimum word descent from `PdfFont.stringMetrics`).
/// * `_Line.realign` then shifts every span up by the line baseline, so the
///   emitted text operator sits one line box plus one maximum ascent below
///   the widget top.
///
/// [baselineOffsetFromTop] replicates that accumulation with the same public
/// inputs package:pdf uses (per-word string metrics over the run text), so
/// the painter can invert it: `top = line.baseline - offset`. No constant is
/// guessed: every value comes from the embedded font itself.
///
/// Note: package:pdf shapes RTL runs (presentation forms) before measuring.
/// Presentation forms share outlines — and therefore vertical extents — with
/// their nominal codepoints in the embedded fonts, so measuring the raw run
/// words yields the same ascent/descent accumulation.
abstract final class PdfTextMetrics {
  static final RegExp _whitespace = RegExp(r'\s');

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
    var top = 0.0;
    var bottom = 0.0;
    final scaledSpacing = letterSpacingPt / fontSizePt;
    for (final word in text.split(_whitespace)) {
      if (word.isEmpty) {
        continue;
      }
      final metrics =
          font.stringMetrics(word, letterSpacing: scaledSpacing) * fontSizePt;
      if (metrics.ascent > bottom) {
        bottom = metrics.ascent;
      }
      if (metrics.descent < top) {
        top = metrics.descent;
      }
    }
    // Line-box height (bottom - top) plus the realign shift (bottom).
    return (bottom - top) + bottom;
  }
}
