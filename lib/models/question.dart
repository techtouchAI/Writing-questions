import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'difficulty.dart';
import 'question_type.dart';

class QuestionOption {
  final String id;
  String text;
  bool isCorrect;

  QuestionOption({
    String? id,
    required this.text,
    this.isCorrect = false,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isCorrect': isCorrect,
    };
  }

  factory QuestionOption.fromMap(Map<String, dynamic> map) {
    return QuestionOption(
      id: _nonEmptyString(map['id']),
      text: map['text']?.toString() ?? '',
      isCorrect: map['isCorrect'] == true,
    );
  }

  QuestionOption copyWith({String? text, bool? isCorrect}) {
    return QuestionOption(
      id: id,
      text: text ?? this.text,
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }
}

class Question {
  final String id;
  String title;
  QuestionType type;
  Difficulty difficulty;
  double marks;
  String subject;
  String topic;
  List<QuestionOption> options;
  String modelAnswer;
  String explanation;
  final DateTime createdAt;

  Question({
    String? id,
    required this.title,
    required this.type,
    this.difficulty = Difficulty.medium,
    this.marks = 1.0,
    this.subject = 'عام',
    this.topic = '',
    List<QuestionOption>? options,
    this.modelAnswer = '',
    this.explanation = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        options = _copyOptions(options ?? const []),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type.name,
      'difficulty': difficulty.name,
      'marks': marks,
      'subject': subject,
      'topic': topic,
      'options': options.map((option) => option.toMap()).toList(growable: false),
      'modelAnswer': modelAnswer,
      'explanation': explanation,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    final rawMarks = map['marks'];
    final parsedMarks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');

    return Question(
      id: _nonEmptyString(map['id']),
      title: map['title']?.toString() ?? '',
      type: QuestionType.fromString(map['type']?.toString() ?? ''),
      difficulty: Difficulty.fromString(map['difficulty']?.toString() ?? ''),
      marks: parsedMarks != null && parsedMarks.isFinite && parsedMarks > 0
          ? parsedMarks
          : 1.0,
      subject: _nonEmptyString(map['subject']) ?? 'عام',
      topic: map['topic']?.toString() ?? '',
      options: _optionsFromValue(map['options']),
      modelAnswer: map['modelAnswer']?.toString() ?? '',
      explanation: map['explanation']?.toString() ?? '',
      createdAt: _dateFromValue(map['createdAt']) ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Question.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Question JSON must contain an object.');
    }
    return Question.fromMap(Map<String, dynamic>.from(decoded));
  }

  Question copyWith({
    String? title,
    QuestionType? type,
    Difficulty? difficulty,
    double? marks,
    String? subject,
    String? topic,
    List<QuestionOption>? options,
    String? modelAnswer,
    String? explanation,
  }) {
    return Question(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      marks: marks ?? this.marks,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      options: options ?? this.options,
      modelAnswer: modelAnswer ?? this.modelAnswer,
      explanation: explanation ?? this.explanation,
      createdAt: createdAt,
    );
  }

  static List<QuestionOption> _optionsFromValue(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((option) => QuestionOption.fromMap(Map<String, dynamic>.from(option)))
        .toList(growable: false);
  }

  static List<QuestionOption> _copyOptions(List<QuestionOption> source) {
    return source.map((option) => option.copyWith()).toList(growable: false);
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
