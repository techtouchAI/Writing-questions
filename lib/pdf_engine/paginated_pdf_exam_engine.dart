import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/canonical/canonical_layout_service.dart';
import '../layout/canonical/layout_document.dart';
import '../layout/canonical/layout_units.dart';
import '../layout/blueprint/exam_blueprint.dart';
import '../layout/document_direction.dart';
import '../layout/document_ir.dart';
import '../models/exam_document.dart';
import 'canonical_layout_pdf_painter.dart';
import 'exam_fonts.dart';
import 'pdf_math_rasters.dart';

/// Multi-page PDF facade. Pagination, line breaks, bidi placement, justification,
/// and all flow geometry come from the same canonical LayoutDocument used by
/// Preview. This layer only paints the resolved point-space boxes.
class PaginatedPdfExamEngine {
  PaginatedPdfExamEngine();

  static const double pageMarginMillimeters = 15;

  static double get contentWidth =>
      LayoutUnits.a4.width - 2 * LayoutUnits.mmToPt(pageMarginMillimeters);

  static double get pageContentHeight =>
      LayoutUnits.a4.height - 2 * LayoutUnits.mmToPt(pageMarginMillimeters);

  /// Kept for source compatibility with P1 callers; canonical layout owns the
  /// actual branch geometry now.
  static double get branchIndent => LayoutUnits.pxToPt(26);

  static DocumentIR _documentIr(ExamDocument document) =>
      DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );

  static bool _needsQuranicFont(DocumentIR ir) =>
      ir.header.showBismillah || ir.hasQuranContent;

  static bool needsQuranicFont(ExamDocument document) =>
      _needsQuranicFont(_documentIr(document));

  /// Produces a PDF from canonical point geometry. `pageAssignments` remains
  /// accepted for compatibility with P1 callers; assignments are no longer
  /// recomputed or painted in a second renderer-specific flow path. Pass a
  /// [layoutDocument] to share the exact Preview layout object; otherwise this
  /// method resolves the same pipeline from the source ExamDocument.
  Future<Uint8List> generate({
    required ExamDocument document,
    List<List<String>>? pageAssignments,
    LayoutDocument? layoutDocument,
    ExamFonts? fonts,
    Uint8List? frameImage,
  }) async {
    final documentIr = _documentIr(document);
    final loadedFonts = fonts ??
        await ExamFonts.load(loadQuranic: _needsQuranicFont(documentIr));
    final layout = layoutDocument ??
        await CanonicalLayoutService.resolve(
          document: document,
          quranFontAvailable: loadedFonts.hasQuranic,
        );
    final mathRasters = await _rasterStoreFor(layout);
    final pdf = _newDocument(document);
    const painter = CanonicalLayoutPdfPainter();
    final direction = layout.direction == DocumentDirection.ltr
        ? pw.TextDirection.ltr
        : pw.TextDirection.rtl;
    final theme = pw.ThemeData.withFont(
      base: loadedFonts.fontFor(document.settings.defaultFont),
      bold: loadedFonts.fontFor(document.settings.defaultFont, bold: true),
    );

    for (final page in layout.pages) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(page.pageSize.width, page.pageSize.height),
          margin: pw.EdgeInsets.zero,
          textDirection: direction,
          theme: theme,
          build: (_) => painter.paintPage(
            page: page,
            sourceDocument: document,
            fonts: loadedFonts,
            mathRasters: mathRasters,
            frameImage: frameImage,
          ),
        ),
      );
    }
    return pdf.save();
  }

  /// Resolves the canonical geometry using the same optional PDF font set as
  /// [generate]. DOCX may consume its P1-compatible page projection without
  /// receiving absolute coordinates.
  Future<LayoutDocument> resolveLayoutDocument({
    required ExamDocument document,
    ExamFonts? fonts,
  }) async {
    final documentIr = _documentIr(document);
    final loadedFonts = fonts ??
        await ExamFonts.load(loadQuranic: _needsQuranicFont(documentIr));
    return CanonicalLayoutService.resolve(
      document: document,
      quranFontAvailable: loadedFonts.hasQuranic,
    );
  }

  /// Returns the canonical question assignments used by Preview and PDF.
  /// DOCX continues to consume this P1-compatible projection without receiving
  /// absolute geometry.
  Future<List<List<String>>> resolveQuestionPages({
    required ExamDocument document,
    ExamFonts? fonts,
  }) async =>
      (await resolveLayoutDocument(document: document, fonts: fonts))
          .questionPageAssignments;

  Future<PdfMathRasters> _rasterStoreFor(LayoutDocument layout) async {
    final collected = PdfMathRasters.collecting();
    for (final line in layout.allLines) {
      for (final run in line.runs) {
        if (run.isMath) collected.lookup(run.text, run.style.fontSizePt);
      }
    }
    if (collected.isEmpty) return PdfMathRasters.empty();
    return collected.resolve();
  }

  static pw.Document _newDocument(ExamDocument document) => pw.Document(
        title: document.name,
        creator: 'صانع ومحرر الأسئلة',
        producer: 'صانع ومحرر الأسئلة — محرك PDF',
        author: document.header.schoolName.isEmpty
            ? null
            : document.header.schoolName,
        subject: document.header.subject,
        keywords: 'ورقة أسئلة, امتحان, ${document.header.subject}',
      );
}
