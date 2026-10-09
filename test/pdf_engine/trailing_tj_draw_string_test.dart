// Vendored drawString trailing-TJ support (Batch 3): a trailing adjustment
// number must be emitted inside the word's TJ array exactly as a PDF viewer
// executes it, and the historical bytes must be preserved when there is no
// correction. Proves the emission primitive Batch 2 builds on.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> emit(double? trailingTj) async {
    final data = await rootBundle.load(ExamFonts.regularAsset);
    final font = pw.Font.ttf(data);
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (context) => pw.CustomPaint(
          painter: (canvas, size) {
            canvas.drawString(
              font.getFont(context),
              12,
              'AB',
              20,
              100,
              trailingTj: trailingTj,
            );
          },
        ),
      ),
    );
    return document.save();
  }

  test('trailing TJ number is emitted inside the word TJ array', () async {
    final raw = latin1.decode(await emit(-38.5), allowInvalid: true);
    final match =
        RegExp(r'\[<([0-9A-Fa-f]+)>\s*(-?[\d.]+)\]TJ').firstMatch(raw);
    expect(match, isNotNull, reason: 'no [hex N]TJ emitted: $raw');
    expect(double.parse(match!.group(2)!), closeTo(-38.5, 1e-9));
  });

  test('zero and null corrections keep the historical bytes', () async {
    for (final value in <double?>[null, 0, -0.0]) {
      final raw = latin1.decode(await emit(value), allowInvalid: true);
      expect(
        RegExp(r'\[<[0-9A-Fa-f]+>\]TJ').hasMatch(raw),
        isTrue,
        reason: 'trailingTj=$value changed the historical bytes',
      );
      expect(
        RegExp(r'\[<[0-9A-Fa-f]+>\s*-?[\d.]+\]TJ').hasMatch(raw),
        isFalse,
        reason: 'trailingTj=$value emitted a number',
      );
    }
  });
}
