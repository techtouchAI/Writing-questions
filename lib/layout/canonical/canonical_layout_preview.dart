import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/equation_model.dart';
import '../../models/exam_document.dart';
import '../../models/floating_element.dart';
import '../../services/math_snapshot_renderer.dart';
import '../document_direction.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// Decoded renderer assets for the Preview painter. These images are kept
/// outside LayoutDocument, which stays renderer-independent and point-only.
final class CanonicalLayoutPreviewAssets {
  CanonicalLayoutPreviewAssets({
    this.pageFrame,
    Map<String, ui.Image> floatingImages = const <String, ui.Image>{},
    Map<String, ui.Image> mathImages = const <String, ui.Image>{},
  })  : floatingImages = Map<String, ui.Image>.unmodifiable(floatingImages),
        mathImages = Map<String, ui.Image>.unmodifiable(mathImages);

  final ui.Image? pageFrame;
  final Map<String, ui.Image> floatingImages;
  final Map<String, ui.Image> mathImages;
  bool _disposed = false;

  static Future<CanonicalLayoutPreviewAssets> load({
    required LayoutDocument layout,
    required ExamDocument document,
  }) async {
    final floating = <String, ui.Image>{};
    final math = <String, ui.Image>{};
    ui.Image? frame;
    try {
      final framePath = layout.pageFrameImagePath;
      if (framePath != null) {
        final bytes = await File(framePath).readAsBytes();
        frame = await _decode(bytes);
      }
    } catch (_) {
      frame = null;
    }

    final decodedFloats = <String>{};
    for (final placement in layout.pages.expand((page) => page.floatingElements)) {
      if (placement.deferredReason != null ||
          !decodedFloats.add(placement.reference.id)) {
        continue;
      }
      final element = document.floatingElementById(placement.reference.id);
      final bytes = element?.bytes;
      if (element?.type != FloatingElementType.image || bytes == null) continue;
      try {
        floating[element!.id] = await _decode(bytes);
      } catch (_) {
        // A bad source image is omitted, just as the PDF painter omits it.
      }
    }

    if (MathSnapshotRenderer.isAvailable) {
      final mathRuns = <String, LayoutRun>{};
      for (final line in layout.allLines) {
        for (final run in line.runs) {
          if (run.isMath && run.text.trim().isNotEmpty) {
            mathRuns.putIfAbsent(run.id, () => run);
          }
        }
      }
      for (final run in mathRuns.values) {
        try {
          final snapshot = await MathSnapshotRenderer.render(
            run.text,
            fontSizePt: run.style.fontSizePt,
          );
          if (snapshot == null) continue;
          try {
            final raster = await snapshot.toPngRaster();
            math[run.id] = await _decode(raster.pngBytes);
          } finally {
            snapshot.dispose();
          }
        } catch (_) {
          // The painter has a readable-text fallback for an unavailable raster.
        }
      }
    }
    return CanonicalLayoutPreviewAssets(
      pageFrame: frame,
      floatingImages: floating,
      mathImages: math,
    );
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pageFrame?.dispose();
    for (final image in floatingImages.values) {
      image.dispose();
    }
    for (final image in mathImages.values) {
      image.dispose();
    }
  }
}

/// Read-only Preview surface for a single canonical page. It paints the exact
/// absolute point positions and never runs paragraph layout or pagination.
class CanonicalLayoutPreviewPage extends StatelessWidget {
  const CanonicalLayoutPreviewPage({
    super.key,
    required this.page,
    required this.document,
    required this.assets,
  });

  final LayoutPage page;
  final ExamDocument document;
  final CanonicalLayoutPreviewAssets assets;

  @override
  Widget build(BuildContext context) {
    final width = LayoutUnits.ptToPx(page.pageSize.width);
    final height = LayoutUnits.ptToPx(page.pageSize.height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _CanonicalLayoutPreviewPainter(
          page: page,
          document: document,
          assets: assets,
        ),
      ),
    );
  }
}

class _CanonicalLayoutPreviewPainter extends CustomPainter {
  const _CanonicalLayoutPreviewPainter({
    required this.page,
    required this.document,
    required this.assets,
  });

  final LayoutPage page;
  final ExamDocument document;
  final CanonicalLayoutPreviewAssets assets;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(LayoutUnits.ptToPx(1));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, page.pageSize.width, page.pageSize.height),
      Paint()..color = Colors.white,
    );
    final frame = assets.pageFrame;
    if (frame != null) {
      _drawImage(frame, canvas, _pageRect, contain: false);
    } else {
      for (final decoration in page.decorations) {
        _paintDecoration(canvas, decoration);
      }
    }
    for (final block in _allBlocks(page.blocks)) {
      for (final decoration in block.decorations) {
        _paintDecoration(canvas, decoration);
      }
    }
    for (final block in page.blocks) {
      for (final line in block.allLines) {
        for (final run in line.runs) {
          _paintRun(canvas, line, run);
        }
      }
    }
    for (final placement in page.floatingElements) {
      if (placement.deferredReason == null) _paintFloat(canvas, placement);
    }
    canvas.restore();
  }

  Rect get _pageRect => Rect.fromLTWH(
        0,
        0,
        page.pageSize.width,
        page.pageSize.height,
      );

  Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* _allBlocks(block.children);
    }
  }

  void _paintDecoration(Canvas canvas, LayoutDecoration decoration) {
    final rect = _flutterRect(decoration.rect);
    if (rect.isEmpty) return;
    final paint = Paint()
      ..color = Color(decoration.colorArgb)
      ..strokeWidth = decoration.strokeWidthPt
      ..style = decoration.kind == LayoutDecorationKind.divider
          ? PaintingStyle.fill
          : PaintingStyle.stroke;
    if (decoration.kind == LayoutDecorationKind.divider) {
      canvas.drawRect(rect, paint);
    } else if (decoration.radiusPt > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(decoration.radiusPt)),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _paintRun(Canvas canvas, LayoutLine line, LayoutRun run) {
    if (run.advance <= 0 || (run.text.isEmpty && !run.isMath)) return;
    final top = line.baseline - run.baselineOffset;
    final destination = Rect.fromLTWH(run.x, top, run.width, run.height);
    if (run.isMath) {
      final image = assets.mathImages[run.id];
      if (image != null) {
        _drawImage(image, canvas, destination, contain: true);
      } else {
        _paintText(canvas, line, run, EquationModel.readableText(run.text));
      }
      return;
    }
    _paintText(canvas, line, run, run.text);
  }

  void _paintText(Canvas canvas, LayoutLine line, LayoutRun run, String text) {
    if (text.isEmpty) return;
    final style = run.style;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: style.font.family,
          fontSize: style.fontSizePt,
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          color: style.colorArgb == null ? Colors.black : Color(style.colorArgb!),
          letterSpacing: style.letterSpacingPt,
          height: style.lineHeightFactor,
          decoration: style.underline ? TextDecoration.underline : null,
        ),
      ),
      textDirection: run.direction == DocumentDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    try {
      final metrics = painter.computeLineMetrics();
      final baselineOffset = metrics.isEmpty
          ? run.baselineOffset
          : metrics.first.baseline;
      painter.paint(
        canvas,
        Offset(run.x, line.baseline - baselineOffset),
      );
    } finally {
      painter.dispose();
    }
  }

  void _paintFloat(Canvas canvas, LayoutFloatPlacement placement) {
    final element = document.floatingElementById(placement.reference.id);
    if (element == null) return;
    final rect = _flutterRect(placement.rect);
    if (rect.isEmpty) return;
    canvas.save();
    if (placement.rotationDegrees != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(placement.rotationDegrees * math.pi / 180);
      canvas.translate(-rect.center.dx, -rect.center.dy);
    }
    switch (element.type) {
      case FloatingElementType.image:
        final image = assets.floatingImages[element.id];
        if (image != null) _drawImage(image, canvas, rect, contain: true);
        break;
      case FloatingElementType.formula:
        if (placement.framed) _paintFloatFrame(canvas, rect, placement.strokeWidthPt);
        for (final line in placement.labelLines) {
          for (final run in line.runs) {
            _paintRun(canvas, line, run);
          }
        }
        break;
      case FloatingElementType.shape:
        if (element.isTextBox) {
          if (placement.framed) {
            _paintFloatFrame(canvas, rect, placement.strokeWidthPt);
          }
          for (final line in placement.labelLines) {
            for (final run in line.runs) {
              _paintRun(canvas, line, run);
            }
          }
        } else {
          _paintShape(canvas, rect, element.shape ?? FloatingShapeType.square,
              placement.strokeWidthPt);
        }
        break;
    }
    canvas.restore();
  }

  void _paintFloatFrame(Canvas canvas, Rect rect, double strokeWidth) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintShape(
    Canvas canvas,
    Rect rect,
    FloatingShapeType shape,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = rect.center;
    switch (shape) {
      case FloatingShapeType.circle:
        canvas.drawOval(rect, paint);
        break;
      case FloatingShapeType.triangle:
        final path = Path()
          ..moveTo(center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case FloatingShapeType.line:
      case FloatingShapeType.divider:
        canvas.drawLine(rect.topLeft, rect.bottomRight, paint);
        break;
      case FloatingShapeType.arrow:
        canvas.drawLine(rect.topLeft, rect.bottomRight, paint);
        final angle = math.atan2(rect.bottom - rect.top, rect.right - rect.left);
        const arrowLength = 10.0;
        final arrow = Path()
          ..moveTo(rect.right, rect.bottom)
          ..lineTo(
            rect.right - arrowLength * math.cos(angle - math.pi / 6),
            rect.bottom - arrowLength * math.sin(angle - math.pi / 6),
          )
          ..moveTo(rect.right, rect.bottom)
          ..lineTo(
            rect.right - arrowLength * math.cos(angle + math.pi / 6),
            rect.bottom - arrowLength * math.sin(angle + math.pi / 6),
          );
        canvas.drawPath(arrow, paint);
        break;
      case FloatingShapeType.square:
      case FloatingShapeType.rectangle:
      case FloatingShapeType.textBox:
        canvas.drawRect(rect, paint);
        break;
    }
  }

  void _drawImage(
    ui.Image image,
    Canvas canvas,
    Rect destination, {
    required bool contain,
  }) {
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    var target = destination;
    if (contain && image.width > 0 && image.height > 0) {
      final scale = math.min(
        destination.width / image.width,
        destination.height / image.height,
      );
      final width = image.width * scale;
      final height = image.height * scale;
      target = Rect.fromLTWH(
        destination.center.dx - width / 2,
        destination.center.dy - height / 2,
        width,
        height,
      );
    }
    canvas.drawImageRect(
      image,
      source,
      target,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  Rect _flutterRect(LayoutRect rect) => Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        rect.height,
      );

  @override
  bool shouldRepaint(covariant _CanonicalLayoutPreviewPainter oldDelegate) =>
      !identical(page, oldDelegate.page) ||
      !identical(document, oldDelegate.document) ||
      !identical(assets, oldDelegate.assets);
}
