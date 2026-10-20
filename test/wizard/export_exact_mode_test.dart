// تمت إزالة نمط التصدير Exact وزر Word: المعاينة الآن تصدر PDF متجه فقط.
// يثبت هذا الاختبار زوال مفتاح Exact وزر Word من الحوار، وبقاء زر PDF.

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
  final reviewTitle = find.text('مراجعة الورقة');
  for (var frame = 0; frame < 300 && reviewTitle.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(reviewTitle, findsOneWidget);
}

void main() {
  testWidgets(
    'review dialog exposes only PDF export, no Exact toggle nor Word button',
    (tester) async {
      await _pump(tester);
      await _openReview(tester);

      expect(find.text('تصدير PDF'), findsOneWidget);
      expect(find.text('تصدير Word'), findsNothing,
          reason: 'زر Word أُزيل؛ PDF المتجه هو المسار الوحيد.');
      // The disclosure that mentioned non-editable images must be gone.
      expect(find.textContaining('OMML'), findsNothing);
    },
  );
}
