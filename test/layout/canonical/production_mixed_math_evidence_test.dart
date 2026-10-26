// Reviewable production evidence, not the injected canonical editor candidate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart' show MathStyle;
import 'package:flutter_test/flutter_test.dart';
import '../../support/production_evidence_fonts.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/semantic/inline_nodes.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/pdf_engine/pdf_math_rasters.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';
import 'package:writing_questions_app/views/widgets/safe_math_tex.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/paper_header_footer_view.dart';

const _out = 'build/production_fragment_repro';
Finder _key(String value) => find.byKey(ValueKey<String>(value));

// Observe the existing public plan-consumer boundary. No resolver injection,
// alternate pagination, production API, model field or recomputed PDF plan.
class _EvidenceController extends ExamWizardController {
  _EvidenceController(ExamDocument document) : super(document: document);
  CanonicalPagePlan? observedPlan;

  @override
  void applyLayoutPlan(CanonicalPagePlan? plan) {
    super.applyLayoutPlan(plan);
    observedPlan = plan;
  }
}

String _mixed(String label) => List<String>.generate(110, (index) =>
  '$label$index هذا نص عربي طويل مع English لفحص مقاطع السؤال والفرع وحدود الصفحات. '
  '${index == 15 || index == 70 ? r'معادلة مضمنة $x^2+1$ ثم معادلة منفردة' '\n' r'$$\frac{a+b}{c}$$' '\n' : ''}',
).join(' ');

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
    // Raster encoding/image codecs need real event-queue turns as well as the
    // fake frame clock. No real delay and no waiting on an unpumped future.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(ready(), isTrue, reason: 'Production math/layout work must actually finish.');
  await tester.pumpAndSettle();
}

Future<T> _finish<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  late T value;
  Object? failure;
  StackTrace? stack;
  unawaited(work.then<void>((result) { value = result; done = true; },
    onError: (Object error, StackTrace trace) { failure = error; stack = trace; done = true; }));
  await _until(tester, () => done);
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  return value;
}

Future<void> _png(WidgetTester tester, Finder finder, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  try {
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
    File('$_out/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Map<String, Rect> _geometry(WidgetTester tester, CanonicalPagePlan plan) {
  final result = <String, Rect>{};
  for (final page in plan.pages) {
    final canvas = tester.renderObject<RenderBox>(_key('a4-page-${page.index}'));
    for (final fragment in page.fragments) {
      final suffix = fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : '';
      final fields = find.descendant(of: _key('page-slice-${fragment.questionId}$suffix'), matching: find.byType(PaperField));
      for (final element in fields.evaluate()) {
        final box = element.findRenderObject()! as RenderBox;
        result['${page.index}/${fragment.fragmentIndex}/${element.widget.key}'] =
          MatrixUtils.transformRect(box.getTransformTo(canvas), Offset.zero & box.size);
      }
    }
  }
  return result;
}

Future<void> _selectPrinted(WidgetTester tester, LayoutDocument layout, String prefix) async {
  final page = layout.pages.firstWhere((page) => page.blocks.any((block) =>
    block.allLines.any((line) => line.runs.any((run) => run.semanticNodeId.startsWith(prefix) && !run.isMath && run.text.trim().isNotEmpty))));
  final finder = _key('a4-page-${page.index}');
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final canvas = tester.renderObject<RenderBox>(finder);
  final viewport = tester.getRect(_key('paper-v-scroll'));
  final points = <Offset>[
    for (final block in page.blocks)
      for (final line in block.allLines)
        for (final run in line.runs)
          if (run.semanticNodeId.startsWith(prefix) && !run.isMath && run.text.trim().isNotEmpty)
            canvas.localToGlobal(Offset(LayoutUnits.ptToPx(run.x + run.width / 2),
              LayoutUnits.ptToPx(line.baseline - run.baselineOffset + run.height / 2))),
  ].where(viewport.contains).toList();
  expect(points, isNotEmpty);
  // Existing production gesture selects the real owner without opening a text
  // editor. Never invoke a selection callback or mutate the model in the test.
  await tester.longPressAt(points.first);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

// Read the source RenderParagraphs, not a second TextPainter/paginator.
List<({String text, double baseline, Rect rect})> _paintedSourceLines(
    WidgetTester tester, Finder field, RenderBox canvas) {
  final result = <({String text, double baseline, Rect rect})>[];
  final paragraphs = find.descendant(of: field, matching: find.byType(RichText)).evaluate()
      .map((element) => element.findRenderObject()).whereType<RenderParagraph>();
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    if (text.isEmpty) continue;
    final transform = paragraph.getTransformTo(canvas);
    final firstBaseline = paragraph.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final firstCaretY = paragraph.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero).dy;
    var start = 0;
    var caretY = firstCaretY;
    void emit(int end) {
      final value = text.substring(start, end).replaceAll('\uFFFC', '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isEmpty) return;
      final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
      if (boxes.isEmpty) return;
      final rect = boxes.map((box) => MatrixUtils.transformRect(transform, box.toRect()))
          .reduce((a, b) => a.expandToInclude(b));
      result.add((text: value, rect: rect, baseline: MatrixUtils.transformPoint(
          transform, Offset(0, firstBaseline + caretY - firstCaretY)).dy));
    }
    for (var offset = 1; offset < text.length; offset++) {
      // A WidgetSpan's caret uses its object box, not the adjacent text
      // strut. It is covered by the separate real-math ink tests; this trace
      // follows text lines affected by its size, without inventing a line.
      if (text.codeUnitAt(offset) == 0xFFFC) continue;
      final nextY = paragraph.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
      if (nextY != caretY) { emit(offset); start = offset; caretY = nextY; }
    }
    emit(text.length);
  }
  result.sort((a, b) => a.baseline.compareTo(b.baseline));
  return result;
}

List<Map<String, Object>> _sourcePageBoundaries(WidgetTester tester,
    CanonicalPagePlan plan, ExamDocument document) {
  final rows = <Map<String, Object>>[];
  for (final fragment in plan.fragmentsOfQuestion('evidence-q')) {
    final suffix = fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : '';
    final slice = _key('page-slice-evidence-q$suffix');
    final canvas = tester.renderObject<RenderBox>(_key('a4-page-${fragment.pageIndex}'));
    final box = tester.renderObject<RenderBox>(slice);
    final clip = MatrixUtils.transformRect(box.getTransformTo(canvas), Offset.zero & box.size);
    for (final source in <(String, String)>[
      ('evidence-q/body', document.questions.single.body),
      ('evidence-q/branch/evidence-b/body', document.questions.single.branches.single.content.body),
    ]) {
      final field = find.descendant(of: slice, matching: find.byWidgetPredicate(
          (widget) => widget is PaperField && widget.controller.text == source.$2));
      expect(field, findsOneWidget);
      final native = _paintedSourceLines(tester, field, canvas).where((line) =>
          line.rect.bottom > clip.top && line.rect.top < clip.bottom).toList();
      final planned = plan.layout.pages[fragment.pageIndex].blocks.expand((block) => block.allLines).where((line) =>
          line.runs.any((run) => run.semanticNodeId.startsWith(source.$1) &&
              !run.isBlockMath && run.text.trim().isNotEmpty)).toList()
          ..sort((a, b) => a.baseline.compareTo(b.baseline));
      final plannedText = <String>[];
      for (final line in planned) {
        final runs = line.runs.where((run) => run.semanticNodeId.startsWith(source.$1)).toList()
            ..sort((a, b) => a.logicalIndex.compareTo(b.logicalIndex));
        plannedText.add(runs.map((run) => run.isMath ? '' : run.text).join()
            .replaceAll(RegExp(r'\s+'), ' ').trim());
      }
      final nativeText = native.map((line) => line.text).toList();
      var maxBaselineDelta = 0.0;
      if (native.length == planned.length) {
        for (var index = 0; index < native.length; index++) {
          final delta = (native[index].baseline - LayoutUnits.ptToPx(planned[index].baseline)).abs();
          if (delta > maxBaselineDelta) maxBaselineDelta = delta;
        }
      }
      final nativeMath = <({String latex, bool display, Rect rect})>[];
      for (final element in find.descendant(of: field, matching: find.byType(SafeMathTex)).evaluate()) {
        final widget = element.widget as SafeMathTex;
        final render = element.findRenderObject()! as RenderBox;
        final rect = MatrixUtils.transformRect(render.getTransformTo(canvas), Offset.zero & render.size);
        if (rect.bottom > clip.top && rect.top < clip.bottom) {
          nativeMath.add((latex: widget.latex.trim(), display: widget.mathStyle == MathStyle.display, rect: rect));
        }
      }
      nativeMath.sort((a, b) => a.rect.top.compareTo(b.rect.top));
      final plannedMath = <({LayoutRun run, Rect rect})>[];
      for (final line in plan.layout.pages[fragment.pageIndex].blocks.expand((block) => block.allLines)) {
        for (final run in line.runs.where((run) => run.isMath && run.semanticNodeId.startsWith(source.$1))) {
          plannedMath.add((run: run, rect: Rect.fromLTWH(LayoutUnits.ptToPx(run.x),
            LayoutUnits.ptToPx(line.baseline - run.baselineOffset),
            LayoutUnits.ptToPx(run.width), LayoutUnits.ptToPx(run.height))));
        }
      }
      plannedMath.sort((a, b) => a.rect.top.compareTo(b.rect.top));
      final mathGeometry = <Map<String, Object>>[];
      for (var index = 0; index < nativeMath.length && index < plannedMath.length; index++) {
        final actual = nativeMath[index];
        final expected = plannedMath[index];
        var delta = 0.0;
        for (final pair in [(actual.rect.left, expected.rect.left), (actual.rect.top, expected.rect.top),
            (actual.rect.width, expected.rect.width), (actual.rect.height, expected.rect.height)]) {
          final difference = (pair.$1 - pair.$2).abs();
          if (difference > delta) delta = difference;
        }
        mathGeometry.add({'nativeLatex': actual.latex, 'plannedLatex': expected.run.text.trim(),
          'nativeDisplay': actual.display, 'plannedDisplay': expected.run.isBlockMath,
          'nativeRectPx': [actual.rect.left, actual.rect.top, actual.rect.width, actual.rect.height],
          'plannedRectPx': [expected.rect.left, expected.rect.top, expected.rect.width, expected.rect.height],
          'maxGeometryDeltaPx': delta});
      }
      rows.add({
        'page': fragment.pageIndex, 'source': source.$1,
        'nativeLineCount': native.length, 'plannedLineCount': planned.length,
        'nativeText': nativeText, 'plannedText': plannedText,
        'maxBaselineDeltaPx': maxBaselineDelta,
        'nativeMathCount': nativeMath.length, 'plannedMathCount': plannedMath.length,
        'mathGeometry': mathGeometry,
        'nativeFirstBaselinePx': native.isEmpty ? -1 : native.first.baseline,
        'plannedFirstBaselinePx': planned.isEmpty ? -1 : LayoutUnits.ptToPx(planned.first.baseline),
        'nativeLastBaselinePx': native.isEmpty ? -1 : native.last.baseline,
        'plannedLastBaselinePx': planned.isEmpty ? -1 : LayoutUnits.ptToPx(planned.last.baseline),
      });
    }
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);
  for (final width in <double>[320, 360]) {
    testWidgets('production split question AND branch inline/display math evidence at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Directory(_out).createSync(recursive: true);
      final controller = _EvidenceController(ExamDocument(
        name: 'Production split mixed math', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(id: 'evidence-q', questionNumber: 1,
          statement: 'سؤال ممتد بمعادلات', body: _mixed('Q'),
          branches: <BranchModel>[BranchModel(id: 'evidence-b',
            content: BranchContent(statement: 'فرع ممتد بمعادلات', body: _mixed('B')))])],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(RepaintBoundary(key: const ValueKey<String>('mixed-evidence-screen'),
        child: MaterialApp(builder: (_, child) => MathSnapshotHost(child: child),
          home: ChangeNotifierProvider<ExamWizardController>.value(value: controller,
            child: ExamPreviewScreen(onBackToQuestions: () {}))),
      ));
      await _until(tester, () => controller.observedPlan != null &&
        identical(controller.observedPlan!.layout.source, controller.documentIr));
      expect(MathSnapshotRenderer.isAvailable, isTrue);
      final plan = controller.observedPlan!;
      final document = controller.document;
      final prefixes = <String>['evidence-q/body', 'evidence-q/branch/evidence-b/body'];
      final pageSets = <String, List<int>>{};
      for (final prefix in prefixes) {
        pageSets[prefix] = [for (final page in plan.layout.pages)
          if (page.blocks.any((block) => block.allLines.any((line) => line.runs.any((run) => run.semanticNodeId.startsWith(prefix))))) page.index];
        expect(pageSets[prefix]!.length, greaterThan(1), reason: 'BOTH source bodies must actually split.');
      }
      final math = plan.layout.allLines.expand((line) => line.runs).where((run) => run.isMath).toList();
      expect(math.any((run) => run.text.contains('x^2')), isTrue);
      expect(math.any((run) => run.text.contains(r'\frac')), isTrue);
      expect(math.map((run) => run.semanticNode).whereType<MathNode>().any((node) => node.isBlock), isTrue);
      expect(math.map((run) => run.semanticNode).whereType<MathNode>().any((node) => !node.isBlock), isTrue);
      expect(math.every((run) => run.mathBox?.source == 'mathSnapshot'), isTrue,
        reason: 'A host being available is insufficient: every math run needs actual snapshot metrics.');
      final before = _geometry(tester, plan);
      expect(before, isNotEmpty);
      var maxSelectionDelta = 0.0;
      final label = 'r9-${width.toInt()}';
      for (final state in <String>['before-selection', 'question-selected', 'branch-selected']) {
        if (state != 'before-selection') {
          if (state == 'branch-selected') {
            // The real long-press toggles the prior question off in multi-select
            // before selecting the branch; do not label a combined selection
            // as branch-only evidence.
            await _selectPrinted(tester, plan.layout, prefixes.first);
          }
          await _selectPrinted(tester, plan.layout, prefixes[state == 'question-selected' ? 0 : 1]);
          expect(controller.document, same(document));
          expect(controller.observedPlan, same(plan));
          final after = _geometry(tester, plan);
          expect(after.keys, before.keys);
          for (final entry in before.entries) {
            final actual = after[entry.key]!;
            // IEEE matrix/translation roundoff only; no pixel-height allowance.
            for (final pair in <(double, double)>[(actual.left, entry.value.left), (actual.top, entry.value.top),
                (actual.width, entry.value.width), (actual.height, entry.value.height)]) {
              final delta = (pair.$1 - pair.$2).abs();
              if (delta > maxSelectionDelta) maxSelectionDelta = delta;
              expect(pair.$1, closeTo(pair.$2, 1e-6), reason: entry.key);
            }
          }
        }
        for (final page in plan.pages) {
          final finder = _key('a4-page-${page.index}');
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await _png(tester, _key('mixed-evidence-screen'), '$label-$state-page-${page.index}-phone');
          await _png(tester, find.ancestor(of: finder, matching: find.byType(RepaintBoundary)).first,
            '$label-$state-page-${page.index}-paper');
        }
      }
      // The exact public raster collector used by the production PDF engine;
      // assert every requested formula succeeded, never accept text fallback.
      final requested = PdfMathRasters.collecting();
      for (final run in math) { requested.lookup(run.text, run.style.fontSizePt, isBlock: run.isBlockMath, bold: run.style.bold, colorArgb: run.style.colorArgb ?? 0xFF000000); }
      final rasters = await _finish(tester, requested.resolve());
      for (final run in math) {
        expect(rasters.lookup(run.text, run.style.fontSizePt, isBlock: run.isBlockMath, bold: run.style.bold, colorArgb: run.style.colorArgb ?? 0xFF000000), isNotNull);
      }
      final pdf = await _finish(tester, PdfExportService.buildDocumentPdfBytes(
        document: document, layoutDocument: plan.layout, mathRasters: rasters));
      File('$_out/$label-same-live-plan.pdf').writeAsBytesSync(pdf);
      File('$_out/$label-manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'surface': 'production default; no resolver/asset injection', 'mathHost': true,
        'widthDp': width, 'pageCount': plan.pageCount, 'bodyPages': pageSets,
        'mathRunCount': math.length, 'mathRasterCount': requested.requestCount,
        'mathMetricsSource': 'mathSnapshot', 'pdfUsesObservedLivePlan': true,
        'measuredSourceFields': before.length, 'maxSelectionDeltaPx': maxSelectionDelta,
        'selectionGeometryTolerancePx': 1e-6, 'manualVisualReview': false,
      }));
      final firstCanvas = tester.renderObject<RenderBox>(_key('a4-page-0'));
      final headerBox = tester.renderObject<RenderBox>(find.byType(PaperHeaderView));
      final headerRect = MatrixUtils.transformRect(headerBox.getTransformTo(firstCanvas), Offset.zero & headerBox.size);
      final expectedHeader = plan.layout.headerBlock!.rect;
      final lastFragment = plan.fragmentsOfQuestion('evidence-q').last;
      final suffix = '/slice${lastFragment.fragmentIndex}';
      final lastCanvas = tester.renderObject<RenderBox>(_key('a4-page-${lastFragment.pageIndex}'));
      final sliceBox = tester.renderObject<RenderBox>(_key('page-slice-evidence-q$suffix'));
      final sliceRect = MatrixUtils.transformRect(sliceBox.getTransformTo(lastCanvas), Offset.zero & sliceBox.size);
      // Branch DragTarget builds later than the question slice; its ValueKeys
      // are local (R6 already proves controller sharing). Identify this source
      // within the last slice, not by an invented global/suffixed branch key.
      final tailField = find.descendant(of: _key('page-slice-evidence-q$suffix'),
        matching: find.byWidgetPredicate((widget) => widget is PaperField &&
            widget.controller.text.contains('B109')));
      expect(tailField, findsOneWidget);
      final field = tester.widget<PaperField>(tailField);
      final paragraphs = find.descendant(of: tailField, matching: find.byType(RichText), skipOffstage: false).evaluate()
          .map((element) => element.findRenderObject()).whereType<RenderParagraph>().toList();
      final tailParagraph = paragraphs.firstWhere((paragraph) => paragraph.text.toPlainText().contains('B109'),
        orElse: () => throw TestFailure(jsonEncode({
          'nativeHeaderPx': [headerRect.left, headerRect.top, headerRect.width, headerRect.height],
          'canonicalHeaderPt': [expectedHeader.left, expectedHeader.top, expectedHeader.width, expectedHeader.height],
          'sourceContainsB109': field.controller.text.contains('B109'),
          'semanticContainsB109': field.semanticContent?.legacyText.contains('B109'),
          'richParagraphTails': paragraphs.map((p) { final text = p.text.toPlainText(); return text.substring(text.length > 160 ? text.length - 160 : 0); }).toList(),
          'editableCount': find.descendant(of: tailField, matching: find.byType(EditableText), skipOffstage: false).evaluate().length,
        })));
      final tailText = tailParagraph.text.toPlainText();
      final tailBoxes = tailParagraph.getBoxesForSelection(TextSelection(
          baseOffset: tailText.indexOf('B109'), extentOffset: tailText.length));
      final tailRect = tailBoxes.map((box) => MatrixUtils.transformRect(
          tailParagraph.getTransformTo(lastCanvas), box.toRect())).reduce((a, b) => a.expandToInclude(b));
      // RenderParagraph has no public getLineBoundary in Flutter 3.22. Read
      // its actual selection geometry; do not build a rival text layouter.
      final end = tailText.trimRight().length;
      final lastLineTop = tailParagraph.getBoxesForSelection(TextSelection(
          baseOffset: end - 1, extentOffset: end), boxHeightStyle: ui.BoxHeightStyle.strut).last.top;
      var nativeLineStart = 0;
      for (var offset = end - 1; offset >= 0; offset--) {
        final boxes = tailParagraph.getBoxesForSelection(TextSelection(
            baseOffset: offset, extentOffset: offset + 1), boxHeightStyle: ui.BoxHeightStyle.strut);
        if (boxes.isNotEmpty && boxes.last.top < lastLineTop) { nativeLineStart = offset + 1; break; }
      }
      final canonicalTailLine = plan.layout.allLines.lastWhere((line) => line.runs.any((run) =>
          run.semanticNodeId.startsWith(prefixes.last)));
      final tailRuns = canonicalTailLine.runs.toList()..sort((a, b) {
        final logical = a.logicalIndex.compareTo(b.logicalIndex);
        return logical != 0 ? logical : a.sourceStartOffset.compareTo(b.sourceStartOffset);
      });
      final trace = <String, Object>{
        'nativeHeaderPx': [headerRect.left, headerRect.top, headerRect.width, headerRect.height],
        'canonicalHeaderPx': [expectedHeader.left, expectedHeader.top, expectedHeader.width, expectedHeader.height].map(LayoutUnits.ptToPx).toList(),
        'nativeFinalBranchLine': tailText.substring(nativeLineStart, end).trim(),
        'canonicalFinalBranchLine': tailRuns.map((run) => run.text).join().trim(),
        'finalGlyphBottomPx': tailRect.bottom, 'fragmentBottomPx': sliceRect.bottom,
        'sourceTopPt': lastFragment.sourceTopPt, 'fragmentHeightPt': lastFragment.heightPt,
      };
      debugPrint('R14 source/window/paint trace $width: ${jsonEncode(trace)}');
      final manifestFile = File('$_out/$label-manifest.json');
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      manifest['sourceWindowPaintTrace'] = trace;
      final boundaries = _sourcePageBoundaries(tester, plan, document);
      manifest['sourcePageBoundaries'] = boundaries;
      manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
      // Existing R4 glyph-edge bound, not a new tolerance or enlarged clip.
      expect(tailRect.bottom, lessThanOrEqualTo(sliceRect.bottom + 0.75), reason: jsonEncode(trace));
      expect(trace['nativeFinalBranchLine'], trace['canonicalFinalBranchLine'], reason: jsonEncode(trace));
      for (final pair in <(double, double)>[(headerRect.left, expectedHeader.left),
          (headerRect.top, expectedHeader.top), (headerRect.width, expectedHeader.width),
          (headerRect.height, expectedHeader.height)]) {
        expect(pair.$1, closeTo(LayoutUnits.ptToPx(pair.$2), 1e-6), reason: jsonEncode(trace));
      }
      for (final row in boundaries) {
        final identity = '${row['source']} page ${row['page']}';
        expect(row['nativeText'], row['plannedText'], reason: identity);
        expect(row['nativeMathCount'], row['plannedMathCount'], reason: identity);
        for (final math in row['mathGeometry']! as List<Map<String, Object>>) {
          expect(math['nativeLatex'], math['plannedLatex'], reason: identity);
          expect(math['nativeDisplay'], math['plannedDisplay'], reason: identity);
          expect(math['maxGeometryDeltaPx'], lessThanOrEqualTo(1e-6), reason: '$identity ${jsonEncode(math)}');
        }
        expect(row['maxBaselineDeltaPx'], lessThanOrEqualTo(1e-6), reason: jsonEncode({
          for (final entry in row.entries)
            if (entry.key != 'nativeText' && entry.key != 'plannedText' && entry.key != 'mathGeometry') entry.key: entry.value,
        }));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
