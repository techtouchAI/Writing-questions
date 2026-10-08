// TEMPORARY diagnostic (Batch D1, remove after evidence is consumed):
// prints shaped-vs-/W-vs-probe advances for the p0q1/title Quran pair so
// the C2-gap root cause can be read off CI PRINTS. Always passes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../export_gate/p0_gate_fixture.dart';
import '../export_gate/pdf_structure_probe.dart';
import 'fake_math_host.dart';

String _cps(String value) =>
    value.runes.map((rune) => rune.toRadixString(16)).join(',');

void main() {
  testWidgets('DIAG advance: shaped vs /W vs probe for title pair',
      (tester) async {
    Future<void> load(String family, List<String> assets) async {
      final loader = FontLoader(family);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }

    await load(ExamFont.arabicFamily, <String>[
      ExamFonts.regularAsset,
      ExamFonts.boldAsset,
    ]);
    await load('Amiri', <String>[ExamFont.quranicAsset]);
    await load('Tajawal', <String>['assets/fonts/Tajawal-Regular.ttf']);

    final mathHost = FakeMathHost()..attach();
    addTearDown(mathHost.detach);

    final rtlDocument = P0GateFixture.rtl();
    late List<int> vectorPdf;
    late String canonicalTitle;
    await tester.runAsync(() async {
      final pdfFonts = await ExamFonts.load(
        loadQuranic: PaginatedPdfExamEngine.needsQuranicFont(rtlDocument),
      );
      final pdfEngine = PaginatedPdfExamEngine();
      final canonicalLayout = await pdfEngine.resolveLayoutDocument(
        document: rtlDocument,
        fonts: pdfFonts,
      );
      vectorPdf = await pdfEngine.generate(
        document: rtlDocument,
        layoutDocument: canonicalLayout,
        fonts: pdfFonts,
      );
      final titleLines = canonicalLayout.allLines
          .where((line) => line.semanticNodeId == 'p0q1/title')
          .toList(growable: false);
      final buffer = StringBuffer();
      for (final run in titleLines.first.runs) {
        buffer.write(
            '[${run.text}(${_cps(run.text)})@${run.x.toStringAsFixed(2)}+'
            '${run.width.toStringAsFixed(2)} fs=${run.style.fontSizePt} '
            'b=${run.style.bold} f=${run.style.font.name} '
            'dir=${run.direction.name}] ');
      }
      canonicalTitle = buffer.toString();
    });
    final evidence = StringBuffer('[diag] canonical: $canonicalTitle\n');

    final bytes = Uint8List.fromList(vectorPdf);
    final report = PdfStructureReport.fromBytes(bytes);
    final page = report.pages.first;
    final titleLines = page.linesWithMarker('STA1');
    for (final line in titleLines) {
      evidence.writeln('[diag] probed line: ${line.describe()}');
      for (final word in line.words) {
        evidence.writeln('[diag] probed "${word.text}"(${_cps(word.text)}) '
            '@${word.x.toStringAsFixed(2)}+'
            '${word.advanceWidth.toStringAsFixed(2)} fs=${word.fontSize} '
            '${word.fontName} ${word.baseFont}');
      }
    }

    final raw = latin1.decode(bytes, allowInvalid: true);
    final tcValues = <String>{
      for (final match in RegExp(r'(-?[\d.]+)\s+Tc').allMatches(raw))
        match.group(1)!,
    }.toList()
      ..sort();
    evidence.writeln('[diag] distinct Tc (${tcValues.length}): '
        '${tcValues.take(24).join(',')}');

    final wArrays = <String>[];
    for (final match
        in RegExp(r'/W\s*\[\s*\d+\s+(\d+)\s+0\s+R').allMatches(raw)) {
      final serial = int.parse(match.group(1)!);
      final obj = RegExp('$serial\\s+0\\s+obj\\b([\\s\\S]*?)endobj')
          .firstMatch(raw)
          ?.group(1);
      if (obj == null) {
        continue;
      }
      final numbers = RegExp(r'-?\d+')
          .allMatches(obj)
          .map((number) => number.group(0)!)
          .toList(growable: false);
      final base = RegExp(r'/BaseFont\s*/([^\s/>]+)')
          .firstMatch(raw.substring(0, match.start).split('endobj').last);
      wArrays.add('obj$serial[${numbers.length}]:'
          '${numbers.take(48).join(',')}${base == null ? '' : ' base=${base.group(1)}'}');
    }
    for (final entry in wArrays) {
      evidence.writeln('[diag] /W $entry');
    }

    // Deliberate failure: surfacing evidence through the failure
    // annotation because passing-test PRINTS are unreadable (log
    // downloads EOF). Remove this file after consuming the evidence.
    expect(evidence.isEmpty, isTrue, reason: evidence.toString());
  });
}
