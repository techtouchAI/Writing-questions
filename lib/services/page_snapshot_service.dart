import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'export_file_service.dart';

/// لقطة صفحة كاملة من لوحة المعاينة: بايتات PNG وأبعادها المنطقية.
class PageSnapshot {
  const PageSnapshot({
    required this.pageIndex,
    required this.pngBytes,
    required this.widthPx,
    required this.heightPx,
  });

  final int pageIndex;
  final Uint8List pngBytes;

  /// أبعاد الصفحة المنطقية (بكسل اللوحة عند 96dpi)، قبل تكبير دقة الطباعة.
  final double widthPx;
  final double heightPx;
}

/// خدمة لقط الصفحات من **نفس ما ترسمه المعاينة**.
///
/// مسار Exact يلتقط حدود الصفحة الأصلية، صفحةً صفحة، بعد إحضارها إلى نافذة
/// التمرير والتأكد من اكتمال رسمها. لا تُنشأ شجرة معاينة ثانية ولا تُكرّر
/// عناصر التحرير ومتحكمات النص أثناء الالتقاط.
abstract final class PageSnapshotService {
  /// بكسل لكل بوصة في لوحة المعاينة (96dpi منطقي).
  static const double canvasDpi = 96;

  /// دقة اللقط الافتراضية (طباعة عالية الجودة).
  static const double defaultDpi = 300;

  static const int _maxPaintWaitFrames = 12;

  /// يُحضر الصفحة إلى نافذة التمرير، ينتظر رسمها فعلياً، ثم يلتقطها.
  ///
  /// صفحات `SingleChildScrollView` البعيدة تكون موجودة في الشجرة لكنها قد لا
  /// تكون قد رُسمت؛ استدعاء `toImage` قبل الرسم كان سبباً لفشل التصدير. جلب
  /// الصفحة ثم انتظار إطار مرسوم يجعل الالتقاط مستقراً حتى في المستندات
  /// متعددة الصفحات، ومن دون بناء نسخة ثانية من عناصر التحرير.
  static Future<PageSnapshot> captureVisiblePage(
    GlobalKey boundaryKey, {
    required int pageIndex,
    double dpi = defaultDpi,
  }) async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError(
        'لا يمكن الوصول إلى صفحة المعاينة ${pageIndex + 1} قبل تركيبها.',
      );
    }

    await Scrollable.ensureVisible(
      context,
      alignment: 0,
      duration: Duration.zero,
      curve: Curves.linear,
    );
    await _waitForPaintedBoundary(boundaryKey, pageIndex);
    return capturePage(
      boundaryKey,
      pageIndex: pageIndex,
      dpi: dpi,
    );
  }

  /// يلتقط الصفحة التي يحمل [boundaryKey] جذرها.
  ///
  /// على المستدعي التأكد من أن الصفحة رُسمت في الإطار الحالي؛ للمسار الذي قد
  /// يلتقط صفحة خارج نافذة العرض استعمل [captureVisiblePage].
  static Future<PageSnapshot> capturePage(
    GlobalKey boundaryKey, {
    required int pageIndex,
    double dpi = defaultDpi,
  }) async {
    if (!dpi.isFinite || dpi <= 0) {
      throw ArgumentError.value(
        dpi,
        'dpi',
        'يجب أن تكون الدقة موجبة ومحدودة.',
      );
    }

    final boundary = _boundaryOf(boundaryKey, pageIndex);
    if (boundary.debugNeedsPaint) {
      throw StateError(
        'لا يمكن التقاط صفحة المعاينة ${pageIndex + 1}: لم يكتمل رسمها بعد.',
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
        pngBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        widthPx: boundary.size.width,
        heightPx: boundary.size.height,
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
      snapshots.add(
        await captureVisiblePage(
          boundaryKeys[index],
          pageIndex: index,
          dpi: dpi,
        ),
      );
    }
    return List<PageSnapshot>.unmodifiable(snapshots);
  }

  static Future<void> _waitForPaintedBoundary(
    GlobalKey boundaryKey,
    int pageIndex,
  ) async {
    for (var attempt = 0; attempt < _maxPaintWaitFrames; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      final object = boundaryKey.currentContext?.findRenderObject();
      if (object is RenderRepaintBoundary &&
          object.attached &&
          object.hasSize &&
          !object.debugNeedsPaint) {
        return;
      }
    }
    throw StateError(
      'تعذّر تجهيز صفحة المعاينة ${pageIndex + 1} للرسم بعد '
      '$_maxPaintWaitFrames إطاراً.',
    );
  }

  static RenderRepaintBoundary _boundaryOf(
    GlobalKey boundaryKey,
    int pageIndex,
  ) {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary ||
        !object.attached ||
        !object.hasSize ||
        object.size.isEmpty) {
      throw StateError(
        'لا يمكن التقاط الصفحة ${pageIndex + 1}: لوحة الصفحة غير جاهزة.',
      );
    }
    return object;
  }

  /// يسجّل سبب فشل اللقط مع الصفحة — ولا يبتلع الاستثناء (شرط §28).
  static void logCaptureFailure(
    Object error,
    StackTrace stackTrace,
    int pageIndex,
  ) {
    ExportFileService.logError(
      'Page snapshot failed (page ${pageIndex + 1})',
      error,
      stackTrace,
    );
  }
}
