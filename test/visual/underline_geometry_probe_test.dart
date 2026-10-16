// The Preview draws an underline through the engine's own font metrics; the
// PDF draws one through `CanonicalText`'s replication of the replaced
// `pw.Text` path. The ink maps say the two rules do not land in the same place
// (the heaviest band of an underlined line sits 4 px lower in the PDF), but a
// band in a coarse map cannot say what the correct offset is. This probe
// measures the Preview's own rule -- its distance below the baseline and its
// thickness, in pixels and in points -- and publishes it, so the printed
// placement can be brought to the screen's instead of to a guess.
//
// It measures, it does not yet assert parity: the PDF side needs the number
// this probe publishes, and a test that guessed it would be worthless.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_font.dart';

import 'italic_oblique_probe_test.dart' show publish;
import 'visual_parity_fixture_test.dart' show loadAppFonts;

/// One rasterised line and the ink this probe reads from it.
class _Raster {
  _Raster(this.pixels, this.width, this.height);

  final List<int> pixels;
  final int width;
  final int height;

  int ink(int x, int y) => 255 - pixels[(y * width + x) * 4];
}

/// Per-row ink: `(top, bottom, fill)` where fill is the fraction of the row's
/// own span that is inked, or null when the row has no ink.
({int top, int bottom, int count, double fill})? _row(_Raster raster, int y) {
  int? first;
  int? last;
  var count = 0;
  for (var x = 0; x < raster.width; x++) {
    if (raster.ink(x, y) <= 16) continue;
    first ??= x;
    last = x;
    count++;
  }
  if (first == null) return null;
  return (
    top: first,
    bottom: last!,
    count: count,
    fill: count / (last - first + 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measures the Preview underline offset and thickness',
      (tester) async {
    await loadAppFonts();
    const fontPx = 120.0;
    const text = 'nnnn';
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                text,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontFamily: ExamFont.arabicFamily,
                  fontSize: fontPx,
                  color: Color(0xFF000000),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    for (var attempt = 0; attempt < 4 && boundary.debugNeedsPaint; attempt++) {
      await tester.pump();
    }
    final raster = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = _Raster(
        data!.buffer.asUint8List().toList(growable: false),
        image.width,
        image.height,
      );
      image.dispose();
      return result;
    });

    // A rule is a row that is inked almost continuously across its own span,
    // far more densely than the gaps inside a letter. 'nnnn' is used because
    // its stems end flat on the baseline, so the last glyph row above the rule
    // is the baseline row itself.
    final rows = <int, ({int top, int bottom, int count, double fill})>{};
    for (var y = 0; y < raster!.height; y++) {
      final row = _row(raster, y);
      if (row != null) rows[y] = row;
    }
    // Publish the anatomy before any assertion: a probe that fails silently
    // says nothing about the thing it was built to measure.
    final anatomy = <String>[
      'raster ${raster.width}x${raster.height}',
      'ink rows ${rows.isEmpty ? 0 : '${rows.keys.first}..${rows.keys.last}'}',
    ];
    for (final entry in rows.entries.where((e) => e.value.count >= 20).take(24)) {
      anatomy.add('  y=${entry.key} count=${entry.value.count} '
          'span=${entry.value.top}..${entry.value.bottom} '
          'fill=${entry.value.fill.toStringAsFixed(3)}');
    }
    publish('C6 underline probe anatomy', anatomy);
    expect(rows, isNotEmpty, reason: 'the probe drew nothing');
    final ruleRows = <int>[
      for (final entry in rows.entries)
        if (entry.value.fill > 0.95 && entry.value.count > 40) entry.key,
    ];
    expect(ruleRows, isNotEmpty,
        reason: 'no continuous horizontal rule found below the letters; the '
            'probe cannot measure an underline it did not draw');
    final ruleTop = ruleRows.first;
    final ruleBottom = ruleRows.last;
    final glyphRows = rows.keys.where((y) => y < ruleTop).toList();
    expect(glyphRows, isNotEmpty, reason: 'no glyph ink above the rule');
    final baseline = glyphRows.last;

    const pxToPt = 72.0 / 96.0;
    publish('C6 underline probe measured', <String>[
      'font ${fontPx}px',
      'baseline row y=$baseline',
      'rule rows y=$ruleTop..$ruleBottom',
      'offset ${(ruleTop - baseline).toStringAsFixed(1)}px '
          '${((ruleTop - baseline) * pxToPt).toStringAsFixed(2)}pt',
      'thickness ${(ruleBottom - ruleTop + 1).toStringAsFixed(1)}px '
          '${((ruleBottom - ruleTop + 1) * pxToPt).toStringAsFixed(2)}pt',
      'offset/em ${((ruleTop - baseline) / fontPx).toStringAsFixed(4)} '
          'thickness/em ${((ruleBottom - ruleTop + 1) / fontPx).toStringAsFixed(4)}',
      'rule fill ${rows[ruleTop]!.fill.toStringAsFixed(3)}',
    ]);

    // Sanity only: a rule below the baseline, thin relative to the em.
    final offset = ruleTop - baseline;
    expect(offset, greaterThan(0),
        reason: 'the rule must sit below the baseline row ($baseline)');
    expect(offset / fontPx, lessThan(0.25),
        reason: 'the rule cannot be a quarter of the em below the baseline');
  });
}
