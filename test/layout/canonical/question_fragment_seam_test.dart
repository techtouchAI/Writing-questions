// بوابة **دقة القصّ عند حدود مقاطع السؤال الممتدّ** (§19.12).
//
// السؤال الذي تجيب عنه هذه البوابة: حين يُقطع سؤال بين صفحتين، هل يظهر آخر سطر
// من المقطع الأول وأول سطر من المقطع التالي **كاملين**، أم أن هنالك قصّاً عند
// الحدّ؟ ولا يُكتفى بعدّ الأسطر أو بعدّ الحبر:
//
//   * هندسة: صناديق الأسطر التي يرسمها الحقل فعلاً (`RenderEditable`، أي هندسة
//     Skia المرسومة) تُقارن بنافذة المقطع من الخطة — احتواء كامل، وتقسيم
//     متصل غير متداخل لكل أسطر السؤال، وعدد أسطر كل مقطع = عدد أسطر الخطة.
//   * صورة: تُلتقط صفحة كل مقطع (`RepaintBoundary`) ويُقاس الحبر عند الحدّين:
//     حبر موجود في سطر الحدّ، ولا حبر في صف البكسل الأخير من النافذة (قصّ) ولا
//     في أول صف من نافذة التكملة (قصّ من الأعلى).
//   * تطابق مع PDF: مستند رموز فريدة (`W0001`…) يُثبت أن كلمة آخر سطر من
//     المقطع الأول مطبوعة في صفحته ولا تتكرّر في صفحة التكملة، وكلمة أول سطر
//     من التكملة في صفحتها ولا تتكرّر في السابقة.
//
// التفاوت وأصله: نافذة المقطع تُقاس بـ`LayoutUnits.ptToPx` (96px/in = 1.333333
// px/pt) بينما يُبنى المحتوى بأنماط `PaperMetrics` (A4 = 794px ↔ 595.2756pt =
// 1.333836 px/pt). فرق النسبة 3.7698e-4، أي 0.0005026px لكل نقطة ارتفاع.
// لذلك يُحسب الحدّ المسموح في الاختبار **من الثابتين أنفسهما** (لا رقم سحري):

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
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

/// فرق النسبة بين تحويل البكسل في المعاينة (`PaperMetrics`) وتحويله في المحرك
/// (`LayoutUnits`): 3.7698e-4. الحدّ المسموح لأي انزياح يشتقّ منه.
final double kUnitRatioError = PaperMetrics.px(1) / LayoutUnits.ptToPx(1) - 1;

/// انزياح البكسل المتوقّع مقابل نقطة ارتفاع واحدة.
final double kPxPerPtMismatch =
    PaperMetrics.px(1) - LayoutUnits.ptToPx(1);

String _arabicParagraph(String tag, {int repeats = 4}) =>
    List<String>.generate(
      repeats,
      (index) =>
          'فقرة $tag رقم $index تقيس دقة القصّ عند حدود مقاطع السؤال الممتدّ '
          'بين صفحتين، وتحمل كلمات متعددة وأرقاماً ٢٠ و2026 وفواصل، حتى يبلغ '
          'النصّ حدّ الصفحة ويقرّر المحرك موضع الفصل بين الأسطر.',
    ).join(' ');

/// مستند عربي: سؤال طويل يتجاوز متن الصفحة، وسؤالان قصيران حوله.
ExamDocument _arabicDocument() => ExamDocument(
      name: 'دقة القصّ عند حدود المقاطع',
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
          id: 'sq1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          body: _arabicParagraph('أ', repeats: 3),
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'sq2',
          questionNumber: 2,
          statement: 'السؤال الثاني',
          body: '${_arabicParagraph('ب', repeats: 46)} ZEND2',
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'sq3',
          questionNumber: 3,
          statement: 'السؤال الثالث',
          body: _arabicParagraph('ج', repeats: 3),
          bodyAlign: PaperAlign.justify,
        ),
      ],
    );

/// رموز فريدة: كل كلمة في السؤال قابلة للتتبّع بين المعاينة و PDF بلا لبس.
String _tokens({required int count}) =>
    <String>[for (var index = 1; index <= count; index++) 'W${index.toString().padLeft(4, '0')}']
        .join(' ');

ExamDocument _tokenDocument() => ExamDocument(
      name: 'Seam tokens',
      header: ExamHeaderModel.initial(
        subject: 'Mathematics',
        schoolName: 'Al-Nahda School',
      ),
      settings: const PaperSettings(
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'tq1',
          questionNumber: 1,
          statement: 'Question one',
          body: _tokens(count: 760),
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'tq2',
          questionNumber: 2,
          statement: 'Question two',
          body: 'W9999',
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
  ExamDocument document, {
  Size size = const Size(1400, 6000),
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

Finder _fieldOf(CanonicalPagePlanFragment fragment) => find.descendant(
      of: find.byKey(
        ValueKey<String>(
          'page-slice-${fragment.questionId}'
          '${fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : ''}',
        ),
      ),
      matching: find.byType(TextField),
    );

Finder _editableOf(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

RenderEditable _renderEditable(WidgetTester tester, Finder field) =>
    tester.state<EditableTextState>(_editableOf(field)).renderEditable;

typedef _LineBox = ({double left, double top, double right, double bottom});

/// صناديق الأسطر كما يرسمها الحقل: `getBoxesForSelection` على كامل النصّ يعيد
/// صندوقاً لكل محرف؛ تُدمج صناديق السطر الواحد (فرق أعلى ≤ 1px).
List<_LineBox> _lineBoxes(WidgetTester tester, Finder field) {
  final editable = _renderEditable(tester, field);
  final text = tester.widget<TextField>(field).controller!.text;
  final boxes = editable
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )
      .toList();
  final origin = tester.getTopLeft(_editableOf(field));
  final merged = <_LineBox>[];
  for (final box in boxes) {
    final left = origin.dx + box.left;
    final top = origin.dy + box.top;
    final right = origin.dx + box.right;
    final bottom = origin.dy + box.bottom;
    if (merged.isNotEmpty && (merged.last.top - top).abs() <= 1.0) {
      final previous = merged.removeLast();
      merged.add((
        left: math.min(previous.left, left),
        top: previous.top,
        right: math.max(previous.right, right),
        bottom: math.max(previous.bottom, bottom),
      ));
      continue;
    }
    merged.add((left: left, top: top, right: right, bottom: bottom));
  }
  return merged;
}

/// حدود الصفحة المرسومة كما تُلتقط صورتها (أقرب `RepaintBoundary` بحجم الورقة).
RenderRepaintBoundary _pageBoundary(
  WidgetTester tester,
  Finder pageFinder,
  Rect pageRect,
) {
  final candidates = find
      .ancestor(of: pageFinder, matching: find.byType(RepaintBoundary))
      .evaluate();
  for (final candidate in candidates) {
    final box = candidate.renderObject! as RenderBox;
    if ((box.size.width - pageRect.width).abs() <= 1 &&
        (box.size.height - pageRect.height).abs() <= 1) {
      return candidate.renderObject! as RenderRepaintBoundary;
    }
  }
  fail('لا RepaintBoundary بحجم الصفحة ${pageRect.size}: لا يمكن التقاط صورة.');
}

Rect _windowOf(WidgetTester tester, CanonicalPagePlanFragment fragment) =>
    tester.getRect(
      find.byKey(
        ValueKey<String>(
          'page-slice-${fragment.questionId}'
          '${fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : ''}',
        ),
      ),
    );

/// الحدّ المسموح لانزياح الهندسة عند مقطع بعينه، مشتقّ من مصدره لا من نتيجة
/// اليوم: (إزاحة المقطع + ارتفاعه) × فرق النسبة بين ثابتَي التحويل، زائد هامش
/// تقريب هندسة الودجات (0.5px).
double _allowedSeamDriftPx(CanonicalPagePlanFragment fragment) =>
    (fragment.sourceTopPt + fragment.heightPt) * kPxPerPtMismatch + 0.5;

/// أسطر الخطة لسؤال واحد على صفحة مقطع معيّن، بترتيبها.
List<LayoutLine> _linesOfFragment(
  CanonicalPagePlan plan,
  CanonicalPagePlanFragment fragment,
) {
  final ids = fragment.lineIds.toSet();
  return <LayoutLine>[
    for (final page in plan.layout.pages)
      if (page.index == fragment.pageIndex)
        for (final block in page.blocks)
          if (block.kind == LayoutBlockKind.question &&
              block.semanticNodeId == fragment.questionId)
            for (final line in block.allLines)
              if (ids.contains(line.id)) line,
  ];
}

typedef _EdgeWord = ({String word, int pageIndex, int fragmentIndex});

/// أول/آخر كلمة في سطر (بترتيب المصدر المنطقي).
String _edgeWord(LayoutLine line, {required bool first}) {
  final runs = line.runs.toList()
    ..sort((a, b) => a.logicalIndex.compareTo(b.logicalIndex));
  final words = <String>[
    for (final run in runs)
      for (final word in run.words)
        if (word.text.trim().isNotEmpty) word.text.trim(),
  ];
  expect(words, isNotEmpty, reason: 'سطر بلا كلمات في ${line.id}.');
  return first ? words.first : words.last;
}

/// إزاحة مؤشر حقيقية عند بداية سطر مرئي، مشتقّة من هندسة المؤشر نفسها.
///
/// `RenderEditable` لا يعرّف `getPositionForOffset` في هذه النسخة، فيُعكس
/// الاتجاه: `getLocalRectForCaret(offset).top` دالة غير متناقصة في الإزاحة،
/// فبحث ثنائي يعطي أول إزاحة تنتمي إلى السطر المطلوب — وهو المسار نفسه الذي
/// يستعمله الرسم لوضع المؤشر عند حدّ المقطع.
int _caretOffsetAtLineStart(
  WidgetTester tester,
  Finder field,
  _LineBox line,
) {
  final editable = _renderEditable(tester, field);
  final origin = tester.getTopLeft(_editableOf(field));
  final targetTop = line.top - origin.dy;
  final text = tester.widget<TextField>(field).controller!.text;
  var low = 0;
  var high = text.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final top =
        editable.getLocalRectForCaret(TextPosition(offset: middle)).top;
    if (top >= targetTop - 0.5) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  testWidgets('تقسيم الأسطر بين المقاطع متصل وغير متداخل، ولا سطر يُقصّ',
      (tester) async {
    final document = _arabicDocument();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    expect(plan.hasContinuations, isTrue,
        reason: 'المستند لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');

    final fragments = plan.fragmentsOfQuestion('sq2');
    // كل مقطع يبني الكتلة كاملة، فعدد أسطر السؤال = عدد أسطر أول حقل.
    final totalLines = _lineBoxes(tester, _fieldOf(fragments.first)).length;
    final covered = <int>[];
    var previousIndex = -1;

    for (final fragment in fragments) {
      final field = _fieldOf(fragment);
      expect(field, findsOneWidget,
          reason: 'حقل المقطع ${fragment.fragmentIndex} غير موجود.');
      final window = _windowOf(tester, fragment);
      final lines = _lineBoxes(tester, field);
      final drift = _allowedSeamDriftPx(fragment);

      // أسطر المقطع = الأسطر التي يتقاطع صندوقها مع النافذة تقاطعاً جوهرياً.
      final visible = <int>[
        for (var index = 0; index < lines.length; index++)
          if (lines[index].bottom > window.top + 0.5 &&
              lines[index].top < window.bottom - 0.5)
            index,
      ];
      expect(
        visible.length,
        fragment.lineIds.length,
        reason: 'عدد الأسطر المرسومة في المقطع ${fragment.fragmentIndex} '
            '(${visible.length}) لا يساوي عدد أسطر الخطة '
            '(${fragment.lineIds.length}): إمّا سطر مقصوص أو سطر دخيل.',
      );

      // (أ) الاحتواء: لا سطر يتجاوز النافذة (قصّ أعلى/أسفل).
      for (final index in visible) {
        final line = lines[index];
        expect(line.top, greaterThanOrEqualTo(window.top - drift),
            reason: 'سطر ${index + 1} من المقطع ${fragment.fragmentIndex} '
                'يبدأ فوق النافذة بـ${(window.top - line.top).toStringAsFixed(2)}px.');
        expect(line.bottom, lessThanOrEqualTo(window.bottom + drift),
            reason: 'سطر ${index + 1} من المقطع ${fragment.fragmentIndex} '
                'يتجاوز النافذة بـ'
                '${(line.bottom - window.bottom).toStringAsFixed(2)}px '
                '(الحدّ المشتقّ ${drift.toStringAsFixed(2)}px).');
      }

      // (ب) لا فجوة غير مبررة: أول سطر عند أعلى النافذة، وآخر سطر يملأها.
      final first = lines[visible.first];
      final last = lines[visible.last];
      final pitch = visible.length > 1
          ? lines[visible[1]].top - first.top
          : last.bottom - first.top;
      expect((first.top - window.top).abs(), lessThanOrEqualTo(pitch * 0.5 + drift),
          reason: 'المقطع ${fragment.fragmentIndex} يبدأ بفجوة '
              '${(first.top - window.top).toStringAsFixed(2)}px فوق أول سطر.');
      expect(window.bottom - last.bottom, lessThanOrEqualTo(pitch + 0.5),
          reason: 'المقطع ${fragment.fragmentIndex} ينتهي بفجوة '
              '${(window.bottom - last.bottom).toStringAsFixed(2)}px بعد آخر سطر.');

      // (ج) الاتصال: الأسطر متتابعة عبر المقاطع بلا تداخل ولا فجوة.
      expect(visible.first, previousIndex + 1,
          reason: 'المقطع ${fragment.fragmentIndex} يبدأ من السطر '
              '${visible.first} بعد أن انتهى السابق عند $previousIndex.');
      covered.addAll(visible);
      previousIndex = visible.last;
    }

    expect(covered, List<int>.generate(totalLines, (index) => index),
        reason: 'الأسطر المغطاة ($covered) ليست كل أسطر السؤال ($totalLines) '
            'بترتيبها: فقد أو تكرار عند الحدّ.');
  });

  testWidgets('حبر الحدّ: آخر سطر ظاهر كاملاً، ولا حبر مقطوع عند خطّ القصّ',
      (tester) async {
    final document = _arabicDocument();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final fragments = plan.fragmentsOfQuestion('sq2');
    expect(fragments.length, greaterThan(1));

    for (final fragment in fragments) {
      final field = _fieldOf(fragment);
      final window = _windowOf(tester, fragment);
      final lines = _lineBoxes(tester, field);
      final visible = <int>[
        for (var index = 0; index < lines.length; index++)
          if (lines[index].bottom > window.top + 0.5 &&
              lines[index].top < window.bottom - 0.5)
            index,
      ];
      expect(visible, isNotEmpty);

      final pageFinder =
          find.byKey(ValueKey<String>('a4-page-${fragment.pageIndex}'));
      final pageRect = tester.getRect(pageFinder);
      final boundary = _pageBoundary(tester, pageFinder, pageRect);
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      try {
        final data = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final pixels = data.buffer.asUint8List();
        final scale = pageRect.width / image.width;

        int darkIn(Rect rectPx) {
          final left = (rectPx.left / scale).floor().clamp(0, image.width - 1);
          final right = (rectPx.right / scale).ceil().clamp(0, image.width);
          final top = (rectPx.top / scale).floor().clamp(0, image.height - 1);
          final bottom = (rectPx.bottom / scale).ceil().clamp(0, image.height);
          var count = 0;
          for (var y = top; y < bottom; y++) {
            for (var x = left; x < right; x++) {
              final offset = (y * image.width + x) * 4;
              if (pixels[offset + 3] > 32 &&
                  (pixels[offset] + pixels[offset + 1] + pixels[offset + 2]) / 3 <
                      140) {
                count++;
              }
            }
          }
          return count;
        }

        Rect local(Rect globalRect) => Rect.fromLTRB(
              globalRect.left - pageRect.left,
              globalRect.top - pageRect.top,
              globalRect.right - pageRect.left,
              globalRect.bottom - pageRect.top,
            );

        // (1) سطر الحدّ الأخير مرسوم فعلاً داخل الصفحة.
        final lastLine = Rect.fromLTRB(
          lines[visible.last].left,
          lines[visible.last].top,
          lines[visible.last].right,
          lines[visible.last].bottom,
        );
        expect(darkIn(local(lastLine)), greaterThan(20),
            reason: 'آخر سطر في المقطع ${fragment.fragmentIndex} بلا حبر '
                'مرسوم: القياس بلا معنى.');

        // (2) لا حبر في صف البكسل عند حدّ النافذة السفلي (قصّ).
        final bottomBand = Rect.fromLTRB(
          window.left,
          window.bottom - scale,
          window.right,
          window.bottom,
        );
        expect(darkIn(local(bottomBand)), 0,
            reason: 'حبر ملتصق بحدّ القصّ السفلي في المقطع '
                '${fragment.fragmentIndex}: سطر مقطوع.');

        // (3) نافذة التكملة: لا حبر مقطوع عند أعلاها، وأول سطر مرسوم.
        if (fragment.isContinuation) {
          final topBand = Rect.fromLTRB(
            window.left,
            window.top,
            window.right,
            window.top + scale,
          );
          expect(darkIn(local(topBand)), 0,
              reason: 'حبر ملتصق بحدّ القصّ العلوي في المقطع '
                  '${fragment.fragmentIndex}: سطر مقطوع من أعلاه.');
          final firstLine = Rect.fromLTRB(
            lines[visible.first].left,
            lines[visible.first].top,
            lines[visible.first].right,
            lines[visible.first].bottom,
          );
          expect(darkIn(local(firstLine)), greaterThan(20),
              reason: 'أول سطر في التكملة ${fragment.fragmentIndex} بلا حبر.');
        }
      } finally {
        image.dispose();
      }
    }
  });

  testWidgets('مصدر نصّ واحد: التحديد والتحرير والمؤشر وIME والتراجع والإعادة',
      (tester) async {
    final document = _arabicDocument();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final fragments = plan.fragmentsOfQuestion('sq2');

    final startField = _fieldOf(fragments.first);
    final continuationField = _fieldOf(fragments.last);
    expect(startField, findsOneWidget);
    expect(continuationField, findsOneWidget);

    final startController = tester.widget<TextField>(startField).controller!;
    final continuationController =
        tester.widget<TextField>(continuationField).controller!;
    expect(identical(startController, continuationController), isTrue,
        reason: 'المقطعان لا يشتركان في المتحكم: مصدران للنصّ.');

    // (1) تحديد يعبر الحدّ: نقطتان هندسيتان في آخر سطر من المقطع الأول وأول
    // سطر من مقطع التكملة (`getPositionForOffset` على الحقل نفسه) — فيظهر
    // تحديد واحد على المقطعين، ويثبت أن المؤشر يُسقَط على المصدر الصحيح عبر
    // النافذة المزاحة والمقصوصة.
    final firstWindow = _windowOf(tester, fragments.first);
    final firstLines = _lineBoxes(tester, startField);
    final visibleInFirst = <_LineBox>[
      for (final line in firstLines)
        if (line.bottom > firstWindow.top + 0.5 && line.top < firstWindow.bottom - 0.5)
          line,
    ];
    final lastWindow = _windowOf(tester, fragments.last);
    final lastLines = _lineBoxes(tester, continuationField);
    final visibleInLast = <_LineBox>[
      for (final line in lastLines)
        if (line.bottom > lastWindow.top + 0.5 && line.top < lastWindow.bottom - 0.5)
          line,
    ];
    expect(visibleInFirst, isNotEmpty);
    expect(visibleInLast, isNotEmpty);
    final from = _caretOffsetAtLineStart(tester, startField, visibleInFirst.last);
    final to = _caretOffsetAtLineStart(
        tester, continuationField, visibleInLast.first);
    expect(to, greaterThan(from),
        reason: 'موضع المؤشر في التكملة ($to) ليس بعد موضعه في المقطع الأول '
            '($from): إسقاط المؤشر على المصدر خاطئ.');
    startController.selection = TextSelection(baseOffset: from, extentOffset: to);
    await tester.pump();

    for (final fragment in <CanonicalPagePlanFragment>[
      fragments.first,
      fragments.last,
    ]) {
      final editable = _renderEditable(tester, _fieldOf(fragment));
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to),
      );
      expect(boxes, isNotEmpty,
          reason: 'التحديد العابر للحدّ غير مرئي في المقطع '
              '${fragment.fragmentIndex}.');
    }

    // (2) IME: التركيب في مقطع التكملة يصل إلى المتحكم الواحد.
    await tester.showKeyboard(continuationField);
    await tester.pump();
    final composingText = '${startController.text}ـ';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: composingText,
        selection: TextSelection.collapsed(offset: composingText.length),
        composing: TextRange(start: composingText.length - 1, end: composingText.length),
      ),
    );
    await tester.pump();
    expect(startController.text, composingText,
        reason: 'التركيب لم يصل إلى المصدر الواحد.');
    expect(startController.value.composing.isValid, isTrue,
        reason: 'منطقة التركيب (IME) فُقدت.');

    // (3) التحرير من التكملة يظهر في مقطع البداية.
    const replacement = 'ZEND2-EDIT';
    await tester.enterText(continuationField, replacement);
    await tester.pumpAndSettle();
    expect(startController.text, replacement);
    final startEditable = _renderEditable(tester, startField);
    expect((startEditable.text as TextSpan?)?.toPlainText(), replacement,
        reason: 'مقطع البداية لا يعرض النصّ المحرَّر في التكملة.');
    expect(startController.selection.isValid, isTrue,
        reason: 'المؤشر غير صالح بعد التحرير من التكملة.');

    // (4) التراجع والإعادة عبر مسار المستند نفسه (شريط المعاينة).
    expect(controller.canUndo, isTrue, reason: 'لا تراجع بعد تحرير.');
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.document.questions[1].body, isNot(replacement),
        reason: 'التراجع لم يُعِد المحتوى السابق.');
    expect(controller.canRedo, isTrue);
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.document.questions[1].body, replacement,
        reason: 'الإعادة لم تُعِد التحرير.');
  });

  testWidgets('PDF: كلمات الحدّ تُطبع في صفحة مقطعها مرة واحدة (رموز فريدة)',
      (tester) async {
    final document = _tokenDocument();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final fragments = plan.fragmentsOfQuestion('tq1');
    expect(fragments.length, greaterThan(1),
        reason: 'مستند الرموز لم يُنتج سؤالاً ممتداً: القياس بلا عيّنة.');

    // كلمتا الحدّ لكل مقطع: أول كلمة في أول سطره، وآخر كلمة في آخر سطره.
    final seamWords = <({String word, int pageIndex, int fragmentIndex})>[
      for (final fragment in fragments) ...<_EdgeWord>[
        (
          word: _edgeWord(_linesOfFragment(plan, fragment).first, first: true),
          pageIndex: fragment.pageIndex,
          fragmentIndex: fragment.fragmentIndex,
        ),
        (
          word: _edgeWord(_linesOfFragment(plan, fragment).last, first: false),
          pageIndex: fragment.pageIndex,
          fragmentIndex: fragment.fragmentIndex,
        ),
      ],
    ];

    final bytes = (await tester.runAsync(() async {
      final fonts = await ExamFonts.load();
      return PaginatedPdfExamEngine().generate(
        document: controller.document,
        fonts: fonts,
      );
    }))!;

    expect(PdfContentProbe.pageCountOf(bytes), plan.pageCount,
        reason: 'عدد صفحات PDF لا يساوي عدد صفحات الخطة.');

    final pages = <List<String>>[
      for (var index = 0; index < plan.pageCount; index++)
        <String>[
          for (final word
              in PdfContentProbe.fromBytes(bytes, pageIndex: index).words)
            word.text.trim(),
        ],
    ];

    // كل كلمة حدّ تُطبع مرة واحدة، في صفحة مقطعها بالضبط.
    for (final seam in seamWords) {
      final occurrences = <int>[
        for (var page = 0; page < pages.length; page++)
          if (pages[page].contains(seam.word)) page,
      ];
      expect(occurrences, <int>[seam.pageIndex],
          reason: 'الكلمة "${seam.word}" من سطر حدّ المقطع '
              '${seam.fragmentIndex} ظهرت في صفحات $occurrences مقابل '
              'صفحة المقطع ${seam.pageIndex}.');
    }
  });

  // ⚠️ TEMP (يُزال بعد قراءة الأرقام): يطبع جدول الحدود في رسالة فشل، لأن سجلات
  // التشغيل الكاملة غير قابلة للتنزيل من بيئة التطوير.
  testWidgets('SEAM-PROBE: جدول قياس الحدود', (tester) async {
    final document = _arabicDocument();
    final controller = await _pumpPreview(tester, document);
    final plan = await _planOf(controller.document);
    final fragments = plan.fragmentsOfQuestion('sq2');
    final buffer = StringBuffer()
      ..writeln('مستند عربي: ${fragments.length} مقطع، '
          'فرق النسبة=$kUnitRatioError، انزياح/pt=$kPxPerPtMismatch px');
    final firstLines = _lineBoxes(tester, _fieldOf(fragments.first));
    for (final fragment in fragments) {
      final window = _windowOf(tester, fragment);
      final lines = _lineBoxes(tester, _fieldOf(fragment));
      final visible = <int>[
        for (var index = 0; index < lines.length; index++)
          if (lines[index].bottom > window.top + 0.5 &&
              lines[index].top < window.bottom - 0.5)
            index,
      ];
      final topGap = lines[visible.first].top - window.top;
      final bottomGap = window.bottom - lines[visible.last].bottom;
      final overflow = lines[visible.last].bottom - window.bottom;
      buffer.writeln(
        'f${fragment.fragmentIndex}: srcTop=${fragment.sourceTopPt.toStringAsFixed(2)}pt '
        'h=${fragment.heightPt.toStringAsFixed(2)}pt '
        'win=${window.height.toStringAsFixed(2)}px '
        'أسطر=${visible.length}/${fragment.lineIds.length} '
        'topGap=${topGap.toStringAsFixed(2)}px '
        'bottomGap=${bottomGap.toStringAsFixed(2)}px '
        'overflow=${overflow.toStringAsFixed(2)}px '
        'الحدّ=${_allowedSeamDriftPx(fragment).toStringAsFixed(2)}px',
      );
    }
    buffer.writeln('إجمالي أسطر السؤال (أول حقل)=${firstLines.length}');
    // فشل مقصود لعرض الجدول في تعليقات CI.
    expect(buffer.toString(), 'PROBE');
  });
}
