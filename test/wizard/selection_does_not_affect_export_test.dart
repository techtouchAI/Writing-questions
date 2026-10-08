// التحديد حالة واجهة لا حالة مستند.
//
// `selectedQuestions`/`selectedBranches`/`multiSelect` تعيش في الشاشة، ويجب
// ألا تترك أثراً في النموذج ولا في أي ملف مُصدَّر. الاختبار يفعله كما يفعله
// المستخدم (نقرة على «تحديد الكل» في المعاينة) ثم يقارن **بصمة التصدير**
// قبل التحديد وبعده: النص ومواضعه وحجمه في PDF.
// (البايتات الخام لا تصلح للمقارنة: كل توليد يكتب طابع زمن في الملف.)
//
// (حُذفت بصمة Word في C5 مع القابل للتحرير: Word اليوم صور صفحات المعاينة،
// والتحديد لا يصل إلى الصورة أصلاً.)
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
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

import '../pdf_engine/pdf_content_probe.dart';

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

/// بصمة PDF: كل كلمة مرسومة بموضعها وحجمها + عدد الصفحات.
Future<List<String>> _pdfFingerprint(ExamDocument document) async {
  final bytes = await PaginatedPdfExamEngine().generate(document: document);
  final probe = PdfContentProbe.fromBytes(bytes);
  return <String>[
    'pages=${PdfContentProbe.pageCountOf(bytes)}',
    for (final word in probe.words)
      '${word.text}@${word.x.toStringAsFixed(2)},'
          '${word.y.toStringAsFixed(2)}@${word.fontSize}',
  ];
}

void main() {
  testWidgets('تحديد الكل لا يغيّر مخرجات PDF', (tester) async {
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
    final beforePdf = await _pdfFingerprint(controller.document);

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
    // …ولا صفحة PDF (النص والمواضع والأحجام).
    // (حُذفت بصمة Word في C5 مع القابل للتحرير.)
    expect(await _pdfFingerprint(controller.document), beforePdf,
        reason: 'التحديد UI state: لا يصل إلى PDF.');

    // وإلغاء التحديد كذلك.
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(await _pdfFingerprint(controller.document), beforePdf);
  });
}
