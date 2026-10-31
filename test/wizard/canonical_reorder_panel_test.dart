import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/canonical_reorder_panel.dart';

ExamDocument _document() => ExamDocument(name: 'Concurrent reorder',
  header: ExamHeaderModel.initial(subject: 'English'), questions: [
    QuestionModel(id: 'qa', questionNumber: 1, statement: 'ALPHA', branches: [
      BranchModel(id: 'ba', content: BranchContent(statement: 'BALPHA'))]),
    QuestionModel(id: 'qb', questionNumber: 2, statement: 'BETA', branches: [
      BranchModel(id: 'bb', content: BranchContent(statement: 'BBETA'))]),
  ]);

Future<void> _mount(WidgetTester tester, ExamWizardController controller, {bool locked = false}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnimatedBuilder(animation: controller,
    builder: (context, _) => CanonicalReorderPanel(controller: controller, locked: locked,
      onClose: () {}, onChanged: () {})))));
  await tester.pumpAndSettle();
}

Finder _handle(String id) => find.byKey(ValueKey<String>('canonical-drag-$id'));
Finder _target(String id) => find.byKey(ValueKey<String>('canonical-drop-$id'));
Future<TestGesture> _start(WidgetTester tester, String id) async {
  final gesture = await tester.startGesture(tester.getRect(_handle(id)).topLeft + const Offset(1, 1));
  await tester.pump(const Duration(milliseconds: 650));
  return gesture;
}

void main() {
  testWidgets('stable branch identity survives question reorder DURING actual drag', (tester) async {
    final c = ExamWizardController(document: _document());
    await _mount(tester, c);
    final gesture = await _start(tester, 'ba');
    c.moveQuestion(0, 1); // Concurrent mutation, NOT a substitute for the tested drag.
    await tester.pumpAndSettle();
    await gesture.moveTo(tester.getCenter(_target('bb')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up(); await tester.pumpAndSettle();
    expect(c.questions.map((q) => q.id), ['qb','qa']);
    expect(c.questions[0].branches.single.content.statement, 'BALPHA');
    expect(c.questions[1].branches.single.content.statement, 'BBETA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletion during drag cannot act on a reused positional index', (tester) async {
    final c = ExamWizardController(document: _document());
    await _mount(tester, c);
    final gesture = await _start(tester, 'ba');
    c.removeQuestion(0);
    await tester.pumpAndSettle();
    final afterDeletion = jsonEncode(c.document.toMap());
    await gesture.moveTo(tester.getCenter(_target('bb')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up(); await tester.pumpAndSettle();
    expect(jsonEncode(c.document.toMap()), afterDeletion);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long native list auto-scrolls during real drag to last question', (tester) async {
    final c = ExamWizardController(document: ExamDocument(name: 'Long reorder',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: [for (var i = 0; i < 30; i++) QuestionModel(id: 'q$i', questionNumber: i + 1, statement: 'TOKEN$i')]));
    await _mount(tester, c);
    final gesture = await _start(tester, 'q0');
    final list = find.descendant(of: find.byType(CanonicalReorderPanel), matching: find.byType(ListView));
    final window = tester.getRect(list);
    await gesture.moveTo(Offset(window.center.dx, window.bottom - 1));
    var reachable = false;
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (_target('q29').evaluate().isEmpty) continue;
      final rect = tester.getRect(_target('q29'));
      if (rect.top >= window.top && rect.bottom <= window.bottom) { reachable = true; break; }
    }
    expect(reachable, isTrue, reason: 'The last FULL48dp handle must be reachable, not a partially clipped cache child.');
    await gesture.moveTo(tester.getCenter(_target('q29')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up(); await tester.pumpAndSettle();
    expect(c.questions.last.id, 'q0');
    expect(c.questions, hasLength(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('outside cancellation stops edge scroll after source row is recycled', (tester) async {
    final c = ExamWizardController(document: ExamDocument(name: 'Cancel long reorder',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: [for (var i = 0; i < 30; i++)
        QuestionModel(id: 'q$i', questionNumber: i + 1, statement: 'TOKEN$i')]));
    await _mount(tester, c);
    final original = jsonEncode(c.document.toMap());
    final gesture = await _start(tester, 'q0');
    final list = find.descendant(of: find.byType(CanonicalReorderPanel), matching: find.byType(ListView));
    final window = tester.getRect(list);
    await gesture.moveTo(Offset(window.center.dx, window.bottom - 1));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(_handle('q0'), findsNothing, reason: 'Must actually recycle the original source row.');
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, greaterThan(300));
    expect(position.pixels, lessThan(position.maxScrollExtent));
    await gesture.moveTo(window.center);
    final centredAt = position.pixels;
    await tester.pump(const Duration(seconds: 1));
    expect(position.pixels, centredAt,
      reason: 'A recycled source must not leave an obsolete edge pointer while dragging inside.');
    await gesture.moveTo(const Offset(319, 650)); // Outside the native panel.
    await gesture.up();
    final stoppedAt = position.pixels;
    await tester.pump(const Duration(seconds: 1));
    expect(position.pixels, stoppedAt, reason: 'No orphaned timer may scroll after cancellation.');
    expect(jsonEncode(c.document.toMap()), original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked native handles do not mutate model', (tester) async {
    final c = ExamWizardController(document: _document());
    await _mount(tester, c, locked: true);
    final original = jsonEncode(c.document.toMap());
    final gesture = await _start(tester, 'qa');
    await gesture.moveTo(tester.getCenter(_target('qb')));
    await gesture.up(); await tester.pumpAndSettle();
    expect(jsonEncode(c.document.toMap()), original);
    expect(tester.takeException(), isNull);
  });
}
