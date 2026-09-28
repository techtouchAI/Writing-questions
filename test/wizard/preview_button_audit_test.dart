import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

ExamDocument _document() => ExamDocument(
      name: 'تدقيق الأزرار',
      header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
      questions: [
        QuestionModel(id: 'q1', questionNumber: 1, prompt: 'السؤال الأول', branches: [
          BranchModel(id: 'b1', content: BranchContent(type: QuestionType.essay, text: 'الفرع الأول')),
        ]),
        QuestionModel(id: 'q2', questionNumber: 2, prompt: 'السؤال الثاني'),
      ],
    );

Future<void> _pump(WidgetTester tester, ExamWizardController controller,
    {double width = 1600, VoidCallback? onBack}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider.value(
      value: controller,
      child: ExamPreviewScreen(onBackToQuestions: onBack ?? () {}),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _tool(String tooltip) => find.descendant(
      of: find.byType(PreviewToolbar), matching: find.byTooltip(tooltip)).last;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.descendant(
    of: find.byKey(ValueKey<String>(key)), matching: find.byType(TextField));

void main() {
  // A miss is a failure, not a warning: these tests reproduce the original
  // "visible but untappable" controls, rather than calling callbacks directly.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('automatic font, size, spacing and color really clear overrides', (tester) async {
    final controller = ExamWizardController(document: _document());
    controller.updateQuestionStyle(0, const PaperTextStyle(
      font: PaperFont.tajawal, fontSize: 20, lineHeight: 2, color: 0xFF1E3A8A,
    ));
    await _pump(tester, controller);
    for (final menu in ['نوع الخط', 'حجم الخط', 'تباعد الأسطر', 'لون النص']) {
      await _tap(tester, _tool(menu));
      await _tap(tester, find.text(menu == 'نوع الخط' ? 'افتراضي الورقة' : 'تلقائي').last);
    }
    expect(controller.questions.first.style.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing focus selects branch, question and header for formatting', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('branch-b1'));
    await _tap(tester, _tool('عريض'));
    await _tap(tester, _tool('مائل'));
    await _tap(tester, _tool('تحته خط'));
    await _tap(tester, _tool('إطار حول التحديد'));
    final branch = controller.questions.first.branches.single;
    expect(branch.style.bold, isTrue);
    expect(branch.style.italic, isTrue);
    expect(branch.style.underline, isTrue);
    expect(branch.showFrame, isTrue);
    expect(controller.questions.first.style.isEmpty, isTrue);

    await _tap(tester, _field('prompt-q2'));
    for (final entry in {
      'محاذاة لليمين': PaperAlign.right,
      'توسيط': PaperAlign.center,
      'محاذاة لليسار': PaperAlign.left,
      'ضبط': PaperAlign.justify,
    }.entries) {
      await _tap(tester, _tool(entry.key));
      expect(controller.questions[1].style.align, entry.value);
    }
    final headerField = find.byType(PaperField).first;
    await _tap(tester, find.descendant(of: headerField, matching: find.byType(TextField)));
    await _tap(tester, _tool('تحته خط'));
    expect(controller.document.header.style.underline, isTrue);
    expect(controller.questions[1].style.underline, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo/redo text does not feed synchronization back into history', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await tester.enterText(_field('branch-b1'), 'نص جديد');
    await tester.pumpAndSettle();
    await _tap(tester, _tool('تراجع'));
    expect(controller.questions.first.branches.single.content.text, 'الفرع الأول');
    expect(controller.canRedo, isTrue);
    expect(tester.widget<TextField>(_field('branch-b1')).controller!.text, 'الفرع الأول');
    await _tap(tester, _tool('إعادة'));
    expect(controller.questions.first.branches.single.content.text, 'نص جديد');
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving questions retains the correct field edit owner', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    controller.moveQuestion(0, 1);
    await tester.pumpAndSettle();
    await tester.enterText(_field('prompt-q1'), 'تم تحرير الأول بعد نقله');
    await tester.pumpAndSettle();
    expect(controller.document.questionById('q1')!.prompt, 'تم تحرير الأول بعد نقله');
    expect(controller.document.questionById('q2')!.prompt, 'السؤال الثاني');
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating toolbar and corner handles receive real taps', (tester) async {
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(FloatingElement(
      id: 'shape', type: FloatingElementType.shape, shape: FloatingShapeType.square,
      dx: 150, dy: 650, width: 90, height: 80,
    ), questionIndex: 0);
    await _pump(tester, controller);
    await _tap(tester, find.byKey(const ValueKey('page-element-shape')));
    FloatingElement element() => controller.questions.first.attachments.single;
    final stroke = element().strokeWidth;
    await _tap(tester, find.byTooltip('زيادة سماكة الحد'));
    expect(element().strokeWidth, stroke + 0.5);
    await _tap(tester, find.byTooltip('تقليل سماكة الحد'));
    expect(element().strokeWidth, stroke);
    await _tap(tester, find.byTooltip('توسيط العنصر'));
    final centered = element().dx;
    await _tap(tester, find.byTooltip('محاذاة لليمين').last);
    expect(element().dx, isNot(centered));
    await _tap(tester, find.byTooltip('محاذاة لليسار').last);
    expect(element().dx, isNot(centered));
    await _tap(tester, find.byKey(const ValueKey('rotate-element-shape')));
    expect(element().rotationDegrees, 45);
    await _tap(tester, _tool('قفل التحريك'));
    expect(find.byKey(const ValueKey('delete-element-shape')), findsNothing);
    await _tap(tester, _tool('فتح القفل (السماح بالتحريك)'));
    await _tap(tester, find.byKey(const ValueKey('delete-element-shape')));
    expect(controller.questions.first.attachments, isEmpty);
    await _tap(tester, _tool('تراجع'));
    expect(controller.questions.first.attachments, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text box edit handle opens the editor and saves', (tester) async {
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(FloatingElement(
      id: 'box', type: FloatingElementType.shape, shape: FloatingShapeType.textBox,
      dx: 150, dy: 650, width: 180, height: 90,
    ), questionIndex: 0);
    await _pump(tester, controller);
    await _tap(tester, find.byKey(const ValueKey('page-element-box')));
    await _tap(tester, find.byKey(const ValueKey('edit-element-box')));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'ملاحظة جديدة');
    await _tap(tester, find.text('حفظ'));
    expect(controller.questions.first.attachments.single.label, 'ملاحظة جديدة');
  });

  testWidgets('phone toolbar scroll, zoom controls, formulas toggle and review buttons', (tester) async {
    final controller = ExamWizardController(document: _document());
    var back = false;
    await _pump(tester, controller, width: 390, onBack: () => back = true);
    await _tap(tester, _tool('نسبة التكبير — انقر للعودة إلى 100%'));
    expect(find.text('100%'), findsOneWidget);
    await _tap(tester, _tool('تكبير'));
    expect(find.text('120%'), findsOneWidget);
    await _tap(tester, _tool('تصغير'));
    expect(find.text('100%'), findsOneWidget);
    await _tap(tester, _tool('ملاءمة الورقة للشاشة'));
    expect(find.text('100%'), findsNothing);
    await _tap(tester, _tool('توسيط الورقة'));
    await _tap(tester, _tool('شريط الصيغ والوسائط'));
    expect(find.text('رياضيات'), findsNothing);
    await _tap(tester, _tool('شريط الصيغ والوسائط'));
    expect(find.text('رياضيات'), findsOneWidget);
    for (final format in ['PDF', 'Word']) {
      await _tap(tester, _tool('مراجعة وتصدير $format'));
      expect(find.text('مراجعة الورقة'), findsOneWidget);
      expect(find.text('ورقة الطالب'), findsOneWidget);
      await _tap(tester, find.text('رجوع'));
    }
    await _tap(tester, find.byTooltip('عرض نموذج الإجابة'));
    await _tap(tester, _tool('مراجعة وتصدير PDF'));
    expect(find.text('نموذج الإجابة'), findsOneWidget);
    await _tap(tester, find.text('رجوع'));
    await _tap(tester, find.byTooltip('العودة للأسئلة'));
    expect(back, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text insertion without a field gives guidance instead of silence', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, find.text('سطر جديد'));
    expect(find.text('انقر داخل حقل نصي على الورقة أولاً.'), findsOneWidget);
    await _tap(tester, _field('branch-b1'));
    await _tap(tester, find.text('ملاحظة للمعلم'));
    expect(controller.questions.first.branches.single.content.text, contains('ملاحظة: '));
    await _tap(tester, find.byTooltip('حذف الفرع'));
    await _tap(tester, find.text('سطر جديد'));
    expect(tester.takeException(), isNull);
  });
}
