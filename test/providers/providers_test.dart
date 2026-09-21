import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/difficulty.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/question_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QuestionProvider', () {
    test('seeds sample questions on first launch', () async {
      final provider = QuestionProvider();

      await provider.loadQuestions();

      expect(provider.questions, isNotEmpty);
    });

    test('keeps persisted questions on subsequent launches', () async {
      final first = QuestionProvider();
      await first.loadQuestions();
      final count = first.questions.length;

      final second = QuestionProvider();
      await second.loadQuestions();

      expect(second.questions, hasLength(count));
    });

    test('filters by search query, type, difficulty and subject', () async {
      final provider = QuestionProvider();
      await provider.loadQuestions();

      provider.setSearchQuery('عاصمة');
      expect(provider.filteredQuestions, hasLength(1));
      expect(provider.filteredQuestions.first.type, QuestionType.multipleChoice);

      provider.setSearchQuery('');
      provider.setTypeFilter(QuestionType.essay);
      expect(provider.filteredQuestions.every((q) => q.type == QuestionType.essay), isTrue);

      provider.setTypeFilter(null);
      provider.setDifficultyFilter(Difficulty.easy);
      expect(
        provider.filteredQuestions.every((q) => q.difficulty == Difficulty.easy),
        isTrue,
      );

      provider.setDifficultyFilter(null);
      final subjects = provider.availableSubjects;
      provider.setSubjectFilter(subjects.last);
      expect(
        provider.filteredQuestions.every((q) => q.subject == subjects.last),
        isTrue,
      );

      provider.resetFilters();
      expect(provider.filteredQuestions.length, provider.questions.length);
    });

    test('add, update and delete mutate the bank', () async {
      final provider = QuestionProvider();
      await provider.loadQuestions();
      final baseline = provider.questions.length;

      final question = createQuestion('سؤال جديد');
      await provider.addQuestion(question);
      expect(provider.questions, hasLength(baseline + 1));

      await provider.updateQuestion(
        question.copyWith(title: 'عنوان معدّل'),
      );
      expect(provider.questions.first.title, 'عنوان معدّل');

      await provider.deleteQuestion(question.id);
      expect(provider.questions, hasLength(baseline));
    });
  });
}

// Helper at top level so both groups can use it.
Question createQuestion(String title) {
  return Question(
    title: title,
    type: QuestionType.trueFalse,
    subject: 'مادة تجريبية',
  );
}
