import 'dart:ui';

/// مقاسات لوحة ورقة A4 في الواجهة التفاعلية (WYSIWYG).
///
/// اللوحة = الورقة كاملة (بما فيها هوامش الطباعة) بدقة 96 نقطة/بوصة:
/// - A4 = 210×297 مم = 794×1123 بكسل منطقي.
/// - هامش 15 مم (مواصفة محرك الـ PDF) = 56.7 بكسل.
///
/// إحداثيات [`FloatingElement`] (dx, dy, width, height) تُخزَّن **بنفس
/// وحدات هذه اللوحة (بكسلات منطقي)** وتنتقل 1:1 إلى `pw.Positioned` في
/// محرك الـ PDF عبر [normalizedX]/[normalizedY] (نسب من أبعاد الورقة).
abstract final class ExamCanvasGeometry {
  /// عرض لوحة الورقة (بكسل منطقي = A4 عرضاً عند 96dpi).
  static const Size canvasSize = Size(794, 1123);

  /// هامش الورقة الداخلي (15 مم عند 96dpi) — يطابق `PdfExamEngine.pageMarginMillimeters`.
  static const double margin = 15 * 96 / 25.4;

  static double get width => canvasSize.width;

  static double get height => canvasSize.height;

  /// محتوى الورقة داخل الهوامش.
  static double get contentWidth => width - 2 * margin;

  static double get contentHeight => height - 2 * margin;

  /// موقع الإفلات الافتراضي لعنصر جديد (وسط اللوحة عمودياً قليلاً).
  static const double defaultElementDx = 322;
  static double get defaultElementDy => margin + 260;

  /// حجم افتراضي للعنصر العائم الجديد.
  static const double defaultElementSize = 100;

  /// إحداثي أفقي مُطبَّع [0..1] من عرض الورقة (لنقله إلى نقاط PDF).
  static double normalizedX(double dx) => dx / width;

  /// إحداثي رأسي مُطبَّع [0..1] من ارتفاع الورقة (لنقله إلى نقاط PDF).
  static double normalizedY(double dy) => dy / height;

  static double normalizedWidth(double w) => w / width;

  static double normalizedHeight(double h) => h / height;
}
