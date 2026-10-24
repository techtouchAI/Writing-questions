// أزرار التنسيق في المعاينة: هل تعكس **التحديد الحالي** لا نمط العنصر؟
//
// هذا اختبار واجهة حقيقي على `ExamPreviewScreen`: يبني مستندًا فيه كلمة عريضة
// (نطاق تخزين) داخل متن سؤال عادي، ثم يحرّك التحديد داخل حقل التحرير نفسه
// ويقرأ حالة زر «عريض» من شجرة الودجات (تظليل الزر المحدد)، لا من متغيّر
// داخلي ولا من وجود نصّ في الملف.
//
// الحالات المقيسة والانتقال بينها بلا بقايا:
//   ١. تحديد داخل الكلمة العريضة        ⇒ الزر مفعّل.
//   ٢. تحديد داخل الكلمة العادية        ⇒ الزر غير مفعّل (الحالة السابقة لا تبقى).
//   ٣. تحديد يغطي الكلمتين (مختلط)      ⇒ الزر غير مفعّل، لا «مفعّل» كاذبًا.
//   ٤. العودة إلى الكلمة العريضة        ⇒ الزر مفعّل من جديد.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/text_format_span.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

const String _body = 'كلمة أخرى';

ExamDocument _document() => ExamDocument(
      name: 'حالة أزرار التنسيق',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'نص السؤال',
          body: _body,
          // «كلمة» عريضة وحدها؛ «أخرى» تبقى بنمط العنصر.
          bodyFormats: const <TextFormatSpan>[
            TextFormatSpan(start: 0, end: 4, bold: true),
          ],
        ),
      ],
    );

ExamDocument _styledDocument() => ExamDocument(
      name: 'حالة أزرار التنسيق — مائل وتسطير ولون',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'نص السؤال',
          body: _body,
          // «كلمة» مائلة ومسطّرة وملوّنة معًا؛ «أخرى» بنمط العنصر.
          bodyFormats: const <TextFormatSpan>[
            TextFormatSpan(
              start: 0,
              end: 4,
              italic: true,
              underline: true,
              color: 0xFFB91C1C,
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

/// هل زر الشريط ذو التلميح [tooltip] يظهر مفعّلًا (تظليل `selected` في
/// `_ToolButton`)؟ التلميح هو ما يراه المستخدم، فلا يُقاس متغيّر داخلي.
bool _toolSelected(WidgetTester tester, String tooltip) {
  final container = find
      .descendant(of: find.byTooltip(tooltip), matching: find.byType(Container))
      .first;
  return tester.widget<Container>(container).decoration != null;
}

/// لون أيقونة «لون النص» في الشريط: يعكس لون التحديد الحالي (`null` = تلقائي).
Color? _colorTint(WidgetTester tester) =>
    tester.widget<Icon>(find.byIcon(Icons.format_color_text).first).color;

Future<void> _select(
  WidgetTester tester,
  Finder field,
  int start,
  int end,
) async {
  final controller = tester.widget<TextField>(field).controller!;
  controller.selection = TextSelection(baseOffset: start, extentOffset: end);
  await tester.pump();
}

void main() {
  testWidgets('زر العريض يتبع التحديد الفعلي ولا يبقى على حاله', (tester) async {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final field = _field('body-q1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    // التركيز يفعّل الحقل في المعاينة (نفس ما يفعله النقر عليه).
    await tester.tap(field);
    await tester.showKeyboard(field);
    await tester.pumpAndSettle();

    // ١. كل التحديد داخل «كلمة» العريضة.
    await _select(tester, field, 0, 4);
    expect(_toolSelected(tester, 'عريض'), isTrue,
        reason: 'تحديد كلمة عريضة يجب أن يُظهر زر العريض مفعّلًا.');

    // ٢. التحديد انتقل إلى «أخرى» العادية: لا بد أن يزول التفعيل.
    await _select(tester, field, 5, 9);
    expect(_toolSelected(tester, 'عريض'), isFalse,
        reason: 'بقي زر العريض مفعّلًا بعد الانتقال إلى كلمة غير عريضة '
            '(حالة قديمة لم تُنظَّف).');

    // ٣. تحديد مختلط يغطي الكلمتين: لا يدّعي حالة واحدة.
    await _select(tester, field, 0, 9);
    expect(_toolSelected(tester, 'عريض'), isFalse,
        reason: 'التحديد المختلط لا يجوز أن يُظهر زر العريض مفعّلًا.');

    // ٤. العودة إلى الكلمة العريضة.
    await _select(tester, field, 0, 4);
    expect(_toolSelected(tester, 'عريض'), isTrue,
        reason: 'لم يعد الزر مفعّلًا عند العودة إلى الكلمة العريضة.');
  });

  testWidgets('قلب العريض على تحديد جزئي يخصّ الكلمة وحدها', (tester) async {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final field = _field('body-q1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.showKeyboard(field);
    await tester.pumpAndSettle();

    // تحديد «أخرى» ثم قلب العريض عبر callback الشريط نفسه.
    //
    // يُستدعى الـcallback المسجَّل في الشريط مباشرةً بدل النقر على الزر: النقر
    // على عنصر خارج حقل النص في Flutter يُفقد الحقل التركيز، وهو سلوك واجهة لا
    // علاقة له بمنطق التنسيق الذي نقيسه هنا (الحالة ← التحديد ← الحفظ).
    await _select(tester, field, 5, 9);
    tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).onToggleBold();
    await tester.pumpAndSettle();

    final formats = controller.document.questions.single.bodyFormats;
    expect(controller.document.questions.single.body, _body,
        reason: 'قلب التنسيق يجب ألا يغيّر نصّ الحقل.');
    // النطاق القديم («كلمة») باقٍ كما هو، ونطاق جديد على «أخرى» فقط.
    expect(
      formats.where((span) => span.start == 0 && span.end == 4),
      hasLength(1),
      reason: 'تنسيق الكلمة السابقة تغيّر: $formats',
    );
    final applied = formats.where((span) => span.start == 5 && span.end == 9);
    expect(applied, hasLength(1),
        reason: 'التنسيق لم يقع على التحديد نفسه: $formats');
    expect(applied.single.bold, isTrue);
    expect(_toolSelected(tester, 'عريض'), isTrue,
        reason: 'بعد التطبيق يجب أن يعكس الزر حالة التحديد.');
  });

  testWidgets('المائل والتسطير واللون تتبع التحديد نفسه لا نمط العنصر',
      (tester) async {
    final controller = ExamWizardController(document: _styledDocument());
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final field = _field('body-q1');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.showKeyboard(field);
    await tester.pumpAndSettle();

    // ١. داخل الكلمة المنسّقة: الأزرار الثلاثة تعكس النطاق المخزَّن.
    await _select(tester, field, 0, 4);
    expect(_toolSelected(tester, 'مائل'), isTrue,
        reason: 'تحديد كلمة مائلة يجب أن يُظهر زر المائل مفعّلًا.');
    expect(_toolSelected(tester, 'تحته خط'), isTrue,
        reason: 'تحديد كلمة مسطّرة يجب أن يُظهر زر التسطير مفعّلًا.');
    expect(_colorTint(tester), const Color(0xFFB91C1C),
        reason: 'أيقونة اللون يجب أن تعرض لون النطاق المحدَّد.');

    // ٢. الانتقال إلى الكلمة العادية: لا تبقى حالة قديمة على أي زر.
    await _select(tester, field, 5, 9);
    expect(_toolSelected(tester, 'مائل'), isFalse,
        reason: 'بقي زر المائل مفعّلًا بعد الانتقال إلى كلمة عادية.');
    expect(_toolSelected(tester, 'تحته خط'), isFalse,
        reason: 'بقي زر التسطير مفعّلًا بعد الانتقال إلى كلمة عادية.');
    expect(_colorTint(tester), isNull,
        reason: 'بقي لون التحديد السابق على أيقونة اللون.');

    // ٣. تحديد مختلط: لا يدّعي المائل ولا التسطير ولا لونًا واحدًا.
    await _select(tester, field, 0, 9);
    expect(_toolSelected(tester, 'مائل'), isFalse);
    expect(_toolSelected(tester, 'تحته خط'), isFalse);
    expect(_colorTint(tester), isNull,
        reason: 'التحديد المختلط الألوان لا يجوز أن يعرض لونًا واحدًا.');

    // ٤. العودة إلى الكلمة المنسّقة: الحالة تعود كما كانت.
    await _select(tester, field, 0, 4);
    expect(_toolSelected(tester, 'مائل'), isTrue);
    expect(_toolSelected(tester, 'تحته خط'), isTrue);
    expect(_colorTint(tester), const Color(0xFFB91C1C));
  });
}
