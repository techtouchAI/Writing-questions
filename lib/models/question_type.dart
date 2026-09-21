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

  static QuestionType fromString(String val) {
    return QuestionType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => QuestionType.multipleChoice,
    );
  }
}
