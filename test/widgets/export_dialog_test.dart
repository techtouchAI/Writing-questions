import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/views/widgets/export_dialog.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Builder(builder: (context) => child)),
  );
}

MainQuestion _sampleQuestion() {
  return MainQuestion(
    title: 'ما هي عاصمة العراق؟',
    type: QuestionType.multipleChoice,
    options: <QuestionOption>[
      QuestionOption(text: 'بغداد', isCorrect: true),
      QuestionOption(text: 'البصرة'),
    ],
  );
}

void main() {
  testWidgets('exam export offers only PDF versions (Word/Excel frozen)', (
    tester,
  ) async {
    final exam = Exam(
      name: 'اختبار رسمي',
      header: ExamHeader(),
      mainQuestions: [_sampleQuestion()],
    );

    await tester.pumpWidget(_wrap(ExportDialog(exam: exam)));
    await tester.pumpAndSettle();

    expect(find.text('PDF — ورقة الطالب'), findsOneWidget);
    expect(find.text('PDF — نموذج الإجابة للمعلم'), findsOneWidget);
    expect(find.textContaining('.docx'), findsNothing, reason: 'Word مجمّد للامتحانات');
    expect(find.textContaining('.xlsx'), findsNothing, reason: 'Excel مجمّد للامتحانات');
    expect(
      find.textContaining('التنسيق الوزاري الثابت'),
      findsOneWidget,
      reason: 'يظهر تنبيه تجميد Word/Excel للامتحانات الرسمية',
    );
  });

  testWidgets('question bank export keeps the Excel option', (tester) async {
    await tester.pumpWidget(
      _wrap(ExportDialog(mainQuestions: <MainQuestion>[_sampleQuestion()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excel — جدول بيانات (.xlsx)'), findsOneWidget);
    expect(find.text('PDF — ورقة الطالب'), findsNothing);
  });
}
