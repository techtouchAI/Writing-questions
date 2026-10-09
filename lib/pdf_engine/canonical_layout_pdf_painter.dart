import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/canonical/c6_experiment_snap.dart';
import '../layout/canonical/layout_document.dart';
import '../layout/document_direction.dart';
import '../models/equation_model.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import 'canonical_text.dart';
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

  /// Paints each already-resolved text run at its canonical word origins.
  /// Plain U+0020 and fixed-advance runs are geometry, not PDF text widgets,
  /// and math runs keep their canonical box for the raster image. Origins
  /// are never remapped by PDF advances: that would re-justify the line
  /// inside the renderer. No line-breaking, bidi reordering, or
  /// justification is performed here. Text widgets are shifted by the
  /// PDF-side baseline mapping ([PdfTextMetrics]) so the emitted operator
  /// lands on the canonical baseline.
  pw.Widget _paintCanonicalLines(
    Iterable<LayoutLine> lines, {
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    required pw.Context context,
  }) {
    final children = <pw.Widget>[];
    for (final line in lines) {
      // Keep the canonical logical emission order; positions are the
      // canonical word origins, painted as-is.
      for (final run in _logicalRuns(line)) {
        children.addAll(
          _positionedRunWidgets(
            line,
            run,
            fonts: fonts,
            mathRasters: mathRasters,
            context: context,
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

  bool _isSpacerRun(LayoutRun run) {
    if (run.text.isEmpty) return true;
    if (run.isMath) return false;
    return run.text.runes.every((rune) => rune == 0x20);
  }

  /// One spaceless text emission: a canonical word, a math fallback, or a
  /// wordless run's whole text. [CanonicalText] replicates the replaced
  /// pw.Text ink geometry and closes the executed advance onto
  /// [canonicalAdvancePt]; the caller's [pw.Positioned] carries the
  /// canonical origin with the C1 baseline mapping in its top, exactly as
  /// before. Letter spacing has no producer anywhere (no data key, no code
  /// setter) and must stay unset: [CanonicalText] emits none, matching the
  /// always-zero spacing used before.
  pw.Widget _wordTextWidget(
    LayoutRun run,
    String text,
    ExamFonts fonts, {
    required double canonicalAdvancePt,
  }) {
    assert(
      run.style.letterSpacingPt == null || run.style.letterSpacingPt == 0,
      'CanonicalText emits no letter spacing; letterSpacingPt must stay '
      'unset (it has no producer).',
    );
    return CanonicalText(
      text: text,
      font: fonts.fontFor(run.style.font, bold: run.style.bold),
      fontSizePt: run.style.fontSizePt,
      color: run.style.colorArgb == null
          ? PdfColors.black
          : PdfColor.fromInt(run.style.colorArgb!),
      canonicalAdvancePt: canonicalAdvancePt,
      rtl: run.direction == DocumentDirection.rtl,
      underline: run.style.underline,
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

  /// Positioned PDF widgets for one canonical run, shared by page lines and
  /// floating labels (the parents clip, so no per-run box is needed). Text
  /// is emitted per canonical word at its word origin; every run carries at
  /// most one word today (fragments are ICU words), so page output matches
  /// the former whole-run emission while the emitter consumes the canonical
  /// word contract. Math rasters keep the canonical run box; math without a
  /// raster falls back to its readable text at the run origin, as before.
  /// Runs without words and without visible text emit nothing; a text run
  /// that unexpectedly carries no words still emits whole-run text.
  List<pw.Widget> _positionedRunWidgets(
    LayoutLine line,
    LayoutRun run, {
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
    required pw.Context context,
    double originX = 0,
    double originY = 0,
  }) {
    if (run.advance <= 0 || _isSpacerRun(run)) return const <pw.Widget>[];
    final raster =
        run.isMath ? mathRasters.lookup(run.text, run.style.fontSizePt) : null;
    if (raster != null) {
      return <pw.Widget>[
        pw.Positioned(
          left: run.x - originX,
          top: c6SnapBaselinePt(line.baseline) - run.baselineOffset - originY,
          child: pw.Image(
            pw.MemoryImage(raster.pngBytes),
            width: run.width,
            height: run.height,
            fit: pw.BoxFit.fill,
          ),
        ),
      ];
    }
    // Height remains intrinsic for text to avoid clipping font-specific
    // ascent/descent. The C1 baseline mapping sets the widget origin,
    // exactly as before; CanonicalText replicates the replaced ink offsets
    // inside it.
    final top =
        c6SnapBaselinePt(line.baseline) - _pdfTextTopOffset(run, fonts, context) - originY;
    pw.Widget wordWidget(String text, double left, double advance) =>
        pw.Positioned(
          left: left,
          top: top,
          child: _wordTextWidget(
            run,
            text,
            fonts,
            canonicalAdvancePt: advance,
          ),
        );
    if (run.isMath) {
      return <pw.Widget>[
        wordWidget(
          EquationModel.readableText(run.text),
          run.x - originX,
          run.advance,
        ),
      ];
    }
    if (run.words.isEmpty) {
      return <pw.Widget>[wordWidget(run.text, run.x - originX, run.advance)];
    }
    // The executed word advance is the word's own shaped text advance:
    // the pitch (word.advance) reaches into the following space, which
    // belongs to gaps, not to the TJ correction.
    return <pw.Widget>[
      for (final word in run.words)
        wordWidget(word.text, word.x - originX, word.textAdvance),
    ];
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
            localChildren.addAll(
              _positionedRunWidgets(
                line,
                run,
                fonts: fonts,
                mathRasters: mathRasters,
                context: context,
                originX: rect.left,
                originY: rect.top,
              ),
            );
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
            localChildren.addAll(
              _positionedRunWidgets(
                line,
                run,
                fonts: fonts,
                mathRasters: mathRasters,
                context: context,
                originX: rect.left,
                originY: rect.top,
              ),
            );
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
