import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../support/production_evidence_fonts.dart';
import 'package:writing_questions_app/views/widgets/visual_equation_editor.dart';

/// مضيف يفتح محرر المعادلات بزر ويلتقط المقطع الناتج.
class _EditorHost extends StatefulWidget {
  const _EditorHost({this.initialLatex, this.initialIsBlock = false});

  final String? initialLatex;
  final bool initialIsBlock;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  String? result;

  Future<void> _open() async {
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: widget.initialLatex,
      initialIsBlock: widget.initialIsBlock,
    );
    setState(() => result = snippet ?? '<cancelled>');
  }

  @override
  Widget build(BuildContext context) {
    // ملاحظة: MaterialApp تُبنى فوق المضيف في pumpWidget — سياق _open
    // يحتاج MaterialLocalizations عند فتح الحوار.
    return Scaffold(
      body: Column(
        children: <Widget>[
          TextButton(onPressed: _open, child: const Text('فتح المحرر')),
          Text('النتيجة: ${result ?? '—'}'),
        ],
      ),
    );
  }
}

List<String> _slotTexts(WidgetTester tester) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .map((field) => field.controller!.text)
      .toList(growable: false);
}

/// يضخ المضيف بنافذة اختبار طويلة: زر الإدراج أسفل الحوار يُقصّ
/// في نافذة 800×600 الافتراضية فيفشل النقر عليه.
Future<void> _pumpEditor(WidgetTester tester, Widget host, {double width = 900}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: host));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadProductionEvidenceFonts);
  for (final width in [320.0, 360.0]) {
    for (final block in [false, true]) {
      testWidgets('long compound scroll/edit/history preserves ${block ? "display" : "inline"} math at $width', (tester) async {
        const latex = r'\sqrt{\frac{a+b+c+d+e+f+g+h}{p+q}}+LONGTAIL';
        await _pumpEditor(tester, _EditorHost(initialLatex: latex, initialIsBlock: block), width: width);
        await tester.tap(find.text('فتح المحرر'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final viewport = find.byKey(const Key('eq_model_horizontal_scroll'));
        await tester.ensureVisible(viewport);
        await tester.pumpAndSettle();
        final scrollable = find.descendant(of: viewport, matching: find.byType(Scrollable)).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0), reason: 'Compound must have real reachable overflow, not shrink.');
        final before = position.pixels;
        final rect = tester.getRect(viewport);
        // Drag in the blank gutter above the scrollbar, not a text field's
        // independent cursor/selection or a scrollbar thumb at its boundary.
        await tester.dragFrom(Offset(rect.left + 2, rect.bottom - 10), const Offset(-160, 0));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(before));
        final tail = find.byType(TextField).last;
        await tester.ensureVisible(tail);
        await tester.pumpAndSettle();
        final original = tester.widget<TextField>(tail).controller!.text;
        expect(original, endsWith('LONGTAIL'));
        final changed = original.replaceFirst('LONGTAIL', 'NEWTAIL');
        await tester.tap(tail);
        await tester.enterText(tail, changed);
        await tester.pumpAndSettle();
        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
        await tap(find.byKey(const Key('eq_undo')));
        expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, original);
        await tap(find.byKey(const Key('eq_redo')));
        expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, changed);
        await tap(find.text('إدراج'));
        final delimiter = block ? r'$$' : r'$';
        expect(find.text('النتيجة: $delimiter${latex.replaceFirst("LONGTAIL", "NEWTAIL")}$delimiter'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  group('VisualEquationEditor', () {
    testWidgets('builds a fraction visually and inserts inline math', (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();
      expect(find.text('محرر المعادلات'), findsOneWidget);

      // بناء كسر من الشريط وملء خانتيه كتابةً.
      await tester.tap(find.text('كسر'));
      await tester.pumpAndSettle();
      final slots = find.byType(TextField);
      expect(slots, findsNWidgets(2));
      await tester.enterText(slots.at(0), 'a');
      await tester.enterText(slots.at(1), 'b');
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $\frac{a}{b}$'), findsOneWidget);
    });

    testWidgets('loads an existing formula for visual editing', (tester) async {
      await _pumpEditor(tester, const _EditorHost(initialLatex: r'\frac{1}{2}'));
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // المعادلة القديمة حُمّلت في خانات مرئية قابلة للتحرير.
      expect(_slotTexts(tester), containsAll(<String>['1', '2']));

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $\frac{1}{2}$'), findsOneWidget);
    });

    testWidgets('inserts symbols at the cursor with live structure', (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('x²'));
      await tester.pumpAndSettle();
      final slots = find.byType(TextField);
      expect(slots, findsNWidgets(2));
      // القاعدة ثم الدليل.
      await tester.enterText(slots.at(0), 'x');
      await tester.enterText(slots.at(1), '2');
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $x^{2}$'), findsOneWidget);
    });

    testWidgets('block mode wraps the result in double dollars', (tester) async {
      await _pumpEditor(tester, const _EditorHost(initialIsBlock: true));
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('√'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $$\sqrt{x}$$'), findsOneWidget);
    });

    testWidgets('cancelling returns null without a result', (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('النتيجة: <cancelled>'), findsOneWidget);
    });
  });
}
