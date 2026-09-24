import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/services/excel_export_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('xlsx_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('produces a decodable workbook with the expected rows', () async {
    final file = await ExcelExportService.exportQuestionsToExcel(
      questions: [
        MainQuestion(
          title: 'سؤال اختيار من متعدد',
          type: QuestionType.multipleChoice,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 2)],
          subject: 'العلوم',
          options: [
            QuestionOption(text: 'أ', isCorrect: true),
            QuestionOption(text: 'ب'),
            QuestionOption(text: 'ج'),
            QuestionOption(text: 'د'),
          ],
          explanation: 'شرح',
        ),
        MainQuestion(
          title: 'سؤال مقالي',
          type: QuestionType.essay,
          branches: <QuestionBranch>[QuestionBranch(text: '', marks: 5)],
          modelAnswer: 'الإجابة النموذجية',
        ),
      ],
      sheetName: 'بنك الأسئلة',
      fileBaseName: 'بنك_الأسئلة',
      outputDirectory: tempDir,
    );

    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.xlsx'));

    final excel = Excel.decodeBytes(await file.readAsBytes());
    expect(excel.tables.keys, contains('بنك الأسئلة'));

    final sheet = excel.tables['بنك الأسئلة']!;
    expect(sheet.maxRows, 3, reason: 'header row + 2 data rows');

    String text(int column, int row) {
      final value =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row)).value;
      if (value is TextCellValue) {
        return value.value.text ?? '';
      }
      return value?.toString() ?? '';
    }

    // Header row.
    expect(text(1, 0), 'نص السؤال');

    // MCQ row: correct answers joined, options spread across columns.
    expect(text(1, 1), 'سؤال اختيار من متعدد');
    expect(text(7, 1), 'أ');
    expect(text(8, 1), 'ب');
    expect(text(11, 1), 'أ');

    // Essay row: model answer lands in the answer column.
    expect(text(1, 2), 'سؤال مقالي');
    expect(text(11, 2), 'الإجابة النموذجية');
  });

  test('sanitizes illegal worksheet characters', () async {
    final file = await ExcelExportService.exportQuestionsToExcel(
      questions: [MainQuestion(title: 'سؤال', type: QuestionType.trueFalse)],
      sheetName: 'اسم يحتوي: رموز* ممنوعة[] وتجاوز الثين والثلثين من الحروف 12345',
      fileBaseName: 'تصدير',
      outputDirectory: tempDir,
    );

    final excel = Excel.decodeBytes(await file.readAsBytes());
    final sheetName = excel.tables.keys.first;

    expect(sheetName, isNot(contains(RegExp(r'[\\/*?:\[\]]'))));
    expect(sheetName.length, lessThanOrEqualTo(31));
  });
}
