// [C6-DIAG-3] TEMPORARY math equivalence probe. Not for merge; removed in cleanup.
// Question: does the host+yield driver (test contract `e2a1483`) produce the same
// math rasters as the production path? Varies only timing and lifecycle, and
// compares with the exact call the Preview makes (render -> toPngRaster, default
// density, run font size). Writes one line per condition to
// build/visual_parity/c6diag/math_equivalence.txt. Does not assert, and changes
// no production file.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/pdf_engine/pdf_math_rasters.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';

const String _outFile = 'build/visual_parity/c6diag/math_equivalence.txt';
const double _fontPt = 10.5;

/// Same formulas as the contract probe (taken from the gate fixture).
const List<String> _formulas = <String>[
  r'\frac{a}{b}',
  r'x^2+2x+1=0',
  r'\sqrt{x^2}=|x|',
  r'a_n = n^{\frac{1}{2}}',
  r'\begin{matrix} 1 & 2 \\ 3 & 4 \end{matrix}',
  r'x^2 - 4 = 0',
];

class _Result {
  _Result({
    required this.label,
    required this.done,
    required this.pumps,
    required this.availableStart,
    required this.availableEnd,
    required this.rasters,
    required this.sizes,
    required this.hashes,
    required this.wallMs,
  });

  final String label;
  final bool done;
  final int pumps;
  final bool availableStart;
  final bool availableEnd;
  final int rasters;
  final List<String> sizes;
  final List<int> hashes;
  final int wallMs;

  String get hashKey => hashes.join(',');

  String describe() {
    return '$label: done=$done pumps=$pumps available=$availableStart/$availableEnd '
        'rasters=$rasters/${_formulas.length} wallMs=$wallMs '
        'sizes=${sizes.join(' ')} hashes=${hashes.join(',')}';
  }
}

int _hash(List<int> bytes) {
  var hash = 0;
  for (final byte in bytes) {
    hash = (hash * 31 + byte) & 0x7fffffff;
  }
  return hash;
}

/// The Preview's exact call sequence: render, then toPngRaster, then dispose.
Future<MathRaster?> _viaPreviewPath(String latex) async {
  final snapshot = await MathSnapshotRenderer.render(latex, fontSizePt: _fontPt);
  if (snapshot == null) return null;
  try {
    return await snapshot.toPngRaster();
  } finally {
    snapshot.dispose();
  }
}

Future<_Result> _condition(
  WidgetTester tester, {
  required String label,
  required bool host,
  required bool previewPath,
  required int realDelayMs,
  required int extraPumps,
}) async {
  final clock = Stopwatch()..start();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      builder: host ? (_, child) => MathSnapshotHost(child: child) : null,
      home: const SizedBox.shrink(),
    ),
  );
  await tester.pump();
  final availableStart = MathSnapshotRenderer.isAvailable;

  List<MathRaster?>? got;
  final futures = <Future<MathRaster?>>[
    for (final latex in _formulas)
      previewPath ? _viaPreviewPath(latex) : PdfMathRasters.rasterize(latex, _fontPt),
  ];
  unawaited(
    Future.wait<MathRaster?>(futures).then((results) {
      got = results;
    }),
  );

  var pumps = 0;
  while (got == null && pumps < 400) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: realDelayMs)),
    );
    pumps++;
  }
  final done = got != null;
  for (var i = 0; i < extraPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  final availableEnd = MathSnapshotRenderer.isAvailable;

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
    hashes.add(_hash(raster.pngBytes));
  }
  clock.stop();
  return _Result(
    label: label,
    done: done,
    pumps: pumps,
    availableStart: availableStart,
    availableEnd: availableEnd,
    rasters: rasters,
    sizes: sizes,
    hashes: hashes,
    wallMs: clock.elapsedMilliseconds,
  );
}

void main() {
  testWidgets('[C6-DIAG-3] math equivalence across drivers', (tester) async {
    Directory('build/visual_parity/c6diag').createSync(recursive: true);
    final results = <_Result>[
      await _condition(
        tester,
        label: 'E1 pdf-path host yield0',
        host: true,
        previewPath: false,
        realDelayMs: 0,
        extraPumps: 0,
      ),
      await _condition(
        tester,
        label: 'E2 pdf-path host realdelay20ms',
        host: true,
        previewPath: false,
        realDelayMs: 20,
        extraPumps: 0,
      ),
      await _condition(
        tester,
        label: 'E3 pdf-path host yield0 +30 extra pumps',
        host: true,
        previewPath: false,
        realDelayMs: 0,
        extraPumps: 30,
      ),
      await _condition(
        tester,
        label: 'E4 preview-path host yield0',
        host: true,
        previewPath: true,
        realDelayMs: 0,
        extraPumps: 0,
      ),
      await _condition(
        tester,
        label: 'E5 gate-contract no host (preview falls back to text)',
        host: false,
        previewPath: false,
        realDelayMs: 0,
        extraPumps: 0,
      ),
    ];

    final e1 = results.first;
    final lines = <String>[for (final r in results) r.describe()];
    for (final r in results) {
      lines.add('${r.label}: same hashes as E1 = ${r.hashKey == e1.hashKey}');
    }
    File(_outFile).writeAsStringSync('${lines.join('\n')}\n');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
