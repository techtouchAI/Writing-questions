import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

// Round-4 isolation for canonical test-2: is a bare first resolve (no
// screen, no pumps, no tap) enough to poison a later runAsync resolve? If
// test B hangs here, the poison is the first resolve itself (static font
// state), not the screen.

ExamDocument _tinyDocument() => ExamDocument(
      name: 'Tiny direct resolve',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'tiny-question',
          questionNumber: 1,
          statement: 'Tap the MARKER in this question.',
          body: 'The body stays on the canonical page geometry.',
        ),
      ],
    );

ExamDocument _secondDocument() {
  const bodyPart =
      'هذا نص عربي طويل يختبر حدود الصفحة والانتقال بين الصفحات مع سلامة '
      'الهندسة ومواقع الكلمات في المعاينة القانونية.';
  return ExamDocument(
    name: 'RTL floating text hit',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    floatingElements: <FloatingElement>[
      FloatingElement(
        id: 'rtl-floating-note',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.textBox,
        dx: 110,
        dy: 170,
        pageIndex: 1,
        width: 300,
        height: 96,
        label: 'ملاحظة MixedCase42 — نهاية',
        framed: true,
      ),
    ],
    questions: <QuestionModel>[
      QuestionModel(
        id: 'long-rtl-question',
        questionNumber: 1,
        statement: 'تمهيد عربي English 123',
        body: List<String>.filled(72, bodyPart).join(' '),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iso-2b first: bare direct resolve without any screen',
      (tester) async {
    final controller = ExamWizardController(document: _tinyDocument());
    addTearDown(controller.dispose);
    debugPrint('[diag] iso-2b-a: resolving');
    final layout = await CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    );
    // Direct resolve returns a non-nullable LayoutDocument (only runAsync's
    // own Future<T?> wrapper is nullable), so no null checks here.
    debugPrint('[diag] iso-2b-a: resolved pages=${layout.pageCount}');
    expect(layout.pageCount, greaterThan(0));
    expect(identical(layout.source, controller.documentIr), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-2b-a: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('iso-2b second: runAsync resolve after a direct resolve',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = _secondDocument();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    debugPrint('[diag] iso-2b-b: resolving');
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: document,
        sourceIr: controller.documentIr,
      ),
    );
    debugPrint('[diag] iso-2b-b: resolved pages=${layout?.pageCount}');
    expect(layout, isNotNull);
    expect(layout!.pageCount, greaterThan(1));
    expect(identical(layout.source, controller.documentIr), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-2b-b: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));
}
