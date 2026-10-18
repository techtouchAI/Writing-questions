// التحقق من أن `MathSnapshotHost` في ركيزة التحقق البصري يعكس بيئة الإنتاج.
//
// الركيزة (test/visual/visual_parity_fixture_test.dart) تصنع الملفات التي
// يحكم بها مقياس RMSE في CI؛ لو استُبدل مضيف اللقطات فيها بغير مضيف الإنتاج
// (أو أُلغي) لصارت المقارنة بين مسارين مختلفين والبوابة كاذبة. هذا الاختبار
// يعقد العقد نفسه صريحاً: كلا الملفين يثبّت المضيف بالبنية نفسها عبر
// `MaterialApp.builder`، والبنية تلك تُفعّل `MathSnapshotRenderer` فعلاً.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

/// التعبير الذي يبني به كل ملف مضيف اللقطات (يساوي المسافات مطبوعةً).
String _hostBuilderOf(String source, String label) {
  final match = RegExp(
    r'builder:\s*\(\s*[^,()]*\s*,\s*[^,()]*\s*\)\s*=>\s*'
    r'MathSnapshotHost\s*\(\s*child:\s*[^,()]*\s*\)',
  ).firstMatch(source);
  if (match == null) {
    fail(
      '$label لا يثبّت MathSnapshotHost عبر MaterialApp.builder — '
      'بيئة الركيزة لم تعد بيئة الإنتاج.',
    );
  }
  return match.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الركيزة تثبّت مضيف اللقطات بالبنية نفسها التي يثبّته بها الإنتاج', () {
    final production = File('lib/main.dart').readAsStringSync();
    final fixture =
        File('test/visual/visual_parity_fixture_test.dart').readAsStringSync();

    final productionBuilder = _hostBuilderOf(production, 'lib/main.dart');
    final fixtureBuilder = _hostBuilderOf(
      fixture,
      'test/visual/visual_parity_fixture_test.dart',
    );

    expect(
      fixtureBuilder,
      productionBuilder,
      reason: 'تركيب MathSnapshotHost في الركيزة يخالف الإنتاج — '
          'المقارنة البصرية ستقيس مسارين مختلفين.',
    );
  });

  testWidgets('بنية الإنتاج نفسها تُفعّل مسار اللقطات الذي تعتمده الركيزة',
      (tester) async {
    // نفس التركيب حرفيًا: builder يلف التطبيق كله بمضيف اللقطات.
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    expect(
      MathSnapshotRenderer.isAvailable,
      isTrue,
      reason: 'بلا مضيف مسجَّل ترتد كل صيغة إلى النص المقروء وتُصبح مقارنة '
          'الركيزة بلا معادلات حقيقية.',
    );
  });
}
