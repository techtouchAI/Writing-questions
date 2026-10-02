import 'docx_document_export_service.dart' show MathRasterizer;
import 'math_snapshot_renderer.dart';

/// ترسيم صيغة LaTeX إلى صورة PNG لتصدير Word — عند تعذّر OMML فقط.
///
/// الرسم لا يتم هنا: تُطلب اللقطة من [MathSnapshotRenderer] الذي يبني
/// **المحرك نفسه الذي تعرضه لوحة A4** (`SafeMathTex` ← `flutter_math_fork`)
/// ويرسمه خارج الشاشة. فأي معادلة تعجز عن تمثيلها OMML تظهر في Word بشكلها
/// الحقيقي في التطبيق، لا نص كود ولا رسماً من محرك ثانٍ.
///
/// - المقاسات بالنقاط (pt) هي نفسها التي يضعها تصدير PDF، فيتطابق حجم
///   المعادلة في الورقتين.
/// - الكثافة [density] بكسل لكل نقطة (≈576 نقطة/بوصة) لتبقى حادة عند
///   الطباعة والتكبير.
/// - يُضاف أسفل الصورة فراغ شفاف بمقدار نزول الصيغة عن خط الأساس، لأن Word
///   يضع أسفل الصورة المضمّنة **على** خط أساس النص: بهذا تجلس المعادلة على
///   السطر تماماً بدل أن ترتفع عنه. النزول يقيسه المضيف من المحرك نفسه
///   (`getDistanceToBaseline`) ويأتي جاهزاً في `MathSnapshot.descentPt`، فلا
///   يُخترَع مقدار بديل عند غيابه — وعندها تُكتب الصورة بلا تمديد.
///
/// أي فشل (صيغة غير مدعومة أو تعذّر الرسم أو غياب المضيف) يعيد `null` فيكتب
/// المصدر نص الصيغة المقروء بدل إسقاط الفقرة.
abstract final class MathImageRenderer {
  /// بكسل لكل نقطة — صور المتجهات لا تفقد الحدّة بكثافة أعلى.
  ///
  /// ‏8 بكسل/نقطة ≈ 576 نقطة/بوصة: معادلة بعرض بوصة تحمل 576 بكسلاً فتبقى
  /// حادّة عند الطباعة على طابعات الليزر (600dpi) وعند التكبير في Word.
  static const double density = MathSnapshotRenderer.defaultDensity;

  static Future<MathRaster?> rasterize(String latex, double fontSizePt) async {
    // أي فشل في اللقطة (مضيف غائب، محرف ناقص، استثناء في الرسم) ارتدادٌ إلى
    // `null`: المُصدِّر يكتب النص المقروء، ولا تسقط الورقة كلها.
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
    if (snapshot.widthPt <= 0 || snapshot.heightPt <= 0) {
      snapshot.dispose();
      return null;
    }
    try {
      try {
        return await snapshot.toPngRaster(padBelowPt: snapshot.descentPt);
      } catch (_) {
        // تعذّر الترميز الممدّد: تُكتب المعادلة بلا فراغ النزول أحسن من تُفقد.
        if (snapshot.descentPt <= 0) {
          rethrow;
        }
        return await snapshot.toPngRaster();
      }
    } catch (_) {
      return null; // تعذّر الترميز كله: ارتداد صامت يُبلَّغ، لا تفجير للتصدير.
    } finally {
      snapshot.dispose();
    }
  }

  /// نفس الدالة بصيغة `MathRasterizer` الجاهزة للتمرير من الواجهة.
  static MathRasterizer get asRasterizer => rasterize;
}
