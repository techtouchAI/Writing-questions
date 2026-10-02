// التحديد حالة واجهة لا حالة مستند.
//
// `selectedQuestions`/`selectedBranches`/`multiSelect` تعيش في الشاشة، ويجب
// ألا تترك أثراً في النموذج ولا في أي ملف مُصدَّر. الاختبار يفعل ذلك كما
// يفعله المستخدم (نقرة على «تحديد الكل» داخل المعاينة) ثم يقارن **بايتات**
// PDF وWord قبل التحديد وبعده: تطابق تام لا «تشابه».
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

ExamDocument _document() => ExamDocument(
      name: 'عزل التحديد',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'نقطة',
              options: <QuestionOption>[QuestionOption(text: 'خيار')],
            ),
          ],
          branches: <BranchModel>[
            BranchModel(id: 'b1', content: BranchContent(statement: 'فرع')),
          ],
        ),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'السؤال الثاني'),
      ],
    );

Future<Uint8List> _pdfBytes(ExamDocument document) =>
    PaginatedPdfExamEngine().generate(document: document);

Future<Uint8List> _wordBytes(ExamDocument document) =>
    DocxDocumentExportService.buildDocumentDocxBytes(document: document);

void main() {
  testWidgets('تحديد الكل لا يغيّر بايتات PDF ولا Word', (tester) async {
    tester.view.physicalSize = const Size(1500, 1400);
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

    final beforeModel = controller.document.toMap();
    final beforePdf = await _pdfBytes(controller.document);
    final beforeWord = await _wordBytes(controller.document);

    // المستخدم يضغط «تحديد الكل» (الحالة تدخل وضع التحديد المتعدد فعلاً).
    final selectAll = find
        .descendant(
          of: find.byType(PreviewToolbar),
          matching: find.byKey(const ValueKey<String>('select-all-blocks')),
        )
        .last;
    await tester.ensureVisible(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('preview-selection-count')),
        findsOneWidget,
        reason: 'دخلنا وضع التحديد فعلاً (العدّاد ظاهر).');

    // النموذج لم يتغيّر…
    expect(controller.document.toMap(), beforeModel);
    // …والملفات المنشأة من النموذج نفسه لم تتغيّر بايتاً واحداً.
    final afterPdf = await _pdfBytes(controller.document);
    final afterWord = await _wordBytes(controller.document);
    expect(afterPdf, equals(beforePdf),
        reason: 'التحديد UI state: لا يصل إلى PDF.');
    expect(afterWord, equals(beforeWord),
        reason: 'التحديد UI state: لا يصل إلى Word.');

    // وإلغاء التحديد كذلك.
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(await _pdfBytes(controller.document), equals(beforePdf));
    expect(await _wordBytes(controller.document), equals(beforeWord));
  });
}
