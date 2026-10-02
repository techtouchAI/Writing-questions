// تطابق عقد التصدير: الرقم الواحد يصل إلى المعاينة وPDF وWord.
//
// هذا الاختبار لا يقارن «شيفرة بشيفرة» بل **قيمة بقيمة**: لكل عنصر (قسم،
// عنوان سؤال، متن، نقطة، خيار، فرع) يُقاس:
//   * المعاينة: نمط Flutter المشتق من العقد (بكسل اللوحة).
//   * PDF: حجم الخط الفعلي داخل الملف (عبر PdfContentProbe) — لا وجود الشيفرة.
//   * Word: قيم `w:sz`/`w:ind`/`w:spacing` داخل الفقرة نفسها في مستند مفكوك.
// ويُعاد الاختبار نفسه بمعاملَي قياس (fontScale/heightScale ≠ 1) لإثبات أن
// القياس يُطبَّق مرة واحدة في الثلاثة ولا يُضاعف في أي مسار.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_style.dart';
import 'package:writing_questions_app/layout/visual/visual_typography.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/subject_layout.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/views/wizard/paper_styles.dart';

import '../pdf_engine/pdf_content_probe.dart';

QuestionModel _question() => QuestionModel(
      id: 'q1',
      questionNumber: 1,
      category: 'القواعد',
      statement: 'منطوق السؤال',
      body: 'نص السؤال',
      marks: 10,
      items: <BranchItem>[
        BranchItem(
          id: 'p1',
          kind: PointKind.multipleChoice,
          text: 'نقطة السؤال',
          options: <QuestionOption>[QuestionOption(text: 'خيار أول')],
        ),
      ],
      branches: <BranchModel>[
        BranchModel(
          id: 'b1',
          marks: 4,
          content: BranchContent(
            statement: 'عنوان الفرع',
            body: 'نص الفرع',
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

/// فقرة Word التي تحوي [needle] كاملةً (من `<w:p>` إلى `</w:p>`).
String _paragraphWith(String xml, String needle) {
  final matches = RegExp('<w:p>.*?</w:p>', dotAll: true).allMatches(xml);
  for (final match in matches) {
    if (match.group(0)!.contains(needle)) {
      return match.group(0)!;
    }
  }
  fail('لم أجد فقرة تحوي «$needle» في مستند Word.');
}

Future<String> _docxXml(ExamDocument document) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
}

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
  group('القيم الافتراضية: نفس الرقم في الثلاثة', () {
    const settings = PaperSettings();

    test('القسم: 12.5pt في العقد وPDF، و25 نصف نقطة في Word', () async {
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
      expect(_pdfFontSizeFor(probe, 'القواعد'), closeTo(12.5, 0.01));

      // Word: w:sz/w:szCs من نفس القيمة.
      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'القواعد');
      expect(paragraph.contains('<w:sz w:val="25"/>'), isTrue);
      expect(paragraph.contains('<w:szCs w:val="25"/>'), isTrue);
    });

    test('عنوان السؤال: 11pt، وارتفاع سطر 1.7 (408 تويب)', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'منطوق'), closeTo(11, 0.01));

      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'منطوق');
      expect(paragraph.contains('<w:sz w:val="22"/>'), isTrue);
      expect(paragraph.contains('w:line="408"'), isTrue,
          reason: '240 × 1.7 = 408 — ارتفاع سطر العنوان من العقد لا من إعداد الورقة.');
      expect(paragraph.contains('<w:b/>'), isTrue,
          reason: 'عنوان السؤال غامق في الأدوار الثلاثة (المعاينة/PDF/Word).');
    });

    test('نص السؤال: 11pt وبلا غامق، وفجوته من العقد (30 تويب)', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'نص السؤال'), closeTo(11, 0.01));

      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'نص السؤال');
      expect(paragraph.contains('<w:sz w:val="22"/>'), isTrue);
      expect(paragraph.contains('<w:b/>'), isFalse);
      expect(
        paragraph.contains('w:before="${PaperMetrics.twips(VisualMetrics.elementGapPx)}"'),
        isTrue,
        reason: 'الفجوة قبل النص = VisualMetrics.elementGapPx محوّلة بتويب الأداة.',
      );
    });

    test('النقطة والخيار: 10.5pt (21 نصف نقطة) وإزاحة 540 تويب', () async {
      final document = _document();
      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(_pdfFontSizeFor(probe, 'نقطة السؤال'), closeTo(10.5, 0.01));

      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'نقطة السؤال');
      expect(paragraph.contains('<w:sz w:val="21"/>'), isTrue);
      expect(
        paragraph.contains(
          '<w:ind w:right="${PaperMetrics.twips(VisualMetrics.pointIndentPx)}"/>',
        ),
        isTrue,
        reason: 'إزاحة النقطة 36px في المعاينة = 540 تويب في Word.',
      );
      expect(paragraph.contains('w:line="360"'), isTrue,
          reason: '240 × 1.5 = 360 لارتفاع سطر النقطة من العقد.');
    });

    test('الفرع: إزاحة 390 تويب وخط 348 (1.45)', () async {
      final document = _document();
      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'عنوان الفرع');
      expect(
        paragraph.contains(
          '<w:ind w:right="${PaperMetrics.twips(VisualMetrics.branchIndentPx)}"/>',
        ),
        isTrue,
      );
      expect(paragraph.contains('w:line="348"'), isTrue);
    });

    test('الخيار: إزاحة النقطة + 300 تويب', () async {
      final document = _document();
      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'خيار أول');
      expect(
        paragraph.contains(
          '<w:ind w:right="${PaperMetrics.twips(VisualMetrics.pointIndentPx) + PaperMetrics.twips(VisualMetrics.optionIndentPx)}"/>',
        ),
        isTrue,
      );
    });
  });

  // معامل القياس العام: يُطبَّق مرة واحدة في كل المسارات.
  group('fontScale/heightScale = 1.25: القياس مرة واحدة', () {
    const settings = PaperSettings(
      baseFontSize: 10.5 * 1.25,
      lineSpacing: 1.45 * 1.25,
    );

    test('عنوان السؤال: 13.75pt و510 تويب في الثلاثة', () async {
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
      expect(_pdfFontSizeFor(probe, 'منطوق'), closeTo(13.75, 0.05),
          reason: 'PDF يجب أن يحمل الحجم المقاس مرة واحدة، لا 17.2pt.');

      final xml = await _docxXml(document);
      final paragraph = _paragraphWith(xml, 'منطوق');
      expect(paragraph.contains('<w:sz w:val="28"/>'), isTrue,
          reason: 'round(13.75 × 2) = 28 — قياس واحد لا مضاعف.');
      expect(paragraph.contains('w:line="510"'), isTrue);
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
}
