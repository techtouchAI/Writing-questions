// بوابة **امتداد السؤال عبر الصفحات** على مستوى الخطة (بلا ودجات).
//
// لماذا بوابة مستقلة؟ لأن الخطة السابقة كانت تعرف *بداية* السؤال فقط، وتكملته
// معلنةً بمعرّف بلا هندسة؛ فكان السطح التفاعلي يرسم السؤال كاملاً في صفحة
// بدايته ويقصّه عند حدّ الصفحة، بينما يطبعه PDF كاملاً على صفحاته (§19.6 كان
// يعلن هذا الفرق قيداً مقبولاً). صار النموذج يحمل لكل مقطع: إزاحته داخل الكتلة
// الكاملة وارتفاعه وأسطرَه، فتُرسم النافذة نفسها في السطح وفي PDF.
//
// المقيس هنا من `LayoutDocument` وحده (لا قياس نصّ ثانٍ ولا ودجات):
//   1. السؤال الطويل يُقطَّع فعلاً، وعدد مقاطعه = عدد الصفحات التي يغطيها.
//   2. المقاطع تتجاور بلا فجوة ولا تراكب: إزاحة كل مقطع = مجموع ارتفاعات ما
//      قبله، وأول مقطع يبدأ من صفر (نافذة كاملة من أعلى الكتلة).
//   3. لا فقدان ولا تكرار في المحتوى: كل سطر من أسطر السؤال يظهر في مقطع واحد
//      فقط، ومجموع الأسطر = كل أسطر السؤال.
//   4. كل مقطع يقع داخل متن صفحته (أعلى/أسفل) — لا قصّ ولا تجاوز للهوامش.
//   5. إسقاط PDF (`questionPageAssignments`) يطابق صفحات المقاطع نفسها.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

/// فقرة طويلة: تكفي أسطرها لتجاوز متن صفحة كاملة.
String _paragraph(String marker, {int repeats = 4}) => List<String>.generate(
      repeats,
      (index) =>
          'فقرة $marker رقم $index تقيس امتداد السؤال عبر الصفحات في المعاينة '
          'وتصدير PDF، وتحمل كلمات متعددة وأرقاماً ٢٠ و2026 وفواصل، حتى يبلغ '
          'النصّ حدّ الصفحة ويقرّر المحرك موضع الفصل بين الأسطر.',
    ).join(' ');

ExamDocument _document({bool ltr = false}) => ExamDocument(
      name: ltr ? 'Question fragments — LTR' : 'مقاطع السؤال — عربية',
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
        QuestionModel(
          id: 'fq1',
          questionNumber: 1,
          statement: ltr ? 'First question' : 'السؤال الأول',
          body: _paragraph(ltr ? 'LTR-A' : 'أ', repeats: 3),
          bodyAlign: PaperAlign.justify,
        ),
        // سؤال أطول من متن صفحة: يمتدّ وجوباً على أكثر من صفحة.
        QuestionModel(
          id: 'fq2',
          questionNumber: 2,
          statement: ltr ? 'Second question' : 'السؤال الثاني',
          body: '${_paragraph(ltr ? 'LTR-B' : 'ب', repeats: 46)} ZEND2',
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'fq3',
          questionNumber: 3,
          statement: ltr ? 'Third question' : 'السؤال الثالث',
          body: _paragraph(ltr ? 'LTR-C' : 'ج', repeats: 3),
          bodyAlign: PaperAlign.justify,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  Future<CanonicalPagePlan> planFor(ExamDocument document) async {
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    final layout = await CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    );
    return CanonicalPagePlan.fromLayout(layout);
  }

  void expectFragmentsTileTheirQuestion(
    CanonicalPagePlan plan,
    String questionId,
  ) {
    final fragments = plan.fragmentsOfQuestion(questionId);
    expect(fragments.length, greaterThan(1),
        reason: 'السؤال $questionId لم يُقطَّع: القياس بلا عيّنة.');
    // (1) الترتيب والفهرس.
    for (var index = 0; index < fragments.length; index++) {
      expect(fragments[index].fragmentIndex, index,
          reason: 'فهرس المقطع ${fragments[index].fragmentIndex} لا يطابق '
              'ترتيبه $index في $questionId.');
      expect(fragments[index].fragmentCount, fragments.length,
          reason: 'عدد مقاطع السؤال غير متسق في $questionId.');
    }
    // (2) التجاور: أول مقطع نافذة من أعلى الكتلة، وكل مقطع يبدأ حيث انتهى
    // سابقه (بلا فجوة ولا تراكب).
    expect(fragments.first.sourceTopPt, closeTo(0, 0.01),
        reason: 'أول مقطع لا يبدأ من أعلى الكتلة: '
            '${fragments.first.sourceTopPt}');
    for (var index = 1; index < fragments.length; index++) {
      final previous = fragments[index - 1];
      final current = fragments[index];
      expect(
        current.sourceTopPt,
        closeTo(previous.sourceTopPt + previous.heightPt, 0.5),
        reason: 'فجوة/تراكب بين المقطعين ${index - 1} و$index في '
            '$questionId: ${previous.sourceTopPt}+${previous.heightPt} مقابل '
            '${current.sourceTopPt}',
      );
      expect(current.continuesFromPrevious, isTrue,
          reason: 'مقطع لاحق لا يُعلن أنه تكملة في $questionId.');
      expect(previous.continuesOnNext, isTrue,
          reason: 'مقطع سابق لا يُعلن أن للسؤال تكملة في $questionId.');
    }
    expect(fragments.last.continuesOnNext, isFalse,
        reason: 'المقطع الأخير يقول إن للسؤال تكملة في $questionId.');
    // (3) لا فقدان ولا تكرار: أسطر السؤال موزّعة مرة واحدة بالضبط.
    final seen = <String>[];
    for (final fragment in fragments) {
      expect(fragment.lineIds, isNotEmpty,
          reason: 'مقطع بلا أسطر في $questionId (صفحة فارغة).');
      for (final lineId in fragment.lineIds) {
        expect(seen.contains(lineId), isFalse,
            reason: 'سطر $lineId مكرَّر بين مقاطع $questionId.');
        seen.add(lineId);
      }
    }
    final total = plan.layout.pages
        .expand((page) => page.blocks)
        .where((block) =>
            block.semanticNodeId == questionId &&
            block.kind == LayoutBlockKind.question)
        .expand((block) => block.allLines)
        .map((line) => line.id)
        .toSet();
    expect(seen.toSet(), total,
        reason: 'أسطر السؤال في المقاطع لا تساوي أسطره في المستند: '
            '${seen.length} مقابل ${total.length}');
    // (4) داخل المتن: لا مقطع يتجاوز أعلى/أسفل متن صفحته.
    for (final fragment in fragments) {
      final page = plan.pages[fragment.pageIndex];
      final bodyBottom = page.bodyBounds.top + page.bodyBounds.height;
      expect(fragment.topPt, greaterThanOrEqualTo(page.bodyBounds.top - 0.5),
          reason: 'المقطع ${fragment.fragmentIndex} يبدأ فوق متن صفحته '
              '${fragment.pageIndex}.');
      expect(fragment.topPt + fragment.heightPt, lessThanOrEqualTo(bodyBottom + 1),
          reason: 'المقطع ${fragment.fragmentIndex} يتجاوز أسفل متن صفحته '
              '${fragment.pageIndex}: '
              '${fragment.topPt + fragment.heightPt} > $bodyBottom');
    }
    // (5) إسقاط PDF يطابق صفحات المقاطع.
    final assignments = plan.questionAssignments;
    final pagesOfFragments = fragments.map((fragment) => fragment.pageIndex).toList();
    final pagesOfPdf = <int>[
      for (var index = 0; index < assignments.length; index++)
        if (assignments[index].contains(questionId)) index,
    ];
    expect(pagesOfPdf, pagesOfFragments,
        reason: 'صفحات السؤال في PDF لا تطابق صفحات مقاطعه في الخطة.');
  }

  test('سؤال أطول من صفحة: المقاطع تتجاور بلا فجوة وتغطي كل الأسطر (عربي)', () async {
    final plan = await planFor(_document());
    expect(plan.hasContinuations, isTrue,
        reason: 'المستند لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');
    expect(plan.firstContinuedQuestionId, 'fq2');
    expectFragmentsTileTheirQuestion(plan, 'fq2');
  });

  test('السؤال نفسه في مستند LTR: نفس العقد (ترتيب، تجاور، تغطية)', () async {
    final plan = await planFor(_document(ltr: true));
    expect(plan.hasContinuations, isTrue,
        reason: 'مستند LTR لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');
    expectFragmentsTileTheirQuestion(plan, 'fq2');
  });

  test('لا صفحة فارغة: كل صفحة تحمل مقطعاً واحداً على الأقل', () async {
    final plan = await planFor(_document());
    for (final page in plan.pages) {
      expect(page.fragments, isNotEmpty,
          reason: 'الصفحة ${page.index} بلا أي مقطع — صفحة فارغة في الورقة.');
      expect(page.usedHeightPt, greaterThan(0),
          reason: 'الصفحة ${page.index} بلا ارتفاع مستهلك.');
    }
  });

  test('الأسئلة غير الممتدّة تبقى مقطعاً واحداً من أعلى الكتلة', () async {
    final plan = await planFor(_document());
    for (final id in <String>['fq1', 'fq3']) {
      final fragments = plan.fragmentsOfQuestion(id);
      expect(fragments.length, 1, reason: 'السؤال $id قُطِّع بلا حاجة.');
      expect(fragments.single.isSplit, isFalse);
      expect(fragments.single.sourceTopPt, 0);
    }
  });
}
