import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  group('Question structured input', () {
    test('round-trips category and branches', () {
      final question = Question(
        title: 'أعرب ما تحته خط',
        type: QuestionType.essay,
        subject: 'اللغة العربية',
        category: 'القواعد',
        marks: 4,
        branches: [
          QuestionBranch(label: 'أ', text: 'حدد نوع الكلمة', marks: 2),
          QuestionBranch(label: 'ب', text: 'أعرب آخر الكلمات', marks: 2),
        ],
        modelAnswer: 'إعراب كامل',
      );

      final restored = Question.fromMap(question.toMap());

      expect(restored.category, 'القواعد');
      expect(restored.branches, hasLength(2));
      expect(restored.branches.first.label, 'أ');
      expect(restored.branches.first.text, 'حدد نوع الكلمة');
      expect(restored.branches.first.marks, 2);
      expect(restored.branches.last.marks, 2);
    });

    test('applies safe defaults for legacy stored maps', () {
      final restored = Question.fromMap(const {
        'title': 'سؤال قديم',
        'type': 'essay',
      });

      expect(restored.category, '');
      expect(restored.branches, isEmpty);
    });

    test('repairs corrupt branch marks', () {
      final restored = Question.fromMap(const {
        'title': 'سؤال',
        'type': 'essay',
        'branches': [
          {'text': 'فرع سليم', 'marks': 1.5},
          {'text': 'فرع تالف', 'marks': 'غير رقم'},
          {'text': '', 'marks': 3},
        ],
      });

      expect(restored.branches, hasLength(3));
      expect(restored.branches[0].marks, 1.5);
      expect(restored.branches[1].marks, 0);
      expect(restored.branches[2].text, '');
      expect(restored.branches[2].label, '');
    });

    test('rejects a non-list branches value', () {
      final restored = Question.fromMap(const {
        'title': 'سؤال',
        'type': 'essay',
        'branches': 'ليست قائمة',
      });
      expect(restored.branches, isEmpty);
    });
  });
}
