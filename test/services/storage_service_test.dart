import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/question.dart';
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
        Question(title: 'سؤال محفوظ', type: QuestionType.essay, marks: 4),
      ]);

      final loaded = await storage.loadQuestions();

      expect(loaded, hasLength(1));
      expect(loaded.first.title, 'سؤال محفوظ');
      expect(loaded.first.type, QuestionType.essay);
      expect(loaded.first.marks, 4);
    });

    test('skips corrupt records instead of crashing', () async {
      await prefs.setStringList('app_saved_questions', [
        '{invalid json',
        '{"title":"سؤال سليم","type":"essay"}',
        '"not-even-an-object"',
      ]);

      final storage = StorageService(prefs: prefs);
      final loaded = await storage.loadQuestions();

      expect(loaded, hasLength(1));
      expect(loaded.first.title, 'سؤال سليم');
    });

    test('returns an empty list for missing keys', () async {
      final storage = StorageService(prefs: prefs);

      expect(await storage.loadQuestions(), isEmpty);
      expect(await storage.loadExams(), isEmpty);
    });
  });
}
