import 'canonical/layout_units.dart';

import '../models/exam_canvas_geometry.dart';

/// المقاسات المشتركة بين لوحة المعاينة (بكسل منطقي عند 96dpi) وملف الـ PDF
/// (نقاط 72dpi) — نسبة تحويل واحدة تضمن أن ما يُرى هو ما يُطبع.
///
/// صندوق المحتوى في كل الصفحات يُشتق من هامش واحد هو `PaperSettings.marginMm`
/// (انظر [pageContentHeightFor]/[contentWidthFor])، وهو نفسه حشوة الإطار.
abstract final class PaperMetrics {
  /// نقطة PDF لكل بكسل منطقي على اللوحة (A4: 595.2756pt ↔ 793.7008px).
  // A rounded 794px A4 width is not a physical-unit conversion. It made
  // 10.5pt become 14.005277px while canonical measurement used 14px.
  static double get pointsPerPixel =>
      LayoutUnits.pointsPerInch / LayoutUnits.logicalPixelsPerInch;

  static double px(double points) => LayoutUnits.ptToPx(points);

  static double pt(double pixels) => LayoutUnits.pxToPt(pixels);

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
  static double get contentWidthPx => contentWidthFor(ExamCanvasGeometry.marginMm);

  /// الارتفاع المتاح للكتل داخل صفحة واحدة لهامش طباعة [marginMm] بالمليمتر
  /// (الصندوق كاملاً؛ التذييل يُحجز من آخر كتلة فقط عبر `lastPageReserve`).
  static double pageContentHeightFor(double marginMm) =>
      px(LayoutUnits.a4.height) - 2 * ExamCanvasGeometry.marginFor(marginMm);

  /// عرض المحتوى لهامش طباعة [marginMm] بالمليمتر.
  static double contentWidthFor(double marginMm) =>
      px(LayoutUnits.a4.width) - 2 * ExamCanvasGeometry.marginFor(marginMm);

  /// معرّف كتلة الترويسة في محرك التقسيم.
  static const String headerBlockId = '__header__';

  /// معرّف قياس التذييل (لا يدخل التقسيم كتلةً؛ ارتفاعه يُحجز من آخر كتلة).
  static const String footerBlockId = '__footer__';
}
