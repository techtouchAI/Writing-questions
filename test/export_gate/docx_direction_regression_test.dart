// Focused regression tests for editable-DOCX direction (the P0-GATE-06/07/11
// contracts) plus the centered-line vector-PDF case: tiny documents built
// inline, asserting the artifact bytes via [OoxmlProbe]/[PdfContentProbe].
// These run in seconds and pinpoint the direction layer without the full
// gate fixture — they do not replace the P0 gates, they guard the fix.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

import '../pdf_engine/pdf_content_probe.dart';
import 'ooxml_probe.dart';

const String _marker = 'REGDIR1';
const String _centerMarker = 'REGCENTERTOKEN';

bool _hasArabic(String text) =>
    text.runes.any((rune) => rune >= 0x0600 && rune <= 0x06FF);

bool _hasArabicIndicDigit(String text) =>
    text.runes.any((rune) => rune >= 0x0660 && rune <= 0x0669);

ExamDocument _rtlDoc({String? statement, bool withPoint = false}) =>
    ExamDocument(
      name: 'انحدار الاتجاه',
      header: ExamHeaderModel(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: statement ?? 'أجب عن $_marker ثم راجع.',
          body: 'نص المتن.',
          items: withPoint
              ? <BranchItem>[
                  BranchItem(
                    id: 'p1',
                    kind: PointKind.multipleChoice,
                    text: 'نص النقطة',
                    options: <QuestionOption>[QuestionOption(text: 'أ')],
                  ),
                ]
              : null,
        ),
      ],
    );

ExamDocument _ltrDoc({String? statement, bool withPoint = false}) =>
    ExamDocument(
      name: 'Direction regression',
      header: ExamHeaderModel(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: statement ?? 'Answer $_marker then review.',
          body: 'Body text.',
          items: withPoint
              ? <BranchItem>[
                  BranchItem(
                    id: 'p1',
                    kind: PointKind.multipleChoice,
                    text: 'Point text',
                    options: <QuestionOption>[QuestionOption(text: 'A')],
                  ),
                ]
              : null,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExamFonts pdfFonts;

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
    pdfFonts = await ExamFonts.load();
  });

  test('arabic-indic digits carry w:rtl inside an RTL paragraph', () async {
    final document = _rtlDoc(statement: 'أجب عن $_marker ثم ٢٠ درجة.');
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    final title = probe.paragraphs
        .firstWhere((paragraph) => paragraph.text.contains(_marker));
    expect(title.props.hasBidi, isTrue);
    final digitRuns = title.runs.where((run) => _hasArabicIndicDigit(run.text)).toList();
    expect(digitRuns, isNotEmpty,
        reason: 'No run carries the arabic-indic digits: '
            '${title.runs.map((run) => run.text).toList()}');
    expect(digitRuns.every((run) => run.rtl), isTrue,
        reason: 'Digit run in RTL paragraph lacks `w:rtl`: '
            '${digitRuns.map((run) => run.text).toList()}');
  });

  test('mixed paragraph keeps per-run direction (arabic rtl, latin ltr)',
      () async {
    final document =
        _rtlDoc(statement: 'س١ اقرأ $_marker ثم ٢٠ درجة.');
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    final title = probe.paragraphs
        .firstWhere((paragraph) => paragraph.text.contains(_marker));
    expect(title.props.hasBidi, isTrue);
    expect(title.runs.length, greaterThan(1));
    final arabicRuns =
        title.runs.where((run) => _hasArabic(run.text)).toList();
    final englishRuns = title.runs
        .where((run) => run.text.contains(_marker))
        .toList();
    expect(arabicRuns, isNotEmpty);
    expect(englishRuns, isNotEmpty);
    expect(arabicRuns.every((run) => run.rtl), isTrue,
        reason: 'Arabic run in RTL paragraph lacks `w:rtl`: '
            '${arabicRuns.map((run) => run.text).toList()}');
    expect(englishRuns.every((run) => !run.rtl), isTrue,
        reason: 'Embedded English run incorrectly carries `w:rtl`: '
            '${englishRuns.map((run) => run.text).toList()}');
  });

  test('ltr document has no w:bidi and no w:rtl in any paragraph', () async {
    final document = _ltrDoc(
      statement: 'Answer $_marker then review القاعدة.',
      withPoint: true,
    );
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    expect(probe.paragraphs, isNotEmpty);
    final bidiLeak = <int>[
      for (final paragraph in probe.paragraphs)
        if (paragraph.props.hasBidi) paragraph.index,
    ];
    expect(bidiLeak, isEmpty,
        reason: 'LTR paragraphs carrying `w:bidi`: $bidiLeak');
    final rtlRunLeak = <int>[
      for (final paragraph in probe.paragraphs)
        if (paragraph.runs.any((run) => run.rtl)) paragraph.index,
    ];
    expect(rtlRunLeak, isEmpty,
        reason: 'LTR paragraphs with a `w:rtl` run: $rtlRunLeak');
  });

  test('rtl indents use w:start with w:right, never w:left', () async {
    final document = _rtlDoc(withPoint: true);
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    final indents = probe.indentDirectives;
    expect(indents, isNotEmpty,
        reason: 'No `w:ind` in the file: indentation untested.');
    for (final indent in indents) {
      expect(indent.containsKey('w:start'), isTrue,
          reason: 'Indent without `w:start`: $indent');
      expect(indent['w:left'], isNull,
          reason: 'Arabic indent used `w:left`: $indent');
      expect(indent['w:right'], indent['w:start'],
          reason: 'Physical side mismatches the directional one: $indent');
    }
  });

  test('ltr indents use w:start with w:left, never w:right', () async {
    final document = _ltrDoc(withPoint: true);
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    final indents = probe.indentDirectives;
    expect(indents, isNotEmpty,
        reason: 'No `w:ind` in the LTR file: indentation untested.');
    for (final indent in indents) {
      expect(indent['w:right'], isNull,
          reason: 'LTR indent used `w:right`: $indent');
      expect(indent['w:left'], indent['w:start'],
          reason: 'Latin indent inconsistent: $indent');
    }
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
