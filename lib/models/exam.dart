import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'question.dart';
import 'exam_header.dart';

class Exam {
  final String id;
  String name;
  ExamHeader header;
  List<Question> questions;
  DateTime createdAt;

  Exam({
    String? id,
    required this.name,
    ExamHeader? header,
    List<Question>? questions,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        header = header ?? ExamHeader(),
        questions = questions ?? [],
        createdAt = createdAt ?? DateTime.now();

  double get totalMarks {
    return questions.fold(0.0, (sum, q) => sum + q.marks);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'header': header.toMap(),
      'questions': questions.map((q) => q.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Exam.fromMap(Map<String, dynamic> map) {
    return Exam(
      id: map['id'],
      name: map['name'] ?? 'اختبار غير معنون',
      header: ExamHeader.fromMap(map['header'] ?? {}),
      questions: (map['questions'] as List<dynamic>?)
              ?.map((q) => Question.fromMap(q as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory Exam.fromJson(String source) => Exam.fromMap(jsonDecode(source));
}
