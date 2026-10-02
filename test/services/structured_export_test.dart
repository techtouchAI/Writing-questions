// البنية لا النص المدموج: أجزاء العنصر تُصدَّر **جريانات/كتلاً مستقلة**.
//
// كانت `TitleLineBlueprint.line` و`PointBlueprint.line` و`OptionBlueprint.line`
// تُدمج (الرقم ← المنطوق ← الدرجة ← التسمية) في نص واحد، فيفقد الراسم قدرته
// على إعطاء كل جزء تنسيقه وموضعه (الرقم غامق، الدرجة عند حافة السطر، الخيار
// في صندوقه). هذه الاختبارات تُثبّت أن:
//   * Word: كل جزء جريان `<w:r>` مستقل (وعددها > 1 في الفقرة الواحدة).
//   * PDF: الخيارات في **صناديق ثابتة العرض** تتشارك السطر وتلتفّ كما في
//     المعاينة (لا نصاً واحداً يفصل بينه بمسافات NBSP).
//   * القيم (الحجم/الإزاحة/الفجوة/ارتفاع السطر) هي قيم العقد نفسه.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_typography.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

import '../pdf_engine/pdf_content_probe.dart';

ExamDocument _document() => ExamDocument(
      name: 'بنية',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      // أرقام لاتينية وتسميات صريحة: تُقرأ صريحةً من PDF أيضاً.
      settings: const PaperSettings(numerals: PaperNumerals.latin),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'Cat',
          statement: 'Stmt',
          marksOverride: 12,
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'PointOne',
              marks: 3,
              options: <QuestionOption>[
                QuestionOption(text: 'OptA', labelOverride: 'A)'),
                QuestionOption(text: 'OptB', labelOverride: 'B)'),
                QuestionOption(text: 'OptC', labelOverride: 'C)'),
                QuestionOption(text: 'OptD', labelOverride: 'D)'),
              ],
            ),
          ],
        ),
      ],
    );

Future<String> _docxXml(ExamDocument document) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
}

/// فقرة Word التي تحوي [needle] كاملةً (من `<w:p>` إلى `</w:p>`).
String _paragraphWith(String xml, String needle) {
  for (final match in RegExp('<w:p>.*?</w:p>', dotAll: true).allMatches(xml)) {
    if (match.group(0)!.contains(needle)) {
      return match.group(0)!;
    }
  }
  fail('لم أجد فقرة تحوي «$needle».');
}

int _runsIn(String paragraph) => RegExp('<w:r>').allMatches(paragraph).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Word: الأجزاء جريانات مستقلة', () {
    test('سطر العنوان: الرقم والمنطوق والدرجة في جريانات منفصلة', () async {
      final document = _document();
      final question = document.questions.single;
      final label = document.displayQuestionLabel(question);
      final xml = await _docxXml(document);
      final title = _paragraphWith(xml, 'Stmt');
      expect(_runsIn(title), greaterThanOrEqualTo(3),
          reason: 'الرقم ← المنطوق ← الدرجة ثلاثة جريانات، لا نص واحد.');
      expect(title.contains('>$label</w:t>') || title.contains('>$label<'),
          isTrue,
          reason: 'رقم السؤال «$label» جريان مستقل.');
      // مجمّع النص يعيد السطر كما في المعاينة (الأجزاء تفصلها مسافة واحدة).
      final plain = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
          .allMatches(title)
          .map((match) => match.group(1))
          .join();
      // الأجزاء الثلاثة متتالية بمسافة واحدة، والدرجة في آخر السطر.
      expect(plain, startsWith('$label Stmt '));
      expect(plain, contains('12'));
      expect(plain, endsWith(')'));
    });

    test('سطر النقطة: التسمية غامقة وحدها والنص غير غامق', () async {
      final xml = await _docxXml(_document());
      final point = _paragraphWith(xml, 'PointOne');
      expect(_runsIn(point), greaterThanOrEqualTo(3),
          reason: 'الرقم ← النص ← الدرجة ثلاثة جريانات.');
      // جريان التسمية وحده يحمل <w:b/> داخل خصائصه.
      final labelRun = RegExp(r'<w:r><w:rPr>(?:(?!</w:rPr>).)*<w:b/>'
              r'(?:(?!</w:rPr>).)*</w:rPr><w:t[^>]*>[^<]*</w:t></w:r>')
          .firstMatch(point);
      expect(labelRun, isNotNull, reason: 'التسمية جريان غامق مستقل.');
      // وجريان النص نفسه (الذي يحمل «PointOne») ليس غامقاً.
      final textRun = RegExp(r'<w:r><w:rPr>((?:(?!</w:rPr>).)*)</w:rPr>'
              r'<w:t[^>]*>PointOne</w:t></w:r>')
          .firstMatch(point);
      expect(textRun, isNotNull);
      expect(textRun!.group(1)!.contains('<w:b/>'), isFalse,
          reason: 'نص النقطة ليس غامقاً: الغامق للتسمية وحدها.');
    });

    test('صف الخيارات: لكل خيار تسمية ونص جريانين مستقلين', () async {
      final xml = await _docxXml(_document());
      final options = _paragraphWith(xml, 'OptA');
      // 4 تسميات + 4 نصوص = 8 جريانات على الأقل (وفواصل بينها).
      expect(_runsIn(options), greaterThanOrEqualTo(8),
          reason: 'كل خيار: التسمية جريان والنص جريان — لا سطر مدموج.');
      for (final label in const <String>['A)', 'B)', 'C)', 'D)']) {
        expect(options.contains('>$label</w:t>') || options.contains('>$label<'),
            isTrue,
            reason: 'تسمية الخيار $label جريان مستقل.');
      }
      expect(options.contains('<w:r><w:rPr>'), isTrue);
    });
  });

  group('Word: قيم العقد نفسها (لا أرقام محلية)', () {
    test('الحجم والإزاحة وارتفاع السطر والفجوة من ExamTypography/VisualMetrics',
        () async {
      final xml = await _docxXml(_document());
      final point = _paragraphWith(xml, 'PointOne');
      expect(
        point.contains(
          '<w:ind w:right="${PaperMetrics.twips(VisualMetrics.pointIndentPx)}"/>',
        ),
        isTrue,
        reason: 'إزاحة النقطة من VisualMetrics لا رقم مكتوب في الخدمة.',
      );
      expect(point.contains('<w:sz w:val="21"/>'), isTrue,
          reason: 'حجم النقطة 10.5pt → 21 نصف نقطة من العقد.');
      expect(point.contains('w:line="360"'), isTrue,
          reason: 'ارتفاع سطر النقطة 1.5 → 360 تويب من العقد.');

      final options = _paragraphWith(xml, 'OptA');
      expect(
        options.contains(
          '<w:ind w:right="${PaperMetrics.twips(VisualMetrics.pointIndentPx) + PaperMetrics.twips(VisualMetrics.optionIndentPx)}"/>',
        ),
        isTrue,
        reason: 'إزاحة الخيارات = إزاحة النقطة + إزاحتها من العقد.',
      );
      expect(options.contains('<w:sz w:val="21"/>'), isTrue);
      expect(options.contains('w:line="336"'), isTrue,
          reason: 'ارتفاع سطر الخيار 1.4 → 336 تويب من العقد.');
      expect(
        options.contains('w:before="${PaperMetrics.twips(VisualMetrics.optionTopGapPx)}"'),
        isTrue,
        reason: 'الفجوة قبل صف الخيارات من العقد (2px → 30 تويب).',
      );
    });
  });

  group('PDF: الخيارات صناديق ثابتة العرض في سطر واحد', () {
    test('ثلاثة خيارات تشترك السطر والرابع يلتفّ، والعرض عرض العقد', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      ProbedWord option(String text) => probe.words.firstWhere(
            (word) => word.text.contains(text),
            orElse: () => fail('كلمة الخيار «$text» لم تُرسم في PDF.'),
          );

      final a = option('OptA');
      final b = option('OptB');
      final c = option('OptC');
      final d = option('OptD');

      expect(a.y, closeTo(b.y, 0.5), reason: 'الخياران الأول والثاني في سطر واحد.');
      expect(b.y, closeTo(c.y, 0.5), reason: 'ثلاثة خيارات تتشارك السطر كما في المعاينة.');
      expect(d.y, lessThan(a.y),
          reason: 'الخيار الرابع يلتفّ إلى صف جديد (Wrap) كما في المعاينة.');

      // الترتيب من اليمين إلى اليسار: الأول يميناً ثم التالي يساراً.
      expect(a.x, greaterThan(b.x));
      expect(b.x, greaterThan(c.x));

      // المسافة بين صندوقين متجاورين = عرض الصندوق + الفجوة (من العقد).
      final step = PaperMetrics.pt(
        VisualMetrics.optionBoxWidthPx + VisualMetrics.optionWrapSpacingPx,
      );
      expect((a.x - b.x).abs(), closeTo(step, 1.0),
          reason: 'عرض صندوق الخيار وفجوته من العقد لا من قياس النص الحر.');
      expect(
        probe.words.any((word) => word.text.contains('PointOne')),
        isTrue,
        reason: 'نص النقطة مرسوم ككلمة مستقلة عن تسميتها.',
      );
      expect(
        probe.words.any((word) => word.text.contains('1-')),
        isTrue,
        reason: 'تسمية النقطة كتلة مستقلة (لا نص مدموج مع النص).',
      );
    });
  });
}
