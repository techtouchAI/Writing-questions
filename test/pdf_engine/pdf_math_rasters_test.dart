// عقد لقطات رياضيات PDF: جولة تجمع الطلبات من الشجرة، وجولة تخدم من المخزون.
// ما يُختبر هنا هو ما لا يُرى في ملف ناتج: أن كل صيغة طُلبت مرة واحدة بحجمها،
// وأن ما تعذّر التقاطه لا يدخل المخزون فيرتد نصاً مقروءاً بدل أن يفجّر التصدير،
// وأن القياسات تصل بالنقاط كما قاسها المحرك (بلا فراغ نزول: ذاك عقد Word).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/pdf_engine/pdf_math_rasters.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';

import 'fake_math_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = FakeMathHost();
  setUp(host.attach);
  tearDown(host.detach);

  group('سياق اللقطات', () {
    test('جولة الجمع تسجّل كل صيغة مرة واحدة بحجم خطها، ولا تخدم شيئاً', () {
      final collecting = PdfMathRasters.collecting();

      expect(collecting.lookup(r'\frac{5}{8}', 12), isNull);
      expect(collecting.lookup(r'\frac{5}{8}', 12), isNull);
      expect(collecting.lookup(r'\frac{5}{8}', 10.5), isNull);
      expect(collecting.lookup('x_1', 12), isNull);

      // نفس الصيغة بحجمين مختلفين = لقطان مختلفان (المقياس بالنقاط لا نسبي).
      expect(collecting.requestCount, 3);
      expect(
        collecting.recorded,
        contains((latex: 'x_1', fontSizePt: 12.0)),
      );
    });

    test('الصيغة الفارغة أو الحجم غير القانوني لا يصل إلى المضيف', () {
      final collecting = PdfMathRasters.collecting();

      expect(collecting.lookup('   ', 12), isNull);
      expect(collecting.lookup(r'x^2', 0), isNull);
      expect(collecting.lookup(r'x^2', -3), isNull);
      expect(collecting.isEmpty, isTrue);
      expect(host.requests, isEmpty);
    });

    test('سياق المخزون يخدم ما جُمع ويرد null لما غاب', () {
      final raster = MathRaster(
        pngBytes: Uint8List.fromList(<int>[1, 2, 3]),
        widthPt: 20,
        heightPt: 14,
      );
      final serving = PdfMathRasters.serving(<String, MathRaster>{
        PdfMathRasters.key(r'\frac{5}{8}', 12): raster,
      });

      expect(serving.lookup(r'\frac{5}{8}', 12), same(raster));
      // حجم لم تُلتقط له لقطة: لا تُنسب إليه لقطة حجم آخر.
      expect(serving.lookup(r'\frac{5}{8}', 11), isNull);
      expect(serving.lookup(r'\sqrt{2}', 12), isNull);
      // جولة البناء لا تسجّل طلبات: المخزون هو المرجع.
      expect(serving.isEmpty, isTrue);
    });

    test('resolve يلتقط ما جُمع فقط، ويُسقِط ما تعذّر بلا استثناء', () async {
      final collecting = PdfMathRasters.collecting();
      collecting.lookup(r'\sqrt{9}', 12);
      collecting.lookup(r'\vec{F}', 12);
      host.failingLatex = r'\vec{F}';

      final serving = await collecting.resolve();

      expect(host.requestedLatex, <String>[r'\sqrt{9}', r'\vec{F}']);
      expect(serving.lookup(r'\sqrt{9}', 12), isNotNull);
      // ما تعذّر لا يدخل المخزون: المحرك يكتبه نصاً مقروءاً، لا صورة فاضية.
      expect(serving.lookup(r'\vec{F}', 12), isNull);
    });

    test('الكثافة الافتراضية تمرّ كما هي، فتكون الصورة بدقة التصدير', () async {
      final collecting = PdfMathRasters.collecting();
      collecting.lookup('x', 12);
      await collecting.resolve();

      expect(host.lastDensity, MathSnapshotRenderer.defaultDensity);
      expect(host.requests.single.fontSizePt, 12);
    });
  });

  group('اللقطة الواحدة', () {
    test('القياس بالنقاط من المحرك، وPNG حقيقي بلا فراغ نزول إضافي', () async {
      final raster = await PdfMathRasters.rasterize(r'\hat{x}', 12);

      expect(raster, isNotNull);
      // عرض المضيف الوهمي: 6 + الطول × 0.8 — لا تقريب ولا تحجيم في الطريق.
      expect(raster!.widthPt, 6 + r'\hat{x}'.length * 0.8);
      expect(raster.heightPt, moreOrLessEquals(12 * 1.4));
      // توقيع PNG: الصورة مرمَّزة فعلاً، لا رأس قائمة مُختلَق.
      expect(raster.pngBytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });

    test('لقطة فارغة المقاس تُهمل، ولا تُكتب صورة بصفر عرض', () async {
      final empty = FakeMathHost(widthOf: (_) => 0);
      empty.attach();
      addTearDown(empty.detach);

      expect(await PdfMathRasters.rasterize('x', 12), isNull);
      expect(await PdfMathRasters.rasterize('', 12), isNull);
      expect(await PdfMathRasters.rasterize(r'x^2', 0), isNull);
    });

    test('بلا مضيف رسم: سياق فارغ صالح، ولا استثناء يصل إلى المُصدِّر', () async {
      final orphan = PdfMathRasters.collecting();
      orphan.lookup(r'\frac{1}{2}', 12);
      // بلا مضيف (لا شجرة ودجت، ولا تسجيل): كل صيغة ترتد null بصمت.
      host.detach();

      final serving = await orphan.resolve();
      expect(serving.lookup(r'\frac{1}{2}', 12), isNull);
      expect(await PdfMathRasters.rasterize(r'\frac{1}{2}', 12), isNull);
    });
  });
}
