import 'dart:io';

import 'package:excel/excel.dart';

import '../models/label_alphabet.dart';
import '../models/main_question.dart';
import '../models/question_type.dart';
import 'export_file_service.dart';

class ExcelExportService {
  static Future<File> exportQuestionsToExcel({
    required List<MainQuestion> questions,
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
      'الفروع (أ، ب، ج...)',
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
        TextCellValue(_branchesSummary(question)),
        TextCellValue(question.type.arabicLabel),
        TextCellValue(question.difficulty.arabicLabel),
        // الدرجة الكلية = مجموع درجات الفروع آلياً (roll-up).
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

  static String _answerFor(MainQuestion question) {
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
    return column == 0 || column == 3 || column == 4 || column == 5;
  }

  /// ملخص الفروع بتسميات ديناميكية من الفهرس (أ، ب، ج...) مع الدرجات.
  static String _branchesSummary(MainQuestion question) {
    return question.branches.asMap().entries.map((entry) {
      final label = LabelAlphabet.at(entry.key);
      final marks = entry.value.marks == entry.value.marks.truncateToDouble()
          ? entry.value.marks.toInt().toString()
          : entry.value.marks.toString();
      final text = entry.value.text.trim();
      return '$label) ${text.isEmpty ? '—' : text} [$marks]';
    }).join('\n');
  }

  /// تسمية الخيار تُولَّد ديناميكياً من الفهرس (أ، ب، ج...) بلا قوائم مخزنة.
  static String _optionLabel(int index) {
    return 'الخيار ${LabelAlphabet.at(index)}';
  }
}
