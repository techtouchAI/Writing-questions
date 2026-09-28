import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports free images and text boxes at page-relative positions', () async {
    final document = ExamDocument(
      name: 'عناصر حرة',
      header: ExamHeaderModel.ministerialDefault(subject: 'اللغة الإنجليزية'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, prompt: 'Question one'),
        QuestionModel(id: 'q2', questionNumber: 2, prompt: 'Question two'),
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

  test('uses PDF pagination when Word export has no preview assignments', () async {
    final document = ExamDocument(
      name: 'توافق التصدير',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: List<String>.filled(100, 'سطر طويل لاختبار ترقيم الصفحات').join('\n'),
        ),
        QuestionModel(id: 'q2', questionNumber: 2, prompt: 'السؤال الثاني'),
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
    final assignments = await PdfExportService.resolvePageAssignments(document: document);
    expect(assignments.length, greaterThan(1));
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(document: document);
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);

    final firstPageBreak = xml.indexOf('<w:br w:type="page"/>');
    final floatingImageAnchor = xml.indexOf('wp:anchor');
    expect(firstPageBreak, greaterThanOrEqualTo(0));
    expect(floatingImageAnchor, greaterThan(firstPageBreak));
    expect(
      RegExp('<w:br w:type="page"/>').allMatches(xml).length,
      assignments.length - 1,
    );
  });

  test('global attachment mirrors do not print empty question or branch labels', () async {
    final globalMirror = FloatingElement(
      id: 'global-only-mirror',
      type: FloatingElementType.shape,
      shape: FloatingShapeType.square,
      width: 24,
      height: 24,
    );
    final document = ExamDocument(
      name: 'مرآة عنصر حر',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
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

    final assignments = await PdfExportService.resolvePageAssignments(document: document);
    expect(assignments.expand((page) => page), isEmpty);
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(document: document);
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
    expect(xml, isNot(contains('NO_GHOST_BRANCH')));
  });
}
