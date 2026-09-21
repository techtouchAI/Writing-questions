import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/difficulty.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  group('Question serialization', () {
    test('round-trips through its map representation', () {
      final question = Question(
        title: 'ما هي عاصمة العراق؟ <&>',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.hard,
        marks: 2.5,
        subject: 'الجغرافيا',
        topic: 'عواصم',
        options: [
          QuestionOption(text: 'بغداد', isCorrect: true),
          QuestionOption(text: 'البصرة'),
        ],
        modelAnswer: 'بغداد',
        explanation: 'معلومة عامة',
      );

      final restored = Question.fromMap(question.toMap());

      expect(restored.id, question.id);
      expect(restored.title, question.title);
      expect(restored.type, QuestionType.multipleChoice);
      expect(restored.difficulty, Difficulty.hard);
      expect(restored.marks, 2.5);
      expect(restored.options.length, 2);
      expect(restored.options.first.text, 'بغداد');
      expect(restored.options.first.isCorrect, isTrue);
      expect(restored.modelAnswer, 'بغداد');
      expect(restored.explanation, 'معلومة عامة');
      expect(restored.createdAt, question.createdAt);
    });

    test('applies safe defaults for missing or corrupt fields', () {
      final question = Question.fromMap(const {
        'title': 'سؤال',
        'type': 'نوع_غير_معروف',
        'difficulty': 'مستوى_غير_معروف',
        'options': 'ليست قائمة',
      });

      expect(question.type, QuestionType.multipleChoice);
      expect(question.difficulty, Difficulty.medium);
      expect(question.marks, 1.0);
      expect(question.options, isEmpty);
      expect(question.subject, 'عام');
    });

    test('copyWith preserves identity fields', () {
      final original = Question(title: 'أصل', marks: 1.0);
      final copy = original.copyWith(title: 'معدّل', marks: 3.0);

      expect(copy.id, original.id);
      expect(copy.createdAt, original.createdAt);
      expect(copy.title, 'معدّل');
      expect(copy.marks, 3.0);
      expect(original.title, 'أصل', reason: 'copyWith must not mutate the source');
    });
  });

  group('Exam', () {
    test('totalMarks sums question marks', () {
      final exam = Exam(
        name: 'اختبار',
        header: ExamHeader(),
        questions: [
          Question(title: 'س1', marks: 2.0),
          Question(title: 'س2', marks: 1.5),
          Question(title: 'س3', marks: 0.5),
        ],
      );

      expect(exam.totalMarks, 4.0);
    });

    test('round-trips through JSON', () {
      final exam = Exam(
        name: 'الاختبار النهائي',
        questions: [Question(title: 'س1', type: QuestionType.trueFalse)],
      );

      final restored = Exam.fromJson(exam.toJson());

      expect(restored.id, exam.id);
      expect(restored.name, exam.name);
      expect(restored.questions, hasLength(1));
      expect(restored.questions.first.type, QuestionType.trueFalse);
    });
  });
}
