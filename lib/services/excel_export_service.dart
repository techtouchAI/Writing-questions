import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import '../models/exam.dart';

class ExcelExportService {
  static Future<File> exportQuestionsToExcel({
    required List<Question> questions,
    String sheetName = 'بنك الأسئلة',
    String? fileName,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, sheetName);
    final sheet = excel[sheetName];

    // Configure Header Columns
    final headers = [
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

    // Add Header Row
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }

    // Add Data Rows
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final rowIndex = i + 1;

      String optionA = '';
      String optionB = '';
      String optionC = '';
      String optionD = '';
      String correctAnswer = '';

      if (q.type == QuestionType.multipleChoice) {
        if (q.options.isNotEmpty) optionA = q.options[0].text;
        if (q.options.length > 1) optionB = q.options[1].text;
        if (q.options.length > 2) optionC = q.options[2].text;
        if (q.options.length > 3) optionD = q.options[3].text;

        final correctOptions = q.options.where((o) => o.isCorrect).map((o) => o.text).toList();
        correctAnswer = correctOptions.join(' | ');
      } else if (q.type == QuestionType.trueFalse) {
        final correct = q.options.firstWhere(
          (o) => o.isCorrect,
          orElse: () => QuestionOption(text: 'غير محدد', isCorrect: false),
        );
        correctAnswer = correct.text;
      } else {
        correctAnswer = q.modelAnswer;
      }

      final rowData = [
        TextCellValue('${i + 1}'),
        TextCellValue(q.title),
        TextCellValue(q.type.arabicLabel),
        TextCellValue(q.difficulty.arabicLabel),
        DoubleCellValue(q.marks),
        TextCellValue(q.subject),
        TextCellValue(q.topic),
        TextCellValue(optionA),
        TextCellValue(optionB),
        TextCellValue(optionC),
        TextCellValue(optionD),
        TextCellValue(correctAnswer),
        TextCellValue(q.explanation),
      ];

      for (int col = 0; col < rowData.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
        cell.value = rowData[col];
        cell.cellStyle = CellStyle(
          horizontalAlign: (col == 0 || col == 2 || col == 3 || col == 4)
              ? HorizontalAlign.Center
              : HorizontalAlign.Right,
        );
      }
    }

    final fileBytes = excel.save();
    if (fileBytes == null) {
      throw Exception('فشل إنشاء بايتات ملف Excel');
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'اسئلة_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File('${outputDir.path}/$name');
    await file.writeAsBytes(fileBytes, flush: true);
    return file;
  }

  static Future<void> shareExcelFile(File file, {String? subject}) async {
    final xFile = XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await Share.shareXFiles([xFile], text: subject ?? 'تصدير الأسئلة بصيغة Excel');
  }
}
