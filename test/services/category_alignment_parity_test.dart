// محاذاة سطر القسم (`QuestionModel.categoryAlign`) في الثلاثة.
//
// الميزة تمرّ: Model ← Controller ← المعاينة/PDF/Word. والاختبار يقيس الأثر
// الفعلي لا وجود الشيفرة:
//   * المعاينة: موضع run القسم ومحاذاة السطر في `LayoutDocument` الذي ترسمه الشاشة.
//   * PDF: موضع كلمة القسم المرسومة بالنسبة لحدود صندوق المحتوى.
//   * Word: قيمة `w:jc` في فقرة القسم وحدها.
// ويُعاد للعربية (RTL) والإنجليزية (LTR) لأن `start/end` يتبعان الاتجاه.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../pdf_engine/pdf_content_probe.dart';

/// حدود صندوق المحتوى في PDF لهامش 15مم (الافتراضي).
const double _leftEdge = 42.52;
const double _rightEdge = 552.76;

ExamDocument _document({
  required PaperAlign? align,
  required String subject,
}) =>
    ExamDocument(
      name: 'محاذاة القسم',
      header: ExamHeaderModel.initial(subject: subject),
      settings: const PaperSettings(),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'Cat',
          categoryAlign: align,
          statement: 'Stmt',
          branches: <BranchModel>[
            BranchModel(id: 'b1', content: BranchContent(statement: 'Branch')),
          ],
        ),
      ],
    );

/// فقرة Word التي تحوي «Cat» (سطر القسم).
Future<String> _wordCategoryParagraph(ExamDocument document) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
  );
  final xml = utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
        as List<int>,
  );
  for (final match in RegExp('<w:p>.*?</w:p>', dotAll: true).allMatches(xml)) {
    if (match.group(0)!.contains('Cat')) {
      return match.group(0)!;
    }
  }
  fail('لم أجد فقرة القسم في Word.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF: موضع سطر القسم يتبع المحاذاة', () {
    Future<ProbedWord> categoryWord(PaperAlign align) async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(align: align, subject: 'Arabic'),
      );
      return PdfContentProbe.fromBytes(bytes)
          .words
          .firstWhere((word) => word.text.contains('Cat'));
    }

    test('يسار: الكلمة تبدأ من حدّ المحتوى الأيسر', () async {
      final word = await categoryWord(PaperAlign.left);
      expect(word.x, closeTo(_leftEdge, 3),
          reason: 'المحاذاة «يسار» تُلصق القسم بحدّ الصندوق الأيسر.');
    });

    test('يمين: الكلمة تنتهي عند حدّ المحتوى الأيمن', () async {
      final word = await categoryWord(PaperAlign.right);
      expect(word.x + word.advanceWidth, closeTo(_rightEdge, 3),
          reason: 'المحاذاة «يمين» تُلصق القسم بحدّ الصندوق الأيمن: $word');
    });

    test('وسط: مركز الكلمة في منتصف الصندوق', () async {
      final word = await categoryWord(PaperAlign.center);
      expect(word.x + word.advanceWidth / 2,
          closeTo((_leftEdge + _rightEdge) / 2, 4),
          reason: 'المحاذاة «وسط» توسّط سطر القسم في صندوق المحتوى: $word');
    });
  });

  group('Word: w:jc في فقرة القسم وحدها', () {
    Future<String> categoryJc(PaperAlign align,
        {String subject = 'Arabic'}) async {
      final paragraph = await _wordCategoryParagraph(
        _document(align: align, subject: subject),
      );
      return RegExp(r'w:jc w:val="([a-z]+)"').firstMatch(paragraph)!.group(1)!;
    }

    test('left/center/right تُكتب حرفياً في الفقرة', () async {
      expect(await categoryJc(PaperAlign.left), 'left');
      expect(await categoryJc(PaperAlign.center), 'center');
      expect(await categoryJc(PaperAlign.right), 'right');
    });

    test('start/end يتبعان اتجاه الورقة (RTL مقابل LTR)', () async {
      expect(await categoryJc(PaperAlign.start), 'right');
      expect(await categoryJc(PaperAlign.end), 'left');
      // القالب الإنجليزي هو مسار LTR الفعلي في التطبيق.
      expect(await categoryJc(PaperAlign.start, subject: 'English'),
          'left',
          reason: 'في ورقة LTR يبدأ السطر من اليسار.');
      expect(await categoryJc(PaperAlign.end, subject: 'English'), 'right');
    });
  });

  group('المعاينة: محاذاة هندسة LayoutDocument الفعلية', () {
    Future<({LayoutPage page, LayoutLine line, LayoutRun run})> categoryGeometry(
      WidgetTester tester,
      PaperAlign align, {
      String subject = 'اللغة العربية',
    }) async {
      tester.view.physicalSize = const Size(1500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExamWizardController(
        document: _document(align: align, subject: subject),
      );
      addTearDown(controller.dispose);
      // The interactive paper is the screen default; the canonical surface
      // under test is requested explicitly with the production resolvers
      // (the same defaults the single-surface screen used to apply).
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ExamWizardController>.value(
            value: controller,
            child: ExamPreviewScreen(
              onBackToQuestions: () {},
              canonicalLayoutResolver: ({
                required document,
                required sourceIr,
              }) =>
                  CanonicalLayoutService.resolve(
                document: document,
                sourceIr: sourceIr,
              ),
              canonicalPreviewAssetLoader: ({
                required layout,
                required document,
              }) =>
                  CanonicalLayoutPreviewAssets.load(
                layout: layout,
                document: document,
              ),
            ),
          ),
        ),
      );
      for (var frame = 0;
          frame < 40 &&
              find.byType(CanonicalLayoutPreviewPage).evaluate().isEmpty;
          frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final preview = tester.widget<CanonicalLayoutPreviewPage>(
        find.byType(CanonicalLayoutPreviewPage).first,
      );
      final matches = <({LayoutPage page, LayoutLine line, LayoutRun run})>[
        for (final page in preview.layoutDocument.pages)
          for (final block in page.blocks)
            for (final line in block.allLines)
              for (final run in line.runs)
                if (run.text.contains('Cat'))
                  (page: page, line: line, run: run),
      ];
      expect(matches, hasLength(1));
      return matches.single;
    }

    void expectEdgeAlignment(
      ({LayoutPage page, LayoutLine line, LayoutRun run}) geometry,
      PaperAlign align,
      bool rtl,
    ) {
      final content = geometry.page.contentBounds;
      expect(geometry.line.alignment, align);
      switch (align) {
        case PaperAlign.left:
          expect(geometry.run.x, closeTo(content.left, 0.1));
          break;
        case PaperAlign.right:
          expect(geometry.run.x + geometry.run.width,
              closeTo(content.right, 0.1));
          break;
        case PaperAlign.center:
          expect(geometry.run.x + geometry.run.width / 2,
              closeTo((content.left + content.right) / 2, 0.1));
          break;
        case PaperAlign.start:
          final actualEdge = rtl
              ? geometry.run.x + geometry.run.width
              : geometry.run.x;
          expect(actualEdge, closeTo(rtl ? content.right : content.left, 0.1));
          break;
        case PaperAlign.end:
          final actualEdge = rtl
              ? geometry.run.x
              : geometry.run.x + geometry.run.width;
          expect(actualEdge, closeTo(rtl ? content.left : content.right, 0.1));
          break;
        case PaperAlign.justify:
          fail('Category fixture does not request justified alignment.');
      }
    }

    testWidgets('left/center/right are painted at their canonical x positions',
        (tester) async {
      for (final align in <PaperAlign>[
        PaperAlign.left,
        PaperAlign.center,
        PaperAlign.right,
      ]) {
        final geometry = await categoryGeometry(tester, align);
        expectEdgeAlignment(geometry, align, true);
      }
    });

    testWidgets('start/end follow RTL and LTR page direction', (tester) async {
      for (final (subject, rtl) in <(String, bool)>[
        ('اللغة العربية', true),
        ('English', false),
      ]) {
        for (final align in <PaperAlign>[PaperAlign.start, PaperAlign.end]) {
          final geometry = await categoryGeometry(
            tester,
            align,
            subject: subject,
          );
          expectEdgeAlignment(geometry, align, rtl);
        }
      }
    });
  });
}
