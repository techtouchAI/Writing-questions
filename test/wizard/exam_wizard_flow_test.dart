import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/exam_wizard_screen.dart';

Widget _app(Widget home) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(home: home),
  );
}

ExamDocument _previewDocument({int questionCount = 2}) {
  return ExamDocument(
    name: 'معاينة',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      for (var q = 0; q < questionCount; q++)
        QuestionModel(
          id: 'q${q + 1}',
          questionNumber: q + 1,
          branches: <BranchModel>[
            BranchModel(
              id: 'q${q + 1}a',
              content: BranchContent(type: QuestionType.essay, text: 'محتوى س${q + 1} أ'),
              marks: q + 1.0,
            ),
            BranchModel(
              id: 'q${q + 1}b',
              content: BranchContent(type: QuestionType.essay, text: 'محتوى س${q + 1} ب'),
              marks: 1,
            ),
          ],
        ),
    ],
  );
}

Widget _preview(ExamWizardController controller) {
  return _app(
    ChangeNotifierProvider<ExamWizardController>.value(
      value: controller,
      child: ExamPreviewScreen(onBackToQuestions: () {}),
    ),
  );
}

void main() {
  group('Wizard step flow', () {
    testWidgets('walks header → first question → second question → preview', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(const ExamWizardScreen()));

      // الخطوة 1: الترويسة بأعمدتها الثلاثة.
      expect(find.text('الخطوة 1: ترويسة النموذج الوزاري'), findsOneWidget);
      expect(find.text('العمود الأيمن'), findsOneWidget);
      expect(find.text('العمود الأوسط'), findsOneWidget);
      expect(find.text('العمود الأيسر'), findsOneWidget);

      await tester.ensureVisible(find.text('التالي: إعداد السؤال الأول'));
      await tester.tap(find.text('التالي: إعداد السؤال الأول'));
      await tester.pumpAndSettle();

      // الخطوة 2: العنوان ديناميكي ويبدأ بالفرع (أ).
      expect(find.text('إعداد السؤال الأول'), findsOneWidget);
      expect(find.text('الفرع (أ)'), findsOneWidget);

      // إضافة فرع جديد يضيف (ب) بنفس الأدوات.
      await tester.ensureVisible(find.textContaining('إضافة فرع جديد'));
      await tester.tap(find.textContaining('إضافة فرع جديد'));
      await tester.pumpAndSettle();
      expect(find.text('الفرع (ب)'), findsOneWidget);

      // بدون محتوى لا يُسمح بالمتابعة.
      await tester.tap(find.text('التالي: سؤال جديد'));
      await tester.pumpAndSettle();
      expect(find.text('إعداد السؤال الأول'), findsOneWidget);

      // كتابة محتوى ودرجة ثم [التالي] يفتح «إعداد السؤال الثاني».
      await tester.enterText(find.widgetWithText(TextFormField, 'نص الفرع').first, 'عرّف الفاعل');
      await tester.enterText(find.widgetWithText(TextFormField, 'الدرجة').first, '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('التالي: سؤال جديد'));
      await tester.pumpAndSettle();
      expect(find.text('إعداد السؤال الثاني'), findsOneWidget);
      expect(find.text('الفرع (أ)'), findsOneWidget);
      expect(find.text('الفرع (ب)'), findsNothing);

      // إنهاء وعرض النموذج من سؤال فارغ مرفوض، ومن السؤال الأول مقبول.
      await tester.tap(find.text('السؤال الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنهاء وعرض النموذج'));
      await tester.pumpAndSettle();

      expect(find.textContaining('الخطوة 3: معاينة A4'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('a4-page-0')), findsOneWidget);
      expect(find.text('السؤال الأول: [٥ درجة]'), findsOneWidget);
    });
  });

  group('ExamPreviewScreen', () {
    testWidgets('measures blocks and paginates whole questions onto pages', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 3));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();

      // كل الكتل قيست ديناميكياً عبر MeasureSize.
      expect(controller.isFullyMeasured, isTrue);
      expect(controller.blockHeight(PaperMetrics.headerBlockId), greaterThan(0));
      expect(controller.blockHeight('q1'), greaterThan(0));

      // ثلاثة أسئلة مقالية قصيرة تتسع في صفحة واحدة.
      expect(controller.pagination.pageCount, 1);
      expect(find.byKey(const ValueKey<String>('a4-page-0')), findsOneWidget);
      expect(find.text('السؤال الأول: [٢ درجة]'), findsOneWidget);
      expect(find.text('السؤال الثالث: [٤ درجة]'), findsOneWidget);
    });

    testWidgets('moves a question that no longer fits to the next page as a whole', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 2));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();
      expect(controller.pagination.pageCount, 1);

      // ضخّم السؤال الثاني حتى لا يتسع مع الأول في الصفحة نفسها.
      final pageHeight = PaperMetrics.pageContentHeightPx;
      controller.reportBlockHeight('q2', pageHeight * 0.95);
      await tester.pump();

      expect(controller.pagination.pageCount, 2);
      expect(controller.pageAssignments[0], <String>['q1']);
      expect(controller.pageAssignments[1], <String>['q2']);
      expect(find.byKey(const ValueKey<String>('a4-page-1')), findsOneWidget);
      // السؤال الثاني وفروعه معاً على الصفحة الثانية (لا فصل للفروع).
      final page1 = find.byKey(const ValueKey<String>('a4-page-1'));
      expect(
        find.descendant(of: page1, matching: find.text('محتوى س2 أ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: page1, matching: find.text('محتوى س2 ب')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: page1, matching: find.text('السؤال الثاني: [٣ درجة]')),
        findsOneWidget,
      );
    });

    testWidgets('in-place editing updates the model without leaving the sheet', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 1));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      await tester.enterText(find.text('محتوى س1 أ'), 'نص معدّل مباشرة');
      await tester.pump();

      expect(
        controller.document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 0)).content.text,
        'نص معدّل مباشرة',
      );
    });

    testWidgets('drag & drop swaps branch content while headings stay in place', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 2));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();

      final source = find.byKey(const ValueKey<String>('branch-target-q1a'));
      final target = find.byKey(const ValueKey<String>('branch-target-q2b'));
      expect(source, findsOneWidget);
      expect(target, findsOneWidget);

      // سحب بالضغط المطوّل من (السؤال الأول - أ) إلى (السؤال الثاني - ب).
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      const q1a = BranchRef(questionIndex: 0, branchIndex: 0);
      const q2b = BranchRef(questionIndex: 1, branchIndex: 1);
      expect(controller.document.branchAt(q1a).content.text, 'محتوى س2 ب');
      expect(controller.document.branchAt(q1a).marks, 1);
      expect(controller.document.branchAt(q2b).content.text, 'محتوى س1 أ');
      expect(controller.document.branchAt(q2b).marks, 1);
      expect(controller.document.branchAt(q1a).id, 'q1a');
      expect(controller.document.branchAt(q2b).id, 'q2b');

      // العناوين لم تتحرك، والحقول على الورقة تعكس المحتوى الجديد.
      expect(find.text('السؤال الأول: [٢ درجة]'), findsOneWidget);
      expect(find.text('السؤال الثاني: [٣ درجة]'), findsOneWidget);
      final firstField = tester.widget<TextField>(
        find.descendant(of: source, matching: find.byType(TextField)).first,
      );
      expect(firstField.controller!.text, 'محتوى س2 ب');
    });

    testWidgets('exposes the floating tools toolbar above the pages', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 1));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      expect(find.text('وسائط'), findsOneWidget);
      expect(find.text('رياضيات'), findsOneWidget);

      // إضافة شكل بلا فرع محدد تُرشد المستخدم؛ وبعد التحديد يُثبَّت فوق الفرع.
      await tester.tap(find.text('وسائط'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مربع'));
      await tester.pump();
      expect(find.textContaining('انقر على فرع داخل الورقة'), findsOneWidget);

      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      await tester.pump();
      await tester.tap(find.text('مربع'));
      await tester.pump();
      expect(
        controller.document
            .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
            .attachments,
        hasLength(1),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
