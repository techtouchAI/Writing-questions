import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/views/widgets/points_editor.dart';
import 'package:writing_questions_app/views/widgets/rich_content_field.dart';

/// محرر النقاط ([PointsEditor]): تسلسل تلقائي متصل مهما اختلفت الأنواع،
/// وبلا أزرار ترتيب، وبلا أي عنصر إجابة — والحقول غنية (نص + معادلات
/// مرئية) وتحفظ النص المكتوب، ولكل نقطة درجة برقم خام يلفّه النظام عند
/// الطباعة «(٢ درجة)».
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
              child: SingleChildScrollView(
                child: PointsEditor(
                  points: items,
                  labelOf: (index, point) => '${index + 1}-',
                  optionLabelOf: (index, option) => '( ${index + 1} )',
                  marksHelperOf: (marks) => 'تُطبع بصيغة (٢٤ درجة) عند الإظهار.',
                  onChanged: (updated) => setState(() => items = updated),
                ),
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

    // الترقيم التلقائي ظاهر (تسلسل واحد متصل بالفهرس).
    expect(find.text('1-'), findsOneWidget);
    expect(find.text('2-'), findsOneWidget);

    // لا أزرار تقديم أو تأخير: لا قائمة إعادة ترتيب ولا أيقونات نقل.
    // نقاط الكتابة نص حر فقط ولا تحتوي قائمة لاختيار النوع.
    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.byType(DropdownButton), findsNothing);
    expect(find.text('نوع النقطة'), findsNothing);
    expect(find.text('نص حر'), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(find.byTooltip('نقل النقطة لأعلى'), findsNothing);
    expect(find.byTooltip('نقل النقطة لأسفل'), findsNothing);

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

  testWidgets('writes a point marks as a raw number (the system wraps it)', (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: 'نقطة')],
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('point-marks-i1')),
      '2',
    );
    await tester.pump();

    // الرقم الخام محفوظ كما هو؛ اللفّ «(٢ درجة)» يتم عند بناء الورقة.
    expect(read().single.marks, 2);

    // مسح الرقم يعيد الدرجة صفراً (بلا درجة معلنة).
    await tester.enterText(
      find.byKey(const ValueKey<String>('point-marks-i1')),
      '',
    );
    await tester.pump();
    expect(read().single.marks, 0);
  });

  testWidgets('لا حقل كود خام في المحرر: الحقول غنية وتُفتح على معادلات مرئية',
      (tester) async {
    final read = await pumpEditor(
      tester,
      initialItems: <BranchItem>[BranchItem(id: 'i1', text: r'احسب $1+1$')],
    );

    // لا حقل نصي مكشوف على المصدر: الصيغة تُعرض مرئية لا كوداً، ولا يوجد أي
    // حقل يحمل علامات الدولار الخام (حقل العدد ودرجة النقطة حقول رقمية).
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
