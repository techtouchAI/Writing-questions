import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/pagination_engine.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports free images and text boxes at page-relative positions', () async {
    final document = ExamDocument(
      name: 'عناصر حرة',
      header: ExamHeaderModel.initial(subject: 'اللغة الإنجليزية'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'Question one'),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'Question two'),
      ],
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'free-text',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          label: 'مربع نص حر',
          dx: 80,
          dy: 150,
          width: 150,
          height: 70,
          framed: true,
        ),
        FloatingElement(
          id: 'free-image',
          type: FloatingElementType.image,
          bytes: _pngBytes,
          dx: 40,
          dy: 90,
          pageIndex: 1,
          width: 100,
          height: 60,
        ),
      ],
    );

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
      pageAssignments: const <List<String>>[
        <String>['q1'],
        <String>['q2'],
      ],
      legacyPaginationInput: PaginationInput(
        blocks: const <PageBlock>[
          PageBlock(id: PaperMetrics.headerBlockId, height: 0),
          PageBlock(id: 'q1', height: 600),
          PageBlock(id: 'q2', height: 600),
        ],
        pageHeight: 1000,
        footerMeasured: true,
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xmlFile = archive.findFile('word/document.xml');
    expect(xmlFile, isNotNull);
    final xml = utf8.decode(xmlFile!.content as List<int>);

    expect(xml, contains('مربع نص حر'));
    expect(xml, contains('wp:anchor'));
    expect(xml, contains('wp:positionH relativeFrom="page"'));
    expect(xml, contains('wp:positionV relativeFrom="page"'));
    expect(xml, contains('w:tblpPr w:horzAnchor="page" w:vertAnchor="page"'));
    expect(xml, contains('<w:br w:type="page"/>'));
    expect(xml.indexOf('<w:br w:type="page"/>'), lessThan(xml.indexOf('Question two')));
    expect(archive.findFile('word/media/image1.png'), isNotNull);

    final relationships = archive.findFile('word/_rels/document.xml.rels');
    expect(relationships, isNotNull);
    expect(
      utf8.decode(relationships!.content as List<int>),
      contains('Target="media/image1.png"'),
    );
  });

  test('floating OOXML anchors preserve measured RTL/LTR positions and extents', () async {
    for (final subject in <String>['الرياضيات', 'English']) {
      final isLtr = subject == 'English';
      final document = ExamDocument(
        name: 'Floating geometry',
        header: ExamHeaderModel.initial(subject: subject),
        questions: <QuestionModel>[
          QuestionModel(id: 'q1', questionNumber: 1, statement: 'BODY1'),
        ],
        floatingElements: <FloatingElement>[
          FloatingElement(
            id: 'free-image',
            type: FloatingElementType.image,
            bytes: _pngBytes,
            dx: 40,
            dy: 90,
            width: 100,
            height: 60,
          ),
          FloatingElement(
            id: 'owned-image',
            type: FloatingElementType.image,
            bytes: _pngBytes,
            dx: 40,
            dy: 90,
            width: 100,
            height: 60,
            ownerQuestionId: 'q1',
          ),
        ],
      );
      final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
        document: document,
        pageAssignments: const <List<String>>[
          <String>['q1'],
        ],
        legacyPaginationInput: PaginationInput(
          blocks: const <PageBlock>[
            PageBlock(id: PaperMetrics.headerBlockId, height: 0),
            PageBlock(id: 'q1', height: 100),
          ],
          pageHeight: 1000,
          footerMeasured: true,
        ),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );
      final freeAnchor = _anchorForRelation(xml, 'rIdImg2');
      final ownedAnchor = _anchorForRelation(xml, 'rIdImg3');
      final freeHorizontal = _position(freeAnchor, 'wp:positionH');
      final freeVertical = _position(freeAnchor, 'wp:positionV');
      final ownedHorizontal = _position(ownedAnchor, 'wp:positionH');
      final ownedVertical = _position(ownedAnchor, 'wp:positionV');
      final referenceWidth = isLtr
          ? ExamCanvasGeometry.width
          : PaperMetrics.contentWidthFor(document.settings.marginMm);
      final freeReferenceWidth = ExamCanvasGeometry.width;
      final freeLeft = isLtr ? 40.0 : freeReferenceWidth - 40 - 100;
      final ownedLeft = isLtr ? 40.0 : referenceWidth - 40 - 100;
      final expectedX = (PaperMetrics.pt(freeLeft) * 12700).round();
      final expectedOwnedX = (PaperMetrics.pt(ownedLeft) * 12700).round();
      final expectedY = (PaperMetrics.pt(90) * 12700).round();
      final expectedWidth = (PaperMetrics.pt(100) * 12700).round();
      final expectedHeight = (PaperMetrics.pt(60) * 12700).round();

      expect(freeHorizontal.$1, 'page', reason: 'subject=$subject');
      expect(freeHorizontal.$2, expectedX, reason: 'subject=$subject');
      expect(freeVertical.$1, 'page', reason: 'subject=$subject');
      expect(freeVertical.$2, expectedY, reason: 'subject=$subject');
      expect(ownedHorizontal.$1, 'column', reason: 'subject=$subject');
      expect(ownedHorizontal.$2, expectedOwnedX, reason: 'subject=$subject');
      expect(ownedVertical.$1, 'paragraph', reason: 'subject=$subject');
      expect(ownedVertical.$2, expectedY, reason: 'subject=$subject');
      for (final anchor in <String>[freeAnchor, ownedAnchor]) {
        expect(_extent(anchor), (<int>[expectedWidth, expectedHeight]),
            reason: 'x/y/width/height must stay in canonical logical-pixel '
                'units for subject=$subject.');
      }
    }
  });

  test('ignores out-of-order PDF assignments and keeps PaginationEngine source order', () async {
    final document = ExamDocument(
      name: 'ترتيب التوزيع',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'Question one'),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'Question two'),
      ],
    );
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
      pageAssignments: const <List<String>>[
        <String>['q2'],
        <String>['q1'],
      ],
      legacyPaginationInput: PaginationInput(
        blocks: const <PageBlock>[
          PageBlock(id: PaperMetrics.headerBlockId, height: 0),
          PageBlock(id: 'q1', height: 600),
          PageBlock(id: 'q2', height: 600),
        ],
        pageHeight: 1000,
        footerMeasured: true,
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
    final pageBreak = xml.indexOf('<w:br w:type="page"/>');
    final questionOne = xml.indexOf('Question one');
    final questionTwo = xml.indexOf('Question two');

    expect(pageBreak, greaterThan(questionOne));
    expect(pageBreak, lessThan(questionTwo));
    expect(
      RegExp('<w:br w:type="page"/>').allMatches(xml),
      hasLength(1),
      reason: 'A legacy PDF page list must not select editable Word pages; '
          'PaginationEngine preserves the source order and measured grouping.',
    );
  });

  test('rejects PaginationInput blocks that reorder the source questions', () async {
    final document = ExamDocument(
      name: 'ترتيب مدخلات التقسيم',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'Question one'),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'Question two'),
      ],
    );
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
      pageAssignments: const <List<String>>[
        <String>['q2'],
        <String>['q1'],
      ],
      legacyPaginationInput: PaginationInput(
        blocks: const <PageBlock>[
          PageBlock(id: PaperMetrics.headerBlockId, height: 0),
          PageBlock(id: 'q2', height: 600),
          PageBlock(id: 'q1', height: 600),
        ],
        pageHeight: 1000,
        footerMeasured: true,
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);

    expect(xml.indexOf('Question one'), lessThan(xml.indexOf('Question two')));
  });

  test('missing header measurement falls back to canonical block geometry', () async {
    final document = ExamDocument(
      name: 'قياس الترويسة',
      header: ExamHeaderModel.initial(subject: 'English'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'A'),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'B'),
      ],
    );
    final expectedBytes =
        await DocxDocumentExportService.buildDocumentDocxBytes(document: document);
    final malformedInput = PaginationInput(
      blocks: const <PageBlock>[
        PageBlock(id: 'q1', height: 600),
        PageBlock(id: 'q2', height: 600),
      ],
      pageHeight: 1000,
      footerMeasured: true,
    );
    expect(malformedInput.paginate().pageCount, 2);
    final actualBytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
      pageAssignments: const <List<String>>[
        <String>['q1'],
        <String>['q2'],
      ],
      legacyPaginationInput: malformedInput,
    );
    final expectedXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(expectedBytes)
          .findFile('word/document.xml')!
          .content as List<int>,
    );
    final actualXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(actualBytes)
          .findFile('word/document.xml')!
          .content as List<int>,
    );
    int pageBreakCount(String xml) =>
        RegExp('<w:br w:type="page"/>').allMatches(xml).length;

    expect(pageBreakCount(expectedXml), 0,
        reason: 'The short-question fallback fixture should fit one page.');
    expect(pageBreakCount(actualXml), pageBreakCount(expectedXml),
        reason: 'An input without the required header block was accepted.');
  });

  test('direct Word export follows its measured PaginationEngine plan without a PDF plan', () async {
    final document = ExamDocument(
      name: 'توافق التصدير',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          body: List<String>.filled(100, 'سطر طويل لاختبار ترقيم الصفحات').join('\n'),
        ),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'السؤال الثاني'),
      ],
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'free-image',
          type: FloatingElementType.image,
          bytes: _pngBytes,
          dx: 40,
          dy: 90,
          pageIndex: 1,
          width: 100,
          height: 60,
        ),
      ],
    );
    final legacyInput =
        await DocxDocumentExportService.resolveEditablePaginationInput(
      document: document,
    );
    final expectedPages = legacyInput.paginate().pages
        .where((page) => page.blockIds.any((id) => id != PaperMetrics.headerBlockId))
        .toList(growable: false);
    expect(expectedPages.length, greaterThan(1));
    // Deliberately omit pageAssignments and the measured input: the public
    // direct-export path must resolve its own DOCX pagination plan.
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);

    final firstPageBreak = xml.indexOf('<w:br w:type="page"/>');
    final floatingImageAnchor = xml.indexOf('wp:anchor');
    expect(firstPageBreak, greaterThanOrEqualTo(0));
    expect(floatingImageAnchor, greaterThan(firstPageBreak));
    final docxPageBreaks =
        RegExp('<w:br w:type="page"/>').allMatches(xml).length;
    expect(docxPageBreaks, expectedPages.length - 1,
        reason: 'The generated Word breaks must follow the independently '
            'resolved LegacyDocxAdapter → PaginationEngine plan.');
  });

  test('editable DOCX keeps mixed Arabic and Latin run directions on RTL and LTR paper', () async {
    Future<String> exportMixed(String subject) async {
      final document = ExamDocument(
        name: 'Mixed direction',
        header: ExamHeaderModel.initial(subject: subject),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'mixed',
            questionNumber: 1,
            statement: 'Direction test',
            body: 'قبل MIXLTR1 بعد',
          ),
        ],
      );
      final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
        document: document,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
    }

    String paragraphFor(String xml, String marker) =>
        RegExp('<w:p(?:\\s[^>]*)?>.*?</w:p>', dotAll: true)
            .allMatches(xml)
            .map((match) => match.group(0)!)
            .firstWhere((paragraph) => paragraph.contains(marker));

    String runFor(String paragraph, String marker) =>
        RegExp('<w:r>.*?</w:r>', dotAll: true)
            .allMatches(paragraph)
            .map((match) => match.group(0)!)
            .firstWhere((run) => run.contains(marker));

    for (final subject in <String>['اللغة العربية', 'English']) {
      final xml = await exportMixed(subject);
      final paragraph = paragraphFor(xml, 'MIXLTR1');
      expect(paragraph, contains('<w:bidi/>'), reason: 'subject=$subject');
      expect(runFor(paragraph, 'قبل'), contains('<w:rtl/>'), reason: 'subject=$subject');
      expect(runFor(paragraph, 'MIXLTR1'), isNot(contains('<w:rtl/>')),
          reason: 'Latin segment should remain LTR on subject=$subject');
      expect(runFor(paragraph, 'بعد'), contains('<w:rtl/>'), reason: 'subject=$subject');
    }
  });

  test('global attachment mirrors do not print empty question or branch labels', () async {
    final globalMirror = FloatingElement(
      id: 'global-only-mirror',
      type: FloatingElementType.shape,
      shape: FloatingShapeType.square,
      dx: 0,
      dy: 0,
      width: 24,
      height: 24,
    );
    final document = ExamDocument(
      name: 'مرآة عنصر حر',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'mirror-owner',
          questionNumber: 1,
          branches: <BranchModel>[
            BranchModel(
              labelOverride: 'NO_GHOST_BRANCH',
              content: BranchContent.empty(),
              attachments: <FloatingElement>[globalMirror],
            ),
          ],
        ),
      ],
      floatingElements: <FloatingElement>[globalMirror],
    );

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(document: document);
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
    expect(xml, isNot(contains('NO_GHOST_BRANCH')));
  });
}

String _anchorForRelation(String xml, String relationId) {
  final relationOffset = xml.indexOf('r:embed="$relationId"');
  expect(relationOffset, greaterThanOrEqualTo(0));
  final start = xml.lastIndexOf('<wp:anchor', relationOffset);
  final close = xml.indexOf('</wp:anchor>', relationOffset);
  expect(start, greaterThanOrEqualTo(0));
  expect(close, greaterThan(relationOffset));
  return xml.substring(start, close + '</wp:anchor>'.length);
}

(String, int) _position(String anchor, String element) {
  final match = RegExp(
    '<$element relativeFrom="([^"]+)"><wp:posOffset>(\\d+)</wp:posOffset></$element>',
  ).firstMatch(anchor);
  expect(match, isNotNull, reason: 'Missing numeric $element in $anchor');
  return (match!.group(1)!, int.parse(match.group(2)!));
}

List<int> _extent(String anchor) {
  final match = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"').firstMatch(anchor);
  expect(match, isNotNull, reason: 'Missing drawing extent in $anchor');
  return <int>[int.parse(match!.group(1)!), int.parse(match.group(2)!)];
}
