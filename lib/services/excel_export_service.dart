import 'dart:io';

import 'package:excel/excel.dart';

import '../models/question.dart';
import '../models/question_type.dart';
import 'export_file_service.dart';

/// Builds Excel (.xlsx) workbooks that mirror the question bank in a
/// structured table, ready for LMS import or printing.
abstract final class ExcelExportService {
  static const String _mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static const List<String> _headers = [
    '#',
    'نص السؤال',
    'النوع',
    'الصعوبة',
    'الدرجة',
    'المادة',
    'الوحدة / الموضوع',
    'الخيار الأول (أ)',
    'الخيار الثاني (ب)',
    'الخيار الثالث (ج)',
    'الخيار الرابع (د)',
    'الإجابة الصحيحة / النموذجية',
    'الشرح والتوضيح',
  ];

  /// Columns that render centered instead of right-aligned.
  static const Set<int> _centeredColumns = {0, 2, 3, 4};

  /// Generates the .xlsx file for [questions] and returns it as a [File].
  static Future<File> exportQuestionsToExcel({
    required List<Question> questions,
    String sheetName = 'بنك الأسئلة',
    String? fileBaseName,
    Directory? outputDirectory,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final safeSheetName = ExportFileService.sanitizeSheetName(sheetName);
    excel.rename(defaultSheet, safeSheetName);
    final sheet = excel[safeSheetName];

    _writeHeaderRow(sheet);
    for (var i = 0; i < questions.length; i++) {
      _writeDataRow(sheet, rowIndex: i + 1, number: i + 1, question: questions[i]);
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw const ExportException('تعذر توليد بايتات ملف Excel.');
    }

    return ExportFileService.writeExportFile(
      baseName: fileBaseName ?? safeSheetName,
      extension: 'xlsx',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  /// Opens the system share sheet for a previously generated file.
  static Future<void> shareExcelFile(File file, {String? subject}) {
    return ExportFileService.shareExportFile(
      file,
      mimeType: _mimeType,
      subject: subject,
    );
  }

  static void _writeHeaderRow(Sheet sheet) {
    for (var col = 0; col < _headers.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        ..value = TextCellValue(_headers[col])
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
    }
  }

  static void _writeDataRow(
    Sheet sheet, {
    required int rowIndex,
    required int number,
    required Question question,
  }) {
    final values = _dataRowValues(number, question);
    for (var col = 0; col < values.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex))
          ..value = values[col]
          ..cellStyle = CellStyle(
            horizontalAlign: _centeredColumns.contains(col)
                ? HorizontalAlign.Center
                : HorizontalAlign.Right,
          );
    }
  }

  static List<CellValue> _dataRowValues(int number, Question question) {
    return [
      TextCellValue('$number'),
      TextCellValue(question.title),
      TextCellValue(question.type.arabicLabel),
      TextCellValue(question.difficulty.arabicLabel),
      DoubleCellValue(question.marks),
      TextCellValue(question.subject),
      TextCellValue(question.topic),
      TextCellValue(_optionText(question, 0)),
      TextCellValue(_optionText(question, 1)),
      TextCellValue(_optionText(question, 2)),
      TextCellValue(_optionText(question, 3)),
      TextCellValue(_correctAnswer(question)),
      TextCellValue(question.explanation),
    ];
  }

  static String _optionText(Question question, int index) {
    final options = question.options;
    return index < options.length ? options[index].text : '';
  }

  static String _correctAnswer(Question question) {
    switch (question.type) {
      case QuestionType.multipleChoice:
        return question.options
            .where((option) => option.isCorrect)
            .map((option) => option.text)
            .join(' | ');
      case QuestionType.trueFalse:
        return question.options
            .firstWhere(
              (option) => option.isCorrect,
              orElse: () => QuestionOption(text: 'غير محدد'),
            )
            .text;
      case QuestionType.fillInTheBlank:
      case QuestionType.essay:
        return question.modelAnswer;
    }
  }
}
