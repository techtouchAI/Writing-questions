import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_header.dart';

void main() {
  group('ExamHeader structured fields', () {
    test('round-trips directorate, section, examType, and date', () {
      final header = ExamHeader(
        institutionName: 'مدرسة النهضة',
        directorate: 'مديرية تربية بغداد',
        section: 'شعبة 1',
        examType: 'اختبار نصف السنة',
        title: 'اختبار نصف السنة',
        subject: 'اللغة العربية',
        gradeStage: 'الثالث المتوسط',
        duration: '',
        examDate: DateTime(2026, 1, 15),
      );

      final restored = ExamHeader.fromMap(header.toMap());

      expect(restored.directorate, header.directorate);
      expect(restored.section, 'شعبة 1');
      expect(restored.examType, 'اختبار نصف السنة');
      expect(restored.examDate, DateTime(2026, 1, 15));
    });

    test('fills empty defaults for legacy stored maps', () {
      final restored = ExamHeader.fromMap(const {
        'institutionName': 'وزارة التربية',
        'title': 'اختبار قديم',
        'subject': 'الرياضيات',
        'gradeStage': 'الخامس الابتدائي',
        'academicYear': '2024 - 2025',
        'duration': 'ساعة واحدة',
        'instructor': 'أ. سعيد',
        'generalInstructions': 'أجب بالترتيب.',
      });

      expect(restored.directorate, '');
      expect(restored.section, '');
      expect(restored.examType, '');
      expect(restored.examDate, isNull);
      expect(restored.title, 'اختبار قديم');
      expect(restored.duration, 'ساعة واحدة');
    });

    test('ignores an unparseable exam date', () {
      final restored = ExamHeader.fromMap(const {'examDate': 'ليست تاريخاً'});
      expect(restored.examDate, isNull);
    });
  });

  group('ExamHeader.computedDuration', () {
    test('keeps the manual value when present', () {
      final header = ExamHeader(duration: '90 دقيقة');
      expect(header.computedDuration, '90 دقيقة');
    });

    test('falls back to ministry rules when duration is empty', () {
      final header = ExamHeader(
        gradeStage: 'الثالث المتوسط',
        subject: 'اللغة العربية',
        duration: '',
      );
      expect(header.computedDuration, 'ساعتان');
    });
  });
}
