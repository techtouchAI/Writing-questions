import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/export_file_name.dart';

void main() {
  group('ExportFileName', () {
    test('creates a safe extension-normalized filename', () {
      final name = ExportFileName.fileName(
        value: '  اختبار/الرياضيات.XLSX  ',
        extension: '.xlsx',
        fallbackStem: 'بنك_الأسئلة',
      );

      expect(name, 'اختبار_الرياضيات.xlsx');
      expect(name.contains('/'), isFalse);
    });

    test('uses a fallback when a filename contains no usable stem', () {
      final name = ExportFileName.fileName(
        value: '///',
        extension: 'docx',
        fallbackStem: 'ورقة_الامتحان',
      );

      expect(name, 'ورقة_الامتحان.docx');
    });

    test('limits worksheet names and removes unsupported characters', () {
      final sheetName = ExportFileName.excelSheetName(
        'اختبار: الرياضيات/الفصل الأول * نسخة موسعة جداً جداً',
      );

      expect(sheetName.runes.length, lessThanOrEqualTo(31));
      expect(RegExp(r'[\[\]:*?/\\]').hasMatch(sheetName), isFalse);
    });
  });
}
