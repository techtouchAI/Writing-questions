// TEMPORARY diagnostic (deleted before the final commit): prints the DOCX
// header projection to CI annotations so the missing-marker root cause is
// measured instead of guessed. No assertion here is a gate.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

import 'ooxml_probe.dart';
import 'p0_gate_fixture.dart';

String _clean(String value) => value
    .replaceAll('%', '#')
    .replaceAll('\n', ' | ')
    .replaceAll('\r', '')
    .replaceAll('::', ': ');

void _note(String title, String message) {
  debugPrint('::notice title=$title::${_clean(message)}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DIAG docx header markers', () async {
    final document = P0GateFixture.rtl();
    final blueprint = ExamBlueprint.from(document);
    final ir =
        DocumentIR.fromBlueprint(blueprint: blueprint, document: document);

    _note(
      'DIAG blueprint header',
      'right=${blueprint.header.rightLines} '
      'center=${blueprint.header.centerLines} '
      'left=${blueprint.header.leftLines}',
    );
    _note(
      'DIAG ir header',
      'right=${ir.header.rightColumn.map((e) => e.content.legacyText).toList()} '
      'center=${ir.header.centerColumn.map((e) => e.content.legacyText).toList()} '
      'left=${ir.header.leftColumn.map((e) => e.content.legacyText).toList()}',
    );

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    _note('DIAG parts', probe.partNames.join(','));

    final raw = probe.documentXml;
    final flat = probe.flatText;
    final report = <String>[
      for (final marker in P0GateFixture.headerMarkers)
        '$marker:raw=${raw.contains(marker)}:flat=${flat.contains(marker)}',
    ];
    _note('DIAG marker presence', report.join(' '));

    final tableAt = raw.indexOf('<w:tbl');
    _note(
      'DIAG first table at $tableAt',
      tableAt < 0
          ? 'no table in document.xml'
          : raw.substring(tableAt, (tableAt + 900).clamp(0, raw.length)),
    );

    final texts = <String>[
      for (final paragraph in probe.paragraphs.take(16))
        '${paragraph.index}#${paragraph.text}',
    ];
    _note('DIAG first paragraphs', texts.join(' ❙ '));
  });
}
