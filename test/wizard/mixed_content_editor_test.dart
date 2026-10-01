// اختبار محرر المحتوى المختلط (منطوق السؤال/الفرع وكل إدخال نصي):
// النص الرئيسي واحد لا يتجزأ ولا يُحذف، وبلا زر «إضافة نص» — والمعادلة
// تُغرَس عند مؤشر الكتابة داخله، وحذفها يعيد دمج النص حوله.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/views/widgets/mixed_content_editor.dart';

class _Host extends StatefulWidget {
  const _Host(this.source);

  final String source;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? result;

  Future<void> _open() async {
    final saved = await MixedContentEditor.show(context, source: widget.source);
    setState(() => result = saved ?? '<cancelled>');
  }

  @override
  Widget build(BuildContext context) {
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

Future<void> _pumpHost(WidgetTester tester, String source) async {
  tester.view.physicalSize = const Size(900, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: _Host(source)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('فتح المحرر'));
  await tester.pumpAndSettle();
}

Finder _editorFields() => find.descendant(
      of: find.byType(MixedContentEditor),
      matching: find.byType(TextField),
    );

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('حفظ المحتوى'));
  await tester.pumpAndSettle();
}

void main() {
  group('MixedContentEditor', () {
    testWidgets('لا زر «إضافة نص»: النص الرئيسي واحد والمعادلات تُضاف إليه',
        (tester) async {
      await _pumpHost(tester, 'احسب ثم أجب');

      expect(find.text('إضافة نص'), findsNothing);
      expect(find.text('إضافة معادلة'), findsOneWidget);
      expect(find.text('النص الرئيسي'), findsOneWidget);

      await tester.enterText(_editorFields().first, 'احسب قيمة ك');
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة معادلة'));
      await tester.pumpAndSettle();

      // المعادلة أُلحقت عند المؤشر (نهاية النص): خانة نص واحدة + معادلة.
      expect(_editorFields(), findsOneWidget);
      expect(find.text('معادلة سطرية'), findsOneWidget);

      await _save(tester);
      expect(find.text('النتيجة: احسب قيمة ك'), findsOneWidget);
    });

    testWidgets('يدرج المعادلة عند المؤشر تماماً ويقسم النص حولها',
        (tester) async {
      await _pumpHost(tester, 'abcd');

      final controller = tester.widget<TextField>(_editorFields().first).controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await tester.tap(find.text('إضافة معادلة'));
      await tester.pumpAndSettle();
      expect(_editorFields(), findsNWidgets(2));
      expect(tester.widget<TextField>(_editorFields().at(0)).controller!.text, 'ab');
      expect(tester.widget<TextField>(_editorFields().at(1)).controller!.text, 'cd');

      // ملء المعادلة في محررها المرئي المضمَّن.
      await tester.tap(find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'));
      await tester.pumpAndSettle();
      await tester.enterText(_editorFields().last, 'x');
      await tester.pumpAndSettle();

      await _save(tester);
      expect(find.text(r'النتيجة: ab$x$cd'), findsOneWidget);
    });

    testWidgets('حذف المعادلة يدمج النص حولها قسماً واحداً متصلاً',
        (tester) async {
      await _pumpHost(tester, r'أ $\frac{1}{2}$ ب');

      expect(find.text('النص الرئيسي'), findsOneWidget);
      expect(find.text('تكملة النص'), findsOneWidget);

      await tester.tap(find.byTooltip('حذف المعادلة'));
      await tester.pumpAndSettle();

      expect(find.text('تكملة النص'), findsNothing);
      expect(_editorFields(), findsOneWidget);
      expect(tester.widget<TextField>(_editorFields().first).controller!.text, 'أ  ب');

      await _save(tester);
      expect(find.text('النتيجة: أ  ب'), findsOneWidget);
    });

    testWidgets('مصدر معادلة خالصة يُفتح بخانة نص قابلة للكتابة حولها',
        (tester) async {
      await _pumpHost(tester, r'$x^{2}$');

      expect(_editorFields(), findsOneWidget);
      expect(find.text('معادلة سطرية'), findsOneWidget);

      await tester.enterText(_editorFields().first, 'احسب');
      await tester.pumpAndSettle();
      await _save(tester);
      expect(find.text(r'النتيجة: $x^{2}$احسب'), findsOneWidget);
    });

    testWidgets('الإلغاء لا يغيّر المصدر', (tester) async {
      await _pumpHost(tester, r'نص $\times$');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('النتيجة: <cancelled>'), findsOneWidget);
    });
  });
}
