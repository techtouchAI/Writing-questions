// Integration candidate only: this never enables the production default.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/text_format_span.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';
import 'package:writing_questions_app/views/wizard/canonical_editing_layer.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

String _body(String label) => List<String>.generate(125,
  (i) => '$label$i نص عربي طويل مع English لفحص انتقال المصدر بين مقاطع الصفحات.',
).join(' ');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CanonicalLayoutPreviewPage).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('The real canonical layout/assets never became ready.');
}

Finder _page(int index) => find.byWidgetPredicate((widget) =>
  widget is CanonicalLayoutPreviewPage && widget.page.index == index);

List<({LayoutLine line, LayoutRun run})> _runs(LayoutPage page, String prefix) => [
  for (final block in page.blocks)
    for (final line in block.allLines)
      for (final run in line.runs)
        if (run.semanticNodeId.startsWith(prefix) && run.text.trim().isNotEmpty && !run.isMath)
          (line: line, run: run),
];

Future<double> _tapPrintedFragment(WidgetTester tester, LayoutPage page, String prefix, {bool endingRunOnly = false}) async {
  final finder = _page(page.index);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  List<Offset> availableTargets() {
    final box = tester.renderObject<RenderBox>(finder);
    // getRect combines transformed top-left with UNTRANSFORMED local size.
    // The real paper is zoomed: use its entire actual paint transform.
    final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final panel = find.descendant(of: find.byType(CanonicalEditingLayer), matching: find.byType(Material));
    final panelRect = panel.evaluate().isEmpty ? null : tester.getRect(panel.first);
    final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    final runs = _runs(page, prefix);
    final targets = endingRunOnly && runs.isNotEmpty
        ? [runs.reduce((a, b) => a.run.sourceEndOffset >= b.run.sourceEndOffset ? a : b)]
        : runs;
    return targets.map((value) => Offset(
      rect.left + (value.run.x + value.run.width / 2) / page.pageSize.width * rect.width,
      rect.top + (value.line.baseline - value.run.baselineOffset + value.run.height / 2) / page.pageSize.height * rect.height,
    )).where((point) => screen.contains(point) && (panelRect == null || !panelRect.contains(point))).toList();
  }
  var available = availableTargets();
  if (available.isEmpty) {
    // A contextual editor can cover a short continuation after top alignment.
    // Real paper scrolling must expose it WITHOUT closing/recreating the input
    // session. Exercise the actual scroll view and remeasure the actual panel.
    await Scrollable.ensureVisible(tester.element(finder), alignment: 1);
    await tester.pumpAndSettle();
    available = availableTargets();
  }
  if (available.isEmpty) {
    // At the document end both ensureVisible alignments clamp to the SAME
    // maximum scroll offset. Drag the real paper backwards: the prior visible
    // anchor moves down and the native pane can sit above it, exposing the short
    // final continuation below. The 2dp edge is outside native chrome (8dp
    // inset), not a callback/scroll-controller shortcut or a hidden editor.
    final scroll = tester.getRect(find.byKey(const ValueKey<String>('paper-v-scroll')));
    for (final delta in <double>[180, -360, 180]) {
      await tester.dragFrom(Offset(scroll.left + 2, scroll.center.dy), Offset(0, delta));
      await tester.pumpAndSettle();
      available = availableTargets();
      if (available.isNotEmpty) break;
    }
  }
  final box = tester.renderObject<RenderBox>(finder);
  final actualPage = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  final panel = find.descendant(of: find.byType(CanonicalEditingLayer), matching: find.byType(Material));
  final panelRect = panel.evaluate().isEmpty ? null : tester.getRect(panel.first);
  expect(available, isNotEmpty, reason: 'After real paper scrolling, page ${page.index} / $prefix must remain reachable. Actual page: $actualPage; native pane: $panelRect; run count: ${_runs(page, prefix).length}.');
  // Use a real pointer hit, never call an activation callback or showKeyboard.
  final before = tester.widget<CanonicalLayoutPreviewPage>(finder).layoutDocument;
  await tester.tapAt(available.last);
  await tester.pumpAndSettle();
  expect(tester.widget<CanonicalLayoutPreviewPage>(finder).layoutDocument, same(before),
    reason: 'Source/metadata activation must not repaginate unchanged data.');
  final afterBox = tester.renderObject<RenderBox>(finder);
  final afterPage = MatrixUtils.transformRect(afterBox.getTransformTo(null), Offset.zero & afterBox.size);
  var maxDelta = 0.0;
  for (final pair in <(double, double)>[(afterPage.left, actualPage.left), (afterPage.top, actualPage.top),
      (afterPage.width, actualPage.width), (afterPage.height, actualPage.height)]) {
    // Only floating-point paint-matrix roundoff, not a pixel/line-height budget.
    final delta = (pair.$1 - pair.$2).abs();
    if (delta > maxDelta) maxDelta = delta;
    expect(pair.$1, closeTo(pair.$2, 1e-6), reason: 'Activating $prefix moved/resized printed page ${page.index}.');
  }
  return maxDelta;
}

Widget _candidateScreen(ExamWizardController controller) => MaterialApp(home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(
          onBackToQuestions: () {},
          enableSeparateEditorCandidate: true,
          canonicalLayoutResolver: ({required ExamDocument document, required DocumentIR sourceIr}) =>
            CanonicalLayoutService.resolve(document: document, sourceIr: sourceIr),
          canonicalPreviewAssetLoader: ({required LayoutDocument layout, required ExamDocument document}) =>
            CanonicalLayoutPreviewAssets.load(layout: layout, document: document),
        ),
      ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FlutterTextMetrics.ensureFontsLoaded);

  for (final width in <double>[320, 360]) {
    testWidgets('candidate native question and branch source keeps IME across fragments at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final questionBody = _body('Q');
      final branchBody = _body('B');
      final document = ExamDocument(
        name: 'Native editor integration candidate',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(id: 'candidate-q', questionNumber: 1, statement: 'منطوق السؤال', body: questionBody,
            branches: <BranchModel>[
              BranchModel(id: 'candidate-b', content: BranchContent(statement: 'منطوق الفرع', body: branchBody)),
            ]),
        ],
      );
      final controller = ExamWizardController(document: document);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      final layout = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
      final originalDocument = controller.document;

      for (final entry in <String, String>{
        'body-candidate-q': 'candidate-q/body',
        'branch-body-candidate-b': 'candidate-q/branch/candidate-b/body',
      }.entries) {
        if (find.byType(CanonicalEditingLayer).evaluate().isNotEmpty) {
          // Switching to a DIFFERENT source field may close the old contextual
          // editor. Fragment-to-fragment checks below never close it.
          await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
          await tester.pumpAndSettle();
        }
        final pages = layout.pages.where((page) => _runs(page, entry.value).isNotEmpty).toList();
        expect(pages.length, greaterThan(1), reason: '${entry.key} must REALLY span pages.');
        EditableTextState? originalEditor;
        TextEditingController? originalController;
        int? inputConnections;
        for (final page in pages) {
          await _tapPrintedFragment(tester, page, entry.value);
          final sourceField = find.byKey(ValueKey<String>(entry.key));
          expect(sourceField, findsOneWidget);
          final native = tester.state<EditableTextState>(find.descendant(of: sourceField, matching: find.byType(EditableText)));
          originalEditor ??= native;
          originalController ??= native.widget.controller;
          expect(identical(native, originalEditor), isTrue,
            reason: 'Changing only the printed fragment must NOT recreate the native editor.');
          expect(identical(native.widget.controller, originalController), isTrue);
          expect(native.widget.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          final connections = tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
          inputConnections ??= connections;
          expect(connections, inputConnections, reason: 'Moving the anchor must not reconnect IME.');
          expect(native.widget.style.color, isNot(Colors.transparent));
          expect(find.descendant(of: _page(page.index), matching: find.byType(PaperField)), findsNothing,
            reason: 'Native text and IME must not enter the printable subtree.');
          expect(identical(controller.document, originalDocument), isTrue);
          expect(tester.widget<CanonicalLayoutPreviewPage>(_page(page.index)).layoutDocument, same(layout));
          final panel = find.descendant(of: find.byType(CanonicalEditingLayer), matching: find.byType(Material)).first;
          expect(tester.getRect(panel).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(panel).right, lessThanOrEqualTo(width));
        }
      }
      final source = find.byKey(const ValueKey<String>('branch-body-candidate-b'));
      final native = tester.state<EditableTextState>(find.descendant(of: source, matching: find.byType(EditableText)));
      final offset = native.widget.controller.selection.extentOffset;
      final composed = '${branchBody.substring(0, offset)}م${branchBody.substring(offset)}';
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: composed,
        selection: TextSelection.collapsed(offset: offset + 1),
        composing: TextRange(start: offset, end: offset + 1),
      ));
      await tester.pumpAndSettle();
      final after = tester.state<EditableTextState>(find.descendant(of: source, matching: find.byType(EditableText)));
      expect(identical(after, native), isTrue);
      expect(after.widget.focusNode.hasFocus, isTrue);
      expect(after.widget.controller.value.composing, TextRange(start: offset, end: offset + 1));
      expect(controller.questions.single.branches.single.content.body, composed);
      expect(controller.questions.single.body, questionBody);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.questions.single.branches.single.content.body, branchBody);
      controller.redo();
      await tester.pumpAndSettle();
      expect(controller.questions.single.branches.single.content.body, composed);
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native empty question and branch bodies stay outside print at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Optional bodies',
        header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(
          id: 'empty-q', questionNumber: 1, statement: 'منطوق السؤال',
          branches: <BranchModel>[BranchModel(id: 'empty-b', content: BranchContent(statement: 'منطوق الفرع'))],
        )],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      for (final entry in <String, String>{
        'body-empty-q': 'empty-q',
        'branch-body-empty-b': 'empty-q/branch/empty-b',
      }.entries) {
        final pageWidget = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first);
        final layout = pageWidget.layoutDocument;
        final before = controller.document;
        final lines = [for (final page in layout.pages) for (final block in page.blocks) for (final line in block.allLines) line.rect];
        expect([for (final page in layout.pages) ..._runs(page, '${entry.value}/body')], isEmpty);
        final page = layout.pages.firstWhere((page) => _runs(page, '${entry.value}/title/statement').isNotEmpty);
        await _tapPrintedFragment(tester, page, '${entry.value}/title/statement');
        final action = find.byKey(const ValueKey<String>('question-action-edit-body'));
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing, reason: 'Candidate bodies use the same anchored native editor, not a replacement dialog.');
        final field = find.byKey(ValueKey<String>(entry.key));
        final editable = find.descendant(of: field, matching: find.byType(EditableText));
        expect(editable, findsOneWidget);
        final native = tester.widget<EditableText>(editable);
        final nativeState = tester.state<EditableTextState>(editable);
        expect(native.focusNode.hasFocus, isTrue);
        expect(tester.getSize(find.descendant(of: field, matching: find.byType(TextField))).height, greaterThanOrEqualTo(48));
        expect(controller.document, same(before));
        final after = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in after.pages) for (final block in page.blocks) for (final line in block.allLines) line.rect], lines,
          reason: 'Opening an optional editor must create no printed box or change any printed coordinate.');
        expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage), matching: field), findsNothing);
        final connections = tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
        tester.testTextInput.updateEditingValue(const TextEditingValue(text: 'م',
          selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
        await tester.pumpAndSettle();
        expect(native.controller.value.composing, const TextRange(start: 0, end: 1));
        expect(tester.state<EditableTextState>(editable), same(nativeState));
        await tester.enterText(field, 'إضافة نص اختياري English');
        await tester.pumpAndSettle();
        expect(native.controller.text, 'إضافة نص اختياري English');
        expect(entry.key.startsWith('branch') ? controller.questions.single.branches.single.content.body : controller.questions.single.body, native.controller.text);
        expect(tester.state<EditableTextState>(editable), same(nativeState));
        expect(tester.widget<EditableText>(editable).controller, same(native.controller));
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(editable), same(nativeState), reason: 'Removing the final printed run must retain native focus/controller/session via the actual owner anchor.');
        expect(native.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length, connections);
        final cleared = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in cleared.pages) ..._runs(page, '${entry.value}/body')], isEmpty);
        await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native metadata reuses label and marks dialogs with 48dp controls at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Native metadata', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(id: 'meta-q', questionNumber: 1, statement: 'منطوق السؤال', marksOverride: 4,
            statementFormats: const <TextFormatSpan>[TextFormatSpan(start: 0, end: 5, bold: true, color: 0xFF123456)],
            branches: <BranchModel>[BranchModel(id: 'meta-b', marks: 2, content: BranchContent(statement: 'منطوق الفرع'))]),
          QuestionModel(id: 'untouched-q', questionNumber: 2, statement: 'سؤال لا يتغير'),
        ],
      ));
      addTearDown(controller.dispose);
      final untouched = controller.questions.last.toMap();
      final formats = controller.questions.first.statementFormats.map((span) => span.toMap()).toList();
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      Future<void> saveDialog(String title, String value, {bool numeric = false}) async {
        final dialog = find.byType(AlertDialog);
        expect(find.descendant(of: dialog, matching: find.text(title)), findsOneWidget);
        final input = find.descendant(of: dialog, matching: find.byType(TextField));
        expect(tester.getSize(input).height, greaterThanOrEqualTo(48));
        await tester.tap(input);
        await tester.pumpAndSettle();
        expect(tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText))).focusNode.hasFocus, isTrue);
        await tester.enterText(input, value);
        final save = find.descendant(of: dialog, matching: find.widgetWithText(FilledButton, numeric ? 'تطبيق' : 'حفظ'));
        final cancel = find.descendant(of: dialog, matching: find.widgetWithText(TextButton, 'إلغاء'));
        for (final control in <Finder>[save, cancel]) {
          expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
        }
        await tester.tap(save);
        await tester.pumpAndSettle();
      }
      Future<void> printed(String prefix, String title, String value, {bool numeric = false}) async {
        final before = controller.document;
        final layout = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        final page = layout.pages.firstWhere((page) => _runs(page, prefix).isNotEmpty);
        await _tapPrintedFragment(tester, page, prefix);
        expect(controller.document, same(before), reason: 'Opening metadata must change no printed data/geometry.');
        expect(tester.widget<CanonicalLayoutPreviewPage>(_page(page.index)).layoutDocument, same(layout));
        await saveDialog(title, value, numeric: numeric);
      }
      await printed('meta-q/title/label', 'رقم السؤال', 'س خاص/');
      expect(controller.questions.first.numberOverride, 'س خاص/');
      await printed('meta-q/title/marks', 'درجة السؤال', '8', numeric: true);
      expect(controller.questions.first.marksOverride, 8);
      await printed('meta-q/branch/meta-b/title/label', 'رقم الفرع', 'ب خاص');
      expect(controller.questions.first.branches.single.labelOverride, 'ب خاص');
      await printed('meta-q/branch/meta-b/title/marks', 'درجة الفرع', '5', numeric: true);
      expect(controller.questions.first.branches.single.marks, 5);
      for (final name in <String>['question-action-label', 'question-action-marks', 'branch-action-label', 'branch-action-marks']) {
        final action = find.byKey(ValueKey<String>(name));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(tester.getSize(action), const Size(48, 48));
        expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage), matching: action), findsNothing);
        final before = controller.document;
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('إلغاء')));
        await tester.pumpAndSettle();
        expect(controller.document, same(before), reason: 'Cancel must preserve all data.');
      }
      // A non-printed zero mark still has the SAME native 48dp command.
      for (final kind in <String>['question', 'branch']) {
        final action = find.byKey(ValueKey<String>('$kind-action-marks'));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        await saveDialog(kind == 'question' ? 'درجة السؤال' : 'درجة الفرع', '0', numeric: true);
        expect(kind == 'question' ? controller.questions.first.marksOverride : controller.questions.first.branches.single.marks, 0);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await saveDialog(kind == 'question' ? 'درجة السؤال' : 'درجة الفرع', '7', numeric: true);
        expect(kind == 'question' ? controller.questions.first.marksOverride : controller.questions.first.branches.single.marks, 7);
      }
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.questions.first.branches.single.marks, 0);
      controller.redo();
      await tester.pumpAndSettle();
      expect(controller.questions.first.branches.single.marks, 7);
      expect(controller.questions.last.toMap(), untouched);
      expect(controller.questions.first.statementFormats.map((span) => span.toMap()).toList(), formats);
      expect(controller.questions.first.statement, 'منطوق السؤال');
      expect(controller.questions.first.branches.single.content.statement, 'منطوق الفرع');
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native entirely unprinted owners keep all statement and body fields accessible at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Unprinted source owners', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(id: 'blank-q', questionNumber: 1, statement: '   ',
          branches: <BranchModel>[BranchModel(id: 'blank-b', content: BranchContent(body: '\n '))])],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      for (final key in <String>['statement-blank-q', 'branch-statement-blank-b', 'body-blank-q', 'branch-body-blank-b']) {
        final before = controller.document;
        final plan = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in plan.pages) ..._runs(page, 'blank-q')], isEmpty,
          reason: 'Entirely empty/whitespace owners must have NO printed placeholder.');
        final access = find.byKey(const ValueKey<String>('canonical-empty-fields'));
        await tester.ensureVisible(access);
        await tester.pumpAndSettle();
        expect(tester.getSize(access), const Size(48, 48));
        await tester.tap(access);
        await tester.pumpAndSettle();
        final entry = find.byKey(ValueKey<String>('canonical-empty-$key'));
        expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
        await tester.tap(entry);
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey<String>(key));
        final editable = find.descendant(of: field, matching: find.byType(EditableText));
        final native = tester.state<EditableTextState>(editable);
        expect(native.widget.focusNode.hasFocus, isTrue);
        expect(controller.document, same(before));
        expect(tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument, same(plan));
        expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage), matching: field), findsNothing);
        final connections = tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
        tester.testTextInput.updateEditingValue(const TextEditingValue(text: 'م',
          selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
        await tester.pumpAndSettle();
        expect(native.widget.controller.text, 'م');
        expect(native.widget.controller.value.composing, const TextRange(start: 0, end: 1));
        expect(tester.state<EditableTextState>(editable), same(native));
        final typed = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in typed.pages) ..._runs(page, 'blank-q')], isNotEmpty);
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(editable), same(native));
        expect(native.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length, connections);
        final cleared = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in cleared.pages) ..._runs(page, 'blank-q')], isEmpty);
        await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
        await tester.pumpAndSettle();
      }
      expect(controller.questions.single.statement, isEmpty);
      expect(controller.questions.single.body, isEmpty);
      expect(controller.questions.single.branches.single.content.statement, isEmpty);
      expect(controller.questions.single.branches.single.content.body, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native option identity survives a same-frame earlier deletion at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      BranchItem item(String id) => BranchItem(id: id, text: 'اختر الإجابة', kind: PointKind.multipleChoice,
        options: <QuestionOption>[
          QuestionOption(id: '$id-first', text: 'FIRST'),
          QuestionOption(id: '$id-second', text: 'SECOND', formats: const <TextFormatSpan>[TextFormatSpan(start: 0, end: 6, bold: true)]),
          QuestionOption(id: '$id-third', text: 'THIRD'),
        ]);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Persistent option identity', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(id: 'identity-q', questionNumber: 1, statement: 'منطوق السؤال',
          items: <BranchItem>[item('identity-qp')],
          branches: <BranchModel>[BranchModel(id: 'identity-b', content: BranchContent(statement: 'منطوق الفرع', items: <BranchItem>[item('identity-bp')]))])],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      for (final entry in <String, PointsOwner>{
        'identity-q/point/identity-qp': const PointsOwner.question(0),
        'identity-q/branch/identity-b/point/identity-bp': PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 0)),
      }.entries) {
        final point = controller.document.pointsOf(entry.value).single;
        final selected = point.options[1];
        final untouched = point.options.last.toMap();
        final layout = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        final prefix = '${entry.key}/options/${selected.id}/content';
        final page = layout.pages.firstWhere((page) => _runs(page, prefix).isNotEmpty);
        await _tapPrintedFragment(tester, page, prefix);
        final field = find.byWidgetPredicate((widget) => widget is PaperField && widget.controller.text == selected.text);
        final fieldKey = tester.widget<PaperField>(field).key;
        final editable = find.descendant(of: find.byKey(fieldKey!), matching: find.byType(EditableText));
        final native = tester.state<EditableTextState>(editable);
        final originalController = native.widget.controller;
        final connections = tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
        // Deliberate external model mutation, NOT an assertion of delete-button
        // parity: exercise input arriving BEFORE the next widget/layout build.
        controller.removePointOption(entry.value, point.id, 0);
        const composed = 'SECONDم';
        tester.testTextInput.updateEditingValue(const TextEditingValue(text: composed,
          selection: TextSelection.collapsed(offset: 7), composing: TextRange(start: 6, end: 7)));
        final updated = controller.document.pointsOf(entry.value).single;
        expect(updated.options.first.id, selected.id);
        expect(updated.options.first.text, composed,
          reason: 'An earlier deletion must not retarget the old index callback to the NEXT option.');
        expect(updated.options.last.toMap(), untouched);
        expect(updated.options.first.formats.map((span) => span.toMap()).toList(), selected.formats.map((span) => span.toMap()).toList());
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(editable), same(native));
        expect(native.widget.controller, same(originalController));
        expect(native.widget.focusNode.hasFocus, isTrue);
        expect(native.widget.controller.value.composing, const TextRange(start: 6, end: 7));
        expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length, connections);
        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.document.pointsOf(entry.value).single.options.first.text, 'SECOND');
        controller.redo();
        await tester.pumpAndSettle();
        expect(controller.document.pointsOf(entry.value).single.options.first.text, composed);
        await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native point and option continuations preserve geometry and source identity at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      BranchItem point(String id) => BranchItem(id: id, text: _body('$id-text'), kind: PointKind.multipleChoice,
        textFormats: const <TextFormatSpan>[TextFormatSpan(start: 0, end: 2, italic: true)],
        options: <QuestionOption>[QuestionOption(id: '$id-long', text: _body('$id-option'),
          formats: const <TextFormatSpan>[TextFormatSpan(start: 0, end: 2, bold: true)]),
          QuestionOption(id: '$id-sibling', text: 'خيار شقيق محفوظ')]);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Point and option continuation geometry', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(id: 'split-q', questionNumber: 1, statement: 'منطوق السؤال',
          items: <BranchItem>[point('split-qp')], branches: <BranchModel>[BranchModel(id: 'split-b',
            content: BranchContent(statement: 'منطوق الفرع', items: <BranchItem>[point('split-bp')]))]),
          QuestionModel(id: 'next-q', questionNumber: 2, statement: 'السؤال التالي NEXT')],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(RepaintBoundary(key: const ValueKey<String>('native-point-evidence-screen'),
        child: _candidateScreen(controller)));
      await _settle(tester);
      LayoutDocument currentLayout() => tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
      const output = 'build/production_fragment_repro';
      Directory(output).createSync(recursive: true);
      final label = 'r10-native-${width.toInt()}';
      Future<void> png(Finder finder, String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        try {
          final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
          File('$output/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
      Future<void> capture(String state) async {
        for (final page in currentLayout().pages) {
          final finder = _page(page.index);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await png(find.byKey(const ValueKey<String>('native-point-evidence-screen')), '$label-$state-page-${page.index}-phone');
          await png(find.ancestor(of: finder, matching: find.byType(RepaintBoundary)).first, '$label-$state-page-${page.index}-paper');
        }
      }
      await capture('before-selection');
      var maxActivationDelta = 0.0;
      final sourcePages = <String, List<int>>{};
      final original = controller.document.toMap();
      final sources = <String, ({String prefix, String Function() text})>{
        'item-split-qp': (prefix: 'split-q/point/split-qp/content', text: () => controller.questions.first.items.single.text),
        'option:split-qp:split-qp-long': (prefix: 'split-q/point/split-qp/options/split-qp-long/content', text: () => controller.questions.first.items.single.options.first.text),
        'item-split-bp': (prefix: 'split-q/branch/split-b/point/split-bp/content', text: () => controller.questions.first.branches.single.content.items.single.text),
        'option:split-bp:split-bp-long': (prefix: 'split-q/branch/split-b/point/split-bp/options/split-bp-long/content', text: () => controller.questions.first.branches.single.content.items.single.options.first.text),
      };
      for (final entry in sources.entries) {
        if (find.byType(CanonicalEditingLayer).evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
          await tester.pumpAndSettle();
        }
        final source = entry.value.text();
        final plan = currentLayout();
        final pages = plan.pages.where((page) => _runs(page, entry.value.prefix).isNotEmpty).map((page) => page.index).toList();
        sourcePages[entry.key] = pages;
        expect(pages.length, greaterThan(1), reason: '${entry.key} must really split, not only its parent question.');
        final coverage = List<int>.filled(source.length, 0);
        for (final page in plan.pages) {
          for (final value in _runs(page, entry.value.prefix)) {
            // Shared-plan line AND glyph-metric boxes must fit the actual page
            // body, rather than relying on a larger clip to hide overflow.
            expect(value.line.rect.top, greaterThanOrEqualTo(page.bodyBounds.top - 1e-6));
            expect(value.line.rect.bottom, lessThanOrEqualTo(page.bodyBounds.bottom + 1e-6));
            final inkTop = value.line.baseline - value.run.baselineOffset;
            expect(inkTop, greaterThanOrEqualTo(page.bodyBounds.top - 1e-6));
            expect(inkTop + value.run.height, lessThanOrEqualTo(page.bodyBounds.bottom + 1e-6));
            for (var offset = value.run.sourceStartOffset; offset < value.run.sourceEndOffset; offset++) {
              expect(offset, inInclusiveRange(0, source.length - 1));
              coverage[offset]++;
            }
          }
        }
        for (var offset = 0; offset < source.length; offset++) {
          if (source[offset].trim().isNotEmpty) {
            expect(coverage[offset], 1, reason: 'Missing/duplicated printable source at ${entry.key}:$offset.');
          }
        }
        EditableTextState? firstEditor;
        TextEditingController? firstController;
        int? connections;
        for (final pageIndex in pages) {
          final live = currentLayout();
          final delta = await _tapPrintedFragment(tester, live.pages[pageIndex], entry.value.prefix,
            endingRunOnly: pageIndex == pages.last);
          if (delta > maxActivationDelta) maxActivationDelta = delta;
          final field = find.byKey(ValueKey<String>(entry.key));
          final editable = find.descendant(of: field, matching: find.byType(EditableText));
          final native = tester.state<EditableTextState>(editable);
          firstEditor ??= native;
          firstController ??= native.widget.controller;
          connections ??= tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
          expect(native, same(firstEditor));
          expect(native.widget.controller, same(firstController));
          expect(native.widget.focusNode.hasFocus, isTrue);
          expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage), matching: field), findsNothing);
          expect(currentLayout(), same(live));
          final offset = native.widget.controller.selection.extentOffset;
          expect(offset, inInclusiveRange(0, source.length));
          final changed = source.replaceRange(offset, offset, 'م');
          tester.testTextInput.updateEditingValue(TextEditingValue(text: changed,
            selection: TextSelection.collapsed(offset: offset + 1), composing: TextRange(start: offset, end: offset + 1)));
          await tester.pumpAndSettle();
          expect(entry.value.text(), changed, reason: 'Editing fragment $pageIndex must write the original model source.');
          expect(tester.state<EditableTextState>(editable), same(firstEditor));
          expect(native.widget.controller.value.composing, TextRange(start: offset, end: offset + 1));
          controller.undo();
          await tester.pumpAndSettle();
          expect(controller.document.toMap(), original, reason: 'Undo must restore all owners, options and range formats exactly.');
          expect(native.widget.focusNode.hasFocus, isTrue);
          expect(tester.state<EditableTextState>(editable), same(firstEditor));
          expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length, connections);
        }
      }
      final finalLayout = currentLayout();
      final lastBranchPage = finalLayout.pages.lastWhere((page) => _runs(page, 'split-q/branch/split-b/').isNotEmpty);
      final nextPage = finalLayout.pages.firstWhere((page) => _runs(page, 'next-q/title/').isNotEmpty);
      expect(nextPage.index, greaterThanOrEqualTo(lastBranchPage.index));
      if (nextPage.index == lastBranchPage.index) {
        final branchBottom = _runs(lastBranchPage, 'split-q/branch/split-b/').map((value) => value.line.rect.bottom).reduce((a, b) => a > b ? a : b);
        final nextTop = _runs(nextPage, 'next-q/title/').map((value) => value.line.rect.top).reduce((a, b) => a < b ? a : b);
        expect(nextTop, greaterThanOrEqualTo(branchBottom - 1e-6), reason: 'Final branch ink must not overlap the following question.');
      }
      expect(identical(finalLayout.source, controller.documentIr), isTrue,
        reason: 'PDF evidence must use the displayed plan of the current, restored model.');
      await capture('option-selected');
      expect(currentLayout(), same(finalLayout));
      final pdf = await tester.runAsync(() => PdfExportService.buildDocumentPdfBytes(
        document: controller.document, layoutDocument: finalLayout));
      expect(pdf, isNotNull);
      File('$output/$label-same-live-plan.pdf').writeAsBytesSync(pdf!);
      File('$output/$label-manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'surface': 'opt-in native editor candidate; production remains legacy',
        'widthDp': width, 'pageCount': finalLayout.pageCount, 'sourcePages': sourcePages,
        'allPrintableSourceOffsetsCoveredExactlyOnce': true, 'glyphBoxesWithinPageBody': true,
        'everyFragmentEditedOriginalModelAndUndoRestoredAllData': true,
        'maxActivationDeltaPx': maxActivationDelta, 'geometryTolerancePx': 1e-6,
        'pdfUsesDisplayedLivePlan': true, 'lastBranchPage': lastBranchPage.index,
        'followingQuestionPage': nextPage.index, 'manualVisualReview': false,
      }));
      expect(tester.takeException(), isNull);
    });

    testWidgets('candidate native point and option commands preserve existing models at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      BranchItem item(String id) => BranchItem(id: id, text: 'نص النقطة الأصلية',
        textFormats: const <TextFormatSpan>[TextFormatSpan(start: 0, end: 2, italic: true)]);
      final controller = ExamWizardController(document: ExamDocument(
        name: 'Native point commands', header: ExamHeaderModel.initial(subject: 'الرياضيات'),
        questions: <QuestionModel>[QuestionModel(id: 'commands-q', questionNumber: 1, statement: 'منطوق السؤال',
          items: <BranchItem>[item('commands-qp')], branches: <BranchModel>[BranchModel(id: 'commands-b',
            content: BranchContent(statement: 'منطوق الفرع', items: <BranchItem>[item('commands-bp')]))])],
      ));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_candidateScreen(controller));
      await _settle(tester);
      Future<void> command(String key) async {
        final action = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(tester.getSize(action), const Size(48, 48));
        expect(find.descendant(of: find.byType(CanonicalLayoutPreviewPage), matching: action), findsNothing);
        final before = controller.document;
        final plan = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        final coordinates = [for (final page in plan.pages) for (final block in page.blocks) for (final line in block.allLines) line.rect];
        await tester.tap(action);
        await tester.pumpAndSettle();
        if (identical(controller.document, before)) {
          final after = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
          expect(after, same(plan));
          expect([for (final page in after.pages) for (final block in page.blocks) for (final line in block.allLines) line.rect], coordinates,
            reason: 'Opening $key must not move any printed line.');
        }
      }
      Future<void> chooseKind(PointKind kind) async {
        await command('point-action-kind');
        final entry = find.byKey(ValueKey<String>('point-kind-${kind.name}'));
        expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
        await tester.tap(entry);
        await tester.pumpAndSettle();
      }
      Future<void> dialog(String title, String text, {bool numeric = false}) async {
        final route = find.byType(AlertDialog);
        expect(find.descendant(of: route, matching: find.text(title)), findsOneWidget);
        final input = find.descendant(of: route, matching: find.byType(TextField));
        expect(tester.getSize(input).height, greaterThanOrEqualTo(48));
        await tester.tap(input);
        await tester.enterText(input, text);
        await tester.tap(find.descendant(of: route, matching: find.text(numeric ? 'تطبيق' : 'حفظ')));
        await tester.pumpAndSettle();
      }
      Future<void> printed(String prefix) async {
        final layout = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        final page = layout.pages.firstWhere((page) => _runs(page, prefix).isNotEmpty);
        await _tapPrintedFragment(tester, page, prefix);
      }
      Future<void> empty(String key) async {
        await command('canonical-empty-fields');
        final entry = find.byKey(ValueKey<String>('canonical-empty-$key'));
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: 'Empty-source switch must survive popup focus restoration; mounted fields: '
            '${tester.widgetList<PaperField>(find.byType(PaperField)).map((field) => field.key).toList()}');
      }
      Future<void> history(String tooltip) async {
        final action = find.byTooltip(tooltip);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      for (final owner in <PointsOwner>[const PointsOwner.question(0), PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 0))]) {
        final point = controller.document.pointsOf(owner).single;
        final other = owner.isBranch ? const PointsOwner.question(0) : PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 0));
        final otherData = controller.document.pointsOf(other).map((point) => point.toMap()).toList();
        final prefix = owner.isBranch ? 'commands-q/branch/commands-b/point/${point.id}' : 'commands-q/point/${point.id}';
        await printed('$prefix/content');
        List<String>? optionIds;
        for (final kind in <PointKind>[PointKind.trueFalse, PointKind.fillBlank, PointKind.multipleChoice, PointKind.plain, PointKind.multipleChoice]) {
          await chooseKind(kind);
          expect(controller.document.pointsOf(owner).single.kind, kind);
          expect(controller.document.pointsOf(owner).single.text, point.text);
          if (kind == PointKind.multipleChoice) optionIds ??= controller.document.pointsOf(owner).single.options.map((option) => option.id).toList();
          if (optionIds != null) expect(controller.document.pointsOf(owner).single.options.map((option) => option.id).toList(), optionIds);
        }
        expect(controller.document.pointsOf(owner).single.options.length, 4);
        await command('point-action-label');
        await dialog('ترقيم النقطة', 'نقطة خاصة');
        expect(controller.document.pointsOf(owner).single.labelOverride, 'نقطة خاصة');
        await printed('$prefix/label');
        await dialog('ترقيم النقطة', 'نقطة مطبوعة');
        await command('point-action-marks');
        await dialog('درجة النقطة', '3', numeric: true);
        expect(controller.document.pointsOf(owner).single.marks, 3);
        await printed('$prefix/marks');
        await dialog('درجة النقطة', '4', numeric: true);
        final options = controller.document.pointsOf(owner).single.options;
        final firstId = options.first.id;
        String optionKey(String id) => 'option:${Uri.encodeComponent(point.id)}:${Uri.encodeComponent(id)}';
        await empty(optionKey(firstId));
        final field = find.byKey(ValueKey<String>(optionKey(firstId)));
        final editable = find.descendant(of: field, matching: find.byType(EditableText));
        final native = tester.state<EditableTextState>(editable);
        await tester.enterText(field, 'خيار أول');
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(editable), same(native));
        expect(controller.document.pointsOf(owner).single.options.first.text, 'خيار أول');
        final retainedOptions = controller.document.pointsOf(owner).single.options.map((option) => option.toMap()).toList();
        await chooseKind(PointKind.plain);
        expect(controller.document.pointsOf(owner).single.options.map((option) => option.toMap()).toList(), retainedOptions);
        final pointField = find.byKey(ValueKey<String>('item-${point.id}'));
        final pointEditor = tester.widget<EditableText>(find.descendant(of: pointField, matching: find.byType(EditableText)));
        expect(pointEditor.focusNode.hasFocus, isTrue, reason: 'Hiding MCQ options must activate point text, not lose the editor.');
        expect(find.byKey(ValueKey<String>(optionKey(firstId))), findsNothing);
        await chooseKind(PointKind.multipleChoice);
        expect(controller.document.pointsOf(owner).single.options.map((option) => option.toMap()).toList(), retainedOptions);
        await printed('$prefix/options/$firstId/content');
        await command('option-action-label');
        await dialog('تسمية الخيار', 'C.');
        await printed('$prefix/options/$firstId/label');
        await dialog('تسمية الخيار', 'D.');
        expect(controller.document.pointsOf(owner).single.options.first.labelOverride, 'D.');
        final secondId = controller.document.pointsOf(owner).single.options[1].id;
        await empty(optionKey(secondId));
        await command('option-action-delete');
        expect(controller.document.pointsOf(owner).single.options.length, 3);
        expect(controller.document.pointsOf(owner).single.options.any((option) => option.id == secondId), isFalse);
        expect(controller.document.pointsOf(owner).single.options.first.id, firstId);
        expect(controller.document.pointsOf(owner).single.options.first.text, 'خيار أول');
        await history('تراجع');
        expect(controller.document.pointsOf(owner).single.options[1].id, secondId);
        await history('إعادة');
        expect(controller.document.pointsOf(owner).single.options.length, 3);
        await printed('$prefix/content');
        await command('point-action-add-option');
        expect(controller.document.pointsOf(owner).single.options.length, 4);
        final addedId = controller.document.pointsOf(owner).single.options.last.id;
        await empty(optionKey(addedId));
        await tester.enterText(find.byKey(ValueKey<String>(optionKey(addedId))), 'خيار مضاف');
        await tester.pumpAndSettle();
        final saved = controller.document.pointsOf(owner).single.toMap();
        await command('point-action-delete');
        expect(controller.document.pointsOf(owner), isEmpty);
        await history('تراجع');
        expect(controller.document.pointsOf(owner).single.toMap(), saved);
        // Existing add-point command, now with real access to its empty source.
        await command('question-action-add-point');
        final addedPoint = controller.document.pointsOf(owner).last;
        expect(controller.document.pointsOf(owner).length, 2);
        await empty('item-${addedPoint.id}');
        final linesField = find.byKey(ValueKey<String>('item-${addedPoint.id}'));
        final linesEditable = find.descendant(of: linesField, matching: find.byType(EditableText));
        final lineEditor = tester.state<EditableTextState>(linesEditable);
        final lineConnections = tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length;
        await tester.enterText(linesField, 'سطر أول\nسطر ثان');
        await tester.pumpAndSettle();
        expect(controller.document.pointsOf(owner).last.text, 'سطر أول\nسطر ثان');
        await history('تراجع');
        expect(controller.document.pointsOf(owner).last.text, isEmpty);
        expect(tester.state<EditableTextState>(linesEditable), same(lineEditor));
        expect(lineEditor.widget.focusNode.hasFocus, isTrue);
        await history('إعادة');
        expect(controller.document.pointsOf(owner).last.text, 'سطر أول\nسطر ثان');
        expect(tester.state<EditableTextState>(linesEditable), same(lineEditor));
        expect(lineEditor.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.setClient').length, lineConnections);
        await command('point-action-delete');
        expect(controller.document.pointsOf(owner).single.toMap(), saved);
        expect(controller.document.pointsOf(other).map((point) => point.toMap()).toList(), otherData);
        expect(controller.document.pointsOf(owner).single.textFormats.map((span) => span.toMap()).toList(), point.textFormats.map((span) => span.toMap()).toList());
      }
      expect(controller.questions.single.statement, 'منطوق السؤال');
      expect(controller.questions.single.branches.single.content.statement, 'منطوق الفرع');
      expect(tester.takeException(), isNull);
    });
  }
}
