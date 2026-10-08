import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/canonical/layout_document.dart';
import '../layout/document_direction.dart';
import '../models/equation_model.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import 'exam_fonts.dart';
import 'floating_elements_pdf.dart';
import 'pdf_math_rasters.dart';
import 'pdf_text_metrics.dart';

/// PDF-side painter for a completed LayoutDocument. Canonical run origins
/// are authoritative for text operators; PDF font advances are never used
/// to displace them. There is no Row, Wrap, line-break, justification, or
/// page-flow pass in this class.
class CanonicalLayoutPdfPainter {
  const CanonicalLayoutPdfPainter();

  pw.Widget paintPage({
    required pw.Context context,
    required LayoutPage page,
    required ExamDocument sourceDocument,
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    Uint8List? frameImage,
  }) {
    final pageWidth = page.pageSize.width;
    final pageHeight = page.pageSize.height;
    pw.MemoryImage? usableFrameImage;
    if (sourceDocument.settings.pageBorder && frameImage != null) {
      try {
        usableFrameImage = pw.MemoryImage(frameImage);
      } catch (_) {
        // Invalid frame data must not abort export; the canonical vector border
        // remains available in page.decorations as the fallback.
      }
    }
    final children = <pw.Widget>[
      pw.SizedBox(width: pageWidth, height: pageHeight),
      if (usableFrameImage != null)
        pw.Positioned.fill(
          child: pw.Image(usableFrameImage, fit: pw.BoxFit.fill),
        ),
      if (usableFrameImage == null)
        for (final decoration in page.decorations) _paintDecoration(decoration),
      for (final block in _allBlocks(page.blocks))
        for (final decoration in block.decorations) _paintDecoration(decoration),
      pw.Positioned.fill(
        child: _paintCanonicalLines(
          <LayoutLine>[
            for (final block in page.blocks) ...block.allLines,
          ],
          fonts: fonts,
          mathRasters: mathRasters,
          context: context,
        ),
      ),
      for (final placement in page.floatingElements)
        if (placement.deferredReason == null)
          _paintFloat(
            placement,
            sourceDocument: sourceDocument,
            fonts: fonts,
            mathRasters: mathRasters,
            context: context,
          ),
    ];
    return pw.SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: pw.Stack(
        fit: pw.StackFit.expand,
        overflow: pw.Overflow.visible,
        children: children,
      ),
    );
  }

  /// Paints each already-resolved text run at its canonical origin. Plain
  /// U+0020 and fixed-advance runs are geometry, not PDF text widgets, and
  /// math runs keep their canonical box for the raster image. Origins are
  /// never remapped by PDF advances: that would re-justify the line inside
  /// the renderer. No line-breaking, bidi reordering, or justification is
  /// performed here. Text widgets are shifted by the PDF-side baseline
  /// mapping ([PdfTextMetrics]) so the emitted operator lands on the
  /// canonical baseline.
  pw.Widget _paintCanonicalLines(
    Iterable<LayoutLine> lines, {
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    required pw.Context context,
  }) {
    final children = <pw.Widget>[];
    for (final line in lines) {
      final runs = line.runs
          .where((run) => run.advance > 0)
          .toList(growable: false);
      if (runs.isEmpty) continue;

      final contents = <pw.Widget?>[];
      final rasterById = <String, bool>{};
      for (final run in runs) {
        if (_isCanonicalSpacer(run)) {
          contents.add(null);
          continue;
        }

        final raster = run.isMath
            ? mathRasters.lookup(run.text, run.style.fontSizePt)
            : null;
        if (raster != null) {
          rasterById[run.id] = true;
          contents.add(
            pw.Image(
              pw.MemoryImage(raster.pngBytes),
              width: run.width,
              height: run.height,
              fit: pw.BoxFit.fill,
            ),
          );
          continue;
        }

        contents.add(
          _textRunWidget(
            run,
            fonts,
            textAlign: pw.TextAlign.left,
          ),
        );
      }

      // Canonical run origins are authoritative for PDF text operators: the
      // parity contract requires the actual operator to use the canonical
      // run x within tolerance, and remapping origins by PDF advances
      // re-justifies the line inside the renderer — displacing starts
      // beyond tolerance whenever the shapers diverge (notably Arabic).
      final contentById = <String, pw.Widget?>{
        for (var index = 0; index < runs.length; index++)
          runs[index].id: contents[index],
      };
      // Keep the canonical logical emission order; positions are the
      // canonical run origins, painted as-is.
      for (final run in _logicalRuns(line)) {
        final content = contentById[run.id];
        if (content == null) continue;
        final top = rasterById[run.id] == true
            ? line.baseline - run.baselineOffset
            : line.baseline - _pdfTextTopOffset(run, fonts, context);
        children.add(
          pw.Positioned(
            left: run.x,
            top: top,
            child: content,
          ),
        );
      }
    }
    return pw.Stack(
      fit: pw.StackFit.expand,
      overflow: pw.Overflow.visible,
      children: children,
    );
  }

  bool _isCanonicalSpacer(LayoutRun run) {
    if (run.text.isEmpty) return true;
    if (run.isMath) return false;
    return run.text.runes.every((rune) => rune == 0x20);
  }

  pw.Text _textRunWidget(
    LayoutRun run,
    ExamFonts fonts, {
    required pw.TextAlign textAlign,
  }) {
    final text = run.isMath ? EquationModel.readableText(run.text) : run.text;
    return pw.Text(
      text,
      style: _pdfTextStyle(run, fonts),
      textDirection: _pdfDirection(run.direction),
      textAlign: textAlign,
      softWrap: false,
      maxLines: 1,
      tightBounds: false,
      overflow: pw.TextOverflow.clip,
    );
  }

  Iterable<LayoutRun> _logicalRuns(LayoutLine line) sync* {
    final byId = <String, LayoutRun>{for (final run in line.runs) run.id: run};
    for (final id in line.logicalRunIds) {
      final run = byId[id];
      if (run != null) yield run;
    }
  }

  Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* _allBlocks(block.children);
    }
  }

  pw.Widget _paintDecoration(LayoutDecoration decoration) {
    final rect = decoration.rect;
    if (rect.isEmpty) return pw.SizedBox.shrink();
    if (decoration.kind == LayoutDecorationKind.divider) {
      return pw.Positioned(
        left: rect.left,
        top: rect.top,
        child: pw.Container(
          width: rect.width,
          height: rect.height,
          color: PdfColor.fromInt(decoration.colorArgb),
        ),
      );
    }
    return pw.Positioned(
      left: rect.left,
      top: rect.top,
      child: pw.Container(
        width: rect.width,
        height: rect.height,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: PdfColor.fromInt(decoration.colorArgb),
            width: decoration.strokeWidthPt,
          ),
          borderRadius: decoration.radiusPt > 0
              ? pw.BorderRadius.circular(decoration.radiusPt)
              : null,
        ),
      ),
    );
  }

  pw.Widget? _paintRun(
    LayoutLine line,
    LayoutRun run, {
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    required pw.Context context,
    double originX = 0,
    double originY = 0,
  }) {
    if (run.advance <= 0 || (run.text.isEmpty && !run.isMath)) return null;
    final left = run.x - originX;
    final textStyle = _pdfTextStyle(run, fonts);
    final raster = run.isMath
        ? mathRasters.lookup(run.text, run.style.fontSizePt)
        : null;
    // Floating labels retain their existing fixed-run placement; ordinary page
    // lines use _paintCanonicalLines above to paint canonical origins as-is.
    // Height remains intrinsic for text to avoid clipping font-specific
    // ascent/descent; raster math already has canonical dimensions.
    final top = raster != null
        ? line.baseline - run.baselineOffset - originY
        : line.baseline - _pdfTextTopOffset(run, fonts, context) - originY;
    final pw.Widget content;
    if (raster != null) {
      content = pw.Image(
        pw.MemoryImage(raster.pngBytes),
        width: run.width,
        height: run.height,
        fit: pw.BoxFit.fill,
      );
    } else if (run.isMath) {
      content = pw.Text(
        EquationModel.readableText(run.text),
        style: textStyle,
        textDirection: _pdfDirection(run.direction),
        textAlign: pw.TextAlign.start,
        softWrap: false,
        maxLines: 1,
        tightBounds: false, // Retain font ascent/descent for stable baselines.
        overflow: pw.TextOverflow.clip,
      );
    } else {
      content = pw.Text(
        run.text,
        style: textStyle,
        textDirection: _pdfDirection(run.direction),
        textAlign: pw.TextAlign.start,
        softWrap: false,
        maxLines: 1,
        tightBounds: false, // Retain font ascent/descent for stable baselines.
        overflow: pw.TextOverflow.clip,
      );
    }
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: run.width,
        height: raster == null ? null : run.height,
        child: content,
      ),
    );
  }

  /// PDF-side distance from a single-line text widget top to its emitted
  /// baseline, resolved from the embedded font itself (see [PdfTextMetrics]).
  double _pdfTextTopOffset(
    LayoutRun run,
    ExamFonts fonts,
    pw.Context context,
  ) {
    final font =
        fonts.fontFor(run.style.font, bold: run.style.bold).getFont(context);
    return PdfTextMetrics.baselineOffsetFromTop(
      font: font,
      fontSizePt: run.style.fontSizePt,
      text: run.text,
      letterSpacingPt: run.style.letterSpacingPt ?? 0,
    );
  }

  pw.TextStyle _pdfTextStyle(LayoutRun run, ExamFonts fonts) => pw.TextStyle(
        font: fonts.fontFor(run.style.font, bold: run.style.bold),
        fontSize: run.style.fontSizePt,
        fontWeight: run.style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: run.style.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        color: run.style.colorArgb == null
            ? PdfColors.black
            : PdfColor.fromInt(run.style.colorArgb!),
        letterSpacing: run.style.letterSpacingPt ?? 0,
        wordSpacing: _usesPdfNbspSpacing(run) ? 1 : 0,
        lineSpacing: 0,
        height: 1,
        decoration: run.style.underline
            ? pw.TextDecoration.underline
            : pw.TextDecoration.none,
      );

  // NBSP/NNBSP ranges remain one canonical run and every PDF run is
  // softWrap:false. package:pdf substitutes its U+0020 advance while shaping
  // these nonbreaking characters, so enable exactly that within-run advance;
  // it does not create a new line-break or justification opportunity.
  bool _usesPdfNbspSpacing(LayoutRun run) => run.text.runes.any(
        (rune) => rune == 0x00a0 || rune == 0x202f,
      );

  pw.TextDirection _pdfDirection(DocumentDirection direction) =>
      direction == DocumentDirection.ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl;

  pw.Widget _paintFloat(
    LayoutFloatPlacement placement, {
    required ExamDocument sourceDocument,
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    required pw.Context context,
  }) {
    final element = sourceDocument.floatingElementById(placement.reference.id);
    if (element == null) return pw.SizedBox.shrink();
    final rect = placement.rect;
    final width = rect.width;
    final height = rect.height;
    final localChildren = <pw.Widget>[
      pw.SizedBox(width: width, height: height),
    ];

    switch (element.type) {
      case FloatingElementType.image:
        final bytes = element.bytes;
        if (bytes != null) {
          localChildren.add(
            pw.Positioned.fill(
              child: pw.Image(
                pw.MemoryImage(bytes),
                fit: pw.BoxFit.contain,
              ),
            ),
          );
        }
        break;
      case FloatingElementType.shape:
        if (element.isTextBox) {
          if (placement.framed) {
            localChildren.add(
              pw.Positioned.fill(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: PdfColors.black,
                      width: placement.strokeWidthPt,
                    ),
                  ),
                ),
              ),
            );
          }
        for (final line in placement.labelLines) {
          for (final run in _logicalRuns(line)) {
              final positioned = _paintRun(
                line,
                run,
                fonts: fonts,
                mathRasters: mathRasters,
                context: context,
                originX: rect.left,
                originY: rect.top,
              );
              if (positioned != null) localChildren.add(positioned);
            }
          }
        } else {
          final shape = element.shape ?? FloatingShapeType.square;
          final svg = element.svgSource ?? FloatingElementsPdf.shapeToSvg(
            shape,
            width,
            height,
            strokeWidth: placement.strokeWidthPt,
          );
          localChildren.add(
            pw.Positioned.fill(
              child: pw.SvgImage(svg: svg, fit: pw.BoxFit.fill),
            ),
          );
        }
        break;
      case FloatingElementType.formula:
        if (placement.framed) {
          localChildren.add(
            pw.Positioned.fill(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.black,
                    width: placement.strokeWidthPt,
                  ),
                ),
              ),
            ),
          );
        }
        for (final line in placement.labelLines) {
          for (final run in _logicalRuns(line)) {
            final positioned = _paintRun(
              line,
              run,
              fonts: fonts,
              mathRasters: mathRasters,
              context: context,
              originX: rect.left,
              originY: rect.top,
            );
            if (positioned != null) localChildren.add(positioned);
          }
        }
        break;
    }

    pw.Widget child = pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(
        fit: pw.StackFit.expand,
        overflow: pw.Overflow.clip,
        children: localChildren,
      ),
    );
    if (placement.rotationDegrees != 0) {
      child = pw.Transform.rotateBox(
        angle: placement.rotationDegrees * math.pi / 180,
        child: child,
      );
    }
    return pw.Positioned(left: rect.left, top: rect.top, child: child);
  }
}
