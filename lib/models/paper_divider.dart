/// فاصل أفقي (خط) بعد سؤال أو فرع: ────────────
///
/// يُخزَّن داخل مالكه (السؤال/الفرع) فينتقل معه عند إعادة الترتيب،
/// ويُقاس معه فلا يكسر التقسيم الورقي.
class PaperDivider {
  const PaperDivider({
    this.thickness = 1.2,
    this.widthFraction = 1.0,
    this.spacingBefore = 6.0,
    this.spacingAfter = 6.0,
  });

  /// سماكة الخط بالنقاط (0.5..6).
  final double thickness;

  /// نسبة العرض من عرض المحتوى (0.2..1.0).
  final double widthFraction;

  /// مسافة قبل/بعد الفاصل بالنقاط.
  final double spacingBefore;
  final double spacingAfter;

  PaperDivider copyWith({
    double? thickness,
    double? widthFraction,
    double? spacingBefore,
    double? spacingAfter,
  }) {
    return PaperDivider(
      thickness: thickness ?? this.thickness,
      widthFraction: widthFraction ?? this.widthFraction,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      spacingAfter: spacingAfter ?? this.spacingAfter,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'thickness': thickness,
      'widthFraction': widthFraction,
      'spacingBefore': spacingBefore,
      'spacingAfter': spacingAfter,
    };
  }

  /// قراءة متسامحة: أي قيمة تالفة ترتد إلى الافتراضي.
  factory PaperDivider.fromMap(Map<String, dynamic> map) {
    return PaperDivider(
      thickness: _num(map['thickness'], fallback: 1.2, min: 0.5, max: 6),
      widthFraction: _num(map['widthFraction'], fallback: 1, min: 0.2, max: 1),
      spacingBefore: _num(map['spacingBefore'], fallback: 6, min: 0, max: 40),
      spacingAfter: _num(map['spacingAfter'], fallback: 6, min: 0, max: 40),
    );
  }

  /// يقرأ فاصلاً من قيمة مخزنة؛ الغياب يعني «لا فاصل»، والتلف يُتجاهل.
  static PaperDivider? fromValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      return null;
    }
    try {
      return PaperDivider.fromMap(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is PaperDivider &&
        other.thickness == thickness &&
        other.widthFraction == widthFraction &&
        other.spacingBefore == spacingBefore &&
        other.spacingAfter == spacingAfter;
  }

  @override
  int get hashCode => Object.hash(thickness, widthFraction, spacingBefore, spacingAfter);

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
