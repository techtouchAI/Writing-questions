// صدق ترويسة واحدة عبر المعاينة وPDF — المصدر الوحيد `document.header.style`:
//   * PDF: الحجم والمسافة الرأسية والمحاذاة المقاسة من المحتوى المرسوم،
//   * المعاينة: ودجت الترويسة يقرأ الإعداد نفسه (حجم/محاذاة/مسافة فقرات)،
//   * والعينتان تُكتبان في build/math_samples للمراجعة البشرية:
//     test-header-default.pdf / test-header-modified.pdf
//
// (حُذفت في C5 مع Word القابل للتحرير: مجموعة DOCX — وصول كل خاصية إلى
// `word/document.xml` وعينتا docx — Word اليوم صور صفحات المعاينة.)
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/views/widgets/tex_text.dart';
import 'package:writing_questions_app/views/wizard/paper_header_footer_view.dart';

import '../pdf_engine/pdf_content_probe.dart';

/// تعديل كامل لإعداد الترويسة — كل خاصية تدعمها المعاينة وPDF.
const PaperTextStyle _modifiedHeaderStyle = PaperTextStyle(
  font: PaperFont.tajawal,
  fontSize: 16,
  bold: false,
  italic: true,
  underline: true,
  align: PaperAlign.left,
  lineHeight: 2.0,
  paragraphSpacing: 8,
  color: 0xFFFF0000,
);

ExamDocument _doc({PaperTextStyle headerStyle = PaperTextStyle.empty}) {
  return ExamDocument(
    name: 'ترويسة',
    header: ExamHeaderModel.initial(
      subject: 'الرياضيات',
      schoolName: 'Abc School',
    ).copyWith(style: headerStyle),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'سؤال واحد يكفي لقياس الترويسة',
        items: <BranchItem>[
          BranchItem(id: 'i1', text: 'نقطة قياس واحدة'),
        ],
      ),
    ],
  );
}

Future<void> _writeSample(String name, Uint8List bytes) async {
  final directory = Directory('build/math_samples');
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final file = File('build/math_samples/$name');
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('عينة الترويسة: ${file.path}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF — إعداد الترويسة مرسوم فعلاً', () {
    test('الحجم والمسافة الرأسية والمحاذاة تتغير بين الافتراضي والمعدَّل',
        () async {
      final defaultDoc = _doc();
      final modifiedDoc = _doc(headerStyle: _modifiedHeaderStyle);

      final defaultBytes =
          await PaginatedPdfExamEngine().generate(document: defaultDoc);
      final modifiedBytes =
          await PaginatedPdfExamEngine().generate(document: modifiedDoc);
      await _writeSample('test-header-default.pdf', defaultBytes);
      await _writeSample('test-header-modified.pdf', modifiedBytes);

      final defaultProbe = PdfContentProbe.fromBytes(defaultBytes);
      final modifiedProbe = PdfContentProbe.fromBytes(modifiedBytes);

      // مِرساة ASCII لا تتأثر بتشكيل العربية: اسم المدرسة في سطر الترويسة.
      ProbedWord schoolWord(PdfContentProbe probe) => probe.words.firstWhere(
            (word) => word.text.contains('Abc'),
            orElse: () => fail('سطر اسم المدرسة «Abc» لم يُرسم في الـ PDF.'),
          );

      final defaultWord = schoolWord(defaultProbe);
      final modifiedWord = schoolWord(modifiedProbe);
      expect(defaultWord.fontSize, 10.0,
          reason: 'حجم الترويسة الافتراضي في PDF 10pt.');
      expect(modifiedWord.fontSize, 16.0,
          reason: 'حجم الترويسة المعدَّل 16pt يصل إلى الرسم.');

      // أول عنوان سؤال (11pt) — المسافة من سطر الترويسة إليه تكبر مع
      // تباعد الأسطر 2.0 ومسافة الفقرات 8.
      double headerToQuestionGap(PdfContentProbe probe) {
        final question = probe.words.firstWhere(
          (word) => word.fontSize == 11.0,
          orElse: () => fail('لا كلمة بحجم عنوان السؤال 11pt في الـ PDF.'),
        );
        return schoolWord(probe).y - question.y;
      }

      final defaultGap = headerToQuestionGap(defaultProbe);
      final modifiedGap = headerToQuestionGap(modifiedProbe);
      expect(defaultGap, greaterThan(0));
      expect(modifiedGap, greaterThan(defaultGap + 10),
          reason: 'تباعد الأسطر ومسافة الفقرات يوسّعان الترويسة فعلياً.');

      // المحاذاة يسار: السطر يبدأ من حافة العمود لا من وسطه.
      expect(modifiedWord.x, lessThan(defaultWord.x),
          reason: 'align=left يزيح سطر الترويسة عن التوسيط الافتراضي.');
    });
  });

  group('المعاينة — الودجت يقرأ المصدر الوحيد نفسه', () {
    Future<void> pumpHeader(
      WidgetTester tester,
      ExamDocument document,
    ) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blueprint = ExamBlueprint.from(document);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PaperHeaderView(
              header: blueprint.header,
              style: document.header.style,
              defaultFont: document.settings.defaultFont,
              fontScale: 1,
              heightScale: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('افتراضي: توسيط العمود وحجم 10pt وبلا مسافة فقرات',
        (tester) async {
      await pumpHeader(tester, _doc());
      final lines = tester.widgetList<TexText>(find.byType(TexText)).toList();
      expect(lines, isNotEmpty);
      expect(lines.first.textAlign, TextAlign.center);
      expect(lines.first.style?.fontSize, closeTo(PaperMetrics.px(10), 0.01));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 8,
        ),
        findsNothing,
      );
    });

    testWidgets('معدَّل: محاذاة يسار وحجم 16pt ومسافة فقرات 8',
        (tester) async {
      await pumpHeader(tester, _doc(headerStyle: _modifiedHeaderStyle));
      final lines = tester.widgetList<TexText>(find.byType(TexText)).toList();
      expect(lines, isNotEmpty);
      expect(lines.first.textAlign, TextAlign.left);
      expect(lines.first.style?.fontSize, closeTo(PaperMetrics.px(16), 0.01));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 8,
        ),
        findsWidgets,
      );
    });
  });
}
