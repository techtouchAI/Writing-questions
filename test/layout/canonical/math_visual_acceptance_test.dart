import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:writing_questions_app/views/widgets/safe_math_tex.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/production_evidence_fonts.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/semantic/inline_nodes.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

Future<T> finish<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  late T result;
  Object? error;
  StackTrace? trace;
  unawaited(work.then<void>((value) { result = value; done = true; },
    onError: (Object e, StackTrace s) { error = e; trace = s; done = true; }));
  for (var i = 0; i < 500 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(done, isTrue);
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return result;
}

// Connected components distinguish actual curved/stroked math glyphs from
// Ahem's filled rectangles. The thin fraction rule is intentionally excluded;
// no golden/font substitution, clipping allowance, or RMSE threshold is used.
({int ink, int nonRectangular, int filledRectangles}) inkShape(
    Uint8List rgba, int width, int height) {
  final visited = Uint8List(width * height);
  bool ink(int p) => rgba[p * 4 + 3] >= 128;
  var total = 0, curved = 0, rectangles = 0;
  for (var p = 0; p < visited.length; p++) {
    if (visited[p] != 0 || !ink(p)) continue;
    final queue = <int>[p]; visited[p] = 1;
    var left = width, right = 0, top = height, bottom = 0, count = 0;
    for (var i = 0; i < queue.length; i++) {
      final at = queue[i], x = at % width, y = at ~/ width;
      count++;
      if (x < left) left = x; if (x > right) right = x;
      if (y < top) top = y; if (y > bottom) bottom = y;
      for (final next in <int>[if (x > 0) at - 1, if (x + 1 < width) at + 1,
          if (y > 0) at - width, if (y + 1 < height) at + width]) {
        if (visited[next] == 0 && ink(next)) { visited[next] = 1; queue.add(next); }
      }
    }
    total += count;
    final w = right - left + 1, h = bottom - top + 1;
    // At density 8, a rule is a few pixels high; glyphs span tens of pixels.
    if (w < 8 || h < 8) continue;
    if (count == w * h) { rectangles++; } else { curved++; }
  }
  return (ink: total, nonRectangular: curved, filledRectangles: rectangles);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);
  for (final width in <double>[320, 360]) {
    testWidgets('real math acceptance has glyph ink, not Ahem rectangles at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
        home: const SizedBox.expand()));
      for (final isBlock in <bool>[false, true]) {
      final snapshot = await finish(tester, MathSnapshotRenderer.render(r'\frac{a+b}{c}', isBlock: isBlock));
      expect(snapshot, isNotNull);
      try {
        final pixels = await finish(tester, snapshot!.image.toByteData(format: ui.ImageByteFormat.rawRgba));
        final shape = inkShape(pixels!.buffer.asUint8List(), snapshot.image.width, snapshot.image.height);
        Directory('build/production_fragment_repro').createSync(recursive: true);
        final png = await finish(tester, snapshot.toPngRaster());
        File('build/production_fragment_repro/r13-math-${width.toInt()}-${isBlock ? 'display' : 'inline'}.png').writeAsBytesSync(png.pngBytes);
        expect(shape.ink, greaterThan(0), reason: 'An empty snapshot is not readable math.');
        expect(shape.nonRectangular, greaterThanOrEqualTo(3), reason: 'a, b and c must be glyph strokes, not solid font-test blocks: $shape');
        expect(shape.filledRectangles, 0, reason: 'Ahem rectangle glyphs must fail acceptance: $shape');
      } finally { snapshot?.dispose(); }
      }
    });

    testWidgets('real math acceptance snapshot ignores ambient debug font weight at $width', (tester) async {
      await tester.pumpWidget(MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
        home: const Scaffold(body: Center(child: RepaintBoundary(key: ValueKey<String>('math-source-reference'),
          child: SafeMathTex(r'\frac{a+b}{c}', textStyle: TextStyle(fontSize: 96,
            color: Colors.black, fontWeight: FontWeight.normal, fontStyle: FontStyle.normal)))))));
      final snapshot = await finish(tester, MathSnapshotRenderer.render(r'\frac{a+b}{c}', fontSizePt: 12));
      expect(snapshot, isNotNull);
      final reference = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey<String>('math-source-reference'))).toImageSync();
      try {
        final expected = await finish(tester, reference.toByteData(format: ui.ImageByteFormat.rawRgba));
        final actual = await finish(tester, snapshot!.image.toByteData(format: ui.ImageByteFormat.rawRgba));
        expect(snapshot.image.width, reference.width, reason: 'Same formula/style/density must not inherit a bold debug font outside Scaffold.');
        expect(snapshot.image.height, reference.height);
        expect(actual!.buffer.asUint8List(), orderedEquals(expected!.buffer.asUint8List()));
      } finally { snapshot?.dispose(); reference.dispose(); }
    });

    testWidgets('real math acceptance preserves inline versus display metrics at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
        home: const SizedBox.expand()));
      final document = ExamDocument(name: 'Same formula, two actual styles',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'), questions: <QuestionModel>[
          QuestionModel(id: 'styles-q', questionNumber: 1, body:
            r'عربي English $\frac{a+b}{c}$' '\n' r'$$\frac{a+b}{c}$$')]);
      final layout = await finish(tester, CanonicalLayoutService.resolve(document: document));
      final runs = layout.allLines.expand((line) => line.runs).where((run) => run.isMath).toList();
      final inline = runs.singleWhere((run) => !(run.semanticNode! as MathNode).isBlock);
      final display = runs.singleWhere((run) => (run.semanticNode! as MathNode).isBlock);
      expect(inline.style.fontSizePt, display.style.fontSizePt);
      expect(display.mathBox!.heightPt, greaterThan(inline.mathBox!.heightPt),
        reason: 'The real display fraction is taller; source style must survive snapshot collection/cache.');
    });
  }
}
