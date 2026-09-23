import '../models/subject_catalog.dart';
import 'exam_strategy.dart';
import 'strategies/arabic_exam_strategy.dart';
import 'strategies/english_exam_strategy.dart';
import 'strategies/generic_exam_strategy.dart';
import 'strategies/islamic_exam_strategy.dart';

/// سجل استراتيجيات الـ PDF: يحوّل اسم المادة إلى الاستراتيجية المناسبة.
///
/// إضافة مادة جديدة = إضافة استراتيجية واحدة وسطر واحد هنا،
/// وليس تعديل شجرة شروط داخل المحرك.
abstract final class ExamStrategies {
  static ExamStrategy forSubject(String subject) {
    if (SubjectCatalog.isArabicSubject(subject)) {
      return const ArabicExamStrategy();
    }
    if (SubjectCatalog.isIslamicSubject(subject)) {
      return const IslamicExamStrategy();
    }
    if (SubjectCatalog.isEnglishSubject(subject)) {
      return const EnglishExamStrategy();
    }
    return const GenericExamStrategy();
  }
}
