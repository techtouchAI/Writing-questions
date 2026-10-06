// Hang repro for the canonical preview suite: every test in
// `canonical_preview_screen_test.dart` except the first hits the 10-minute
// runner timeout (5 × 600s dominate each CI cycle), and a bare timeout names
// no stage. These two tests mirror the hanging bodies (direct page pump with
// a huge document; dispose while a layout is pending) with a [diag] print
// after every await — prints flush live, so even a timed-out run pinpoints
// the last completed stage — and the `runAsync` resolve carries the outer
// `.timeout` that the visual fixture proved fires (inner-`runAsync`
// `.timeout` never does: shape-1 pends 120s+ untouched by its 30s guard).
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

ExamDocument _hugeDocument() {
  const bodyPart =
      'هذا نص عربي طويل يختبر حدود الصفحة والانتقال بين الصفحات مع سلامة '
      'الهندسة ومواقع الكلمات في المعاينة القانونية.';
  return ExamDocument(
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
        label: 'ملاحظة MixedCase42 — نهاية',
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
}

ExamDocument _smallDocument() => ExamDocument(
      name: 'Canonical preview interaction',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'canonical-hit-question',
          questionNumber: 1,
          statement: 'Tap the CANONICALMARKER in this question.',
          body: 'The body stays on the canonical page geometry.',
        ),
      ],
    );

Widget _screen(
  ExamWizardController controller, {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repro: direct page pump with huge doc completes every stage',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = _hugeDocument();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    debugPrint('[diag] repro-tap: resolving');
    // The harness types the awaited chain nullable; `resolve` itself is
    // non-null, so `!` fails loudly on a harness artifact, never silently.
    final layout = (await tester
        .runAsync(
          () => CanonicalLayoutService.resolve(
            document: document,
            sourceIr: controller.documentIr,
          ),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw StateError(
            'HANG: CanonicalLayoutService.resolve did not complete in 60s',
          ),
        ))!;
    debugPrint('[diag] repro-tap: resolved pages=${layout.pageCount}');
    // This document measures exactly 2 pages in CI; the repro needs a
    // later owned page (pages[1]), not three pages.
    expect(layout.pageCount, greaterThan(1));
    final page = layout.pages[1];

    debugPrint('[diag] repro-tap: pumping page');
    final events = <CanonicalPagePointerEvent>[];
    final assets = CanonicalLayoutPreviewAssets();
    addTearDown(assets.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CanonicalLayoutPreviewPage(
            key: const ValueKey<String>('floating-page-hit'),
            layoutDocument: layout,
            page: page,
            document: document,
            assets: assets,
            onTap: events.add,
          ),
        ),
      ),
    );
    debugPrint('[diag] repro-tap: pumped');

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
    final screen = transform.screenPointFromPage(
      page.pageSize.width / 2,
      page.pageSize.height / 2,
    );
    debugPrint('[diag] repro-tap: tapping');
    await tester.tapAt(Offset(screen.x, screen.y));
    await tester.pump();
    debugPrint('[diag] repro-tap: tapped events=${events.length}');
    expect(events.length, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('repro: dispose with pending layout completes every stage',
      (tester) async {
    final document = _smallDocument();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    final pendingLayout = Completer<LayoutDocument>();
    final resolutionStarted = Completer<void>();
    debugPrint('[diag] repro-dispose: resolving');
    // The harness types the awaited chain nullable; `resolve` itself is
    // non-null, so `!` fails loudly on a harness artifact, never silently.
    final layout = (await tester
        .runAsync(
          () => CanonicalLayoutService.resolve(
            document: document,
            sourceIr: controller.documentIr,
          ),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw StateError(
            'HANG: CanonicalLayoutService.resolve did not complete in 60s',
          ),
        ))!;
    debugPrint('[diag] repro-dispose: resolved pages=${layout.pageCount}');

    debugPrint('[diag] repro-dispose: pumping screen');
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
        }) async =>
            CanonicalLayoutPreviewAssets(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint('[diag] repro-dispose: pumped '
        'started=${resolutionStarted.isCompleted}');
    expect(resolutionStarted.isCompleted, isTrue);

    debugPrint('[diag] repro-dispose: disposing screen');
    await tester.pumpWidget(const SizedBox.shrink());
    pendingLayout.complete(layout);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint('[diag] repro-dispose: disposed');

    expect(find.byType(CanonicalLayoutPreviewPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
