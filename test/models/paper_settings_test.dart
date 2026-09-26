import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

ExamDocument _document({String subject = 'اللغة العربية', PaperSettings? settings}) {
  return ExamDocument(
    name: 'ورقة',
    header: ExamHeaderModel.ministerialDefault(subject: subject),
    questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
    settings: settings,
  );
}

void main() {
  group('QuestionLabelStyle', () {
    test('defaults to ministerial and parses leniently', () {
      expect(const PaperSettings().questionLabelStyle, QuestionLabelStyle.ministerial);
      expect(QuestionLabelStyle.parse('compact'), QuestionLabelStyle.compact);
      expect(QuestionLabelStyle.parse('ministerial'), QuestionLabelStyle.ministerial);
      expect(QuestionLabelStyle.parse(null), QuestionLabelStyle.ministerial);
      expect(QuestionLabelStyle.parse('bogus'), QuestionLabelStyle.ministerial);
    });

    test('round-trips through settings serialization', () {
      const settings = PaperSettings(
        questionLabelStyle: QuestionLabelStyle.compact,
        baseFontSize: 12,
        lineSpacing: 1.8,
        marginMm: 20,
      );
      final restored = PaperSettings.fromMap(settings.toMap());
      expect(restored, settings);
      expect(restored.questionLabelStyle, QuestionLabelStyle.compact);
      // المستندات القديمة (بلا الحقل) تُفتح بالنمط الوزاري.
      expect(
        PaperSettings.fromMap(const <String, dynamic>{}).questionLabelStyle,
        QuestionLabelStyle.ministerial,
      );
    });

    test('exposes scale factors around the reference values', () {
      expect(const PaperSettings().fontScale, 1.0);
      expect(const PaperSettings().heightScale, 1.0);
      expect(
        const PaperSettings(baseFontSize: 12).fontScale,
        closeTo(12 / 10.5, 0.0001),
      );
      expect(
        const PaperSettings(lineSpacing: 2).heightScale,
        closeTo(2 / 1.45, 0.0001),
      );
    });
  });

  group('ExamDocument question labels', () {
    test('uses ministerial labels by default', () {
      final document = _document();
      expect(
        document.displayQuestionLabel(document.questions.single),
        'السؤال الأول',
      );
    });

    test('uses compact labels with the sheet numeral style', () {
      final arabicIndic = _document(
        settings: const PaperSettings(questionLabelStyle: QuestionLabelStyle.compact),
      );
      expect(
        arabicIndic.displayQuestionLabel(arabicIndic.questions.single),
        'س١',
      );
      final latin = _document(
        settings: const PaperSettings(
          questionLabelStyle: QuestionLabelStyle.compact,
          numerals: PaperNumerals.latin,
        ),
      );
      expect(latin.displayQuestionLabel(latin.questions.single), 'س1');
    });

    test('keeps Q1 labels for LTR sheets in both styles', () {
      final ministerial = _document(subject: 'اللغة الإنجليزية');
      expect(
        ministerial.displayQuestionLabel(ministerial.questions.single),
        'Q1',
      );
      final compact = _document(
        subject: 'اللغة الإنجليزية',
        settings: const PaperSettings(questionLabelStyle: QuestionLabelStyle.compact),
      );
      expect(compact.displayQuestionLabel(compact.questions.single), 'Q1');
    });

    test('manual label override wins over both styles', () {
      final document = _document(
        settings: const PaperSettings(questionLabelStyle: QuestionLabelStyle.compact),
      );
      final manual = document.questions.single.copyWith(
        numberOverride: () => 'سؤال التميز',
      );
      expect(document.displayQuestionLabel(manual), 'سؤال التميز');
      // التسمية التلقائية تتجاهل اليدوية (تُستخدم تلميحاً في المحرر).
      expect(document.autoQuestionLabel(manual), 'س١');
      expect(document.autoBranchLabel(0), 'أ');
      expect(document.autoBranchLabel(2), 'ج');
    });
  });
}
