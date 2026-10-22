import 'package:uuid/uuid.dart';

import 'paper_text_style.dart';
import 'text_format_span.dart';

/// خيار في سؤال «اختيار من متعدد».
class QuestionOption {
  QuestionOption({
    String? id,
    required this.text,
    this.labelOverride,
    this.align,
    List<TextFormatSpan>? formats,
  })  : id = id ?? const Uuid().v4(),
        formats = List<TextFormatSpan>.unmodifiable(
          formats ?? const <TextFormatSpan>[],
        );

  final String id;
  String text;

  /// تنسيق نطاقات نصّ الخيار (محارف محدَّدة داخل [text]).
  final List<TextFormatSpan> formats;

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
      if (formats.isNotEmpty)
        'formats': formats.map((span) => span.toMap()).toList(growable: false),
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
      formats: TextFormatSpan.listFromValue(map['formats']),
    );
  }

  QuestionOption copyWith({
    String? text,
    String? Function()? labelOverride,
    PaperAlign? Function()? align,
    List<TextFormatSpan>? formats,
  }) {
    final nextText = text ?? this.text;
    return QuestionOption(
      id: id,
      text: nextText,
      labelOverride: labelOverride == null ? this.labelOverride : labelOverride(),
      align: align == null ? this.align : align(),
      // إزاحات التنسيق تتبع نصّ الخيار، فأي مسار تحرير يُعيد تأسيسها.
      formats: formats ??
          TextFormatSpans.rebase(
            this.formats,
            previous: this.text,
            next: nextText,
          ),
    );
  }
}
