/// رسم المعادلات **بمحرك التطبيق نفسه** (flutter_math_fork) إلى لقطة نقطية
/// ([ui.Image] بأبعادها بالنقاط — الترميز إلى PNG على عاتق المستهلك).
///
/// هذا الملف هو نقطة الوصل بين شجرة ودجت التصدير ومحرك الرياضيات: لا يحمل أي
/// منطق تخطيط ولا جدول محارف، بل يطلب من `MathSnapshotHost` (المضيف الخفيّ
/// في `lib/views/widgets/`) أن يبني `SafeMathTex` نفسه الذي تعرضه اللوحة،
/// ويقيسه ويرسمه على لوحة شفافة خارج الشاشة. فلا يبقى في المشروع محرك
/// رياضيات ثانٍ يحاول تقليد الأول:
///
/// ```text
/// LaTeX ─→ flutter_math_fork ─→ الشاشة (مباشر)
///                             └→ PDF: لقطة عالية الدقة
///                             └→ Word: لقطة عند تعذّر OMML فقط
/// LaTeX ─→ EquationModel ────→ OMML: معادلة Word الأصلية (المسار الأساسي)
/// ```
///
/// المقياس: تُرسم المعادلة بخط `fontSizePt × density` ثم يُقسم قياسها على
/// الكثافة نفسها — فتُقرأ الأبعاد بالنقاط كما يريدها محرك PDF وWord مباشرةً،
/// والدقة أعلى بمقدار الكثافة، بلا عامل تحجيم يدوي ولا تصحيح baseline
/// مخترَع: كل رقم يأتي من المحرك نفسه (`size` و`getDistanceToBaseline`).
library math_snapshot_renderer;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// معادلة LaTeX مرسومة صورةً: بايتات PNG بمقاساتها بالنقاط (pt).
///
/// الشكل المحايد الوحيد للصور في المشروع: يستعمله تصدير Word (عند تعذّر OMML)
/// وتصدير PDF (المسار الأساسي للرياضيات) — فلا مساران يرمّزان المحرك نفسه.
class MathRaster {
  const MathRaster({
    required this.pngBytes,
    required this.widthPt,
    required this.heightPt,
  });

  final Uint8List pngBytes;
  final double widthPt;
  final double heightPt;
}

/// نتيجة لقطة معادلة واحدة.
class MathSnapshot {
  const MathSnapshot({
    required this.image,
    required this.widthPt,
    required this.heightPt,
    this.baselinePt,
  });

  /// يُطلق الصورة بعد آخر استعمال — مالك اللقطة يملكها حتى يرمّزها.
  /// [`toPngRaster`] لا يطلقها بنفسه؛ يُستدعى مرة أو مرتين ثم [dispose].
  void dispose() => image.dispose();

  /// صورة المحرك الملتقطة (شفافة الخلفية، حبر أسود كما في المطبعة).
  ///
  /// تبقى [ui.Image] لا بايتات PNG عن قصد: ترميز PNG **عملية غير متزامنة**
  /// (`toByteData`) تتوقف في مناطق الاختبار ذات fake-async، فالترميز يُترك
  /// لمستهلك يحتاجه في سياقه غير المتزامن (`MathImageRenderer` للـ Word،
  /// و`PdfMathRasters` للـ PDF)، والمستدعي يُطلق الصورة بعد الترميز.
  final ui.Image image;

  /// العرض الطبيعي بالنقاط: قياس المحرك مقسوماً على الكثافة.
  final double widthPt;

  /// الارتفاع الطبيعي بالنقاط، متضمناً نزول الصيغة.
  final double heightPt;

  /// بعد خط الأساس من أعلى الصندوق بالنقاط، أو `null` إن لم يُعلن المحرك عن
  /// خط أساس (لا يُخترَع رقم بديل: من يحتاج النزول يحسبه من الارتفاع).
  final double? baselinePt;

  /// نزول الصيغة تحت خط الأساس — 0 عند غياب خط الأساس.
  double get descentPt {
    final baseline = baselinePt;
    if (baseline == null) {
      return 0;
    }
    final descent = heightPt - baseline;
    return descent < 0 ? 0 : descent;
  }

  /// PNG من الصورة الملتقطة، مع فراغ شفاف اختياري [padBelowPt] تحتها.
  ///
  /// الترميز غير متزامن (`toByteData`) فيُستدعى من مسار تصدير غير متزامن،
  /// لا من داخل المضيف الملتقِط. والكثافة تُقرأ من الصورة نفسها: لا رقم يدور
  /// في الحسبان ولا افتراض عن الخط. لا يُطلق [image] — مالك اللقطة يطلقها
  /// بعد آخر استعمال (فقد يُعاد الترميز بمسار بديل عند تعذّر الأول).
  Future<MathRaster> toPngRaster({double padBelowPt = 0}) async {
    final bytes = padBelowPt <= 0
        ? await _encodePlain()
        : await _encodePadded(padBelowPt);
    return MathRaster(
      pngBytes: bytes,
      widthPt: widthPt,
      heightPt: heightPt + (padBelowPt <= 0 ? 0 : padBelowPt),
    );
  }

  Future<Uint8List> _encodePlain() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('تعذّر ترميز لقطة المعادلة إلى PNG.');
    }
    return data.buffer.asUint8List();
  }

  /// تُرسم الصورة على لوحة أطول — بلا تمديد ولا قصّ لاحق — لأن من يضع
  /// الصورة يمسك حافتها السفلى عند خط الأساس (Word مثلاً).
  Future<Uint8List> _encodePadded(double padBelowPt) async {
    final density = heightPt > 0
        ? image.height / heightPt
        : MathSnapshotRenderer.defaultDensity;
    final extra = (padBelowPt * density).ceil();
    final widthPx = image.width;
    final paddedHeightPx = image.height + extra;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, widthPx.toDouble(), paddedHeightPx.toDouble()),
    );
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final ui.Image padded;
    try {
      padded = await picture.toImage(widthPx, paddedHeightPx);
    } finally {
      // اللوحة الوسيطة مورد أصلي: تُطلق فور أخذ الصورة منها (وحتى عند
      // فشل الرسم) فلا تتراكم لوحات غير محررة عبر تصدير طويل.
      picture.dispose();
    }
    final data = await padded.toByteData(format: ui.ImageByteFormat.png);
    padded.dispose();
    if (data == null) {
      throw StateError('تعذّر ترميز لقطة المعادلة الممدّدة إلى PNG.');
    }
    return data.buffer.asUint8List();
  }
}

/// مزوّد اللقطات: يبني الودجت ويرسمه (تنفيذه في `MathSnapshotHost`).
typedef MathSnapshotProvider = Future<MathSnapshot?> Function(
  String latex,
  double fontSizePt,
  double density,
);

/// خدمة الوصول إلى المضيف المرسوم بلا سياق واجهة (شجرة تصدير نظيفة).
abstract final class MathSnapshotRenderer {
  /// بكسل لكل نقطة: المتجهات المنقطة لا تستفيد من أكثر من هذا، والفرق بين
  /// 8 و12 غير مرئي على طابعة 600dpi بينما الحجم يتضاعف.
  static const double defaultDensity = 8.0;

  static MathSnapshotProvider? _provider;

  /// سبب آخر تعذّر في اللقطة — يملؤه `MathSnapshotHost` عند الفشل، للتشخيص
  /// في الاختبارات والسجلات فقط: لا يُبنى عليه أي منطق ولا يُقرأ في الإنتاج.
  static String? debugLastFailure;

  /// هل المضيف موجود؟ (لا يوجد في اختبارات المحرك النقية، ولا في isolate
  /// بلا شجرة ودجت — عندها ترجع [render] `null` فيرتد المستدعي بأمان).
  static bool get isAvailable => _provider != null;

  static void attach(MathSnapshotProvider provider) {
    _provider = provider;
  }

  static void detach(MathSnapshotProvider provider) {
    if (identical(_provider, provider)) {
      _provider = null;
    }
  }

  /// يرسم [latex] بمحرك المعاينة نفسه؛ `null` عند غياب المضيف أو أي فشل.
  static Future<MathSnapshot?> render(
    String latex, {
    double fontSizePt = 12,
    double density = defaultDensity,
  }) {
    final provider = _provider;
    if (provider == null || latex.trim().isEmpty || fontSizePt <= 0) {
      return Future<MathSnapshot?>.value();
    }
    try {
      return provider(latex, fontSizePt, density);
    } catch (_) {
      return Future<MathSnapshot?>.value();
    }
  }
}
