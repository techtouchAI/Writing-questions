// The Preview slants an italic run even though no italic face is bundled: the
// engine synthesises the oblique. The printed page must reproduce that slant
// (`package:pdf` never reads `TextStyle.fontStyle`), which is what
// [CanonicalText.syntheticObliqueShear] does. A constant that only *claims* to
// match the Preview proves nothing, so this probe measures the slant back from
// Preview pixels: one column of vertical stems, upright and italic, rasterised
// through the same widget-test capture path the visual-parity fixture uses.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';

import 'visual_parity_fixture_test.dart' show loadAppFonts;

/// One rasterised stem column and the ink this probe reads from it.
class _Raster {
  _Raster(this.pixels, this.width, this.height);

  final List<int> pixels;
  final int width;
  final int height;

  /// Ink amount at one pixel (white = 0, black = 255, red channel: the probe
  /// renders black text on white, so the channels carry the same value).
  int ink(int x, int y) => 255 - pixels[(y * width + x) * 4];
}

/// Least-squares slope of the per-row ink centroid, in pixels of x per pixel
/// of y. Screen rows run downwards, so a run whose ascenders lean towards the
/// end of the line has a negative slope of magnitude = the shear factor.
double _centroidSlope(_Raster raster) {
  final rows = <double>[];
  final centroids = <double>[];
  for (var y = 0; y < raster.height; y++) {
    var weight = 0.0;
    var moment = 0.0;
    for (var x = 0; x < raster.width; x++) {
      final ink = raster.ink(x, y);
      weight += ink;
      moment += ink * x;
    }
    if (weight < 40) {
      continue;
    }
    rows.add(y.toDouble());
    centroids.add(moment / weight);
  }
  expect(rows.length, greaterThan(20),
      reason: 'the stem column must cover enough rows to fit a slope');
  final meanRow = rows.reduce((a, b) => a + b) / rows.length;
  final meanCentroid = centroids.reduce((a, b) => a + b) / centroids.length;
  var covariance = 0.0;
  var variance = 0.0;
  for (var index = 0; index < rows.length; index++) {
    covariance += (rows[index] - meanRow) * (centroids[index] - meanCentroid);
    variance += (rows[index] - meanRow) * (rows[index] - meanRow);
  }
  expect(variance, greaterThan(0));
  return covariance / variance;
}

Future<_Raster> _rasterise(WidgetTester tester, FontStyle fontStyle) async {
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
              // Vertical stems only: no serif, foot or dot moves the per-row
              // centroid, so the fit sees the slant alone.
              'llllllll',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: ExamFont.arabicFamily,
                fontSize: 120,
                fontStyle: fontStyle,
                color: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // `toImage` requires a painted boundary; pump until the frame is clean,
  // exactly as the visual-parity fixture does before it captures a page.
  for (var attempt = 0; attempt < 4 && boundary.debugNeedsPaint; attempt++) {
    await tester.pump();
  }
  expect(boundary.debugNeedsPaint, isFalse,
      reason: 'the probe widget must be painted before it can be captured');
  final raster = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = data!.buffer.asUint8List().toList(growable: false);
    final result = _Raster(pixels, image.width, image.height);
    image.dispose();
    return result;
  });
  return raster!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Preview slants italic runs by the emitted oblique factor',
      (tester) async {
    await loadAppFonts();

    final upright = _centroidSlope(await _rasterise(tester, FontStyle.normal));
    final italic = _centroidSlope(await _rasterise(tester, FontStyle.italic));

    // Control: upright stems are vertical, so their slope is zero within ink
    // rasterisation noise. Without this the italic number below could be an
    // artefact of the fit rather than of the engine.
    expect(upright.abs(), lessThan(0.02),
        reason: 'upright stems must not slant (measured $upright)');
    final measured = -italic;
    expect(measured, inInclusiveRange(0.12, 0.40),
        reason: 'an italic run must actually be slanted by the engine '
            '(measured $measured); a value near zero would mean the upright '
            'control is the only thing this probe measures');
    // The factor the PDF emits is the factor the Preview renders.
    expect(measured,
        closeTo(CanonicalText.syntheticObliqueShear, 0.02),
        reason: 'the emitted shear ${CanonicalText.syntheticObliqueShear} must '
            'be the slant the Preview actually renders ($measured)');
  });
}
