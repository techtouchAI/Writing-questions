import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/services/docx_export_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docx_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Exam buildExam() {
    return Exam(
      name: 'اختبار تجريبي',
      header: ExamHeader(),
      mainQuestions: [
        MainQuestion(
          title: 'ما هي عاصمة العراق؟',
          type: QuestionType.multipleChoice,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 2)],
          options: [
            QuestionOption(text: 'بغداد', isCorrect: true),
            QuestionOption(text: 'البصرة'),
          ],
          explanation: 'معلومة عامة',
        ),
        MainQuestion(
          title: 'الأرض تدور حول الشمس.',
          type: QuestionType.trueFalse,
          options: [
            QuestionOption(text: 'صح', isCorrect: true),
            QuestionOption(text: 'خطأ'),
          ],
        ),
        MainQuestion(
          title: 'وحدة قياس التيار هي _____.',
          type: QuestionType.fillInTheBlank,
          modelAnswer: 'الأمبير',
        ),
        MainQuestion(
          title: 'ناقش دور الطاقة المتجددة.',
          type: QuestionType.essay,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 5)],
          modelAnswer: 'عناصر الإجابة',
        ),
      ],
    );
  }

  test('produces a valid OOXML zip package', () async {
    final file = await DocxExportService.exportExamToDocx(
      exam: buildExam(),
      outputDirectory: tempDir,
    );

    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.docx'));

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final partNames = archive.files.map((f) => f.name).toSet();

    expect(partNames, containsAll(<String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
      'word/styles.xml',
      'word/_rels/document.xml.rels',
    ]));
  });

  test('escapes XML-sensitive characters in Arabic content', () async {
    final exam = Exam(
      name: 'اختبار',
      mainQuestions: [
        MainQuestion(title: 'سؤال بعلامات <&>" خاصة', type: QuestionType.essay),
      ],
    );

    final file = await DocxExportService.exportExamToDocx(
      exam: exam,
      outputDirectory: tempDir,
    );

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final document =
        utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);

    expect(document, contains('سؤال بعلامات &lt;&amp;&gt;&quot; خاصة'));
    expect(document.contains('<&>'), isFalse, reason: 'raw XML must be escaped');
  });

  test('student version hides answers; teacher version shows them', () async {
    Future<String> documentXml({required bool isTeacher}) async {
      final file = await DocxExportService.exportExamToDocx(
        exam: buildExam(),
        isTeacherVersion: isTeacher,
        outputDirectory: tempDir,
      );
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
    }

    final student = await documentXml(isTeacher: false);
    final teacher = await documentXml(isTeacher: true);

    // Student paper: blank answer areas, no correct answers.
    expect(student, contains('اسم الطالب'));
    expect(student, contains('الإجابة: (     ) صح'));
    expect(student, isNot(contains('الإجابة الصحيحة')));

    // Teacher paper: correct answers, model answers and grading notes.
    expect(teacher, contains('نموذج الإجابة'));
    expect(teacher, contains('الإجابة الصحيحة: صح'));
    expect(teacher, contains('الإجابة النموذجية: الأمبير'));
    expect(teacher, contains('بغداد  ✔'));
    expect(teacher, contains('سبب الإجابة / الملاحظات: معلومة عامة'));
  });

  test('supports multi-mark formatting without trailing zeros', () async {
    final exam = buildExam(); // total = 2 + 1 + 1 + 5 = 9

    final file = await DocxExportService.exportExamToDocx(
      exam: exam,
      outputDirectory: tempDir,
    );
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final document =
        utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);

    expect(document, contains('الدرجة الكلية: 9 درجة'));
    expect(document, contains('[2 درجة]'));
    expect(document, contains('[5 درجة]'));
  });
}
