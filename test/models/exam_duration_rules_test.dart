import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_duration_rules.dart';

void main() {
  group('ExamDurationRules.calculate', () {
    test('الصف المتوسط + مادة لغوية = ساعتان', () {
      expect(
        ExamDurationRules.calculate(
          grade: 'الأول المتوسط',
          subject: 'اللغة العربية',
        ),
        'ساعتان',
      );
      expect(
        ExamDurationRules.calculate(
          grade: 'الثالث المتوسط',
          subject: 'اللغة الإنجليزية',
        ),
        'ساعتان',
      );
    });

    test('الصف المتوسط + مادة غير لغوية = ساعة ونصف', () {
      expect(
        ExamDurationRules.calculate(
          grade: 'الثاني المتوسط',
          subject: 'الرياضيات',
        ),
        'ساعة ونصف',
      );
      expect(
        ExamDurationRules.calculate(grade: 'الثالث المتوسط', subject: 'العلوم'),
        'ساعة ونصف',
      );
    });

    test('غير المتوسط + مادة لغوية = ساعتان ونصف', () {
      expect(
        ExamDurationRules.calculate(
          grade: 'الصف الثالث الثانوي',
          subject: 'اللغة الإنجليزية',
        ),
        'ساعتان ونصف',
      );
      expect(
        ExamDurationRules.calculate(
          grade: 'الصف الخامس الابتدائي',
          subject: 'اللغة العربية',
        ),
        'ساعتان ونصف',
      );
    });

    test('غير المتوسط + مادة غير لغوية = ساعتان', () {
      expect(
        ExamDurationRules.calculate(
          grade: 'الصف السادس الابتدائي',
          subject: 'العلوم',
        ),
        'ساعتان',
      );
      expect(
        ExamDurationRules.calculate(
          grade: 'الصف الثالث الثانوي',
          subject: 'الكيمياء',
        ),
        'ساعتان',
      );
    });
  });

  group('ExamDurationRules predicates', () {
    test('يكتشف مرحلة المتوسط من تسمية الصف', () {
      expect(ExamDurationRules.isMiddleSchoolGrade('الثالث المتوسط'), isTrue);
      expect(ExamDurationRules.isMiddleSchoolGrade(' الصف الأول المتوسط '), isTrue);
      expect(ExamDurationRules.isMiddleSchoolGrade('الصف الثالث الثانوي'), isFalse);
      expect(ExamDurationRules.isMiddleSchoolGrade(''), isFalse);
    });

    test('يكتشف مادتي اللغتين بصيغ متعددة', () {
      expect(ExamDurationRules.isLanguageSubject('اللغة العربية'), isTrue);
      expect(ExamDurationRules.isLanguageSubject('اللغة الإنجليزية'), isTrue);
      expect(ExamDurationRules.isLanguageSubject('الرياضيات'), isFalse);
      expect(ExamDurationRules.isLanguageSubject(''), isFalse);
    });
  });
}
