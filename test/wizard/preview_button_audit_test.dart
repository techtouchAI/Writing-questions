import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/providers/exam_document_provider.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/widgets/smart_exam_toolbar.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

class _TestImagePicker extends ImagePickerPlatform {
  _TestImagePicker({this.fail = false, this.file});
  final bool fail;
  final XFile? file;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (fail) throw StateError('Gallery permission denied');
    return file;
  }
}

ExamDocument _document() => ExamDocument(
      name: 'تدقيق الأزرار',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: [
        QuestionModel(id: 'q1', questionNumber: 1, prompt: 'السؤال الأول', branches: [
          BranchModel(id: 'b1', content: BranchContent(type: QuestionType.essay, text: 'الفرع الأول')),
        ]),
        QuestionModel(id: 'q2', questionNumber: 2, prompt: 'السؤال الثاني'),
      ],
    );

Future<void> _pump(WidgetTester tester, ExamWizardController controller,
    {double width = 1600, VoidCallback? onBack, ExamDocumentProvider? library}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        if (library != null) ChangeNotifierProvider.value(value: library),
      ],
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
    for (final menu in ['نوع الخط', 'حجم الخط', 'تباعد الأسطر', 'لون عنوان السؤال']) {
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
    await _tap(tester, _field('header-right-0'));
    expect(tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).selectionLabel, 'الترويسة');
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

  testWidgets('free elements can be added to a document with no questions', (tester) async {
    final controller = ExamWizardController(
      document: ExamDocument(
        name: 'ورقة فارغة',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      ),
    );
    await _pump(tester, controller);

    await _tap(tester, _tool('إدراج شكل'));
    await _tap(tester, find.text('مربع').last);

    expect(controller.document.questions, isEmpty);
    expect(controller.document.floatingElements, hasLength(1));
    expect(controller.document.floatingElements.single.shape, FloatingShapeType.square);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected free elements can move to another preview page', (tester) async {
    final document = ExamDocument(
      name: 'تعدد الصفحات',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: List<String>.filled(100, 'سطر طويل لاختبار تعدد الصفحات').join('\n'),
          attachments: <FloatingElement>[
            FloatingElement(
              id: 'legacy-page-nav-element',
              type: FloatingElementType.shape,
              shape: FloatingShapeType.square,
              dx: 220,
              dy: 260,
              width: 60,
              height: 60,
            ),
          ],
        ),
        QuestionModel(id: 'q2', questionNumber: 2, prompt: 'السؤال الثاني'),
      ],
    );
    final controller = ExamWizardController(document: document);
    controller.addFloatingElement(FloatingElement(
      id: 'page-nav-element',
      type: FloatingElementType.shape,
      shape: FloatingShapeType.square,
      dx: 140,
      dy: 180,
      width: 60,
      height: 60,
    ));
    await _pump(tester, controller);
    expect(controller.pagination.pageCount, greaterThan(1));

    await _tap(tester, find.byKey(const ValueKey('page-element-page-nav-element')));
    await _tap(tester, find.byTooltip('نقل إلى الصفحة التالية'));

    expect(controller.document.floatingElements.single.pageIndex, 1);

    await _tap(tester, find.byKey(const ValueKey('page-element-legacy-page-nav-element')));
    await _tap(tester, find.byTooltip('نقل إلى الصفحة السابقة'));
    expect(
      controller.document.floatingElementById('legacy-page-nav-element')!.pageIndex,
      0,
    );
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
    Future<void> tapTool(String tooltip) async {
      final scrollable = find.descendant(
        of: find.byType(PreviewToolbar), matching: find.byType(Scrollable));
      // ListView lazily disposes distant buttons. Scroll them into the tree
      // before ensureVisible/tap, just as a phone user swipes the toolbar.
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      final target = find.descendant(
        of: find.byType(PreviewToolbar), matching: find.byTooltip(tooltip));
      await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    final controller = ExamWizardController(document: _document());
    var back = false;
    await _pump(tester, controller, width: 390, onBack: () => back = true);
    await tapTool('نسبة التكبير — انقر للعودة إلى 100%');
    expect(tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).zoom, 1);
    await tapTool('تكبير');
    expect(tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).zoom, closeTo(1.2, 0.001));
    await tapTool('تصغير');
    expect(tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).zoom, 1);
    await tapTool('ملاءمة الورقة للشاشة');
    expect(tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).zoom, lessThan(1));
    await tapTool('توسيط الورقة');
    await tapTool('شريط الصيغ والوسائط');
    expect(find.text('رياضيات'), findsNothing);
    await tapTool('شريط الصيغ والوسائط');
    expect(find.text('رياضيات'), findsOneWidget);
    for (final format in ['PDF', 'Word']) {
      await tapTool('مراجعة وتصدير $format');
      expect(find.text('مراجعة الورقة'), findsOneWidget);
      // ورقة واحدة للأسئلة: لا مبدّل «ورقة الطالب/نموذج الإجابة» إطلاقاً.
      expect(find.text('ورقة الطالب'), findsNothing);
      expect(find.textContaining('نموذج الإجابة'), findsNothing);
      await _tap(tester, find.text('رجوع'));
    }
    // لا وجود لنسخة «نموذج الإجابة» ولا لأي زر يفتحها في أي مرحلة.
    expect(find.byTooltip('عرض نموذج الإجابة'), findsNothing);
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

  testWidgets('all shape menu entries and media chips insert as free document elements', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('prompt-q1'));
    final shapes = {
      'مستطيل': FloatingShapeType.rectangle, 'مربع': FloatingShapeType.square,
      'دائرة': FloatingShapeType.circle, 'مثلث': FloatingShapeType.triangle,
      'خط': FloatingShapeType.line, 'سهم': FloatingShapeType.arrow,
    };
    for (final entry in shapes.entries) {
      final before = controller.document.floatingElements.length;
      await _tap(tester, _tool('إدراج شكل'));
      await _tap(tester, find.text(entry.key).last);
      expect(controller.document.floatingElements.length, before + 1);
      expect(controller.document.floatingElements.last.shape, entry.value);
    }
    await _tap(tester, find.text('وسائط'));
    for (final entry in shapes.entries) {
      final before = controller.document.floatingElements.length;
      await _tap(tester, find.text(entry.key).last);
      expect(controller.document.floatingElements.length, before + 1);
      expect(controller.document.floatingElements.last.shape, entry.value);
    }
    expect(controller.questions.every((question) => question.attachments.isEmpty), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add divider, thickness, width and delete have visible model effects', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('prompt-q1'));
    await _tap(tester, _tool('إضافة فاصل'));
    expect(controller.questions.first.dividerAfter, isNotNull);
    await _tap(tester, find.byKey(const ValueKey('divider-q:q1')));
    await _tap(tester, find.text('السماكة'));
    expect(controller.questions.first.dividerAfter!.thickness, 3);
    await _tap(tester, find.text('كامل'));
    expect(controller.questions.first.dividerAfter!.widthFraction, 0.66);
    await _tap(tester, find.text('ثلثان'));
    expect(controller.questions.first.dividerAfter!.widthFraction, 0.33);
    await _tap(tester, find.text('ثلث'));
    expect(controller.questions.first.dividerAfter!.widthFraction, 1);
    await _tap(tester, find.text('حذف'));
    expect(controller.questions.first.dividerAfter, isNull);
  });

  testWidgets('question and branch add, copy, label and delete buttons', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('prompt-q1'));
    await _tap(tester, find.text('فرع جديد'));
    expect(controller.questions.first.branches, hasLength(2));
    expect(controller.questions[1].branches, isEmpty);
    await _tap(tester, find.byTooltip('نسخ الفرع').first);
    expect(controller.questions.first.branches, hasLength(3));
    await _tap(tester, find.byTooltip('تثبيت تسمية الفرع').first);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'أولاً');
    await _tap(tester, find.text('حفظ'));
    expect(controller.questions.first.branches.first.labelOverride, 'أولاً');
    await _tap(tester, find.byTooltip('حذف الفرع').first);
    expect(controller.questions.first.branches, hasLength(2));
    await _tap(tester, find.byTooltip('نسخ السؤال').first);
    expect(controller.questions, hasLength(3));
    await _tap(tester, find.byTooltip('تثبيت تسمية السؤال').first);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'تمرين');
    await _tap(tester, find.text('حفظ'));
    expect(controller.questions.first.numberOverride, 'تمرين');
    await _tap(tester, find.byTooltip('حذف السؤال').first);
    await _tap(tester, find.text('حذف'));
    expect(controller.questions, hasLength(2));
    await _tap(tester, find.text('سؤال جديد'));
    expect(controller.questions, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi selection formats both questions and can be switched off', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _tool('تحديد متعدد'));
    await _tap(tester, _field('prompt-q1'));
    await _tap(tester, _field('prompt-q2'));
    await _tap(tester, _tool('مائل'));
    expect(controller.questions.every((q) => q.style.italic == true), isTrue);
    await _tap(tester, _tool('تحديد متعدد'));
    await _tap(tester, _field('prompt-q1'));
    await _tap(tester, _tool('مائل'));
    expect(controller.questions.first.style.italic, isFalse);
    expect(controller.questions.last.style.italic, isTrue);
  });

  testWidgets('question spacing presets and custom values update the selected question', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);

    await _tap(tester, _tool('المسافة بين الأسئلة'));
    await _tap(tester, find.text('24 بكسل').last);
    expect(controller.questions.first.spacingAfter, 24);

    await _tap(tester, _tool('المسافة بين الأسئلة'));
    await _tap(tester, find.text('قيمة مخصصة...'));
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '120',
    );
    await _tap(tester, find.text('تطبيق'));
    expect(controller.questions.first.spacingAfter, 120);

    await _tap(tester, _field('prompt-q2'));
    await _tap(tester, _tool('المسافة بين الأسئلة'));
    await _tap(tester, find.text('0 بكسل — بلا فراغ'));
    expect(controller.questions[1].spacingAfter, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom size, spacing and HEX apply; cancellation leaves formatting unchanged', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    for (final entry in {
      'حجم الخط': '17',
      'تباعد الأسطر': '1.7',
      'لون عنوان السؤال': '#ABCDEF',
    }.entries) {
      await _tap(tester, _tool(entry.key));
      await _tap(tester, find.text('مخصص...'));
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), entry.value);
      await _tap(tester, find.text('تطبيق'));
    }
    expect(controller.questions.first.style.fontSize, 17);
    expect(controller.questions.first.style.lineHeight, 1.7);
    expect(controller.questions.first.titleColor, 0xFFABCDEF);
    expect(controller.questions.first.style.color, isNull);
    await _tap(tester, _tool('حجم الخط'));
    await _tap(tester, find.text('مخصص...'));
    await _tap(tester, find.text('إلغاء'));
    expect(controller.questions.first.style.fontSize, 17);
  });

  testWidgets('settings cancel and apply are separate actions', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    final original = controller.document.settings.pageBorder;
    await _tap(tester, find.byTooltip('إعدادات الورقة'));
    await _tap(tester, find.text('إطار حول الصفحة'));
    await _tap(tester, find.text('إلغاء'));
    expect(controller.document.settings.pageBorder, original);
    await _tap(tester, find.byTooltip('إعدادات الورقة'));
    await _tap(tester, find.text('إطار حول الصفحة'));
    await _tap(tester, find.text('تطبيق'));
    expect(controller.document.settings.pageBorder, !original);
    await _tap(tester, _tool('تراجع'));
    expect(controller.document.settings.pageBorder, original);
  });

  testWidgets('both save buttons persist the document in the library', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = ExamDocumentProvider();
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller, library: library);
    await _tap(tester, find.byTooltip('حفظ الورقة'));
    expect(library.documents.single.id, controller.document.id);
    await tester.enterText(_field('prompt-q1'), 'نص محفوظ');
    await tester.pumpAndSettle();
    await _tap(tester, _tool('حفظ'));
    expect(library.documents.single.questions.first.prompt, 'نص محفوظ');
    final reloaded = ExamDocumentProvider();
    await reloaded.loadDocuments();
    expect(reloaded.documents.single.questions.first.prompt, 'نص محفوظ');
  });

  testWidgets('every formula template opens an editor, cancel does not insert', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    for (final tab in {
      'رياضيات': ['محرر المعادلات', 'كسر', 'جذر', 'أس', 'فرعي', 'متكامل', 'مجموع', 'نهاية', 'معادلة'],
      'كيمياء': ['ماء', 'ثاني أكسيد الكربون', 'حمض الكبريتيك', 'الأمونيا', 'سهم تفاعل', 'تفاعل عكوس', 'معادلة أيونية'],
      'فيزياء': ['قوانين نيوتن', 'نسبية', 'قانون أوم', 'الشغل', 'سرعة', 'متغير'],
    }.entries) {
      await _tap(tester, find.text(tab.key));
      for (final label in tab.value) {
        await _tap(tester, find.text(label).last);
        expect(find.byType(Dialog), findsOneWidget);
        await _tap(tester, find.text('إلغاء'));
      }
    }
    expect(controller.questions.first.attachments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every preset font, size, spacing and color changes the target', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    for (final font in PaperFont.values) {
      await _tap(tester, _tool('نوع الخط'));
      await _tap(tester, find.textContaining(font.arabicLabel).last);
      expect(controller.questions.first.style.font, font);
    }
    for (final size in PreviewToolbar.fontSizes) {
      await _tap(tester, _tool('حجم الخط'));
      await _tap(tester, find.text(size.toInt().toString()).last);
      expect(controller.questions.first.style.fontSize, size);
    }
    for (final spacing in PreviewToolbar.lineSpacings) {
      await _tap(tester, _tool('تباعد الأسطر'));
      await _tap(tester, find.text(spacing.toString()).last);
      expect(controller.questions.first.style.lineHeight, spacing);
    }
    for (final color in PreviewToolbar.textColors) {
      await _tap(tester, _tool('لون عنوان السؤال'));
      await _tap(tester, find.textContaining(color.$2).last);
      expect(controller.questions.first.titleColor, color.$1);
      expect(controller.questions.first.style.color, isNull);
    }
  });

  testWidgets('resize handle is inside hit bounds, including at non-default zoom', (tester) async {
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(FloatingElement(
      id: 'resize', type: FloatingElementType.shape, shape: FloatingShapeType.rectangle,
      dx: 100, dy: 600, width: 100, height: 80,
    ), questionIndex: 0);
    await _pump(tester, controller);
    await _tap(tester, _tool('تكبير'));
    await _tap(tester, find.byKey(const ValueKey('page-element-resize')));
    final handle = find.byKey(const ValueKey('resize-element-resize'));
    await tester.ensureVisible(handle);
    // Arabic page: dx is measured from the right, so drag the resize handle left to widen.
    await tester.drag(handle, const Offset(-36, 24));
    await tester.pumpAndSettle();
    final element = controller.questions.first.attachments.single;
    expect(element.width, greaterThan(100));
    expect(element.height, greaterThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch point add, label, answer and delete without reorder controls', (tester) async {
    final controller = ExamWizardController(document: _document());
    const ref = BranchRef(questionIndex: 0, branchIndex: 0);
    controller.updateBranchType(ref, QuestionType.trueFalse);
    controller.setBranchItemCount(ref, 2);
    controller.updateBranchItemText(ref, 0, 'الأولى');
    controller.updateBranchItemText(ref, 1, 'الثانية');
    await _pump(tester, controller);
    expect(find.byTooltip('نقل النقطة لأعلى'), findsNothing);
    expect(find.byTooltip('نقل النقطة لأسفل'), findsNothing);
    final firstItemId = controller.document.branchAt(ref).content.items.first.id;
    await _tap(tester, find.byKey(ValueKey<String>('item-$firstItemId')));
    await _tap(tester, find.byTooltip('انقر لتعديل ترقيم النقطة').first);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'أولاً');
    await _tap(tester, find.text('حفظ'));
    expect(controller.document.branchAt(ref).content.items.first.labelOverride, 'أولاً');
    // لا زر «نموذج الإجابة» ولا أي عنصر إجابة في الواجهة إطلاقاً.
    expect(find.byTooltip('عرض نموذج الإجابة'), findsNothing);
    expect(find.byKey(const ValueKey<String>('b-b1-answer-0')), findsNothing);
    final firstItem = controller.document.branchAt(ref).content.items.first;
    expect(firstItem.toMap().containsKey('isCorrect'), isFalse);
    await _tap(tester, find.byTooltip('إضافة نقطة'));
    expect(controller.document.branchAt(ref).content.items, hasLength(3));
    await _tap(tester, find.byTooltip('حذف النقطة').last);
    expect(controller.document.branchAt(ref).content.items, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quran insertion and staged formula cancellation give real effects', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('branch-b1'));
    await _tap(tester, find.text('آية قرآنية'));
    expect(controller.questions.first.branches.single.content.text, contains('﴿'));
    await _tap(tester, find.text('رياضيات'));
    await _tap(tester, find.text('كسر'));
    await _tap(tester, find.text('إدراج'));
    expect(find.byTooltip('إلغاء الإدراج'), findsOneWidget);
    await _tap(tester, find.byTooltip('إلغاء الإدراج'));
    expect(find.byTooltip('إلغاء الإدراج'), findsNothing);
    expect(controller.questions.first.attachments, isEmpty);
    expect(controller.questions.first.branches.single.attachments, isEmpty);
  });

  testWidgets('image picker failure is reported, not treated as cancellation', (tester) async {
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    ImagePickerPlatform.instance = _TestImagePicker(fail: true);
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _tool('إدراج صورة'));
    expect(find.textContaining('تعذر فتح الصورة'), findsOneWidget);
    expect(controller.document.floatingElements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image insert, media insert, replace and cancellation use the picker result', (tester) async {
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    ImagePickerPlatform.instance = _TestImagePicker(file: XFile.fromData(bytes, mimeType: 'image/png'));
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _tool('إدراج صورة'));
    expect(controller.document.floatingElements.single.bytes, bytes);
    final original = controller.document.floatingElements.single;
    await _tap(tester, find.byTooltip('استبدال الصورة'));
    final replaced = controller.document.floatingElements.single;
    expect(replaced.id, original.id);
    expect(replaced.dx, original.dx);
    expect(replaced.dy, original.dy);
    expect(replaced.width, original.width);
    expect(replaced.height, original.height);
    await _tap(tester, find.text('وسائط'));
    await _tap(tester, find.descendant(of: find.byType(SmartExamToolbar), matching: find.text('صورة')));
    expect(controller.document.floatingElements, hasLength(2));
    ImagePickerPlatform.instance = _TestImagePicker();
    await _tap(tester, _tool('إدراج صورة'));
    expect(controller.document.floatingElements, hasLength(2));
    expect(find.textContaining('تعذر فتح الصورة'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
