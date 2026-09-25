import 'paper_font.dart';

/// محاذاة النص داخل الورقة.
///
/// [start]/[end] منطقيان (يتبعان RTL/LTR)، و[left]/[right] مطلقان،
/// و[center]/[justify] كما هو متوقع.
enum PaperAlign {
  start,
  center,
  end,
  justify,
  left,
  right;

  String get arabicLabel {
    switch (this) {
      case PaperAlign.start:
        return 'بداية السطر';
      case PaperAlign.center:
        return 'توسيط';
      case PaperAlign.end:
        return 'نهاية السطر';
      case PaperAlign.justify:
        return 'ضبط';
      case PaperAlign.left:
        return 'يسار';
      case PaperAlign.right:
        return 'يمين';
    }
  }

  /// قراءة متسامحة: أي قيمة مجهولة ترتد إلى [start].
  static PaperAlign parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final align in PaperAlign.values) {
      if (align.name == normalized) {
        return align;
      }
    }
    return PaperAlign.start;
  }
}

/// تنسيق نص عنصر واحد في الورقة (سؤال/فرع/نقطة/ترويسة/مربع نص).
///
/// كل الحقول اختيارية: القيمة `null` تعني «وراثة من إعدادات الورقة»،
/// فيبقى التنسيق الافتراضي موحداً ما لم يخصّص المدرس عنصراً بعينه.
/// الكائن غير قابل للتغيير ويُدمج عبر [merge].
class PaperTextStyle {
  const PaperTextStyle({
    this.font,
    this.fontSize,
    this.bold,
    this.italic,
    this.underline,
    this.align,
    this.lineHeight,
  });

  /// النمط الفارغ: يرث كل شيء من الورقة.
  static const PaperTextStyle empty = PaperTextStyle();

  final PaperFont? font;

  /// حجم الخط بالنقاط (8..28 منطقياً).
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final PaperAlign? align;

  /// تباعد الأسطر (1.0..2.5 منطقياً).
  final double? lineHeight;

  bool get isEmpty =>
      font == null &&
      fontSize == null &&
      bold == null &&
      italic == null &&
      underline == null &&
      align == null &&
      lineHeight == null;

  bool get isNotEmpty => !isEmpty;

  /// يدمج [other] فوق هذا النمط (قيم [other] غير الفارغة تسود).
  PaperTextStyle merge(PaperTextStyle? other) {
    if (other == null || other.isEmpty) {
      return this;
    }
    return PaperTextStyle(
      font: other.font ?? font,
      fontSize: other.fontSize ?? fontSize,
      bold: other.bold ?? bold,
      italic: other.italic ?? italic,
      underline: other.underline ?? underline,
      align: other.align ?? align,
      lineHeight: other.lineHeight ?? lineHeight,
    );
  }

  PaperTextStyle copyWith({
    PaperFont? Function()? font,
    double? Function()? fontSize,
    bool? Function()? bold,
    bool? Function()? italic,
    bool? Function()? underline,
    PaperAlign? Function()? align,
    double? Function()? lineHeight,
  }) {
    return PaperTextStyle(
      font: font != null ? font() : this.font,
      fontSize: fontSize != null ? fontSize() : this.fontSize,
      bold: bold != null ? bold() : this.bold,
      italic: italic != null ? italic() : this.italic,
      underline: underline != null ? underline() : this.underline,
      align: align != null ? align() : this.align,
      lineHeight: lineHeight != null ? lineHeight() : this.lineHeight,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (font != null) 'font': font!.name,
      if (fontSize != null) 'fontSize': fontSize,
      if (bold != null) 'bold': bold,
      if (italic != null) 'italic': italic,
      if (underline != null) 'underline': underline,
      if (align != null) 'align': align!.name,
      if (lineHeight != null) 'lineHeight': lineHeight,
    };
  }

  /// قراءة متسامحة: الحقول التالفة تُتجاهل بدل إسقاط المستند كاملاً.
  factory PaperTextStyle.fromMap(Map<String, dynamic> map) {
    return PaperTextStyle(
      font: map.containsKey('font') ? PaperFont.parse(map['font']) : null,
      fontSize: _optionalDouble(map['fontSize'], min: 6, max: 40),
      bold: _optionalBool(map['bold']),
      italic: _optionalBool(map['italic']),
      underline: _optionalBool(map['underline']),
      align: map.containsKey('align') ? PaperAlign.parse(map['align']) : null,
      lineHeight: _optionalDouble(map['lineHeight'], min: 1, max: 3),
    );
  }

  /// يقرأ نمطاً من قيمة مخزنة (خريطة أو غياب) دون رمي أي استثناء.
  static PaperTextStyle fromValue(Object? value) {
    if (value is! Map) {
      return PaperTextStyle.empty;
    }
    try {
      return PaperTextStyle.fromMap(Map<String, dynamic>.from(value));
    } catch (_) {
      return PaperTextStyle.empty;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is PaperTextStyle &&
        other.font == font &&
        other.fontSize == fontSize &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.align == align &&
        other.lineHeight == lineHeight;
  }

  @override
  int get hashCode => Object.hash(font, fontSize, bold, italic, underline, align, lineHeight);

  static double? _optionalDouble(Object? value, {required double min, required double max}) {
    final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) {
      return null;
    }
    return parsed.clamp(min, max).toDouble();
  }

  static bool? _optionalBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    return null;
  }
}
