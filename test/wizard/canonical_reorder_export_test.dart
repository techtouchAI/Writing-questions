// Candidate-only real drags. Original production suite is unchanged.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../pdf_engine/pdf_content_probe.dart';
import '../support/production_evidence_fonts.dart';

class _Observed extends ExamWizardController {
  _Observed({required ExamDocument document}) : super(document: document);
  CanonicalPagePlan? plan;
  @override
  void applyLayoutPlan(CanonicalPagePlan? value) {
    super.applyLayoutPlan(value);
    plan = value;
  }
}

ExamDocument _document() => ExamDocument(name: 'Actual reorder evidence',
  header: ExamHeaderModel.initial(subject: 'English'), questions: [
    QuestionModel(id: 'qa', questionNumber: 1, statement: 'QALPHA نص مختلط', branches: [
      BranchModel(id: 'ba', content: BranchContent(statement: 'BALPHA'), marks: 1),
      BranchModel(id: 'bb', content: BranchContent(statement: 'BBETA'), marks: 2),
    ]),
    QuestionModel(id: 'qb', questionNumber: 2, statement: 'QBETA نص مختلط', branches: [
      BranchModel(id: 'bc', content: BranchContent(statement: 'BGAMMA'), marks: 3),
    ]),
  ]);

const _out = 'build/production_fragment_repro';
const _tokens = {'QALPHA', 'QBETA', 'BALPHA', 'BBETA', 'BGAMMA'};

Offset _center(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
}

Future<void> _capture(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final box = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('reorder-screen')));
    final image = await box.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(data!.buffer.asUint8List());
    } finally { image.dispose(); }
  });
}

// Inventory every mounted interactive primitive in these actual production
// frames. Bounds are transformed to screen dp (NOT unscaled paper pixels).
// A render-path hit sample is diagnostic, NOT proof of gesture ownership or a
// 48dp effective target. Dialogs, later pages and platform handles are excluded
// explicitly; do not extrapolate this inventory to all editing states.
List<Map<String, Object?>> _touchInventory(WidgetTester tester) {
  final viewport = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final rows = <Map<String, Object?>>[];
  for (final element in tester.allElements) {
    final widget = element.widget;
    final interactive = widget is EditableText || widget is Draggable<Object> ||
      (widget is InkResponse && (widget.onTap != null || widget.onLongPress != null || widget.onDoubleTap != null)) ||
      (widget is GestureDetector && (widget.onTap != null || widget.onLongPress != null ||
        widget.onPanUpdate != null || widget.onScaleUpdate != null));
    if (!interactive) continue;
    final object = element.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      rows.add({'widget': widget.runtimeType.toString(), 'key': widget.key?.toString(),
        'measurement': 'unavailable', 'effectiveTargetVerified': false});
      continue;
    }
    final rect = MatrixUtils.transformRect(object.getTransformTo(null), Offset.zero & object.size);
    String? tooltip;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Tooltip) {
        tooltip = (ancestor.widget as Tooltip).message;
        return false;
      }
      return true;
    });
    rows.add({'widget': widget.runtimeType.toString(), 'key': widget.key?.toString(),
      'tooltip': tooltip, 'text': widget is EditableText ? widget.controller.text : null,
      'measurement': 'transformed rendered bounds, not effective gesture ownership',
      'rectDp': [rect.left, rect.top, rect.right, rect.bottom],
      'widthDp': rect.width, 'heightDp': rect.height,
      'fullyInViewport': rect.left >= viewport.left && rect.top >= viewport.top &&
        rect.right <= viewport.right && rect.bottom <= viewport.bottom,
      'renderedBoundsMeet48': rect.width >= 48 && rect.height >= 48,
      'centreContainsRenderObjectInHitPath': viewport.contains(rect.center) &&
        tester.hitTestOnBinding(rect.center).path.any((entry) => identical(entry.target, object)),
      'effectiveTargetVerified': false});
  }
  return rows;
}

Future<void> _history(WidgetTester tester, String label) async {
  final button = find.byTooltip(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);
  final results = <Map<String, Object?>>[];
  final files = [for (final width in [320, 360])
    for (final kind in ['question', 'branch-within', 'branch-between'])
      for (final ending in ['before.png', 'after.png', 'after.pdf']) 'candidate-drag-$width-$kind-$ending'];
  setUpAll(() {
    Directory(_out).createSync(recursive: true);
    File('$_out/candidate-reorder-manifest.json').writeAsStringSync(jsonEncode({
      'files': files, 'results': results, 'expectedCases': 6,
      'completedCases': results.length, 'allCasesPassed': results.length == 6,
      'manualVisualReview': false,
      'surface': 'injected canonical candidate only; production stays OFF',
      'capturePixelRatio': 3,
    }));
  });
  for (final width in [320.0, 360.0]) {
    for (final kind in ['question', 'branch-within', 'branch-between']) {
      testWidgets('canonical candidate $kind native48 drag, history and actual live-plan PDF at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final failures = <FlutterErrorDetails>[];
        final originalErrorHandler = FlutterError.onError!;
        FlutterError.onError = (details) {
          failures.add(details);
          originalErrorHandler(details);
        };
        addTearDown(() => FlutterError.onError = originalErrorHandler);
        void noFrameworkError(String phase) => expect(tester.takeException(), isNull,
          reason: '$phase: ${failures.map((details) => details.toString()).join("\n")}');
        final controller = _Observed(document: _document());
        addTearDown(controller.dispose);
        await tester.pumpWidget(RepaintBoundary(key: const ValueKey('reorder-screen'),
          child: MaterialApp(debugShowCheckedModeBanner: false, locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate], home: ChangeNotifierProvider<ExamWizardController>.value(
            value: controller, child: ExamPreviewScreen(onBackToQuestions: () {},
              enableSeparateEditorCandidate: true,
              canonicalLayoutResolver: ({required ExamDocument document, required DocumentIR sourceIr}) =>
                CanonicalLayoutService.resolve(document: document, sourceIr: sourceIr),
              canonicalPreviewAssetLoader: ({required LayoutDocument layout, required ExamDocument document}) =>
                CanonicalLayoutPreviewAssets.load(layout: layout, document: document))))));
        for (var i = 0; i < 500 && (controller.plan == null ||
            find.byType(CanonicalLayoutPreviewPage).evaluate().isEmpty); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        await tester.pumpAndSettle();
        await _history(tester, 'ملاءمة الورقة للشاشة');
        expect(controller.plan, isNotNull);
        expect(find.byType(CanonicalLayoutPreviewPage), findsWidgets);
        expect(identical(controller.plan!.layout.source, controller.documentIr), isTrue);
        final unchangedPlan = controller.plan!.layout;
        final reorderButton = find.byKey(const ValueKey<String>('canonical-action-reorder'));
        await tester.ensureVisible(reorderButton);
        await tester.tap(reorderButton);
        await tester.pumpAndSettle();
        expect(controller.plan!.layout, same(unchangedPlan));
        final original = jsonEncode(controller.document.toMap());
        final beforePlan = controller.plan!.layout;
        final base = 'candidate-drag-${width.toInt()}-$kind';
        Directory(_out).createSync(recursive: true);
        final beforeTargets = _touchInventory(tester);
        expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage),
          matching: find.byType(EditableText)), findsNothing);
        final handles = find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('canonical-drag-'));
        expect(handles, findsNWidgets(5));
        final rects = [for (final element in handles.evaluate())
          tester.getRect(find.byElementPredicate((e) => identical(e, element)))];
        final viewport = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].width, 48);
          expect(rects[i].height, 48);
          // Rect.contains(its bottomRight) is FALSE by definition (exclusive
          // right/bottom). A48dp handle flush with the screen is nevertheless
          // fully contained. Compare rectangle edges, with ZERO tolerance.
          expect(rects[i].left, greaterThanOrEqualTo(viewport.left));
          expect(rects[i].top, greaterThanOrEqualTo(viewport.top));
          expect(rects[i].right, lessThanOrEqualTo(viewport.right));
          expect(rects[i].bottom, lessThanOrEqualTo(viewport.bottom));
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse);
          }
        }
        await _capture(tester, '$_out/$base-before.png');

        final sourceId = kind == 'question' ? 'qb' : kind == 'branch-within' ? 'bb' : 'ba';
        final targetId = kind == 'question' ? 'qa' : kind == 'branch-within' ? 'ba' : 'bc';
        final source = find.byKey(ValueKey<String>('canonical-drag-$sourceId'));
        final destination = find.byKey(ValueKey<String>('canonical-drop-$targetId'));
        expect(source, findsOneWidget);
        expect(destination, findsOneWidget);
        // Start at the CORNER of the actual48dp control, outside the icon ink.
        // An enlarged rectangle with deferToChild would fail this real drag.
        final from = tester.getRect(source).topLeft + const Offset(1, 1);
        final to = _center(tester, destination);
        final gesture = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 650));
        for (var step = 1; step <= 10; step++) {
          await gesture.moveTo(Offset.lerp(from, to, step / 10)!);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        noFrameworkError('real drop');
        final expected = kind == 'question'
          ? ['QBETA', 'BGAMMA', 'QALPHA', 'BALPHA', 'BBETA']
          : kind == 'branch-within'
            ? ['QALPHA', 'BBETA', 'BALPHA', 'QBETA', 'BGAMMA']
            : ['QALPHA', 'BGAMMA', 'BBETA', 'QBETA', 'BALPHA'];
        if (kind == 'question') {
          expect(controller.questions.map((q) => q.id), ['qb', 'qa']);
        } else if (kind == 'branch-within') {
          expect(controller.questions.first.branches.map((b) => b.id), ['bb', 'ba']);
        } else {
          expect(controller.questions.first.branches.map((b) => b.id), ['ba', 'bb']);
          expect(controller.questions.last.branches.single.id, 'bc');
          expect(controller.questions.first.branches.first.content.statement, 'BGAMMA');
          expect(controller.questions.first.branches.first.marks, 3);
          expect(controller.questions.last.branches.single.content.statement, 'BALPHA');
          expect(controller.questions.last.branches.single.marks, 1);
        }
        final changed = jsonEncode(controller.document.toMap());
        expect(changed, isNot(original));
        expect(identical(controller.plan!.layout.source, controller.documentIr), isTrue);
        final live = controller.plan!.layout;
        expect(identical(beforePlan, live), isFalse);
        final bytes = await tester.runAsync(() => PdfExportService.buildDocumentPdfBytes(
          document: controller.document, layoutDocument: live));
        File('$_out/$base-after.pdf').writeAsBytesSync(bytes!);
        final emitted = <String>[];
        for (var page = 0; page < PdfContentProbe.pageCountOf(bytes); page++) {
          final probe = PdfContentProbe.fromBytes(bytes, pageIndex: page);
          final words = probe.words;
          for (final line in probe.lines.where((line) => line.words.any((word) =>
              word.text == 'QALPHA' || word.text == 'QBETA'))) {
            final arabic = line.words.where((word) => const {'نص', 'مختلط'}.contains(word.text) ||
              const {'نص', 'مختلط'}.contains(String.fromCharCodes(word.text.runes.toList().reversed))).toList()
              ..sort((a, b) => a.x.compareTo(b.x));
            expect(arabic, hasLength(2));
            expect(arabic.first.x + arabic.first.advanceWidth, lessThan(arabic.last.x),
              reason: 'Actual Arabic word advances in the LTR title may not overlap.');
            final marks = line.words.where((word) => word.text.startsWith('(')).toList()
              ..sort((a, b) => a.x.compareTo(b.x));
            expect(marks, isNotEmpty);
            expect(arabic.last.x + arabic.last.advanceWidth, lessThan(marks.first.x),
              reason: 'The Arabic BiDi island must not consume the Latin marks interval.');
          }
          for (final word in words.where((word) => _tokens.contains(word.text.trim()))) {
            emitted.add(word.text.trim());
            final planned = live.pages[page].blocks.expand((block) => block.allLines)
              .expand((line) => line.runs).expand((run) => run.words)
              .singleWhere((candidate) => candidate.text.trim() == word.text.trim());
            // PdfNum serializes decimal coordinates; 1e-4pt bounds accumulated
            // five-decimal operator rounding, not a paper-layout allowance.
            expect(word.x, closeTo(planned.x, 1e-4));
          }
        }
        expect(emitted, expected, reason: 'Inspect actual PDF words, not source order alone.');
        final afterTargets = _touchInventory(tester);
        await _capture(tester, '$_out/$base-after.png');
        await _history(tester, 'تراجع');
        noFrameworkError('undo');
        expect(jsonEncode(controller.document.toMap()), original);
        await _history(tester, 'إعادة');
        noFrameworkError('redo');
        expect(jsonEncode(controller.document.toMap()), changed);
        expect(tester.takeException(), isNull);
        results.add({'widthDp': width, 'kind': kind,
          'touchInventoryScope': 'Native candidate reorder handles measured; corner gesture, containment and pairwise non-overlap tested. Other primitives are diagnostic only, not general48dp acceptance.',
          'nativeHandleRectsDp': [for (final r in rects) [r.left,r.top,r.right,r.bottom]],
          'realCornerDrag': true,
          'beforeScreenshot': '$base-before.png', 'afterScreenshot': '$base-after.png',
          'beforeTargets': beforeTargets, 'afterTargets': afterTargets,
          'headerModel': controller.document.header.toMap(), 'realLongPressDrag': true,
          'from': [from.dx, from.dy], 'to': [to.dx, to.dy],
          'modelBefore': jsonDecode(original), 'modelAfter': jsonDecode(changed),
          'pdfTokens': emitted, 'undoRestoresOriginal': true, 'redoRestoresChanged': true,
          'pdfUsesObservedLivePlan': true, 'pdfCoordinatesVerified': true});
        File('$_out/candidate-reorder-manifest.json').writeAsStringSync(jsonEncode({
          'files': files, 'results': results, 'expectedCases': 6,
      'completedCases': results.length, 'allCasesPassed': results.length == 6,
      'manualVisualReview': false,
          'surface': 'injected canonical candidate only; production stays OFF',
      'capturePixelRatio': 3,
        }));
      });
    }
  }
}
