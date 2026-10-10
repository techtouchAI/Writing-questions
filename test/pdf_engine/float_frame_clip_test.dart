// Regression tests for the floating square/rectangle frame in the PDF (C6).
//
// Defect 1 (geometry): shapeToSvg insets the frame rectangle by stroke/2, so the
// centred stroke lands inside the layout box. The canonical Preview draws the
// stroke centred on the box itself, so the PDF frame sits about stroke/2 off.
//
// Defect 2 (clip): pw.SvgImage clips to its box by default. The outer half of a
// centred stroke is cut away, which halves the visible frame thickness.
//
// Clipping is detected in the uncompressed content stream by the `W n` operator
// that SvgImage emits when clip is true.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/pdf_engine/floating_elements_pdf.dart';

final RegExp _rectPattern = RegExp(
  r'<rect x="([-\d.]+)" y="([-\d.]+)" width="([-\d.]+)" height="([-\d.]+)"',
);

Future<String> _pdfContent(pw.Widget widget) async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(200, 200),
      margin: pw.EdgeInsets.zero,
      build: (context) => widget,
    ),
  );
  final Uint8List bytes = await doc.save();
  return String.fromCharCodes(bytes);
}

FloatingElement _frame(FloatingShapeType shape, {String? svgSource}) {
  return FloatingElement(
    type: FloatingElementType.shape,
    shape: shape,
    svgSource: svgSource,
    dx: 0,
    dy: 0,
    width: 100,
    height: 80,
    strokeWidth: 2.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('floating square/rectangle frame', () {
    test('is drawn on the full layout box, not inset by stroke/2', () {
      for (final shape in <FloatingShapeType>[
        FloatingShapeType.square,
        FloatingShapeType.rectangle,
      ]) {
        final svg = FloatingElementsPdf.shapeToSvg(shape, 100, 80, strokeWidth: 2.0);
        final match = _rectPattern.firstMatch(svg);
        expect(match, isNotNull, reason: '$shape must draw a <rect>');
        expect(double.parse(match!.group(1)!), 0, reason: '$shape x');
        expect(double.parse(match.group(2)!), 0, reason: '$shape y');
        expect(double.parse(match.group(3)!), 100, reason: '$shape width');
        expect(double.parse(match.group(4)!), 80, reason: '$shape height');
      }
    });

    test('generated frame is not clipped, user SVG still is', () async {
      final generated = FloatingElementsPdf.shapeToSvg(
        FloatingShapeType.square,
        100,
        80,
        strokeWidth: 2.0,
      );

      final generatedPdf = await _pdfContent(
        FloatingElementsPdf.build(
          _frame(FloatingShapeType.square),
          widthPt: 100,
          heightPt: 80,
        ),
      );
      expect(
        generatedPdf,
        isNot(contains(' W n')),
        reason: 'the generated frame must not clip its centred stroke',
      );

      // Control: the same markup supplied as user SVG keeps SvgImage's default
      // clip. This proves the detector works and that user SVG is unchanged.
      final userPdf = await _pdfContent(
        FloatingElementsPdf.build(
          _frame(FloatingShapeType.square, svgSource: generated),
          widthPt: 100,
          heightPt: 80,
        ),
      );
      expect(userPdf, contains(' W n'));
    });
  });
}
