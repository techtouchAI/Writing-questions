// تطابق العقد: الرقم الواحد يصل إلى المعاينة وPDF.
//
// هذا الاختبار لا يقارن «شيفرة بشيفرة» بل **قيمة بقيمة**: لكل عنصر
// (قسم، عنوان سؤال، متن، نقطة) يُقاس:
//   * المعاينة: نمط Flutter المشتق من العقد (بكسل اللوحة).
//   * PDF: الحجم الفعلي داخل الملف (عبر PdfContentProbe) — لا وجود الشيفرة.
// ويُعاد الاختبار نفسه بمعاملَي قياس (fontScale/heightScale ≠ 1) لإثبات أن
// القياس يُطبَّق مرة واحدة ولا يُضاعف في أي مسار.
//
// (حُذفت في C5 مع Word القابل للتحرير: قيم `w:sz`/`w:ind`/`w:spacing` داخل
// الفقرة واختبارا الفرع والخيار — Word اليوم صور لا بنية.)
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_style.dart';
import 'package:writing_questions_app/layout/visual/visual_typography.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/subject_layout.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/views/wizard/paper_styles.dart';

import '../pdf_engine/pdf_content_probe.dart';

QuestionModel _question() => QuestionModel(
      id: 'q1',
      questionNumber: 1,
      category: 'Cat',
      statement: 'Stmt',
      body: 'BodyText',
      marksOverride: 10,
      items: <BranchItem>[
        BranchItem(
          id: 'p1',
          kind: PointKind.multipleChoice,
          text: 'PointText',
          options: <QuestionOption>[QuestionOption(text: 'OptA')],
        ),
      ],
      branches: <BranchModel>[
        BranchModel(
          id: 'b1',
          marks: 4,
          content: BranchContent(
            statement: 'BranchTitle',
            body: 'BranchBody',
          ),
        ),
      ],
    );

ExamDocument _document({PaperSettings settings = const PaperSettings()}) =>
    ExamDocument(
      name: 'تطابق العقود',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      settings: settings,
      questions: <QuestionModel>[_question()],
    );

/// حجم الخط الفعلي في PDF لأول سطر يحوي [needle] (نقاط).
double _pdfFontSizeFor(PdfContentProbe probe, String needle) {
  for (final line in probe.lines) {
    if (line.words.any((word) => word.text.contains(needle))) {
      return line.fontSize;
    }
  }
  fail('لم أجد سطراً يحوي «$needle» في PDF.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // المعاملات الافتراضية (fontScale = heightScale = 1).
  group('القيم الافتراضية: نفس الرقم في العقد والمعاينة وPDF', () {
    const settings = PaperSettings();

    test('القسم: 12.5pt في العقد والمعاينة وPDF', () async {
      final document = _document();
      final contract = ExamTypography.resolve(
        VisualRole.category,
        settings: settings,
        layout: SubjectLayoutTemplate.arabic,
      );
      expect(contract.fontSizePt, 12.5);

      // المعاينة: نفس القيمة بالبكسل.
      final preview = PaperStyles.role(VisualRole.category,
          layout: SubjectLayoutTemplate.arabic);
      expect(preview.reference.fontSizePt, contract.fontSizePt);

      // PDF: السطر المرسوم فعلاً.
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'Cat'), closeTo(12.5, 0.01));
    });

    test('عنوان السؤال: 11pt مرسوماً في PDF', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'Stmt'), closeTo(11, 0.01));
    });

    test('نص السؤال: 11pt مرسوماً في PDF', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'BodyText'), closeTo(11, 0.01));
    });

    test('النقطة: 10.5pt مرسومة في PDF', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'PointText'), closeTo(10.5, 0.01));
    });

  });

  // معامل القياس العام: يُطبَّق مرة واحدة في كل المسارات.
  group('fontScale/heightScale = 1.25: القياس مرة واحدة', () {
    const settings = PaperSettings(
      baseFontSize: 10.5 * 1.25,
      lineSpacing: 1.45 * 1.25,
    );

    test('عنوان السؤال: 13.75pt و510 تويب في العقد وPDF', () async {
      final document = _document(settings: settings);
      final contract = ExamTypography.resolve(
        VisualRole.questionTitle,
        settings: settings,
        layout: SubjectLayoutTemplate.arabic,
      );
      expect(contract.fontSizePt, closeTo(13.75, 1e-9));
      expect(contract.lineTwips, 510); // 240 × 1.7 × 1.25

      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'Stmt'), closeTo(13.75, 0.05),
          reason: 'PDF يجب أن يحمل الحجم المقاس مرة واحدة، لا 17.2pt.');
    });

    test('القسم: 15.625pt → 31 نصف نقطة، والمعاينة بنفس البكسل', () {
      final contract = ExamTypography.resolve(
        VisualRole.category,
        settings: settings,
        layout: SubjectLayoutTemplate.arabic,
      );
      expect(contract.halfPoints, 31);
      final preview = PaperStyles.resolve(
        PaperStyles.category,
        null,
        fontScale: settings.fontScale,
        heightScale: settings.heightScale,
      );
      expect(
        preview.fontSize,
        closeTo(PaperMetrics.px(contract.fontSizePt), 0.01),
        reason: 'المعاينة تحوّل القيمة نفسها إلى بكسل اللوحة.',
      );
    });
  });

  // مسح معاملات القياس: الحجم والمسافات يتغيّران في العقد والمعاينة وPDF
  // **بنفس الاتجاه والنسبة** — لا مسار يتجاهل المعامل ولا مسار يضاعفه.
  group('مسح fontScale × heightScale', () {
    for (final fontScale in const <double>[0.8, 1.0, 1.2]) {
      for (final heightScale in const <double>[0.9, 1.0, 1.1]) {
        test('fontScale=$fontScale heightScale=$heightScale', () async {
          final settings = PaperSettings(
            baseFontSize: PaperSettings.referenceFontSize * fontScale,
            lineSpacing: PaperSettings.referenceLineSpacing * heightScale,
          );
          final document = _document(settings: settings);
          final contract = ExamTypography.resolve(
            VisualRole.questionTitle,
            settings: settings,
            layout: document.layout,
          );
          expect(contract.fontSizePt, closeTo(11 * fontScale, 1e-9));

          // PDF: الحجم المرسوم فعلاً.
          final bytes =
              await PaginatedPdfExamEngine().generate(document: document);
          expect(
            _pdfFontSizeFor(PdfContentProbe.fromBytes(bytes), 'Stmt'),
            closeTo(contract.fontSizePt, 0.05),
          );

          // المعاينة: النمط نفسه محوَّلاً إلى بكسل اللوحة.
          final preview = PaperStyles.resolve(
            PaperStyles.question,
            null,
            fontScale: fontScale,
            heightScale: heightScale,
          );
          expect(
            preview.fontSize,
            closeTo(PaperMetrics.px(contract.fontSizePt), 0.01),
          );
          expect(preview.height, closeTo(contract.lineHeight, 1e-9));
        });
      }
    }
  });
}
