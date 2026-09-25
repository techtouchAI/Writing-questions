import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Size;

import '../models/floating_element.dart';
import '../views/widgets/paper_shape_painter.dart';
import 'docx_document_export_service.dart' show ShapeRasterizer;

/// ترسيم الأشكال المتجهة إلى صور PNG (لتصدير Word).
///
/// يُمرَّر كـ [ShapeRasterizer] إلى [DocxDocumentExportService] من الواجهة.
/// أي فشل يعيد `null` فيُكتب عنصر نصي بديل بدل إسقاط التصدير.
abstract final class ShapeImageRenderer {
  static Future<Uint8List?> rasterize(
    FloatingElement element,
    double widthPx,
    double heightPx,
  ) async {
    try {
      final width = widthPx.clamp(8.0, 1200.0).toInt();
      final height = heightPx.clamp(8.0, 1200.0).toInt();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
      PaperShapePainter(
        element.shape ?? FloatingShapeType.square,
        strokeWidth: element.strokeWidth,
      ).paint(canvas, Size(width.toDouble(), height.toDouble()));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        return null;
      }
      return bytes.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// نفس الدالة بصيغة [ShapeRasterizer] الجاهزة للتمرير.
  static ShapeRasterizer get asRasterizer => rasterize;
}
