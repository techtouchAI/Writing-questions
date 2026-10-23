// بوابة **السؤال الممتدّ على سطح المعاينة الإنتاجي** (ودجات، لا رسام قانوني).
//
// هذه هي البوابة التي كانت تغيب: كانت الخطة تعلن أن للسؤال تكملة، والسطح يرسم
// السؤال كاملاً في صفحة بدايته ويقصّه عند حدّ الصفحة، فيرى المدرس محتوىً ناقصاً
// عمّا يطبعه PDF، ويُعلن ذلك «قيد عرض» (§19.6). الآن صار السطح يرسم **نافذة
// المقطع** من الخطة نفسها: ارتفاعها وإزاحتها من الخطة، والكتلة المبنية هي
// الكتلة نفسها بمتحكماتها (مصدر نصّي واحد، لا محرّر ثانٍ).
//
// المقيس هنا:
//   1. لكل مقطع في الخطة ودجت مقطع مرسوم على صفحته، بارتفاع المقطع نفسه.
//   2. إزاحة الرسم داخل المقطع تساوي `sourceTopPt` من الخطة (لا حساب ثانٍ).
//   3. نصّ نهاية السؤال (علامة مرسومة) يقع هندسياً داخل صفحة تكملته، ولا يقع
//      داخل صفحة البداية (لا تكرار مرئي، لا محتوى مفقود).
//   4. التحرير من مقطع التكملة يغيّر المصدر الواحد نفسه، فيتغيّر عرض مقطع
//      البداية معه، ويبقى المؤشر صالحاً (لا محرّران يتنازعان الحالة).
//   5. PDF الناتج من المستند نفسه يضع العلامة في صفحة التكملة نفسها التي
//      حدّدتها الخطة، ولا صفحة فارغة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../../pdf_engine/pdf_content_probe.dart';

/// علامة نهاية السؤال: كلمة لاتينية حتى تُقرأ في نصّ PDF كما هي.
const String kEndMarker = 'ZEND2';

const String _marker = kEndMarker;

String _paragraph(String tag, {int repeats = 4}) => List<String>.generate(
      repeats,
      (index) =>
          'فقرة $tag رقم $index تقيس امتداد السؤال عبر الصفحات في سطح المعاينة '
          'وتصدير PDF، وتحمل كلمات متعددة وأرقاماً ٢٠ و2026 وفواصل، حتى يبلغ '
          'النصّ حدّ الصفحة ويقرّر المحرك موضع الفصل بين الأسطر.',
    ).join(' ');

ExamDocument _document() => ExamDocument(
      name: 'امتداد السؤال على سطح المعاينة',
      header: ExamHeaderModel.initial(
        subject: 'الرياضيات',
        schoolName: 'ثانوية النهوض',
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
          statement: 'السؤال الأول',
          body: _paragraph('أ', repeats: 3),
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'fq2',
          questionNumber: 2,
          statement: 'السؤال الثاني',
          body: '${_paragraph('ب', repeats: 16)} $_marker',
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'fq3',
          questionNumber: 3,
          statement: 'السؤال الثالث',
          body: _paragraph('ج', repeats: 3),
          bodyAlign: PaperAlign.justify,
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

Finder _sliceKeyFor(CanonicalPagePlanFragment fragment) => find.byKey(
      ValueKey<String>(
        'page-slice-${fragment.questionId}'
        '${fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : ''}',
      ),
    );

/// مستطيل [marker] كما هو مرسوم فعلاً داخل حقل (إحداثيات عالمية).
Rect _markerRect(
  WidgetTester tester,
  Finder fieldFinder,
  String marker,
) {
  final editableFinder =
      find.descendant(of: fieldFinder, matching: find.byType(EditableText));
  final editable = tester.state<EditableTextState>(editableFinder).renderEditable;
  final TextSpan? span = editable.text as TextSpan?;
  final text = span?.toPlainText() ?? '';
  final index = text.indexOf(marker);
  expect(index, isNonNegative,
      reason: 'العلامة "$marker" غير موجودة في نصّ الحقل: ${text.length} حرفاً.');
  final boxes = editable.getBoxesForSelection(
    TextSelection(baseOffset: index, extentOffset: index + marker.length),
  );
  expect(boxes, isNotEmpty, reason: 'لا صناديق رسم للعلامة "$marker".');
  final origin = tester.getTopLeft(editableFinder);
  final box = boxes.first;
  return Rect.fromLTWH(
    origin.dx + box.left,
    origin.dy + box.top,
    box.right - box.left,
    box.bottom - box.top,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  testWidgets('سطح المعاينة يرسم تكملة السؤال على صفحتها بهندسة الخطة',
      (tester) async {
    final document = _document();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);

    expect(plan.hasContinuations, isTrue,
        reason: 'المستند لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');
    final fragments = plan.fragmentsOfQuestion('fq2');
    expect(fragments.length, greaterThan(1));

    for (final fragment in fragments) {
      final slice = _sliceKeyFor(fragment);
      expect(slice, findsOneWidget,
          reason: 'مقطع السؤال ${fragment.fragmentIndex} على الصفحة '
              '${fragment.pageIndex} غير مرسوم على السطح.');
      final size = tester.getSize(slice);
      expect(
        size.height,
        closeTo(LayoutUnits.ptToPx(fragment.heightPt), 1.0),
        reason: 'ارتفاع مقطع ${fragment.fragmentIndex} على السطح ${size.height} '
            'مقابل ${LayoutUnits.ptToPx(fragment.heightPt)} من الخطة.',
      );
      if (fragment.isContinuation) {
        final transformFinder = find.byKey(
          ValueKey<String>(
            'page-slice-offset-${fragment.questionId}'
            '/slice${fragment.fragmentIndex}',
          ),
        );
        expect(transformFinder, findsOneWidget);
        final transform = tester.widget<Transform>(transformFinder);
        expect(
          transform.transform.getTranslation().y,
          closeTo(-LayoutUnits.ptToPx(fragment.sourceTopPt), 0.75),
          reason: 'إزاحة التكملة على السطح لا تساوي إزاحتها داخل الكتلة في '
              'الخطة (${fragment.sourceTopPt}pt).',
        );
      }
    }

    // العلامة تقع داخل صفحة التكملة (آخر مقطع).
    final last = fragments.last;
    final continuationField = find.byKey(
      ValueKey<String>('body-fq2/slice${last.fragmentIndex}'),
    );
    expect(continuationField, findsOneWidget,
        reason: 'حقل التكملة غير موجود: لا يُحرَّر امتداد السؤال.');
    final pageRect = tester.getRect(
      find.byKey(ValueKey<String>('a4-page-${last.pageIndex}')),
    );
    final lastPage = plan.pages[last.pageIndex];
    final bodyTop =
        pageRect.top + LayoutUnits.ptToPx(lastPage.bodyBounds.top);
    final bodyBottom = pageRect.top +
        LayoutUnits.ptToPx(lastPage.bodyBounds.top + lastPage.bodyBounds.height);
    final continuationMarker =
        _markerRect(tester, continuationField, _marker);
    expect(continuationMarker.top, greaterThanOrEqualTo(bodyTop - 1),
        reason: 'نهاية السؤال فوق متن صفحة التكملة: ${continuationMarker.top} '
            '< $bodyTop');
    expect(continuationMarker.bottom, lessThanOrEqualTo(bodyBottom + 2),
        reason: 'نهاية السؤال تحت متن صفحة التكملة: '
            '${continuationMarker.bottom} > $bodyBottom');

    // ولا تظهر العلامة في صفحة البداية: موضعها هناك خارج نافذة المقطع.
    final startField = find.byKey(const ValueKey<String>('body-fq2'));
    expect(startField, findsOneWidget);
    final startSlice = _sliceKeyFor(fragments.first);
    final startSliceRect = tester.getRect(startSlice);
    final startMarker = _markerRect(tester, startField, _marker);
    expect(startMarker.top, greaterThan(startSliceRect.bottom),
        reason: 'العلامة تُرسم داخل نافذة صفحة البداية — تكرار مرئي: '
            '${startMarker.top} <= ${startSliceRect.bottom}');

    // لا فقدان ولا تكرار: عدد المقاطع المرسومة = عدد مقاطع الخطة.
    final shown = <int>[
      for (final fragment in fragments)
        if (_sliceKeyFor(fragment).evaluate().isNotEmpty) fragment.fragmentIndex,
    ];
    expect(shown, fragments.map((fragment) => fragment.fragmentIndex).toList());
  });

  testWidgets('التحرير من مقطع التكملة يغيّر المصدر الواحد ويظهر في مقطع البداية',
      (tester) async {
    final document = _document();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final last = plan.fragmentsOfQuestion('fq2').last;

    final continuationField = find.descendant(
      of: find.byKey(ValueKey<String>('body-fq2/slice${last.fragmentIndex}')),
      matching: find.byType(TextField),
    );
    final startField = find.descendant(
      of: find.byKey(const ValueKey<String>('body-fq2')),
      matching: find.byType(TextField),
    );
    expect(continuationField, findsOneWidget);
    expect(startField, findsOneWidget);
    final startController =
        tester.widget<TextField>(startField).controller!;
    final continuationController =
        tester.widget<TextField>(continuationField).controller!;
    expect(identical(startController, continuationController), isTrue,
        reason: 'مقطع التكملة لا يشترك في المتحكم نفسه: مصدران للنصّ.');

    const edit = '$_marker-EDIT9';
    await tester.enterText(continuationField, edit);
    await tester.pumpAndSettle();

    expect(startController.text, edit,
        reason: 'التحرير من التكملة لم يصل إلى المصدر الواحد.');
    expect(startController.selection.isValid, isTrue,
        reason: 'المؤشر/Tحديد غير صالح بعد التحرير من مقطع التكملة.');
    // الحقل في مقطع البداية يعرض النصّ نفسه (عرض متزامن، لا نسخة نصّ).
    final startEditable = tester
        .state<EditableTextState>(
          find.descendant(of: startField, matching: find.byType(EditableText)),
        )
        .renderEditable;
    expect((startEditable.text as TextSpan?)?.toPlainText(), edit);

    // النموذج نفسه تغيّر (لا حالة عرض موازية).
    expect(controller.document.questions[1].body, contains('EDIT9'));
  });

  testWidgets('PDF يضع نهاية السؤال في صفحة تكملته نفسها (عينة حقيقية)',
      (tester) async {
    final document = _document();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final last = plan.fragmentsOfQuestion('fq2').last;

    final bytes = (await tester.runAsync(() async {
      final fonts = await ExamFonts.load();
      return PaginatedPdfExamEngine().generate(
        document: controller.document,
        fonts: fonts,
      );
    }))!;

    expect(PdfContentProbe.pageCountOf(bytes), plan.pageCount,
        reason: 'عدد صفحات PDF لا يساوي عدد صفحات الخطة.');

    final pagesWithMarker = <int>[];
    for (var index = 0; index < plan.pageCount; index++) {
      final probe = PdfContentProbe.fromBytes(bytes, pageIndex: index);
      expect(probe.words, isNotEmpty,
          reason: 'صفحة $index في PDF بلا كلمات — صفحة فارغة.');
      if (probe.words.any((word) => word.text.contains('ZEND2'))) {
        pagesWithMarker.add(index);
      }
    }
    expect(pagesWithMarker, <int>[last.pageIndex],
        reason: 'علامة نهاية السؤال ظهرت في صفحات $pagesWithMarker مقابل '
            'صفحة التكملة ${last.pageIndex} في الخطة.');
  });
}
