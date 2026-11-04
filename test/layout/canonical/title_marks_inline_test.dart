// بوابة عقد سطر العنوان: الدرجة **داخل فقرة المنطوق** لا صندوقًا على حافة الصفّ.
//
// ما تقيسه هذه البوابة على سطح الإنتاج نفسه (`ExamPreviewScreen` كما يُنشأ في
// الإنتاج، بلا محوّل canonical):
//   * الدرجة تُرسم داخل فقرة الحقل نفسه (لا `TextField` منفصل ولا ودجة بجانبه).
//   * بينها وبين المنطوق `U+00A0` واحد، كما في `LayoutEngine._titleBlock`.
//   * حين يلتفّ المنطوق على أكثر من سطر تقع الدرجة على **السطر الأخير**.
//   * ملاصقتها للمحرف الذي قبلها تقع داخل 0.75pt (نفس تفاوت بوابة الحقل).
//   * أداة تحرير الدرجة موجودة خارج الورقة (شريط السؤال) بعد نقلها.
//
// المصدر: `lib/views/wizard/exam_preview_screen.dart` (`_titleRow`,
// `_trailingTitleContent`, `_paperField`) و`lib/views/widgets/paper_field.dart`
// (`renderWhenNotRich`).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// التفاوت الموثَّق (pt) لملاصقة الدرجة للمحرف الذي قبلها.
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

RichText _titleParagraph(WidgetTester tester) {
  final paragraph = find
      .descendant(of: _titleField(), matching: find.byType(RichText))
      .evaluate()
      .map((element) => element.widget)
      .whereType<RichText>()
      .where((widget) => widget.text.toPlainText().contains('درجة'))
      .toList(growable: false);
  expect(paragraph, hasLength(1),
      reason: 'لم تُرسم الدرجة داخل فقرة المنطوق: '
          'إما أنها عادت ودجةً مستقلة، أو أن الحقل لم يُرسم من renderBuilder.');
  return paragraph.single;
}

void main() {
  testWidgets('الدرجة داخل فقرة المنطوق بعد U+00A0 وعلى السطر الأخير',
      (tester) async {
    await _pump(tester, _document());

    // 1) الحقل نفسه لم يعد TextField في وضع العرض: الفقرة هي الراسم.
    expect(
      find.descendant(of: _titleField(), matching: find.byType(TextField)),
      findsNothing,
      reason: 'الحقل ما زال TextField، فالدرجة لم تُدمج في نصّه.',
    );

    final richText = _titleParagraph(tester);
    final render = tester.renderObject<RenderParagraph>(find.byWidget(richText));
    final plain = richText.text.toPlainText();

    // 2) المحرف الواصل U+00A0 موجود قبل الدرجة مباشرة.
    final marksNameIndex = plain.indexOf('درجة');
    expect(marksNameIndex, greaterThan(0), reason: 'لا نصّ للدرجة في الفقرة.');
    final openIndex = plain.lastIndexOf('(', marksNameIndex);
    expect(openIndex, greaterThan(0), reason: 'لا قوس افتتاح لمجموعة الدرجة.');
    final nbspIndex = plain.lastIndexOf('\u00A0', openIndex);
    expect(nbspIndex, greaterThan(0),
        reason: 'لا فاصل U+00A0 قبل الدرجة (عقد المحرك: NBSP لا SizedBox).');
    expect(plain.substring(nbspIndex + 1, openIndex).trim(), isEmpty,
        reason: 'بين U+00A0 والدرجة محتوى غير متوقّع.');

    // 3) الأسطر: المنطوق الطويل يلتفّ، والدرجة تقع على السطر الأخير.
    final allBoxes = render.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length),
    );
    expect(allBoxes, isNotEmpty, reason: 'لا صناديق نصّ: القياس بلا عيّنة.');
    final lineTops = <double>[];
    for (final box in allBoxes) {
      if (lineTops.every((top) => (top - box.top).abs() > _kLineTolerancePt)) {
        lineTops.add(box.top);
      }
    }
    expect(lineTops.length, greaterThanOrEqualTo(2),
        reason: 'المنطوق لم يلتفّ: الحالة لا تقيس «السطر الأخير».');
    final lastLineTop = lineTops.reduce((a, b) => a > b ? a : b);

    final marksBoxes = render.getBoxesForSelection(
      TextSelection(baseOffset: openIndex, extentOffset: plain.length),
    );
    expect(marksBoxes, isNotEmpty, reason: 'لا صندوق لمجموعة الدرجة.');
    for (final box in marksBoxes) {
      expect((box.top - lastLineTop).abs(), lessThanOrEqualTo(_kLineTolerancePt),
          reason: 'الدرجة ليست على السطر الأخير (top=${box.top}, '
              'lastLineTop=$lastLineTop).');
    }

    // 4) الملاصقة: بين الدرجة والمحرف الذي قبلها عرض U+00A0 نفسه، لا صفّ كامل.
    final nbspBoxes = render.getBoxesForSelection(
      TextSelection(baseOffset: nbspIndex, extentOffset: nbspIndex + 1),
    );
    expect(nbspBoxes, hasLength(1), reason: 'U+00A0 ليس محرفًا واحدًا.');
    final nbspBox = nbspBoxes.single;
    final marksEdge = marksBoxes
        .map((box) => render.textDirection == TextDirection.rtl
            ? box.right
            : box.left)
        .reduce((a, b) => a > b ? a : b);
    final nbspEdge = render.textDirection == TextDirection.rtl
        ? nbspBox.left
        : nbspBox.right;
    expect((marksEdge - nbspEdge).abs(), lessThanOrEqualTo(_kAdjacencyTolerancePt),
        reason: 'المسافة بين الدرجة والفاصل ${(marksEdge - nbspEdge).abs()}pt '
            'تتجاوز $_kAdjacencyTolerancePt pt.');
  });

  testWidgets('أداة تحرير الدرجة في الشريط خارج الورقة', (tester) async {
    await _pump(tester, _document());

    expect(find.byKey(const ValueKey<String>('question-action-marks')), findsOneWidget,
        reason: 'لا أداة لتحرير درجة السؤال بعد نقلها خارج الورقة.');

    // لا تبقى أداة تحرير داخل الورقة: لا نصّ «+ درجة» ولا ودجة قابلة للنقر
    // على حافة صفّ العنوان.
    expect(find.text('+ درجة'), findsNothing,
        reason: '«+ درجة» ما زالت تُرسم داخل مساحة الورقة.');
  });

  testWidgets('سؤال بلا درجة لا يُلحق بفقرة العنوان شيئًا', (tester) async {
    await _pump(tester, _document(marksOverride: null));

    final richText = find
        .descendant(of: _titleField(), matching: find.byType(RichText))
        .evaluate()
        .map((element) => element.widget)
        .whereType<RichText>()
        .toList(growable: false);
    for (final widget in richText) {
      expect(widget.text.toPlainText().contains('درجة'), isFalse,
          reason: 'سؤال بلا درجة رسم درجةً في فقرته.');
    }
  });
}
