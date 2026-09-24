import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/difficulty.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_type.dart';

void main() {
  group('MainQuestion map round-trip', () {
    test('round-trips through its map representation', () {
      final question = MainQuestion(
        title: 'ما هي عاصمة العراق؟ <&>',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.hard,
        subject: 'الجغرافيا',
        topic: 'عواصم',
        branches: <QuestionBranch>[
          QuestionBranch(text: 'اختر الإجابة', marks: 2.5),
        ],
        options: <QuestionOption>[
          QuestionOption(text: 'بغداد', isCorrect: true),
          QuestionOption(text: 'البصرة'),
        ],
        modelAnswer: 'بغداد',
        explanation: 'معلومة عامة',
      );

      final restored = MainQuestion.fromMap(question.toMap());

      expect(restored.id, question.id);
      expect(restored.title, question.title);
      expect(restored.type, QuestionType.multipleChoice);
      expect(restored.difficulty, Difficulty.hard);
      expect(restored.marks, 2.5);
      expect(restored.branches.single.text, 'اختر الإجابة');
      expect(restored.options.length, 2);
      expect(restored.options.first.text, 'بغداد');
      expect(restored.options.first.isCorrect, isTrue);
      expect(restored.modelAnswer, 'بغداد');
      expect(restored.explanation, 'معلومة عامة');
      expect(restored.createdAt, question.createdAt);
    });
  });

  group('Exam hierarchical model', () {
    test('totalMarks rolls up from every QuestionBranch of every question', () {
      final exam = Exam(
        name: 'اختبار',
        header: ExamHeader(),
        mainQuestions: <MainQuestion>[
          MainQuestion(
            title: 'س1',
            type: QuestionType.essay,
            branches: <QuestionBranch>[
              QuestionBranch(text: 'أ', marks: 2),
              QuestionBranch(text: 'ب', marks: 1.5),
            ],
          ),
          MainQuestion(
            title: 'س2',
            type: QuestionType.trueFalse,
            branches: <QuestionBranch>[QuestionBranch(text: '', marks: 0.5)],
          ),
        ],
      );

      expect(exam.mainQuestions, hasLength(2));
      expect(exam.totalMarks, 4.0);
    });

    test('round-trips through JSON with branches and floating elements', () {
      final exam = Exam(
        name: 'الاختبار النهائي',
        mainQuestions: <MainQuestion>[
          MainQuestion(
            title: 'س1',
            type: QuestionType.trueFalse,
            branches: <QuestionBranch>[QuestionBranch(text: '', marks: 3)],
          ),
        ],
      );

      final restored = Exam.fromJson(exam.toJson());

      expect(restored.id, exam.id);
      expect(restored.name, exam.name);
      expect(restored.mainQuestions, hasLength(1));
      expect(restored.mainQuestions.first.type, QuestionType.trueFalse);
      expect(restored.mainQuestions.first.marks, 3);
      expect(restored.floatingElements, isEmpty);
    });

    test('preserves manual ordering (no hidden shuffle)', () {
      final exam = Exam(
        name: 'ترتيب يدوي',
        mainQuestions: <MainQuestion>[
          MainQuestion(title: 'الأول', type: QuestionType.essay),
          MainQuestion(title: 'الثاني', type: QuestionType.essay),
          MainQuestion(title: 'الثالث', type: QuestionType.essay),
        ],
      );

      final restored = Exam.fromJson(exam.toJson());
      expect(
        restored.mainQuestions.map((question) => question.title).toList(),
        <String>['الأول', 'الثاني', 'الثالث'],
      );
    });

    test('reads legacy exams saved under the old questions key', () {
      final restored = Exam.fromMap(<String, dynamic>{
        'id': 'exam-legacy',
        'name': 'اختبار قديم',
        'questions': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'س1', 'type': 'essay', 'marks': 2},
        ],
      });

      expect(restored.mainQuestions, hasLength(1));
      expect(restored.mainQuestions.first.marks, 2);
    });

    test('throws for a corrupted question so storage can isolate the record', () {
      expect(
        () => Exam.fromMap(<String, dynamic>{
          'name': 'اختبار تالف',
          'mainQuestions': <Map<String, dynamic>>[
            <String, dynamic>{'title': 'س1', 'type': 'نوع_غير_معروف'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => Exam.fromMap(<String, dynamic>{
          'name': 'اختبار تالف',
          'mainQuestions': 'ليست قائمة',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
