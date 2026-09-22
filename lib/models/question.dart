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

/// فرع من فروع السؤال (أ، ب، ج...) بدرجة مستقلة اختيارية.
///
/// يمثّل البنية الصارمة للفروع في هندسة محرك الأسئلة بدل ترك الفروع
/// مدموجة داخل نص السؤال الحر.
class QuestionBranch {
  String label;
  String text;
  double marks;

  QuestionBranch({
    this.label = '',
    required this.text,
    this.marks = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'text': text,
      'marks': marks,
    };
  }

  factory QuestionBranch.fromMap(Map<String, dynamic> map) {
    final rawMarks = map['marks'];
    final parsedMarks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    return QuestionBranch(
      label: map['label']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      marks: parsedMarks != null && parsedMarks.isFinite && parsedMarks >= 0
          ? parsedMarks
          : 0.0,
    );
  }

  QuestionBranch copyWith({String? label, String? text, double? marks}) {
    return QuestionBranch(
      label: label ?? this.label,
      text: text ?? this.text,
      marks: marks ?? this.marks,
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

  /// قسم السؤال داخل المادة (القواعد/الأدب/إنشاء... مثلاً) لتقسيم ورقة الامتحان.
  String category;
  List<QuestionBranch> branches;
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
    this.category = '',
    List<QuestionBranch>? branches,
    List<QuestionOption>? options,
    this.modelAnswer = '',
    this.explanation = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        branches = List<QuestionBranch>.unmodifiable(
          _copyBranches(branches ?? const []),
        ),
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
      'category': category,
      'branches': branches.map((branch) => branch.toMap()).toList(growable: false),
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
      category: map['category']?.toString() ?? '',
      branches: _branchesFromValue(map['branches']),
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
    String? category,
    List<QuestionBranch>? branches,
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
      category: category ?? this.category,
      branches: branches ?? this.branches,
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

  static List<QuestionBranch> _branchesFromValue(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((branch) => QuestionBranch.fromMap(Map<String, dynamic>.from(branch)))
        .where((branch) => branch.text.trim().isNotEmpty || branch.marks > 0)
        .toList(growable: false);
  }

  static List<QuestionOption> _copyOptions(List<QuestionOption> source) {
    return source.map((option) => option.copyWith()).toList(growable: false);
  }

  static List<QuestionBranch> _copyBranches(List<QuestionBranch> source) {
    return source.map((branch) => branch.copyWith()).toList(growable: false);
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
