// البنية لا النص المدموج: الخيارات في PDF **صناديق ثابتة العرض** تتشارك
// السطر وتلتفّ كما في المعاينة (لا نصاً واحداً يفصل بينه بمسافات NBSP)،
// والقيم (العرض والفجوة) هي قيم العقد نفسه.
//
// (حُذفت في C5 مع Word القابل للتحرير: جريانات `<w:r>` المستقلة لكل جزء
// وقيم `w:ind/w:sz/w:line` من العقد — Word اليوم صور لا بنية.)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../pdf_engine/pdf_content_probe.dart';

ExamDocument _document() => ExamDocument(
      name: 'بنية',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      // أرقام لاتينية وتسميات صريحة: تُقرأ صريحةً من PDF أيضاً.
      settings: const PaperSettings(numerals: PaperNumerals.latin),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'Cat',
          statement: 'Stmt',
          marksOverride: 12,
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'PointOne',
              marks: 3,
              options: <QuestionOption>[
                QuestionOption(text: 'OptA', labelOverride: 'A)'),
                QuestionOption(text: 'OptB', labelOverride: 'B)'),
                QuestionOption(text: 'OptC', labelOverride: 'C)'),
                QuestionOption(text: 'OptD', labelOverride: 'D)'),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF: الخيارات صناديق ثابتة العرض في سطر واحد', () {
    test('ثلاثة خيارات تشترك السطر والرابع يلتفّ، والعرض عرض العقد', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      ProbedWord option(String text) => probe.words.firstWhere(
            (word) => word.text.contains(text),
            orElse: () => fail('كلمة الخيار «$text» لم تُرسم في PDF.'),
          );

      final a = option('OptA');
      final b = option('OptB');
      final c = option('OptC');
      final d = option('OptD');

      expect(a.y, closeTo(b.y, 0.5), reason: 'الخياران الأول والثاني في سطر واحد.');
      expect(b.y, closeTo(c.y, 0.5), reason: 'ثلاثة خيارات تتشارك السطر كما في المعاينة.');
      expect(d.y, lessThan(a.y),
          reason: 'الخيار الرابع يلتفّ إلى صف جديد (Wrap) كما في المعاينة.');

      // الترتيب من اليمين إلى اليسار: الأول يميناً ثم التالي يساراً.
      expect(a.x, greaterThan(b.x));
      expect(b.x, greaterThan(c.x));

      // المسافة بين صندوقين متجاورين = عرض الصندوق + الفجوة (من العقد).
      // تُقاس من **تسميتي** الخيارين (وكلتاهما في أول صندوقها) فلا يتداخل
      // عرض التسمية مع نص الخيار في القياس.
      // The canonical semantic tree keeps punctuation in its own stable run,
      // so the word probe sees the alphanumeric label separately from `)`.
      final labelA = probe.words.firstWhere((word) => word.text.trim() == 'A');
      final labelB = probe.words.firstWhere((word) => word.text.trim() == 'B');
      final step = PaperMetrics.pt(
        VisualMetrics.optionBoxWidthPx + VisualMetrics.optionWrapSpacingPx,
      );
      expect((labelA.x - labelB.x).abs(), closeTo(step, 1.0),
          reason: 'عرض صندوق الخيار وفجوته من العقد لا من قياس النص الحر.');
      expect(
        probe.words.any((word) => word.text.contains('PointOne')),
        isTrue,
        reason: 'نص النقطة مرسوم ككلمة مستقلة عن تسميتها.',
      );
      final pointLine = probe.lines.firstWhere(
        (line) => line.words.any((word) => word.text.trim() == 'PointOne'),
      );
      final pointLabelParts = pointLine.words
          .map((word) => word.text.trim())
          .where((text) => text == '1' || text == '-')
          .toSet();
      expect(
        pointLabelParts,
        containsAll(<String>{'1', '-'}),
        reason: 'رقم النقطة وفاصلها يُرسمان كتسمية مستقلة عن نصها.',
      );
    });
    test('option label anchor is independent of content width and survives long option pagination', () async {
      final source = _document();
      final question = source.questions.single;
      final point = question.items.single;
      final changed = source.copyWith(questions: [question.copyWith(items: [
        point.copyWith(options: [
          point.options.first.copyWith(text: '${List.filled(80, 'نص خيار طويل English').join(' ')} OPTEND'),
          ...point.options.skip(1),
        ]),
      ])]);
      final engine = PaginatedPdfExamEngine();
      final before = await engine.resolveLayoutDocument(document: source);
      final after = await engine.resolveLayoutDocument(document: changed);
      expect(after.pages.length, greaterThan(1));
      double labelX(LayoutDocument layout) => layout.allLines.expand((line) => line.runs)
          .expand((run) => run.words).firstWhere((word) => word.text.trim() == 'A').x;
      expect(labelX(after), closeTo(labelX(before), 1e-6),
        reason: 'A fixed native label column must not move when only option content changes.');
      final shortPdf = PdfContentProbe.fromBytes(await engine.generate(document: source, layoutDocument: before));
      final longBytes = await engine.generate(document: changed, layoutDocument: after);
      // fromBytes intentionally reads ONE page (the first by default). The
      // regression's tail is on a continuation page: inspect every actual PDF
      // page, without changing the default probe contract or weakening the tail.
      final longPages = [for (var page = 0; page < PdfContentProbe.pageCountOf(longBytes); page++)
        PdfContentProbe.fromBytes(longBytes, pageIndex: page)];
      final longPdf = longPages.first;
      final tailPages = [for (var page = 0; page < longPages.length; page++)
        if (longPages[page].words.any((word) => word.text.contains('OPTEND'))) page];
      final plannedTailPage = after.pages.indexWhere((page) => page.blocks
        .expand((block) => block.allLines).expand((line) => line.runs)
        .any((run) => run.text.contains('OPTEND')));
      final evidence = Directory('build/production_fragment_repro')..createSync(recursive: true);
      File('${evidence.path}/optend-long.pdf').writeAsBytesSync(longBytes);
      File('${evidence.path}/optend-short.pdf').writeAsBytesSync(
        await engine.generate(document: source, layoutDocument: before));
      File('${evidence.path}/optend-manifest.json').writeAsStringSync(jsonEncode({
        'caseId': 'OPTEND-CONTINUATION', 'pdfPageCount': longPages.length,
        'plannedTailPage': plannedTailPage, 'actualTailPages': tailPages,
        'firstPageHasTail': longPages.first.words.any((word) => word.text.contains('OPTEND')),
        'englishWordsPerPage': [for (final page in longPages)
          page.words.where((word) => word.text.trim() == 'English').length],
        'tail': [for (final page in longPages) for (final word in page.words)
          if (word.text.contains('OPTEND')) {'text': word.text, 'x': word.x, 'y': word.y}],
      }));
      ProbedWord label(PdfContentProbe pdf) => pdf.words.firstWhere((word) => word.text.trim() == 'A');
      expect(label(longPdf).x, closeTo(label(shortPdf).x, 1e-6));
      expect(longPages.expand((page) => page.words).any((word) => word.text.contains('OPTEND')), isTrue);
      expect(longPages.length, after.pageCount);
      expect(plannedTailPage, greaterThan(0), reason: 'The tail must exercise a continuation page.');
      expect(tailPages, [plannedTailPage], reason: 'The actual PDF must emit the tail exactly on its planned page.');
      expect(longPages.expand((page) => page.words)
        .where((word) => word.text.contains('OPTEND')), hasLength(1));
      expect(longPages.expand((page) => page.words)
        .where((word) => word.text.trim() == 'English'), hasLength(80),
        reason: 'Every repeated source word must survive actual PDF emission, including page boundaries.');
      final tail = longPages[plannedTailPage].words.singleWhere((word) => word.text.contains('OPTEND'));
      final body = after.pages[plannedTailPage].bodyBounds;
      expect(tail.x, greaterThanOrEqualTo(body.left - 1e-6));
      expect(tail.x + tail.advanceWidth, lessThanOrEqualTo(body.right + 1e-6));
      final tailTopDownBaseline = after.pages[plannedTailPage].pageSize.height - tail.y;
      expect(tailTopDownBaseline, greaterThanOrEqualTo(body.top));
      expect(tailTopDownBaseline, lessThanOrEqualTo(body.bottom));
      final tall = await CanonicalLayoutService.resolve(document: changed,
        pageSize: const LayoutSize(width: 210 * 72 / 25.4, height: 20000));
      final ids = after.allLines.map((line) => line.id).toList()..sort();
      final referenceIds = tall.allLines.map((line) => line.id).toList()..sort();
      expect(ids, referenceIds, reason: 'Every unsplit option line must survive exactly once.');
      expect(ids.toSet().length, ids.length, reason: 'No duplicated option lines across page windows.');
    });
  });
}
