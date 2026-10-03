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

/// PDF-side painter for a completed LayoutDocument. Each string/math/image is
/// placed at its canonical point-space box; there is no Row, Wrap, line-break,
/// justification, or page-flow pass in this class.
class CanonicalLayoutPdfPainter {
  const CanonicalLayoutPdfPainter();

  pw.Widget paintPage({
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
      for (final block in page.blocks)
        for (final line in block.allLines)
          for (final run in _logicalRuns(line))
            if (_paintRun(
                  line,
                  run,
                  fonts: fonts,
                  mathRasters: mathRasters,
                ) case final pw.Widget widget)
              widget,
      for (final placement in page.floatingElements)
        if (placement.deferredReason == null)
          _paintFloat(
            placement,
            sourceDocument: sourceDocument,
            fonts: fonts,
            mathRasters: mathRasters,
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
    double originX = 0,
    double originY = 0,
  }) {
    if (line.id.contains('header') &&
        (run.text.contains('المتوسط') ||
            run.text.contains('السنة') ||
            run.text.contains('النهوض') ||
            run.text == 'س')) {
      // ignore: avoid_print
      print('[p0-gate] canonical header direction=${run.direction} '
          'run=${run.text} id=${run.semanticNodeId}');
    }
    if (line.id.contains('/category/')) {
      // ignore: avoid_print
      print('[canonical-category] align=${line.alignment} '
          'lineDirection=${line.direction} runDirection=${run.direction} '
          'x=${run.x.toStringAsFixed(2)} width=${run.width.toStringAsFixed(2)} '
          'text=${run.text}');
    }
    if (run.advance <= 0 || (run.text.isEmpty && !run.isMath)) return null;
    final left = run.x - originX;
    final top = line.baseline - run.baselineOffset - originY;
    final textStyle = _pdfTextStyle(run, fonts);
    final height = run.isMath ? run.height : line.rect.height;
    final pw.Widget content;
    if (run.isMath) {
      final raster = mathRasters.lookup(run.text, run.style.fontSizePt);
      if (raster != null) {
        content = pw.Image(
          pw.MemoryImage(raster.pngBytes),
          width: run.width,
          height: run.height,
          fit: pw.BoxFit.fill,
        );
      } else {
        content = pw.Text(
          EquationModel.readableText(run.text),
          style: textStyle,
          textDirection: _pdfDirection(run.direction),
          textAlign: pw.TextAlign.start,
          softWrap: false,
          maxLines: 1,
          tightBounds: true,
          overflow: pw.TextOverflow.clip,
        );
      }
    } else {
      content = pw.Text(
        run.text,
        style: textStyle,
        textDirection: _pdfDirection(run.direction),
        textAlign: pw.TextAlign.start,
        softWrap: false,
        maxLines: 1,
        tightBounds: true,
        overflow: pw.TextOverflow.clip,
      );
    }
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: run.width,
        height: height,
        child: pw.Align(
          alignment: pw.Alignment.topLeft,
          child: content,
        ),
      ),
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
        wordSpacing: 0,
        lineSpacing: 0,
        height: 1,
        decoration: run.style.underline
            ? pw.TextDecoration.underline
            : pw.TextDecoration.none,
      );

  pw.TextDirection _pdfDirection(DocumentDirection direction) =>
      direction == DocumentDirection.ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl;

  pw.Widget _paintFloat(
    LayoutFloatPlacement placement, {
    required ExamDocument sourceDocument,
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
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
