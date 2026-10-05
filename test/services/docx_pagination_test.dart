import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/pagination_engine.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measured header height changes editable DOCX page ownership', () async {
    final shortHeaderDocument = _document(schoolName: 'مدرسة قصيرة');
    final longHeaderDocument = _document(
      schoolName: 'HDRLONG ${List<String>.filled(90, 'مدرسة').join(' ')}',
    );
    final shortMeasurement =
        await DocxDocumentExportService.resolveEditablePaginationInput(
      document: shortHeaderDocument,
    );
    final longMeasurement =
        await DocxDocumentExportService.resolveEditablePaginationInput(
      document: longHeaderDocument,
    );
    final shortHeaderHeight = _headerHeight(shortMeasurement);
    final longHeaderHeight = _headerHeight(longMeasurement);

    expect(longHeaderHeight, greaterThan(shortHeaderHeight),
        reason: 'The wrapped header must contribute its measured height.');
    expect(longMeasurement.footerMeasured, isTrue);
    expect(longMeasurement.lastPageReserve, greaterThan(0));

    final shortCapacity = _singlePageQuestionCapacity(shortMeasurement);
    final longCapacity = _singlePageQuestionCapacity(longMeasurement);
    expect(shortCapacity, greaterThan(longCapacity));
    expect(longCapacity, greaterThan(0));
    final totalQuestionHeight = (shortCapacity + longCapacity) / 2;
    final questionHeight = totalQuestionHeight / 2;
    final shortPlan = _withQuestionHeights(shortMeasurement, questionHeight);
    final longPlan = _withQuestionHeights(longMeasurement, questionHeight);

    expect(shortPlan.paginate().pageCount, 1,
        reason: 'The short measured header should leave room for both questions.');
    expect(longPlan.paginate().pageCount, 2,
        reason: 'The tall measured header should move the second question.');

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: longHeaderDocument,
      // A complete but infeasible one-page candidate must not override the
      // page grouping independently produced by PaginationEngine.
      pageAssignments: const <List<String>>[
        <String>['q1', 'q2'],
      ],
      legacyPaginationInput: longPlan,
    );
    final xml = _documentXml(bytes);
    final firstBreak = xml.indexOf('<w:br w:type="page"/>');

    expect(firstBreak, greaterThan(xml.indexOf('BODY1')));
    expect(firstBreak, lessThan(xml.indexOf('BODY2')));
    expect(xml.indexOf('HDRLONG'), lessThan(xml.indexOf('BODY1')),
        reason: 'Header content must precede the source-ordered body.');
    expect(xml.indexOf('DOCXFTR1'), greaterThan(xml.indexOf('BODY2')),
        reason: 'Footer content must follow the final body question.');
    expect(_pageBreakCount(xml), longPlan.paginate().pageCount - 1);
  });

  test('measured footer reserve moves body content and prevents last-page overlap', () async {
    final shortFooterDocument = _document(footerName: 'A');
    final longFooterDocument = _document(
      footerName: List<String>.filled(240, 'SIGNER').join(' '),
    );
    final shortMeasurement =
        await DocxDocumentExportService.resolveEditablePaginationInput(
      document: shortFooterDocument,
    );
    final longMeasurement =
        await DocxDocumentExportService.resolveEditablePaginationInput(
      document: longFooterDocument,
    );

    expect(shortMeasurement.footerMeasured, isTrue);
    expect(longMeasurement.footerMeasured, isTrue);
    expect(longMeasurement.lastPageReserve,
        greaterThan(shortMeasurement.lastPageReserve),
        reason: 'Wrapped signature geometry must increase the footer reserve.');

    final headerHeight = _headerHeight(longMeasurement);
    final unreservedCapacity = longMeasurement.pageHeight -
        headerHeight -
        2 * longMeasurement.spacing;
    final reservedCapacity =
        unreservedCapacity - longMeasurement.lastPageReserve;
    expect(longMeasurement.lastPageReserve, greaterThan(0));
    expect(reservedCapacity, greaterThan(0));
    final totalQuestionHeight = (unreservedCapacity + reservedCapacity) / 2;
    final questionHeight = totalQuestionHeight / 2;
    final withoutFooterReserve = _withQuestionHeights(
      longMeasurement,
      questionHeight,
      lastPageReserve: 0,
    );
    final withFooterReserve = _withQuestionHeights(
      longMeasurement,
      questionHeight,
    );

    expect(withoutFooterReserve.paginate().pageCount, 1,
        reason: 'Without measured footer space, both body blocks fit.');
    final reservedPlan = withFooterReserve.paginate();
    expect(reservedPlan.pageCount, 2,
        reason: 'The final body block must move to protect the footer area.');
    expect(
      reservedPlan.pages.last.usedHeight + withFooterReserve.lastPageReserve,
      lessThanOrEqualTo(withFooterReserve.pageHeight + 0.01),
      reason: 'The last-page body and measured footer reserve overlap.',
    );

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: longFooterDocument,
      pageAssignments: const <List<String>>[
        <String>['q1', 'q2'],
      ],
      legacyPaginationInput: withFooterReserve,
    );
    final xml = _documentXml(bytes);
    final firstBreak = xml.indexOf('<w:br w:type="page"/>');
    final bodyTwo = xml.indexOf('BODY2');
    final footer = xml.indexOf('DOCXFTR1');

    expect(firstBreak, greaterThan(xml.indexOf('BODY1')));
    expect(firstBreak, lessThan(bodyTwo));
    expect(footer, greaterThan(bodyTwo));
    expect(_pageBreakCount(xml), reservedPlan.pageCount - 1);
    expect(xml, contains('w:tblpYSpec="bottom"'),
        reason: 'The measured footer is anchored to the last-page bottom.');
  });
}

ExamDocument _document({
  String schoolName = 'مدرسة قصيرة',
  String footerName = 'A',
}) =>
    ExamDocument(
      name: 'DOCX pagination geometry',
      header: ExamHeaderModel(
        schoolName: schoolName,
        showBismillah: false,
        examType: 'اختبار',
        academicYear: '2026/2027',
        subject: 'English',
      ),
      footer: ExamFooterModel(
        closingPhrase: 'DOCXFTR1',
        primary: SignatureModel(name: footerName),
      ),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'BODY1'),
        QuestionModel(id: 'q2', questionNumber: 2, statement: 'BODY2'),
      ],
    );

double _headerHeight(PaginationInput input) => input.blocks
    .firstWhere((block) => block.id == PaperMetrics.headerBlockId)
    .height;

double _singlePageQuestionCapacity(PaginationInput input) =>
    input.pageHeight -
    _headerHeight(input) -
    input.lastPageReserve -
    2 * input.spacing;

PaginationInput _withQuestionHeights(
  PaginationInput measured,
  double questionHeight, {
  double? lastPageReserve,
}) =>
    PaginationInput(
      blocks: <PageBlock>[
        PageBlock(
          id: PaperMetrics.headerBlockId,
          height: _headerHeight(measured),
        ),
        PageBlock(id: 'q1', height: questionHeight),
        PageBlock(id: 'q2', height: questionHeight),
      ],
      pageHeight: measured.pageHeight,
      spacing: measured.spacing,
      lastPageReserve: lastPageReserve ?? measured.lastPageReserve,
      footerMeasured: measured.footerMeasured,
    );

String _documentXml(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('word/document.xml');
  expect(file, isNotNull);
  return utf8.decode(file!.content as List<int>);
}

int _pageBreakCount(String xml) =>
    RegExp('<w:br w:type="page"/>').allMatches(xml).length;
