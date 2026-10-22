// بوابة مطابقة الهندسة بين **حقل المعاينة الفعلي** والتخطيط القانوني (الذي
// يرسمه PDF حرفياً).
//
// لماذا بوابة ثانية وقد قِيس PDF ↔ LayoutDocument في `pdf_glyph_overlap_test`؟
// لأن تلك تقيس الطرف الثاني من السلسلة فقط. أما الحقل الذي يكتب فيه المدرس
// ويرى فيه النتيجة فكان يُخطَّط بمحرّك نصّ آخر: التفاف خاص به، وتوسعة
// `wordSpacing` يدوية فوق `TextAlign.justify`. فكان يمكن أن ينجح كل اختبار
// ويبقى المستخدم يرى أسطراً ممدودة أكثر من العمود ثم تُطبع أسطر أخرى.
//
// ما تقيسه البوابة (من المصدر الدلالي نفسه، لا من مطابقة صور):
//   * نصّ كل سطر: نقاط الالتفاف نفسها (تساوٍ بعد تطبيع المسافات).
//   * عدد الأسطر: تساوٍ تام.
//   * عرض كل سطر: السطر المضبوط = عرض العمود، وغير المضبوط = عرضه الطبيعي.
//   * تباعد الأسطر رأسياً (قياس تراكمي، لا إزاحة ثابتة).
//   * وجود نص عربي مضبوط متعدد الأسطر، ونص قصير أحادي، ونص إنجليزي LTR، في
//     المستند نفسه، كلٌّ في اختبار مستقل كي تُقاس كل حالة حتى لو فشلت أخرى.
//
// حدود القياس: `RenderEditable` يعطي صناديق التحديد لكل سطر (هندسة Skia
// المرسومة فعلاً) وحدود كل سطر نصياً، ولا يعطي موضع كل محرف منفرداً عبر واجهة
// عامة، فلا تدّعي البوابة أكثر من: نصّ السطر، عدده، حوافه، عروضه، تباعده.
//
// التفاوت المبرَّر: 0.75pt (≈0.26mm) — نفس الحد الموثَّق في بوابة تطابق الحبر
// (`pdf_glyph_overlap_test`)، وهو أكبر من تقريب تحويل px→pt (±0.05pt) وأصغر من
// أصغر مسافة كلمة مقروءة (≈1pt). لا يُؤخذ من نتائج اليوم: بدونه لا يمكن مقارنة
// محركين يشتركان في Skia ويختلفان في تقريب ارتفاع السطر وقياس الحافة.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// التفاوت الموثَّق (pt) بين هندسة الحقل والهندسة القانونية.
const double kGeometryTolerancePt = 0.75;

/// التفاوت الرأسي (pt) بين موضعي سطر متقابلين.
const double kVerticalTolerancePt = 1.0;

const String _arabicBody =
    'هذا متن عربي طويل يقيس الضبط الحقيقي في حقل المعاينة مقابل التخطيط '
    'القانوني الذي يطبعه PDF، ويحمل أرقاماً ٢٠ و 2026 وكلمات متعددة '
    'ليُقس على فواصلها القابلة للكسر في كل سطر ما عدا الأخير من الفقرة.';

const String _englishBody =
    'A justified English paragraph that is long enough to wrap into more '
    'than one line so the LTR line breaking can be compared with the '
    'canonical layout of the same paragraph in the exported PDF.';

const String _shortBody = 'سطر واحد لا يُمَدّ.';

ExamDocument _document() => ExamDocument(
      name: 'مطابقة هندسة المعاينة والتخطيط',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'سؤال أول',
          body: _arabicBody,
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          statement: 'سؤال ثانٍ',
          body: _shortBody,
          bodyAlign: PaperAlign.justify,
        ),
        QuestionModel(
          id: 'q3',
          questionNumber: 3,
          statement: 'Third question',
          body: _englishBody,
          bodyAlign: PaperAlign.justify,
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, ExamWizardController controller) async {
  tester.view.physicalSize = const Size(1600, 2600);
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

Finder _field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    );

RenderEditable _editable(WidgetTester tester, Finder field) => tester
    .state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .renderEditable;

typedef _FieldLine = ({
  String text,
  double left,
  double right,
  double top,
  double bottom,
});

/// أسطر النص كما يرسمها الحقل نفسه (صناديق Skia للتحديد الكامل + حدود الأسطر)،
/// بالنقاط، مع نصّ كل سطر لاستخراج نقاط الالتفاف.
List<_FieldLine> _fieldLines(WidgetTester tester, Finder field) {
  final editable = _editable(tester, field);
  final text = tester.widget<TextField>(field).controller!.text;
  expect(text.trim(), isNotEmpty, reason: 'الحقل المقيس فارغ.');
  final boxes = editable.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty,
      reason: 'لا صناديق نصّ للحقل: القياس بلا عيّنة.');
  final sorted = boxes.toList()
    ..sort((a, b) {
      final dy = a.top.compareTo(b.top);
      return dy != 0 ? dy : a.left.compareTo(b.left);
    });
  final boxesPerLine = <({double left, double right, double top, double bottom})>[];
  for (final box in sorted) {
    final top = box.top;
    if (boxesPerLine.isNotEmpty && (boxesPerLine.last.top - top).abs() <= 1.0) {
      final previous = boxesPerLine.removeLast();
      boxesPerLine.add((
        left: previous.left < box.left ? previous.left : box.left,
        right: previous.right > box.right ? previous.right : box.right,
        top: previous.top,
        bottom: previous.bottom > box.bottom ? previous.bottom : box.bottom,
      ));
      continue;
    }
    boxesPerLine.add((
      left: box.left,
      right: box.right,
      top: top,
      bottom: box.bottom,
    ));
  }

  // حدود الأسطر نصياً: `RenderEditable` لا يعطي `getLineBoundary`، فيُستخرج
  // نصّ كل سطر من صناديق المحارف المفردة (صندوق لكل محرف ← خطّه). هذا يعطي
  // نقاط الالتفاف نفسها لا استنتاجاً من العرض.
  final lineTexts = <StringBuffer>[];
  final lineTops = <double>[];
  for (var index = 0; index < text.length; index++) {
    final charBoxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    final top = charBoxes.isEmpty
        ? (lineTops.isEmpty ? 0.0 : lineTops.last)
        : charBoxes.first.top;
    var lineIndex =
        lineTops.indexWhere((existing) => (existing - top).abs() <= 1.0);
    if (lineIndex < 0) {
      lineTops.add(top);
      lineIndex = lineTops.length - 1;
    }
    while (lineTexts.length <= lineIndex) {
      lineTexts.add(StringBuffer());
    }
    lineTexts[lineIndex].write(text[index]);
  }
  expect(lineTexts.length, boxesPerLine.length,
      reason: 'عدد حدود الأسطر النصية (${lineTexts.length}) لا يساوي عدد '
          'صناديق الأسطر المرسومة (${boxesPerLine.length}): القياس غير موثوق.');

  return <_FieldLine>[
    for (var index = 0; index < boxesPerLine.length; index++)
      (
        text: lineTexts[index].toString(),
        left: LayoutUnits.pxToPt(boxesPerLine[index].left),
        right: LayoutUnits.pxToPt(boxesPerLine[index].right),
        top: LayoutUnits.pxToPt(boxesPerLine[index].top),
        bottom: LayoutUnits.pxToPt(boxesPerLine[index].bottom),
      ),
  ];
}

LayoutDocument _layout(ExamDocument document) => const LayoutEngine().layout(
      document: DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      ),
      configuration: ExamDocumentLayoutAdapter.configurationFor(document),
      fontMetrics: const FlutterTextMetrics(),
    );

List<LayoutLine> _canonicalLines(LayoutDocument layout, String nodePrefix) =>
    <LayoutLine>[
      for (final page in layout.pages)
        for (final block in page.blocks)
          for (final line in block.allLines)
            if (line.runs.any(
              (run) => run.semanticNodeId.startsWith(nodePrefix),
            ))
              line,
    ];

/// نصّ السطر القانوني بالترتيب المنطقي (لا المرئي)، مطبَّعاً.
String _canonicalLineText(LayoutLine line) {
  final runs = line.runs.toList()
    ..sort((a, b) => a.logicalIndex.compareTo(b.logicalIndex));
  return _normalize(runs.map((run) => run.text).join());
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'[ \t\n\r\u00a0]+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  Future<(ExamDocument, LayoutDocument)> pumpDocument(
    WidgetTester tester,
  ) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    return (document, _layout(document));
  }

  /// تشخيص مكثّف في سطرين (سجلّ CI يقتطع الرسائل الطويلة): نمط الحقل ونمط
  /// القانوني، ثم نصّ كل سطر وعرضه على الجانبين.
  void diagnose(
    String key,
    WidgetTester tester,
    Finder field,
    String source,
    List<_FieldLine> fieldLines,
    List<LayoutLine> canonicalLines,
  ) {
    final style = tester.widget<TextField>(field).style;
    final firstRun = canonicalLines.first.runs.isEmpty
        ? null
        : (canonicalLines.first.runs.toList()
              ..sort((a, b) => a.logicalIndex.compareTo(b.logicalIndex)))
            .first;
    final canonicalStyle = firstRun?.style;
    final probe = canonicalStyle == null
        ? null
        : const FlutterTextMetrics().measureText(
            _normalize(source),
            canonicalStyle,
            DocumentDirection.rtl,
          );
    final painter = TextPainter(
      text: TextSpan(text: _normalize(source), style: style),
      textDirection: ui.TextDirection.rtl,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: double.infinity);
    // ignore: avoid_print
    print('[geom] $key | الحقل fs=${style?.fontSize?.toStringAsFixed(3)} '
        'w=${style?.fontWeight} i=${style?.fontStyle} '
        'h=${style?.height} | القانوني fs=${canonicalStyle?.fontSizePt} '
        'b=${canonicalStyle?.bold} i=${canonicalStyle?.italic} '
        'lh=${canonicalStyle?.lineHeightFactor} | '
        'قياس المحرك=${probe?.advance.toStringAsFixed(2)}pt '
        'قياس TextStyle الحقل=${LayoutUnits.pxToPt(painter.width).toStringAsFixed(2)}pt');
    painter.dispose();
    String short(String value) =>
        value.length <= 24 ? value : '${value.substring(0, 24)}…';
    // ignore: avoid_print
    print('[geom] $key | الحقل: '
        '${fieldLines.map((l) => '${(l.right - l.left).toStringAsFixed(2)}'
            '"${short(_normalize(l.text))}"').toList()} | القانوني: '
        '${canonicalLines.map((l) => '${l.naturalWidth.toStringAsFixed(2)}/'
            '${l.resolvedWidth.toStringAsFixed(2)}j${l.isJustified}'
            '"${short(_canonicalLineText(l))}"').toList()}');
  }

  testWidgets('فقرة عربية مضبوطة: نقاط الالتفاف والعروض والتباعد مطابقة',
      (tester) async {
    final (_, canonical) = await pumpDocument(tester);
    const key = 'body-q1';
    const node = 'q1/body';
    final field = _field(key);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    final fieldLines = _fieldLines(tester, field);
    final canonicalLines = _canonicalLines(canonical, node);
    expect(canonicalLines, isNotEmpty,
        reason: 'لا أسطر قانونية لـ$node: القياس بلا مرجع.');
    diagnose(key, tester, field, _arabicBody, fieldLines, canonicalLines);

    // تشخيص سلسلة الأحجام: من أين يأتي فرق العمود (2px) إن وُجد.
    final chain = <String>[];
    tester.element(field).visitAncestorElements((element) {
      final render = element.renderObject;
      if (render is RenderBox && render.hasSize && chain.length < 14) {
        chain.add('${element.widget.runtimeType}='
            '${render.size.width.toStringAsFixed(2)}');
      }
      return chain.length < 14;
    });
    // ignore: avoid_print
    print('[geom] $key | سلسلة العرض: ${chain.join(' < ')} | عمود التخطيط='
        '${canonical.pages.first.bodyBounds.width.toStringAsFixed(2)}pt');

    // (0) العمود نفسه: عرض حقل التحرير = عرض عمود النصّ القانوني. الفرق هنا
    // يعني أن ما يُرسم على الشاشة يُلفّ في عمود غير العمود المطبوع (كان
    // `padding: 1` لمؤشّر التحديد يضيّقه 2px ما دام السؤال محدَّداً).
    expect(
      LayoutUnits.pxToPt(tester.getSize(field).width),
      closeTo(canonical.pages.first.bodyBounds.width, kGeometryTolerancePt),
      reason: '$key: عمود الحقل '
          '${LayoutUnits.pxToPt(tester.getSize(field).width).toStringAsFixed(2)}pt '
          'مقابل عمود التخطيط '
          '${canonical.pages.first.bodyBounds.width.toStringAsFixed(2)}pt.',
    );

    // (1) عدد الأسطر: تساوٍ تام.
    expect(fieldLines, hasLength(canonicalLines.length),
        reason: '$key: ${fieldLines.length} سطراً في الحقل مقابل '
            '${canonicalLines.length} قانونياً.');

    // (2) نقاط الالتفاف: نصّ كل سطر مطابق بعد تطبيع المسافات.
    for (var index = 0; index < canonicalLines.length; index++) {
      expect(
        _normalize(fieldLines[index].text),
        _canonicalLineText(canonicalLines[index]),
        reason: '$key: نصّ السطر ${index + 1} مختلف — أي أن الالتفاف انكسر في '
            'موضع آخر، ولو تساوى عدد الأسطر.',
      );
    }

    // (3) عرض كل سطر: المضبوط يبلغ العمود، والأخير بلا مدّ.
    for (var index = 0; index < canonicalLines.length; index++) {
      final line = canonicalLines[index];
      final expected =
          line.isJustified ? line.resolvedWidth : line.naturalWidth;
      final actual = fieldLines[index].right - fieldLines[index].left;
      expect(actual, closeTo(expected, kGeometryTolerancePt),
          reason: '$key: عرض السطر ${index + 1} — ${expected.toStringAsFixed(2)}pt'
              ' متوقعاً (isJustified=${line.isJustified}, natural='
              '${line.naturalWidth.toStringAsFixed(2)}, resolved='
              '${line.resolvedWidth.toStringAsFixed(2)}).');
    }

    // (4) التباعد الرأسي: قياس تراكمي بين السطور.
    for (var index = 1; index < canonicalLines.length; index++) {
      final fieldGap = fieldLines[index].top - fieldLines[index - 1].top;
      final expectedGap =
          canonicalLines[index].rect.top - canonicalLines[index - 1].rect.top;
      expect(fieldGap, closeTo(expectedGap, kVerticalTolerancePt),
          reason: '$key: المسافة بين السطر $index و${index + 1} — '
              '${fieldGap.toStringAsFixed(2)}pt مقابل '
              '${expectedGap.toStringAsFixed(2)}pt.');
    }

    // (5) الشروط نفسها ليست عمياء: البوابة تحتاج سطراً مضبوطاً وآخر غير مضبوط.
    expect(canonicalLines.any((line) => line.isJustified), isTrue,
        reason: '$key: لا سطر مضبوط في المرجع — العيّنة لا تقيس الضبط.');
    expect(canonicalLines.last.isJustified, isFalse,
        reason: '$key: السطر الأخير مضبوط — القاعدة تنصّ على عدم مدّه.');
    final fieldColumn = canonicalLines
        .firstWhere((line) => line.isJustified)
        .resolvedWidth;
    final lastWidth =
        fieldLines.last.right - fieldLines.last.left;
    expect(lastWidth, lessThan(fieldColumn - kGeometryTolerancePt),
        reason: '$key: السطر الأخير في الحقل ممتدّ إلى العمود '
            '(${lastWidth.toStringAsFixed(2)}pt ≈ $fieldColumn): هذا مدّ سطر '
            'أخير، وهو ما تمنعه القاعدة.');
  });

  testWidgets('فقرة قصيرة أحادية السطر: لا تُمَدّ في الحقل ولا في التخطيط',
      (tester) async {
    final (_, canonical) = await pumpDocument(tester);
    const key = 'body-q2';
    const node = 'q2/body';
    final field = _field(key);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    final fieldLines = _fieldLines(tester, field);
    final canonicalLines = _canonicalLines(canonical, node);
    expect(canonicalLines, hasLength(1),
        reason: 'الفقرة القصيرة التُفّت قانونياً إلى '
            '${canonicalLines.length} أسطر: القياس بلا عيّنة.');
    diagnose(key, tester, field, _shortBody, fieldLines, canonicalLines);

    expect(fieldLines, hasLength(1),
        reason: '$key: الحقل لفّ الفقرة القصيرة إلى ${fieldLines.length} أسطر.');
    expect(canonicalLines.single.isJustified, isFalse,
        reason: 'التخطيط القانوني مدّ فقرة من سطر واحد.');
    expect(_normalize(fieldLines.single.text),
        _canonicalLineText(canonicalLines.single),
        reason: '$key: نصّ السطر مختلف بين الحقل والتخطيط.');
    final width = fieldLines.single.right - fieldLines.single.left;

    // (أ) نمط الحقل يُصرّح بتباعده ولا يرثه من ثيم Material: وراثة
    // `letterSpacing` (0.5px في bodyLarge) تجعل النصّ المرسوم أوسع من قياس
    // المحرك نفسه بنحو 11%، فتنكسر الأسطر في موضع آخر غير PDF.
    final fieldStyle = tester.widget<TextField>(field).style!;
    expect(fieldStyle.letterSpacing ?? 0, 0,
        reason: '$key: تباعد محارف موروث/غير صفري في حقل الورقة — '
            'النصّ سيُرسم أوسع من قياس المحرك.');
    expect(fieldStyle.wordSpacing ?? 0, 0,
        reason: '$key: تباعد كلمات غير صفري في حقل الورقة.');

    // (ب) ما يُرسم في الحقل يساوي قياس نمطه المعلن نفسه: يمسك أي خاصية
    // موروثة أو مضافة لم تُصرَّح.
    final naturalPainter = TextPainter(
      text: TextSpan(text: _shortBody, style: fieldStyle),
      textDirection: ui.TextDirection.rtl,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: double.infinity);
    addTearDown(naturalPainter.dispose);
    expect(
      width,
      closeTo(LayoutUnits.pxToPt(naturalPainter.width), kGeometryTolerancePt),
      reason: '$key: العرض المرسوم ${width.toStringAsFixed(2)}pt لا يساوي قياس '
          'نمط الحقل نفسه '
          '${LayoutUnits.pxToPt(naturalPainter.width).toStringAsFixed(2)}pt.',
    );

    expect(
      width,
      closeTo(canonicalLines.single.naturalWidth, kGeometryTolerancePt),
      reason: '$key: الفقرة الأحادية عرضها ${width.toStringAsFixed(2)}pt في '
          'الحقل مقابل ${canonicalLines.single.naturalWidth.toStringAsFixed(2)}pt '
          'طبيعياً — فرق يعني مدّاً أو قياساً مختلفاً.',
    );
  });

  testWidgets('فقرة إنجليزية مضبوطة (LTR): الالتفاف والعروض مطابقة',
      (tester) async {
    final (_, canonical) = await pumpDocument(tester);
    const key = 'body-q3';
    const node = 'q3/body';
    final field = _field(key);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    final fieldLines = _fieldLines(tester, field);
    final canonicalLines = _canonicalLines(canonical, node);
    expect(canonicalLines, isNotEmpty,
        reason: 'لا أسطر قانونية لـ$node: القياس بلا مرجع.');
    diagnose(key, tester, field, _englishBody, fieldLines, canonicalLines);

    expect(fieldLines, hasLength(canonicalLines.length),
        reason: '$key: ${fieldLines.length} سطراً في الحقل مقابل '
            '${canonicalLines.length} قانونياً (LTR).');
    for (var index = 0; index < canonicalLines.length; index++) {
      expect(_normalize(fieldLines[index].text),
          _canonicalLineText(canonicalLines[index]),
          reason: '$key: نصّ السطر ${index + 1} مختلف (LTR).');
      final line = canonicalLines[index];
      final expected =
          line.isJustified ? line.resolvedWidth : line.naturalWidth;
      final actual = fieldLines[index].right - fieldLines[index].left;
      expect(actual, closeTo(expected, kGeometryTolerancePt),
          reason: '$key: عرض السطر ${index + 1} (LTR) — '
              '${expected.toStringAsFixed(2)}pt متوقعاً.');
      // LTR: بداية السطر عند الحافة اليسرى للحقل، لا اليمنى.
      expect(fieldLines[index].left, lessThan(1.0),
          reason: '$key: السطر ${index + 1} لا يبدأ من الحافة اليسرى '
              '(${fieldLines[index].left.toStringAsFixed(2)}pt) — اتجاه غير LTR.');
    }
  });

  test('لا يُعاد إدخال توسعة ضبط يدوية ولا استثناء قياس', () {
    // البوابة تحرس السبب لا العَرَض: أي عودة إلى `wordSpacing` يدوي أو إلى حدّ
    // محلي للتوسعة تُفشل البوابة حتى لو بدت الأسطر «مقبولة» بصرياً.
    for (final path in <String>[
      'lib/views/widgets/paper_field.dart',
      'lib/views/widgets/tex_text.dart',
      'lib/layout/visual/visual_flutter_style.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('justifyWordSpacing'), isFalse,
          reason: '$path: عادت توسعة الضبط اليدوية.');
      expect(source.contains('clamp(12.0, 60.0)'), isFalse,
          reason: '$path: عاد حدّ التوسعة المحلي.');
    }
    final metrics = File('lib/layout/canonical/flutter_text_metrics.dart')
        .readAsStringSync();
    for (final needle in <String>[
      'eligibleForJustification',
      'index < lineMetrics.length - 1',
      'opportunities > 0',
    ]) {
      expect(metrics.contains(needle), isTrue,
          reason: 'قاعدة الضبط الوحيدة مفقودة من المحرك: $needle');
    }
  });

  testWidgets('نصّ الحقل هو نصّ المصدر حرفياً (لا مسافات ضبط مُدخلة)',
      (tester) async {
    // توزيع الضبط هندسة لا محتوى: ما يُخزَّن ويُرسم هو نصّ المصدر نفسه، فلا
    // تُحقن مسافات في النموذج لتحقيق عرض سطر.
    await pumpDocument(tester);
    for (final entry in <String, String>{
      'body-q1': _arabicBody,
      'body-q3': _englishBody,
    }.entries) {
      final field = _field(entry.key);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        entry.value,
        reason: '${entry.key}: نصّ الحقل مختلف عن نصّ المصدر '
            '(مسافات/محارف مُضافة للضبط).',
      );
    }
  });
}
