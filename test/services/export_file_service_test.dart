import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/export_file_service.dart';

void main() {
  test('writes a portable export name without duplicating its extension', () async {
    final directory = await Directory.systemTemp.createTemp('export_file_test');
    addTearDown(() => directory.delete(recursive: true));

    final file = await ExportFileService.writeExportFile(
      baseName: 'نتيجة: الاختبار.xlsx',
      extension: '.xlsx',
      bytes: <int>[1, 2, 3],
      destination: directory,
    );

    final name = file.uri.pathSegments.last;
    expect(name, endsWith('.xlsx'));
    expect(name, isNot(contains('.xlsx_')));
    expect(name, isNot(contains(':')));
    expect(await file.readAsBytes(), <int>[1, 2, 3]);
  });
}
