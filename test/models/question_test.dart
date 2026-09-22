import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/difficulty.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  group('Question', () {
    test('round-trips Arabic content and options through JSON', () {
      final question = Question(
        id: 'question-1',
        title: 'ما عاصمة العراق؟',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.easy,
        marks: 2,
        subject: 'الجغرافيا',
        topic: 'العراق',
        options: <QuestionOption>[
          QuestionOption(id: 'a', text: 'بغداد', isCorrect: true),
          QuestionOption(id: 'b', text: 'البصرة'),
        ],
        explanation: 'بغداد هي العاصمة.',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final restored = Question.fromJson(question.toJson());

      expect(restored.id, question.id);
      expect(restored.title, 'ما عاصمة العراق؟');
      expect(restored.marks, 2);
      expect(restored.options, hasLength(2));
      expect(restored.options.first.isCorrect, isTrue);
      expect(restored.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('copyWith copies option objects instead of sharing mutable state', () {
      final original = Question(
        id: 'question-2',
        title: 'سؤال',
        type: QuestionType.multipleChoice,
        options: <QuestionOption>[
          QuestionOption(id: 'option-1', text: 'الإجابة', isCorrect: true),
          QuestionOption(id: 'option-2', text: 'خيار آخر'),
        ],
      );

      final copy = original.copyWith();
      copy.options.first.text = 'تعديل محلي';

      expect(original.options.first.text, 'الإجابة');
      expect(copy.options.first.text, 'تعديل محلي');
    });

    test('recovers a safe default mark from invalid persisted data', () {
      final question = Question.fromMap(<String, dynamic>{
        'id': 'question-3',
        'title': 'سؤال مؤرشف',
        'type': 'essay',
        'difficulty': 'hard',
        'marks': -2,
      });

      expect(question.marks, 1);
      expect(question.type, QuestionType.essay);
      expect(question.difficulty, Difficulty.hard);
      expect(question.subject, 'عام');
    });
  });
}
