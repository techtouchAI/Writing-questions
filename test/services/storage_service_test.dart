import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/storage_service.dart';

ExamDocument _sampleDocument() {
  return ExamDocument(
    name: 'نموذج محفوظ',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('StorageService', () {
    test('round-trips exam documents through persistence', () async {
      final storage = StorageService(prefs: prefs);
      await storage.saveExamDocuments([_sampleDocument()]);

      final loaded = await storage.loadExamDocuments();

      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.name, 'نموذج محفوظ');
      expect(loaded.items.first.header.subject, 'اللغة العربية');
      expect(loaded.items.first.questions, hasLength(1));
    });

    test('skips corrupt records instead of crashing', () async {
      await prefs.setStringList('app_saved_exam_documents', [
        '{invalid json',
        _sampleDocument().toJson(),
        '{"name":"بلا ترويسة"}',
        '{"name":"أسئلة تالفة","header":{},"questions":"ليست قائمة"}',
        '"not-even-an-object"',
      ]);

      final storage = StorageService(prefs: prefs);
      final loaded = await storage.loadExamDocuments();

      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.name, 'نموذج محفوظ');
    });

    test('distinguishes a missing key from an intentionally empty library', () async {
      final storage = StorageService(prefs: prefs);

      final missing = await storage.loadExamDocuments();
      expect(missing.items, isEmpty);
      expect(missing.hadStoredValue, isFalse);

      await prefs.setStringList('app_saved_exam_documents', <String>[]);
      final emptyLibrary = await storage.loadExamDocuments();
      expect(emptyLibrary.items, isEmpty);
      expect(emptyLibrary.hadStoredValue, isTrue);
    });
  });
}
