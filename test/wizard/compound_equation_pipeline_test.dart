import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/equation_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/views/widgets/mixed_content_editor.dart';
import 'package:writing_questions_app/views/widgets/safe_math_tex.dart';
import 'package:writing_questions_app/views/widgets/visual_equation_editor.dart';

class _RtlEquationDialogHost extends StatefulWidget {
  const _RtlEquationDialogHost({this.initialLatex});

  final String? initialLatex;

  @override
  State<_RtlEquationDialogHost> createState() => _RtlEquationDialogHostState();
}

class _RtlEquationDialogHostState extends State<_RtlEquationDialogHost> {
  String? saved;

  Future<void> _open() async {
    final res = await showVisualEquationEditor(
      context: context,
      initialLatex: widget.initialLatex,
    );
    setState(() => saved = res ?? '<cancelled>');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          TextButton(onPressed: _open, child: const Text('فتح المعادلة')),
          Text('المخرج: ${saved ?? '—'}'),
        ],
      ),
    );
  }
}

class _RtlMixedHost extends StatefulWidget {
  const _RtlMixedHost(this.initialSource);

  final String initialSource;

  @override
  State<_RtlMixedHost> createState() => _RtlMixedHostState();
}

class _RtlMixedHostState extends State<_RtlMixedHost> {
  String? saved;

  Future<void> _open() async {
    final res = await MixedContentEditor.show(
      context,
      source: saved ?? widget.initialSource,
    );
    if (res != null) {
      setState(() => saved = res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          TextButton(onPressed: _open, child: const Text('فتح المختلط')),
          Text('المتن: ${saved ?? widget.initialSource}'),
        ],
      ),
    );
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<void> _pumpRtlApp(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(960, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Issue 2 — Compound Equation Structured AST & Parser Invariants', () {
    test(
        'Scenario 1, 3, 7: compound exponents ("5^{2} + 6^{2} =") and roots ("\\sqrt{5} + \\sqrt{8} =") parse & round-trip without swallowing operators',
        () {
      // Pre-fix bug proof: previously `EquationModel.parse('5^{2} + 6^{2} =')`
      // swallowed `' + 6'` into the second exponent base producing `'5^{2}{ + 6}^{2} ='`!
      const powers = '5^{2} + 6^{2} =';
      final parsedPowers = EquationModel.parse(powers);
      expect(parsedPowers.toLatex(), powers);
      expect(parsedPowers.nodes, hasLength(4));
      expect(parsedPowers.nodes[0], isA<EqSup>());
      expect((parsedPowers.nodes[1] as EqText).text, ' + ');
      expect(parsedPowers.nodes[2], isA<EqSup>());
      expect((parsedPowers.nodes[3] as EqText).text, ' =');

      const roots = r'\sqrt{5} + \sqrt{8} =';
      final parsedRoots = EquationModel.parse(roots);
      expect(parsedRoots.toLatex(), roots);
      expect(parsedRoots.nodes, hasLength(4));
      expect(parsedRoots.nodes[0], isA<EqSqrt>());
      expect((parsedRoots.nodes[1] as EqText).text, ' + ');
      expect(parsedRoots.nodes[2], isA<EqSqrt>());
      expect((parsedRoots.nodes[3] as EqText).text, ' =');

      // Multi-character braced base `{x+1}^{2}` also round-trips cleanly without doubling braces!
      expect(EquationModel.parse('{x+1}^{2}').toLatex(), '{x+1}^{2}');
      expect(EquationModel.parse('{12}^{2} + {25}^{2} = 769').toLatex(),
          '{12}^{2} + {25}^{2} = 769');
    });

    test(
        'Scenario 4 & 10: AST component IDs, middle insert-before/insert-after/edit/delete, and legacy Unicode compatibility',
        () {
      // Legacy Unicode math strings (`5² + 6² =`, `√5 + √8 =`) load directly into structured AST nodes!
      final fromUnicodePowers = EquationModel.parse('5² + 6² =');
      expect(fromUnicodePowers.nodes[0], isA<EqSup>());
      expect(fromUnicodePowers.nodes[2], isA<EqSup>());
      expect(fromUnicodePowers.toLatex(), '5^{2} + 6^{2} =');

      final fromUnicodeRoots = EquationModel.parse('√5 + √8 =');
      expect(fromUnicodeRoots.nodes[0], isA<EqSqrt>());
      expect(fromUnicodeRoots.nodes[2], isA<EqSqrt>());
      expect(fromUnicodeRoots.toLatex(), r'\sqrt{5} + \sqrt{8} =');

      // Middle edit / insert before / insert after / delete with stable IDs:
      final model = EquationModel.parse(r'\sqrt{5}+\sqrt{99}+\sqrt{8}=');
      final middleRoot = model.nodes[2] as EqSqrt;
      final firstRootId = model.nodes[0].id;
      final lastRootId = model.nodes[4].id;

      // Insert before middle component:
      final beforeSlot =
          model.insertSlotBefore((middleRoot.body.single as EqText).id);
      beforeSlot.text = '2';
      expect(model.toLatex(), r'\sqrt{5}+2\sqrt{99}+\sqrt{8}=');

      // Delete middle `\sqrt{99}` cleanly:
      final midLoc = model.locateById(middleRoot.id)!;
      final refocus =
          model.removeComponentAndRefocus(midLoc.parentList, midLoc.index);
      expect(refocus.focus, isNotNull);
      // Neighboring IDs of untouched components stay 100% identical!
      expect(model.nodes.first.id, firstRootId);
      expect(model.locateById(lastRootId), isNotNull);
      refocus.focus!.text = '+';
      expect(model.toLatex(), r'\sqrt{5}+\sqrt{8}=');
    });

    test(
        'Scenario 7: ExamDocument JSON save + reopen preserves compound equations identically',
        () {
      final doc = ExamDocument(
        id: 'eq-save-reopen',
        name: 'اختبار المعادلات المركبة',
        header: ExamHeaderModel.initial(),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'q1',
            questionNumber: 1,
            statement: r'أ ) احسب قيمة $\sqrt{5}+\sqrt{8}=$ و$5^{2}+6^{2}=$ بدقة.',
            items: <BranchItem>[
              BranchItem(
                id: 'i1',
                text:
                    r'حل المعادلة $\frac{\sqrt{5}+1}{2}+3^{2}=\left(x+1\right)^{2}$ في مجموعة الأعداد الحقيقية.',
              ),
            ],
          ),
        ],
      );
      final jsonRoundTrip = ExamDocument.fromJson(doc.toJson());
      expect(jsonRoundTrip.questions.single.statement,
          doc.questions.single.statement);
      expect(jsonRoundTrip.questions.single.items.single.text,
          doc.questions.single.items.single.text);
    });
  });

  group('Issue 2 — VisualEquationEditor Widget Lifecycle in Real RTL App Context', () {
    testWidgets(
        'Scenario 2A: builds "\\sqrt{5}+\\sqrt{8}=" smoothly in RTL app with strict left-to-right visual coordinates',
        (tester) async {
      await _pumpRtlApp(tester, const _RtlEquationDialogHost());
      await tester.tap(find.text('فتح المعادلة'));
      await tester.pumpAndSettle();

      // 1. Add first root √5
      await tester.tap(find.text('√'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.pumpAndSettle();

      // Verify inside RTL app that '√' symbol sits STRICTLY TO THE LEFT of its radicand TextField!
      final sqrtSymbolDx = tester.getTopLeft(find.text('√').last).dx;
      final bodyFieldDx = tester.getTopLeft(find.byType(TextField).first).dx;
      expect(sqrtSymbolDx, lessThan(bodyFieldDx),
          reason:
              'Inside Arabic RTL app, √ glyph ($sqrtSymbolDx) must sit to the LEFT of radicand slot ($bodyFieldDx), never reversed as "5√"!');

      // 2. Step out of √5 -> add '+' -> add second √8 -> step out -> add '='
      await tester.tap(find.byKey(const Key('eq_nav_next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('√'));
      await tester.pumpAndSettle();
      // Active focus automatically moved inside the second root!
      final activeFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList(growable: false);
      expect(activeFields.last.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField).last, '8');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('eq_nav_next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      // Verify ALL 4 visual slots increase strictly left-to-right on screen:
      // [5] < [+] < [8] < [=] even inside `Directionality.rtl`!
      final allFields = find.byType(TextField);
      expect(allFields, findsNWidgets(4));
      final xs = <double>[
        for (var i = 0; i < 4; i++) tester.getTopLeft(allFields.at(i)).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
      expect(xs[2], lessThan(xs[3]));

      // Live preview widget exists and renders without fallback error!
      expect(find.byType(SafeMathTex), findsOneWidget);

      await _tapVisible(tester, find.text('إدراج'));
      expect(find.text(r'المخرج: $\sqrt{5}+\sqrt{8}=$'), findsOneWidget);
    });

    testWidgets(
        'Scenario 2B: builds "5^{2}+6^{2}=" naturally by typing base "5" -> tapping "x²" -> typing "2" -> stepping out via ArrowRight / button',
        (tester) async {
      await _pumpRtlApp(tester, const _RtlEquationDialogHost());
      await tester.tap(find.text('فتح المعادلة'));
      await tester.pumpAndSettle();

      // Tap canvas to begin typing `5`, then tap `x²` directly!
      await tester.tap(
        find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.pumpAndSettle();

      // Tapping `x²` with cursor after `5` captures `5` as base and focuses exponent!
      await _tapVisible(tester, find.text('x²'));
      expect(find.byType(TextField), findsNWidgets(2));
      // Base slot is on the LEFT, exponent slot is on the RIGHT (even in RTL locale!):
      expect(
        tester.getTopLeft(find.byType(TextField).at(0)).dx,
        lessThan(tester.getTopLeft(find.byType(TextField).at(1)).dx),
      );
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.pumpAndSettle();

      // Exit exponent using keyboard Right Arrow key!
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Type `+6` directly into the new top-level sibling slot, tap `x²`, type `2`!
      await tester.enterText(find.byType(TextField).last, '+6');
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('x²'));
      await tester.enterText(find.byType(TextField).last, '2');
      await tester.pumpAndSettle();

      // Step out and tap `=`!
      await _tapVisible(tester, find.byKey(const Key('eq_nav_next')));
      await _tapVisible(tester, find.text('='));

      await _tapVisible(tester, find.text('إدراج'));
      expect(find.text(r'المخرج: $5^{2}+6^{2}=$'), findsOneWidget);
    });

    testWidgets(
        'Scenario 4, 5, 11: long multi-part equation middle editing, deletion, undo/redo, and cursor stability without controller crashes',
        (tester) async {
      await _pumpRtlApp(
        tester,
        const _RtlEquationDialogHost(
          initialLatex:
              r'\frac{1}{2}+\sqrt{5}+5^{2}+\left(x+1\right)+6^{2}=\sqrt{61}',
        ),
      );
      await tester.tap(find.text('فتح المعادلة'));
      await tester.pumpAndSettle();

      // Focus middle `5^{2}` base slot (`'5'`) and edit it to `'7'`, verifying cursor stays in that slot!
      final fiveFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '5',
      );
      // Both `\sqrt{5}` and `5^{2}` contain `'5'`; pick the second one (`5^{2}` base).
      await tester.tap(fiveFieldFinder.at(1));
      await tester.pumpAndSettle();
      await tester.enterText(fiveFieldFinder.at(1), '7');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                  (w) => w is TextField && w.controller?.text == '7'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
        reason: 'Cursor & focus must remain inside the edited middle slot',
      );

      // Focus inside `\left(x+1\right)` and delete that active component cleanly via toolbar!
      final fenceBody = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'x+1',
      );
      await tester.tap(fenceBody);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const Key('eq_delete_active')));
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'x+1'),
        findsNothing,
      );

      // Undo restores `\left(x+1\right)`, Redo removes it again cleanly!
      await _tapVisible(tester, find.byKey(const Key('eq_undo')));
      expect(
        find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'x+1'),
        findsOneWidget,
      );
      await _tapVisible(tester, find.byKey(const Key('eq_redo')));
      expect(
        find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'x+1'),
        findsNothing,
      );

      await _tapVisible(tester, find.text('إدراج'));
      expect(
        find.text(r'المخرج: $\frac{1}{2}+\sqrt{5}+7^{2}++6^{2}=\sqrt{61}$'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Scenario 6 & 12: compound equation inside Arabic RTL sentence with parentheses in MixedContentEditor saves and reopens cleanly',
        (tester) async {
      await _pumpRtlApp(
        tester,
        const _RtlMixedHost('أ ) جد ناتج العبارة (الأولى): '),
      );
      await tester.tap(find.text('فتح المختلط'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('إضافة معادلة'));

      await _tapVisible(tester, find.text('√'));
      final mathSlots = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '?',
      );
      await tester.enterText(mathSlots.first, '5');
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const Key('eq_nav_next')));
      await _tapVisible(tester, find.text('+'));
      await _tapVisible(tester, find.text('√'));
      await tester.enterText(mathSlots.last, '8');
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const Key('eq_nav_next')));
      await _tapVisible(tester, find.text('='));

      await _tapVisible(tester, find.text('حفظ المحتوى'));
      expect(
        find.text(r'المتن: أ ) جد ناتج العبارة (الأولى): $\sqrt{5}+\sqrt{8}=$'),
        findsOneWidget,
      );

      // Reopen saved Arabic + parentheses + compound equation in MixedContentEditor:
      await tester.tap(find.text('فتح المختلط'));
      await tester.pumpAndSettle();
      expect(find.byType(SafeMathTex), findsOneWidget);
      await _tapVisible(tester, find.text('حفظ المحتوى'));
      expect(
        find.text(r'المتن: أ ) جد ناتج العبارة (الأولى): $\sqrt{5}+\sqrt{8}=$'),
        findsOneWidget,
      );
    });
  });
}
