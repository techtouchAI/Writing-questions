// [C6-POS] TEMPORARY Preview text-position probe (non-gating). Not for merge.
//
// Question: where does the Preview paint each word and each line baseline, in
// the same layout points that the vector PDF uses? This file only records
// measurements. It changes no production file and asserts nothing about the
// gate. The PDF side is read by tool/diag_c6_text_positions.py from the gate's
// own vector.pdf, and the two are compared there.
//
// The Preview side mirrors CanonicalLayoutPreviewPage._paintRun and
// _paintText (lib/layout/canonical/canonical_layout_preview.dart): the same
// skip rule, the same TextStyle fields, the same TextPainter configuration, and
// the same paint offset (line.baseline - baselineOffset). The layout is
// resolved exactly as ExamPreviewScreen does, with controller.document and
// controller.documentIr.
//
// Output: build/visual_parity/c6diag/text_positions/preview_positions.json
// Runs only in the c6-diagnostics CI job, with continue-on-error.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

import 'visual_parity_fixture_test.dart' as fixture;

const String _outDir = 'build/visual_parity/c6diag/text_positions';
const String _outFile = '$_outDir/preview_positions.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-POS] Preview text positions (non-gating)',
    (tester) async {
      await tester.runAsync(() async {
        await fixture.loadAppFonts();
        final controller = ExamWizardController(
          document: fixture.fixtureDocument(),
        );
        final layout = await CanonicalLayoutService.resolve(
          document: controller.document,
          sourceIr: controller.documentIr,
        );
        controller.dispose();

        final pages = <Map<String, Object?>>[];
        for (final page in layout.pages) {
          final lines = <Map<String, Object?>>[];
          for (final block in page.blocks) {
            for (final line in block.allLines) {
              lines.add(_lineRecord(line, 'block'));
            }
          }
          for (final float in page.floatingElements) {
            // Deferred floats are not painted by the Preview.
            if (float.deferredReason != null) continue;
            for (final line in float.labelLines) {
              lines.add(_lineRecord(line, 'float'));
            }
          }
          pages.add(<String, Object?>{
            'page': page.index + 1,
            'widthPt': page.pageSize.width,
            'heightPt': page.pageSize.height,
            'lines': lines,
          });
        }

        final out = <String, Object?>{
          'schema': 'c6-preview-positions-v1',
          'scalePxPerPt': LayoutUnits.ptToPx(1),
          'pages': pages,
        };
        Directory(_outDir).createSync(recursive: true);
        File(_outFile).writeAsStringSync(jsonEncode(out));
        expect(pages, isNotEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Map<String, Object?> _lineRecord(LayoutLine line, String source) {
  final runs = <Map<String, Object?>>[];
  for (final run in line.runs) {
    // Same skip rule as CanonicalLayoutPreviewPage._paintRun.
    if (run.advance <= 0 || (run.text.isEmpty && !run.isMath)) continue;
    runs.add(_runRecord(line, run));
  }
  return <String, Object?>{
    'source': source,
    'baselinePt': line.baseline,
    'layoutAscentPt': line.ascent,
    'layoutDescentPt': line.descent,
    'layoutLeadingPt': line.leading,
    'runs': runs,
  };
}

Map<String, Object?> _runRecord(LayoutLine line, LayoutRun run) {
  final style = run.style;
  final record = <String, Object?>{
    'text': run.text,
    'xPt': run.x,
    'widthPt': run.width,
    'advancePt': run.advance,
    'layoutBaselineOffsetPt': run.baselineOffset,
    'fontFamily': style.font.family,
    'fontSizePt': style.fontSizePt,
    'bold': style.bold,
    'italic': style.italic,
    'rtl': run.direction == DocumentDirection.rtl,
    'isMath': run.isMath,
    'measured': false,
  };
  // Math is painted as an image when available, so it is not a text position.
  if (run.isMath) return record;

  final painter = TextPainter(
    text: TextSpan(
      text: run.text,
      style: TextStyle(
        fontFamily: style.font.family,
        fontSize: style.fontSizePt,
        fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: style.letterSpacingPt,
        height: style.lineHeightFactor,
        decoration: style.underline ? TextDecoration.underline : null,
      ),
    ),
    textDirection: run.direction == DocumentDirection.rtl
        ? TextDirection.rtl
        : TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  try {
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return record;
    final first = metrics.first;
    // Same paint offset as CanonicalLayoutPreviewPage._paintText.
    final paintTop = line.baseline - first.baseline;
    record['measured'] = true;
    record['painterWidthPt'] = painter.width;
    record['innerBaselinePt'] = first.baseline;
    record['innerAscentPt'] = first.ascent;
    record['innerDescentPt'] = first.descent;
    record['innerHeightPt'] = first.height;
    record['paintTopPt'] = paintTop;
    record['previewBaselinePt'] = paintTop + first.baseline;
    record['previewWords'] = _previewWords(painter, run);
    record['layoutWords'] = <Map<String, Object?>>[
      for (final word in run.words)
        <String, Object?>{
          'text': word.text,
          'xPt': word.x,
          'advancePt': word.advance,
          'textAdvancePt': word.textAdvance,
        },
    ];
    return record;
  } finally {
    painter.dispose();
  }
}

/// Preview word boxes in layout points. Each word is the k-th match of
/// canonicalWordPattern in run.text, which is the same tokenisation the PDF
/// writer uses for run.words. countsMatchLayout reports whether the token
/// count agrees with run.words.
List<Map<String, Object?>> _previewWords(TextPainter painter, LayoutRun run) {
  final matches = canonicalWordPattern.allMatches(run.text).toList();
  final countsMatchLayout = matches.length == run.words.length;
  final out = <Map<String, Object?>>[];
  for (var k = 0; k < matches.length; k++) {
    final match = matches[k];
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
      boxHeightStyle: ui.BoxHeightStyle.tight,
      boxWidthStyle: ui.BoxWidthStyle.tight,
    );
    if (boxes.isEmpty) continue;
    var left = boxes.first.left;
    var right = boxes.first.right;
    for (final box in boxes) {
      if (box.left < left) left = box.left;
      if (box.right > right) right = box.right;
    }
    out.add(<String, Object?>{
      'index': k,
      'text': match.group(0),
      'leftPt': run.x + left,
      'rightPt': run.x + right,
      'boxCount': boxes.length,
      'countsMatchLayout': countsMatchLayout,
    });
  }
  return out;
}
