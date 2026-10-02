import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/exam_canvas_geometry.dart';
import 'export_file_service.dart';

/// لقطة صفحة كاملة من لوحة المعاينة: بايتات PNG وأبعادها.
class PageSnapshot {
  const PageSnapshot({
    required this.pageIndex,
    required this.pngBytes,
    required this.widthPx,
    required this.heightPx,
  });

  final int pageIndex;
  final Uint8List pngBytes;

  /// العرض المنطقي (بكسل اللوحة 96dpi) الذي التُقطت منه الصفحة.
  final double widthPx;
  final double heightPx;
}

/// خدمة لقط الصفحات من **نفس ما تراه الشاشة**.
///
/// هي أساس التصدير الدقيق (Exact): لا يعيد PDF ولا Word حساب layout، بل
/// يستعمل الصفحة كما رسمها Flutter بالبكسل → فتطابق الناتج المعاينة بالبناء
/// لا بالمصادفة. الدقة تُحسب من A4: `pixelRatio = dpi / 96`، والقيمة
/// الافتراضية 300dpi كما تُطبع الصور مهنياً.
abstract final class PageSnapshotService {
  /// بكسل لكل بوصة في لوحة المعاينة (96dpi منطقي).
  static const double canvasDpi = 96;

  /// دقة اللقط الافتراضية (طباعة عالية الجودة).
  static const double defaultDpi = 300;

  /// يلتقط الصفحة التي يحمل [boundaryKey] جذرها.
  static Future<PageSnapshot> capturePage(
    GlobalKey boundaryKey, {
    required int pageIndex,
    double dpi = defaultDpi,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'لا يمكن التقاط الصفحة ${pageIndex + 1}: لوحة الصفحة غير مرسومة بعد.',
      );
    }
    final pixelRatio = dpi / canvasDpi;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('تعذّر ترميز الصفحة ${pageIndex + 1} صورةً (PNG).');
      }
      return PageSnapshot(
        pageIndex: pageIndex,
        pngBytes: data.buffer.asUint8List(),
        widthPx: ExamCanvasGeometry.width,
        heightPx: ExamCanvasGeometry.height,
      );
    } finally {
      image.dispose();
    }
  }

  /// يلتقط كل الصفحات بالترتيب (صفحة واحدة فاشلة = استثناء واضح برقمها).
  static Future<List<PageSnapshot>> captureAll(
    List<GlobalKey> boundaryKeys, {
    double dpi = defaultDpi,
  }) async {
    final snapshots = <PageSnapshot>[];
    for (var index = 0; index < boundaryKeys.length; index++) {
      snapshots.add(await capturePage(boundaryKeys[index], pageIndex: index, dpi: dpi));
    }
    return List<PageSnapshot>.unmodifiable(snapshots);
  }

  /// يسجّل سبب فشل اللقط مع الصفحة — ولا يبتلع الاستثناء (شرط §28).
  static void logCaptureFailure(Object error, StackTrace stackTrace, int pageIndex) {
    ExportFileService.logError(
      'Page snapshot failed (page ${pageIndex + 1})',
      error,
      stackTrace,
    );
  }
}
