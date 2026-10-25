// Integration candidate only: this never enables the production default.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
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

Future<void> _tapPrintedFragment(WidgetTester tester, LayoutPage page, String prefix) async {
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
    return _runs(page, prefix).map((value) => Offset(
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
  expect(available, isNotEmpty, reason: 'After real paper scrolling, page ${page.index} / $prefix must remain reachable through its actual render transform.');
  // Use a real pointer hit, never call an activation callback or showKeyboard.
  await tester.tapAt(available.last);
  await tester.pumpAndSettle();
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
        final cleared = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage).first).layoutDocument;
        expect([for (final page in cleared.pages) ..._runs(page, '${entry.value}/body')], isEmpty);
        await tester.tap(find.byTooltip('إغلاق محرر المحتوى'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
