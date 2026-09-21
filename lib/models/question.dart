import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'question_type.dart';
import 'difficulty.dart';

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
      id: map['id'],
      text: map['text'] ?? '',
      isCorrect: map['isCorrect'] ?? false,
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
  String modelAnswer; // Used for Essay, Fill in blanks, or general explanation
  String explanation;
  DateTime createdAt;

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
        options = options ?? [],
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
      'options': options.map((e) => e.toMap()).toList(),
      'modelAnswer': modelAnswer,
      'explanation': explanation,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    return Question(
      id: map['id'],
      title: map['title'] ?? '',
      type: QuestionType.fromString(map['type'] ?? ''),
      difficulty: Difficulty.fromString(map['difficulty'] ?? ''),
      marks: (map['marks'] as num?)?.toDouble() ?? 1.0,
      subject: map['subject'] ?? 'عام',
      topic: map['topic'] ?? '',
      options: rawOptions is List<dynamic>
          ? rawOptions.whereType<Map>().map((e) => QuestionOption.fromMap(Map<String, dynamic>.from(e))).toList()
          : <QuestionOption>[],
      modelAnswer: map['modelAnswer'] ?? '',
      explanation: map['explanation'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory Question.fromJson(String source) => Question.fromMap(jsonDecode(source));

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
      options: options ?? List.from(this.options),
      modelAnswer: modelAnswer ?? this.modelAnswer,
      explanation: explanation ?? this.explanation,
      createdAt: createdAt,
    );
  }
}
