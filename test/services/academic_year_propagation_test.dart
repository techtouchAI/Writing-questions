// =============================================================================
// العام الدراسي: مصدر واحد، وتحديث فوري، واستمرار عبر الحفظ وإعادة التحميل
// إلى التصدير.
//
// العقد المُثبَّت هنا:
//   1. `ExamHeaderModel.academicYear` هو المصدر الوحيد؛ لا قيمة افتراضية
//      تُحقن في المعاينة أو التصدير (الافتراضي يُحسب مرة واحدة في
//      `ExamHeaderModel.initial` ثم يُحفظ).
//   2. تعديل الترويسة يُبطل كاشات `ExamBlueprint`/`DocumentIR` فتصل القيمة
//      الجديدة إلى المعاينة والتصدير في الطلب نفسه (لا قيمة قديمة).
//   3. الحفظ وإعادة التحميل تعيدان القيمة نفسها (لا إعادة حساب للعام الحالي).
//   4. نسق الأرقام يتبع إعداد الورقة فقط، ولا يغيّر قيمة العام المخزّنة.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

ExamDocument _document({
  String year = '2026/2027',
  PaperSettings settings = const PaperSettings(),
}) =>
    ExamDocument(
      name: 'عام دراسي',
      header: ExamHeaderModel(
        schoolName: 'مدرسة',
        examType: 'نصف السنة',
        academicYear: year,
        subject: 'اللغة العربية',
        showBismillah: false,
      ),
      settings: settings,
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'سؤال'),
      ],
    );

/// سطر العام كما يصل إلى المخطط (المصدر الذي يرسمه كلٌّ من المعاينة وPDF).
String? _yearLine(ExamBlueprint blueprint) {
  for (final line in blueprint.header.centerContentLines) {
    if (line.field == HeaderFieldKind.academicYear) return line.text;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('العام الدراسي — مصدر واحد', () {
    test('الحقل المحرَّر هو ما يصل إلى مخطط المعاينة/التصدير', () {
      final controller = ExamWizardController(document: _document());
      final document = controller.document;
      expect(
        _yearLine(controller.blueprint),
        '${ExamCatalog.academicYearPrefix} '
        '${document.localizeDigits(document.header.academicYear)}',
      );
    });

    test('تعديل العام يُحدّث المخطط وIR فوراً (لا كاش قديم)', () {
      final controller = ExamWizardController(document: _document());
      final before = controller.blueprint;
      final beforeIr = controller.documentIr;

      controller.updateHeader(
        controller.document.header.copyWith(academicYear: '2027/2028'),
      );

      expect(controller.blueprint, isNot(same(before)),
          reason: 'لم يُبَطل كاش المخطط بعد تعديل الترويسة.');
      expect(controller.documentIr, isNot(same(beforeIr)),
          reason: 'لم يُبَطل كاش DocumentIR بعد تعديل الترويسة.');

      final yearNew = controller.document.localizeDigits('2027');
      expect(_yearLine(controller.blueprint), contains(yearNew),
          reason: 'العام الجديد لم يصل إلى مخطط المعاينة: '
              '${_yearLine(controller.blueprint)}');
      expect(
        controller.documentIr.header.centerColumn
            .firstWhere((line) => line.field == HeaderFieldKind.academicYear)
            .content
            .legacyText,
        contains(yearNew),
        reason: 'العام الجديد لم يصل إلى DocumentIR الذي يرسمه PDF.',
      );
      expect(_yearLine(controller.blueprint), isNot(contains('2026')));
    });

    test('الحفظ وإعادة التحميل يحفظان القيمة ولا يعيدان حساب «العام الحالي»',
        () {
      final original = _document(year: '2024/2025');
      final restored = ExamDocument.fromJson(original.toJson());
      expect(restored.header.academicYear, '2024/2025');

      final controller = ExamWizardController(document: restored);
      expect(_yearLine(controller.blueprint),
          contains(restored.document.localizeDigits('2024')),
          reason: 'إعادة التحميل استبدلت العام المحفوظ بعام آخر.');
    });

    test('نسق الأرقام يتبع الورقة ولا يغيّر قيمة العام المخزّنة', () {
      final indic = _document(
        settings: const PaperSettings(numerals: PaperNumerals.arabicIndic),
      );
      final latin = _document(
        settings: const PaperSettings(numerals: PaperNumerals.latin),
      );
      expect(_yearLine(ExamBlueprint.from(indic)), contains('٢٠٢٦'));
      expect(_yearLine(ExamBlueprint.from(latin)), contains('2026'));
      expect(_yearLine(ExamBlueprint.from(latin)), isNot(contains('٢٠٢٦')));
      // المخزَّن لم يُمسّ في الحالتين.
      expect(indic.header.academicYear, '2026/2027');
      expect(latin.header.academicYear, '2026/2027');
    });

    test('قاعدة بداية العام الدراسي في أيلول ثابتة', () {
      expect(AcademicYear.current(DateTime(2026, 9, 1)), '2026/2027');
      expect(AcademicYear.current(DateTime(2026, 8, 31)), '2025/2026');
      expect(AcademicYear.suggestions(DateTime(2026, 9, 1)),
          contains('2026/2027'));
    });

    test('ورقة جديدة تأخذ العام الحالي مرة واحدة عند الإنشاء فقط', () {
      final initial = ExamHeaderModel.initial(now: DateTime(2027, 2, 1));
      expect(initial.academicYear, '2026/2027');
      final edited = initial.copyWith(academicYear: '2030/2031');
      expect(edited.copyWith(examType: 'نهاية السنة').academicYear,
          '2030/2031');
    });

    test('إعدادات الورقة لا تحقن عاماً من عندها', () {
      final document = _document(
        year: '2031/2032',
        settings: const PaperSettings(showQuestionMarks: false),
      );
      expect(_yearLine(ExamBlueprint.from(document)),
          contains(document.localizeDigits('2031')));
    });
  });
}
