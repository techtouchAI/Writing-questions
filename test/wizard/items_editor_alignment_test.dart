import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/views/widgets/items_editor.dart';
import 'package:writing_questions_app/views/widgets/rich_content_field.dart';

/// محرر النقاط: تسلسل تلقائي، وبلا أزرار ترتيب، وبلا أي عنصر إجابة —
/// والحقول غنية (نص + معادلات مرئية) وتحفظ النص المكتوب.
void main() {
  /// يبني المحرر مع حالة محيطة تُعيد البناء بعد كل تعديل (كما في الشاشات).
  Future<List<BranchItem> Function()> pumpEditor(
    WidgetTester tester, {
    required List<BranchItem> initialItems,
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
      BranchItem(id: 'i1', text: 'النقطة الأولى'),
      BranchItem(id: 'i2', text: 'النقطة الثانية'),
    ];

    await pumpEditor(tester, initialItems: items);

    // الترقيم التلقائي ظاهر.
    expect(find.text('1-'), findsOneWidget);
    expect(find.text('2-'), findsOneWidget);

    // لا أزرار تقديم أو تأخير.
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    // لا عنصر إجابة إطلاقاً: لا علامات ✓/✗ ولا كلمات صح/خطأ ولا مفتاح نمط.
    expect(find.text('✓'), findsNothing);
    expect(find.text('✗'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.text('صح'), findsNothing);
    expect(find.text('خطأ'), findsNothing);
    expect(find.text('علامات (✓ / ✗)'), findsNothing);
    expect(find.text('كلمات (صح / خطأ)'), findsNothing);
    expect(find.textContaining('الإجابات للتصحيح'), findsNothing);

    // النصوص محفوظة في الحقول الغنية.
    expect(find.text('النقطة الأولى'), findsOneWidget);
    expect(find.text('النقطة الثانية'), findsOneWidget);
  });

  testWidgets('hides the answer control for non true/false items', (tester) async {
    await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: 'فراغ')],
    );

    expect(find.text('—'), findsNothing);
    expect(find.text('✓'), findsNothing);
    expect(find.text('✗'), findsNothing);
  });

  testWidgets('keeps writing the item text verbatim', (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1')],
    );

    // النقر على الحقل الغني يفتح محرر المحتوى، وتُكتب فيه عبارة النقطة.
    await tester.tap(find.byType(RichContentField).last);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'الأرض كروية');
    await tester.tap(find.text('حفظ المحتوى'));
    await tester.pump();
    await tester.pump();

    expect(read().single.text, 'الأرض كروية');
  });

  testWidgets('لا حقل كود خام في المحرر: الحقول غنية وتُفتح على معادلات مرئية',
      (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: r'احسب $1+1$')],
    );

    // لا حقل نصي مكشوف على المصدر: الصيغة تُعرض مرئية لا كوداً، ولا يوجد أي
    // حقل يحمل علامات الدولار الخام (حقل العدد وحده حقل رقمي).
    expect(find.text(r'$1+1$'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.controller?.text.contains(r'$') ?? false),
      ),
      findsNothing,
    );
    expect(read().single.text, r'احسب $1+1$');
  });
}
