import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

ExamDocument _document({String subject = 'اللغة العربية', PaperSettings? settings}) {
  return ExamDocument(
    name: 'ورقة',
    header: ExamHeaderModel.initial(subject: subject),
    questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
    settings: settings,
  );
}

void main() {
  group('QuestionLabelStyle', () {
    test('defaults to ordinal and parses leniently', () {
      expect(const PaperSettings().questionLabelStyle, QuestionLabelStyle.ordinal);
      expect(QuestionLabelStyle.parse('compact'), QuestionLabelStyle.compact);
      expect(QuestionLabelStyle.parse('ordinal'), QuestionLabelStyle.ordinal);
      expect(QuestionLabelStyle.parse(null), QuestionLabelStyle.ordinal);
      expect(QuestionLabelStyle.parse('bogus'), QuestionLabelStyle.ordinal);
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
      // المستندات بلا الحقل تُفتح بالنمط الرسمي.
      expect(
        PaperSettings.fromMap(const <String, dynamic>{}).questionLabelStyle,
        QuestionLabelStyle.ordinal,
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

  group('PaperSettings', () {
    test('page numbers do not exist anywhere in the settings', () {
      final map = const PaperSettings().toMap();
      expect(map.keys.where((key) => key.toLowerCase().contains('pagenumber')), isEmpty);
      // مفتاح قديم في ملف محفوظ يُهمَل بلا أثر.
      final restored = PaperSettings.fromMap(<String, dynamic>{...map, 'showPageNumbers': true});
      expect(restored.toMap().containsKey('showPageNumbers'), isFalse);
    });

    test('the official label of the ordinal style hides the old wording', () {
      expect(QuestionLabelStyle.ordinal.arabicLabel, 'رسمي (السؤال الأول)');
      expect(QuestionLabelStyle.compact.arabicLabel, 'مختصر (س1)');
    });

    test('the page frame image is stored as a path and cleared with copyWith', () {
      const settings = PaperSettings(pageBorder: true, frameImagePath: '/tmp/frame.png');
      expect(settings.hasFrameImage, isTrue);
      final restored = PaperSettings.fromMap(settings.toMap());
      expect(restored, settings);
      expect(restored.frameImagePath, '/tmp/frame.png');

      final cleared = settings.copyWith(frameImagePath: () => null);
      expect(cleared.hasFrameImage, isFalse);
      expect(cleared.toMap().containsKey('frameImagePath'), isFalse);
      expect(settings.copyWith(marginMm: 12).frameImagePath, '/tmp/frame.png');
    });

    test('the margin is clamped to the slider range', () {
      expect(PaperSettings.fromMap(const <String, dynamic>{'marginMm': 2}).marginMm,
          PaperSettings.minMarginMm);
      expect(PaperSettings.fromMap(const <String, dynamic>{'marginMm': 90}).marginMm,
          PaperSettings.maxMarginMm);
      expect(const PaperSettings().marginMm, PaperSettings.defaultMarginMm);
    });
  });

  group('ExamDocument question labels', () {
    test('uses ordinal labels by default', () {
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
      final ordinal = _document(subject: 'اللغة الإنجليزية');
      expect(
        ordinal.displayQuestionLabel(ordinal.questions.single),
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
