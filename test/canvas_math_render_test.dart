import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_competition_app/layout/math_utils.dart';
import 'package:writing_competition_app/models/branch_item.dart';
import 'package:writing_competition_app/models/branch_model.dart';
import 'package:writing_competition_app/models/exam_document.dart';
import 'package:writing_competition_app/models/exam_header.dart';
import 'package:writing_competition_app/models/question_model.dart';
import 'package:writing_competition_app/models/question_type.dart';
import 'package:writing_competition_app/providers/exam_wizard_controller.dart';
import 'package:writing_competition_app/providers/exam_controller.dart';
import 'package:writing_competition_app/providers/settings_controller.dart';
import 'package:writing_competition_app/views/wizard/wizard_canvas_step.dart';
import 'package:writing_competition_app/views/widgets/formula_inserter.dart';
import 'package:writing_competition_app/views/widgets/paper_field.dart';

ExamDocument _document({
  String branchText = 'نص عادي للفرع بلا رموز',
  String promptText = r'المعادلة: s = \sqrt{5} والكسر: \frac{a}{b}',
}) => ExamDocument(
      name: 'اختبار',
      header: ExamHeader(
        ministry: 'وزارة التربية',
        educationBody: 'المديرية العامة',
        school: 'ابتدائية النور',
        grade: 'الخامس',
        subject: 'الرياضيات',
        date: '٢٠٢٦/٩/٢٧',
        timeAllowed: '٩٠ دقيقة',
        totalMarks: '٥٠ درجة',
        teacherName: 'أ. محمد',
        invigilatorName: 'أ. علي',
        notes: 'يمنع استخدام الآلة الحاسبة',
      ),
      questions: [
        QuestionModel(
          id: 'q0',
          type: QuestionType.multipleChoice,
          title: 'السؤال الأول',
          marks: 2,
          prompt: 'نص السؤال الأول: ١ + ١ = ؟',
          options: ['الخيار أ', 'الخيار ب'],
          modelAnswer: 'الخيار أ',
          branches: [],
        ),
        QuestionModel(
          id: 'q1',
          type: QuestionType.trueFalse,
          title: 'السؤال الثاني',
          marks: 3,
          prompt: promptText,
          branches: [
            BranchModel(
              id: 'b1',
              title: 'الفرع أ',
              marks: 2,
              content: branchText,
              items: [
                BranchItem(id: 'b1i1', text: 'نص الفرع الأول'),
                BranchItem(id: 'b1i2', text: 'نص الفرع الثاني'),
              ],
            ),
          ],
        ),
      ],
    );

Widget _shell(ExamDocument document) => CanvasSettingsScope(
      settings: const CanvasSettings(),
      child: MaterialApp(
        home: Scaffold(
          body: WizardCanvasStep(
            controller: ExamWizardController(
              document: document,
              examController: ExamController(),
              settingsController: SettingsController(),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('الحقل الذكي: مصدر المعادلة أثناء التحرير فقط ثم العرض النهائي بعد فقدان التركيز',
      (tester) async {
    await tester.pumpWidget(_shell(_document()));
    await tester.pumpAndSettle();

    // البداية: الحقل غير مركّز ومعادلة داخله → عرض نهائي واحد فقط (بلا معاينة منفصلة).
    expect(find.byType(Math), findsOneWidget);

    final key = const ValueKey<String>('prompt-q1');
    await tester.showKeyboard(key);
    await tester.pump();

    // أثناء التحرير: المصدر كنص عادي (تُخفى الصيغة المُصيَّرة) — لا تكرار للمعاينة.
    expect(find.byType(Math), findsNothing);
    expect(find.textContaining(r'\sqrt'), findsOneWidget);

    await tester.enterText(key, r'المتغيرات: s = \sqrt{5}');
    expect(tester.widget<PaperField>(find.byKey(key)).controller.text,
        r'المتغيرات: s = \sqrt{5}');

    // بعد فقدان التركيز: يظهر العرض النهائي المُصيَّر وحده.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('نص الفرع: العرض النهائي بالرسم المصحفي يبقى في مكانه ولا يتكرر', (tester) async {
    await tester.pumpWidget(
      _shell(_document(
        branchText: 'بسم الله الرحمن الرحيم \\Al{إِنَّا أَنزَلْنَاهُ}',
        promptText: 'سؤال بلا رموز',
      )),
    );
    await tester.pumpAndSettle();

    // العرض النهائي (Text.rich) للنص المرسل وحده — لا حقل تحرير مرئي فوقه.
    expect(find.byType(Text.rich), findsOneWidget);
    expect(find.textContaining(r'\Al'), findsNothing);
  });

  testWidgets('زر المعادلة يدرج المعادلة النهائية كنص جاهز بدون إعادة إدخال الرموز', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      CanvasSettingsScope(
        settings: const CanvasSettings(),
        child: MaterialApp(
          home: Scaffold(
            body: FormulaInserter(
              controller: controller,
              onInsert: () {},
              onEdit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'$\frac{1}{2}$'), findsOneWidget);
    await tester.tap(find.text(r'$\frac{1}{2}$'));
    await tester.pump();
    expect(controller.text, r'$\frac{1}{2}$');
  });
}
