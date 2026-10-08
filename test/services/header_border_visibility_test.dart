// ظهور إطار الترويسة (`PaperSettings.headerBorder`) في المخرجات.
//
// الخاصية تمرّ من الإعداد إلى العقد الدلالي مرة واحدة
// ([HeaderBlueprint.framed]) ثم يقرؤها كل راسم — فإطفاؤها يطفيها في
// المعاينة وPDF معاً، وتشغيلها يشغّلها فيهما.
//
// (حُذف في C5 مع Word القابل للتحرير: اختبار `<w:tblBorders>` — Word اليوم
// صور صفحات المعاينة، والإطار جزء من الصورة.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/views/wizard/paper_header_footer_view.dart';

ExamDocument _document({required bool framed}) => ExamDocument(
      name: 'إطار الترويسة',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      settings: PaperSettings(headerBorder: framed),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'سؤال'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('العقد الدلالي يحمل الإعداد كما هو (مصدر واحد)', () {
    expect(ExamBlueprint.from(_document(framed: true)).header.framed, isTrue);
    expect(ExamBlueprint.from(_document(framed: false)).header.framed, isFalse);
  });

  test('PDF: الإعداد لا يغيّر النص المرسوم (الإطار عرضٌ لا محتوى)', () async {
    final onBytes = await PaginatedPdfExamEngine().generate(
      document: _document(framed: true),
    );
    final offBytes = await PaginatedPdfExamEngine().generate(
      document: _document(framed: false),
    );
    expect(onBytes.length, greaterThan(1000));
    expect(String.fromCharCodes(offBytes.sublist(0, 5)), '%PDF-');
    expect(offBytes, isNot(equals(onBytes)),
        reason: 'الإطار يغيّر الرسم فعلاً (ليس إعداداً مهملاً).');
  });

  testWidgets('المعاينة: ودجت الترويسة يقرأ الإطار من العقد', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaperHeaderView(
            header: ExamBlueprint.from(_document(framed: true)).header,
            style: PaperTextStyle.empty,
            defaultFont: PaperFont.naskh,
            fontScale: 1,
            heightScale: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final decorated = tester.widgetList<Container>(find.byType(Container)).where(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).border != null,
        );
    expect(decorated, isNotEmpty,
        reason: 'إطار الترويسة مرسوم في المعاينة عند تفعيله.');
  });
}
