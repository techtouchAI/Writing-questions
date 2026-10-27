// Production gestures, not model-command substitutes. Candidate stays OFF.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
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
    final image = await box.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(data!.buffer.asUint8List());
    } finally { image.dispose(); }
  });
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
      for (final ending in ['before.png', 'after.png', 'after.pdf']) 'drag-$width-$kind-$ending'];
  setUpAll(() {
    Directory(_out).createSync(recursive: true);
    File('$_out/editing-manifest.json').writeAsStringSync(jsonEncode({
      'files': files, 'results': results, 'manualVisualReview': false,
      'surface': 'production default; candidate OFF',
    }));
  });
  for (final width in [320.0, 360.0]) {
    for (final kind in ['question', 'branch-within', 'branch-between']) {
      testWidgets('real $kind drag, history and actual live-plan PDF at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _Observed(document: _document());
        addTearDown(controller.dispose);
        await tester.pumpWidget(RepaintBoundary(key: const ValueKey('reorder-screen'),
          child: MaterialApp(home: ChangeNotifierProvider<ExamWizardController>.value(
            value: controller, child: ExamPreviewScreen(onBackToQuestions: () {})))));
        for (var i = 0; i < 500 && controller.plan == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        await tester.pumpAndSettle();
        await _history(tester, 'ملاءمة الورقة للشاشة');
        expect(controller.plan, isNotNull);
        expect(identical(controller.plan!.layout.source, controller.documentIr), isTrue);
        final original = jsonEncode(controller.document.toMap());
        final beforePlan = controller.plan!.layout;
        final base = 'drag-${width.toInt()}-$kind';
        Directory(_out).createSync(recursive: true);
        await _capture(tester, '$_out/$base-before.png');

        Finder question(int index) => find.byWidgetPredicate((w) => w is LongPressDraggable<int> && w.data == index);
        Finder branch(int q, int b) => find.byWidgetPredicate((w) => w is LongPressDraggable<BranchRef> &&
          w.data?.questionIndex == q && w.data?.branchIndex == b);
        final source = kind == 'question' ? question(1) : branch(0, kind == 'branch-within' ? 1 : 0);
        final destination = kind == 'question' ? question(0) : branch(kind == 'branch-between' ? 1 : 0, 0);
        expect(source, findsOneWidget);
        expect(destination, findsOneWidget);
        final from = _center(tester, source), to = _center(tester, destination);
        final gesture = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 650));
        for (var step = 1; step <= 10; step++) {
          await gesture.moveTo(Offset.lerp(from, to, step / 10)!);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await gesture.up();
        await tester.pumpAndSettle();
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
          final words = PdfContentProbe.fromBytes(bytes, pageIndex: page).words;
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
        await _capture(tester, '$_out/$base-after.png');
        await _history(tester, 'تراجع');
        expect(jsonEncode(controller.document.toMap()), original);
        await _history(tester, 'إعادة');
        expect(jsonEncode(controller.document.toMap()), changed);
        expect(tester.takeException(), isNull);
        results.add({'widthDp': width, 'kind': kind, 'realLongPressDrag': true,
          'from': [from.dx, from.dy], 'to': [to.dx, to.dy],
          'modelBefore': jsonDecode(original), 'modelAfter': jsonDecode(changed),
          'pdfTokens': emitted, 'undoRestoresOriginal': true, 'redoRestoresChanged': true,
          'pdfUsesObservedLivePlan': true, 'pdfCoordinatesVerified': true});
        File('$_out/editing-manifest.json').writeAsStringSync(jsonEncode({
          'files': files, 'results': results, 'manualVisualReview': false,
          'surface': 'production default; candidate OFF',
        }));
      });
    }
  }
}
