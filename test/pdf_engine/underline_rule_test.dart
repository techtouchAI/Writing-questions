// The printed underline must sit where the Preview draws it.
//
// The replaced `pw.Text` path drew it with the *package's* rule (half the font's
// descent below the baseline, thickness 0.05 em). The Preview does not use that
// rule: the engine draws a solid decoration as a filled rectangle of thickness
// `fontSize / 14` centred one thickness below the baseline, when the face
// carries no underline metrics of its own (Skia's `skparagraph`
// `Decorations::calculateThickness`/`calculatePosition`, whose comments read
// "This is how flutter calculates the thickness/positioning").
//
// Two things can silently break that agreement, so both are pinned here:
//  1. the emitted geometry -- thickness and offset from the baseline;
//  2. the *precondition* on the bundled faces (no underline metrics), because
//     a face that carries them would make the engine use its own numbers while
//     this emitter keeps using the fallback.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';

/// Every face the app bundles, so a new one cannot escape the precondition.
const List<String> _bundledFaces = <String>[
  ExamFont.regularAsset,
  ExamFont.boldAsset,
  ExamFont.quranicAsset,
  ExamFont.tajawalRegularAsset,
  ExamFont.tajawalBoldAsset,
  ExamFont.rakkasRegularAsset,
];

/// The `post` table version of a TrueType asset, or null when it has none.
int? _postVersion(ByteData font) {
  final numTables = font.getUint16(4);
  for (var index = 0; index < numTables; index++) {
    final record = 12 + index * 16;
    final tag = String.fromCharCodes(
      <int>[0, 1, 2, 3].map((offset) => font.getUint8(record + offset)),
    );
    if (tag != 'post') continue;
    return font.getUint32(font.getUint32(record + 8));
  }
  return null;
}

Future<String> _emitUnderscored(pw.Font font, double size) async {
  final document = pw.Document(compress: false);
  document.addPage(pw.Page(build: (context) => pw.Stack(
        fit: pw.StackFit.expand,
        children: <pw.Widget>[
          pw.Positioned(
            left: 90,
            top: 50,
            child: CanonicalText(
              text: 'STA1',
              font: font,
              fontSizePt: size,
              color: PdfColors.black,
              canonicalAdvancePt: 10,
              rtl: false,
              underline: true,
            ),
          ),
        ],
      )));
  return latin1.decode(await document.save(), allowInvalid: true);
}

/// One emitted rule: the band's centre, its span, and the stroke width, in the
/// canvas's own coordinates (y-up: `y` is measured from the box's bottom edge).
({double y, double span, double lineWidth}) _ruleOf(String raw) {
  final stroke = RegExp(
    r'(-?[\d.]+) (-?[\d.]+) m (-?[\d.]+) (-?[\d.]+) l S',
  ).firstMatch(raw);
  expect(stroke, isNotNull, reason: 'the widget must draw a stroked rule');
  final width = RegExp(r'(-?[\d.]+) w').firstMatch(raw);
  expect(width, isNotNull, reason: 'the rule must set a stroke width');
  final x0 = double.parse(stroke!.group(1)!);
  final y0 = double.parse(stroke.group(2)!);
  final x1 = double.parse(stroke.group(3)!);
  expect(double.parse(stroke.group(4)!), closeTo(y0, 1e-9),
      reason: 'the rule must be horizontal');
  return (
    y: y0,
    span: x1 - x0,
    lineWidth: double.parse(width!.group(1)!),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled faces carry no underline metrics of their own', () async {
    for (final asset in _bundledFaces) {
      final data = await rootBundle.load(asset);
      final version = _postVersion(data);
      expect(version, isNotNull, reason: '$asset has no post table');
      // Post version 1 is the only one that carries underlinePosition and
      // underlineThickness. The bundled faces use version 2 or 3, which drop
      // them, so both the engine and this emitter fall back to their own
      // rules -- which is what the geometry test below pins. A face with
      // version 1 would silently make the Preview use its numbers instead.
      expect(version, isNot(0x00010000),
          reason: '$asset carries post underline metrics; the Preview would '
              'use them while CanonicalText uses the engine fallback');
    }
  });

  test('the rule is the engine rule: fontSize / 14 below the baseline',
      () async {
    final bytes = await rootBundle.load(ExamFont.regularAsset);
    for (final size in <double>[8, 11, 12, 20]) {
      final raw = await _emitUnderscored(pw.Font.ttf(bytes), size);
      final rule = _ruleOf(raw);
      final thickness = CanonicalText.underlineThicknessPt(size);
      expect(thickness, closeTo(size / 14, 1e-12));

      // The stroke's width *is* the rule's thickness and its path is the
      // centre of the band, so the band spans y ± thickness/2.
      // The emission rounds every number to five decimals, so the tolerance
      // is the file's own quantum, not machine epsilon.
      expect(rule.lineWidth, closeTo(thickness, 1e-4),
          reason: 'thickness at $size pt');
      expect(rule.span, greaterThan(0), reason: 'the rule must span ink');

      final pdfFont = PdfTtfFont(PdfDocument(), bytes);
      final metrics = pdfFont.stringMetrics('STA1') * size;
      final baseline = metrics.maxHeight - metrics.ascent;   // y-up canvas
      expect(rule.y, closeTo(baseline - thickness, 1e-4),
          reason: 'the stroke must be centred one thickness below the '
              'baseline at $size pt');

      // The band lies entirely below the baseline and stays thin: a sanity
      // check that no sign flip can turn "under the text" into "through it".
      expect(rule.y + thickness / 2, lessThan(baseline),
          reason: 'the rule must not reach the baseline at $size pt');
      expect(thickness / size, lessThan(0.2),
          reason: 'the rule must stay a rule at $size pt');
    }
  });
}
