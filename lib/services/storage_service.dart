import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/question.dart';
import '../models/exam.dart';
import '../models/exam_header.dart';

class StorageService {
  static const String _questionsKey = 'app_saved_questions';
  static const String _examsKey = 'app_saved_exams';
  static const String _defaultHeaderKey = 'app_default_header';

  Future<List<Question>> loadQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_questionsKey) ?? [];
    return jsonList.map((e) => Question.fromJson(e)).toList();
  }

  Future<void> saveQuestions(List<Question> questions) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = questions.map((e) => e.toJson()).toList();
    await prefs.setStringList(_questionsKey, jsonList);
  }

  Future<List<Exam>> loadExams() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_examsKey) ?? [];
    return jsonList.map((e) => Exam.fromJson(e)).toList();
  }

  Future<void> saveExams(List<Exam> exams) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = exams.map((e) => e.toJson()).toList();
    await prefs.setStringList(_examsKey, jsonList);
  }

  Future<ExamHeader> loadDefaultHeader() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_defaultHeaderKey);
    if (jsonString != null) {
      return ExamHeader.fromMap(jsonDecode(jsonString));
    }
    return ExamHeader();
  }

  Future<void> saveDefaultHeader(ExamHeader header) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultHeaderKey, jsonEncode(header.toMap()));
  }
}
