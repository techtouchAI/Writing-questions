import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_interaction.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import '../../pdf_engine/pdf_content_probe.dart';

const String _sourceMarker = 'CANONICALPDFGEOMETRYTOKEN';

ExamDocument _document({
  String subject = 'Mathematics',
  String statement = 'Question title with $_sourceMarker',
  String body = 'Body text used to measure the content area.',
  ExamFooterModel? footer,
}) =>
    ExamDocument(
      name: 'Canonical geometry parity',
      header: ExamHeaderModel(
        subject: subject,
        showBismillah: false,
        schoolName: 'Canonical Test School',
        grade: 'Grade 10',
        time: '45 minutes',
      ),
      footer: footer,
      settings: const PaperSettings(
        marginMm: 15,
        defaultFont: PaperFont.naskh,
        baseFontSize: 12,
        lineSpacing: 1.4,
        showQuestionMarks: false,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'canonical-q1',
          questionNumber: 1,
          statement: statement,
          body: body,
        ),
      ],
    );

List<({LayoutLine line, LayoutRun run})> _runs(LayoutPage page) =>
    <({LayoutLine line, LayoutRun run})>[
      for (final block in page.blocks)
        for (final line in block.allLines)
          for (final run in line.runs) (line: line, run: run),
    ];

void _expectNoHeaderFooterOverlap(LayoutPage page) {
  if (page.headerBounds != null) {
    expect(
      page.bodyBounds.top,
      greaterThanOrEqualTo(page.headerBounds!.bottom - 0.02),
      reason: 'Page ${page.index}: body begins inside the measured header.',
    );
  }
  if (page.footerBounds != null) {
    expect(
      page.bodyBounds.bottom,
      lessThanOrEqualTo(page.footerBounds!.top + 0.02),
      reason: 'Page ${page.index}: body overlaps the measured footer.',
    );
    for (final block in page.blocks.where(
      (block) => block.kind == LayoutBlockKind.question,
    )) {
      expect(
        block.rect.bottom,
        lessThanOrEqualTo(page.footerBounds!.top + 0.02),
        reason: 'Page ${page.index}: question ${block.semanticNodeId} overlaps '
            'the measured footer.',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExamFonts pdfFonts;

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
    pdfFonts = await ExamFonts.load();
  });

  test('screen → page → canonical run → source offset uses shared geometry', () async {
    final document = _document();
    final layout = await CanonicalLayoutService.resolve(document: document);
    expect(layout.pages, isNotEmpty);

    final page = layout.pages.first;
    final match = _runs(page).firstWhere(
      (entry) => entry.run.text.contains(_sourceMarker),
      orElse: () => throw StateError('The canonical run was not laid out.'),
    );
    final run = match.run;
    final line = match.line;
    final runRect = LayoutRect.fromLTWH(
      run.x,
      line.baseline - run.baselineOffset,
      run.width,
      run.height,
    );
    final expectedPoint = (x: runRect.left + runRect.width / 2,
      y: runRect.top + runRect.height / 2);

    // Model the actual fitted/zoomed page viewport, including a non-zero
    // screen origin. The round-trip must not depend on a parallel widget layout.
    final transform = CanonicalPageTransform(
      screenLeft: 47,
      screenTop: 83,
      screenWidth: 721,
      screenHeight: 1018,
      pageWidthPt: LayoutUnits.a4.width,
      pageHeightPt: LayoutUnits.a4.height,
    );
    final screen = transform.screenPointFromPage(expectedPoint.x, expectedPoint.y);
    final pagePoint = transform.pagePointFromScreen(screen.x, screen.y);
    expect(pagePoint.x, closeTo(expectedPoint.x, 0.01));
    expect(pagePoint.y, closeTo(expectedPoint.y, 0.01));

    final hit = CanonicalLayoutHitTester.hitTest(
      page: page,
      pageIndex: page.index,
      xPt: pagePoint.x,
      yPt: pagePoint.y,
    );
    expect(hit, isNotNull);
    expect(hit!.runId, run.id);
    expect(hit.semanticNodeId, run.semanticNodeId);
    expect(hit.lineId, line.id);
    expect(hit.sourceStartOffset, run.sourceStartOffset);
    expect(hit.sourceEndOffset, run.sourceEndOffset);
    expect(
      hit.sourceOffset,
      allOf(
        greaterThanOrEqualTo(run.sourceStartOffset),
        lessThanOrEqualTo(run.sourceEndOffset),
      ),
    );
    expect(hit.rect.left, closeTo(runRect.left, 0.01));
    expect(hit.rect.top, closeTo(runRect.top, 0.01));
    expect(hit.rect.width, closeTo(runRect.width, 0.01));
    expect(hit.rect.height, closeTo(runRect.height, 0.01));
  });

  test('real vector PDF words occupy canonical page, run, and baseline geometry',
      () async {
    final documents = <ExamDocument>[
      _document(
        subject: 'الرياضيات',
        statement: 'نص عربي مختلط English 2042 قبل $_sourceMarker وبعده.',
      ),
      _document(
        subject: 'English',
        statement: 'Arabic العربية and Latin ENGLISH 2042 around $_sourceMarker.',
      ),
    ];

    for (final document in documents) {
      final layout = await CanonicalLayoutService.resolve(document: document);
      final target = <({LayoutPage page, LayoutLine line, LayoutRun run})>[
        for (final page in layout.pages)
          for (final entry in _runs(page))
            if (entry.run.text.contains(_sourceMarker))
              (page: page, line: entry.line, run: entry.run),
      ].single;
      final bytes = await PaginatedPdfExamEngine().generate(
        document: document,
        layoutDocument: layout,
        fonts: pdfFonts,
      );

      final pdfPageCount = PdfContentProbe.pageCountOf(bytes);
      expect(pdfPageCount, layout.pageCount,
          reason: 'Vector PDF must keep LayoutDocument page ownership.');
      final pdfHits = <({int pageIndex, ProbedWord word})>[];
      for (var pageIndex = 0; pageIndex < pdfPageCount; pageIndex++) {
        final probe = PdfContentProbe.fromBytes(
          Uint8List.fromList(bytes),
          pageIndex: pageIndex,
        );
        for (final word in probe.words.where(
          (word) => word.text == _sourceMarker,
        )) {
          pdfHits.add((pageIndex: pageIndex, word: word));
        }
      }

      expect(pdfHits, hasLength(1),
          reason: 'The marker must be extracted once from the generated PDF.');
      final pdfHit = pdfHits.single;
      expect(pdfHit.pageIndex, target.page.index,
          reason: 'The PDF must paint the run on its canonical page.');
      expect(pdfHit.word.fontSize, closeTo(target.run.style.fontSizePt, 0.02));
      expect(pdfHit.word.x, closeTo(target.run.x, 2.5),
          reason: 'The actual PDF text operator must use the canonical run x.');
      expect(
        target.page.pageSize.height - pdfHit.word.y,
        closeTo(target.line.baseline, 4.0),
        reason: 'The actual PDF text baseline must map to the canonical baseline.',
      );
    }
  });

  test('canonical header and footer reservations change body geometry, not overlap', () async {
    const shortFooter = ExamFooterModel(
      closingPhrase: '',
      primary: SignatureModel(name: 'A. Teacher'),
    );
    final longFooter = ExamFooterModel(
      closingPhrase: List<String>.filled(
        24,
        'Footer measurement must reserve real page space',
      ).join(' '),
      primary: SignatureModel(
        name: List<String>.filled(8, 'Teacher Signature').join(' '),
      ),
    );

    final shortLayout = await CanonicalLayoutService.resolve(
      document: _document(footer: shortFooter),
    );
    final longLayout = await CanonicalLayoutService.resolve(
      document: _document(footer: longFooter),
    );
    final shortPage = shortLayout.pages.last;
    final longPage = longLayout.pages.last;

    expect(shortPage.headerBounds, isNotNull);
    expect(shortPage.footerBounds, isNotNull);
    expect(longPage.headerBounds, isNotNull);
    expect(longPage.footerBounds, isNotNull);
    expect(longPage.footerBounds!.height, greaterThan(shortPage.footerBounds!.height));
    expect(longPage.bodyBounds.height, lessThan(shortPage.bodyBounds.height));
    _expectNoHeaderFooterOverlap(shortPage);
    _expectNoHeaderFooterOverlap(longPage);
  });

  test('header/body/footer bounds remain disjoint on every generated page', () async {
    final longBody = List<String>.filled(
      680,
      'Canonical pagination must keep this paragraph inside the page content area.',
    ).join(' ');
    final layout = await CanonicalLayoutService.resolve(
      document: _document(body: longBody),
    );

    expect(layout.pageCount, greaterThan(1));
    expect(layout.pages.first.headerBounds, isNotNull);
    expect(layout.pages.last.footerBounds, isNotNull);
    for (final page in layout.pages) {
      expect(page.contentBounds.width, closeTo(LayoutUnits.a4.width -
          2 * LayoutUnits.mmToPt(15), 0.02));
      _expectNoHeaderFooterOverlap(page);
    }
  });

  test('page transform clamps points to page edges and is invertible in bounds', () {
    const transform = CanonicalPageTransform(
      screenLeft: 10,
      screenTop: 30,
      screenWidth: 500,
      screenHeight: 700,
      pageWidthPt: 420,
      pageHeightPt: 595,
    );
    final topLeft = transform.pagePointFromScreen(10, 30);
    final bottomRight = transform.pagePointFromScreen(510, 730);
    expect(topLeft.x, 0);
    expect(topLeft.y, 0);
    expect(bottomRight.x, 420);
    expect(bottomRight.y, 595);

    final outside = transform.pagePointFromScreen(-90, 930);
    expect(outside.x, 0);
    expect(outside.y, 595);
    const pageCenter = (x: 210.0, y: 297.5);
    final screenCenter = transform.screenPointFromPage(pageCenter.x, pageCenter.y);
    final roundTrip = transform.pagePointFromScreen(screenCenter.x, screenCenter.y);
    expect(roundTrip.x, closeTo(pageCenter.x, 1e-9));
    expect(roundTrip.y, closeTo(pageCenter.y, 1e-9));
  });
}
