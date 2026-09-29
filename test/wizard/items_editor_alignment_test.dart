import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/views/widgets/items_editor.dart';

void main() {
  group('ItemsEditor UI & Behaviors', () {
    testWidgets('displays automatic sequence numbers and no reorder arrows', (tester) async {
      final items = [
        BranchItem(id: 'i1', text: 'النقطة الأولى', isCorrect: true),
        BranchItem(id: 'i2', text: 'النقطة الثانية', isCorrect: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: ItemsEditor(
                items: items,
                showTrueFalseAnswers: true,
                trueFalseFormat: 'symbols',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // يظهر الترقيم التلقائي
      expect(find.text('1-'), findsOneWidget);
      expect(find.text('2-'), findsOneWidget);

      // لا توجد أزرار تقديم أو تأخير
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

      // تظهر خيارات النمط والرموز
      expect(find.text('علامات (✓ / ✗)'), findsOneWidget);
      expect(find.text('كلمات (صح / خطأ)'), findsOneWidget);
      expect(find.text('✓'), findsNWidgets(2));
      expect(find.text('✗'), findsNWidgets(2));
    });

    testWidgets('allows switching between symbols and words', (tester) async {
      String currentFormat = 'words';
      final items = [
        BranchItem(id: 'i1', text: 'نقطة تجريبية', isCorrect: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: ItemsEditor(
                    items: items,
                    showTrueFalseAnswers: true,
                    trueFalseFormat: currentFormat,
                    onFormatChanged: (format) {
                      setState(() => currentFormat = format);
                    },
                    onChanged: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      );

      // النمط الحالي كلمات
      expect(find.text('صح'), findsOneWidget);
      expect(find.text('خطأ'), findsOneWidget);

      // التحويل لعلامات
      await tester.tap(find.text('علامات (✓ / ✗)'));
      await tester.pumpAndSettle();

      expect(currentFormat, 'symbols');
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('✗'), findsOneWidget);
    });
  });
}
