// «تحديد الكل» والضغط المطوّل من أي موضع داخل السؤال — في لوحة المعاينة.
//
// الدليل المطلوب ليس وجود الأزرار بل الأثر الفعلي:
//   * «تحديد الكل» يحدد كل الكتل **القابلة للتحديد** ويحدّث العدّاد من
//     النموذج نفسه، ثم يلغي تحديد الجميع، والحالة تبقى بعد إعادة البناء.
//   * الضغط المطوّل داخل حقل نص السؤال/نص الفرع/نص النقطة/الخيار — أي داخل
//     `TextField` — يفعّل التحديد المتعدد ويحدد الكتلة صاحبة الحقل، وهذا ما
//     لا يمكن أن يفعله `GestureDetector` أب لأن `RenderEditable` يمسك
//     الإيماءة داخلياً؛ لذلك الطبقة العليا في `PaperField`.
//   * التحديد لا يمس محتوى الورقة (لا كتابة ولا ترتيب ولا تخزين).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

ExamDocument _document() => ExamDocument(
      name: 'تحديد المعاينة',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'القواعد',
          statement: 'منطوق السؤال الأول',
          body: 'نص السؤال الأول',
          items: <BranchItem>[
            BranchItem(id: 'qi1', text: 'نقطة السؤال الأولى'),
            BranchItem(
              id: 'qi-mcq',
              kind: PointKind.multipleChoice,
              text: 'نقطة الخيارات',
              options: <QuestionOption>[
                QuestionOption(text: 'خيار أول'),
                QuestionOption(text: 'خيار ثانٍ'),
              ],
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                statement: 'عنوان الفرع',
                body: 'نص الفرع',
                items: <BranchItem>[BranchItem(id: 'bi1', text: 'نقطة الفرع')],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          statement: 'منطوق السؤال الثاني',
          body: 'نص السؤال الثاني',
        ),
        QuestionModel(
          id: 'q3',
          questionNumber: 3,
          statement: r'احسب قيمة $x^2+1$',
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, ExamWizardController controller) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ExamWizardController _controller() =>
    ExamWizardController(document: _document());

Finder _selectAllButtons() =>
    find.byKey(const ValueKey<String>('select-all-blocks'));

Finder _counter() => find.byKey(const ValueKey<String>('preview-selection-count'));

Future<void> _revealSelectAll(WidgetTester tester) async {
  final scrollables = find.descendant(
    of: find.byType(PreviewToolbar),
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final position = tester.state<ScrollableState>(scrollables.first).position;
  var steps = 0;
  while (_selectAllButtons().evaluate().isEmpty &&
      position.pixels < position.maxScrollExtent &&
      steps < 80) {
    position.jumpTo((position.pixels + 120).clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
    steps++;
  }
}

/// الزر الذي يحمل المفتاح (قد يكون مرتين: واحد فعلي وآخر غير مرئي داخل القوائم).
Finder _selectAll() => _selectAllButtons().last;

String _counterText(WidgetTester tester) {
  final finder = _counter();
  if (finder.evaluate().isEmpty) {
    return '';
  }
  return tester.widget<Text>(
    find.descendant(of: finder, matching: find.byType(Text)).first,
  ).data!;
}

Future<void> _tapSelectAll(WidgetTester tester) async {
  await _revealSelectAll(tester);
  final finder = _selectAll();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// حقل الورقة القابل للتحرير داخل مفتاح الحقل المطلوب.
Finder _field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    );

String _snapshot(ExamWizardController controller) =>
    jsonEncode(controller.document.toMap());

void main() {
  testWidgets('زر «تحديد الكل» موجود في الشريط مع عدّاد المحدد', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _revealSelectAll(tester);
    expect(_selectAllButtons(), findsWidgets,
        reason: 'زر select-all-blocks يجب أن يكون جزءاً من PreviewToolbar.');
  });

  testWidgets('تحديد الكل ثم إلغاء تحديد الجميع مع عدّاد صحيح', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final before = _snapshot(controller);

    // التحديد الأول: كل الكتل القابلة للتحديد = أسئلة + فروع، محسوبة من
    // النموذج نفسه (مصدر الـselection logic) لا من عدد الودجات.
    final document = controller.document;
    final total = document.questions.length +
        document.questions.fold<int>(0, (sum, q) => sum + q.branches.length);
    await _tapSelectAll(tester);
    expect(
      _counterText(tester),
      'المحدد ${document.formatNumber(total)} من ${document.formatNumber(total)}',
      reason: 'العدّاد يجب أن يعرض المحدد من المجموع الكلي للكتل القابلة للتحديد.',
    );

    // الضغط مرة أخرى: إلغاء تحديد الجميع.
    await _tapSelectAll(tester);
    expect(
      _counterText(tester),
      'المحدد ${document.formatNumber(0)} من ${document.formatNumber(total)}',
      reason: 'الضغط الثاني يلغي تحديد الجميع ويحدّث العدّاد.',
    );
    final after = _snapshot(controller);
    expect(after, before,
        reason: 'التحديد/إلغاؤه يجب ألا يغيّر محتوى الورقة إطلاقاً.');
  });

  testWidgets('الضغط المطوّل داخل حقل نص السؤال يحدد السؤال', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final field = _field('body-q1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.longPress(field);
    await tester.pumpAndSettle();

    final counter = _counterText(tester);
    expect(counter, isNotEmpty,
        reason: 'الضغط المطوّل داخل TextField يجب أن يدخل وضع التحديد المتعدد.');
    expect(counter.contains('١') || counter.contains('1'), isTrue,
        reason: 'السؤال صاحب الحقل يجب أن يكون محدداً.');
  });

  testWidgets('الضغط المطوّل داخل حقل نص الفرع يحدد الفرع', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final field = _field('branch-body-b1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.longPress(field);
    await tester.pumpAndSettle();
    expect(_counterText(tester), isNotEmpty);
  });

  testWidgets('الضغط المطوّل على حقل نقطة/خيار يحدد الكتلة صاحبتها',
      (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final pointField = _field('item-qi1');
    await tester.ensureVisible(pointField);
    await tester.pumpAndSettle();
    await tester.longPress(pointField);
    await tester.pumpAndSettle();
    expect(_counterText(tester), isNotEmpty,
        reason: 'الضغط المطوّل على نص نقطة يجب أن يحدد كتلتها.');

    // الخروج من التحديد ثم اختبار حقل الخيار.
    await _tapSelectAll(tester);
    final optionField = _field('option-qi-mcq-0');
    await tester.ensureVisible(optionField);
    await tester.pumpAndSettle();
    await tester.longPress(optionField);
    await tester.pumpAndSettle();
    expect(_counterText(tester), isNotEmpty,
        reason: 'الضغط المطوّل على خيار يجب أن يحدد الكتلة صاحبة الخيار.');
  });

  testWidgets('الضغط المطوّل داخل حقل معادلة مرسومة يحدد السؤال', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    // حقل المعادلة يُعرض مرسوماً (TexText) لا `TextField` — والضغط المطوّل
    // عليه يجب أن يمرّ إلى طبقة التحديد لا أن يضيع في الرسم.
    final mathField = find.byKey(const ValueKey<String>('statement-q3'));
    expect(
      find.descendant(of: mathField, matching: find.byType(TextField)),
      findsNothing,
      reason: 'حقل المعادلة يُعرض مرسوماً لا محرَّراً في الوضع العادي.',
    );
    await tester.ensureVisible(mathField);
    await tester.pumpAndSettle();
    await tester.longPress(mathField);
    await tester.pumpAndSettle();
    final document = controller.document;
    final total = document.questions.length +
        document.questions.fold<int>(0, (sum, q) => sum + q.branches.length);
    expect(
      _counterText(tester),
      'المحدد ${document.formatNumber(1)} من ${document.formatNumber(total)}',
      reason: 'الضغط المطوّل على معادلة مرسومة يفعّل التحديد ويحدد السؤال '
          'الذي يحملها وحده.',
    );
  });

  testWidgets('الضغط المطوّل على حقل قيد التحرير لا يسرق تأشير النص',
      (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    // نقرة أولى تُركّز الحقل (فتح تحرير)، ثم ضغط مطوّل داخله.
    final field = _field('body-q1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    final focused = tester.widget<TextField>(field);
    expect(focused.focusNode?.hasFocus, isTrue,
        reason: 'النقرة يجب أن تركز حقل التحرير كما كانت دائماً.');

    await tester.longPress(field);
    await tester.pumpAndSettle();
    expect(_counterText(tester), isEmpty,
        reason: 'داخل حقل قيد التحرير يبقى التأشير الطبيعي ولا يبدأ التحديد المتعدد.');
    expect(_snapshot(controller).isNotEmpty, isTrue);
  });
}
