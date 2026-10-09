import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/pdf_engine/floating_elements_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingElementsPdf.shapeToSvg', () {
    test('emits self-contained SVG geometry per shape', () {
      final square = FloatingElementsPdf.shapeToSvg(
        FloatingShapeType.square,
        100,
        80,
      );
      expect(square, contains('<svg'));
      expect(square, contains('<rect'));
      expect(square, contains('stroke="#111827"'));

      final circle = FloatingElementsPdf.shapeToSvg(
        FloatingShapeType.circle,
        60,
        60,
      );
      expect(circle, contains('<circle'));

      final triangle = FloatingElementsPdf.shapeToSvg(
        FloatingShapeType.triangle,
        90,
        70,
      );
      expect(triangle, contains('<path'));
    });

    test('square and rectangle frames are centred on the layout box', () {
      // Regression (C6): the frame must span the whole box, not an inset of
      // stroke/2, so the PDF outline lands where the preview's drawRect puts it.
      const shapes = [FloatingShapeType.square, FloatingShapeType.rectangle];
      for (final shape in shapes) {
        final svg = FloatingElementsPdf.shapeToSvg(
          shape,
          100,
          80,
          strokeWidth: 2,
        );
        expect(svg, contains('<rect x="0" y="0" width="100.0" height="80.0"'));
        expect(svg, isNot(contains('x="1.0"')));
        expect(svg, contains('stroke-width="2.0"'));
      }
    });
  });

  group('ExamCanvasGeometry', () {
    test('validates coordinate normalization shared with the UI canvas', () {
      expect(ExamCanvasGeometry.normalizedX(0), 0);
      expect(ExamCanvasGeometry.normalizedY(0), 0);
      expect(
        ExamCanvasGeometry.normalizedX(ExamCanvasGeometry.width),
        closeTo(1.0, 0.0001),
      );
      expect(
        ExamCanvasGeometry.normalizedY(ExamCanvasGeometry.height),
        closeTo(1.0, 0.0001),
      );
    });
  });
}
