import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/canonical/layout_document.dart';
import '../layout/document_direction.dart';
import '../models/equation_model.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import '../models/paper_text_style.dart';
import 'exam_fonts.dart';
import 'floating_elements_pdf.dart';
import 'pdf_math_rasters.dart';

/// PDF-side painter for a completed LayoutDocument. Canonical run gaps and
/// line anchors remain authoritative; PDF font advances only map those gaps
/// onto the PDF canvas. There is no Row, Wrap, line-break, justification, or
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
          context,
          <LayoutLine>[
            for (final block in page.blocks) ...block.allLines,
          ],
          fonts: fonts,
          mathRasters: mathRasters,
        ),
      ),
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

  /// Measures each already-resolved text run with the PDF font, then maps its
  /// origin so the gaps between canonical run boxes remain unchanged. Plain
  /// U+0020 and fixed-advance runs are geometry, not PDF text widgets: retain
  /// their canonical advance directly. No line-breaking, bidi reordering, or
  /// justification is performed here.
  pw.Widget _paintCanonicalLines(
    pw.Context context,
    Iterable<LayoutLine> lines, {
    required ExamFonts fonts,
    required PdfMathRasters mathRasters,
  }) {
    final children = <pw.Widget>[];
    for (final line in lines) {
      final runs = line.runs
          .where((run) => run.advance > 0)
          .toList(growable: false);
      if (runs.isEmpty) continue;

      final advances = <double>[];
      final contents = <pw.Widget?>[];
      for (final run in runs) {
        if (_isCanonicalSpacer(run)) {
          advances.add(run.width);
          contents.add(null);
          continue;
        }

        final raster = run.isMath
            ? mathRasters.lookup(run.text, run.style.fontSizePt)
            : null;
        if (raster != null) {
          advances.add(run.width);
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

        final measuredText = _textRunWidget(
          run,
          fonts,
          textAlign: pw.TextAlign.left,
        );
        final measuredAdvance = pw.Widget.measure(
          measuredText,
          context: context,
        ).x;
        advances.add(measuredAdvance.isFinite && measuredAdvance >= 0
            ? measuredAdvance
            : run.width);
        contents.add(
          _textRunWidget(
            run,
            fonts,
            textAlign: pw.TextAlign.left,
          ),
        );
      }

      final origins = _mappedRunOrigins(line, runs, advances);
      final originById = <String, double>{
        for (var index = 0; index < runs.length; index++)
          runs[index].id: origins[index],
      };
      final contentById = <String, pw.Widget?>{
        for (var index = 0; index < runs.length; index++)
          runs[index].id: contents[index],
      };
      // Keep the canonical logical emission order; positions come from the
      // canonical gaps/anchor mapped through the measured PDF advances.
      for (final run in _logicalRuns(line)) {
        final content = contentById[run.id];
        if (content == null) continue;
        children.add(
          pw.Positioned(
            left: originById[run.id],
            top: line.baseline - run.baselineOffset,
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

  List<double> _mappedRunOrigins(
    LayoutLine line,
    List<LayoutRun> runs,
    List<double> advances,
  ) {
    assert(runs.length == advances.length);
    final origins = List<double>.filled(runs.length, 0);
    if (runs.isEmpty) return origins;

    final gaps = <double>[
      for (var index = 0; index + 1 < runs.length; index++)
        runs[index + 1].x - (runs[index].x + runs[index].width),
    ];
    final rightAligned = _rightAnchorsLine(line);
    if (rightAligned == true) {
      final last = runs.length - 1;
      origins[last] = runs[last].x + runs[last].width - advances[last];
      for (var index = last - 1; index >= 0; index--) {
        origins[index] =
            origins[index + 1] - gaps[index] - advances[index];
      }
      return origins;
    }

    var extent = advances.first;
    for (var index = 0; index < gaps.length; index++) {
      extent += gaps[index] + advances[index + 1];
    }
    final start = rightAligned == null
        ? (runs.first.x + runs.last.x + runs.last.width - extent) / 2
        : runs.first.x;
    origins[0] = start;
    for (var index = 0; index < gaps.length; index++) {
      origins[index + 1] = origins[index] + advances[index] + gaps[index];
    }
    return origins;
  }

  bool? _rightAnchorsLine(LayoutLine line) {
    switch (line.alignment) {
      case PaperAlign.left:
        return false;
      case PaperAlign.right:
        return true;
      case PaperAlign.center:
        return null;
      case PaperAlign.end:
        return line.direction != DocumentDirection.rtl;
      case PaperAlign.start:
      case PaperAlign.justify:
      case null:
        return line.direction == DocumentDirection.rtl;
    }
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
    if (run.advance <= 0 || (run.text.isEmpty && !run.isMath)) return null;
    final left = run.x - originX;
    final top = line.baseline - run.baselineOffset - originY;
    final textStyle = _pdfTextStyle(run, fonts);
    final raster = run.isMath
        ? mathRasters.lookup(run.text, run.style.fontSizePt)
        : null;
    // Floating labels retain their existing fixed-run placement; ordinary page
    // lines use _paintCanonicalLines above to map PDF advances onto canonical
    // gaps. Height remains intrinsic for text to avoid clipping font-specific
    // ascent/descent; raster math already has canonical dimensions.
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
