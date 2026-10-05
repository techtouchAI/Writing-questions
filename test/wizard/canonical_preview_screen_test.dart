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

      await tester.pumpWidget(_screen(controller));
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
    },
  );

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
    await _pumpUntilCanonicalPage(tester);

    expect(find.byType(CanonicalLayoutPreviewPage), findsOneWidget);
    expect(assetAttempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale layout completion cannot replace the newer document page',
      (tester) async {
    final initial = _document(statement: 'Old $_hitMarker source');
    final controller = ExamWizardController(document: initial);
    addTearDown(controller.dispose);
    final oldLayout = await CanonicalLayoutService.resolve(document: initial);
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
  });

  testWidgets('disposing while canonical layout is pending discards late result',
      (tester) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);
    final pendingLayout = Completer<LayoutDocument>();
    final resolutionStarted = Completer<void>();
    final layout = await CanonicalLayoutService.resolve(document: document);

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
  });
}
