import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/exam.dart';
import '../models/exam_header.dart';
import '../models/question.dart';

class StorageLoadResult<T> {
  const StorageLoadResult({
    required this.items,
    required this.hadStoredValue,
    this.discardedEntries = 0,
  });

  final List<T> items;
  final bool hadStoredValue;
  final int discardedEntries;

  bool get recoveredFromCorruption => discardedEntries > 0;
}

class StorageService {
  StorageService({
    SharedPreferences? prefs,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : assert(prefs == null || preferencesLoader == null),
        _preferencesLoader =
            preferencesLoader ?? _createPreferencesLoader(prefs);

  static const String _questionsKey = 'app_saved_questions';
  static const String _examsKey = 'app_saved_exams';
  static const String _defaultHeaderKey = 'app_default_header';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;

  static Future<SharedPreferences> Function() _createPreferencesLoader(
    SharedPreferences? prefs,
  ) {
    if (prefs != null) {
      return () => Future<SharedPreferences>.value(prefs);
    }
    return SharedPreferences.getInstance;
  }

  Future<StorageLoadResult<Question>> loadQuestions() {
    return _loadList(_questionsKey, Question.fromJson);
  }

  Future<void> saveQuestions(List<Question> questions) {
    return _saveList(_questionsKey, questions.map((question) => question.toJson()));
  }

  Future<StorageLoadResult<Exam>> loadExams() {
    return _loadList(_examsKey, Exam.fromJson);
  }

  Future<void> saveExams(List<Exam> exams) {
    return _saveList(_examsKey, exams.map((exam) => exam.toJson()));
  }

  Future<ExamHeader> loadDefaultHeader() async {
    final preferences = await _getPreferences();
    final jsonString = preferences.getString(_defaultHeaderKey);
    if (jsonString == null || jsonString.isEmpty) {
      return ExamHeader();
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        return ExamHeader();
      }
      return ExamHeader.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // A damaged default header must not prevent the application from opening.
      return ExamHeader();
    }
  }

  Future<void> saveDefaultHeader(ExamHeader header) async {
    final preferences = await _getPreferences();
    final saved = await preferences.setString(_defaultHeaderKey, jsonEncode(header.toMap()));
    if (!saved) {
      throw StateError('تعذر حفظ الترويسة الافتراضية على الجهاز.');
    }
  }

  Future<StorageLoadResult<T>> _loadList<T>(
    String key,
    T Function(String source) decoder,
  ) async {
    final preferences = await _getPreferences();
    final storedItems = preferences.getStringList(key);
    final savedItems = storedItems ?? const <String>[];
    final items = <T>[];
    var discardedEntries = 0;

    for (final savedItem in savedItems) {
      try {
        items.add(decoder(savedItem));
      } catch (_) {
        // Keep valid local records available even if one older/corrupt record fails.
        discardedEntries++;
      }
    }

    return StorageLoadResult<T>(
      items: List<T>.unmodifiable(items),
      hadStoredValue: storedItems != null,
      discardedEntries: discardedEntries,
    );
  }

  Future<void> _saveList(String key, Iterable<String> values) async {
    final preferences = await _getPreferences();
    final saved = await preferences.setStringList(key, values.toList(growable: false));
    if (!saved) {
      throw StateError('تعذر حفظ البيانات على الجهاز.');
    }
  }

  Future<SharedPreferences> _getPreferences() {
    return _preferences ??= _preferencesLoader();
  }
}
