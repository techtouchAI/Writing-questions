import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
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

    testWidgets('text color swatches apply to the current target', (tester) async {
      final controller = ExamWizardController(document: _document());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('لون النص'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('كحلي'));
      await tester.pump();

      expect(controller.document.questions.single.style.color, 0xFF1E3A8A);
      expect(controller.document.questions.single.style.colorHex, '1E3A8A');
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
    testWidgets('drags a shape to a new absolute position', (tester) async {
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

      // السحب بالضغط المطوّل: يفوز بساحة الإيماءات أمام تمرير الصفحة.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FloatingElementView)),
      );
      await tester.pump(kLongPressTimeout);
      await gesture.moveBy(const Offset(30, 12));
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .attachments
          .single;
      expect(moved.dx, greaterThan(0));
      expect(moved.dy, greaterThan(0));
    });
  });
}
