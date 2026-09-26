import 'package:uuid/uuid.dart';

/// خيار إجابة في سؤال الاختيار من متعدد / صح وخطأ.
class QuestionOption {
  QuestionOption({
    String? id,
    required this.text,
    this.isCorrect = false,
    this.labelOverride,
  }) : id = id ?? const Uuid().v4();

  final String id;
  String text;
  bool isCorrect;

  /// تسمية مخصصة للخيار يثبّتها المدرس.
  ///
  /// - `null` = التسمية التلقائية من الفهرس (( أ )، ( ب )...).
  /// - نص فارغ `''` = بلا تسمية إطلاقاً (تُخفى ولا تترك مسافة).
  /// - أي نص آخر = يُعرض حرفياً ولا يعاد ترقيمه أبداً.
  String? labelOverride;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'isCorrect': isCorrect,
      if (labelOverride != null) 'labelOverride': labelOverride,
    };
  }

  /// يقرأ خياراً من مخزون JSON/Map **بشكل صارم**؛ تركيب تالف يرمي
  /// [FormatException] ليُعزل السجل التالف بواسطة [StorageService].
  /// الحقل الجديد (التسمية المخصصة) متسامح لتبقى الخيارات القديمة صالحة.
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
      labelOverride: map['labelOverride'] is String ? map['labelOverride'] as String : null,
    );
  }

  QuestionOption copyWith({String? text, bool? isCorrect, String? Function()? labelOverride}) {
    return QuestionOption(
      id: id,
      text: text ?? this.text,
      isCorrect: isCorrect ?? this.isCorrect,
      labelOverride: labelOverride == null ? this.labelOverride : labelOverride(),
    );
  }
}
