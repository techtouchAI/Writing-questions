import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';

/// اتجاه العرض في العقد البصري — مستقل عن Flutter وعن pdf حتى يصلح للثلاثة.
enum VisualDirection { rtl, ltr }

/// دور العنصر في الورقة: هو مفتاح التنسيق الوحيد.
///
/// كل راسم (المعاينة، PDF، Word) يطلب النمط بالدور من [VisualTypography]
/// ولا يحمل أرقاماً خاصة به — فحجم «سطر القسم» أو «نص النقطة» يُكتب مرة
/// واحدة في العقد، ويُترجم بعدها إلى بكسل الشاشة أو نقاط PDF أو أنصاف نقاط
/// Word بتحويلات موحّدة.
enum VisualRole {
  /// سطر عنوان الورقة الرئيسي (اسم الامتحان).
  headerTitle,

  /// أسطر الترويسة العادية (الإدارة/المادة/الصف/الوقت).
  headerBody,

  /// البسملة أعلى الترويسة.
  bismillah,

  /// شارة صغيرة (نوع السؤال/التلميح).
  badge,

  /// عنوان قسم السؤال («القواعد»).
  category,

  /// سطر عنوان السؤال (الرقم + المنطوق + الدرجة).
  questionTitle,

  /// نص السؤال.
  questionBody,

  /// سطر عنوان الفرع.
  branchTitle,

  /// نص الفرع.
  branchBody,

  /// نص نقطة (سؤال مباشر أو فرع).
  point,

  /// نص خيار «اختيار من متعدد».
  option,

  /// آية قائمة بذاتها.
  verse,

  /// ملاحظة صغيرة.
  small,

  /// ملاحظة متوسطة.
  note,

  /// سطر التذييل (التوقيعات والعبارة الختامية).
  footer,
}

/// نمط نصّي في العقد البصري: القيم **نهائية** (بعد كل معاملات القياس).
///
/// [fontSizePt] بالنقاط (وحدة الطباعة) و[lineHeight] مضاعف ارتفاع السطر
/// (baseline-to-baseline = [lineHeight] × [fontSizePt]) — نفس دلالة
/// `TextStyle.height` في Flutter و`lineHeight` في المعاينة.
class VisualTextStyle {
  const VisualTextStyle({
    required this.role,
    required this.font,
    required this.fontSizePt,
    required this.lineHeight,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
    this.letterSpacingPt,
    this.align,
  });

  /// الدور الذي وُلد منه النمط (للتوثيق والاختبارات).
  final VisualRole role;

  final PaperFont font;

  /// حجم الخط النهائي بالنقاط (بعد `fontScale`).
  final double fontSizePt;

  /// مضاعف ارتفاع السطر النهائي (بعد `heightScale`).
  final double lineHeight;

  final bool bold;
  final bool italic;
  final bool underline;

  /// لون ARGB مخصص (`null` = لون الورقة الافتراضي الأسود).
  final int? color;

  final double? letterSpacingPt;

  /// محاذاة مخصّصة لهذا العنصر (`null` = محاذاة الدور/السياق).
  final PaperAlign? align;

  /// حجم الخط ببكسل لوحة المعاينة (96dpi).
  ///
  /// لا يُستدعى هنا [PaperMetrics] لتظل هذه الطبقة نقية، فالحساب في
  /// مُلحِق المعاينة ([VisualStyleToFlutter]).
  VisualTextStyle copyWith({
    VisualRole? role,
    PaperFont? font,
    double? fontSizePt,
    double? lineHeight,
    bool? bold,
    bool? italic,
    bool? underline,
    int? Function()? color,
    double? Function()? letterSpacingPt,
    PaperAlign? Function()? align,
  }) {
    return VisualTextStyle(
      role: role ?? this.role,
      font: font ?? this.font,
      fontSizePt: fontSizePt ?? this.fontSizePt,
      lineHeight: lineHeight ?? this.lineHeight,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      color: color != null ? color() : this.color,
      letterSpacingPt: letterSpacingPt != null ? letterSpacingPt() : this.letterSpacingPt,
      align: align != null ? align() : this.align,
    );
  }

  /// حجم الخط بأنصاف النقاط كما يكتبه Word (`w:sz`).
  int get halfPoints => (fontSizePt * 2).round();

  /// ارتفاع السطر بتوينب Word (`w:line` مع `w:lineRule="auto"`؛ 240 = مفرد).
  int get lineTwips => (240 * lineHeight).round();

  /// تباعد الأسطر كما تحسبه مكتبة pdf: إزاحة السطر التالي عن الطبيعي
  /// (تُحسب في مُلحِق pdf حيث يتوفر مقاس الخط المحمّل).
  @override
  String toString() => 'VisualTextStyle(${role.name}, ${fontSizePt}pt, '
      '×$lineHeight${bold ? ', bold' : ''})';
}
