import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

// Round-4 isolation for canonical test-2: is second-use `tester.runAsync`
// alone enough to hang, with no screen and no direct resolve anywhere? If
// test B hangs here, the poison is pure runAsync reuse; if B passes,
// runAsync reuse is innocent and the poison needs other context.

ExamDocument _document() {
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

  testWidgets('iso-2c first: runAsync resolve with no prior use', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    debugPrint('[diag] iso-2c-a: resolving');
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: document,
        sourceIr: controller.documentIr,
      ),
    );
    debugPrint('[diag] iso-2c-a: resolved pages=${layout?.pageCount}');
    expect(layout, isNotNull);
    expect(layout!.pageCount, greaterThan(1));
    expect(identical(layout.source, controller.documentIr), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-2c-a: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('iso-2c second: identical runAsync resolve immediately after',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    debugPrint('[diag] iso-2c-b: resolving');
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: document,
        sourceIr: controller.documentIr,
      ),
    );
    debugPrint('[diag] iso-2c-b: resolved pages=${layout?.pageCount}');
    expect(layout, isNotNull);
    expect(layout!.pageCount, greaterThan(1));
    expect(identical(layout.source, controller.documentIr), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-2c-b: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));
}
