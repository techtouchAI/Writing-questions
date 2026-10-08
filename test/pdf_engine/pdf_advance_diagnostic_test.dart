// TEMPORARY diagnostic (Batch D1, remove after evidence is consumed):
// compact shaped-vs-/W-vs-probe evidence for the p0q1/title Quran pair.
// Fails deliberately so the evidence surfaces in the failure annotation
// (passing-test PRINTS are unreadable: CI log downloads EOF).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../export_gate/p0_gate_fixture.dart';
import '../export_gate/pdf_structure_probe.dart';
import 'fake_math_host.dart';

String _cps(String value) =>
    value.runes.map((rune) => rune.toRadixString(16)).join(',');

String _stripMarks(String value) => String.fromCharCodes(
      value.runes.where((rune) =>
          !(rune >= 0x064b && rune <= 0x065f) && rune != 0x0670),
    );

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
    late String ilmaRun;
    late String zadniRun;
    late String ilmaText;
    late String zadniText;
    late double ilmaX;
    late double zadniX;
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
      String describe(Object? run) {
        final value = run as dynamic;
        return '"${value.text}"@${value.x.toStringAsFixed(2)}+'
            '${value.width.toStringAsFixed(2)} fs=${value.style.fontSizePt} '
            'b=${value.style.bold} f=${value.style.font.name}';
      }

      final quran = canonicalLayout.allLines
          .expand((line) => line.runs)
          .where((run) => run.isQuran)
          .toList(growable: false);
      final ilma = quran.firstWhere(
          (run) => _stripMarks(run.text as String).contains('علما'));
      final zadni = quran.firstWhere(
          (run) => _stripMarks(run.text as String).contains('زدني'));
      ilmaRun = describe(ilma);
      zadniRun = describe(zadni);
      ilmaText = ilma.text as String;
      zadniText = zadni.text as String;
      ilmaX = (ilma.x as num).toDouble();
      zadniX = (zadni.x as num).toDouble();
    });

    final bytes = Uint8List.fromList(vectorPdf);
    final report = PdfStructureReport.fromBytes(bytes);
    final titleWords = <String>[];
    for (final line in report.pages.first.linesWithMarker('STA1')) {
      for (final word in line.words) {
        if ((word.x - ilmaX).abs() < 0.5 || (word.x - zadniX).abs() < 0.5) {
          titleWords.add('"${word.text}"@${word.x.toStringAsFixed(2)}+'
              '${word.advanceWidth.toStringAsFixed(2)} fs=${word.fontSize} '
              '${word.fontName} ${word.baseFont}');
        }
      }
    }

    final raw = latin1.decode(bytes, allowInvalid: true);
    final unicodeToCid = <int, int>{};
    for (final match in RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>')
        .allMatches(raw)) {
      unicodeToCid[int.parse(match.group(2)!, radix: 16)] =
          int.parse(match.group(1)!, radix: 16);
    }
    final widthsBySerial = <int, List<int>>{};
    for (final match
        in RegExp(r'/W\s*\[\s*\d+\s+(\d+)\s+0\s+R').allMatches(raw)) {
      final serial = int.parse(match.group(1)!);
      final obj = RegExp('$serial\\s+0\\s+obj\\b([\\s\\S]*?)endobj')
          .firstMatch(raw)
          ?.group(1);
      if (obj != null) {
        widthsBySerial[serial] = RegExp(r'-?\d+')
            .allMatches(obj)
            .map((number) => int.parse(number.group(0)!))
            .toList(growable: false);
      }
    }
    String wordWidths(String label, String logical) {
      final shaped = logicalToVisual(logical);
      final entries = <String>[];
      for (final rune in shaped.runes) {
        final cid = unicodeToCid[rune];
        var found = '';
        for (final serial in widthsBySerial.keys) {
          final widths = widthsBySerial[serial]!;
          if (cid != null && cid < widths.length) {
            found = '$found$serial:${widths[cid]} ';
          }
        }
        entries.add('${rune.toRadixString(16)}=cid$cid[$found]');
      }
      return '$label shaped=${_cps(shaped)} ${entries.join(' ')}';
    }

    final evidence = <String>[
      'canon ilma $ilmaRun',
      'canon zadni $zadniRun',
      'probe ${titleWords.join(' | ')}',
      wordWidths('ilma', ilmaText),
      wordWidths('zadni', zadniText),
      'widthTables ${widthsBySerial.keys.join(',')}',
    ].join('\n');
    expect(evidence.isEmpty, isTrue, reason: evidence);
  });
}
