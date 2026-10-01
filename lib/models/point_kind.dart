/// نوع النقطة المرقّمة داخل مجموعة نقاط سؤال أو فرع.
///
/// الأنواع تُخلط بحرية داخل **المجموعة نفسها**؛ والترقيم (١-، ٢-، ٣-...)
/// تسلسل واحد متصل بالفهرس مهما اختلفت الأنواع.
enum PointKind {
  /// نص حر: يُطبع كما كُتب.
  plain,

  /// صح/خطأ: عبارة يليها قوسا إجابة فارغان.
  trueFalse,

  /// إكمال الفراغ: يُلحق فراغ منقّط بآخر الجملة إن لم يكتب المدرس فراغاً
  /// بنفسه (شرطات سفلية ___ أو نقاط ......).
  fillBlank,

  /// اختيار من متعدد: نص السؤال ثم خياراته ( أ )، ( ب )... في سطر تالٍ.
  multipleChoice;

  String get arabicLabel {
    switch (this) {
      case PointKind.plain:
        return 'نص حر';
      case PointKind.trueFalse:
        return 'صح أو خطأ';
      case PointKind.fillBlank:
        return 'إكمال الفراغ';
      case PointKind.multipleChoice:
        return 'اختيار من متعدد';
    }
  }

  /// تلميح حقل نص النقطة بحسب نوعها (إرشاد المدرس لما يكتب).
  String get textHint {
    switch (this) {
      case PointKind.plain:
        return 'اكتب نص النقطة هنا';
      case PointKind.trueFalse:
        return 'اكتب العبارة فقط (يُضاف قوسا الإجابة تلقائياً)';
      case PointKind.fillBlank:
        return 'اكتب الجملة (يُضاف فراغ منقّط في آخرها إن لم تضع ___ بنفسك)';
      case PointKind.multipleChoice:
        return 'اكتب نص السؤال (تُكتب الخيارات تحته)';
    }
  }

  /// قراءة متسامحة: أي قيمة مجهولة أو مفقودة تعطي [plain].
  static PointKind parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final kind in PointKind.values) {
      if (kind.name == normalized) {
        return kind;
      }
    }
    return PointKind.plain;
  }
}
