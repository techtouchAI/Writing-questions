import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/math_image_renderer.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';

/// ما استُقبل من المُصدِّر: الصيغة والحجم والكثافة.
final List<List<Object?>> _calls = <List<Object?>>[];

/// صورة حقيقية من المحرك: الترميز إلى PNG يُختبر ببيانات يُنتجها `dart:ui`
/// نفسه لا ببايتات مزوّرة، فيُغطّى المسار كاملاً (التقاط → ترميز → فراغ نزول).
Future<ui.Image> _image(int widthPx, int heightPx) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(widthPx, heightPx);
  picture.dispose();
  return image;
}

Future<({int width, int height})> _sizeOfPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = (width: frame.image.width, height: frame.image.height);
  frame.image.dispose();
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MathSnapshotProvider? registered;

  void register(MathSnapshotProvider provider) {
    registered = provider;
    MathSnapshotRenderer.attach(provider);
  }

  tearDown(() {
    final provider = registered;
    if (provider != null) {
      MathSnapshotRenderer.detach(provider);
    }
    registered = null;
    _calls.clear();
  });

  test('لا مضيف: اللقطة null بلا استثناء، والترسيم يرتد إلى null', () async {
    expect(MathSnapshotRenderer.isAvailable, isFalse);
    expect(await MathSnapshotRenderer.render(r'x^2'), isNull);
    expect(await MathImageRenderer.rasterize(r'\frac{5}{8}', 12), isNull);
  });

  test('صيغة فارغة لا تُرسل إلى المضيف إطلاقاً', () async {
    var called = false;
    register((latex, fontSizePt, density) async {
      called = true;
      return MathSnapshot(image: await _image(1, 1), widthPt: 1, heightPt: 1);
    });
    expect(await MathImageRenderer.rasterize('   ', 12), isNull);
    expect(called, isFalse);
  });

  test('لقطة بلا خط أساس معلَن: المقاس يمرّ كما هو وبلا تمديد', () async {
    register((latex, fontSizePt, density) async {
      _calls.add(<Object?>[latex, fontSizePt, density]);
      return MathSnapshot(
        image: await _image(96, 48),
        widthPt: 12,
        heightPt: 6,
      );
    });

    final raster = await MathImageRenderer.rasterize(r'\frac{5}{8}', 12);
    expect(raster, isNotNull);
    expect(raster!.widthPt, 12);
    expect(raster.heightPt, 6);
    expect(await _sizeOfPng(raster.pngBytes),
        (width: 96, height: 48), // بلا سطر إضافي تحت.
        reason: 'بلا نزول معلَن لا يُمدّ السطر');
    // الكثافة المتفق عليها وحجم الخط بالنقاط يمرّان كما هما.
    expect(_calls.single, <Object?>[r'\frac{5}{8}', 12.0, 8.0]);
  });

  test('نزول الصيغة عن خط الأساس يُضاف فراغاً شفافاً أسفل الصورة', () async {
    register((latex, fontSizePt, density) async {
      return MathSnapshot(
        image: await _image(96, 48),
        widthPt: 12,
        heightPt: 6,
        baselinePt: 4, // النزول = 6 - 4 = نقطتان
      );
    });

    final raster = await MathImageRenderer.rasterize('x_1^2', 12);
    expect(raster, isNotNull);
    // العرض لا يتغير، والارتفاع يزاد بمقدار النزول فقط — بلا تحجيم ولا قصّ.
    expect(raster!.widthPt, 12);
    expect(raster.heightPt, moreOrLessEquals(8));
    expect(raster.pngBytes.length, greaterThan(8));
    // النزول نقطتان × الكثافة 8 = 16 بكسلاً تحت الصورة، وعرضها كما هو.
    expect(await _sizeOfPng(raster.pngBytes), (width: 96, height: 64));
  });

  test('مضيف يرمي استثناءً: null بدل سقوط تصدير الورقة كلها', () async {
    register((latex, fontSizePt, density) async {
      throw StateError('تلف في لوحة الرسم');
    });
    expect(await MathImageRenderer.rasterize(r'\sqrt{2}', 12), isNull);
  });

  test('مضيف يعيد صورة فارغة المقاس: تُهمل ولا تُكتب بعرض صفر', () async {
    register((latex, fontSizePt, density) async {
      return MathSnapshot(image: await _image(1, 1), widthPt: 0, heightPt: 0);
    });
    expect(await MathImageRenderer.rasterize('x', 12), isNull);
  });
}
