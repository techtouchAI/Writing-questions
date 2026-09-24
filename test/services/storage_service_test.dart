import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('StorageService', () {
    test('round-trips questions through persistence', () async {
      final storage = StorageService(prefs: prefs);
      await storage.saveQuestions([
        MainQuestion(
          title: 'سؤال محفوظ',
          type: QuestionType.essay,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 4)],
        ),
      ]);

      final loaded = await storage.loadQuestions();

      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.title, 'سؤال محفوظ');
      expect(loaded.items.first.type, QuestionType.essay);
      expect(loaded.items.first.marks, 4);
    });

    test('skips corrupt records instead of crashing', () async {
      await prefs.setStringList('app_saved_questions', [
        '{invalid json',
        '{"title":"سؤال سليم","type":"essay"}',
        '{"title":"نوع مجهول","type":"نوع_غير_معروف"}',
        '{"title":"فروع تالفة","type":"essay","branches":"ليست قائمة"}',
        '"not-even-an-object"',
      ]);

      final storage = StorageService(prefs: prefs);
      final loaded = await storage.loadQuestions();

      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.title, 'سؤال سليم');
    });

    test('distinguishes a missing key from an intentionally empty bank', () async {
      final storage = StorageService(prefs: prefs);

      final missing = await storage.loadQuestions();
      expect(missing.items, isEmpty);
      expect(missing.hadStoredValue, isFalse);

      await prefs.setStringList('app_saved_questions', <String>[]);
      final emptyBank = await storage.loadQuestions();
      expect(emptyBank.items, isEmpty);
      expect(emptyBank.hadStoredValue, isTrue);
    });
  });
}
