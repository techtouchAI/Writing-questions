// بوابة مطابقة الهندسة بين **حقل المعاينة الفعلي** والتخطيط القانوني (الذي
// يرسمه PDF حرفياً).
//
// لماذا بوابة ثانية وقد قِيس PDF ↔ LayoutDocument في `pdf_glyph_overlap_test`؟
// لأن تلك تقيس الطرف الثاني من السلسلة فقط. أما الحقل الذي يكتب فيه المدرس
// ويرى فيه النتيجة فكان يُخطَّط بمحرّك نصّ آخر: التفاف خاص به، وتوسعة
// `wordSpacing` يدوية فوق `TextAlign.justify`. فكان يمكن أن ينجح كل اختبار
// ويبقى المستخدم يرى أسطراً ممدودة أكثر من العمود ثم تُطبع أسطر أخرى.
//
// ما تقيسه البوابة (من المصدر الدلالي نفسه لا من مطابقة صور):
//   * عدد الأسطر ونقاط الالتفاف (تساوٍ تام، لا تفاوت).
//   * عرض كل سطر: السطر المضبوط = عرض العمود، والسطر الأخير = عرضه الطبيعي.
//   * الفقرة من سطر واحد لا تُمَدّ (لا في الحقل ولا في التخطيط).
//   * تباعد الأسطر رأسياً (قياس تراكمي، لا إزاحة ثابتة).
//   * وجود نص عربي مضبوط، ونص إنجليزي LTR، ونص قصير، في المستند نفسه.
//
// حدود القياس: `RenderEditable` يعطي صناديق التحديد لكل سطر (Skia paragraph)،
// وهي الهندسة المرسومة فعلاً في الحقل؛ ولا يعطي موضع كل محرف منفرداً عبر واجهة
// عامة، فلا تدّعي البوابة أكثر من: أسطر، حواف، عروض، تباعد.
//
// التفاوت المبرَّر: 0.75pt (≈0.26mm) — نفس الحد الموثَّق في بوابة تطابق
// الحبر (`pdf_glyph_overlap_test`)، وهو أكبر من تقريب تحويل px→pt (±0.05pt)
// وأصغر من أصغر مسافة كلمة مقروءة (≈1pt). لا يُؤخذ من نتائج اليوم يإلى
// المبدأ: بدونه لا يمكن مقارنة محركين يشتركان في Skia ويختلفان في تقريب
// ارتفاع السطر.
import 'dart:io';

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

/// أسطر النص كما يرسمها الحقل نفسه (صناديق Skia للتحديد الكامل)، بالنقاط.
List<({double left, double right, double top, double bottom})> _fieldLines(
  WidgetTester tester,
  Finder field,
) {
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
  final lines = <({double left, double right, double top, double bottom})>[];
  for (final box in sorted) {
    final top = box.top;
    if (lines.isNotEmpty && (lines.last.top - top).abs() <= 1.0) {
      final previous = lines.removeLast();
      lines.add((
        left: previous.left < box.left ? previous.left : box.left,
        right: previous.right > box.right ? previous.right : box.right,
        top: previous.top,
        bottom: previous.bottom > box.bottom ? previous.bottom : box.bottom,
      ));
      continue;
    }
    lines.add((
      left: box.left,
      right: box.right,
      top: top,
      bottom: box.bottom,
    ));
  }
  return <({double left, double right, double top, double bottom})>[
    for (final line in lines)
      (
        left: LayoutUnits.pxToPt(line.left),
        right: LayoutUnits.pxToPt(line.right),
        top: LayoutUnits.pxToPt(line.top),
        bottom: LayoutUnits.pxToPt(line.bottom),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  testWidgets('حقل المعاينة يطابق التخطيط القانوني في الأسطر والعروض والتباعد',
      (tester) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final canonical = _layout(document);
    const cases = <String, String>{
      'body-q1': 'q1/body',
      'body-q2': 'q2/body',
      'body-q3': 'q3/body',
    };
    for (final entry in cases.entries) {
      final field = _field(entry.key);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final fieldLines = _fieldLines(tester, field);
      final canonicalLines = _canonicalLines(canonical, entry.value);
      expect(canonicalLines, isNotEmpty,
          reason: 'لا أسطر قانونية لـ${entry.value}: القياس بلا مرجع.');

      // (1) عدد الأسطر: تساوٍ تام. اختلافه يعني التفافاً مختلفاً، وهو الفرق
      // الذي لا يجوز أن يبقى بين ما يراه المستخدم وما يُطبع.
      expect(
        fieldLines.length,
        canonicalLines.length,
        reason: '${entry.key}: الحقل التُفّ على ${fieldLines.length} سطراً '
            'والتخطيط القانوني على ${canonicalLines.length}.\n'
            'حقل: ${fieldLines.map((l) => '${(l.right - l.left).toStringAsFixed(2)}pt').toList()}\n'
            'قانوني: ${canonicalLines.map((l) => '${(l.resolvedWidth).toStringAsFixed(2)}pt').toList()}',
      );

      // (2) عرض كل سطر: المضبوط = عرض العمود، والأخير = عرضه الطبيعي.
      for (var index = 0; index < canonicalLines.length; index++) {
        final line = canonicalLines[index];
        final isLast = index == canonicalLines.length - 1;
        final expected =
            isLast || !line.isJustified ? line.naturalWidth : line.resolvedWidth;
        final actual = fieldLines[index].right - fieldLines[index].left;
        expect(
          (actual - expected).abs(),
          lessThanOrEqualTo(kGeometryTolerancePt),
          reason: '${entry.key} سطر ${index + 1}/${canonicalLines.length}: '
              'عرض الحقل ${actual.toStringAsFixed(2)}pt مقابل '
              '${expected.toStringAsFixed(2)}pt قانونياً '
              '(isJustified=${line.isJustified}, natural='
              '${line.naturalWidth.toStringAsFixed(2)}, '
              'resolved=${line.resolvedWidth.toStringAsFixed(2)}).',
        );
      }

      // (3) التباعد الرأسي: يبدأ السطر التالي بعد ارتفاع السطر السابق نفسه.
      for (var index = 1; index < canonicalLines.length; index++) {
        final fieldGap = fieldLines[index].top - fieldLines[index - 1].top;
        final expectedGap = canonicalLines[index].rect.top -
            canonicalLines[index - 1].rect.top;
        expect(
          (fieldGap - expectedGap).abs(),
          lessThanOrEqualTo(kVerticalTolerancePt),
          reason: '$entry.key المسافة بين السطر ${index} و${index + 1}: '
              '${fieldGap.toStringAsFixed(2)}pt في الحقل مقابل '
              '${expectedGap.toStringAsFixed(2)}pt قانونياً.',
        );
      }

      // (4) الحافة: السطر مضبوط يعني أنه بلغ عرض العمود، لا عرضاً آخر.
      final columnWidth = canonicalLines
          .firstWhere((line) => line.isJustified, orElse: () => canonicalLines.first)
          .resolvedWidth;
      for (var index = 0; index < canonicalLines.length - 1; index++) {
        if (!canonicalLines[index].isJustified) continue;
        final width = fieldLines[index].right - fieldLines[index].left;
        expect((width - columnWidth).abs(), lessThanOrEqualTo(kGeometryTolerancePt),
            reason: '${entry.key} سطر ${index + 1} المضبوط لم يبلغ عرض العمود: '
                '${width.toStringAsFixed(2)} مقابل '
                '${columnWidth.toStringAsFixed(2)}pt');
      }
    }
  });

  testWidgets('الفقرة من سطر واحد لا تُمَدّ في الحقل ولا في التخطيط',
      (tester) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final canonical = _layout(document);
    final canonicalLines = _canonicalLines(canonical, 'q2/body');
    expect(canonicalLines, hasLength(1),
        reason: 'الفقرة القصيرة التُفّت قانونياً إلى '
            '${canonicalLines.length} أسطر: القياس بلا عيّنة.');
    expect(canonicalLines.single.isJustified, isFalse,
        reason: 'التخطيط القانوني مدّ فقرة من سطر واحد.');

    final field = _field('body-q2');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final fieldLines = _fieldLines(tester, field);
    expect(fieldLines, hasLength(1));
    final width = fieldLines.single.right - fieldLines.single.left;
    expect(
      (width - canonicalLines.single.naturalWidth).abs(),
      lessThanOrEqualTo(kGeometryTolerancePt),
      reason: 'الحقل مدّ فقرة من سطر واحد: ${width.toStringAsFixed(2)}pt مقابل '
          'عرضها الطبيعي ${canonicalLines.single.naturalWidth.toStringAsFixed(2)}pt.',
    );
  });

  test('الحقل لا يضيف توسعة كلمات يدوية: الضبط قاعدة واحدة في المحرك', () {
    // الفحص على السلوك لا على وجود نصّ في الملف: لا حقل ولا `TexText` يمرّر
    // `wordSpacing` مشتقاً من عرض الفقرة، لأن ذلك يُنتج توسعة ثانية فوق
    // `TextAlign.justify` (وهو ما قاسته هذه البوابة قبل الإصلاح).
    const files = <String>[
      'lib/views/widgets/paper_field.dart',
      'lib/views/widgets/tex_text.dart',
      'lib/layout/visual/visual_flutter_style.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source.contains('justifyWordSpacing'), isFalse,
          reason: '$path: عادت التوسعة اليدوية للضبط — سطران بعرضين.');
      expect(source.contains('clamp(12.0, 60.0)'), isFalse,
          reason: '$path: حدّ توسعة محلي.');
    }
    final metrics = File('lib/layout/canonical/flutter_text_metrics.dart')
        .readAsStringSync();
    for (final needle in <String>[
      'eligibleForJustification',
      'index < lineMetrics.length - 1',
      'opportunities > 0',
    ]) {
      expect(metrics.contains(needle), isTrue,
          reason: 'قاعدة الضبط الواحدة مفقودة من المحرك: $needle');
    }
  });
}
