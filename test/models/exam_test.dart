import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  test('Exam preserves its creation date when edited with copyWith', () {
    final createdAt = DateTime.utc(2026, 9, 22);
    final exam = Exam(
      id: 'exam-1',
      name: 'الاختبار الأول',
      header: ExamHeader(title: 'اختبار تجريبي'),
      questions: <Question>[
        Question(
          id: 'question-1',
          title: 'سؤال',
          type: QuestionType.essay,
          marks: 2.5,
        ),
      ],
      createdAt: createdAt,
    );

    final edited = exam.copyWith(name: 'الاختبار المعدل');

    expect(edited.id, exam.id);
    expect(edited.name, 'الاختبار المعدل');
    expect(edited.createdAt, createdAt);
    expect(edited.totalMarks, 2.5);
  });

  test('Exam restores malformed optional sections with safe defaults', () {
    final exam = Exam.fromMap(<String, dynamic>{
      'id': 'exam-2',
      'name': 'اختبار مؤرشف',
      'header': 'غير صالح',
      'questions': 'غير صالح',
    });

    expect(exam.questions, isEmpty);
    expect(exam.header.title, isNotEmpty);
  });
}
