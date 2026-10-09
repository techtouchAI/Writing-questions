// [C6-DIAG-2] TEMPORARY contract lifecycle probe. Not for merge; removed in cleanup.
// Question: does the production raster path (MathSnapshotHost via MaterialApp.builder +
// PdfMathRasters.rasterize) complete under a pump-only driver, and does a one-event-turn
// yield per pump (the e2a1483 idiom) change the output? Two drivers, same inputs.
// The gate fixture is not changed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/pdf_engine/pdf_math_rasters.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

const String _outDir = 'build/visual_parity/c6diag';

/// Formulas taken from the gate fixture (raw LaTeX as the layout passes them).
const List<String> _formulas = <String>[
  r'\frac{a}{b}',
  r'x^2+2x+1=0',
  r'\sqrt{x^2}=|x|',
  r'a_n = n^{\frac{1}{2}}',
  r'\begin{matrix} 1 & 2 \\ 3 & 4 \end{matrix}',
  r'x^2 - 4 = 0',
];

Future<Map<String, Object?>> _drive(
  WidgetTester tester, {
  required bool yieldEachPump,
  required bool withHost,
}) async {
  // withHost=false mirrors the gate fixture's MaterialApp (no MathSnapshotHost).
  await tester.pumpWidget(
    MaterialApp(
      builder: withHost ? (_, child) => MathSnapshotHost(child: child) : null,
      home: const SizedBox.shrink(),
    ),
  );
  await tester.pump();

  final futures = <Future<MathRaster?>>[
    for (final latex in _formulas) PdfMathRasters.rasterize(latex, 10.5),
  ];
  List<MathRaster?>? got;
  unawaited(
    Future.wait<MathRaster?>(futures).then((results) {
      got = results;
    }),
  );

  var pumps = 0;
  while (got == null && pumps < 400) {
    await tester.pump(const Duration(milliseconds: 50));
    if (yieldEachPump) {
      await tester.runAsync(() async {
        await Future<void>(() {});
      });
    }
    pumps++;
  }

  final sizes = <String>[];
  final hashes = <int>[];
  var rasters = 0;
  for (final raster in got ?? const <MathRaster?>[]) {
    if (raster == null) {
      sizes.add('null');
      hashes.add(-1);
      continue;
    }
    rasters++;
    sizes.add(
      '${raster.widthPt.toStringAsFixed(2)}x${raster.heightPt.toStringAsFixed(2)}'
      '/${raster.pngBytes.length}B',
    );
    var hash = 0;
    for (final byte in raster.pngBytes) {
      hash = (hash * 31 + byte) & 0x7fffffff;
    }
    hashes.add(hash);
  }

  return <String, Object?>{
    'mode': '${withHost ? 'host' : 'nohost'} ${yieldEachPump ? 'pump+yield' : 'pump-only'}',
    'done': got != null,
    'pumps': pumps,
    'formulas': _formulas.length,
    'rasters': rasters,
    'sizes': sizes,
    'hashes': hashes,
    'lastFailure': MathSnapshotRenderer.debugLastFailure,
  };
}

void main() {
  testWidgets('[C6-DIAG-2] math lifecycle pump-only', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final result = await _drive(tester, yieldEachPump: false, withHost: true);
    File('$_outDir/contract_pump_only.json')
        .writeAsStringSync(jsonEncode(result));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('[C6-DIAG-2] math lifecycle pump+yield', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final result = await _drive(tester, yieldEachPump: true, withHost: true);
    File('$_outDir/contract_pump_yield.json')
        .writeAsStringSync(jsonEncode(result));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('[C6-DIAG-2] math lifecycle no host (gate contract)', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final result = await _drive(tester, yieldEachPump: true, withHost: false);
    File('$_outDir/contract_nohost.json').writeAsStringSync(jsonEncode(result));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
