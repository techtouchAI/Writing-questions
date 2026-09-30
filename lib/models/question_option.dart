import 'package:uuid/uuid.dart';

import 'paper_text_style.dart';

/// خيار في سؤال «اختيار من متعدد».
class QuestionOption {
  QuestionOption({
    String? id,
    required this.text,
    this.labelOverride,
    this.align,
  }) : id = id ?? const Uuid().v4();

  final String id;
  String text;

  /// محاذاة هذا الخيار وحده (null = وراثة من محاذاة الفرع).
  ///
  /// Word/MSO يحاذي كل فقرة على حدة؛ النقر على زر المحاذاة وأنت في خيار
  /// لا يجوز أن يُعيد توجيه نص الفرع أو خيارات أخرى.
  final PaperAlign? align;

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
      if (labelOverride != null) 'labelOverride': labelOverride,
      if (align != null) 'align': align!.name,
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
    final rawAlign = map['align'];

    return QuestionOption(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      labelOverride: map['labelOverride'] is String ? map['labelOverride'] as String : null,
      align: rawAlign != null ? PaperAlign.parse(rawAlign) : null,
    );
  }

  QuestionOption copyWith({
    String? text,
    String? Function()? labelOverride,
    PaperAlign? Function()? align,
  }) {
    return QuestionOption(
      id: id,
      text: text ?? this.text,
      labelOverride: labelOverride == null ? this.labelOverride : labelOverride(),
      align: align == null ? this.align : align(),
    );
  }
}
