import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'exam_header.dart';
import 'question.dart';

class Exam {
  final String id;
  final String name;
  final ExamHeader header;
  final List<Question> questions;
  final DateTime createdAt;

  Exam({
    String? id,
    required this.name,
    ExamHeader? header,
    List<Question>? questions,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        header = header ?? ExamHeader(),
        questions = List<Question>.unmodifiable(questions ?? const []),
        createdAt = createdAt ?? DateTime.now();

  double get totalMarks {
    return questions.fold<double>(0, (sum, question) => sum + question.marks);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'header': header.toMap(),
      'questions': questions.map((question) => question.toMap()).toList(growable: false),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Exam.fromMap(Map<String, dynamic> map) {
    return Exam(
      id: _nonEmptyString(map['id']),
      name: _nonEmptyString(map['name']) ?? 'اختبار غير معنون',
      header: _headerFromValue(map['header']),
      questions: _questionsFromValue(map['questions']),
      createdAt: _dateFromValue(map['createdAt']) ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Exam.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Exam JSON must contain an object.');
    }
    return Exam.fromMap(Map<String, dynamic>.from(decoded));
  }

  Exam copyWith({
    String? name,
    ExamHeader? header,
    List<Question>? questions,
  }) {
    return Exam(
      id: id,
      name: name ?? this.name,
      header: header ?? this.header,
      questions: questions ?? this.questions,
      createdAt: createdAt,
    );
  }

  static ExamHeader _headerFromValue(Object? value) {
    return value is Map
        ? ExamHeader.fromMap(Map<String, dynamic>.from(value))
        : ExamHeader();
  }

  static List<Question> _questionsFromValue(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((question) => Question.fromMap(Map<String, dynamic>.from(question)))
        .toList(growable: false);
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
