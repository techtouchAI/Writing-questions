enum Difficulty {
  easy,
  medium,
  hard;

  String get arabicLabel {
    switch (this) {
      case Difficulty.easy:
        return 'سهل';
      case Difficulty.medium:
        return 'متوسط';
      case Difficulty.hard:
        return 'صعب';
    }
  }

  /// يقرأ المستوى **بشكل صارم**؛ القيم المجهولة ترمي [FormatException]
  /// بدل إخفاء تلف البيانات خلف قيمة افتراضية.
  ///
  /// القيم المفقودة تماماً تُعامَل لاحقاً في طبقة النماذج (افتراضي: متوسط).
  static Difficulty parse(String? value) {
    final normalized = value?.trim() ?? '';
    for (final difficulty in Difficulty.values) {
      if (difficulty.name == normalized) {
        return difficulty;
      }
    }
    throw FormatException('Difficulty: مستوى صعوبة غير معروف (${value ?? 'مفقود'}).');
  }
}
