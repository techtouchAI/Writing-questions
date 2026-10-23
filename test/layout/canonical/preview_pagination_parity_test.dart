// بوابة خطة الصفحات: هل يعرض سطح المعاينة الإنتاجي **توزيع الصفحات نفسه**
// الذي يرسمه PDF؟
//
// لماذا بوابة مستقلة؟ لأن كل بوابات التكافؤ القائمة (P0، canonical_layout_pdf_
// parity، preview_field_geometry) تمرّر `canonicalLayoutResolver` فتُقيس السطح
// القانوني المحقون. أما السطح الذي يستعمله المدرس فعلياً فيُبنى من
// `controller.pagination` (محرك تقسيم قديم على ارتفاعات ودجات مقاسة).
// فإذا اختلف المحركان فالمستخدم يرى صفحاتٍ غير التي تُطبع — ولا شيء يقيس ذلك.
//
// المقيس هنا (على الشجرة الفعلية، لا على دوال مساعدة):
//   * عدد صفحات المعاينة مقابل عدد صفحات `LayoutDocument`.
//   * الأسئلة التي **تبدأ** في كل صفحة وترتيبها (نفس إسقاط `CanonicalPagePlan`
//     الذي يقرأه السطح) — لا تُقارن نسخة PDF التي تكرّر سؤال التكملة.
//   * عدم تكرار سؤال في صفحتين، وعدم فقدان أي سؤال.
//   * عقد المحرك: خطة مُسلَّمة تُحترم أو يُرفَض التسليم صراحةً — لا إعادة تقسيم
//     صامتة (وهي الثغرة التي تسمح لمحركين باتخاذ القرار نفسه).
//
// بعد §19.9 لم يبقَ قيد §19.6: السؤال الممتدّ يُرسم على السطح في **مقاطعه**
// (نافذة على صفحة البداية ونافذة على صفحة التكملة)، وكلٌّ بهندسة الخطة. لذلك
// تضاف هنا بوابة توزيع كامل: لكل صفحة، المقاطع المرسومة = مقاطع الخطة بالضبط
// (لا بدايات فقط، ولا تكملة مفقودة).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// فقرة عربية طويلة: تكفي وحدها لأسطر متعددة، وتُكرَّر لملء صفحة.
String _paragraph(String marker, {int repeats = 4}) => List<String>.generate(
      repeats,
      (index) =>
          'فقرة $marker رقم $index تقيس انتقال الأسئلة بين الصفحات في المحرر '
          'والمعاينة وتصدير PDF، وتشمل كلمات متعددة وأرقاماً ٢٠ و2026 '
          'وفواصل، حتى يبلغ النصّ حدّ الصفحة ويقرّر المحرك موضع الفصل.',
    ).join(' ');

/// مستند متعدد الصفحات: قصير ثم طويل جداً (يمتدّ) ثم متوسطات.
/// لا صور ولا عناصر عائمة كي يقيس الاختبار خطة الصفحات وحدها.
ExamDocument _document({bool ltr = false, int questions = 7}) => ExamDocument(
      name: ltr ? 'Pagination plan — LTR' : 'خطة الصفحات — عربية',
      header: ExamHeaderModel.initial(
        subject: ltr ? 'Mathematics' : 'الرياضيات',
        schoolName: ltr ? 'Al-Nahda School' : 'ثانوية النهوض',
      ),
      settings: const PaperSettings(
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        for (var index = 0; index < questions; index++)
          QuestionModel(
            id: 'pq${index + 1}',
            questionNumber: index + 1,
            statement: ltr
                ? 'Question ${index + 1} statement'
                : 'منطوق السؤال ${index + 1}',
            body: _paragraph(
              ltr ? 'LTR Q${index + 1}' : 'Q${index + 1}',
              // السؤال الرابع يمتدّ على أكثر من صفحة: يفرض سياسة الفصل.
              repeats: index == 3 ? 14 : 4,
            ),
            bodyAlign: PaperAlign.justify,
          ),
      ],
    );

/// خطة المعاينة كما تُرسم فعلاً: لكل صفحة، معرّفات كتل الأسئلة بداخلها بالترتيب.
List<List<String>> _renderedPlan(
  WidgetTester tester,
  List<QuestionModel> questions,
) {
  final plan = <List<String>>[];
  for (var pageIndex = 0; pageIndex < 40; pageIndex++) {
    final canvas = find.byKey(ValueKey<String>('a4-page-$pageIndex'));
    if (canvas.evaluate().isEmpty) break;
    final ids = <String>[
      for (final question in questions)
        if (find
            .descendant(
              of: canvas,
              matching:
                  find.byKey(ValueKey<String>('question-block-${question.id}')),
            )
            .evaluate()
            .isNotEmpty)
          question.id,
    ];
    plan.add(ids);
  }
  return plan;
}

/// المقاطع المرسومة فعلاً على كل صفحة: بداية كل سؤال أو تكملته.
///
/// مفتاح مقطع البداية هو `question-block-<id>`، ومفتاح التكملة
/// `question-block-<id>/sliceN` (مفاتيح مميّزة كي لا تتشابه الحقول المشتركة في
/// المتحكم). تُقرأ الشجرة المرسومة لا دوال مساعدة.
List<List<String>> _renderedFragments(
  WidgetTester tester,
  List<QuestionModel> questions,
  int pages,
) {
  final rendered = <List<String>>[];
  for (var pageIndex = 0; pageIndex < pages; pageIndex++) {
    final canvas = find.byKey(ValueKey<String>('a4-page-$pageIndex'));
    if (canvas.evaluate().isEmpty) {
      rendered.add(const <String>[]);
      continue;
    }
    final ids = <String>[];
    for (final question in questions) {
      final starts = find.descendant(
        of: canvas,
        matching: find.byKey(ValueKey<String>('question-block-${question.id}')),
      );
      if (starts.evaluate().isNotEmpty) ids.add('${question.id}#0');
      for (var fragment = 1; fragment < 40; fragment++) {
        final continuation = find.descendant(
          of: canvas,
          matching: find.byKey(
            ValueKey<String>('question-block-${question.id}/slice$fragment'),
          ),
        );
        if (continuation.evaluate().isEmpty) break;
        ids.add('${question.id}#$fragment');
      }
    }
    rendered.add(ids);
  }
  return rendered;
}

String _describe(List<List<String>> plan) =>
    '<${plan.length} صفحة: ${plan.map((page) => page.join(',')).join(' | ')}>';

Future<ExamWizardController> _pumpPreview(
  WidgetTester tester,
  ExamDocument document,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  testWidgets('المعاينة الإنتاجية تعرض خطة الصفحات القانونية نفسها (عربي RTL)',
      (tester) async {
    final document = _document();
    final controller = await _pumpPreview(tester, document);
    final canonical = await CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    );
    // إسقاط الخطة نفسه الذي يقرأه السطح: أسئلة **البداية** لكل صفحة.
    final canonicalPlan = CanonicalPagePlan.fromLayout(canonical).pages
        .map((page) => page.questionIds)
        .toList();
    final previewPlan = _renderedPlan(tester, controller.questions);

    expect(canonical.pageCount, greaterThan(1),
        reason: 'التركيبة بصفحة واحدة: القياس بلا عيّنة.');

    // (1) عدد الصفحات.
    expect(
      previewPlan.length,
      canonicalPlan.length,
      reason: 'عدد صفحات المعاينة ${previewPlan.length} مقابل ${canonicalPlan.length} '
          'في التخطيط الذي يطبعه PDF.\n'
          'معاينة=${_describe(previewPlan)}\nقانوني=${_describe(canonicalPlan)}',
    );

    // (2) توزيع الأسئلة وترتيبها.
    expect(
      previewPlan,
      canonicalPlan,
      reason: 'توزيع الأسئلة على الصفحات مختلف بين المعاينة والـPDF.\n'
          'معاينة=${_describe(previewPlan)}\nقانوني=${_describe(canonicalPlan)}',
    );

    // (3) لا فقدان ولا تكرار.
    final flattened = previewPlan.expand((page) => page).toList();
    expect(flattened.toSet().length, flattened.length,
        reason: 'سؤال مكرَّر في المعاينة: $flattened');
    expect(flattened.toSet(), controller.questions.map((q) => q.id).toSet(),
        reason: 'أسئلة مفقودة من المعاينة: $flattened');
  });

  testWidgets('المعاينة الإنتاجية تعرض خطة الصفحات القانونية نفسها (إنجليزي LTR)',
      (tester) async {
    final document = _document(ltr: true);
    final controller = await _pumpPreview(tester, document);
    final canonical = await CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    );
    final canonicalPlan = CanonicalPagePlan.fromLayout(canonical).pages
        .map((page) => page.questionIds)
        .toList();
    final previewPlan = _renderedPlan(tester, controller.questions);

    expect(canonical.pageCount, greaterThan(1),
        reason: 'التركيبة LTR بصفحة واحدة: القياس بلا عيّنة.');
    expect(
      previewPlan,
      canonicalPlan,
      reason: 'توزيع الصفحات (LTR) مختلف بين المعاينة والـPDF.\n'
          'معاينة=${_describe(previewPlan)}\nقانوني=${_describe(canonicalPlan)}',
    );
  });

  test('المحرك يحترم الخطة المُسلَّمة حرفياً، ويرفض الخطة التي لا تتسع بدل '
      'إعادة التقسيم صامتاً', () {
    final document = _document();
    final ir = DocumentIR.fromBlueprint(
      blueprint: ExamBlueprint.from(document),
      document: document,
    );
    final configuration = ExamDocumentLayoutAdapter.configurationFor(document);
    const engine = LayoutEngine();
    final selfPlanned = engine.layout(
      document: ir,
      configuration: configuration,
      fontMetrics: const FlutterTextMetrics(),
    );
    expect(selfPlanned.pageCount, greaterThan(1),
        reason: 'التركيبة بصفحة واحدة: القياس بلا عيّنة.');

    // (1) خطة المحرك نفسه، مُسلَّمة إليه: تُحترم ولا تُعاد صياغتها.
    final plan = selfPlanned.questionPageAssignments;
    final honored = engine.layout(
      document: ir,
      configuration: configuration,
      fontMetrics: const FlutterTextMetrics(),
      questionPageAssignments: plan,
    );
    // الخطة تُطبَّق: نفس عدد الصفحات ونفس أسئلة البداية ونفس التكملات.
    expect(honored.questionPageAssignments, plan,
        reason: 'المحرك أعاد تقسيم خطة صحيحة مُسلَّمة إليه: '
            '${_describe(selfPlanned.questionPageAssignments)} ← '
            '${_describe(honored.questionPageAssignments)}');

    // (2) خطة لا تتسع (سؤال زائد على الصفحة الأولى): يجب رفضها صراحةً، لا
    // إعادة تقسيم صامتة تُخفي أن الخطة المُسلَّمة لم تُطبَّق.
    final overflowing = <List<String>>[
      <String>[...plan[0], ...plan[1]],
      ...plan.skip(2),
    ];
    expect(
      () => engine.layout(
        document: ir,
        configuration: configuration,
        fontMetrics: const FlutterTextMetrics(),
        questionPageAssignments: overflowing,
      ),
      throwsA(isA<ArgumentError>()),
      reason: 'المحرك قبل خطة تتجاوز سعة الصفحة وأعاد التقسيم صامتاً '
          '(الخطة المُسلَّمة: ${_describe(overflowing)}).',
    );
  });

  testWidgets('كل مقطع في الخطة مرسوم على صفحته — بما فيه تكملة السؤال الممتدّ',
      (tester) async {
    final document = _document();
    final controller = await _pumpPreview(tester, document);
    final plan = CanonicalPagePlan.fromLayout(
      await CanonicalLayoutService.resolve(
        document: controller.document,
        sourceIr: controller.documentIr,
      ),
    );

    expect(plan.hasContinuations, isTrue,
        reason: 'المستند المرجعي لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');

    final expected = <List<String>>[
      for (final page in plan.pages)
        <String>[for (final fragment in page.fragments) '${fragment.questionId}#${fragment.fragmentIndex}'],
    ];
    final rendered = _renderedFragments(tester, controller.questions, plan.pageCount);

    expect(rendered, expected,
        reason: 'المقاطع المرسومة على السطح لا تطابق مقاطع الخطة '
            '(بدايات وتكملات).\nمرسوم=${_describe(rendered)}\n'
            'خطة=${_describe(expected)}');

    // ولا مقطع مرسوم على صفحة لا تخصّه.
    for (final page in plan.pages) {
      for (final fragment in page.fragments) {
        expect(fragment.pageIndex, page.index,
            reason: 'مقطع ${fragment.questionId}#${fragment.fragmentIndex} '
                'منسوب لصفحتين.');
        expect(fragment.heightPt, greaterThan(0),
            reason: 'مقطع بلا ارتفاع في الصفحة ${page.index}.');
      }
    }
  });
}
