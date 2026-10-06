// Focused regression for per-run direction in editable DOCX (the G06
// contract): inside one RTL title paragraph, Arabic runs carry `w:rtl`
// while the embedded English marker stays LTR. P0-GATE-06 asserts this on
// the full gate fixture (minutes); this file rebuilds the same document in
// seconds and pinpoints the direction layer (blueprint nodes, engine
// chunks, artifact runs) via [diag] prints.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/semantic/inline_nodes.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

import 'ooxml_probe.dart';
import 'p0_gate_fixture.dart';

void main() {
  testWidgets('docx run direction: Arabic rtl, English ltr, one RTL paragraph',
      (tester) async {
    await FlutterTextMetrics.ensureFontsLoaded();
    debugPrint('[diag] binding=${WidgetsBinding.instance.runtimeType}');

    // 1. Blueprint node directions feeding the DOCX run writer.
    final document = P0GateFixture.rtl();
    debugPrint('[diag] fixture layout isLtr=${document.layout.isLtr} '
        'subject=${document.header.subject}');
    final title = ExamBlueprint.from(document).questions.first.title;
    debugPrint('[diag] numberNode=${title.numberNode.runtimeType} '
        'dir=${title.numberNode?.direction.name} text="${title.number}"');
    debugPrint('[diag] separatorNode dir='
        '${title.separatorNode?.direction.name}');
    final statement = title.statementContent;
    debugPrint('[diag] statement nodes=${statement?.nodes.length}');
    for (final node in statement?.nodes ?? const <InlineNode>[]) {
      debugPrint('[diag] statement node=${node.runtimeType} '
          'dir=${node.direction.name} text="${node.legacyText}"');
    }
    final marks = title.marksNode;
    debugPrint('[diag] marksNode=${marks?.runtimeType} text="${title.marks}"');
    if (marks != null) {
      for (final child in <InlineNode>[
        marks.opening,
        marks.number,
        marks.numberUnitGap,
        marks.unit,
        marks.closing,
      ]) {
        debugPrint('[diag] marks child=${child.runtimeType} '
            'dir=${child.direction.name} text="${child.legacyText}"');
      }
    }

    // 2. Engine chunking for the exact run texts (prints only: the engine
    // is an implementation detail, the artifact below is the contract).
    const samples = <String>[
      'س١',
      'اقرأ النص ثم أجب: ',
      '﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾',
      ' STA1',
      '٢٠',
      'درجة',
    ];
    for (final sample in samples) {
      for (final fallback in DocumentDirection.values.where(
          (direction) =>
              direction == DocumentDirection.rtl ||
              direction == DocumentDirection.ltr)) {
        final chunks = FlutterTextMetrics.resolveDirectionalRuns(
          sample,
          fallbackDirection: fallback,
        );
        debugPrint('[diag] engine fallback=${fallback.name} "$sample" -> '
            '${chunks.map((chunk) => '[${chunk.direction.name}] ${chunk.text}').join(' | ')}');
      }
    }

    // 3. Artifact runs: the contract.
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final probe = OoxmlProbe.decode(bytes);
    final titleParagraph = probe.paragraphs
        .firstWhere((paragraph) => paragraph.text.contains('STA1'));
    debugPrint('[diag] title hasBidi=${titleParagraph.props.hasBidi} '
        'runs=${titleParagraph.runs.length}');
    for (final run in titleParagraph.runs) {
      debugPrint('[diag] run rtl=${run.rtl} text="${run.text}"');
    }
    expect(titleParagraph.props.hasBidi, isTrue,
        reason: 'فقرة عربية بلا `w:bidi`: سيوجَّه السطر توجيهًا لاتينيًا.');
    final arabicRuns = titleParagraph.runs
        .where((run) => RegExp('[\\u0600-\\u06FF]').hasMatch(run.text))
        .toList();
    final englishRuns = titleParagraph.runs
        .where((run) => run.text.contains('STA1'))
        .toList();
    expect(arabicRuns, isNotEmpty);
    expect(arabicRuns.every((run) => run.rtl), isTrue,
        reason: 'Arabic run in RTL paragraph lacks `w:rtl`: '
            '${arabicRuns.map((run) => run.text).toList()}');
    expect(englishRuns, isNotEmpty);
    expect(englishRuns.every((run) => !run.rtl), isTrue,
        reason: 'Embedded English run in RTL paragraph incorrectly carries '
            '`w:rtl`: ${englishRuns.map((run) => run.text).toList()}');
  });
}
