// Same measurement contract as the original C6 probe. Accept the actual
// rendered LayoutDocument; never resolve/paginate another document here.
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';

Map<String, Object?> c6PreviewPositions(LayoutDocument layout, {required String sourceKind}) {
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

  return <String, Object?>{
    'schema': 'c6-preview-positions-v1',
    'scalePxPerPt': LayoutUnits.ptToPx(1),
    'provenance': <String, Object?>{'kind': sourceKind},
    'pages': pages,
  };
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
    // The geometry gate needs to know which runs carry a rule; the rule's
    // position is measured by tool/check_underline_parity.py, its presence by
    // tool/c6_geometry_gate.py.
    'underline': style.underline,
    'heightPt': run.height,
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
