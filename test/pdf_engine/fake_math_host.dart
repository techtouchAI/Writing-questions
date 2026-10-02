// مضيف رياضيات وهمي لاختبارات التصدير: يسجّل كل ما تطلبه الشجرة من لقطات
// ويعيد صورة حقيقية صغيرة من `dart:ui` نفسه — فيمرّ الاختبار بالمسار الجديد
// كاملاً (طلب ← لقطة ← PNG ← صورة في ملف PDF/Word) بلا انتظار إطار رسم في
// `testWidgets`، وبلا بيانات زائفة: البايتات الناتجة يولّدها المحرك.
//
// لا غنى عن هذا في اختبارات الأنابيب: بدونه يبقى المضيف غائباً فترتد كل
// صيغة إلى النص المقروء، ولا يُختبر مسار الصورة إطلاقاً.
import 'dart:ui' as ui;

import 'package:writing_questions_app/services/math_snapshot_renderer.dart';

/// عرض اللقطة بالنقاط: يتناسب مع طول الصيغة فيقيس الاختبار فراغاً واقعياً
/// بدل رقم ثابت لا يشبه شيئاً.
double mathWidthOf(String latex) => 6 + latex.length * 0.8;

class FakeMathHost {
  FakeMathHost({this.widthOf = mathWidthOf});

  final double Function(String latex) widthOf;

  /// ما طلبته الشجرة فعلاً: (الصيغة، حجم الخط بالنقاط) بترتيب الطلب.
  final List<({String latex, double fontSizePt})> requests =
      <({String latex, double fontSizePt})>[];

  /// الصيغ المطلوبة وحدها، بلا تكرار: للمقارنة بمجموعة متوقعة.
  List<String> get requestedLatex =>
      requests.map((request) => request.latex).toSet().toList(growable: false);

  /// صيغة تُرفض في المضيف (لقطة `null`) — لاختبار الارتداد إلى النص المقروء.
  String? failingLatex;

  /// آخر كثافة وصلت من المُصدِّر (للتأكد أنها تمرّ كما هي).
  double lastDensity = 0;

  /// مرجع ثابت للتسجيل والإلغاء — كما في `MathSnapshotHost`: tear-off جديد في
  /// كل مرة يفشل `identical` في `detach` فيبقى التسجيل معلقاً.
  late final MathSnapshotProvider _registeredProvider = provide;

  bool _attached = false;

  void attach() {
    assert(!_attached, 'المضيف الوهمي مسجَّل مسبقاً');
    _attached = true;
    // الاختبارات تتشارك النسخة نفسها (setUp واحد): السجل يبدأ نظيفاً وإلا
    // تسرّبت طلبات اختبار سابق إلى `requests.single` في الاختبار التالي.
    requests.clear();
    failingLatex = null;
    lastDensity = 0;
    MathSnapshotRenderer.attach(_registeredProvider);
  }

  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    MathSnapshotRenderer.detach(_registeredProvider);
  }

  Future<MathSnapshot?> provide(
    String latex,
    double fontSizePt,
    double density,
  ) async {
    requests.add((latex: latex, fontSizePt: fontSizePt));
    lastDensity = density;
    if (failingLatex == latex) {
      return null;
    }
    final widthPt = widthOf(latex);
    final heightPt = fontSizePt * 1.4;
    return MathSnapshot(
      image: await _solidImage(
        (widthPt * density).round(),
        (heightPt * density).round(),
      ),
      widthPt: widthPt,
      heightPt: heightPt,
      baselinePt: heightPt * 0.78,
    );
  }
}

/// صورة صلبة بمقاس بالبكسل — ترميز PNG يتم بعدها في مسار التصدير نفسه.
Future<ui.Image> _solidImage(int widthPx, int heightPx) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    widthPx <= 0 ? 1 : widthPx,
    heightPx <= 0 ? 1 : heightPx,
  );
  picture.dispose();
  return image;
}

/// كم صورة مضمَّنة فعلاً في ملف PDF: قاموس كل كائن صورة يحمل `/Subtype`
/// قيمته `/Image`، ومكتبة pdf تكتب قواميس الكائنات بلا مسافة بين المفتاح
/// والقيمة (`/Subtype/Image`) — فتُزال المسافات أولاً ليعمل العدّ على
/// الصيغتين. لا يعتمد على أي افتراض عن عدد المقاطع: صورة = كائن صورة.
int imagesInPdf(List<int> bytes) {
  final text = String.fromCharCodes(bytes).replaceAll(' ', '');
  const marker = '/Subtype/Image';
  var count = 0;
  for (var cursor = text.indexOf(marker);
      cursor >= 0;
      cursor = text.indexOf(marker, cursor + 1)) {
    count++;
  }
  return count;
}
