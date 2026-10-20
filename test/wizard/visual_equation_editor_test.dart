import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/equation_model.dart';
import 'package:writing_questions_app/models/tex_content.dart';
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
Future<void> _pumpEditor(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: host));
  await tester.pumpAndSettle();
}

void main() {
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

  // ---------------------------------------------------------------------
  // انحدار: المعادلات المركبة متعددة المكوّنات.
  //
  // كان كل إدراج يندرج داخل الخانة النشطة — فأثناء تحرير محتوى
  // جذر، اندرج العامل التالي داخل الجذر («√5 + √8» تولد
  // «√(5+)»)، وكان الأس بلا تحديد يترك قاعدته فارغة («5» ثم
  // «x²» تولد «5» و«²» فارغة لا «5²»). فتحة الإلحاق تُرجع
  // الإدراج إلى مستوى المعادلة، و«آخر محرف قبل المؤشر» يصير
  // قاعدة الأس.
  // ---------------------------------------------------------------------
  group('compound equations — explicit component sequence', () {
    Future<void> typeInLastSlot(WidgetTester tester, String text) async {
      final slots = find.byType(TextField);
      final count = slots.evaluate().length;
      expect(count, greaterThan(0));
      await tester.enterText(slots.at(count - 1), text);
      await tester.pumpAndSettle();
    }

    Future<void> appendComponent(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('equation-append-slot')),
      );
      await tester.pumpAndSettle();
    }

    /// يبني متتالية مكوّنات علوية من نصوص: الأول يُكتب في
    /// الخانة التي يخلقها الموضع الفارغ، وكل لاحقٍ يُلحق
    /// بفتحة الإلحاق — فلا تبقى خانة أولى فارغة.
    Future<void> buildTopLevelSequence(
      WidgetTester tester,
      List<String> pieces,
    ) async {
      await tester.tap(
        find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'),
      );
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, pieces.first);
      for (final piece in pieces.sublist(1)) {
        await appendComponent(tester);
        await typeInLastSlot(tester, piece);
      }
    }

    testWidgets('builds √5 + √8 = with operators at top level',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // جذر أوّل ومحتواه.
      await tester.tap(find.widgetWithText(InkWell, '√'));
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '5');

      // مكوّن علوي جديد ثم العملية — لا تندرج داخل الجذر.
      await appendComponent(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      // جسم الجذر الأول بقي «5» وحده: العملية ليست داخله.
      expect(_slotTexts(tester), <String>['5', '+']);

      // جذر ثانٍ ومحتواه.
      await tester.tap(find.widgetWithText(InkWell, '√'));
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '8');

      // علامة المساواة مكوّناً علوياً.
      await appendComponent(tester);
      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $\sqrt{5}+\sqrt{8}=$'), findsOneWidget);
    });

    testWidgets('builds 5² + 6² = taking the base from the typed digit',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // «5» ثم x²: القاعدة «5» تُرفع لا تُترك جانباً.
      await tester.tap(
        find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'),
      );
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '5');
      await tester.tap(find.text('x²'));
      await tester.pumpAndSettle();
      // قاعدة غير فارغة ودليل فارغ يُنتظر ملؤه.
      expect(_slotTexts(tester), <String>['5', '']);
      await typeInLastSlot(tester, '2');

      await appendComponent(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      await appendComponent(tester);
      await typeInLastSlot(tester, '6');
      await tester.tap(find.text('x²'));
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '2');

      await appendComponent(tester);
      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $5^{2}+6^{2}=$'), findsOneWidget);
    });

    testWidgets('a selected base is kept whole by x²', (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'),
      );
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, 'x+1');

      // تحديد كل النص ثم x²: القاعدة كاملة بين قوسين.
      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.pumpAndSettle();
      // تحديد كامل النص عبر لوحة المفاتيح البرمجية.
      final controller =
          tester.widget<TextField>(field).controller!;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.tap(find.text('x²'));
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '2');

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      // قاعدة مركبة → {x+1}^{2}.
      expect(find.text(r'النتيجة: ${x+1}^{2}$'), findsOneWidget);
    });

    testWidgets('editing a component keeps its neighbours intact',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // x + y بثلاثة مكوّنات علوية.
      await buildTopLevelSequence(tester, <String>['x', '+', 'y']);
      expect(_slotTexts(tester), <String>['x', '+', 'y']);

      // تعديل المكوّن الأوسط من «+» إلى «-».
      await tester.tap(find.byType(TextField).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '-');
      await tester.pumpAndSettle();
      expect(_slotTexts(tester), <String>['x', '-', 'y']);

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $x-y$'), findsOneWidget);
    });

    testWidgets('deleting the last component spares its neighbours',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();
      await buildTopLevelSequence(tester, <String>['x', '+', 'y']);

      // حذف الأخير يزيل «y» فقط.
      await tester.tap(find.text('⌫ حذف الأخير'));
      await tester.pumpAndSettle();
      expect(_slotTexts(tester), <String>['x', '+']);

      // ثم إلحاق مكوّن جديد بعده.
      await appendComponent(tester);
      await typeInLastSlot(tester, 'z');
      expect(_slotTexts(tester), <String>['x', '+', 'z']);

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $x+z$'), findsOneWidget);
    });

    testWidgets('a long expression keeps every component in order',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // تعبير طويل: أرقام وعمليات متعاقبة.
      await buildTopLevelSequence(
        tester,
        <String>['1', '+', '2', '+', '3', '+', '4'],
      );
      expect(
        _slotTexts(tester),
        <String>['1', '+', '2', '+', '3', '+', '4'],
      );

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $1+2+3+4$'), findsOneWidget);
    });

    testWidgets('repeated structure insertion does not duplicate or lose',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      // جذران متتاليان بمحتويين مختلفين.
      for (final radicand in <String>['a', 'b']) {
        await tester.tap(find.widgetWithText(InkWell, '√'));
        await tester.pumpAndSettle();
        await typeInLastSlot(tester, radicand);
        await appendComponent(tester);
      }
      // الجذران باقيان بمحتويهما لا مكرَّران ولا مدمجان:
      // خانة كل جذر تحمل محتواه وحده قبل الإدراج.
      expect(_slotTexts(tester).where((t) => t == 'a').length, 1);
      expect(_slotTexts(tester).where((t) => t == 'b').length, 1);

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      // ولا «+» اختفت ولا محتوى تضاعف في المقطع المخزَّن.
      expect(find.text(r'النتيجة: $\sqrt{a}\sqrt{b}$'),
          findsOneWidget);
    });

    testWidgets('inserting a structure before a component keeps '
        'the order', (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();
      await buildTopLevelSequence(tester, <String>['x', '+', 'y']);
      expect(_slotTexts(tester), <String>['x', '+', 'y']);

      // المؤشر في بداية «y» ثم جذر: يُدرَج قبلها على مستوى
      // المعادلة لا داخلها.
      final yField = find.byType(TextField).last;
      await tester.tap(yField);
      await tester.pumpAndSettle();
      tester.widget<TextField>(yField).controller!.selection =
          const TextSelection.collapsed(offset: 0);
      await tester.tap(find.widgetWithText(InkWell, '√'));
      await tester.pumpAndSettle();
      // الترتيب: x، +، جسم الجذر (فارغ)، y.
      expect(_slotTexts(tester), <String>['x', '+', '', 'y']);

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $x+\sqrt{}y$'), findsOneWidget);
    });

    testWidgets('deleting a middle structure spares its neighbours',
        (tester) async {
      await _pumpEditor(tester, const _EditorHost());
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.'),
      );
      await tester.pumpAndSettle();
      for (final radicand in <String>['a', 'b', 'c']) {
        await tester.tap(find.widgetWithText(InkWell, '√'));
        await tester.pumpAndSettle();
        await typeInLastSlot(tester, radicand);
        await appendComponent(tester);
      }
      expect(_slotTexts(tester), <String>['a', 'b', 'c', '']);

      // حذف الجذر الأوسط (√b) بزره الأحمر.
      await tester.tap(find.byIcon(Icons.close).at(1));
      await tester.pumpAndSettle();
      expect(_slotTexts(tester), <String>['a', 'c', '']);

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      expect(find.text(r'النتيجة: $\sqrt{a}\sqrt{c}$'),
          findsOneWidget);
    });

    testWidgets('works inside an Arabic RTL directionality',
        (tester) async {
      await _pumpEditor(
        tester,
        const Directionality(
          textDirection: TextDirection.rtl,
          child: _EditorHost(),
        ),
      );
      await tester.tap(find.text('فتح المحرر'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, '√'));
      await tester.pumpAndSettle();
      await typeInLastSlot(tester, '5');
      await appendComponent(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await appendComponent(tester);
      await typeInLastSlot(tester, '=');

      await tester.tap(find.text('إدراج'));
      await tester.pumpAndSettle();
      // الرياضيات LTR داخل السياق العربي RTL — بلا انعكاس.
      expect(find.text(r'النتيجة: $\sqrt{5}+=$'), findsOneWidget);
    });
  });

  group('EquationModel round-trip (save → reopen)', () {
    test('compound structure and order survive the round-trip', () {
      const latex = r'\sqrt{5}+\sqrt{8}=';
      final model = EquationModel.parse(latex);
      // أربعة مكوّنات علوية بالترتيب: جذر، عملية، جذر، مساواة.
      expect(model.nodes, hasLength(4));
      expect(model.nodes[0], isA<EqSqrt>());
      expect(model.nodes[1], isA<EqText>());
      expect(model.nodes[2], isA<EqSqrt>());
      expect(model.nodes[3], isA<EqText>());
      expect(model.toLatex(), latex);
    });

    test('powers compound round-trips with base and exponent', () {
      const latex = r'x^{2}y^{3}=';
      final model = EquationModel.parse(latex);
      // حرفان بأسّين: قاعدة كل أسّ محرفه وحده
      // (قاعدة «آخر وحدة» في المحلل)، فالمستوى
      // الجذري ثلاث عقد: أسّ، أسّ، نص.
      expect(model.nodes, hasLength(3));
      expect(model.nodes[0], isA<EqSup>());
      expect((model.nodes[0] as EqSup).base.single, isA<EqText>());
      expect((model.nodes[0] as EqSup).exponent.single, isA<EqText>());
      expect(model.nodes[1], isA<EqSup>());
      expect(model.nodes[2], isA<EqText>());
      // والجولة تُطابق المصدر بايتاً بايتاً.
      expect(model.toLatex(), latex);
      // وعاملٌ بين أسّين يطوى قاعدة الأس الثاني
      // (سلوك المحلل القائم لا يمسّه الإصلاح) وتُعيد
      // تسلسلتها بثبات تام لا يزيد عليه حفظٌ ثانٍ.
      const folded = r'5^{2}+6^{2}=';
      final foldedModel = EquationModel.parse(folded);
      expect(foldedModel.nodes, hasLength(3));
      expect(foldedModel.toLatex(), r'5^{2}{+6}^{2}=');
    });

    test('legacy single-string equations stay editable', () {
      // صيغ قديمة بلا بنية — تُفتح لا تُرمى، ويبقى
      // محتواها قابلاً للقراءة والتحرير.
      for (final legacy in <String>[
        r'\alpha + \beta',
        r'\int x \, dx',
        r'\sum_{i=1}^{n} i',
      ]) {
        final model = EquationModel.parse(legacy);
        expect(model.toLatex(), isNotEmpty);
        expect(EquationModel.readableText(legacy), isNotEmpty);
      }
      // ولا خسارة في المعادلات البسيطة بلا أسس:
      // التحليل ثم التوليد يُطابق المصدر بايتاً بايتاً.
      expect(
        EquationModel.parse(r'\alpha + \beta').toLatex(),
        r'\alpha + \beta',
      );
    });

    test('equation brackets inside Arabic text never touch the text', () {
      // المعادلة مخزّنة LaTeX LTR داخل نص عربي — لا BiDi
      // تطبَّق على المحتوى الرياضي ولا على النص العربي.
      const source = r'نص $\\sqrt{(x+1)}$ نص';
      final segments = TexContent.split(source);
      expect(segments, hasLength(3));
      expect(segments[0].text, 'نص ');
      expect(segments[1].text, r'\\sqrt{(x+1)}');
      expect(segments[2].text, ' نص');
      // ولنص المعادلة مقروءٌ بلا كود ولا فقدان للأقواس.
      expect(
        EquationModel.readableText(r'\sqrt{(x+1)}'),
        '√((x+1))',
      );
    });
  });
}
