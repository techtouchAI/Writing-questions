import 'dart:io';

import 'package:excel/excel.dart';

import '../models/question.dart';
import '../models/question_type.dart';
import 'export_file_service.dart';

class ExcelExportService {
  static Future<File> exportQuestionsToExcel({
    required List<Question> questions,
    String sheetName = 'بنك الأسئلة',
    String? fileName,
    String? fileBaseName,
    Directory? outputDirectory,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final safeSheetName = ExportFileService.sanitizeSheetName(sheetName);
    excel.rename(defaultSheet, safeSheetName);
    final sheet = excel[safeSheetName];
    final maxOptions = questions.fold<int>(
      0,
      (maximum, question) => question.options.length > maximum
          ? question.options.length
          : maximum,
    );

    final headers = <String>[
      '#',
      'نص السؤال',
      'النوع',
      'الصعوبة',
      'الدرجة',
      'المادة',
      'الوحدة / الموضوع',
      ...List<String>.generate(
        maxOptions,
        (index) => 'الخيار ${_optionLabel(index)}',
      ),
      'الإجابة الصحيحة / النموذجية',
      'الشرح والتوضيح',
    ];

    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[column]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }

    for (var index = 0; index < questions.length; index++) {
      final question = questions[index];
      final rowData = <CellValue>[
        TextCellValue('${index + 1}'),
        TextCellValue(question.title),
        TextCellValue(question.type.arabicLabel),
        TextCellValue(question.difficulty.arabicLabel),
        DoubleCellValue(question.marks),
        TextCellValue(question.subject),
        TextCellValue(question.topic),
        ...List<CellValue>.generate(
          maxOptions,
          (optionIndex) => TextCellValue(
            optionIndex < question.options.length
                ? question.options[optionIndex].text
                : '',
          ),
        ),
        TextCellValue(_answerFor(question)),
        TextCellValue(question.explanation),
      ];

      for (var column = 0; column < rowData.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: index + 1),
        );
        cell.value = rowData[column];
        cell.cellStyle = CellStyle(
          horizontalAlign: _isCenteredColumn(column)
              ? HorizontalAlign.Center
              : HorizontalAlign.Right,
          verticalAlign: VerticalAlign.Top,
        );
      }
    }

    final fileBytes = excel.save();
    if (fileBytes == null) {
      throw StateError('فشل إنشاء بيانات ملف Excel.');
    }

    return ExportFileService.writeExportFile(
      baseName: fileName ?? fileBaseName ?? 'بنك_الأسئلة',
      extension: 'xlsx',
      bytes: fileBytes,
      destination: outputDirectory,
    );
  }

  static Future<void> shareExcelFile(File file, {String? subject}) {
    return ExportFileService.shareExportFile(
      file,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      subject: subject ?? 'تصدير الأسئلة بصيغة Excel',
    );
  }

  static String _answerFor(Question question) {
    if (question.type == QuestionType.multipleChoice) {
      return question.options
          .where((option) => option.isCorrect)
          .map((option) => option.text)
          .join(' | ');
    }
    if (question.type == QuestionType.trueFalse) {
      final correctOptions = question.options
          .where((option) => option.isCorrect)
          .map((option) => option.text)
          .toList(growable: false);
      return correctOptions.isEmpty ? 'غير محدد' : correctOptions.first;
    }
    return question.modelAnswer;
  }

  static bool _isCenteredColumn(int column) {
    return column == 0 || column == 2 || column == 3 || column == 4;
  }

  static String _optionLabel(int index) {
    const labels = <String>['الأول (أ)', 'الثاني (ب)', 'الثالث (ج)', 'الرابع (د)', 'الخامس (هـ)', 'السادس (و)'];
    return index < labels.length ? labels[index] : '${index + 1}';
  }
}
