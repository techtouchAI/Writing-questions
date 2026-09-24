import 'dart:ui' show TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/subject_layout.dart';

void main() {
  group('SubjectLayoutTemplate.fromSubject', () {
    test('maps ministerial subjects to their templates', () {
      expect(SubjectLayoutTemplate.fromSubject('التربية الإسلامية'), SubjectLayoutTemplate.islamic);
      expect(SubjectLayoutTemplate.fromSubject('اللغة العربية'), SubjectLayoutTemplate.arabic);
      expect(SubjectLayoutTemplate.fromSubject('اللغة الإنجليزية'), SubjectLayoutTemplate.english);
      expect(SubjectLayoutTemplate.fromSubject('English'), SubjectLayoutTemplate.english);
      expect(SubjectLayoutTemplate.fromSubject('الفيزياء'), SubjectLayoutTemplate.scientific);
      expect(SubjectLayoutTemplate.fromSubject('الكيمياء'), SubjectLayoutTemplate.scientific);
      expect(SubjectLayoutTemplate.fromSubject('الرياضيات'), SubjectLayoutTemplate.scientific);
      expect(SubjectLayoutTemplate.fromSubject('علم الأحياء'), SubjectLayoutTemplate.scientific);
      expect(SubjectLayoutTemplate.fromSubject('التاريخ'), SubjectLayoutTemplate.generic);
    });

    test('parse is strict', () {
      expect(SubjectLayoutTemplate.parse('arabic'), SubjectLayoutTemplate.arabic);
      expect(() => SubjectLayoutTemplate.parse('latin'), throwsFormatException);
    });
  });

  group('English layout', () {
    const layout = SubjectLayoutTemplate.english;

    test('is fully LTR with Q1/Q2 numbering and A/B/C branches', () {
      expect(layout.textDirection, TextDirection.ltr);
      expect(layout.questionLabel(1), 'Q1');
      expect(layout.questionLabel(12), 'Q12');
      expect(layout.branchLabel(0), 'A');
      expect(layout.branchLabel(2), 'C');
      expect(layout.marksUnit, 'marks');
      expect(layout.formatNumber(2.5), '2.5');
      expect(layout.usesArabicIndicNumerals, isFalse);
    });
  });

  group('Arabic & Islamic layouts', () {
    test('use Arabic ordinals, Arabic letters and Arabic-Indic numerals', () {
      const arabic = SubjectLayoutTemplate.arabic;
      expect(arabic.textDirection, TextDirection.rtl);
      expect(arabic.questionLabel(1), 'السؤال الأول');
      expect(arabic.questionLabel(5), 'السؤال الخامس');
      expect(arabic.questionLabel(25), 'السؤال رقم 25');
      expect(arabic.branchLabel(0), 'أ');
      expect(arabic.branchLabel(3), 'د');
      expect(arabic.formatNumber(10), '١٠');
      expect(arabic.formatNumber(1.5), '١.٥');
      expect(arabic.sections, <String>['القواعد', 'الأدب والنصوص', 'الإملاء', 'الإنشاء']);
    });

    test('islamic template exposes the ministerial sections and quranic font hint', () {
      const islamic = SubjectLayoutTemplate.islamic;
      expect(islamic.prefersQuranicFont, isTrue);
      expect(
        islamic.sections,
        <String>['أحكام التلاوة', 'الحفظ', 'الفهم والتفسير', 'التربية الإسلامية'],
      );
    });
  });

  group('Scientific layout', () {
    test('keeps Latin numerals and grants more answer space', () {
      const scientific = SubjectLayoutTemplate.scientific;
      expect(scientific.formatNumber(7), '7');
      expect(scientific.essayAnswerLines, greaterThan(SubjectLayoutTemplate.generic.essayAnswerLines));
      expect(scientific.lineHeightFactor, greaterThan(SubjectLayoutTemplate.generic.lineHeightFactor));
      expect(scientific.textDirection, TextDirection.rtl);
    });
  });

  test('toArabicIndic converts only ASCII digits', () {
    expect(SubjectLayoutTemplate.toArabicIndic('س2026/2027 A'), 'س٢٠٢٦/٢٠٢٧ A');
  });
}
