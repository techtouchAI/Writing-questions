// المستند الإنجليزي (LTR) كمستند كامل: اتجاه الفقرات والترويسة والتذييل
// وعناوين الأسئلة والدرجات والأرقام وتقسيم الصفحات — في المعاينة (LayoutDocument)
// وفي PDF.
//
// العيب الذي كان قائماً: `DocumentIR` يثبّت اتجاه الترويسة والتذييل على `rtl`
// (`HeaderBlock/FooterBlock/HeaderLineBlock` وبناءها في `_header/_footer`)،
// فورقة إنجليزية تُرسم حقولها من اليمين. هنا يُقاس الاتجاه من مصدره الواحد
// (اتجاه المستند) في التخطيط المشترك ثم في ملف PDF فعلي.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../../export_gate/p0_gate_fixture.dart';
import '../../export_gate/pdf_structure_probe.dart';
import '../../pdf_engine/pdf_content_probe.dart';

LayoutDocument _layout(ExamDocument document) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: ExamDocumentLayoutAdapter.configurationFor(document),
    fontMetrics: const FlutterTextMetrics(),
  );
}

Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    yield* _allBlocks(block.children);
  }
}

/// أسطر كل الكتل التي يبدأ معرّفها الدلالي بـ[prefix].
List<LayoutLine> _linesWithPrefix(LayoutDocument layout, String prefix) =>
    <LayoutLine>[
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            if (line.semanticNodeId.startsWith(prefix)) line,
    ];

ProbedLine _pdfLineWith(PdfStructureReport report, String marker) =>
    report.pages
        .expand((page) => page.lines)
        .firstWhere(
          (line) => line.words.any((word) => word.text.contains(marker)),
          orElse: () => throw StateError('لا سطر يحمل الوسم $marker في PDF.'),
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test('العقد الدلالي: اتجاه الترويسة والتذييل من اتجاه المستند لا مثبَّتاً',
      () {
    final ltr = P0GateFixture.ltr();
    final ltrIr = DocumentIR.fromBlueprint(
      blueprint: ExamBlueprint.from(ltr),
      document: ltr,
    );
    expect(ltrIr.direction, DocumentDirection.ltr);
    expect(ltrIr.header.allLines, isNotEmpty,
        reason: 'الترويسة بلا أسطر: القياس بلا عيّنة.');
    for (final line in ltrIr.header.allLines) {
      expect(line.direction, DocumentDirection.ltr,
          reason: 'حقل ترويسة في ورقة إنجليزية ما زال RTL (${line.field}).');
    }
    expect(ltrIr.footer.closingPhrase!.direction, DocumentDirection.ltr);
    for (final signature in ltrIr.footer.signatures) {
      expect(signature.direction, DocumentDirection.ltr,
          reason: 'توقيع في تذييل ورقة إنجليزية ما زال RTL.');
    }

    // الاتجاه لا يُقلب على العربية: المستند العربي يبقى RTL كما كان.
    final rtl = P0GateFixture.rtl();
    final rtlIr = DocumentIR.fromBlueprint(
      blueprint: ExamBlueprint.from(rtl),
      document: rtl,
    );
    expect(rtlIr.direction, DocumentDirection.rtl);
    for (final line in rtlIr.header.allLines) {
      expect(line.direction, DocumentDirection.rtl);
    }
  });

  test('التخطيط المشترك: ترويسة/تذييل/عنوان/متن إنجليزية كلها ltr', () {
    final ltr = P0GateFixture.ltr();
    final layout = _layout(ltr);

    final headerLines = _linesWithPrefix(layout, 'header');
    expect(headerLines, isNotEmpty, reason: 'لا أسطر ترويسة في التخطيط.');
    for (final line in headerLines) {
      expect(line.direction, DocumentDirection.ltr,
          reason: 'سطر ترويسة إنجليزي في التخطيط ليس ltr: ${line.id}');
    }
    for (final line in _linesWithPrefix(layout, 'footer')) {
      expect(line.direction, DocumentDirection.ltr,
          reason: 'سطر تذييل إنجليزي في التخطيط ليس ltr: ${line.id}');
    }
    final bodyLines = _linesWithPrefix(layout, 'p0lq1/body');
    expect(bodyLines, isNotEmpty, reason: 'لا أسطر متن في السؤال الأول.');
    for (final line in bodyLines) {
      expect(line.direction, DocumentDirection.ltr,
          reason: 'سطر متن إنجليزي في التخطيط ليس ltr: ${line.id}');
    }
    // التقسيم ما زال يعمل: الورقة الإنجليزية تتجاوز صفحة واحدة في التركيبة.
    expect(layout.pageCount, greaterThan(1),
        reason: 'تقسيم الصفحات الإنجليزي لا ينتج أكثر من صفحة.');
  });

  test('PDF: الترويسة والتذييل والعنوان تُرسم ltr بلا أرقام مشرقية', () async {
    final ltr = P0GateFixture.ltr();
    final fonts = await ExamFonts.load();
    final bytes = await PaginatedPdfExamEngine()
        .generate(document: ltr, fonts: fonts);
    final report = PdfStructureReport.fromBytes(bytes);

    // الترويسة (الوقت LTRT1) والتذييل (LTRF1) وعنوان السؤال (LTRSTA1).
    for (final marker in const <String>['LTRT1', 'LTRF1', 'LTRSTA1']) {
      final line = _pdfLineWith(report, marker);
      expect(PdfPageStructure.orderOfLine(line), 'ltr',
          reason: 'السطر الحامل $marker في PDF إنجليزي لا يتقدّم من اليسار: '
              '${line.describe()}');
    }

    // الأرقام في الورقة الإنجليزية لاتينية، لا مشرقية.
    final arabicIndic = report.pages
        .fold<int>(0, (sum, page) => sum + page.arabicIndicDigits);
    expect(arabicIndic, 0,
        reason: 'الورقة الإنجليزية تحمل $arabicIndic رقماً مشرقياً.');

    // النص ما زال قابل الاستخراج، والتقسيم لم ينكسر.
    final probe = PdfContentProbe.fromBytes(bytes, pageIndex: 0);
    expect(probe.words, isNotEmpty);
    expect(report.pageCount, greaterThan(1));
  });
}
