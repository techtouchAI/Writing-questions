// ظهور إطار الترويسة (`PaperSettings.headerBorder`) في المخرجات.
//
// الخاصية تمرّ من الإعداد إلى العقد الدلالي مرة واحدة
// ([HeaderBlueprint.framed]) ثم يقرؤها كل راسم — فإطفاؤها يطفيها في
// المعاينة وPDF معاً، وتشغيلها يشغّلها فيهما.
//
// (حُذف في C5 مع Word القابل للتحرير: اختبار `<w:tblBorders>` — Word اليوم
// صور صفحات المعاينة، والإطار جزء من الصورة.)
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/views/widgets/tex_text.dart';
import '../support/production_evidence_fonts.dart';
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
  setUpAll(loadProductionEvidenceFonts);

  for (final subject in ['English', 'اللغة العربية']) {
    testWidgets('semantic header direction ignores RTL app locale for $subject', (tester) async {
      final document = ExamDocument(name: 'BiDi header', header: ExamHeaderModel(
        subject: subject, schoolName: 'School بابل 2026',
        grade: 'Grade A صف ١٢', time: '90 min ٩٠',
        academicYear: '2026/٢٠٢٧', examType: 'نصف السنة Exam',
      ));
      final header = DocumentIR.fromBlueprint(blueprint: ExamBlueprint.from(document), document: document).header;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(width: 680, child: PaperHeaderView(
          semanticHeader: header, style: PaperTextStyle.empty,
          defaultFont: PaperFont.naskh, fontScale: 1, heightScale: 1,
        )),
      ))));
      await tester.pumpAndSettle();
      for (final line in header.allLines) {
        final field = find.byWidgetPredicate((w) => w is TexText &&
          w.text == line.content.legacyText);
        expect(field, findsOneWidget);
        final rich = find.descendant(of: field, matching: find.byType(RichText));
        expect(rich, findsOneWidget);
        final native = tester.renderObject<RenderParagraph>(rich);
        final direction = line.direction == DocumentDirection.ltr ? TextDirection.ltr : TextDirection.rtl;
        expect(native.textDirection, direction,
          reason: 'Physical RTL header columns must not override semantic paragraph ${line.field}.');
        // Native TextPainter is an independent BiDi oracle using the same span,
        // assets and actual available width, not a PDF-specific visual offset.
        final reference = TextPainter(text: native.text, textDirection: direction,
          textAlign: native.textAlign)..layout(maxWidth: native.size.width);
        final text = native.text.toPlainText();
        for (var offset = 0; offset < text.length; offset++) {
          final selection = TextSelection(baseOffset: offset, extentOffset: offset + 1);
          final actual = native.getBoxesForSelection(selection);
          final expected = reference.getBoxesForSelection(selection);
          expect(actual.length, expected.length);
          for (var i = 0; i < actual.length; i++) {
            expect(actual[i].left, closeTo(expected[i].left, 1e-6));
            expect(actual[i].right, closeTo(expected[i].right, 1e-6));
          }
        }
        reference.dispose();
      }
      expect(tester.takeException(), isNull);
    });
  }

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
              container.foregroundDecoration is BoxDecoration &&
              (container.foregroundDecoration! as BoxDecoration).border != null,
        );
    expect(decorated, isNotEmpty,
        reason: 'إطار الترويسة مرسوم في المعاينة عند تفعيله.');
    final border = (decorated.first.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(border.top.strokeAlign, BorderSide.strokeAlignCenter,
        reason: 'Canonical/PDF strokes are centered on header.rect, not inset into it.');
    final framedSize = tester.getSize(find.byType(PaperHeaderView));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaperHeaderView(
      header: ExamBlueprint.from(_document(framed: false)).header,
      style: PaperTextStyle.empty, defaultFont: PaperFont.naskh,
      fontScale: 1, heightScale: 1,
    ))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PaperHeaderView)), framedSize,
        reason: 'A decorative frame must not add layout insets or change header wrapping.');
  });
}
