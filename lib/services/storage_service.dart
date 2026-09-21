import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/exam.dart';
import '../models/exam_header.dart';
import '../models/question.dart';

/// Local persistence layer on top of [SharedPreferences].
///
/// All decoding is defensive: a single corrupt record is skipped (and logged)
/// instead of crashing the whole app, so one bad write can never lock the
/// user out of their question bank.
class StorageService {
  StorageService({SharedPreferences? prefs})
      : _prefsFuture =
            prefs == null ? SharedPreferences.getInstance() : Future.value(prefs);

  final Future<SharedPreferences> _prefsFuture;

  static const String _questionsKey = 'app_saved_questions';
  static const String _examsKey = 'app_saved_exams';
  static const String _defaultHeaderKey = 'app_default_header';

  Future<List<Question>> loadQuestions() async {
    final prefs = await _prefsFuture;
    final jsonList = prefs.getStringList(_questionsKey) ?? const [];
    return _decodeAll(jsonList, Question.fromJson, 'Question');
  }

  Future<void> saveQuestions(List<Question> questions) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      _questionsKey,
      questions.map((question) => question.toJson()).toList(),
    );
  }

  Future<List<Exam>> loadExams() async {
    final prefs = await _prefsFuture;
    final jsonList = prefs.getStringList(_examsKey) ?? const [];
    return _decodeAll(jsonList, Exam.fromJson, 'Exam');
  }

  Future<void> saveExams(List<Exam> exams) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      _examsKey,
      exams.map((exam) => exam.toJson()).toList(),
    );
  }

  Future<ExamHeader> loadDefaultHeader() async {
    final prefs = await _prefsFuture;
    final jsonString = prefs.getString(_defaultHeaderKey);
    if (jsonString == null) return ExamHeader();
    return _tryDecode(
      jsonString,
      (source) => ExamHeader.fromMap(jsonDecode(source) as Map<String, dynamic>),
      'ExamHeader',
    );
  }

  Future<void> saveDefaultHeader(ExamHeader header) async {
    final prefs = await _prefsFuture;
    await prefs.setString(_defaultHeaderKey, jsonEncode(header.toMap()));
  }

  /// Decodes every record, skipping and logging the ones that fail.
  List<T> _decodeAll<T>(
    List<String> sources,
    T Function(String source) decoder,
    String kind,
  ) {
    final items = <T>[];
    for (final source in sources) {
      final item = _tryDecode(source, decoder, kind);
      if (item != null) items.add(item);
    }
    return items;
  }

  T? _tryDecode<T>(
    String source,
    T Function(String source) decoder,
    String kind,
  ) {
    try {
      return decoder(source);
    } catch (error, stackTrace) {
      developer.log(
        'Skipped a corrupt $kind record (${error.runtimeType}).',
        name: 'StorageService',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
