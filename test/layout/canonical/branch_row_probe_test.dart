// ⚠️ TEMP PROBE — يُزال.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _doc() => ExamDocument(
      name: 'p',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      settings: const PaperSettings(baseFontSize: 11, lineSpacing: 1.7, marginMm: 15),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'bq1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          branches: <BranchModel>[
            BranchModel(
              content: BranchContent(
                statement: 'منطوق الفرع الأول الطويل نسبياً ليقيس عرضه وتفافه',
                items: <BranchItem>[BranchItem(id: 'i1', text: 'نقطة')],
              ),
              marks: 2,
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => FlutterTextMetrics.ensureFontsLoaded());

  testWidgets('PROBE-BRANCH', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = _doc();
    final controller = ExamWizardController(document: doc);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: ExamPreviewScreen(onBackToQuestions: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final planController = ExamWizardController(document: controller.document);
    addTearDown(planController.dispose);
    final layout = await CanonicalLayoutService.resolve(
      document: planController.document,
      sourceIr: planController.documentIr,
    );
    final plan = CanonicalPagePlan.fromLayout(layout);
    String f(double v) => v.toStringAsFixed(2);

    LayoutBlock? branchBlock;
    void scan(LayoutBlock block) {
      if (block.kind == LayoutBlockKind.branch) branchBlock ??= block;
      for (final child in block.children) {
        scan(child);
      }
    }

    for (final page in plan.layout.pages) {
      for (final block in page.blocks) {
        scan(block);
      }
    }
    expect(branchBlock, isNotNull, reason: 'لا كتلة فرع في الخطة.');
    final branch = branchBlock!;
    final title = branch.children.firstWhere((c) => c.kind == LayoutBlockKind.title);

    final branchStatement = controller.document.questions.first.branches.first.content.statement;
    final field = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.controller?.text == branchStatement);
    expect(field, findsOneWidget, reason: 'حقل منطوق الفرع غير موجود.');

    final rect = tester.getRect(field);
    final rowRect = tester.getRect(
      find.ancestor(of: field, matching: find.byType(Row)).first,
    );
    final buttons = find.descendant(
      of: find.ancestor(of: field, matching: find.byType(Row)).first,
      matching: find.byType(IconButton),
    );
    final heights = <String>[
      for (var i = 0; i < tester.widgetList(buttons).length; i++)
        f(tester.getRect(buttons.at(i)).height),
    ];
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    final lines = editable.renderEditable
        .getBoxesForSelection(TextSelection(
          baseOffset: 0,
          extentOffset: editable.textEditingValue.text.length,
        ))
        .length;
    final runs = <LayoutRun>[
      for (final line in branch.allLines)
        ...line.runs.where((run) => run.semanticNodeId.contains('/statement')),
    ];
    final span = runs.isEmpty
        ? 0.0
        : runs.map((r) => r.x + r.advance).reduce(math.max) -
            runs.map((r) => r.x).reduce(math.min);
    final planLines = <String>{
      for (final line in branch.allLines)
        if (line.runs.any((r) => r.semanticNodeId.contains('/statement'))) line.id,
    }.length;

    expect(
      'A${f(rowRect.height)}/${f(LayoutUnits.ptToPx(title.rect.height))}'
      ' B${f(rect.width)}/${f(LayoutUnits.ptToPx(span))}'
      ' C$lines/$planLines'
      ' D${f(rect.top - rowRect.bottom)}'
      ' E${heights.join("/")}',
      'P',
    );
  });
}
