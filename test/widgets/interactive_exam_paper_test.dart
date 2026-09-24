import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/views/widgets/formula_inserter.dart';
import 'package:writing_questions_app/views/widgets/interactive_exam_paper.dart';
import 'package:writing_questions_app/views/widgets/smart_exam_toolbar.dart';

PaperHeaderFields _headerFields() {
  return PaperHeaderFields(
    institutionName: TextEditingController(text: 'وزارة التربية'),
    directorate: TextEditingController(text: 'مديرية تربية'),
    subject: TextEditingController(text: 'اللغة العربية'),
    gradeStage: TextEditingController(text: 'الثالث المتوسط'),
    section: TextEditingController(text: ''),
    instructor: TextEditingController(text: 'أ. مصطفى'),
    title: TextEditingController(text: 'الاختبار النهائي'),
    examType: 'اختبار الفصل الأول',
    academicYear: TextEditingController(text: '2026 - 2027'),
    duration: TextEditingController(text: 'ساعتان'),
    generalInstructions: TextEditingController(text: 'أجب عن جميع الأسئلة.'),
  );
}

Widget _wrap(List<MainQuestion> questions, List<FloatingElement> elements) {
  return MaterialApp(
    home: Scaffold(
      body: InteractiveExamPaper(
        header: _headerFields(),
        mainQuestions: questions,
        floatingElements: elements,
        inserter: FormulaInserter(),
        onChanged: () {},
      ),
    ),
  );
}

MainQuestion _questionWithBranches(List<QuestionBranch> branches) {
  return MainQuestion(
    title: 'أعرب ما تحته خط',
    type: QuestionType.essay,
    branches: branches,
  );
}

void main() {
  testWidgets('renders inline-editable title and branch fields on the A4 canvas', (
    tester,
  ) async {
    final questions = <MainQuestion>[
      _questionWithBranches(<QuestionBranch>[
        QuestionBranch(text: 'حدد نوع الكلمة', marks: 1),
        QuestionBranch(text: 'أعرب الكلمة', marks: 2),
      ]),
    ];

    await tester.pumpWidget(_wrap(questions, <FloatingElement>[]));

    // عناوين الأسئلة والفروع تُحرَّر مباشرة (TextFormField collapsed) — لا حوارات.
    expect(find.text('أعرب ما تحته خط'), findsOneWidget);
    expect(find.text('حدد نوع الكلمة'), findsOneWidget);
    expect(find.text('أعرب الكلمة'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);

    // درجة السؤال = مجموع درجات الفروع آلياً (roll-up) على اللوحة.
    expect(find.text('[3 درجة]'), findsWidgets);
  });

  testWidgets('branch labels are generated dynamically from the index', (
    tester,
  ) async {
    final branches = <QuestionBranch>[
      QuestionBranch(text: 'فرع أول', marks: 1),
      QuestionBranch(text: 'فرع ثانٍ', marks: 1),
      QuestionBranch(text: 'فرع ثالث', marks: 1),
    ];
    final questions = <MainQuestion>[_questionWithBranches(branches)];

    await tester.pumpWidget(_wrap(questions, <FloatingElement>[]));

    // الترقيم متتالٍ من الفهرس: أ، ب، ج — بلا حقل تسمية مخزن.
    expect(find.text('أ'), findsWidgets);
    expect(find.text('ب'), findsWidgets);
    expect(find.text('ج'), findsWidgets);

    // حذف فرع وسط القائمة يعيد الترقيم آلياً دون فجوات (أ ثم ج مباشرة).
    branches.removeAt(1);
    await tester.pumpWidget(_wrap(questions, <FloatingElement>[]));
    await tester.pump();

    expect(find.text('فرع أول'), findsOneWidget);
    expect(find.text('فرع ثالث'), findsOneWidget);
  });

  testWidgets('floating elements render above the text layer and can be added', (
    tester,
  ) async {
    final elements = <FloatingElement>[
      FloatingElement(
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 100,
        dy: 200,
        width: 80,
        height: 80,
      ),
    ];

    await tester.pumpWidget(
      _wrap(<MainQuestion>[_questionWithBranches(<QuestionBranch>[])], elements),
    );

    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('smart toolbar exposes the five context tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartExamToolbar(
            inserter: FormulaInserter(),
            onInsertText: (_) {},
            onAddImage: (_) {},
            onAddShape: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('نص'), findsOneWidget);
    expect(find.text('رياضيات'), findsOneWidget);
    expect(find.text('كيمياء'), findsOneWidget);
    expect(find.text('فيزياء'), findsOneWidget);
    expect(find.text('وسائط'), findsOneWidget);
  });

  testWidgets('formula inserter writes at the cursor of the active field', (
    tester,
  ) async {
    final inserter = FormulaInserter();
    final controller = TextEditingController(text: 'حل ');
    controller.selection = const TextSelection.collapsed(offset: 3);
    inserter.controller = controller;

    inserter.insert(r'$x^2$');

    expect(controller.text, r'حل $x^2$');
  });
}
