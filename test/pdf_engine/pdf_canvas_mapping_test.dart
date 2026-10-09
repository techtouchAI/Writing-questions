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
