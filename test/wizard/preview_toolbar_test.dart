import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/widgets/floating_element_view.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _document() {
  return ExamDocument(
    name: 'شريط',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        prompt: 'نص السؤال',
        branches: <BranchModel>[
          BranchModel(
            id: 'q1a',
            content: BranchContent(
              type: QuestionType.multipleChoice,
              text: 'اختر الإجابة',
              options: <QuestionOption>[
                QuestionOption(text: 'الأول', isCorrect: true),
                QuestionOption(text: 'الثاني'),
              ],
            ),
            marks: 2,
          ),
        ],
      ),
    ],
  );
}

Widget _preview(ExamWizardController controller) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
}

Future<void> _pumpPreview(WidgetTester tester, ExamWizardController controller) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_preview(controller));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('PreviewToolbar formatting', () {
    testWidgets('center keeps the current zoom level', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byTooltip('تكبير'));
      await tester.pump();
      expect(find.text('120%'), findsOneWidget);

      // التوسيط يعيد التمرير فقط — الزوم يبقى 120%.
      await tester.tap(find.byTooltip('توسيط الورقة'));
      await tester.pump();
      expect(find.text('120%'), findsOneWidget);
    });

    testWidgets('line-spacing presets apply to the current target', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('تباعد الأسطر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5').last);
      await tester.pump();

      expect(controller.document.questions.single.style.lineHeight, 1.5);
    });

    testWidgets('color swatches change only the question title color', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(null);
      controller.selectQuestion(0);
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('لون عنوان السؤال'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('كحلي'));
      await tester.pump();

      final question = controller.document.questions.single;
      expect(question.titleColor, 0xFF1E3A8A);
      expect(question.effectiveTitleColor, 0xFF1E3A8A);
      expect(question.style.color, isNull);
      expect(question.style.colorHex, isNull);
    });

    testWidgets('paragraph spacing preset is independent from line height', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('المسافة بين الفقرات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 بكسل').last);
      await tester.pump();

      final style = controller.document.questions.single.style;
      expect(style.paragraphSpacing, 8);
      expect(style.lineHeight, isNull);
    });

    testWidgets('alignment buttons apply to the current target', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('توسيط'));
      await tester.pump();

      expect(
        controller.document.questions.single.style.align,
        PaperAlign.center,
      );
    });
  });

  group('Preview flexible labels', () {
    testWidgets('edits an option label through its dialog', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.text('( أ )'));
      await tester.pumpAndSettle();
      expect(find.text('تسمية الخيار'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'B.');
      await tester.tap(find.text('حفظ'));
      // خروج الحوار متحرك — ننتظر اكتماله حتى لا يُحتسب نصه مع التسمية.
      await tester.pumpAndSettle();

      final options = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .content
          .options;
      expect(options[0].labelOverride, 'B.');
      expect(find.text('B.'), findsOneWidget);
      // الشقيق الثاني بقي تلقائياً بفهرسه الأصلي.
      expect(find.text('( ب )'), findsOneWidget);
    });

    testWidgets('deletes the last branch and shows the empty hint', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('حذف الفرع'));
      await tester.pump();

      expect(controller.document.questions.single.branches, isEmpty);
      expect(find.textContaining('لا فروع بعد'), findsOneWidget);
    });
  });

  group('Preview floating shapes', () {
    testWidgets('يُسحَب الشكل مباشرةً بلا ضغط مطوّل', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 0,
          dy: 0,
          width: 60,
          height: 60,
        ),
      );
      await _pumpPreview(tester, controller);
      expect(find.byType(FloatingElementView), findsOneWidget);

      // لا ضغط مطوّل ولا تحديد مسبق: العنصر يتبع الإصبع فورًا.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FloatingElementView)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(30, 12));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .attachments
          .single;
      // التكبير 100% في هذا المحيط ⇒ بكسل الشاشة = بكسل اللوحة.
      // و`dx` يُقاس من حافة القراءة: في ورقة عربية (RTL) السحب يميناً
      // يُنقص dx — والحركة تبقى مطابقة للإصبع.
      final expectedDx = controller.document.layout.isLtr ? 30.0 : -30.0;
      expect(moved.dx, closeTo(expectedDx, 0.5));
      expect(moved.dy, closeTo(12, 0.5));
    });

    testWidgets('مربع النص يُسحَب مباشرةً بلا تحديد مسبق ولا ضغط مطوّل', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          dx: 0,
          dy: 0,
          width: 120,
          height: 60,
        ),
      );
      await _pumpPreview(tester, controller);

      // لا تحديد مسبق: اللمس والإمساك يكفي — وهو ما كان يجعل المربع يبدو
      // ثابتًا حين كان التحريك يتطلب ضغطًا مطوّلًا أو تحديدًا سابقًا.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FloatingElementView)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 24));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .attachments
          .single;
      // التكبير 100% في هذا المحيط ⇒ بكسل الشاشة = بكسل اللوحة.
      final expectedDx = controller.document.layout.isLtr ? 40.0 : -40.0;
      expect(moved.dx, closeTo(expectedDx, 0.5));
      expect(moved.dy, closeTo(24, 0.5));
    });

    testWidgets('نقرة واحدة على العنصر تُحدّده وتُظهر مقابضه', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          label: 'ملاحظة للمصحح',
          dx: 0,
          dy: 0,
          width: 120,
          height: 60,
        ),
      );
      await _pumpPreview(tester, controller);

      // مقبض التحرير (12×12) يظهر مع التحديد وحده.
      final editHandle = find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.edit && widget.size == 12.0,
      );
      expect(editHandle, findsNothing);

      await tester.tap(find.byType(FloatingElementView));
      await tester.pump();

      // النقرة تصل عبر مسار السحب المباشر (الفوز الفوري بساحة الإيماءات)
      // فتحدّد العنصر بنفسها بلا الحاجة إلى GestureDetector الأب.
      expect(editHandle, findsOneWidget);
    });

    testWidgets('المعادلة الحرة تُرسم معادلةً وتُسحب إلى أي موضع بلا قيود', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      // معادلة في أسفل الورقة (خارج نطاق كتل السؤال) — الموضع حرّ تماماً.
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.formula,
          label: r'\frac{a}{b}',
          dx: 120,
          dy: 900,
          width: 170,
          height: 80,
        ),
      );
      await _pumpPreview(tester, controller);
      // شباك أطول ليبقى أسفل الورقة ظاهراً في هذا المحيط.
      tester.view.physicalSize = const Size(1000, 2600);
      await tester.pump();

      // تُرسم معادلةً (Math) لا نصًّا خامًا.
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$\frac{a}{b}$'), findsNothing);

      // السحب من أي نقطة داخل مستطيلها، وبلا ضغط مطوّل.
      final formula = find.byType(FloatingElementView);
      expect(formula, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(formula));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .attachments
          .single;
      // تحرّكت للأعلى 60 بكسل مع بقاء الإحداثي الأفقي.
      expect(moved.dy, closeTo(840, 0.5));
      expect(moved.dx, closeTo(120, 0.5));
    });

    testWidgets('التحريك بلا قيود: العنصر يخرج عن مساحة الطباعة ولا يُقصّ', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 0,
          dy: 0,
          width: 80,
          height: 80,
        ),
      );
      await _pumpPreview(tester, controller);

      // سحب كبير نحو الأسفل يتجاوز ارتفاع مساحة الطباعة ويخرج عن الهامش.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FloatingElementView)),
      );
      await tester.pump();
      for (var step = 0; step < 16; step++) {
        await gesture.moveBy(const Offset(30, 90));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .attachments
          .single;
      // كان الحدّ القديم هو ارتفاع مساحة الطباعة (‎١٠٤٠‎ بكسل تقريبًا)؛ الآن
      // الموضع حرّ ويتوقف فقط عند بقاء مقبض إمساك داخل الورقة.
      expect(moved.dy, greaterThan(1040));
      expect(moved.dy, lessThanOrEqualTo(ExamCanvasGeometry.height - 24));
    });

    testWidgets('صيغة مربع النص تُعرض معادلةً لا كوداً خاماً', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          label: r'الناتج: $x^2$',
          dx: 0,
          dy: 0,
          width: 160,
          height: 60,
        ),
      );
      await _pumpPreview(tester, controller);

      // المعادلة مرسومة عبر [TexText] (Math من flutter_math_fork) — ودون
      // أن يظهر نص الصيغة الخام في أي مكان على الورقة.
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$x^2$'), findsNothing);
    });

    testWidgets('النقر المزدوج على مربع النص يفتح محرّره', (tester) async {
      final controller = ExamWizardController(document: _document());
      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          label: 'ملاحظة للمصحح',
          dx: 0,
          dy: 0,
          width: 120,
          height: 60,
        ),
      );
      await _pumpPreview(tester, controller);

      // النقرة الأولى تحدّد المربع، والثانية تُكمل «النقر المزدوج» — وهو
      // سلوك محفوظ يدويًّا لأن السحب الفوري يفوز بساحة الإيماءات.
      await tester.tap(find.byType(FloatingElementView));
      await tester.pump();
      await tester.tap(find.byType(FloatingElementView));
      await tester.pumpAndSettle();

      // حوار تحرير مربع النص (عنوانه «مربع نص») — لا شريحة التحديد في الشريط.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('مربع نص'),
        ),
        findsOneWidget,
      );
      expect(find.text('ملاحظة للمصحح'), findsWidgets);
    });
  });
}
