import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../models/exam_canvas_geometry.dart';

/// المقاسات المشتركة بين لوحة المعاينة (بكسل منطقي عند 96dpi) وملف الـ PDF
/// (نقاط 72dpi) — نسبة تحويل واحدة تضمن أن ما يُرى هو ما يُطبع.
abstract final class PaperMetrics {
  /// نقطة PDF لكل بكسل منطقي على اللوحة (A4: 595.28pt ↔ 794px).
  static double get pointsPerPixel => PdfPageFormat.a4.width / ExamCanvasGeometry.width;

  static double px(double points) => points / pointsPerPixel;

  static double pt(double pixels) => pixels * pointsPerPixel;

  /// ارتفاع تذييل الصفحة (رقم الصفحة) على اللوحة.
  static const double footerHeightPx = 18;

  /// المسافة الرأسية بين كتلتين متتاليتين (سؤالين أو الترويسة وأول سؤال).
  static const double blockSpacingPx = 10;

  /// الارتفاع المتاح للكتل داخل صفحة واحدة (بعد الهوامش والتذييل).
  static double get pageContentHeightPx =>
      ExamCanvasGeometry.contentHeight - footerHeightPx;

  static double get contentWidthPx => ExamCanvasGeometry.contentWidth;

  /// معرّف كتلة الترويسة في محرك التقسيم.
  static const String headerBlockId = '__header__';
}
