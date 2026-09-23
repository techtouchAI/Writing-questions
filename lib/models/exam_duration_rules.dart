/// حساب زمن الاختبار آلياً وفق القواعد المتعارف عليها في وزارة التربية.
///
/// القاعدة:
/// - الصفوف المتوسطة: اللغتان ساعتان، وبقية المواد ساعة ونصف.
/// - غير المتوسطة (الابتدائي/الثانوي): اللغتان ساعتان ونصف، وبقية المواد ساعتان.
abstract final class ExamDurationRules {
  /// هل الصف من مرحلة المتوسطة؟
  static bool isMiddleSchoolGrade(String grade) {
    final normalized = grade.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('المتوسط');
  }

  /// مادتا اللغتين: العربية والإنجليزية (يقبل صيغاً اختصاراً).
  static bool isLanguageSubject(String subject) {
    final normalized = subject.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('عربي') || normalized.contains('إنجليز');
  }

  /// النص الزمني الجاهز لعرضه في الترويسة والـ PDF.
  static String calculate({required String grade, required String subject}) {
    final language = isLanguageSubject(subject);
    if (isMiddleSchoolGrade(grade)) {
      return language ? 'ساعتان' : 'ساعة ونصف';
    }
    return language ? 'ساعتان ونصف' : 'ساعتان';
  }
}
