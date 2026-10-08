// تكافؤ x الكنسي في PDF المتجه: عامل النص الفعلي في الملف يجب أن يستخدم
// x السطر الكنسي نفسه وخط الأساس الكنسي — لا إعادة حساب في مسار PDF.
//
// (نُقل حرفياً من ملف انحدار اتجاه Word المحذوف في C5؛ هذا الاختبار لم
// يمسّ Word قط — يقارن `CanonicalLayoutService` ببايتات PDF فقط.)
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import 'pdf_content_probe.dart';

const String _centerMarker = 'REGCENTERTOKEN';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExamFonts pdfFonts;

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
    pdfFonts = await ExamFonts.load();
  });

  test('centered statement marker uses the canonical x in vector pdf',
      () async {
    final document = ExamDocument(
      name: 'Centered parity',
      header: ExamHeaderModel(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          titleAlign: PaperAlign.center,
          statement: 'نص عربي $_centerMarker وبعده.',
          body: 'متن قصير.',
        ),
      ],
    );
    final layout = await CanonicalLayoutService.resolve(document: document);
    final target = <({int pageIndex, double x, double baseline, double fontSize})>[
      for (final page in layout.pages)
        for (final block in page.blocks)
          for (final line in block.allLines)
            for (final run in line.runs)
              if (run.text.contains(_centerMarker))
                (
                  pageIndex: page.index,
                  x: run.x,
                  baseline: line.baseline,
                  fontSize: run.style.fontSizePt,
                ),
    ].single;
    final bytes = await PaginatedPdfExamEngine().generate(
      document: document,
      layoutDocument: layout,
      fonts: pdfFonts,
    );
    final pdfPageCount = PdfContentProbe.pageCountOf(bytes);
    expect(pdfPageCount, layout.pageCount);
    final pdfHits = <({int pageIndex, ProbedWord word})>[];
    for (var pageIndex = 0; pageIndex < pdfPageCount; pageIndex++) {
      final probe = PdfContentProbe.fromBytes(
        Uint8List.fromList(bytes),
        pageIndex: pageIndex,
      );
      for (final word in probe.words.where(
        (word) => word.text == _centerMarker,
      )) {
        pdfHits.add((pageIndex: pageIndex, word: word));
      }
    }
    expect(pdfHits, hasLength(1));
    final pdfHit = pdfHits.single;
    expect(pdfHit.pageIndex, target.pageIndex);
    expect(pdfHit.word.fontSize, closeTo(target.fontSize, 0.02));
    expect(pdfHit.word.x, closeTo(target.x, 2.5),
        reason: 'The actual PDF text operator must use the canonical run x.');
    expect(
      layout.pages[pdfHit.pageIndex].pageSize.height - pdfHit.word.y,
      closeTo(target.baseline, 4.0),
      reason: 'The actual PDF text baseline must map to the canonical baseline.',
    );
  });
}
