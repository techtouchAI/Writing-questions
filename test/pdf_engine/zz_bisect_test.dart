// TEMPORARY bisection (Batch 2): Batch 3's bare-CustomPaint emission is
// green but the Stack+Positioned harness finds no Td/TJ. Isolate tree shape
// vs RTL text. DELETE after the root cause is found.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';

Future<String> _emit(pw.Widget child) async {
  final document = pw.Document();
  document.addPage(pw.Page(build: (context) => child));
  return latin1.decode(await document.save(), allowInvalid: true);
}

pw.Widget _positioned(pw.Widget child) => pw.Stack(
      fit: pw.StackFit.expand,
      overflow: pw.Overflow.visible,
      children: <pw.Widget>[
        pw.Positioned(left: 90, top: 50, child: child),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C1 bare CustomPaint LTR (Batch 3 clone)', () async {
    final font = pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (context) => pw.CustomPaint(
          painter: (canvas, size) {
            canvas.drawString(font.getFont(context), 12, 'AB', 20, 100);
          },
        ),
      ),
    );
    final raw =
        latin1.decode(await document.save(), allowInvalid: true);
    expect(RegExp(r'TJ').hasMatch(raw), isTrue);
  });

  test('C2 Stack+Positioned legacy pw.Text LTR', () async {
    final font = pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
    final raw = await _emit(
      _positioned(
        pw.Text(
          'AB',
          style: pw.TextStyle(font: font, fontSize: 12),
          softWrap: false,
          maxLines: 1,
        ),
      ),
    );
    expect(RegExp(r'Td').hasMatch(raw), isTrue);
  });

  test('C3 Stack+Positioned legacy pw.Text RTL', () async {
    final font = pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
    final raw = await _emit(
      _positioned(
        pw.Text(
          'عِلْمًا',
          style: pw.TextStyle(font: font, fontSize: 12),
          textDirection: pw.TextDirection.rtl,
          softWrap: false,
          maxLines: 1,
        ),
      ),
    );
    expect(RegExp(r'Td').hasMatch(raw), isTrue);
  });
}
