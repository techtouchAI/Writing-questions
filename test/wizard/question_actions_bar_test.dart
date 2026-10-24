// أدوات السؤال على الهاتف: **فصل هندسة الورق عن واجهة التحكم** (§19.15).
//
// الحالة قبل هذا التغيير (مقيسة، SHA `c7282f5`):
//   * الأزرار الثلاث داخل صفّ العنوان بعد تقييده بارتفاع الخطة: 31×31px لكل
//     زرّ — أي **أقل من 48dp** التي توصي بها Material، وتحت الحدّ الذي تفرضه
//     قابلية الاستخدام على شاشة لمس.
//   * الفجوة بين أسفل صفّ العنوان وأعلى المتن **2.00px** فقط، فلا يمكن لهدف
//     48px أن يوجد داخل الصفّ دون أن يرسم على سطر المتن.
//   * أثر ثانٍ أخطر: الأزرار تأكل من عرض المنطوق، فحقل المنطوق **391.86px**
//     مقابل امتداد **410.60px** في الخطة ⇒ **سطران في المعاينة مقابل سطر واحد
//     في الخطة/PDF**.
//
// القرار: نقل الأدوات إلى شريط في واجهة التطبيق **خارج الورقة** (لا يدخل
// `_buildQuestionBlock`)، بهدف 48dp، يعمل على سؤال واحد محدَّد. الصفّ يعود
// هندسة ورق خالصة: ارتفاعه وعرض منطقه من الخطة؛ والشريط لا يعرف عنه المحرك
// ولا PDF شيئاً.
//
// تُقاس هنا أربعة أشياء لا تُخلط: مساحة اللمس، وموقع الشريط خارج الورقة،
// وتطابق هندسة العنوان مع الخطة، وأن الأزرار تعمل على السؤال الصحيح وحده.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// الحدّ الأدنى لهدف اللمس في Material (48dp) — يُقاس على مربّع الزرّ المرسوم،
/// وهو المربّع الذي يجرى عليه اختبار اللمس فعلاً.
const double kMinTouchTarget = 48.0;

final Finder _bar = find.byKey(const ValueKey<String>('question-actions-bar'));
Finder _action(String name) =>
    find.byKey(ValueKey<String>('question-action-$name'));
Finder _statement(String id) =>
    find.byKey(ValueKey<String>('statement-$id'));
Finder _block(String id) =>
    find.byKey(ValueKey<String>('question-block-$id'));

ExamDocument _document() => ExamDocument(
      name: 'أدوات السؤال',
      header: ExamHeaderModel.initial(subject: 'الرياضيات', schoolName: 'ثانوية'),
      settings: const PaperSettings(
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'aq1',
          questionNumber: 1,
          // منطوق يفترض أن يبقى سطراً واحداً (كما في الخطة و PDF)، وكان يلتفّ
          // سطرين حين أكلت أزرار الصفّ من عرضه.
          statement: 'السؤال الأول: احسب قيمة المتغير في المعادلة التالية ثم بيّن خطوات الحل',
          body: 'متن قصير للسؤال الأول يقيس الفجوة بين العنوان والمتن.',
        ),
        QuestionModel(
          id: 'aq2',
          questionNumber: 2,
          statement: 'السؤال الثاني',
          body: 'متن قصير للسؤال الثاني.',
        ),
      ],
    );

Future<CanonicalPagePlan> _planOf(ExamDocument document) async {
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  final layout = await CanonicalLayoutService.resolve(
    document: controller.document,
    sourceIr: controller.documentIr,
  );
  return CanonicalPagePlan.fromLayout(layout);
}

LayoutBlock _blockOf(CanonicalPagePlan plan, String id) {
  for (final page in plan.layout.pages) {
    for (final block in page.blocks) {
      if (block.kind == LayoutBlockKind.question && block.semanticNodeId == id) {
        return block;
      }
    }
  }
  throw StateError('كتلة السؤال $id غير موجودة في الخطة.');
}

Future<ExamWizardController> _pump(
  WidgetTester tester,
  ExamDocument document, {
  Size size = const Size(1400, 2200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// مستند فيه فرع واحد: لقياس صفّ عنوان الفرع وأدواته.
ExamDocument _branchDocument() => ExamDocument(
      name: 'أدوات الفرع',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      settings: const PaperSettings(
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'cq1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          branches: <BranchModel>[
            BranchModel(
              content: BranchContent(
                statement: 'منطوق الفرع الأول ليقيس ارتفاع صفّه وعرض منطقه',
                items: <BranchItem>[BranchItem(id: 'ci1', text: 'نقطة')],
              ),
              marks: 2,
            ),
          ],
        ),
      ],
    );

/// كتلة الفرع داخل كتلة سؤاله (ليست كتلة عليا في الصفحة).
LayoutBlock? _branchBlockOf(CanonicalPagePlan plan, String questionId) {
  LayoutBlock? found;
  void scan(LayoutBlock block) {
    if (block.kind == LayoutBlockKind.branch) found ??= block;
    for (final child in block.children) {
      scan(child);
    }
  }

  for (final page in plan.layout.pages) {
    for (final block in page.blocks) {
      if (block.semanticNodeId == questionId) scan(block);
    }
  }
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => FlutterTextMetrics.ensureFontsLoaded());

  testWidgets('هدف اللمس: 48×48px على الأقل، والنقر يعمل', (tester) async {
    final controller = await _pump(tester, _document());
    await tester.tap(_statement('aq1'));
    await tester.pumpAndSettle();

    for (final name in <String>['add-branch', 'duplicate', 'delete']) {
      final finder = _action(name);
      expect(finder, findsOneWidget, reason: 'الزرّ $name غير موجود في الشريط.');
      final rect = tester.getRect(finder);
      expect(rect.width, greaterThanOrEqualTo(kMinTouchTarget - 0.01),
          reason: 'عرض هدف «$name» ${rect.width.toStringAsFixed(2)}px < 48dp.');
      expect(rect.height, greaterThanOrEqualTo(kMinTouchTarget - 0.01),
          reason: 'ارتفاع هدف «$name» ${rect.height.toStringAsFixed(2)}px < 48dp.');
      final button = tester.widget<IconButton>(finder);
      expect(button.onPressed, isNotNull,
          reason: 'الزرّ «$name» معطّل مع وجود سؤال واحد محدَّد.');
    }

    // النقر يُنفِّذ على السؤال المحدَّد فعلاً (لا مجرّد وجود الأزرار).
    await tester.tap(_action('add-branch'));
    await tester.pumpAndSettle();
    expect(controller.questions.first.branches, hasLength(1));
    expect(controller.questions[1].branches, isEmpty,
        reason: 'أُضيف الفرع إلى سؤال آخر.');
  });

  testWidgets('الشريط خارج الورقة: لا يحتويه أي بلوك، ولا يتقاطع مع الورق',
      (tester) async {
    await _pump(tester, _document());
    expect(_bar, findsOneWidget);
    expect(
      find.descendant(of: _block('aq1'), matching: _bar),
      findsNothing,
      reason: 'الشريط صار داخل كتلة السؤال: عاد إلى هندسة الورق.',
    );

    final barRect = tester.getRect(_bar);
    final paperTop = tester.getRect(find.byKey(const ValueKey<String>('paper-v-scroll'))).top;
    expect(barRect.bottom, lessThanOrEqualTo(paperTop + 0.5),
        reason: 'الشريط يتقاطع مع منطقة الورق '
            '(أسفله ${barRect.bottom.toStringAsFixed(2)}، الورق يبدأ '
            '${paperTop.toStringAsFixed(2)}).');
    expect(tester.getRect(_block('aq1')).bottom, greaterThan(barRect.bottom),
        reason: 'كتلة السؤال ليست أسفل الشريط: القياس بلا معنى.');
  });

  testWidgets('صفّ العنوان هندسة خطة: العرض والارتفاع وعدد الأسطر من الخطة',
      (tester) async {
    final controller = await _pump(tester, _document());
    final plan = await _planOf(controller.document);
    final block = _blockOf(plan, 'aq1');
    final title = block.children.firstWhere((c) => c.kind == LayoutBlockKind.title);
    final body = block.children.firstWhere((c) => c.kind == LayoutBlockKind.body);

    // امتداد المنطوق في الخطة: أقل x إلى أقصى x+advance على أسطره.
    final runs = <LayoutRun>[
      for (final line in block.allLines)
        ...line.runs.where((run) => run.semanticNodeId.contains('/statement')),
    ];
    expect(runs, isNotEmpty, reason: 'لا جريانات لمنطوق السؤال في الخطة.');
    final planLines = <String>{
      for (final line in block.allLines)
        if (line.runs.any((r) => r.semanticNodeId.contains('/statement'))) line.id,
    }.length;
    final planSpan = runs.map((run) => run.x + run.advance).reduce(math.max) -
        runs.map((run) => run.x).reduce(math.min);

    final statement = _statement('aq1');
    final fieldRect = tester.getRect(statement);
    final editable = tester.state<EditableTextState>(
      find.descendant(of: statement, matching: find.byType(EditableText)),
    );
    final renderedLines = editable.renderEditable
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: editable.textEditingValue.text.length,
          ),
        )
        .length;

    // المنطوق المرسوم لا يقلّ عن امتداده في الخطة: أدوات الصفّ كانت تأكل منه.
    expect(fieldRect.width, greaterThanOrEqualTo(LayoutUnits.ptToPx(planSpan) - 1.0),
        reason: 'عرض حقل المنطوق ${fieldRect.width.toStringAsFixed(2)}px أقل من '
            'امتداده في الخطة ${LayoutUnits.ptToPx(planSpan).toStringAsFixed(2)}px.');
    expect(renderedLines, planLines,
        reason: 'المنطوق يُرسم في $renderedLines سطراً مقابل $planLines في الخطة: '
            'المعاينة تخالف PDF في التفاف السطر.');

    // الارتفاع والفجوة من الخطة (لا من أطول ودجة في الصفّ).
    final rowRect = tester.getRect(
      find.ancestor(of: statement, matching: find.byType(Row)).first,
    );
    expect(rowRect.height,
        closeTo(LayoutUnits.ptToPx(title.rect.height), 0.5),
        reason: 'ارتفاع صفّ العنوان ${rowRect.height.toStringAsFixed(2)}px مقابل '
            '${LayoutUnits.ptToPx(title.rect.height).toStringAsFixed(2)}px في الخطة.');
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey<String>('body-aq1')),
    );
    expect(
      bodyRect.top - rowRect.bottom,
      closeTo(
        LayoutUnits.ptToPx(body.rect.top - title.rect.bottom),
        0.75,
      ),
      reason: 'الفجوة بين العنوان والمتن تخالف الخطة.',
    );
  });

  testWidgets('الشريط يقول على أي سؤال يعمل، ويعمل عليه وحده', (tester) async {
    final controller = await _pump(tester, _document());

    // التحرير في السؤال الثاني يحدّده: الشريط يسمّيه، والنسخ ينشئ نسخة منه
    // ويترك السؤال الأول كما هو.
    await tester.tap(_statement('aq2'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _bar,
        matching: find.textContaining('أدوات السؤال'),
      ),
      findsOneWidget,
      reason: 'الشريط لا يسمّي السؤال الذي سيعمل عليه.',
    );
    expect(tester.widget<IconButton>(_action('duplicate')).onPressed, isNotNull);
    await tester.tap(_action('duplicate'));
    await tester.pumpAndSettle();
    expect(controller.questions, hasLength(3));
    expect(controller.questions[0].statement, contains('السؤال الأول'),
        reason: 'تأثّر السؤال الأول بأداة السؤال الثاني.');
    expect(controller.questions[1].statement, contains('السؤال الثاني'));

    // تحديد متعدد ⇒ لا سؤال واحد ⇒ الأزرار معطّلة ولا يتغيّر شيء بالنقر.
    final before = controller.questions.length;
    await tester.tap(find.byTooltip('تحديد متعدد'));
    await tester.pumpAndSettle();
    await tester.tap(_statement('aq1'));
    await tester.pumpAndSettle();
    await tester.tap(_statement('aq2'));
    await tester.pumpAndSettle();
    for (final name in <String>['add-branch', 'duplicate']) {
      expect(tester.widget<IconButton>(_action(name)).onPressed, isNull,
          reason: 'الزرّ «$name» يعمل مع تحديد متعدد (قد يعمل على السؤال الخطأ).');
    }
    expect(controller.questions.length, before,
        reason: 'تغيّر عدد الأسئلة رغم تعطيل الأزرار.');
  });

  testWidgets('الشريط واحد مهما تعددت المقاطع، ويعمل على السؤال الممتد نفسه',
      (tester) async {
    // سؤال طويل يمتدّ صفحتين + سؤال ثانٍ: الشريط لا يتكرّر لكل مقطع.
    final long = List<String>.generate(
      46,
      (index) => 'فقرة تقيس امتداد السؤال عبر أكثر من صفحة في المستند المرجعي '
          'برقم $index وكلمات متعددة تكفي لبلوغ حدّ الصفحة.',
    ).join(' ');
    final controller = await _pump(
      tester,
      ExamDocument(
        name: 'امتداد',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        settings: const PaperSettings(
          baseFontSize: 11,
          lineSpacing: 1.7,
          marginMm: 15,
        ),
        questions: <QuestionModel>[
          QuestionModel(id: 'lq1', questionNumber: 1, statement: 'س', body: long),
          QuestionModel(id: 'lq2', questionNumber: 2, statement: 'ص', body: 'قصير'),
        ],
      ),
      size: const Size(1400, 6000),
    );
    final plan = await _planOf(controller.document);
    expect(plan.hasContinuations, isTrue,
        reason: 'المستند لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');

    expect(_bar, findsOneWidget,
        reason: 'الشريط تكرّر مع مقاطع السؤال الممتد (${_bar.evaluate().length}).');

    // تحرير من التكملة يحدّد السؤال الممتد نفسه، فتعمل الأداة عليه وحده.
    final continuation = plan
        .fragmentsOfQuestion('lq1')
        .firstWhere((fragment) => fragment.isContinuation);
    final bodyField = find.byKey(
      ValueKey<String>('body-lq1/slice${continuation.fragmentIndex}'),
    );
    expect(bodyField, findsOneWidget,
        reason: 'مقطع التكملة غير مبنيّ: القياس بلا عيّنة.');
    await tester.tap(bodyField);
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(_action('add-branch')).onPressed, isNotNull,
        reason: 'الأداة معطّلة بعد تحرير مقطع التكملة.');
    await tester.tap(_action('add-branch'));
    await tester.pumpAndSettle();
    expect(controller.questions.first.branches, hasLength(1),
        reason: 'لم يُضف الفرع إلى السؤال الممتد.');
    expect(controller.questions[1].branches, isEmpty,
        reason: 'تأثّر السؤال الآخر بأداة السؤال الممتد.');
    // الشريط ما زال واحداً بعد التحرير (لم يُبنَ لكل مقطع).
    expect(_bar, findsOneWidget);
  });

  testWidgets('صفّ عنوان الفرع أيضاً هندسة خطة، وأدواته خارج الورقة بـ48dp',
      (tester) async {
    final controller = await _pump(tester, _branchDocument());
    final plan = await _planOf(controller.document);
    final branchBlock = _branchBlockOf(plan, 'cq1');
    expect(branchBlock, isNotNull, reason: 'لا كتلة فرع في الخطة.');
    final title = branchBlock!.children
        .firstWhere((child) => child.kind == LayoutBlockKind.title);

    // الحقل المرسوم لمنطوق الفرع: يُطابق نصّه (لا مفاتيح مفترضة).
    final statementText =
        controller.document.questions.first.branches.first.content.statement;
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == statementText,
    );
    expect(field, findsOneWidget, reason: 'حقل منطوق الفرع غير موجود.');
    final rowRect = tester.getRect(
      find.ancestor(of: field, matching: find.byType(Row)).first,
    );
    expect(
      rowRect.height,
      closeTo(LayoutUnits.ptToPx(title.rect.height), 0.5),
      reason: 'ارتفاع صفّ الفرع ${rowRect.height.toStringAsFixed(2)}px مقابل '
          '${LayoutUnits.ptToPx(title.rect.height).toStringAsFixed(2)}px في '
          'الخطة: أدوات الصفّ تقود الورقة.',
    );
    expect(
      find.descendant(
        of: find.ancestor(of: field, matching: find.byType(Row)).first,
        matching: find.byType(IconButton),
      ),
      findsNothing,
      reason: 'بقي في صفّ الفرع زرّ يحدّد ارتفاعه.',
    );

    // أدوات الفرع في الشريط، 48dp، وتعمل على الفرع الصحيح.
    for (final name in <String>['branch-action-duplicate', 'branch-action-delete']) {
      final rect = tester.getRect(_action(name));
      expect(rect.height, greaterThanOrEqualTo(kMinTouchTarget - 0.01),
          reason: 'هدف «$name» ${rect.height.toStringAsFixed(2)}px < 48dp.');
      expect(tester.widget<IconButton>(_action(name)).onPressed, isNotNull,
          reason: 'أداة الفرع «$name» معطّلة والفرع محدَّد.');
    }
    await tester.tap(_action('branch-action-duplicate'));
    await tester.pumpAndSettle();
    expect(controller.questions.first.branches, hasLength(2),
        reason: 'لم يُنسخ الفرع.');
  });
}
