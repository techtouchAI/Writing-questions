import '../services/math_snapshot_renderer.dart';

/// لقطات رياضيات PDF: مِرحلتان حول بناءٍ متزامن.
///
/// بناء وثائق `pdf` متزامن كلّه، ولقطة المعادلة تحتاج شجرة ودجت وإطار رسم
/// (`MathSnapshotHost`) — فلا يُطلب شيءٌ أثناء البناء. السياق يُفتح حول جولة
/// أولى تبني الورقة كاملةً وتسجّل ما احتاجته من معادلات، ثم تُلتقط كلها مرة
/// واحدة، ثم تُبنى الورقة ثانيةً والمخزون جاهز خلف كل طلب.
///
/// كل هذا بمحرك العرض نفسه (`flutter_math_fork`): فما تراه اللوحة هو ما
/// يُطبع، بلا خط رياضيات ثانٍ ولا رسم متجه بديل — ومقاسات اللقطة نقاطٌ
/// حقيقية فتتطابق الأسطر والصفحات مع المعاينة.
final class PdfMathRasters {
  PdfMathRasters._(this._cache);

  /// جولة جمع: كل طلب يُسجَّل ويُرجَع `null` (الموضع يحجزه نص مؤقت).
  PdfMathRasters.collecting() : _cache = null;

  /// جولة البناء: الطلب يُخدَم من المخزون، ومن غاب يرتد إلى نص مقروء.
  factory PdfMathRasters.serving(Map<String, MathRaster> cache) =>
      PdfMathRasters._(Map<String, MathRaster>.unmodifiable(cache));

  /// مفتاح الطلب: نفس الصيغة بحجم خط مختلف لقطةٌ مختلفة (المقياس بالنقاط).
  static String key(String latex, double fontSizePt) =>
      '${fontSizePt.toStringAsFixed(3)}|$latex';

  final Map<String, MathRaster>? _cache;
  final List<({String latex, double fontSizePt})> _requests =
      <({String latex, double fontSizePt})>[];
  final Set<String> _seen = <String>{};

  /// كم صيغة طُلبت في جولة الجمع (للاختبار والتشخيص).
  int get requestCount => _requests.length;

  /// الطلبات المسجَّلة بترتيبها (نسخة للقراءة: للاختبار والتشخيص).
  List<({String latex, double fontSizePt})> get recorded =>
      List<({String latex, double fontSizePt})>.unmodifiable(_requests);

  bool get isEmpty => _requests.isEmpty;

  /// اللقطة الجاهزة لـ [latex] بحجم [fontSizePt]، أو `null` إن لم تُلتقط.
  MathRaster? lookup(String latex, double fontSizePt) {
    final cache = _cache;
    if (latex.trim().isEmpty || fontSizePt <= 0) {
      return null;
    }
    if (cache == null) {
      final id = key(latex, fontSizePt);
      if (_seen.add(id)) {
        _requests.add((latex: latex, fontSizePt: fontSizePt));
      }
      return null;
    }
    return cache[key(latex, fontSizePt)];
  }

  /// يلتقط كل ما جُمع (بلا انتظار تتابعي: المضيف يبني شجرة اللقطات دفعة
  /// واحدة) ويعيد سياق بناء يخدم من المخزون. صيغة تعذّرت لا تدخل المخزون،
  /// فيكتب محرك الصفحات نصها المقروء — لا كود LaTeX.
  Future<PdfMathRasters> resolve({
    double density = MathSnapshotRenderer.defaultDensity,
  }) async {
    final rasters = await Future.wait<MathRaster?>(
      _requests.map((request) => rasterize(request.latex, request.fontSizePt, density: density)),
    );
    final cache = <String, MathRaster>{};
    for (var index = 0; index < _requests.length; index++) {
      final raster = rasters[index];
      if (raster != null) {
        final request = _requests[index];
        cache[key(request.latex, request.fontSizePt)] = raster;
      }
    }
    return PdfMathRasters.serving(cache);
  }

  /// لقطة واحدة إلى [MathRaster] بغير تمديد أسفلها: صورة PDF تُوضع في سطر
  /// النص كما تضعها المعاينة، وارتفاع صندوق المحرك يتضمّن نزولها أصلاً
  /// (بخلاف Word الذي يمسك الحافة السفلى للصورة عند خط الأساس فيُمَدّ).
  static Future<MathRaster?> rasterize(
    String latex,
    double fontSizePt, {
    double density = MathSnapshotRenderer.defaultDensity,
  }) async {
    final MathSnapshot? snapshot;
    try {
      snapshot = await MathSnapshotRenderer.render(
        latex,
        fontSizePt: fontSizePt,
        density: density,
      );
    } catch (_) {
      return null;
    }
    if (snapshot == null) {
      return null;
    }
    try {
      if (snapshot.widthPt <= 0 || snapshot.heightPt <= 0) {
        return null;
      }
      return await snapshot.toPngRaster();
    } catch (_) {
      return null;
    } finally {
      snapshot.dispose();
    }
  }

  /// بلا مضيف رسم (اختبارات نقية، أو تصدير من isolate): لا لقطات ولا انتظار —
  /// ترتد كل صيغة إلى نصها المقروء كما في سياق فارغ المخزون.
  static PdfMathRasters empty() => PdfMathRasters.serving(
        <String, MathRaster>{},
      );
}
