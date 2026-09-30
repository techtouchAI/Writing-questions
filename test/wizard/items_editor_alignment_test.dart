import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/views/widgets/items_editor.dart';

/// محرر النقاط: تسلسل تلقائي، **خيار إجابة واحد** لكل عبارة صح/خطأ، وبلا
/// أزرار ترتيب — مع الحفاظ على النص المكتوب.
void main() {
  /// يبني المحرر مع حالة محيطة تُعيد البناء بعد كل تعديل (كما في الشاشات).
  Future<List<BranchItem> Function()> pumpEditor(
    WidgetTester tester, {
    required List<BranchItem> initialItems,
    bool showTrueFalseAnswers = false,
  }) async {
    var items = initialItems;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Directionality(
              textDirection: TextDirection.rtl,
              child: ItemsEditor(
                items: items,
                showTrueFalseAnswers: showTrueFalseAnswers,
                onChanged: (updated) => setState(() => items = updated),
              ),
            ),
          ),
        ),
      ),
    );
    return () => items;
  }

  testWidgets('displays automatic sequence numbers and no reorder arrows', (tester) async {
    final items = <BranchItem>[
      BranchItem(id: 'i1', text: 'النقطة الأولى', isCorrect: true),
      BranchItem(id: 'i2', text: 'النقطة الثانية', isCorrect: false),
    ];

    await pumpEditor(
      tester,
      initialItems: items,
      showTrueFalseAnswers: true,
    );

    // الترقيم التلقائي ظاهر.
    expect(find.text('1-'), findsOneWidget);
    expect(find.text('2-'), findsOneWidget);

    // لا أزرار تقديم أو تأخير.
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    // خيار واحد لكل عبارة يعرض إجابتها الحالية (✓ للصح، ✗ للخطأ)…
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('✗'), findsOneWidget);
    // …ولا كلمات «صح/خطأ» مكرّرة ولا مفتاح نمط كتابة على الورقة.
    expect(find.text('صح'), findsNothing);
    expect(find.text('خطأ'), findsNothing);
    expect(find.text('علامات (✓ / ✗)'), findsNothing);
    expect(find.text('كلمات (صح / خطأ)'), findsNothing);
    expect(
      find.textContaining('الإجابات للتصحيح ولا تُطبع على الورقة'),
      findsOneWidget,
    );
  });

  testWidgets('a single tap cycles the answer: unset ← true ← false ← unset', (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: 'عبارة')],
      showTrueFalseAnswers: true,
    );

    // بلا إجابة بعد: الحالة الثالثة «—».
    expect(find.text('—'), findsOneWidget);
    expect(read().single.isCorrect, isNull);

    Future<void> tapToggle() async {
      await tester.tap(find.byKey(const ValueKey<String>('item-answer-i1')));
      await tester.pumpAndSettle();
    }

    await tapToggle();
    expect(read().single.isCorrect, isTrue);
    expect(find.text('✓'), findsOneWidget);

    await tapToggle();
    expect(read().single.isCorrect, isFalse);
    expect(find.text('✗'), findsOneWidget);

    await tapToggle();
    expect(read().single.isCorrect, isNull);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('hides the answer control for non true/false items', (tester) async {
    await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: 'فراغ')],
    );

    expect(find.text('—'), findsNothing);
    expect(
      find.textContaining('الإجابات للتصحيح ولا تُطبع على الورقة'),
      findsNothing,
    );
  });

  testWidgets('keeps writing the item text verbatim', (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1')],
    );

    // آخر حقل نصي في المحرر هو نص النقطة (حقل العدد أعلاه أولاً).
    await tester.enterText(find.byType(TextFormField).last, 'الأرض كروية');
    await tester.pumpAndSettle();

    expect(read().single.text, 'الأرض كروية');
  });
}
