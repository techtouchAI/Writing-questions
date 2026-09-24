import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/difficulty.dart';
import 'package:writing_questions_app/models/label_alphabet.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  group('MainQuestion marks roll-up', () {
    test('total marks always equal the sum of QuestionBranch marks', () {
      final question = MainQuestion(
        title: 'أعرب ما تحته خط',
        type: QuestionType.essay,
        branches: <QuestionBranch>[
          QuestionBranch(text: 'حدد نوع الكلمة', marks: 2),
          QuestionBranch(text: 'أعرب آخر الكلمات', marks: 1.5),
          QuestionBranch(text: '', marks: 0.5),
        ],
      );

      expect(question.marks, 4.0);
    });

    test('marks roll up automatically when branches change', () {
      final question = MainQuestion(
        title: 'سؤال متغير',
        type: QuestionType.essay,
        branches: <QuestionBranch>[QuestionBranch(text: 'أ', marks: 1)],
      );
      expect(question.marks, 1.0);

      question.branches.add(QuestionBranch(text: 'ب', marks: 2.5));
      expect(question.marks, 3.5);

      question.branches.removeAt(0);
      expect(question.marks, 2.5);
    });

    test('a question without branches has zero marks (no hidden field)', () {
      final question = MainQuestion(title: 'بلا فروع', type: QuestionType.essay);
      expect(question.marks, 0.0);
    });
  });

  group('MainQuestion serialization', () {
    test('round-trips Arabic content, branches and options through JSON', () {
      final question = MainQuestion(
        id: 'question-1',
        title: 'ما عاصمة العراق؟',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.easy,
        subject: 'الجغرافيا',
        topic: 'العراق',
        branches: <QuestionBranch>[
          QuestionBranch(id: 'branch-1', text: 'اختر الإجابة الصحيحة', marks: 2),
        ],
        options: <QuestionOption>[
          QuestionOption(id: 'a', text: 'بغداد', isCorrect: true),
          QuestionOption(id: 'b', text: 'البصرة'),
        ],
        explanation: 'بغداد هي العاصمة.',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final restored = MainQuestion.fromJson(question.toJson());

      expect(restored.id, 'question-1');
      expect(restored.title, 'ما عاصمة العراق؟');
      expect(restored.marks, 2);
      expect(restored.branches, hasLength(1));
      expect(restored.branches.first.text, 'اختر الإجابة الصحيحة');
      expect(restored.branches.first.marks, 2);
      expect(restored.options, hasLength(2));
      expect(restored.options.first.isCorrect, isTrue);
      expect(restored.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('never persists branch labels — they are index-generated', () {
      final question = MainQuestion(
        title: 'سؤال',
        type: QuestionType.essay,
        branches: <QuestionBranch>[
          QuestionBranch(text: 'فرع', marks: 1),
        ],
      );

      final map = question.toMap();
      final branchMap =
          (map['branches'] as List).cast<Map<String, dynamic>>().first;
      expect(branchMap.containsKey('label'), isFalse,
          reason: 'التسميات (أ/ب/ج) تُولَّد من الفهرس وقت العرض فقط');

      // التسمية الظاهرة تأتي من الفهرس وحده:
      expect(LabelAlphabet.at(0), 'أ');
      expect(LabelAlphabet.at(1), 'ب');
    });

    test('migrates legacy single marks into one carrier branch', () {
      final restored = MainQuestion.fromMap(const <String, dynamic>{
        'title': 'سؤال قديم',
        'type': 'essay',
        'marks': 2.5,
      });

      expect(restored.branches, hasLength(1));
      expect(restored.branches.first.text, '');
      expect(restored.branches.first.marks, 2.5);
      expect(restored.marks, 2.5);
    });

    test('copyWith copies branch and option objects instead of sharing state', () {
      final original = MainQuestion(
        id: 'question-2',
        title: 'سؤال',
        type: QuestionType.multipleChoice,
        branches: <QuestionBranch>[QuestionBranch(text: 'فرع', marks: 1)],
        options: <QuestionOption>[
          QuestionOption(id: 'option-1', text: 'الإجابة', isCorrect: true),
        ],
      );

      final copy = original.copyWith();
      copy.options.first.text = 'تعديل محلي';
      copy.branches.first.text = 'تعديل الفرع';

      expect(original.options.first.text, 'الإجابة');
      expect(original.branches.first.text, 'فرع');
      expect(copy.options.first.text, 'تعديل محلي');
    });

    test('copyWith preserves identity fields', () {
      final original = MainQuestion(
        title: 'أصل',
        type: QuestionType.essay,
        branches: <QuestionBranch>[QuestionBranch(text: '', marks: 1)],
      );
      final copy = original.copyWith(title: 'معدّل');

      expect(copy.id, original.id);
      expect(copy.createdAt, original.createdAt);
      expect(copy.title, 'معدّل');
      expect(original.title, 'أصل', reason: 'copyWith must not mutate the source');
    });
  });

  group('MainQuestion strict parsing (FormatException isolation)', () {
    test('throws for an unknown question type instead of faking a default', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'نوع_غير_معروف',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws for a missing question type', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{'title': 'سؤال'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws for an unknown difficulty level', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'essay',
          'difficulty': 'مستوى_غير_معروف',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when branches is not a list', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'essay',
          'branches': 'ليست قائمة',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when a branch entry is not a map (invalid branch structure)', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'essay',
          'branches': ['فرع ليس خريطة'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws for corrupt branch marks instead of silently zeroing', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'essay',
          'branches': [
            {'text': 'فرع تالف', 'marks': 'غير رقم'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'essay',
          'branches': [
            {'text': 'فرع سالب', 'marks': -2},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws for negative legacy marks instead of dummy defaults', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال مؤرشف',
          'type': 'essay',
          'marks': -2,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when options is not a list of maps', () {
      expect(
        () => MainQuestion.fromMap(const <String, dynamic>{
          'title': 'سؤال',
          'type': 'multipleChoice',
          'options': 'ليست قائمة',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('applies safe defaults only for truly missing optional data', () {
      final restored = MainQuestion.fromMap(const <String, dynamic>{
        'title': 'سؤال قديم',
        'type': 'essay',
      });

      expect(restored.category, '');
      expect(restored.branches, isEmpty);
      expect(restored.difficulty, Difficulty.medium);
      expect(restored.subject, 'عام');
    });
  });
}
