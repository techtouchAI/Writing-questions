// نمط التصدير في حوار المراجعة: «مطابق للمعاينة (Exact)» مقابل النص المتجه.
//
// الشرط الذي لا يجوز أن يسقط: حين يكون النمط الدقيق مفعّلاً يجب أن **يُعلَن
// صراحةً** أن ملف Word غير قابل للتحرير (فالصفحات صور)، وحين يُطفأ يجب أن
// يظهر وعد المسار الآخر (نص + معادلات OMML). الاختبار يفتح الحوار كما
// يفتحه المستخدم من الشريط، ويقرأ الإعلان من الواجهة نفسها.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

ExamDocument _document() => ExamDocument(
      name: 'نمط التصدير',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          branches: <BranchModel>[
            BranchModel(id: 'b1', content: BranchContent(statement: 'الفرع الأول')),
          ],
        ),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ExamWizardController(document: _document());
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openReview(WidgetTester tester) async {
  final tool = find
      .descendant(
        of: find.byType(PreviewToolbar),
        matching: find.byTooltip('مراجعة وتصدير PDF'),
      )
      .last;
  await tester.ensureVisible(tool);
  await tester.pumpAndSettle();
  await tester.tap(tool);
  await tester.pumpAndSettle();
  expect(find.text('مراجعة الورقة'), findsOneWidget);
}

void main() {
  testWidgets('مفتاح Exact موجود ومفعّل افتراضاً ويعلن عدم قابلية Word للتحرير',
      (tester) async {
    await _pump(tester);
    await _openReview(tester);

    final switchFinder = find.byKey(const ValueKey<String>('export-exact-mode'));
    expect(switchFinder, findsOneWidget, reason: 'مفتاح نمط التصدير في الحوار.');

    final asSwitch = tester.widget<SwitchListTile>(switchFinder);
    expect(asSwitch.value, isTrue, reason: 'الافتراضي: مطابق للمعاينة.');
    // الإعلان الصريح — شرط المستخدم عند قبول Word غير القابل للتحرير.
    expect(find.textContaining('غير قابل للتحرير'), findsOneWidget);
    expect(find.textContaining('صور صفحات المعاينة'), findsOneWidget);
    // عدد صفحات المعاينة ظاهر في المراجعة (مصدر عدّ النمط الدقيق).
    expect(find.text('صفحات المعاينة'), findsOneWidget);
  });

  testWidgets('إطفاء Exact يبدّل الإعلان إلى المسار المتجه القابل للتحرير',
      (tester) async {
    await _pump(tester);
    await _openReview(tester);

    await tester.tap(find.byKey(const ValueKey<String>('export-exact-mode')));
    await tester.pumpAndSettle();

    final asSwitch = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('export-exact-mode')),
    );
    expect(asSwitch.value, isFalse);
    expect(find.textContaining('OMML'), findsOneWidget,
        reason: 'إعلان المسار المتجه: نص ومعادلات OMML قابلة للتحرير.');
    expect(find.textContaining('غير قابل للتحرير'), findsNothing);
  });
}
