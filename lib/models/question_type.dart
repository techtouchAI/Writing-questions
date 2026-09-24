enum QuestionType {
  multipleChoice,
  trueFalse,
  fillInTheBlank,
  essay;

  String get arabicLabel {
    switch (this) {
      case QuestionType.multipleChoice:
        return 'اختيار من متعدد';
      case QuestionType.trueFalse:
        return 'صح أو خطأ';
      case QuestionType.fillInTheBlank:
        return 'إكمال الفراغ';
      case QuestionType.essay:
        return 'سؤال مقالي / شرح';
    }
  }

  /// يقرأ النوع **بشكل صارم**؛ القيم المجهولة أو المفقودة ترمي
  /// [FormatException] بدل إسناد نوع افتراضي وهمي يُخفي تلف البيانات.
  ///
  /// يقوم [StorageService] بعزل أي سجل يحتوي نوعاً غير معروف دون المساس
  /// ببقية السجلات السليمة.
  static QuestionType parse(String? value) {
    final normalized = value?.trim() ?? '';
    for (final type in QuestionType.values) {
      if (type.name == normalized) {
        return type;
      }
    }
    throw FormatException('QuestionType: نوع سؤال غير معروف (${value ?? 'مفقود'}).');
  }
}
