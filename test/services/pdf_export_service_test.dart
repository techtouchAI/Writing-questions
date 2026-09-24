import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/main_question.dart';
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

  Exam buildExam() {
    return Exam(
      name: 'اختبار الرياضيات',
      header: ExamHeader(
        subject: 'الرياضيات',
        gradeStage: 'الصف الخامس الابتدائي',
        instructor: 'أ. سعد',
      ),
      mainQuestions: [
        MainQuestion(
          title: 'احسب ناتج 15 × 4.',
          type: QuestionType.multipleChoice,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 2)],
        ),
        MainQuestion(
          title: 'اكتب خطوات الحل.',
          type: QuestionType.essay,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 5)],
        ),
      ],
    );
  }

  test('buildExamPdfBytes returns a real PDF payload', () async {
    final bytes = await PdfExportService.buildExamPdfBytes(
      exam: buildExam(),
      isTeacherVersion: false,
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
  });

  test('exportExamToPdf writes a .pdf file into the destination', () async {
    final file = await PdfExportService.exportExamToPdf(
      exam: buildExam(),
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
