import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

// Round-4 isolation for canonical test-2: does ONE preceding canonical
// screen test poison a later `tester.runAsync(resolve)`? Test A mirrors the
// essential shape of canonical test-1 (screen resolve + page + tap +
// dispose); test B mirrors canonical test-2 (runAsync resolve). If B hangs,
// the poison needs only one prior screen test; if B passes, test-2's hang
// needs fuller context (to be bisected next).

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 40,
}) async {
  for (var attempt = 0; attempt < maxFrames && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _screenCanonical(ExamWizardController controller) => MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(
          onBackToQuestions: () {},
          canonicalLayoutResolver: ({
            required ExamDocument document,
            required DocumentIR sourceIr,
          }) =>
              CanonicalLayoutService.resolve(
            document: document,
            sourceIr: sourceIr,
          ),
          canonicalPreviewAssetLoader: ({
            required LayoutDocument layout,
            required ExamDocument document,
          }) =>
              CanonicalLayoutPreviewAssets.load(
            layout: layout,
            document: document,
          ),
        ),
      ),
    );

ExamDocument _firstDocument() {
  const repeatedBody =
      'هذا نص عربي طويل يختبر انتقال الفقرة إلى الصفحة التالية مع بقاء '
      'القياس والهندسة والأبعاد متطابقة';
  return ExamDocument(
    name: 'RTL mixed script and page boundary',
    header: ExamHeaderModel.initial(subject: 'الرياضيات'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'first-question',
        questionNumber: 1,
        statement: 'تمهيد عربي English 123',
        body: List<String>.filled(120, repeatedBody).join(' '),
      ),
      QuestionModel(
        id: 'source-question',
        questionNumber: 2,
        statement: 'مصدر مختلط MixCase ٣١٢ ثم MARKER وEnglish42',
        body: 'نص أخير للاختبار.',
      ),
    ],
  );
}

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

  testWidgets('iso-2a first: canonical screen resolves via production seams',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = ExamWizardController(document: _firstDocument());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_screenCanonical(controller));
    await _pumpUntil(
      tester,
      () => find.byType(CanonicalLayoutPreviewPage).evaluate().isNotEmpty,
    );
    final pageFinders = find.byType(CanonicalLayoutPreviewPage);
    expect(pageFinders, findsWidgets);
    final layout =
        tester.widget<CanonicalLayoutPreviewPage>(pageFinders.first).layoutDocument;
    expect(layout.pageCount, greaterThan(1));
    await tester.tapAt(tester.getCenter(pageFinders.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint('[diag] iso-2a-a: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('iso-2a second: runAsync resolve after a screen test',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = _secondDocument();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    debugPrint('[diag] iso-2a-b: resolving');
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: document,
        sourceIr: controller.documentIr,
      ),
    );
    debugPrint('[diag] iso-2a-b: resolved pages=${layout?.pageCount}');
    expect(layout, isNotNull);
    final canonical = layout!;
    expect(canonical.pageCount, greaterThan(1));
    expect(identical(canonical.source, controller.documentIr), isTrue);
    final placement = canonical.pages[1].floatingElements.singleWhere(
      (candidate) => candidate.reference.id == 'rtl-floating-note',
    );
    expect(placement.pageIndex, 1);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-2a-b: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));
}
