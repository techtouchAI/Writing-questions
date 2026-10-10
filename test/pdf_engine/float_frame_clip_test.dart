// Regression tests for the floating square/rectangle frame in the PDF (C6).
//
// Defect 1 (geometry): shapeToSvg insets the frame rectangle by stroke/2, so the
// centred stroke lands inside the layout box. The canonical Preview draws the
// stroke centred on the box itself, so the PDF frame sits about stroke/2 off.
//
// Defect 2 (clip): CanonicalLayoutPdfPainter wraps each floating element in a
// pw.Stack with Overflow.clip, and pw.SvgImage clips to its own box by default.
// Either clip cuts the outer half of a centred stroke, so the PDF frame is about
// half as thick as the Preview's. The painter's live decisions are
// FloatingElementsPdf.svgClipsToBox and centredFrameOverflows. They are tested
// here. The end-to-end effect is measured by the visual gate's rendered edge
// thickness (tool/diag_c6_pdf_frame.py).
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/pdf_engine/floating_elements_pdf.dart';

final RegExp _rectPattern = RegExp(
  r'<rect x="([-\d.]+)" y="([-\d.]+)" width="([-\d.]+)" height="([-\d.]+)"',
);

FloatingElement _shape(FloatingShapeType shape, {String? svgSource}) {
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

    test('generated frame is not clipped by its SVG or its wrapper', () {
      for (final shape in <FloatingShapeType>[
        FloatingShapeType.square,
        FloatingShapeType.rectangle,
      ]) {
        final element = _shape(shape);
        expect(FloatingElementsPdf.svgClipsToBox(element), isFalse,
            reason: '$shape SVG must not clip its centred stroke');
        expect(FloatingElementsPdf.centredFrameOverflows(element), isTrue,
            reason: '$shape wrapper must let its centred stroke overflow');
      }
    });

    test('other generated shapes keep the clip', () {
      for (final shape in <FloatingShapeType>[
        FloatingShapeType.circle,
        FloatingShapeType.triangle,
      ]) {
        final element = _shape(shape);
        expect(FloatingElementsPdf.svgClipsToBox(element), isTrue, reason: '$shape');
        expect(FloatingElementsPdf.centredFrameOverflows(element), isFalse,
            reason: '$shape');
      }
    });

    test('user SVG in a square element keeps the clip', () {
      final element = _shape(
        FloatingShapeType.square,
        svgSource: '<svg xmlns="http://www.w3.org/2000/svg"/>',
      );
      expect(FloatingElementsPdf.svgClipsToBox(element), isTrue);
      expect(FloatingElementsPdf.centredFrameOverflows(element), isFalse);
    });
  });
}
