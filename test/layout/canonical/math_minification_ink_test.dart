// Real-font, real-source, actual preview paint. This catches operator dropout
// after minification, which a high-resolution raster/rectangle test cannot.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

import '../../visual/visual_parity_fixture_test.dart' as fixture;
import 'math_visual_acceptance_test.dart' show finish;

List<({Rect rect, double alphaMass})> _thinCrosses(Uint8List rgba, int width, int height) {
  final visited = Uint8List(width * height);
  final result = <({Rect rect, double alphaMass})>[];
  int alpha(int p) => rgba[p * 4 + 3];
  for (var p = 0; p < visited.length; p++) {
    if (visited[p] != 0 || alpha(p) < 128) continue;
    final queue = <int>[p];
    visited[p] = 1;
    var left = width, right = 0, top = height, bottom = 0;
    final rows = <int, int>{}, columns = <int, int>{};
    for (var i = 0; i < queue.length; i++) {
      final at = queue[i], x = at % width, y = at ~/ width;
      left = math.min(left, x); right = math.max(right, x);
      top = math.min(top, y); bottom = math.max(bottom, y);
      rows.update(y, (v) => v + 1, ifAbsent: () => 1);
      columns.update(x, (v) => v + 1, ifAbsent: () => 1);
      for (final next in [if (x > 0) at - 1, if (x + 1 < width) at + 1,
        if (y > 0) at - width, if (y + 1 < height) at + width]) {
        if (visited[next] == 0 && alpha(next) >= 128) {
          visited[next] = 1; queue.add(next);
        }
      }
    }
    final w = right - left + 1, h = bottom - top + 1;
    // Thin connected horizontal + vertical arms, NOT digits, x or '=' rules.
    if (w < 10 || h < 10 || queue.length / (w * h) >= 0.2 ||
        rows.values.reduce(math.max) < w * 0.7 || columns.values.reduce(math.max) < h * 0.7) continue;
    var mass = 0.0;
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        mass += alpha(y * width + x) / 255;
      }
    }
    result.add((rect: Rect.fromLTRB(left.toDouble(), top.toDouble(),
      (right + 1).toDouble(), (bottom + 1).toDouble()), alphaMass: mass));
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(fixture.loadAppFonts);

  testWidgets('native minified math retains each actual plus operator ink at 96dpi', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
      home: const SizedBox.expand()));
    final document = fixture.fixtureDocument();
    final layout = await finish(tester, CanonicalLayoutService.resolve(document: document));
    final assets = await finish(tester, CanonicalLayoutPreviewAssets.load(layout: layout, document: document));
    addTearDown(assets.dispose);
    final page = layout.pages.first;
    final line = page.blocks.expand((b) => b.allLines).singleWhere((line) =>
      line.runs.any((run) => run.isMath && run.text == 'x^2+2x+1=0'));
    final run = line.runs.singleWhere((run) => run.isMath && run.text == 'x^2+2x+1=0');
    final source = assets.mathImages[run.id]!;
    final sourcePixels = (await finish(tester,
      source.toByteData(format: ui.ImageByteFormat.rawRgba)))!.buffer.asUint8List();
    final crosses = _thinCrosses(sourcePixels, source.width, source.height);
    expect(crosses, hasLength(2), reason: 'Both real source plus glyphs must exist before judging the preview.');
    await tester.pumpWidget(MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: RepaintBoundary(
        key: const ValueKey('native-math-ink'), child: CanonicalLayoutPreviewPage(
          layoutDocument: layout, page: page, document: document, assets: assets))))));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('native-math-ink')));
    final painted = await finish(tester, boundary.toImage());
    try {
      final rgba = (await finish(tester, painted.toByteData(format: ui.ImageByteFormat.rawRgba)))!.buffer.asUint8List();
      final destination = Rect.fromLTWH(run.x, line.baseline - run.baselineOffset, run.width, run.height);
      final scalePt = math.min(destination.width / source.width, destination.height / source.height);
      final scalePx = LayoutUnits.ptToPx(scalePt);
      final origin = Offset(LayoutUnits.ptToPx(destination.center.dx - source.width * scalePt / 2),
        LayoutUnits.ptToPx(destination.center.dy - source.height * scalePt / 2));
      final red = Color(run.style.colorArgb!).red;
      for (var i = 0; i < crosses.length; i++) {
        final cross = crosses[i];
        final expectedMass = cross.alphaMass * scalePx * scalePx;
        final rect = Rect.fromLTRB(origin.dx + cross.rect.left * scalePx,
          origin.dy + cross.rect.top * scalePx, origin.dx + cross.rect.right * scalePx,
          origin.dy + cross.rect.bottom * scalePx).inflate(1);
        var actualMass = 0.0;
        for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
          for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
            actualMass += ((255 - rgba[(y * painted.width + x) * 4]) / (255 - red)).clamp(0, 1);
          }
        }
        debugPrint('MATH_INK_EVIDENCE ${jsonEncode({'operator': i, 'sourceAlphaMass': cross.alphaMass,
          'expectedOutputInk': expectedMass, 'actualOutputInk': actualMass, 'scalePx': scalePx})}');
        // Conservation of integrated alpha, allowing ONE fully covered output
        // pixel for discrete boundary quantisation, not arbitrary font/size
        // compensation. Baseline cubic paint loses >9 pixel-equivalents per +.
        expect(actualMass, closeTo(expectedMass, 1), reason: 'Actual plus operator ink must survive native minification.');
        expect(0, isNot(closeTo(expectedMass, 1)), reason: 'Deleting this operator must not satisfy the same ink contract.');
      }
    } finally {
      painted.dispose();
    }
  });
}
