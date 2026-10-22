// الخطوة الثالثة (شاشة المعاينة القابلة للتحرير): **تحديد نصّي حقيقي بالإيماءات**.
//
// لماذا هذا الملف؟ اختبارات `TextFormatSpan` تثبت الجبر، واختبارات التخطيط
// تثبت أن النطاقات تصل إلى الـPDF — لكن أياً منها لا يثبت أن المستخدم يستطيع
// **تحديد نصّه فعلياً** على الورقة. هنا لا يُكتب `controller.selection` يدوياً:
// كل تحديد يقع بإيماءة على الشاشة (نقر مزدوج، ضغط مطوّل، سحب فأرة)، ثم يُنقر
// زر الشريط الحقيقي، ثم يُقاس النموذج والتخطيط وملف PDF.
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/text_format_span.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

import '../pdf_engine/pdf_content_probe.dart';

/// متن طويل يتجاوز سطراً مرئياً في صفحة A4، ويحمل أرقاماً عربية ولاتينية.
const String _body = 'حل المعادلات التالية ثم اكتب الخطوات كاملة في الفراغ '
    'المخصص للحل النهائي مع ذكر القيمة ٢٠ والعدد 2026 في نهاية الحل نفسه';

/// كلمة أولى عادية، وكلمة ثانية تُنسَّق، وكلمة ثالثة تبقى بلا تنسيق.
const String _mixed = 'المعادلات ٢٠ و 2026 والتالية';

ExamDocument _document({String body = _body}) => ExamDocument(
      name: 'تحديد من واجهة الخطوة الثالثة',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'نص السؤال',
          body: body,
          marksOverride: 20,
          items: <BranchItem>[
            BranchItem(
              id: 'i1',
              text: 'النقطة الأولى',
              marks: 5,
              options: <QuestionOption>[
                QuestionOption(text: 'الخيار الأول'),
                QuestionOption(text: 'الخيار الثاني'),
              ],
            ),
          ],
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

Finder _field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    );

TextEditingController _controllerOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!;

RenderEditable _editable(WidgetTester tester, Finder field) {
  final state = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  return state.renderEditable;
}

/// نقطة على الشاشة داخل محرف [offset] في الحقل — تُحسب من هندسة الحقل نفسه
/// (لا إحداثيات ثابتة)، فتعمل مع أي مقاس خط أو التفاف.
Offset _pointAt(WidgetTester tester, Finder field, int offset) {
  final editable = _editable(tester, field);
  final local = editable.getOffsetForCaret(
    TextPosition(offset: offset),
    Rect.zero,
  );
  final lineHeight = editable.preferredLineHeight;
  return editable.localToGlobal(local + Offset(2, lineHeight / 2));
}

Future<void> _focus(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.showKeyboard(field);
  await tester.pumpAndSettle();
}

Future<void> _doubleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

Future<void> _dragSelect(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveTo(to);
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// زر الشريط مفعّل؟ يُقاس من شجرة الودجات (تظليل `selected`) لا من متغيّر.
bool _toolSelected(WidgetTester tester, String tooltip) {
  final container = find
      .descendant(of: find.byTooltip(tooltip), matching: find.byType(Container))
      .first;
  return tester.widget<Container>(container).decoration != null;
}

Future<void> _tapTool(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

Future<void> _pickColor(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.format_color_text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    yield* _allBlocks(block.children);
  }
}

LayoutDocument _layout(ExamDocument document) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: ExamDocumentLayoutAdapter.configurationFor(document),
    fontMetrics: const FlutterTextMetrics(),
  );
}

List<LayoutRun> _bodyRuns(LayoutDocument layout) => <LayoutRun>[
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            ...line.runs.where(
              (run) => !run.isMath && run.semanticNodeId.startsWith('q1/body'),
            ),
    ];

List<LayoutRun> _runsWithPrefix(LayoutDocument layout, String prefix) =>
    <LayoutRun>[
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            ...line.runs.where(
              (run) => !run.isMath && run.semanticNodeId.startsWith(prefix),
            ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  testWidgets('نقر مزدوج على كلمة يحدّدها، والتعريض يصيبها وحدها',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    // «٢٠» كلمة مستقلة في هذا النص (بين فراغين).
    final text = _controllerOf(tester, field).text;
    final start = text.indexOf('٢٠');
    await _doubleTapAt(tester, _pointAt(tester, field, start + 1));
    final selection = _controllerOf(tester, field).selection;
    expect(selection.isCollapsed, isFalse,
        reason: 'النقر المزدوج لم يحدّد أي نصّ — التحديد غير متاح من الواجهة.');
    expect(selection.textInside(text).trim(), '٢٠',
        reason: 'النقر المزدوج حدّد «${selection.textInside(text)}» بدل الكلمة.');

    await _tapTool(tester, 'عريض');
    final formats = controller.document.questions.single.bodyFormats;
    final bold = formats.where((span) => span.bold == true).toList();
    expect(bold, hasLength(1),
        reason: 'التعريض لم يقع على نطاق واحد: $formats');
    expect(bold.single.start, selection.start);
    expect(bold.single.end, selection.end);
    expect(controller.document.questions.single.body, _mixed,
        reason: 'تنسيق تحديد غيّر النص المخزَّن.');

    // النطاق المحدَّد يبقى كما هو بعد تطبيق التنسيق.
    expect(_controllerOf(tester, field).selection, selection,
        reason: 'ضاع التحديد بعد تطبيق التنسيق.');

    // والتخطيط (مصدر المعاينة وPDF معاً) يحمل التعريض على كلمتين رقميتين
    // لا على بقية المتن.
    final runs = _bodyRuns(_layout(controller.document));
    final boldRuns = runs.where((run) => run.style.bold).toList();
    expect(boldRuns, hasLength(1),
        reason: 'التعريض وصل إلى ${boldRuns.length} جرياناً: '
            '${runs.map((run) => '"${run.text}"').toList()}');
    expect(boldRuns.single.text.trim(), '٢٠');
  });

  testWidgets('الضغط المطوّل (موبايل) يحدّد كلمة، والمائل يصيبها وحدها',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final start = text.indexOf('المعادلات');
    await tester.longPressAt(_pointAt(tester, field, start + 2));
    await tester.pumpAndSettle();
    final selection = _controllerOf(tester, field).selection;
    expect(selection.isCollapsed, isFalse,
        reason: 'الضغط المطوّل لم يحدّد نصّاً (سُلِم لإيماءة السحب/الكتلة).');
    expect(selection.textInside(text).trim(), 'المعادلات',
        reason: 'الضغط المطوّل حدّد «${selection.textInside(text)}» بدل الكلمة.');

    await _tapTool(tester, 'مائل');
    final formats = controller.document.questions.single.bodyFormats;
    final italic = formats.where((span) => span.italic == true).toList();
    expect(italic, hasLength(1), reason: 'الميل لم يقع على نطاق واحد: $formats');
    expect(italic.single.start, selection.start);
    expect(italic.single.end, selection.end);
    for (final other in formats.where((span) => span != italic.single)) {
      expect(other.italic, isNot(true),
          reason: 'الميل تسرّب إلى نطاق آخر: $other');
    }
  });

  testWidgets('سحب الفأرة يحدّد جملة، والتسطير لا يتجاوزها', (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final from = text.indexOf('٢٠');
    final to = text.indexOf('والتالية') + 'والتالية'.length;
    await _dragSelect(
      tester,
      _pointAt(tester, field, from),
      _pointAt(tester, field, to - 1),
    );
    final selection = _controllerOf(tester, field).selection;
    expect(selection.isCollapsed, isFalse,
        reason: 'سحب الفأرة لم يحدّد نصّاً (سُلِم لإيماءة أخرى).');
    expect(selection.start, lessThan(selection.end));
    expect(selection.start, from);
    expect(selection.end, greaterThanOrEqualTo(to - 1),
        reason: 'السحب توقّف قبل نهاية النطاق: ${selection.textInside(text)}');

    await _tapTool(tester, 'تحته خط');
    final formats = controller.document.questions.single.bodyFormats;
    final underline = formats.where((span) => span.underline == true).toList();
    expect(underline, hasLength(1), reason: 'التسطير: $formats');
    expect(underline.single.start, selection.start);
    expect(underline.single.end, selection.end);
    final runs = _bodyRuns(_layout(controller.document));
    expect(runs.where((run) => run.style.underline), hasLength(1),
        reason: 'التسطير لم يصل إلى جريان واحد في التخطيط: '
            '${runs.map((run) => run.text).toList()}');
  });

  testWidgets('تحديد يعبر أكثر من سطر مرئي: التسطير يصل إلى سطرين',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final startPoint = _pointAt(tester, field, 0);
    final endPoint = _pointAt(tester, field, text.length - 1);
    expect(endPoint.dy, greaterThan(startPoint.dy + 4),
        reason: 'النصّ لم يلتف إلى سطرين في هذه البيئة — القياس بلا عيّنة '
            '(نقطتان على السطر نفسه: $startPoint / $endPoint).');

    await _dragSelect(tester, startPoint, endPoint);
    final selection = _controllerOf(tester, field).selection;
    expect(selection.isCollapsed, isFalse);
    expect(selection.end - selection.start, greaterThan(20),
        reason: 'التحديد عبر السطور قصير جداً: '
            '«${selection.textInside(text)}»');

    await _tapTool(tester, 'تحته خط');
    final layout = _layout(controller.document);
    final runs = _bodyRuns(layout).where((run) => run.style.underline);
    expect(runs, isNotEmpty, reason: 'التسطير لم يصل إلى التخطيط.');
    final underlinedLines = <String>{
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            if (line.runs.any((run) => run.style.underline)) line.id,
    };
    expect(underlinedLines.length, greaterThanOrEqualTo(2),
        reason: 'التحديد عبر السطور لم يُسطّر إلا ${underlinedLines.length} '
            'سطراً — النطاق لم يُقس على كل الأسطر المتقاطعة.');
  });

  testWidgets('تحديد السؤال كاملًا: التعريض يشمل المتن ولا يمسّ النقاط',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    await _dragSelect(
      tester,
      _pointAt(tester, field, 0),
      _pointAt(tester, field, text.length - 1),
    );
    final selection = _controllerOf(tester, field).selection;
    expect(selection.start, 0);
    expect(selection.end, greaterThanOrEqualTo(text.length - 1));

    await _tapTool(tester, 'عريض');
    final question = controller.document.questions.single;
    expect(question.bodyFormats.single.start, 0);
    expect(question.bodyFormats.single.end, text.length);
    expect(question.statementFormats, isEmpty,
        reason: 'تنسيق المتن تسرّب إلى منطوق السؤال.');
    expect(question.items.single.textFormats, isEmpty,
        reason: 'تنسيق المتن تسرّب إلى نصّ النقطة.');
    expect(question.items.single.options[0].formats, isEmpty,
        reason: 'تنسيق المتن تسرّب إلى الخيار.');
    expect(question.statement, 'نص السؤال');
  });

  testWidgets('لون نطاق رقمي مختلط، ثم انتقال التحديد يحدّث حالة الأزرار',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final digits = text.indexOf('2026');
    await _dragSelect(
      tester,
      _pointAt(tester, field, digits),
      _pointAt(tester, field, digits + 3),
    );
    await _pickColor(tester, 'خمري');

    final question = controller.document.questions.single;
    final colored = question.bodyFormats
        .where((span) => span.color == 0xFFB91C1C)
        .toList();
    expect(colored, hasLength(1), reason: 'اللون: ${question.bodyFormats}');
    expect(colored.single.start, greaterThanOrEqualTo(digits));
    expect(colored.single.end, lessThanOrEqualTo(digits + 4));
    expect(question.body, _mixed, reason: 'تطبيق اللون غيّر النص.');

    // حالة الشريط تعكس النطاق: لون ظاهر على أيقونة اللون داخل النطاق.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.format_color_text).first).color,
      const Color(0xFFB91C1C),
      reason: 'أيقونة اللون لا تعكس لون التحديد.',
    );

    // الانتقال إلى كلمة بلا تنسيق: لا تبقى حالة قديمة.
    final other = text.indexOf('والتالية');
    await _doubleTapAt(tester, _pointAt(tester, field, other + 1));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.format_color_text).first).color,
      isNull,
      reason: 'بقي لون التحديد السابق بعد الانتقال إلى كلمة أخرى.',
    );
    expect(_toolSelected(tester, 'عريض'), isFalse);
  });

  testWidgets('المحاذاة من التحديد تخصّ فقرة الحقل ولا تمسّ غيرها',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    await _doubleTapAt(tester, _pointAt(tester, field, text.indexOf('٢٠') + 1));
    await _tapTool(tester, 'توسيط');

    final question = controller.document.questions.single;
    expect(question.bodyAlign, PaperAlign.center,
        reason: 'المحاذاة لم تُكتب في فقرة الحقل المحدَّد.');
    expect(question.titleAlign ?? question.style.align, isNot(PaperAlign.center),
        reason: 'محاذاة المتن غيّرت محاذاة عنوان السؤال.');
    expect(controller.document.header, isNotNull);

    final layout = _layout(controller.document);
    final bodyLines = <PaperAlign?>[
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            if (line.runs.any((run) => run.semanticNodeId.startsWith('q1/body')))
              line.alignment,
    ];
    expect(bodyLines, isNotEmpty);
    expect(bodyLines.every((align) => align == PaperAlign.center), isTrue,
        reason: 'أسطر المتن لم تُوسَّط في التخطيط: $bodyLines');
    expect(
      _runsWithPrefix(layout, 'q1/title')
          .any((run) => run.semanticNodeId.startsWith('q1/title')),
      isTrue,
    );
  });

  testWidgets('الحفظ وإعادة الفتح: التنسيق باقٍ على النطاق نفسه',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final word = text.indexOf('المعادلات');
    await _doubleTapAt(tester, _pointAt(tester, field, word + 1));
    await _tapTool(tester, 'عريض');

    final saved = ExamDocument.fromMap(controller.document.toMap());
    expect(saved.questions.single.bodyFormats,
        controller.document.questions.single.bodyFormats);

    // إعادة الفتح في شاشة جديدة: الحقل يعرض النص نفسه، والتخطيط يحمل النطاق.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reopened = ExamWizardController(document: saved);
    addTearDown(reopened.dispose);
    await _pump(tester, reopened);
    final reopenedField = _field('body-q1');
    await tester.ensureVisible(reopenedField);
    await tester.pumpAndSettle();
    expect(_controllerOf(tester, reopenedField).text, _mixed);
    final runs = _bodyRuns(_layout(reopened.document));
    final bold = runs.where((run) => run.style.bold).toList();
    expect(bold, hasLength(1),
        reason: 'التنسيق لم يصل بعد إعادة التحميل: '
            '${runs.map((run) => '"${run.text}" bold=${run.style.bold}').toList()}');
    expect(bold.single.text.trim(), 'المعادلات');
  });

  testWidgets('PDF: الكلمة المحدَّدة بالإيماءة وحدها عريضة بعد التصدير',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final word = text.indexOf('المعادلات');
    await _doubleTapAt(tester, _pointAt(tester, field, word + 1));
    await _tapTool(tester, 'عريض');

    final fonts = await ExamFonts.load();
    final plain = await PaginatedPdfExamEngine()
        .generate(document: _document(body: _mixed), fonts: fonts);
    final formatted = await PaginatedPdfExamEngine()
        .generate(document: controller.document, fonts: fonts);

    int boldWords(Uint8List bytes) {
      final probe = PdfContentProbe.fromBytes(bytes, pageIndex: 0);
      return probe.words
          .where((word) => word.baseFont.toUpperCase().contains('BOLD'))
          .length;
    }

    expect(boldWords(formatted), boldWords(plain) + 1,
        reason: 'عدد الكلمات العريضة في PDF لم يزد كلمة واحدة: '
            '${boldWords(plain)} ← ${boldWords(formatted)}');

    // النصّ نفسه ما زال قابلًا للاستخراج (لم يُستبدل بصورة).
    final probe = PdfContentProbe.fromBytes(formatted, pageIndex: 0);
    expect(probe.words, isNotEmpty);
    expect(
      probe.words.any((word) => word.text.contains('المعادلات')),
      isTrue,
      reason: 'الكلمة المنسّقة غابت عن النص المستخرَج: '
          '${probe.words.map((word) => word.text).toList()}',
    );
  });
}
