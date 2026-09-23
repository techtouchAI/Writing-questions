/// المادة وأقسامها المعتمدة: يُستخدم لتنظيم الإدخال ولاختيار استراتيجية الـ PDF.
///
/// بدل ترك المعلم يكتب نصاً حراً غير منضبط، تعرض الواجهة قسماً مسبقاً
/// لكل مادة (قواعد/أدب/إنشاء للعربية مثلاً)، ويحوّل المحرك نفسه الأقسام
/// إلى عناوين داخل ورقة الامتحان.
abstract final class SubjectCatalog {
  static const String arabicSubject = 'اللغة العربية';
  static const String englishSubject = 'اللغة الإنجليزية';
  static const String islamicSubject = 'التربية الإسلامية';

  static const List<String> knownSubjects = <String>[
    arabicSubject,
    englishSubject,
    islamicSubject,
    'الرياضيات',
    'العلوم',
    'الدراسات الاجتماعية',
    'التربية الوطنية',
    'الحاسوب وعلوم المعلومات',
    'التربية الفنية',
    'عام',
  ];

  /// أقسام مادة اللغة العربية في ورقة الامتحان الرسمية.
  static const List<String> arabicCategories = <String>['القواعد', 'الأدب', 'الإنشاء'];

  /// أقسام مادة التربية الإسلامية.
  static const List<String> islamicCategories = <String>[
    'أحكام التلاوة',
    'الحفظ',
    'العقيدة',
    'الفقه',
    'السيرة النبوية',
  ];

  static bool isArabicSubject(String subject) => subject.trim().contains('عربي');

  static bool isEnglishSubject(String subject) => subject.trim().contains('إنجليز');

  static bool isIslamicSubject(String subject) {
    final normalized = subject.trim();
    return normalized.contains('إسلام') || normalized.contains('اسلام');
  }

  /// قسما المادة المسبقاً؛ قائمة فارغة تعني إدخال حرّ بدون أقسام.
  static List<String> categoriesFor(String subject) {
    if (isArabicSubject(subject)) {
      return List<String>.unmodifiable(arabicCategories);
    }
    if (isIslamicSubject(subject)) {
      return List<String>.unmodifiable(islamicCategories);
    }
    return List<String>.unmodifiable(const <String>[]);
  }
}
