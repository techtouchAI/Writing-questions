// نمط التصدير في حوار المراجعة: «مطابق للمعاينة (Exact)» مقابل النص المتجه.
//
// Exact نمط اختياري لا افتراضي: المسار المعتاد يبقي PDF نصياً وWord قابلاً
// للتحرير. عند تفعيله يجب أن يُعلَن صراحةً أن PDF صورة غير قابلة للبحث وأن
// Word صفحات صور غير قابلة للتحرير. الاختبار يقرأ الوصف من حوار المستخدم نفسه.
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
  // Opening review resolves the canonical pagination document before showing
  // the dialog. Pump the real loading state until the dialog appears; this
  // tolerates the toolbar's indeterminate busy animation without settling it.
  final reviewTitle = find.text('مراجعة الورقة');
  for (var frame = 0; frame < 300 && reviewTitle.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(reviewTitle, findsOneWidget);
}

void main() {
  testWidgets(
    'Exact is optional by default and accurately discloses image-only exports',
    (tester) async {
      await _pump(tester);
      await _openReview(tester);

      const switchKey = ValueKey<String>('export-exact-mode');
      final switchFinder = find.byKey(switchKey);
      expect(
        switchFinder,
        findsOneWidget,
        reason: 'مفتاح نمط التصدير في الحوار.',
      );
      expect(
        tester.widget<SwitchListTile>(switchFinder).value,
        isFalse,
        reason: 'المسار الافتراضي نصي وقابل للتحرير.',
      );
      expect(find.textContaining('OMML'), findsOneWidget);
      expect(find.textContaining('غير قابل للتحرير'), findsNothing);
      expect(find.textContaining('صور صفحات المعاينة'), findsNothing);
      expect(find.text('صفحات المعاينة'), findsOneWidget);

      // Toggle the same live review dialog: normal mode stays editable, while
      // Exact must disclose the loss of searchability/editability explicitly.
      await tester.tap(switchFinder);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(find.textContaining('صور صفحات المعاينة'), findsOneWidget);
      expect(find.textContaining('غير قابل للتحرير'), findsOneWidget);
      expect(find.textContaining('OMML'), findsNothing);
    },
  );
}
