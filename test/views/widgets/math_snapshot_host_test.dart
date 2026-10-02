import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

/// اختبار الوصلة نفسها: المضيف يبنى مع `MaterialApp.builder` كما في
/// `lib/main.dart`، ثم يُطلب رسم معادلة بلا أي سياق واجهة — فتُلتقط صورة
/// حقيقية من محرك `flutter_math_fork` نفسه.
///
/// الخط هنا خط الاختبار (Ahem) لا KaTeX، فلا نتحقق من شكل المحارف بل من
/// العقد: أن الرسم يجري، وأن الأبعاد تُقرأ بالنقاط، وأن للصورة بكسلاتها
/// بمقدار الكثافة. الالتقاط كله متزامن (`toImageSync`) فلا يحتاج منطقة
/// غير متزامنة ولا يعلّق على ترميز PNG — ذاك على عاتق المستهلك.
Future<MathSnapshot?> _capture(String latex, WidgetTester tester) async {
  final future = MathSnapshotRenderer.render(latex, fontSizePt: 12);
  // إطارات كافية: بناء ودجت اللقطة → تخطيط → رسم → التقاط في postFrame.
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
  final snapshot = await future;
  // ignore: avoid_print
  print('لقطة <$latex>: ${snapshot == null ? 'null — ${MathSnapshotRenderer.debugLastFailure}' : '${snapshot.widthPt}x${snapshot.heightPt}pt، بكسل '
      '${snapshot.image.width}x${snapshot.image.height}، نزول ${snapshot.descentPt}'}');
  return snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('لقطة معادلة من المضيف: صورة بقياسين متَّفقين', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: Center(child: Text('ورقة الأسئلة'))),
      ),
    );

    final snapshot = await _capture(r'\frac{5}{8}', tester);
    expect(snapshot, isNotNull, reason: MathSnapshotRenderer.debugLastFailure);
    // 1px منطقي لكل نقطة عند الكثافة 8: بكسلات الصورة = القياس بالنقاط × 8.
    expect(snapshot!.widthPt, greaterThan(0));
    expect(snapshot.widthPt, lessThan(200));
    expect(snapshot.image.width, moreOrLessEquals(snapshot.widthPt * 8, epsilon: 1));
    expect(snapshot.image.height, moreOrLessEquals(snapshot.heightPt * 8, epsilon: 1));
    // خط الأساس يُقرأ إن أعلنه المحرك، وإلا null — ولا يُخترَع بديل.
    expect(snapshot.baselinePt, anyOf(isNull, greaterThan(0)));
    expect(snapshot.descentPt, greaterThanOrEqualTo(0));
  });

  testWidgets('صيغة يكذّبها المحرك لا تُسقط اللقطة ولا تترك مهمة معلقة',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    // `SafeMathTex` يرتد إلى النص المقروء عند تعذر الصيغة، فالمطلوب أن
    // تُنتَج لقطة دائماً ولا يبقى طلب معلّقاً يُعطّل التصدير كله.
    final snapshot = await _capture(r'\frac{1}{', tester);
    expect(snapshot, isNotNull, reason: MathSnapshotRenderer.debugLastFailure);
  });

  testWidgets('القياس من المحرك: الأعرض والأطول يُقرآن بلا قصّ',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    final small = await _capture('x', tester);
    expect(small, isNotNull, reason: MathSnapshotRenderer.debugLastFailure);
    final wide = await _capture(r'\frac{12345}{2}', tester);
    expect(wide, isNotNull, reason: MathSnapshotRenderer.debugLastFailure);
    // بسطٌ أعرض من محرف واحد، وكسرٌ أطول منه: القياس من المحرك لا من تقدير.
    expect(wide!.widthPt, greaterThan(small!.widthPt));
    expect(wide.heightPt, greaterThan(small.heightPt));
  });

  testWidgets('المضيف يسجّل نفسه ويلغي التسجيل عند التفكيك', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    expect(MathSnapshotRenderer.isAvailable, isTrue);

    // إطار أخير يُنهي مهمة معلّقة قبل التفكيك، ثم شجرة بلا مضيف تُسقط التسجيل.
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump();
    expect(MathSnapshotRenderer.isAvailable, isFalse);
    // بلا مضيف: ارتداد صامت إلى `null` — لا استثناء في مسار التصدير.
    expect(await MathSnapshotRenderer.render(r'x^2'), isNull);
  });
}
