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
// * fill and stroke color replicate the replaced decoration over the same
//   span offsets;
// * underline DOES NOT replicate the replaced path: the replaced path used
//   the package's own rule (fontDescent / 2 below the baseline), and the
//   Preview does not. It draws the rule where the engine draws it (see
//   [underlineThicknessPt]); the two rules differ by 2.7 pt on a 11 pt line,
//   which the underline parity check measures against the Preview;
// * a trailing TJ number closes the viewer-executed advance onto
//   [canonicalAdvancePt]: N = (pdfAdvance - canonicalAdvance) * 1000 /
//   fontSize, derived mathematically from the embedded font's own advance
//   for the shaped word. Degenerate inputs (empty text, non-positive size
//   or canonical advance, non-finite or exactly-zero correction) emit the
//   historical TJ bytes, so words without a correction are byte-identical
//   to the uncorrected emission.
//
// * italic replicates the Preview's synthetic oblique (see
//   [CanonicalText.syntheticObliqueShear]): package:pdf never reads
//   TextStyle.fontStyle, and no italic face is bundled, so the Preview's
//   slanted run must be reproduced by shearing the emitted glyphs. The shear
//   is applied around the ink origin inside the existing save/restore, so
//   every other operator — box, clip, Td, TJ number, underline — is
//   byte-identical to the upright emission.
//
// Letter spacing has no producer anywhere (no data key, no code setter) and
// is asserted zero at the call site; CanonicalText takes none.
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Matrix4;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// الجدول المرآوي لقاعدة UAX#9 L4 — كل محرف يحمل خاصية
/// `Bidi_Mirrored` ورسمه في جريان RTL يكون بمحرفه المقابل.
///
/// هذا هو جدول الأقواس والزوايا والاقتباسات الوثائقية الشائعة؛
/// المحارف الرياضية المرآوية تُرسَم عبر لقطة محرك الرياضيات لا
/// كنص، فلا دخول لها هنا. الزوج الواحد يظهر مرتين (كل اتجاه).
const Map<int, int> _kBidiMirrored = <int, int>{
  0x0028: 0x0029, // ( ↔ )
  0x0029: 0x0028,
  0x003C: 0x003E, // < ↔ >
  0x003E: 0x003C,
  0x005B: 0x005D, // [ ↔ ]
  0x005D: 0x005B,
  0x007B: 0x007D, // { ↔ }
  0x007D: 0x007B,
  0x00AB: 0x00BB, // « ↔ »
  0x00BB: 0x00AB,
  0x2039: 0x203A, // ‹ ↔ ›
  0x203A: 0x2039,
  0x2045: 0x2046, // ⁅ ↔ ⁆
  0x2046: 0x2045,
  0x207D: 0x207E, // ⁽ ↔ ⁾
  0x207E: 0x207D,
  0x208D: 0x208E, // ₍ ↔ ₎
  0x208E: 0x208D,
};

/// يكمل خوارزمية BiDi لجريان واحد حُلّ اتجاهه **RTL** مسبقاً
/// (عند كامل الفقرة، لا عند الكلمة المعزولة).
///
/// الجريان الذي يحمل محرفاً قوياً (عربي/لاتيني/…) أو رقماً يُترَك
/// لدالة [logicalToVisual] كما كان دائماً — فاتجاه أساسه المعزول
/// يطابق اتجاه الجريان المحلول، فترتيبها ومراوتها صحيحان حرفيّاً.
/// أما الجريان المحايد الصرف (قوس أو علامة ترقيم بلا محرف قوي ولا
/// رقم) فخوارزميته المعزولة تُسقط أساسه إلى LTR (UAX#9 P2/P3: أول
/// محرف قوي، وافتراضي LTR بلا واحد) فلا تعكس ولا تقلب — بينما في
/// سياق الفقرة RTL كل محارفه عند مستوى فردي، فتُطبَّق عليه L2
/// (عكس الترتيب) ثم L4 (مراوة كل محرف مرآوي).
///
/// الدالة نقية ولا تقرأ ولا تكتب أي حالة — مصدر الحقيقة للنص
/// المنطقي هو [text] كما خزّنه المحرر، والناتج هو نص الإصدار فقط.
String shapeRtlRun(String text) {
  if (_hasStrongDirectionalOrDigit(text)) {
    return logicalToVisual(text);
  }
  // جريان محايد صرف في سياق RTL: L2 ثم L4.
  final reversed = String.fromCharCodes(text.runes.toList().reversed);
  final buffer = StringBuffer();
  for (final rune in reversed.runes) {
    buffer.writeCharCode(_kBidiMirrored[rune] ?? rune);
  }
  return buffer.toString();
}

/// هل يحوي النص محرفاً قوياً الاتجاه (L/R/AL) أو رقماً (EN/AN)؟
/// تلك الكلمات تحسم خوارزميتها المعزولة اتجاهها بنفسها فلا يحتمل
/// الحرف الأخير منها سوى ما فعلته [logicalToVisual] أصلاً.
bool _hasStrongDirectionalOrDigit(String text) {
  for (final rune in text.runes) {
    if (_isStrongDirectionalRune(rune) || _isDigitRune(rune)) {
      return true;
    }
  }
  return false;
}

/// محرف قوي الاتجاه: لاتيني (L)، أو عبراني/عربي (R/AL).
bool _isStrongDirectionalRune(int rune) =>
    // L: الأساسية واللاتينية الممدودة واليونانية والسنغلي
    (rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x00C0 && rune <= 0x02FF) ||
        (rune >= 0x0370 && rune <= 0x058F) ||
        // R: العبرية
        (rune >= 0x0590 && rune <= 0x05FF) ||
        // AL: العربية واشتقاقاتها
        (rune >= 0x0600 && rune <= 0x08FF) ||
        (rune >= 0xFB50 && rune <= 0xFEFF) ||
        (rune >= 0x10E60 && rune <= 0x10E7F) ||
        (rune >= 0x1EC70 && rune <= 0x1EEFF);

/// رقم: لاتيني (EN)، مشرقي (AN)، أو مشرقي ممدود.
bool _isDigitRune(int rune) =>
    (rune >= 0x0030 && rune <= 0x0039) ||
        (rune >= 0x0660 && rune <= 0x0669) ||
        (rune >= 0x06F0 && rune <= 0x06F9);

class CanonicalText extends pw.Widget {
  CanonicalText({
    required this.text,
    required this.font,
    required this.fontSizePt,
    required this.color,
    required this.canonicalAdvancePt,
    required this.rtl,
    required this.underline,
    this.italic = false,
  });

  final String text;
  final pw.Font font;
  final double fontSizePt;
  final PdfColor color;
  final double canonicalAdvancePt;
  final bool rtl;
  final bool underline;

  /// Whether the run is italic, i.e. whether the emitted glyphs are sheared by
  /// [syntheticObliqueShear] to reproduce the Preview's rendering.
  final bool italic;

  /// Underline thickness, in points, for a font size.
  ///
  /// This is the engine's own rule, not the replaced `pw.Text` path's: the
  /// Preview draws the rule with a thickness of `fontSize / 14`
  /// (Skia's `skparagraph` `Decorations::calculateThickness` — "This is how
  /// flutter calculates the thickness" — whose default applies whenever the
  /// face carries no underline thickness of its own, which none of the bundled
  /// faces do; `test/pdf_engine/canonical_text_test.dart` guards that
  /// precondition against the asset bytes). The replaced path used
  /// `fontSize * 0.05` and the package's own line box, which is a different
  /// rule: on an 11 pt line the two disagree by 2.7 pt about where the rule
  /// sits, which the Preview-vs-PDF check now measures and gates.
  static double underlineThicknessPt(double fontSizePt) => fontSizePt / 14;

  /// Skia's synthetic oblique factor: the Preview slants an italic run even
  /// though no italic face is bundled, and package:pdf never reads
  /// `TextStyle.fontStyle`, so the printed page used to stay upright while the
  /// screen slanted. The value is tan(14°) — the shear Skia applies for
  /// `FontStyle.italic` on a family without an italic face.
  ///
  /// It is not a constant the code merely believes in: the emitted factor is
  /// checked against the slant measured from Preview pixels in
  /// `test/visual/italic_oblique_probe_test.dart`, which fits the per-row ink
  /// centroid of a stem column upright and italic and takes the difference of
  /// the two fits (the shear adds a constant to any ink feature's slope, while
  /// the glyph's own baseline drift is identical in both runs). Its first CI
  /// run measured upright 0.0330, italic -0.2195, difference 0.2525 against
  /// this 0.25, so a drift in either the constant or the engine's own
  /// behaviour fails that test instead of silently desynchronising the two
  /// renderings.
  static const double syntheticObliqueShear = 0.25;

  /// Shaped emission text, mirroring package:pdf's default shaping dispatch
  /// **completed** for the run's resolved direction.
  ///
  /// The dispatch itself (RTL runs through [logicalToVisual], LTR runs raw)
  /// is unchanged — this path must stay term-for-term with the replaced
  /// `pw.Text` for every run that carries its own strong character or a
  /// digit. What changed is the one case the dispatch cannot settle on its
  /// own: a run the canonical layout resolved RTL **whose text holds no
  /// strong character and no digit** (a lone bracket, a pure-punctuation
  /// mark). The vendored algorithm infers a paragraph's base direction from
  /// its first strong character (UAX#9 P2/P3) and defaults to LTR when there
  /// is none, so such an isolated run was reordered never and mirrored never
  /// — while the Preview (SkParagraph → HarfBuzz `hb_ot_mirror_chars`) shapes
  /// the *same* run against the whole paragraph, resolves it RTL, and paints
  /// the bracket mirrored. The two readings disagreed exactly on «أ )»-style
  /// runs: the Preview drew the closing parenthesis mirrored to an opening
  /// one at the left of the line, the PDF drew it unmirrored in the opposite
  /// direction — the bracket-flip in the printed page.
  ///
  /// [shapeRtlRun] completes rule L2/L4 against the direction the layout
  /// already resolved, so the PDF now paints what the Preview paints. Runs
  /// with a strong character or a digit keep [logicalToVisual]'s output
  /// byte-for-byte (Arabic words, Latin islands, numerals — all unchanged),
  /// and LTR runs stay raw, so Latin text and equations are untouched.
  String shapedText() => rtl ? shapeRtlRun(text) : text;

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
    // by max height); the ink Td replicates its span point plus realigned
    // offset term-for-term.
    final metrics = pdfFont.stringMetrics(shaped) * fontSizePt;
    final boxHeight = metrics.maxHeight;
    final pdfAdvancePt = metrics.advanceWidth;
    final inkY = boxHeight - metrics.ascent;
    // Underline: the Preview's rule, not the replaced path's. The engine draws
    // a solid decoration as a filled rectangle of height [underlineThicknessPt]
    // whose centre sits that same distance below the baseline (skparagraph's
    // `Decorations`: the position falls back to `thickness` when the face has
    // no underline metrics, and `draw_line_as_rect` fills
    // `{y - thickness/2, y + thickness/2}`), so on screen the rule occupies
    // `baseline + t/2 .. baseline + 1.5t` measured downwards.
    //
    // This canvas is y-up (its rect convention puts the *bottom* at y and the
    // top at y + height), and `inkY` is the baseline in it, so "t/2 below the
    // baseline" is `inkY - t/2` here and the same band is
    // `inkY - 1.5t .. inkY - t/2`. A stroke of width `t` centred at
    // `inkY - t` covers exactly that band.
    final underlineThickness = underlineThicknessPt(fontSizePt);
    final underlineY = inkY - underlineThickness;
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
      ..setFillColor(color);
    // Italic: the Preview shears the glyphs about the ink origin, so this
    // emits the same shear for the printed page. The text origin (0, inkY)
    // is a fixed point of the matrix — the glyphs above the baseline move
    // right — so the ink position is unchanged and an upright run emits no
    // extra operator at all.
    final shear = italic ? syntheticObliqueShear : 0.0;
    if (shear != 0) {
      canvas
        ..saveContext()
        ..setTransform(
          Matrix4.identity()
            ..setEntry(0, 1, shear)
            ..setEntry(0, 3, -shear * inkY),
        );
    }
    canvas.drawString(
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
    if (shear != 0) {
      canvas.restoreContext();
    }
    // The decoration sets its stroke color and width before drawing, and the
    // line is drawn only for underlined text — the same operator order the
    // replaced path used, with the thickness the Preview uses.
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(underlineThickness);
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
