import 'package:uuid/uuid.dart';

/// خيار إجابة في سؤال الاختيار من متعدد / صح وخطأ.
class QuestionOption {
  QuestionOption({
    String? id,
    required this.text,
    this.isCorrect = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  String text;
  bool isCorrect;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'isCorrect': isCorrect,
    };
  }

  /// يقرأ خياراً من مخزون JSON/Map **بشكل صارم**؛ تركيب تالف يرمي
  /// [FormatException] ليُعزل السجل التالف بواسطة [StorageService].
  factory QuestionOption.fromMap(Map<String, dynamic> map) {
    final rawText = map['text'];
    if (rawText != null && rawText is! String && rawText is! num) {
      throw const FormatException('QuestionOption: نص الخيار يجب أن يكون نصاً.');
    }
    final rawCorrect = map['isCorrect'];
    if (rawCorrect != null && rawCorrect is! bool) {
      throw const FormatException('QuestionOption: isCorrect يجب أن يكون منطقياً.');
    }

    return QuestionOption(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      isCorrect: rawCorrect == true,
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
