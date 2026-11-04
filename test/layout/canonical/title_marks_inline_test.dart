// بوابة عقد سطر العنوان: الدرجة **داخل فقرة المنطوق** لا صندوقًا على حافة الصفّ.
//
// ما تقيسه هذه البوابة على سطح الإنتاج نفسه (`ExamPreviewScreen` كما يُنشأ في
// الإنتاج، بلا محوّل canonical):
//   * الدرجة تُرسم داخل نصّ الحقل نفسه (شجرة `buildTextSpan`)، لا ودجة بجانبه.
//   * بينها وبين المنطوق `U+00A0` واحد، كما في `LayoutEngine._titleBlock`.
//   * حين يلتفّ المنطوق على أكثر من سطر تقع الدرجة على **السطر الأخير**.
//   * ملاصقتها للفاصل تقع داخل 0.75pt (نفس تفاوت بوابة هندسة الحقل).
//   * الدرجة ليست جزءًا من نصّ المتحكم: لا تدخل `text` ولا التحديد، فلا تمسّ
//     التحرير ولا الإدخال.
//   * أداة تحرير الدرجة موجودة خارج الورقة (شريط السؤال) بعد نقلها.
//
// القياس: شجرة الأسطر نفسها التي رسمها `RenderEditable`
// (`EditableText.renderEditable.text`) تُخطَّط بـ`TextPainter` بالعرض والنمط
// والاتجاه أنفسهم، فالصناديق المقيسة هي صناديق الرسم لا محاكاة له.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// التفاوت الموثَّق (pt) لملاصقة الدرجة للفاصل الذي قبلها.
const double _kAdjacencyTolerancePt = 0.75;

/// التفاوت الرأسي (pt) لاعتبار صندوقين على السطر نفسه.
const double _kLineTolerancePt = 1.0;

/// منطوق طويل يلتفّ حتمًا على أكثر من سطر داخل عمود الورقة.
const String _longStatement =
    'أوجد قيمة المتغير في المعادلة التالية ثم بيّن أثر التشكيل على قراءة '
    'النص العربي في الفقرة التي تليها مباشرة مع ذكر الخطوات كاملة وبلا إيجاز.';

ExamDocument _document({double? marksOverride = 10}) => ExamDocument(
      name: 'سطر العنوان والدرجة',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: _longStatement,
          marksOverride: marksOverride,
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, ExamDocument document) async {
  tester.view.physicalSize = const Size(1600, 2600);
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
}

Finder _titleField() => find.byKey(const ValueKey<String>('statement-q1'));

Finder _titleEditable() =>
    find.descendant(of: _titleField(), matching: find.byType(EditableText));

RenderEditable _renderEditable(WidgetTester tester) =>
    tester.state<EditableTextState>(_titleEditable()).renderEditable;

/// تخطيط شجرة الأسطر المرسومة فعلاً بالعرض والاتجاه أنفسهما.
TextPainter _paint(RenderEditable editable) {
  final painter = TextPainter(
    text: editable.text,
    textDirection: editable.textDirection,
    textAlign: editable.textAlign,
  )..layout(maxWidth: editable.size.width);
  return painter;
}

List<double> _lineTops(TextPainter painter, int length) {
  final tops = <double>[];
  for (final box in painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  )) {
    if (tops.every((top) => (top - box.top).abs() > _kLineTolerancePt)) {
      tops.add(box.top);
    }
  }
  return tops;
}

void main() {
  testWidgets('الدرجة داخل نصّ الفقرة بعد U+00A0 وعلى السطر الأخير',
      (tester) async {
    await _pump(tester, _document());

    // 1) الحقل بقي قابلاً للتحرير: الدرجة لم تحوّله إلى عرض ثابت.
    expect(_titleEditable(), findsOneWidget,
        reason: 'الحقل ليس TextField: التحرير المباشر فُقد.');

    // 2) الدرجة ليست في نصّ المتحكم: رسم فقط، لا محتوى ولا تحديد.
    final controllerText = tester
        .widget<TextField>(find.descendant(
            of: _titleField(), matching: find.byType(TextField)))
        .controller!
        .text;
    expect(controllerText.contains('درجة'), isFalse,
        reason: 'الدرجة دخلت نصّ الحقل القابل للتحرير.');

    // 3) لكنها في الشجرة المرسومة بعد U+00A0.
    final editable = _renderEditable(tester);
    final painter = _paint(editable);
    final plain = painter.text!.toPlainText();
    expect(plain.contains('درجة'), isTrue,
        reason: 'الدرجة غير مرسومة في فقرة الحقل.');
    final marksNameIndex = plain.indexOf('درجة');
    final openIndex = plain.lastIndexOf('(', marksNameIndex);
    expect(openIndex, greaterThan(0), reason: 'لا قوس افتتاح لمجموعة الدرجة.');
    final nbspIndex = plain.lastIndexOf('\u00A0', openIndex);
    expect(nbspIndex, greaterThan(0),
        reason: 'لا فاصل U+00A0 قبل الدرجة (عقد المحرك: NBSP لا SizedBox).');
    expect(plain.substring(nbspIndex + 1, openIndex).trim(), isEmpty,
        reason: 'بين U+00A0 والدرجة محتوى غير متوقّع.');

    // 4) الأسطر: المنطوق الطويل يلتفّ، والدرجة على السطر الأخير.
    final tops = _lineTops(painter, plain.length);
    expect(tops.length, greaterThanOrEqualTo(2),
        reason: 'المنطوق لم يلتفّ: الحالة لا تقيس «السطر الأخير».');
    final lastLineTop = tops.reduce((a, b) => a > b ? a : b);
    final marksBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: openIndex, extentOffset: plain.length),
    );
    expect(marksBoxes, isNotEmpty, reason: 'لا صندوق لمجموعة الدرجة.');
    for (final box in marksBoxes) {
      expect((box.top - lastLineTop).abs(), lessThanOrEqualTo(_kLineTolerancePt),
          reason: 'الدرجة ليست على السطر الأخير '
              '(top=${box.top}, lastLineTop=$lastLineTop).');
    }

    // 5) الملاصقة: عرض U+00A0 نفسه لا صفّ كامل.
    final nbspBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: nbspIndex, extentOffset: nbspIndex + 1),
    );
    expect(nbspBoxes, hasLength(1), reason: 'U+00A0 ليس محرفًا واحدًا.');
    final rtl = painter.textDirection == TextDirection.rtl;
    final marksEdge = marksBoxes
        .map((box) => rtl ? box.right : box.left)
        .reduce((a, b) => a > b ? a : b);
    final nbspEdge = rtl ? nbspBoxes.single.left : nbspBoxes.single.right;
    expect((marksEdge - nbspEdge).abs(), lessThanOrEqualTo(_kAdjacencyTolerancePt),
        reason: 'المسافة بين الدرجة والفاصل ${(marksEdge - nbspEdge).abs()}pt '
            'تتجاوز $_kAdjacencyTolerancePt pt.');
  });

  testWidgets('أداة تحرير الدرجة في الشريط خارج الورقة', (tester) async {
    await _pump(tester, _document());

    expect(find.byKey(const ValueKey<String>('question-action-marks')), findsOneWidget,
        reason: 'لا أداة لتحرير درجة السؤال بعد نقلها خارج الورقة.');
    expect(find.text('+ درجة'), findsNothing,
        reason: '«+ درجة» ما زالت تُرسم داخل مساحة الورقة.');
  });

  testWidgets('سؤال بلا درجة لا يُلحق بفقرة العنوان شيئًا', (tester) async {
    await _pump(tester, _document(marksOverride: null));

    final editable = _renderEditable(tester);
    expect(editable.text!.toPlainText().contains('درجة'), isFalse,
        reason: 'سؤال بلا درجة رسم درجةً في فقرته.');
  });
}
