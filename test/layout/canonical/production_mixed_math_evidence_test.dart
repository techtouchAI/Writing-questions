// Reviewable production evidence, not the injected canonical editor candidate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      final firstCanvas = tester.renderObject<RenderBox>(_key('a4-page-0'));
      final headerBox = tester.renderObject<RenderBox>(find.byType(PaperHeaderView));
      final headerRect = MatrixUtils.transformRect(headerBox.getTransformTo(firstCanvas), Offset.zero & headerBox.size);
      final expectedHeader = plan.layout.headerBlock!.rect;
      final lastFragment = plan.fragmentsOfQuestion('evidence-q').last;
      final suffix = '/slice${lastFragment.fragmentIndex}';
      final lastCanvas = tester.renderObject<RenderBox>(_key('a4-page-${lastFragment.pageIndex}'));
      final sliceBox = tester.renderObject<RenderBox>(_key('page-slice-evidence-q$suffix'));
      final sliceRect = MatrixUtils.transformRect(sliceBox.getTransformTo(lastCanvas), Offset.zero & sliceBox.size);
      final tailField = _key('branch-body-evidence-b$suffix');
      final tailParagraph = find.descendant(of: tailField, matching: find.byType(RichText)).evaluate()
          .map((element) => element.findRenderObject()).whereType<RenderParagraph>()
          .firstWhere((paragraph) => paragraph.text.toPlainText().contains('B109'));
      final tailText = tailParagraph.text.toPlainText();
      final tailBoxes = tailParagraph.getBoxesForSelection(TextSelection(
          baseOffset: tailText.indexOf('B109'), extentOffset: tailText.length));
      final tailRect = tailBoxes.map((box) => MatrixUtils.transformRect(
          tailParagraph.getTransformTo(lastCanvas), box.toRect())).reduce((a, b) => a.expandToInclude(b));
      final nativeTailLine = tailParagraph.getLineBoundary(TextPosition(offset: tailText.length - 1));
      final canonicalTailLine = plan.layout.allLines.lastWhere((line) => line.runs.any((run) =>
          run.semanticNodeId.startsWith(prefixes.last)));
      final tailRuns = canonicalTailLine.runs.toList()..sort((a, b) {
        final logical = a.logicalIndex.compareTo(b.logicalIndex);
        return logical != 0 ? logical : a.sourceStartOffset.compareTo(b.sourceStartOffset);
      });
      final trace = <String, Object>{
        'nativeHeaderPx': [headerRect.left, headerRect.top, headerRect.width, headerRect.height],
        'canonicalHeaderPx': [expectedHeader.left, expectedHeader.top, expectedHeader.width, expectedHeader.height].map(LayoutUnits.ptToPx).toList(),
        'nativeFinalBranchLine': tailText.substring(nativeTailLine.start, nativeTailLine.end).trim(),
        'canonicalFinalBranchLine': tailRuns.map((run) => run.text).join().trim(),
        'finalGlyphBottomPx': tailRect.bottom, 'fragmentBottomPx': sliceRect.bottom,
        'sourceTopPt': lastFragment.sourceTopPt, 'fragmentHeightPt': lastFragment.heightPt,
      };
      debugPrint('R14 source/window/paint trace $width: ${jsonEncode(trace)}');
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
      for (final run in math) { requested.lookup(run.text, run.style.fontSizePt, isBlock: run.isBlockMath); }
      final rasters = await _finish(tester, requested.resolve());
      for (final run in math) {
        expect(rasters.lookup(run.text, run.style.fontSizePt, isBlock: run.isBlockMath), isNotNull);
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
        'sourceWindowPaintTrace': trace,
      }));
      // Existing R4 glyph-edge bound, not a new tolerance or enlarged clip.
      expect(tailRect.bottom, lessThanOrEqualTo(sliceRect.bottom + 0.75), reason: jsonEncode(trace));
      expect(trace['nativeFinalBranchLine'], trace['canonicalFinalBranchLine'], reason: jsonEncode(trace));
      for (final pair in <(double, double)>[(headerRect.left, expectedHeader.left),
          (headerRect.top, expectedHeader.top), (headerRect.width, expectedHeader.width),
          (headerRect.height, expectedHeader.height)]) {
        expect(pair.$1, closeTo(LayoutUnits.ptToPx(pair.$2), 1e-6), reason: jsonEncode(trace));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
