import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextButton(onPressed: _open, child: const Text('فتح المحرر')),
            Text('النتيجة: ${result ?? '—'}'),
          ],
        ),
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

void main() {
  group('VisualEquationEditor', () {
    testWidgets('builds a fraction visually and inserts inline math', (tester) async {
      await tester.pumpWidget(const _EditorHost());
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
      await tester.pumpWidget(const _EditorHost(initialLatex: r'\frac{1}{2}'));
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // المعادلة القديمة حُمّلت في خانات مرئية قابلة للتحرير.
      expect(_slotTexts(tester), containsAll(<String>['1', '2']));

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $\frac{1}{2}$'), findsOneWidget);
    });

    testWidgets('inserts symbols at the cursor with live structure', (tester) async {
      await tester.pumpWidget(const _EditorHost());
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
      await tester.pumpWidget(const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('منفردة'));
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
      await tester.pumpWidget(const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('النتيجة: <cancelled>'), findsOneWidget);
    });
  });
}
