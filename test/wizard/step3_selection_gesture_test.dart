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
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

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
  final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
  return editable.localToGlobal(caret.center + const Offset(1, 0));
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

/// يحرّك الحقل نفسه (آلية المحرّر) ليُظهر [offset] قبل القياس/السحب، فلا يقع
/// طرف الإيماءة خارج منطقة العرض فتُسحب الصفحة بدل تحديد النصّ.
Future<void> _revealOffset(WidgetTester tester, Finder field, int offset) async {
  final state = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  state.bringIntoView(TextPosition(offset: offset));
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

/// مقاطع النصّ التي يرسمها **حقل التحرير نفسه** (`EditableText`)، بأنماطها.
///
/// تُبنى من `TextEditingController.buildTextSpan` — وهي الدالة الوحيدة التي
/// يبني منها `EditableText` ما يرسمه — ويُتحقّق أولاً أن المتحكم المقروء هو
/// متحكم الحقل في الشجرة، فلا يُقاس كائن منفصل عن الواجهة.
List<({String text, bool bold, bool italic, bool underline, Color? color})>
    _renderedRuns(WidgetTester tester, Finder field) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  final controller = _controllerOf(tester, field);
  expect(identical(editable.controller, controller), isTrue,
      reason: 'المتحكم المرسوم ليس متحكم الحقل نفسه — القياس على كائن آخر.');
  final span = editable.controller.buildTextSpan(
    context: tester.element(field),
    style: editable.style,
    withComposing: false,
  );
  final runs =
      <({String text, bool bold, bool italic, bool underline, Color? color})>[];
  void walk(InlineSpan current) {
    if (current is! TextSpan) return;
    final children = current.children;
    if (children == null || children.isEmpty) {
      final text = current.text ?? '';
      if (text.isEmpty) return;
      final style = current.style ?? const TextStyle();
      runs.add((
        text: text,
        bold: style.fontWeight == FontWeight.bold,
        italic: style.fontStyle == FontStyle.italic,
        underline: style.decoration == TextDecoration.underline,
        color: style.color,
      ));
      return;
    }
    for (final child in children) {
      walk(child);
    }
  }

  walk(span);
  return runs;
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
        for (final block in page.blocks)
          for (final line in block.allLines)
            ...line.runs.where(
              (run) => !run.isMath && run.semanticNodeId.startsWith('q1/body'),
            ),
    ];

List<LayoutRun> _runsWithPrefix(LayoutDocument layout, String prefix) =>
    <LayoutRun>[
      for (final page in layout.pages)
        for (final block in page.blocks)
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
    // التحديد الأصلي (native) قد يضمّ فراغاً مجاوراً للكلمة؛ المقياس المهم أن
    // الكلمة نفسها وحدها صارت عريضة، ولا كلمة أخرى معها.
    final runs = _bodyRuns(_layout(controller.document));
    final boldWordRuns = runs
        .where((run) => run.style.bold && run.text.trim().isNotEmpty)
        .toList();
    expect(boldWordRuns, hasLength(1),
        reason: 'التعريض أصاب ${boldWordRuns.length} كلمة: '
            '${runs.map((run) => '"${run.text}"').toList()}');
    expect(boldWordRuns.single.text.trim(), '٢٠');
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
    final underlined = runs.where((run) => run.style.underline).toList();
    expect(underlined.where((run) => run.text.trim().isNotEmpty), isNotEmpty,
        reason: 'التسطير لم يصل إلى أي كلمة في التخطيط: '
            '${runs.map((run) => run.text).toList()}');
    // وكل تسطير واقع داخل النطاق المحدَّد لا خارجه (نصوص الكلمات تسقط داخل
    // نصّ التحديد نفسه).
    final selectedText = selection.textInside(text);
    for (final run in underlined) {
      final word = run.text.trim();
      if (word.isEmpty) {
        continue;
      }
      expect(selectedText, contains(word),
          reason: 'التسطير تسرّب إلى «$word» خارج التحديد «$selectedText».');
    }
  });

  testWidgets('تحديد يعبر أكثر من سطر مرئي: التسطير يصل إلى سطرين',
      (tester) async {
    // متن أطول من سطر واحد في التخطيط القانوني نفسه (لا في الودجة وحدها).
    final controller =
        ExamWizardController(document: _document(body: '$_body $_body'));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final startPoint = _pointAt(tester, field, 0);
    // أول موضع يقع فعلاً على سطر مرئي تالٍ — يُقاس من هندسة الحقل لا يُفترض.
    var endOffset = -1;
    for (var offset = 1; offset < text.length; offset++) {
      if (_pointAt(tester, field, offset).dy > startPoint.dy + 4) {
        endOffset = offset;
        break;
      }
    }
    expect(endOffset, greaterThan(0),
        reason: 'النصّ لم يلتف إلى سطرين في هذه البيئة — القياس بلا عيّنة.');
    // نمتدّ إلى آخر النصّ (مع بقاء البداية على السطر الأول) فيقع النطاق على
    // كل الأسطر المتقاطعة لا على جزء من الثاني.
    endOffset = text.length - 1;
    // يُكشف موضع النهاية بآلية المحرّر نفسها ثم يُعاد قياس الطرفين بعد التمرير.
    await _revealOffset(tester, field, endOffset);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final endPoint = _pointAt(tester, field, endOffset);
    final revealedStart = _pointAt(tester, field, 0);
    expect(endPoint.dy, greaterThan(revealedStart.dy + 4),
        reason: 'نهاية النطاق عادت إلى السطر الأول — لا تحديد متعدد الأسطر.');
    expect(endPoint.dx, inInclusiveRange(0, screen.width));
    expect(endPoint.dy, inInclusiveRange(0, screen.height),
        reason: 'طرف الإيماءة خارج الشاشة ($endPoint في $screen) — السحب لا '
            'يصل إلى آخر النصّ.');

    await _dragSelect(tester, revealedStart, endPoint);
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
        for (final block in page.blocks)
          for (final line in block.allLines)
            if (line.runs.any((run) => run.style.underline)) line.id,
    };
    final layoutDump = <String>[
      'formats=${controller.document.questions.single.bodyFormats}',
      'selection=${selection.start}..${selection.end} len=${text.length}',
      for (final page in layout.pages)
        for (final block in page.blocks)
          if (block.allLines.isNotEmpty)
            '${block.id}: ${block.allLines.map((line) => '${line.id}'
                '[${line.runs.map((run) => '${run.style.underline ? 'U' : '-'}'
                    '${run.text.trim()}').join('|')}]').join(' / ')}',
    ].join('\n');
    expect(underlinedLines.length, greaterThanOrEqualTo(2),
        reason: 'التحديد عبر السطور لم يُسطّر إلا ${underlinedLines.length} '
            'سطراً — النطاق لم يُقس على كل الأسطر المتقاطعة.\n$layoutDump');

    // الحكم الأدق: كل سطر يتقاطع نطاقه المصدري مع التحديد يجب أن يكون مسطَّراً،
    // فلا يكفي «سطران» بينما جزء من النطاق بلا تنسيق.
    final selectedLineIds = <String>{
      for (final page in layout.pages)
        for (final block in page.blocks)
          for (final line in block.allLines)
            if (line.runs.any((run) =>
                run.semanticNodeId.startsWith('q1/body') &&
                run.sourceEndOffset > selection.start &&
                run.sourceStartOffset < selection.end))
              line.id,
    };
    expect(selectedLineIds.length, greaterThanOrEqualTo(2),
        reason: 'التخطيط لا يحمل النطاق المحدَّد على سطرين ($selectedLineIds)'
            '\n$layoutDump');
    expect(underlinedLines, containsAll(selectedLineIds),
        reason: 'أسطر داخل التحديد لم تُسطَّر: '
            '${selectedLineIds.difference(underlinedLines)}\n$layoutDump');
  });

  testWidgets('تحديد السؤال كاملًا: التعريض يشمل المتن ولا يمسّ النقاط',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    await _revealOffset(tester, field, text.length - 1);
    await _dragSelect(
      tester,
      _pointAt(tester, field, 0),
      _pointAt(tester, field, text.length - 1),
    );
    final selection = _controllerOf(tester, field).selection;
    expect(selection.start, 0);
    expect(selection.end, greaterThanOrEqualTo(text.length - 2),
        reason: 'السحب إلى آخر النصّ لم يغطِّ المتن كاملاً '
            '(توقف عند ${selection.end} من ${text.length}).');

    await _tapTool(tester, 'عريض');
    final question = controller.document.questions.single;
    expect(question.bodyFormats.single.start, 0);
    expect(question.bodyFormats.single.end, selection.end);
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
        for (final block in page.blocks)
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

    // النصّ نفسه ما زال قابلًا للاستخراج (لم يُستبدل بصورة) — في أي صفحة.
    final drawnWords = <String>[
      for (var page = 0;
          page < PdfContentProbe.pageCountOf(formatted);
          page++)
        ...PdfContentProbe.fromBytes(formatted, pageIndex: page)
            .words
            .map((word) => word.text),
    ];
    expect(drawnWords, isNotEmpty);
    // قناة القراءة تعطي ترتيب الوحدات البصري داخل الكلمة (كما ترسمها الأسطر)،
    // فالمقارنة تكون مع الكلمة معكوسة — وهو ما يقلبه أي قارئ PDF إلى المنطقي.
    String visual(String logical) =>
        String.fromCharCodes(logical.runes.toList().reversed);
    expect(
      drawnWords.any((word) => word.contains(visual('المعادلات'))),
      isTrue,
      reason: 'الكلمة المنسّقة غابت عن النص المستخرَج: $drawnWords',
    );
  });

  testWidgets('الحقل نفسه يرسم التعريض على الكلمة المحدَّدة وحدها', (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final word = text.indexOf('المعادلات');
    await _doubleTapAt(tester, _pointAt(tester, field, word + 1));
    final selection = _controllerOf(tester, field).selection;

    // قبل التنسيق: لا مقطع عريض في الحقل.
    expect(_renderedRuns(tester, field).where((run) => run.bold), isEmpty,
        reason: 'الحقل يرسم تعريضاً قبل أي تنسيق.');

    await _tapTool(tester, 'عريض');
    final runs = _renderedRuns(tester, field);
    // النصّ المرسوم هو نصّ الحقل نفسه (لا نسخة ثانية ولا حذف محارف).
    expect(runs.map((run) => run.text).join(), text,
        reason: 'مقاطع الرسم لا تعيد بناء نصّ الحقل كما هو.');
    final bold = runs.where((run) => run.bold).toList();
    expect(bold, hasLength(1),
        reason: 'الحقل لم يرسم تعريضاً على مقطع واحد: '
            '${runs.map((run) => '$run.text[bold=$run.bold]').toList()}');
    expect(bold.single.text.trim(), 'المعادلات',
        reason: 'المقطع العريض «${bold.single.text}» ليس الكلمة المحدَّدة.');
    expect(bold.single.text, selection.textInside(text),
        reason: 'مقطع الرسم «${bold.single.text}» يخالف نطاق التحديد '
            '«${selection.textInside(text)}».');
    // والكلمات المجاورة بقيت بلا تعريض.
    for (final run in runs.where((run) => run.text != bold.single.text)) {
      expect(run.bold, isFalse,
          reason: 'التعريض تسرّب إلى «$run.text» في الحقل.');
    }
  });

  testWidgets('الحقل يرسم اللون على نطاق أرقام عربي/لاتيني مختلط وحده',
      (tester) async {
    final controller = ExamWizardController(document: _document(body: _mixed));
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final field = _field('body-q1');
    await _focus(tester, field);

    final text = _controllerOf(tester, field).text;
    final from = text.indexOf('٢٠');
    final to = text.indexOf('2026') + '2026'.length;
    await _dragSelect(
      tester,
      _pointAt(tester, field, from),
      _pointAt(tester, field, to - 1),
    );
    final selection = _controllerOf(tester, field).selection;
    expect(selection.isCollapsed, isFalse);

    await _pickColor(tester, 'خمري');
    final runs = _renderedRuns(tester, field);
    expect(runs.map((run) => run.text).join(), text,
        reason: 'التلوين غيّر نصّ الحقل المرسوم.');
    final colored = runs
        .where((run) => run.color == const Color(0xFFB91C1C))
        .toList();
    expect(colored, isNotEmpty, reason: 'الحقل لم يرسم اللون على أي مقطع.');
    final coloredText = colored.map((run) => run.text).join();
    expect(coloredText.trim(), selection.textInside(text).trim(),
        reason: 'المقطع الملوَّن «$coloredText» يخالف التحديد '
            '«${selection.textInside(text)}».');
    // لا رقم (عربي أو لاتيني) خارج التحديد صُبغ باللون نفسه.
    expect(coloredText, contains('٢٠'));
    expect(coloredText, contains('2026'));
    for (final run in runs.where((run) => run.color == const Color(0xFFB91C1C))) {
      expect(selection.textInside(text), contains(run.text.trim()),
          reason: 'اللون تسرّب إلى «$run.text» خارج التحديد.');
    }
  });
}
