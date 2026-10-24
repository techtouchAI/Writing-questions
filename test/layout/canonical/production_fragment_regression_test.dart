// Regression reproductions on the production paper, not the injected painter.
// Run: flutter test test/layout/canonical/production_fragment_regression_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

const _output = 'build/production_fragment_repro';

String _longText() => List<String>.generate(
      110,
      (i) => 'W${i.toString().padLeft(3, '0')} '
          'هذا نص عربي طويل لفحص نهاية الصفحة ومقاطع السؤال وحدود القص.',
    ).join(' ');

ExamDocument _document({
  bool long = false,
  bool frame = false,
  bool divider = false,
  List<FloatingElement>? attachments,
}) =>
    ExamDocument(
      name: 'Production fragment regression',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'repro-q',
          questionNumber: 1,
          statement: 'اقرأ السؤال وأجب عن الفرع التالي',
          showFrame: frame,
          body: long ? _longText() : '',
          dividerAfter: divider ? const PaperDivider() : null,
          attachments: attachments,
          branches: <BranchModel>[
            BranchModel(
              id: 'repro-b',
              content: BranchContent(statement: 'نهاية السؤال ZEND'),
            ),
          ],
        ),
      ],
    );

Future<LayoutDocument> _layout(ExamDocument document, {bool unsplit = false}) =>
    CanonicalLayoutService.resolve(
      document: document,
      // Reference measurement only, never a production page-size change.
      pageSize: unsplit
          ? const LayoutSize(width: 210 * 72 / 25.4, height: 20000)
          : null,
    );

Future<ExamWizardController> _pump(
  WidgetTester tester,
  ExamDocument document,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<ExamWizardController>.value(
      value: controller,
      // Deliberately no resolver AND no asset-loader injection: this is the
      // same editable paper that the released application displays.
      child: ExamPreviewScreen(onBackToQuestions: () {}),
    ),
  ));
  await tester.pumpAndSettle();
  return controller;
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void _record(String name, Object data) {
  final directory = Directory(_output)..createSync(recursive: true);
  File('${directory.path}/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}

Future<void> _capture(WidgetTester tester, String name, int pageIndex) async {
  final page = _key('a4-page-$pageIndex');
  await tester.ensureVisible(page);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: page, matching: find.byType(RepaintBoundary)).first,
  );
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  try {
    final png = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    Directory(_output).createSync(recursive: true);
    File('$_output/$name.png').writeAsBytesSync(png.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FlutterTextMetrics.ensureFontsLoaded);

  testWidgets('R1 selecting a question must not move its printed branch',
      (tester) async {
    final controller = await _pump(tester, _document());
    final branch = _key('branch-target-repro-b');
    final before = tester.getRect(branch);
    final beforeDocument = controller.document;
    await _capture(tester, 'r1-before-selection', 0);
    await tester.tap(_key('statement-repro-q'));
    await tester.pumpAndSettle();
    final after = tester.getRect(branch);
    await _capture(tester, 'r1-after-selection', 0);
    _record('r1-selection', <String, Object>{
      'branchTopBeforePx': before.top,
      'branchTopAfterPx': after.top,
      'shiftPx': after.top - before.top,
      'sameDocument': identical(beforeDocument, controller.document),
    });
    expect(identical(beforeDocument, controller.document), isTrue);
    expect(after.top, closeTo(before.top, 0.75),
        reason: 'Selection inserts editor-only fields/buttons into printed flow.');
  });

  test('R2 a split question must retain its final divider exactly once', () async {
    final document = _document(long: true, divider: true);
    final layout = await _layout(document);
    final reference = await _layout(document, unsplit: true);
    final plan = CanonicalPagePlan.fromLayout(layout);
    expect(plan.fragmentsOfQuestion('repro-q').length, greaterThan(1));
    final referenceRules = reference.allBlocks
        .where((b) => b.kind == LayoutBlockKind.divider)
        .map((b) => b.id)
        .toList();
    final splitRules = layout.allBlocks
        .where((b) => b.kind == LayoutBlockKind.divider)
        .map((b) => b.id)
        .toList();
    _record('r2-divider', <String, Object>{
      'unsplitDividerIds': referenceRules,
      'splitDividerIds': splitRules,
      'pageCount': layout.pageCount,
    });
    expect(referenceRules, isNotEmpty);
    expect(splitRules, referenceRules,
        reason: 'Line-only slicing drops non-text content after the final line.');
  });

  test('R3 framed fragments must cover the full original block height', () async {
    final document = _document(long: true, frame: true);
    final layout = await _layout(document);
    final reference = await _layout(document, unsplit: true);
    final original = reference.allBlocks.singleWhere(
      (b) => b.kind == LayoutBlockKind.question && b.semanticNodeId == 'repro-q',
    );
    final fragments = CanonicalPagePlan.fromLayout(layout)
        .fragmentsOfQuestion('repro-q');
    expect(fragments.length, greaterThan(1));
    final coveredEnd = fragments.last.sourceTopPt + fragments.last.heightPt;
    _record('r3-frame', <String, Object>{
      'originalHeightPt': original.rect.height,
      'coveredEndPt': coveredEnd,
      'firstSourceTopPt': fragments.first.sourceTopPt,
      'missingHeightPt': original.rect.height - coveredEnd,
    });
    expect(fragments.first.sourceTopPt, closeTo(0, 0.01));
    expect(coveredEnd, closeTo(original.rect.height, 0.01),
        reason: 'Source windows must include the original frame padding.');
  });

  testWidgets('R4 long production paper contains its final branch within a slice',
      (tester) async {
    final controller = await _pump(tester, _document(long: true, frame: true));
    final plan = CanonicalPagePlan.fromLayout(await _layout(controller.document));
    final fragments = plan.fragmentsOfQuestion('repro-q');
    expect(fragments.length, greaterThan(1));
    final last = fragments.last;
    final suffix = '/slice${last.fragmentIndex}';
    final sliceFinder = _key('page-slice-repro-q$suffix');
    final slice = tester.getRect(sliceFinder);
    final fieldFinder = find.descendant(
      of: sliceFinder,
      matching: find.byWidgetPredicate((widget) =>
          widget is PaperField && widget.controller.text.contains('ZEND')),
    );
    expect(fieldFinder, findsOneWidget);
    final field = tester.getRect(fieldFinder);
    for (final fragment in fragments) {
      await _capture(tester, 'r4-page-${fragment.pageIndex}', fragment.pageIndex);
    }
    final pdf = await tester.runAsync(() =>
        PdfExportService.buildDocumentPdfBytes(
          document: controller.document,
          layoutDocument: plan.layout,
        ));
    File('$_output/r4-same-layout.pdf').writeAsBytesSync(pdf!);
    _record('r4-last-branch', <String, Object>{
      'fragmentIndex': last.fragmentIndex,
      'sliceTopPx': slice.top,
      'sliceBottomPx': slice.bottom,
      'branchTopPx': field.top,
      'branchBottomPx': field.bottom,
      'planHeightPt': last.heightPt,
    });
    expect(field.top, greaterThanOrEqualTo(slice.top - 0.75));
    expect(field.bottom, lessThanOrEqualTo(slice.bottom + 0.75),
        reason: 'The final branch exists in the widget tree but is clipped.');
  });

  test('R5 an owned float at a continuation offset must be visible on a page',
      () async {
    final document = _document(long: true, attachments: <FloatingElement>[
      FloatingElement(
        id: 'repro-float',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.rectangle,
        ownerQuestionId: 'repro-q',
        dx: 8,
        dy: 1500,
        width: 90,
        height: 80,
      ),
    ]);
    final layout = await _layout(document);
    final placement = layout.pages
        .expand((p) => p.floatingElements)
        .singleWhere((p) => p.reference.id == 'repro-float');
    final page = layout.pages[placement.pageIndex];
    _record('r5-owned-float', <String, Object>{
      'pageIndex': placement.pageIndex,
      'floatTopPt': placement.rect.top,
      'floatBottomPt': placement.rect.bottom,
      'pageHeightPt': page.pageSize.height,
      'dyPx': 1500,
    });
    expect(placement.deferredReason, isNull);
    expect(placement.rect.bottom, lessThanOrEqualTo(page.pageSize.height),
        reason: 'Question-local dy is added to its first fragment, not mapped '
            'to a continuation, so both preview and PDF lose the attachment.');
  });
}
