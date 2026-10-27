import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/views/widgets/smart_exam_toolbar.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

/// Opens the initially hidden specialties through its real toggle. Functional
/// tests must navigate the UI, not call an insertion callback directly.
Future<void> openPreviewSpecialty(WidgetTester tester, String tab) async {
  if (find.byType(SmartExamToolbar).evaluate().isEmpty) {
    final toggle = find.descendant(
      of: find.byType(PreviewToolbar),
      matching: find.byTooltip('شريط الصيغ والوسائط'),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  final target = find.descendant(
    of: find.byType(TabBar), matching: find.text(tab),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Scrolls the active lazy command list before resolving and tapping its child.
/// ensureVisible alone cannot materialize an unbuilt ListView child at 320dp.
Future<void> tapPreviewCommand(WidgetTester tester, String tab, String label) async {
  await openPreviewSpecialty(tester, tab);
  final listKey = switch (tab) {
    'نص' => 'smart-text-commands',
    'وسائط' => 'smart-media-commands',
    'رياضيات' => 'smart-formula-commands-كسر',
    'كيمياء' => 'smart-formula-commands-ماء',
    'فيزياء' => 'smart-formula-commands-قوانين نيوتن',
    _ => throw ArgumentError.value(tab, 'tab'),
  };
  final list = find.byKey(ValueKey<String>(listKey));
  final element = find.descendant(of: list, matching: find.byType(Scrollable))
      .first.evaluate().single;
  final scrollable = find.byElementPredicate((candidate) => identical(candidate, element));
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  final command = find.descendant(of: list, matching: find.text(label));
  await tester.scrollUntilVisible(command, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
  expect(command, findsOneWidget);
  await tester.ensureVisible(command);
  await tester.pumpAndSettle();
  await tester.tap(command);
  await tester.pumpAndSettle();
}

Future<void> tapPreviewMedia(WidgetTester tester, String label) =>
    tapPreviewCommand(tester, 'وسائط', label);
