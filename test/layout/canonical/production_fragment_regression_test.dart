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
import 'package:writing_questions_app/views/widgets/smart_exam_toolbar.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

import '../../wizard/preview_test_gestures.dart';

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
  ExamDocument document, {
  Size size = const Size(1400, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  await tester.pumpWidget(RepaintBoundary(
    key: const ValueKey<String>('production-repro-screen'),
    child: MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        // No resolver/asset-loader injection: the released editable paper.
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
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

Future<void> _captureScreen(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('production-repro-screen'),
  );
  await _writeImage(tester, name, boundary);
}

Future<void> _writeImage(
  WidgetTester tester,
  String name,
  RenderRepaintBoundary boundary,
) async {
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

Future<void> _capture(WidgetTester tester, String name, int pageIndex) async {
  final page = _key('a4-page-$pageIndex');
  await tester.ensureVisible(page);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: page, matching: find.byType(RepaintBoundary)).first,
  );
  await _writeImage(tester, name, boundary);
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
    final optionalBody = _key('body-repro-q');
    final inPaperAddPoint = find.descendant(
      of: _key('a4-page-0'), matching: find.byTooltip('إضافة نقطة'),
    );
    _record('r1-selection', <String, Object>{
      'selectedEmptyBodyHeightPx': optionalBody.evaluate().isEmpty ? 0 : tester.getSize(optionalBody).height,
      'inPaperAddPointHeightPx': inPaperAddPoint.evaluate().isEmpty ? 0 : tester.getSize(inPaperAddPoint).height,

      'branchTopBeforePx': before.top,
      'branchTopAfterPx': after.top,
      'shiftPx': after.top - before.top,
      'sameDocument': identical(beforeDocument, controller.document),
    });
    expect(identical(beforeDocument, controller.document), isTrue);
    expect(after.top, closeTo(before.top, 1e-6),
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
    final reference = await _layout(controller.document, unsplit: true);
    final sourceBlock = reference.allBlocks.singleWhere((b) =>
      b.kind == LayoutBlockKind.question && b.semanticNodeId == 'repro-q');
    final sourceWidget = tester.getRect(_key('question-target-repro-q$suffix'));
    final branchWidget = tester.getRect(_key('branch-target-repro-b$suffix'));
    _record('r4-last-branch', <String, Object>{
      'sourceTopPt': last.sourceTopPt,
      'plannedSourceHeightPx': LayoutUnits.ptToPx(sourceBlock.rect.height),
      'actualSourceHeightPx': sourceWidget.height,
      'plannedSourceWidthPx': LayoutUnits.ptToPx(sourceBlock.rect.width),
      'actualSourceWidthPx': sourceWidget.width,
      'branchWidgetHeightPx': branchWidget.height,
      'branchFieldHeightPx': field.height,

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

  testWidgets('R6 continuation branch views keep one shared source',
      (tester) async {
    final controller = await _pump(tester, _document(long: true));
    final plan = CanonicalPagePlan.fromLayout(await _layout(controller.document));
    final fragments = plan.fragmentsOfQuestion('repro-q');
    expect(fragments.length, greaterThan(1));
    final fieldKeys = <String>[];
    final controllers = <TextEditingController>[];
    for (final fragment in fragments) {
      final suffix = fragment.isContinuation
          ? '/slice${fragment.fragmentIndex}'
          : '';
      final slice = _key('page-slice-repro-q$suffix');
      final fields = find.descendant(
        of: slice,
        matching: find.byWidgetPredicate((widget) =>
            widget is PaperField && widget.controller.text.contains('ZEND')),
      );
      expect(fields, findsOneWidget);
      final field = tester.widget<PaperField>(fields);
      fieldKeys.add(field.key.toString());
      controllers.add(field.controller);
    }
    _record('r6-branch-fields', <String, Object>{
      'keys': fieldKeys,
      'uniqueKeys': fieldKeys.toSet().length,
      'fragments': fragments.length,
      'sharedController': controllers.every((c) => identical(c, controllers.first)),
    });
    expect(controllers.every((c) => identical(c, controllers.first)), isTrue);
    // ValueKeys are local to their parents; repeated keys in distinct slices
    // alone are not evidence of lost editing state. Shared source is required.
  });

  for (final width in <double>[320, 360]) {
    testWidgets('R7 specialties are closed initially and insertion is unique at $width dp',
        (tester) async {
      final controller = await _pump(
        tester, _document(), size: Size(width, 900),
      );
      final original = controller.document;
      final initiallyOpen = find.byType(SmartExamToolbar).evaluate().isNotEmpty;
      await _captureScreen(tester, 'r7-${width.toInt()}-initial');
      final toggle = find.byTooltip('شريط الصيغ والوسائط');
      await tester.ensureVisible(toggle);
      if (!initiallyOpen) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      expect(find.byType(SmartExamToolbar), findsOneWidget);
      final media = find.text('وسائط');
      await tester.ensureVisible(media);
      await tester.tap(media);
      await tester.pumpAndSettle();
      await _captureScreen(tester, 'r7-${width.toInt()}-media');
      final imageCommands = find.byTooltip('إدراج صورة').evaluate().length +
          find.text('صورة').evaluate().length;
      // The media ListView is lazy: count a command only after bringing it
      // into view. Otherwise a not-yet-built duplicate looks like absence.
      final mediaList = find.ancestor(
        of: find.text('صورة'), matching: find.byType(ListView),
      ).first;
      final mediaScrollElement = find.descendant(
        of: mediaList, matching: find.byType(Scrollable),
      ).first.evaluate().single;
      // Do not keep a finder rooted in the image chip: that chip may be
      // disposed when it scrolls off this lazy list's viewport.
      final mediaScrollable = find.byElementPredicate(
        (element) => identical(element, mediaScrollElement),
      );
      await tester.scrollUntilVisible(
        find.text('مربع نص'), 160, scrollable: mediaScrollable,
      );
      await tester.pumpAndSettle();
      await _captureScreen(tester, 'r7-${width.toInt()}-media-text-box');
      final textBoxCommands = find.byTooltip('مربع نص').evaluate().length +
          find.text('مربع نص').evaluate().length;
      _record('r7-${width.toInt()}-toolbar', <String, Object>{
        'initiallyOpen': initiallyOpen,
        'imageCommands': imageCommands,
        'textBoxCommands': textBoxCommands,
        'sameDocument': identical(original, controller.document),
      });
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _captureScreen(tester, 'r7-${width.toInt()}-closed');
      expect(find.byType(SmartExamToolbar), findsNothing);
      expect(identical(original, controller.document), isTrue);
      expect(initiallyOpen, isFalse);
      expect(imageCommands, 1);
      expect(textBoxCommands, 1);
    });

    testWidgets('R8 all five specialty tabs and every command retain 48dp targets at $width dp',
        (tester) async {
      final controller = await _pump(tester, _document(), size: Size(width, 900));
      final original = controller.document;
      const commands = <String, List<String>>{
        'نص': <String>['سؤال جديد', 'فرع جديد', 'سطر جديد', 'ملاحظة للمعلم', 'آية قرآنية'],
        'رياضيات': <String>['محرر المعادلات', 'تحرير معادلة', 'كسر', 'جذر', 'أس', 'فرعي', 'متكامل', 'مجموع', 'نهاية', 'معادلة'],
        'كيمياء': <String>['محرر المعادلات', 'تحرير معادلة', 'ماء', 'ثاني أكسيد الكربون', 'حمض الكبريتيك', 'الأمونيا', 'سهم تفاعل', 'تفاعل عكوس', 'معادلة أيونية'],
        'فيزياء': <String>['محرر المعادلات', 'تحرير معادلة', 'قوانين نيوتن', 'نسبية', 'قانون أوم', 'الشغل', 'سرعة', 'متغير'],
        'وسائط': <String>['صورة', 'معادلة حرة', 'مثلث', 'دائرة', 'مربع', 'مستطيل', 'خط', 'سهم', 'مربع نص', 'فاصل'],
      };
      const listKeys = <String, String>{
        'نص': 'smart-text-commands',
        'رياضيات': 'smart-formula-commands-كسر',
        'كيمياء': 'smart-formula-commands-ماء',
        'فيزياء': 'smart-formula-commands-قوانين نيوتن',
        'وسائط': 'smart-media-commands',
      };
      final sizes = <String, Object>{};
      for (final entry in commands.entries) {
        await openPreviewSpecialty(tester, entry.key);
        final tab = find.ancestor(of: find.descendant(of: find.byType(TabBar),
            matching: find.text(entry.key)),
            matching: find.byType(InkWell)).first;
        expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
        final list = find.byKey(ValueKey<String>(listKeys[entry.key]!));
        final element = find.descendant(of: list, matching: find.byType(Scrollable))
            .first.evaluate().single;
        final scrollable = find.byElementPredicate((candidate) => identical(candidate, element));
        for (final label in entry.value) {
          final text = find.descendant(of: list, matching: find.text(label));
          await tester.scrollUntilVisible(text, 120, scrollable: scrollable);
          await tester.pumpAndSettle();
          await tester.ensureVisible(text);
          await tester.pumpAndSettle();
          final target = find.ancestor(of: text, matching: find.byType(InkWell)).first;
          final size = tester.getSize(target);
          sizes['${entry.key}/$label'] = <String, double>{'width': size.width, 'height': size.height};
          expect(size.width, greaterThanOrEqualTo(48), reason: '${entry.key}/$label width');
          expect(size.height, greaterThanOrEqualTo(48), reason: '${entry.key}/$label height');
        }
      }
      _record('r8-${width.toInt()}-specialty-touch', sizes);
      expect(identical(original, controller.document), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('R8 all primary controls have 48dp touch targets at $width dp',
        (tester) async {
      await _pump(tester, _document(), size: Size(width, 900));
      final sizes = <String, Object>{};
      var minimumWidth = double.infinity;
      var minimumHeight = double.infinity;
      for (final label in <String>[
        'تكبير', 'تصغير', 'ملاءمة الورقة للشاشة', 'توسيط الورقة',
        'عريض', 'مائل', 'تحته خط', 'شريط الصيغ والوسائط',
      ]) {
        final target = find.descendant(
          of: find.byTooltip(label), matching: find.byType(InkWell),
        ).first;
        final size = tester.getSize(target);
        sizes[label] = <String, double>{'width': size.width, 'height': size.height};
        if (size.width < minimumWidth) minimumWidth = size.width;
        if (size.height < minimumHeight) minimumHeight = size.height;
      }
      // Cover every primary popup/button as well, not only the eight
      // originally reproduced failures. InkResponse includes IconButton's
      // response as well as InkWell's response for text-based popup menus.
      for (final scope in <String, Finder>{
        'primary': find.byType(PreviewToolbar),
        'app-bar': find.byType(AppBar),
        'question-actions': _key('question-actions-bar'),
      }.entries) {
        final controls = find.descendant(of: scope.value,
            matching: find.byWidgetPredicate((widget) => widget is InkResponse))
            .evaluate().toList();
        expect(controls.length, greaterThan(scope.key == 'primary' ? 20 : 2));
        for (var index = 0; index < controls.length; index++) {
          final element = controls[index];
          final target = find.byElementPredicate((candidate) => identical(candidate, element));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final size = tester.getSize(target);
          final label = '${scope.key}-$index';
          sizes[label] = <String, double>{'width': size.width, 'height': size.height};
          expect(size.width, greaterThanOrEqualTo(48), reason: '$label width');
          expect(size.height, greaterThanOrEqualTo(48), reason: '$label height');
        }
      }
      _record('r8-${width.toInt()}-touch', sizes);
      expect(minimumWidth, greaterThanOrEqualTo(48));
      expect(minimumHeight, greaterThanOrEqualTo(48));
    });
  }
}
