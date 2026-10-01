import 'paper_font.dart';

/// نسق الأرقام في الورقة.
enum PaperNumerals {
  /// يتبع قالب المادة (مشرقية للعربية والإسلامية، لاتينية لغيرهما).
  auto,

  /// أرقام عربية مشرقية دائماً (١٢٣).
  arabicIndic,

  /// أرقام لاتينية دائماً (123).
  latin;

  String get arabicLabel {
    switch (this) {
      case PaperNumerals.auto:
        return 'تلقائي حسب المادة';
      case PaperNumerals.arabicIndic:
        return 'أرقام عربية (١٢٣)';
      case PaperNumerals.latin:
        return 'أرقام لاتينية (123)';
    }
  }

  static PaperNumerals parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final numerals in PaperNumerals.values) {
      if (numerals.name == normalized) {
        return numerals;
      }
    }
    return PaperNumerals.auto;
  }
}

/// نمط تسمية الأسئلة في الورقة.
///
/// - [ordinal]: «السؤال الأول، السؤال الثاني...» (رسمي).
/// - [compact]: «س1، س2...» (مختصر، وQ1/Q2 للأوراق اللاتينية).
///
/// الرقم الذي يكتبه المدرس يدوياً على سؤال بعينه (numberOverride) يتقدم
/// دائماً على النمط العام أياً كان.
enum QuestionLabelStyle {
  ordinal,
  compact;

  String get arabicLabel {
    switch (this) {
      case QuestionLabelStyle.ordinal:
        return 'رسمي (السؤال الأول)';
      case QuestionLabelStyle.compact:
        return 'مختصر (س1)';
    }
  }

  static QuestionLabelStyle parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final style in QuestionLabelStyle.values) {
      if (style.name == normalized) {
        return style;
      }
    }
    return QuestionLabelStyle.ordinal;
  }
}

/// إعدادات الورقة العامة (ترقيم/أرقام/هوامش/خط افتراضي/إطارات).
///
/// كلها اختيارية ولها قيم افتراضية معقولة؛ المدرس يغيّر ما يشاء فقط.
/// القراءة متسامحة: المفتاح الناقص يأخذ قيمته الافتراضية، والمجهول يُتجاهل.
///
/// [baseFontSize] و[lineSpacing] يعملان كمعاملَي قياس عامّين حول القيم
/// المرجعية ([referenceFontSize]/[referenceLineSpacing]): القيمة
/// الافتراضية تعني معامل 1.0 (بلا تغيير)، والتنسيق المخصص لعنصر بعينه
/// (حجم/تباعد مطلق) يتقدم دائماً على القياس العامّ — في الشاشة والـ PDF
/// وملف Word بالقرار نفسه.
///
/// [marginMm] هو **المسافة بين حافة الورقة والنص** في كل الاتجاهات، ومنه
/// وحده يُشتق صندوق المحتوى في المعاينة وPDF وWord. وهو نفسه حشوة الإطار:
/// يُرسم الإطار ([pageBorder]) — إطاراً متجهاً بسيطاً أو صورة PNG شفافة
/// ([frameImagePath]) — داخل هذا الهامش فلا يتداخل مع النص أبداً.
///
/// لا ترقيم للصفحات في أي مخرَج: ليست خياراً أصلاً.
class PaperSettings {
  const PaperSettings({
    this.autoNumberQuestions = true,
    this.autoLetterBranches = true,
    this.numerals = PaperNumerals.auto,
    this.questionLabelStyle = QuestionLabelStyle.ordinal,
    this.showQuestionMarks = true,
    this.pageBorder = false,
    this.frameImagePath,
    this.headerBorder = true,
    this.defaultFont = PaperFont.naskh,
    this.baseFontSize = 10.5,
    this.lineSpacing = 1.45,
    this.marginMm = defaultMarginMm,
  });

  /// حجم خط المتن المرجعي بالنقاط (معامل القياس = baseFontSize / هذا).
  static const double referenceFontSize = 10.5;

  /// تباعد الأسطر المرجعي (معامل القياس = lineSpacing / هذا).
  static const double referenceLineSpacing = 1.45;

  /// هامش الصفحة الافتراضي بالمليمتر.
  static const double defaultMarginMm = 15;

  /// أصغر هامش وأكبره بالمليمتر (حدّا شريط «هوامش الصفحة»).
  static const double minMarginMm = 8;
  static const double maxMarginMm = 25;

  /// إعادة ترقيم الأسئلة تلقائياً (س1..سN) بعد الحذف/النقل.
  final bool autoNumberQuestions;

  /// إعادة ترميز الفروع تلقائياً (أ، ب، ج...) بعد الحذف/النقل.
  final bool autoLetterBranches;

  final PaperNumerals numerals;

  /// نمط تسمية الأسئلة (رسمي/مختصر).
  final QuestionLabelStyle questionLabelStyle;

  /// إظهار درجات الأسئلة والفروع «(٢٠ درجة)» في سطر العنوان.
  final bool showQuestionMarks;

  /// إطار حول كامل الصفحة (يتبع الهامش: انظر وصف الصنف).
  final bool pageBorder;

  /// مسار صورة PNG شفافة تُرسم إطاراً لصفحة A4 كاملة (`null` = إطار متجه).
  /// لا تظهر إلا مع تفعيل [pageBorder]. تُخزَّن كمسار ملف لا بايتات.
  final String? frameImagePath;

  /// إطار حول جدول الترويسة.
  final bool headerBorder;

  final PaperFont defaultFont;

  /// حجم خط المتن الأساسي بالنقاط.
  final double baseFontSize;

  /// تباعد الأسطر العام.
  final double lineSpacing;

  /// هامش الصفحة بالمليمتر (8..25).
  final double marginMm;

  /// هل يوجد إطار صورة مختار؟
  bool get hasFrameImage => frameImagePath != null && frameImagePath!.isNotEmpty;

  /// معامل قياس أحجام الخطوط العامة (1.0 عند القيمة الافتراضية).
  double get fontScale => baseFontSize / referenceFontSize;

  /// معامل قياس تباعد الأسطر العام (1.0 عند القيمة الافتراضية).
  double get heightScale => lineSpacing / referenceLineSpacing;

  PaperSettings copyWith({
    bool? autoNumberQuestions,
    bool? autoLetterBranches,
    PaperNumerals? numerals,
    QuestionLabelStyle? questionLabelStyle,
    bool? showQuestionMarks,
    bool? pageBorder,
    String? Function()? frameImagePath,
    bool? headerBorder,
    PaperFont? defaultFont,
    double? baseFontSize,
    double? lineSpacing,
    double? marginMm,
  }) {
    return PaperSettings(
      autoNumberQuestions: autoNumberQuestions ?? this.autoNumberQuestions,
      autoLetterBranches: autoLetterBranches ?? this.autoLetterBranches,
      numerals: numerals ?? this.numerals,
      questionLabelStyle: questionLabelStyle ?? this.questionLabelStyle,
      showQuestionMarks: showQuestionMarks ?? this.showQuestionMarks,
      pageBorder: pageBorder ?? this.pageBorder,
      frameImagePath:
          frameImagePath != null ? frameImagePath() : this.frameImagePath,
      headerBorder: headerBorder ?? this.headerBorder,
      defaultFont: defaultFont ?? this.defaultFont,
      baseFontSize: baseFontSize ?? this.baseFontSize,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      marginMm: marginMm ?? this.marginMm,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'autoNumberQuestions': autoNumberQuestions,
      'autoLetterBranches': autoLetterBranches,
      'numerals': numerals.name,
      'questionLabelStyle': questionLabelStyle.name,
      'showQuestionMarks': showQuestionMarks,
      'pageBorder': pageBorder,
      if (hasFrameImage) 'frameImagePath': frameImagePath,
      'headerBorder': headerBorder,
      'defaultFont': defaultFont.name,
      'baseFontSize': baseFontSize,
      'lineSpacing': lineSpacing,
      'marginMm': marginMm,
    };
  }

  factory PaperSettings.fromMap(Map<String, dynamic> map) {
    final rawFrame = map['frameImagePath'];
    return PaperSettings(
      autoNumberQuestions: _bool(map['autoNumberQuestions'], fallback: true),
      autoLetterBranches: _bool(map['autoLetterBranches'], fallback: true),
      numerals: PaperNumerals.parse(map['numerals']),
      questionLabelStyle: QuestionLabelStyle.parse(map['questionLabelStyle']),
      showQuestionMarks: _bool(map['showQuestionMarks'], fallback: true),
      pageBorder: _bool(map['pageBorder'], fallback: false),
      frameImagePath:
          rawFrame is String && rawFrame.trim().isNotEmpty ? rawFrame : null,
      headerBorder: _bool(map['headerBorder'], fallback: true),
      defaultFont: PaperFont.parse(map['defaultFont']),
      baseFontSize: _num(map['baseFontSize'], fallback: 10.5, min: 8, max: 16),
      lineSpacing: _num(map['lineSpacing'], fallback: 1.45, min: 1, max: 2.5),
      marginMm: _num(
        map['marginMm'],
        fallback: defaultMarginMm,
        min: minMarginMm,
        max: maxMarginMm,
      ),
    );
  }

  /// قراءة متسامحة من قيمة مخزنة (غياب الإعدادات = الافتراضي).
  static PaperSettings fromValue(Object? value) {
    if (value is! Map) {
      return const PaperSettings();
    }
    try {
      return PaperSettings.fromMap(Map<String, dynamic>.from(value));
    } catch (_) {
      return const PaperSettings();
    }
  }

  @override
  bool operator ==(Object other) {
    return other is PaperSettings &&
        other.autoNumberQuestions == autoNumberQuestions &&
        other.autoLetterBranches == autoLetterBranches &&
        other.numerals == numerals &&
        other.questionLabelStyle == questionLabelStyle &&
        other.showQuestionMarks == showQuestionMarks &&
        other.pageBorder == pageBorder &&
        other.frameImagePath == frameImagePath &&
        other.headerBorder == headerBorder &&
        other.defaultFont == defaultFont &&
        other.baseFontSize == baseFontSize &&
        other.lineSpacing == lineSpacing &&
        other.marginMm == marginMm;
  }

  @override
  int get hashCode => Object.hash(
        autoNumberQuestions,
        autoLetterBranches,
        numerals,
        questionLabelStyle,
        showQuestionMarks,
        pageBorder,
        frameImagePath,
        headerBorder,
        defaultFont,
        baseFontSize,
        lineSpacing,
        marginMm,
      );

  static bool _bool(Object? value, {required bool fallback}) {
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
    return fallback;
  }

  static double _num(Object? value, {
    required double fallback,
    required double min,
    required double max,
  }) {
    final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) {
      return fallback;
    }
    return parsed.clamp(min, max).toDouble();
  }
}
