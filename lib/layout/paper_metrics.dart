import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../models/exam_canvas_geometry.dart';

/// المقاسات المشتركة بين لوحة المعاينة (بكسل منطقي عند 96dpi) وملف الـ PDF
/// (نقاط 72dpi) — نسبة تحويل واحدة تضمن أن ما يُرى هو ما يُطبع.
///
/// صندوق المحتوى في كل الصفحات يُشتق من هامش واحد هو `PaperSettings.marginMm`
/// (انظر [pageContentHeightFor]/[contentWidthFor])، وهو نفسه حشوة الإطار.
abstract final class PaperMetrics {
  /// نقطة PDF لكل بكسل منطقي على اللوحة (A4: 595.28pt ↔ 794px).
  static double get pointsPerPixel => PdfPageFormat.a4.width / ExamCanvasGeometry.width;

  static double px(double points) => points / pointsPerPixel;

  static double pt(double pixels) => pixels * pointsPerPixel;

  /// توينب Word للبكسل المنطقي (1pt = 20 تويب): المصدر الوحيد لتحويل أي
  /// مسافة في نموذج الورقة إلى `w:spacing` في ملف Word — فلا تُكتب أرقام
  /// توينب يدوياً في أي مكان (كانت 30/40/60/180 مكتوبة يدوياً فتنحرف عن
  /// المعاينة والـ PDF).
  static int twips(double pixels) => (pt(pixels) * 20).round();

  /// المسافة الرأسية بين كتلتين متتاليتين (سؤالين أو الترويسة وأول سؤال)،
  /// وبين آخر سؤال والتذييل.
  static const double blockSpacingPx = 10;

  /// الفجوة الافتراضية بين عناصر الكتلة الواحدة (سطر العنوان ← النص ←
  /// النقاط ← الفروع) عندما لا يخصّص المدرس `paragraphSpacing` — القيمة
  /// نفسها في المعاينة والـ PDF وWord.
  static const double elementGapPx = 2;

  /// الفجوة الافتراضية بين فرع وآخر داخل السؤال نفسه (وبين نقطتين) — صفر
  /// يعني تلاصقاً كاملاً كما في Word/MSO.
  static const double itemGapPx = 0;

  /// الفجوة الافتراضية بين سطر الفرع ونصه/نقاطه.
  static const double branchGapPx = 1;

  /// عرض المحتوى على لوحة بالهامش الافتراضي.
  static double get contentWidthPx => ExamCanvasGeometry.contentWidth;

  /// الارتفاع المتاح للكتل داخل صفحة واحدة لهامش طباعة [marginMm] بالمليمتر
  /// (الصندوق كاملاً؛ التذييل يُحجز من آخر كتلة فقط عبر `lastPageReserve`).
  static double pageContentHeightFor(double marginMm) =>
      ExamCanvasGeometry.contentHeightFor(marginMm);

  /// عرض المحتوى لهامش طباعة [marginMm] بالمليمتر.
  static double contentWidthFor(double marginMm) =>
      ExamCanvasGeometry.contentWidthFor(marginMm);

  /// معرّف كتلة الترويسة في محرك التقسيم.
  static const String headerBlockId = '__header__';

  /// معرّف قياس التذييل (لا يدخل التقسيم كتلةً؛ ارتفاعه يُحجز من آخر كتلة).
  static const String footerBlockId = '__footer__';
}
