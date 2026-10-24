// ⚠️ TEMP PROBE — يُزال قبل الالتزام النهائي.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _document() => ExamDocument(
      name: 'أدوات السؤال',
      header: ExamHeaderModel.initial(subject: 'الرياضيات', schoolName: 'ثانوية'),
      settings: const PaperSettings(baseFontSize: 11, lineSpacing: 1.7, marginMm: 15),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'aq1',
          questionNumber: 1,
          statement: 'السؤال الأول: احسب قيمة المتغير في المعادلة التالية ثم بيّن خطوات الحل',
          body: 'متن قصير للسؤال الأول يقيس الفجوة بين العنوان والمتن.',
        ),
        QuestionModel(
          id: 'aq2',
          questionNumber: 2,
          statement: 'السؤال الثاني',
          body: 'متن قصير للسؤال الثاني.',
        ),
      ],
    );

Future<ExamWizardController> _pump(WidgetTester tester, ExamDocument document) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ExamWizardController(document: document);
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
  return controller;
}

Future<CanonicalPagePlan> _planOf(ExamDocument document) async {
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  final layout = await CanonicalLayoutService.resolve(
    document: controller.document,
    sourceIr: controller.documentIr,
  );
  return CanonicalPagePlan.fromLayout(layout);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => FlutterTextMetrics.ensureFontsLoaded());

  testWidgets('PROBE-ACTIONS', (tester) async {
    final controller = await _pump(tester, _document());
    final plan = await _planOf(controller.document);
    String f(double v) => v.toStringAsFixed(2);

    LayoutBlock? blockOf(String id) {
      for (final page in plan.layout.pages) {
        for (final block in page.blocks) {
          if (block.kind == LayoutBlockKind.question && block.semanticNodeId == id) {
            return block;
          }
        }
      }
      return null;
    }

    final block = blockOf('aq1')!;
    final title = block.children.firstWhere((c) => c.kind == LayoutBlockKind.title);
    final body = block.children.firstWhere((c) => c.kind == LayoutBlockKind.body);

    final statement = find.byKey(const ValueKey<String>('statement-aq1'));
    final bodyField = find.byKey(const ValueKey<String>('body-aq1'));
    final sRect = tester.getRect(statement);
    final bRect = tester.getRect(bodyField);

    final rowRect = tester.getRect(
      find.ancestor(of: statement, matching: find.byType(Row)).first,
    );
    final buttons = find.descendant(
      of: find.ancestor(of: statement, matching: find.byType(Row)).first,
      matching: find.byType(IconButton),
    );
    final heights = <String>[
      for (var i = 0; i < tester.widgetList(buttons).length; i++)
        f(tester.getRect(buttons.at(i)).height),
    ];
    final drag = find.byIcon(Icons.drag_indicator);

    // خطوط الخطة لعقدة منطوق السؤال نفسها، ومدى امتدادها الأفقي.
    final runs = <LayoutRun>[
      for (final line in block.allLines)
        ...line.runs.where((run) => run.semanticNodeId == 'aq1/title/statement/1'),
    ];
    final planLines = <String>{
      for (final line in block.allLines)
        if (line.runs.any((r) => r.semanticNodeId == 'aq1/title/statement/1')) line.id,
    }.length;
    final span = runs.isEmpty
        ? 0.0
        : runs
                .map((run) => run.x + run.advance)
                .reduce(math.max) -
            runs.map((run) => run.x).reduce(math.min);
    final editable = tester.state<EditableTextState>(
      find.descendant(of: statement, matching: find.byType(EditableText)),
    );
    final boxes = editable.renderEditable.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: editable.textEditingValue.text.length,
      ),
    );
    final renderedLines = boxes.length;
    expect('A row=${f(rowRect.height)}/${f(LayoutUnits.ptToPx(title.rect.height))}', 'P');
    expect('B stmtW=${f(sRect.width)} planSpan=${f(LayoutUnits.ptToPx(span))}', 'P');
    expect('C stmtLines=$renderedLines planLines=$planLines', 'P');
    expect('D gapBody=${f(bRect.top - rowRect.bottom)} planGap=${f(LayoutUnits.ptToPx(body.rect.top - title.rect.bottom))}', 'P');
    expect('E btns=${heights.join(",")} n=${heights.length}', 'P');
    expect('F drag=${drag.evaluate().isEmpty ? "none" : f(tester.getRect(drag.first).height)}', 'P');
  });
}
