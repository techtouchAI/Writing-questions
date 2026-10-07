import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_interaction.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

const String _hitMarker = 'CANONICALMARKER';

ExamDocument _document({
  String subject = 'English',
  String statement = 'Tap the $_hitMarker in this question.',
  String body = 'The body stays on the canonical page geometry.',
}) =>
    ExamDocument(
      name: 'Canonical preview interaction',
      header: ExamHeaderModel.initial(subject: subject),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'canonical-hit-question',
          questionNumber: 1,
          statement: statement,
          body: body,
        ),
      ],
    );

List<({LayoutLine line, LayoutRun run})> _runs(LayoutPage page) =>
    <({LayoutLine line, LayoutRun run})>[
      for (final block in page.blocks)
        for (final line in block.allLines)
          for (final run in line.runs) (line: line, run: run),
    ];

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 40,
}) async {
  for (var attempt = 0; attempt < maxFrames && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilCanonicalPage(WidgetTester tester) => _pumpUntil(
      tester,
      () => find.byType(CanonicalLayoutPreviewPage).evaluate().isNotEmpty,
    );

Widget _screen(ExamWizardController controller, {
  CanonicalPreviewLayoutResolver? resolver,
  CanonicalPreviewAssetLoader? assetLoader,
}) =>
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(
          onBackToQuestions: () {},
          canonicalLayoutResolver: resolver,
          canonicalPreviewAssetLoader: assetLoader,
        ),
      ),
    );

/// Canonical surface with the production resolver/loader, injected
/// explicitly: the seam-free screen default is the interactive paper.
Widget _screenCanonical(ExamWizardController controller) => _screen(
      controller,
      resolver: ({
        required ExamDocument document,
        required DocumentIR sourceIr,
      }) =>
          CanonicalLayoutService.resolve(
        document: document,
        sourceIr: sourceIr,
      ),
      assetLoader: ({
        required LayoutDocument layout,
        required ExamDocument document,
      }) =>
          CanonicalLayoutPreviewAssets.load(
        layout: layout,
        document: document,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'screen tap follows RTL mixed-script geometry to its source offset on a later page',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const repeatedBody =
          'هذا نص عربي طويل يختبر انتقال الفقرة إلى الصفحة التالية مع بقاء '
          'القياس والهندسة والأبعاد متطابقة';
      final longBody = List<String>.filled(120, repeatedBody).join(' ');
      final document = ExamDocument(
        name: 'RTL mixed script and page boundary',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'first-question',
            questionNumber: 1,
            statement: 'تمهيد عربي English 123',
            body: longBody,
          ),
          QuestionModel(
            id: 'source-question',
            questionNumber: 2,
            statement: 'مصدر مختلط MixCase ٣١٢ ثم $_hitMarker وEnglish42',
            body: 'نص أخير للاختبار.',
          ),
        ],
      );
      final controller = ExamWizardController(document: document);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_screenCanonical(controller));
      await _pumpUntilCanonicalPage(tester);

      final pageFinders = find.byType(CanonicalLayoutPreviewPage);
      expect(pageFinders, findsWidgets);
      final previewWidgets = pageFinders
          .evaluate()
          .map((element) => element.widget as CanonicalLayoutPreviewPage)
          .toList(growable: false);
      final layout = previewWidgets.first.layoutDocument;
      expect(layout.pageCount, greaterThan(1));
      expect(
        previewWidgets.every((preview) => identical(preview.layoutDocument, layout)),
        isTrue,
        reason: 'Every visible page must be painted from one current LayoutDocument.',
      );
      expect(
        previewWidgets.every((preview) =>
            identical(preview.page, layout.pages[preview.page.index])),
        isTrue,
        reason: 'The rendered page must be the page object owned by that document.',
      );
      expect(layout.direction.name, 'rtl');

      final target = <({LayoutPage page, LayoutLine line, LayoutRun run})>[
        for (final page in layout.pages)
          for (final entry in _runs(page))
            if (entry.run.text.contains(_hitMarker))
              (page: page, line: entry.line, run: entry.run),
      ].single;
      expect(target.page.index, greaterThan(0),
          reason: 'The source hit should exercise page ownership after a page break.');
      expect(target.run.sourceEndOffset, greaterThan(target.run.sourceStartOffset));
      final sourceStatement = document.questions
          .singleWhere((question) => question.id == 'source-question')
          .statement;
      expect(
        sourceStatement.substring(
          target.run.sourceStartOffset,
          target.run.sourceEndOffset,
        ),
        target.run.text,
        reason: 'The canonical run interval must address the original statement.',
      );
      expect(target.run.sourceOffsetMap, isNotNull);
      expect(target.run.direction.name, 'ltr',
          reason: 'The Latin run inside the RTL paragraph must keep its own direction.');

      final pageFinder = find.byKey(ValueKey<String>(
        'canonical-preview-page-${target.page.index}',
      ));
      await tester.ensureVisible(pageFinder);
      await tester.pump();
      final pageRect = tester.getRect(pageFinder);
      final transform = CanonicalPageTransform(
        screenLeft: pageRect.left,
        screenTop: pageRect.top,
        screenWidth: pageRect.width,
        screenHeight: pageRect.height,
        pageWidthPt: target.page.pageSize.width,
        pageHeightPt: target.page.pageSize.height,
      );
      final pageXPt = target.run.x + target.run.width / 2;
      final pageYPt =
          target.line.baseline - target.run.baselineOffset + target.run.height / 2;
      final screenPoint = transform.screenPointFromPage(pageXPt, pageYPt);
      final pagePoint = transform.pagePointFromScreen(screenPoint.x, screenPoint.y);
      expect(pagePoint.x, closeTo(pageXPt, 0.02));
      expect(pagePoint.y, closeTo(pageYPt, 0.02));

      final expectedHit = CanonicalLayoutHitTester.hitTest(
        page: target.page,
        pageIndex: target.page.index,
        xPt: pagePoint.x,
        yPt: pagePoint.y,
      );
      expect(expectedHit, isNotNull);
      expect(expectedHit!.runId, target.run.id);
      expect(expectedHit.pageIndex, target.page.index);
      expect(expectedHit.semanticNodeId, target.run.semanticNodeId);
      expect(expectedHit.sourceStartOffset, target.run.sourceStartOffset);
      expect(expectedHit.sourceEndOffset, target.run.sourceEndOffset);
      expect(expectedHit.sourceOffset, isNotNull);
      final markerStart = sourceStatement.indexOf(_hitMarker);
      expect(
        expectedHit.sourceOffset,
        inInclusiveRange(markerStart, markerStart + _hitMarker.length),
        reason: 'The page-space hit must resolve to this marker in source text.',
      );

      await tester.tapAt(Offset(screenPoint.x, screenPoint.y));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fieldFinder = find.descendant(
        of: find.byKey(const ValueKey<String>('statement-source-question')),
        matching: find.byType(TextField),
      );
      expect(fieldFinder, findsOneWidget,
          reason: 'The page hit must activate the owning question statement.');
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.controller, isNotNull);
      expect(field.controller!.selection.isCollapsed, isTrue);
      expect(
        field.controller!.selection.extentOffset,
        expectedHit.sourceOffset,
        reason: 'The caret must use the source offset from the canonical hit.',
      );
      expect(field.style?.color, Colors.transparent,
          reason: 'The IME field must not paint duplicate text over canonical glyphs.');
      expect(tester.takeException(), isNull);
      // Round-3 orphan-hygiene experiment: detach test 1's tree so no
      // in-flight screen work (timers, post-frames, IME, image streams)
      // can wedge the binding for the tests that follow in this isolate.
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint('[diag] canonical-01: done');
    },
  );

  testWidgets(
    'canonical page tap maps RTL mixed floating text on its owned page to source offsets',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const bodyPart =
          'هذا نص عربي طويل يختبر حدود الصفحة والانتقال بين الصفحات مع سلامة '
          'الهندسة ومواقع الكلمات في المعاينة القانونية.';
      const label = 'ملاحظة MixedCase42 — نهاية';
      final document = ExamDocument(
        name: 'RTL floating text hit',
        header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
        floatingElements: <FloatingElement>[
          FloatingElement(
            id: 'rtl-floating-note',
            type: FloatingElementType.shape,
            shape: FloatingShapeType.textBox,
            dx: 110,
            dy: 170,
            pageIndex: 1,
            width: 300,
            height: 96,
            label: label,
            framed: true,
          ),
        ],
        questions: <QuestionModel>[
          QuestionModel(
            id: 'long-rtl-question',
            questionNumber: 1,
            statement: 'تمهيد عربي English 123',
            body: List<String>.filled(72, bodyPart).join(' '),
          ),
        ],
      );
      final controller = ExamWizardController(document: document);
      addTearDown(controller.dispose);
      debugPrint('[diag] canonical-02: resolving');
      final layout = await tester.runAsync(
        () => CanonicalLayoutService.resolve(
          document: document,
          sourceIr: controller.documentIr,
        ),
      );
      debugPrint('[diag] canonical-02: resolved pages=${layout?.pageCount}');
      expect(layout, isNotNull);
      final canonical = layout!;
      // This document measures exactly 2 pages in CI; the test needs the
      // later owned page (pages[1]), not three pages.
      expect(canonical.pageCount, greaterThan(1));
      expect(identical(canonical.source, controller.documentIr), isTrue);
      final page = canonical.pages[1];
      final placement = page.floatingElements.singleWhere(
        (candidate) => candidate.reference.id == 'rtl-floating-note',
      );
      expect(placement.pageIndex, 1);
      final target = <({LayoutLine line, LayoutRun run})>[
        for (final line in placement.labelLines)
          for (final run in line.runs)
            if (run.text.contains('MixedCase42')) (line: line, run: run),
      ].single;
      expect(target.run.direction.name, 'ltr');
      expect(
        label.substring(
          target.run.sourceStartOffset,
          target.run.sourceEndOffset,
        ),
        target.run.text,
      );

      final pageXPt = target.run.x + target.run.width / 2;
      final pageYPt = target.line.baseline -
          target.run.baselineOffset +
          target.run.height / 2;
      final events = <CanonicalPagePointerEvent>[];
      final assets = CanonicalLayoutPreviewAssets();
      addTearDown(assets.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CanonicalLayoutPreviewPage(
              key: const ValueKey<String>('floating-page-hit'),
              layoutDocument: canonical,
              page: page,
              document: document,
              assets: assets,
              onTap: events.add,
            ),
          ),
        ),
      );

      final pageRect = tester.getRect(
        find.byKey(const ValueKey<String>('floating-page-hit')),
      );
      final transform = CanonicalPageTransform(
        screenLeft: pageRect.left,
        screenTop: pageRect.top,
        screenWidth: pageRect.width,
        screenHeight: pageRect.height,
        pageWidthPt: page.pageSize.width,
        pageHeightPt: page.pageSize.height,
      );
      final screen = transform.screenPointFromPage(pageXPt, pageYPt);
      final roundTrip = transform.pagePointFromScreen(screen.x, screen.y);
      expect(roundTrip.x, closeTo(pageXPt, 0.02));
      expect(roundTrip.y, closeTo(pageYPt, 0.02));

      await tester.tapAt(Offset(screen.x, screen.y));
      await tester.pump();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.pagePositionPt.dx, closeTo(pageXPt, 0.02));
      expect(event.pagePositionPt.dy, closeTo(pageYPt, 0.02));
      final hit = event.hit;
      expect(hit, isNotNull);
      expect(hit!.pageIndex, 1);
      expect(hit.floatingElementId, 'rtl-floating-note');
      expect(hit.runId, target.run.id);
      expect(hit.semanticNodeId, target.run.semanticNodeId);
      expect(hit.sourceStartOffset, target.run.sourceStartOffset);
      expect(hit.sourceEndOffset, target.run.sourceEndOffset);
      expect(hit.sourceOffset, isNotNull);
      expect(
        hit.sourceOffset,
        inInclusiveRange(
          label.indexOf('MixedCase42'),
          label.indexOf('MixedCase42') + 'MixedCase42'.length,
        ),
      );
      expect(tester.takeException(), isNull);
      debugPrint('[diag] canonical-02: done');
    },
        // Fail-fast bound (tightening, not loosening): healthy work here is
        // seconds; 120s bounds only hangs, 5x faster than the 600s default.
        timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('canonical floating drag resolves and changes the destination page',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bodyPart =
        'هذا نص طويل يحافظ على حدود الصفحات ويضمن وجود صفحة هدف مستقلة '
        'لتحريك العنصر العائم إليها.';
    final document = ExamDocument(
      name: 'RTL floating page drag',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'drag-to-later-page',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 120,
          dy: 220,
          pageIndex: 1,
          width: 90,
          height: 80,
        ),
      ],
      questions: <QuestionModel>[
        QuestionModel(
          id: 'drag-pagination-question',
          questionNumber: 1,
          statement: 'ابدأ من RTL ثم English 123',
          // The drag target is pages[2]: 72 parts measure only 2 pages in
          // CI, so the document needs headroom for a third page.
          body: List<String>.filled(200, bodyPart).join(' '),
        ),
      ],
    );
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_screenCanonical(controller));
    await _pumpUntilCanonicalPage(tester);
    // The page implies layout+assets are both set; global settle waits for
    // unrelated quiescence the test never needs.
    debugPrint('[diag] canonical-03: page found');

    final preview = tester.widget<CanonicalLayoutPreviewPage>(
      find.byKey(const ValueKey<String>('canonical-preview-page-1')),
    );
    final layout = preview.layoutDocument;
    expect(layout.pageCount, greaterThan(2));
    expect(identical(layout.source, controller.documentIr), isTrue);
    final sourcePage = layout.pages[1];
    final targetPage = layout.pages[2];
    final float = sourcePage.floatingElements.singleWhere(
      (placement) => placement.reference.id == 'drag-to-later-page',
    );
    final sourcePageRect = tester.getRect(
      find.byKey(const ValueKey<String>('canonical-preview-page-1')),
    );
    final targetPageRect = tester.getRect(
      find.byKey(const ValueKey<String>('canonical-preview-page-2')),
    );
    final sourceTransform = CanonicalPageTransform(
      screenLeft: sourcePageRect.left,
      screenTop: sourcePageRect.top,
      screenWidth: sourcePageRect.width,
      screenHeight: sourcePageRect.height,
      pageWidthPt: sourcePage.pageSize.width,
      pageHeightPt: sourcePage.pageSize.height,
    );
    final targetTransform = CanonicalPageTransform(
      screenLeft: targetPageRect.left,
      screenTop: targetPageRect.top,
      screenWidth: targetPageRect.width,
      screenHeight: targetPageRect.height,
      pageWidthPt: targetPage.pageSize.width,
      pageHeightPt: targetPage.pageSize.height,
    );
    final start = sourceTransform.screenPointFromPage(
      float.rect.left + float.rect.width / 2,
      float.rect.top + float.rect.height / 2,
    );
    final destination = targetTransform.screenPointFromPage(
      targetPage.pageSize.width / 2,
      targetPage.pageSize.height / 2,
    );

    final gesture = await tester.startGesture(Offset(start.x, start.y));
    await gesture.moveTo(Offset(destination.x, destination.y));
    debugPrint('[diag] canonical-03: moved');
    await tester.pump(const Duration(milliseconds: 20));
    debugPrint('[diag] canonical-03: pumped');
    await gesture.up();
    debugPrint('[diag] canonical-03: up');
    // The drop updates the model synchronously; wait for the model's own
    // condition, not global quiescence.
    await _pumpUntil(
      tester,
      () => controller.document.floatingElements.single.pageIndex == 2,
    );
    debugPrint('[diag] canonical-03: dropped');

    expect(
      controller.document.floatingElements.single.pageIndex,
      2,
      reason: 'The canonical pointer must resolve the later page under the drag.',
    );
    expect(tester.takeException(), isNull);
    debugPrint('[diag] canonical-03: done');
  },
      // Fail-fast bound (tightening, not loosening): healthy work here is
      // seconds; 120s bounds only hangs, 5x faster than the 600s default.
      timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('canonical preparation failure shows a retry that can succeed',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);
    var assetAttempts = 0;

    await tester.pumpWidget(
      _screen(
        controller,
        resolver: ({
          required ExamDocument document,
          required DocumentIR sourceIr,
        }) => CanonicalLayoutService.resolve(
          document: document,
          sourceIr: sourceIr,
        ),
        assetLoader: ({
          required LayoutDocument layout,
          required ExamDocument document,
        }) async {
          assetAttempts++;
          if (assetAttempts == 1) throw StateError('injected asset failure');
          return CanonicalLayoutPreviewAssets();
        },
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('إعادة المحاولة').evaluate().isNotEmpty,
    );

    expect(find.byType(CanonicalLayoutPreviewPage), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(assetAttempts, 1);

    await tester.tap(find.text('إعادة المحاولة'));
    debugPrint('[diag] canonical-04: tapped retry');
    await _pumpUntilCanonicalPage(tester);
    debugPrint('[diag] canonical-04: page found');

    expect(find.byType(CanonicalLayoutPreviewPage), findsOneWidget);
    expect(assetAttempts, 2);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] canonical-04: done');
  },
      // Fail-fast bound (tightening, not loosening): healthy work here is
      // seconds; 120s bounds only hangs, 5x faster than the 600s default.
      timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('stale layout completion cannot replace the newer document page',
      (tester) async {
    final initial = _document(statement: 'Old $_hitMarker source');
    final controller = ExamWizardController(document: initial);
    addTearDown(controller.dispose);
    final oldLayout = await CanonicalLayoutService.resolve(
      document: initial,
      sourceIr: controller.documentIr,
    );
    debugPrint('[diag] canonical-05: pre-resolved');
    final oldLayoutResult = Completer<LayoutDocument>();
    final firstResolutionStarted = Completer<void>();

    await tester.pumpWidget(
      _screen(
        controller,
        resolver: ({
          required ExamDocument document,
          required DocumentIR sourceIr,
        }) {
          if (identical(document, initial)) {
            if (!firstResolutionStarted.isCompleted) {
              firstResolutionStarted.complete();
            }
            return oldLayoutResult.future;
          }
          return CanonicalLayoutService.resolve(
            document: document,
            sourceIr: sourceIr,
          );
        },
        assetLoader: ({
          required LayoutDocument layout,
          required ExamDocument document,
        }) async => CanonicalLayoutPreviewAssets(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(firstResolutionStarted.isCompleted, isTrue);

    controller.updateQuestionStatement(0, 'New $_hitMarker document version');
    await _pumpUntilCanonicalPage(tester);

    final currentPreview = tester.widget<CanonicalLayoutPreviewPage>(
      find.byType(CanonicalLayoutPreviewPage).first,
    );
    expect(
      currentPreview.layoutDocument.source.questionById('canonical-hit-question')!
          .title.statement.legacyText,
      contains('New $_hitMarker'),
    );
    final currentLayout = currentPreview.layoutDocument;

    oldLayoutResult.complete(oldLayout);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final afterStaleCompletion = tester.widget<CanonicalLayoutPreviewPage>(
      find.byType(CanonicalLayoutPreviewPage).first,
    );
    expect(identical(afterStaleCompletion.layoutDocument, currentLayout), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] canonical-05: done');
  },
      // Fail-fast bound (tightening, not loosening): healthy work here is
      // seconds; 120s bounds only hangs, 5x faster than the 600s default.
      timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('disposing while canonical layout is pending discards late result',
      (tester) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    final pendingLayout = Completer<LayoutDocument>();
    final resolutionStarted = Completer<void>();
    final layout = await CanonicalLayoutService.resolve(
      document: document,
      sourceIr: controller.documentIr,
    );
    debugPrint('[diag] canonical-06: pre-resolved');

    await tester.pumpWidget(
      _screen(
        controller,
        resolver: ({
          required ExamDocument document,
          required DocumentIR sourceIr,
        }) {
          if (!resolutionStarted.isCompleted) resolutionStarted.complete();
          return pendingLayout.future;
        },
        assetLoader: ({
          required LayoutDocument layout,
          required ExamDocument document,
        }) async => CanonicalLayoutPreviewAssets(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(resolutionStarted.isCompleted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    pendingLayout.complete(layout);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CanonicalLayoutPreviewPage), findsNothing);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] canonical-06: done');
  },
      // Fail-fast bound (tightening, not loosening): healthy work here is
      // seconds; 120s bounds only hangs, 5x faster than the 600s default.
      timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
    'seam-free screen shows the interactive paper, not the canonical surface',
    (tester) async {
      final document = _document();
      final controller = ExamWizardController(document: document);
      addTearDown(() {
        debugPrint('[diag] canonical-07: disposing');
        controller.dispose();
        debugPrint('[diag] canonical-07: disposed');
      });

      await tester.pumpWidget(_screen(controller));
      debugPrint('[diag] canonical-07: pumped widget');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('[diag] canonical-07: pumped frames');

      // The production default (no injected seams) is the interactive
      // paper: no canonical page is ever built, and the paper renders
      // the question content.
      expect(find.byType(CanonicalLayoutPreviewPage), findsNothing);
      expect(find.textContaining(_hitMarker), findsWidgets);
      expect(tester.takeException(), isNull);
      debugPrint('[diag] canonical-07: done');
    },
        // Fail-fast bound (tightening, not loosening): healthy work here is
        // seconds; 120s bounds only hangs, 5x faster than the 600s default.
        timeout: const Timeout(Duration(seconds: 120)));
}
