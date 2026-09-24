import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/floating_elements_pdf.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

int _countPages(List<int> bytes) {
  final source = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page(?![s\w])').allMatches(source).length;
}

Uint8List _png1x1() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
}

Exam _examWithExtras({
  bool withFormula = false,
  List<FloatingElement> elements = const <FloatingElement>[],
}) {
  return Exam(
    name: 'اختبار العناصر',
    header: ExamHeader(subject: 'الرياضيات'),
    mainQuestions: <MainQuestion>[
      MainQuestion(
        title: withFormula ? r'حل المعادلة $\frac{x}{2}=4$' : 'سؤال بسيط',
        type: QuestionType.essay,
        branches: <QuestionBranch>[
          QuestionBranch(
            text: withFormula ? r'أوجد قيمة $x$' : 'أوجد الناتج',
            marks: 3,
          ),
        ],
      ),
    ],
    floatingElements: elements,
  );
}

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

  group('PdfExamEngine 1:1 canvas mapping', () {
    test('embeds floating shapes and keeps the sheet on one page', () async {
      final exam = _examWithExtras(elements: <FloatingElement>[
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.circle,
          dx: 120,
          dy: 300,
          width: 80,
          height: 80,
        ),
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.triangle,
          dx: 500,
          dy: 700,
          width: 120,
          height: 90,
        ),
      ]);

      final bytes = await const PdfExamEngine()
          .generate(exam: exam, isTeacherVersion: false);

      expect(_countPages(bytes), 1);
      expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
    });

    test('embeds floating images as PDF image XObjects', () async {
      final exam = _examWithExtras(elements: <FloatingElement>[
        FloatingElement(
          type: FloatingElementType.image,
          bytes: _png1x1(),
          dx: ExamCanvasGeometry.defaultElementDx,
          dy: ExamCanvasGeometry.defaultElementDy,
          width: 100,
          height: 100,
        ),
      ]);

      final bytes = await const PdfExamEngine()
          .generate(exam: exam, isTeacherVersion: false);
      final source = String.fromCharCodes(bytes);

      expect(_countPages(bytes), 1);
      expect(source, contains('/Subtype /Image'));
    });

    test('renders LaTeX question titles as SVG without breaking the page', () async {
      final exam = _examWithExtras(withFormula: true);
      final bytes = await const PdfExamEngine()
          .generate(exam: exam, isTeacherVersion: false);

      expect(_countPages(bytes), 1);
      expect(bytes.length, greaterThan(5 * 1024));
    });

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
