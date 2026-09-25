import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_export_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  ExamDocument buildDocument() {
    return ExamDocument(
      name: 'نموذج الرياضيات',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          questionNumber: 1,
          prompt: 'احسب ناتج 15 × 4.',
          branches: <BranchModel>[
            BranchModel(
              content: BranchContent(type: QuestionType.essay, text: 'اكتب خطوات الحل.'),
              marks: 5,
            ),
          ],
        ),
      ],
    );
  }

  test('buildDocumentPdfBytes returns a real PDF payload', () async {
    final bytes = await PdfExportService.buildDocumentPdfBytes(
      document: buildDocument(),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
  });

  test('exportDocumentToPdf writes a .pdf file into the destination', () async {
    final file = await PdfExportService.exportDocumentToPdf(
      document: buildDocument(),
      isTeacherVersion: true,
      outputDirectory: tempDir,
    );

    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.pdf'));
    expect(await file.length(), greaterThan(5 * 1024));
    final head = await file.openRead(0, 8).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    expect(String.fromCharCodes(head), startsWith('%PDF-'));
  });
}
