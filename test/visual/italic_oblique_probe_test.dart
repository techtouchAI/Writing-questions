// The Preview slants an italic run even though no italic face is bundled: the
// engine synthesises the oblique. The printed page must reproduce that slant
// (`package:pdf` never reads `TextStyle.fontStyle`), which is what
// [CanonicalText.syntheticObliqueShear] does. A constant that only *claims* to
// match the Preview proves nothing, so this probe measures the slant back from
// Preview pixels: a column of vertical stems, upright and italic, rasterised
// through the same widget-test capture path the visual-parity fixture uses.
//
// The measurement is published as a run annotation before it is asserted: the
// number is the evidence, and a bare "expected closeTo(...)" would hide it
// from anyone who cannot open the run log.
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

  /// Ink at one pixel (white = 0, black = 255; the probe draws black on white,
  /// so every channel carries the same value).
  int ink(int x, int y) => 255 - pixels[(y * width + x) * 4];

  /// Bounding box of all ink as `(left, top, right, bottom)`, or null.
  (int, int, int, int)? get inkBounds {
    int? left, top, right, bottom;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (ink(x, y) <= 16) continue;
        left = (left == null || x < left) ? x : left;
        right = (right == null || x > right) ? x : right;
        top = (top == null || y < top) ? y : top;
        bottom = (bottom == null || y > bottom) ? y : bottom;
      }
    }
    if (left == null) return null;
    return (left, top!, right!, bottom!);
  }
}

/// Publishes one line as a workflow notice. Artifact and log hosts are not
/// reachable from every environment, while run annotations are; an assertion
/// alone would leave the measured number unreadable there.
void publish(String title, List<String> lines) {
  final text = lines
      .map((line) => line
          .replaceAll('%', '%25')
          .replaceAll('\r', '%0D')
          .replaceAll('\n', '%0A'))
      .join(' | ');
  // ignore: avoid_print
  print('::notice title=$title::$text');
}

/// Least-squares slope of the per-row ink centroid, in pixels of x per pixel
/// of y. Screen rows run downwards, so a sheared run has a negative slope; the
/// applied shear is the *difference* between the italic and upright fits (see
/// the test), never the raw italic reading.
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

    final uprightRaster = await _rasterise(tester, FontStyle.normal);
    final italicRaster = await _rasterise(tester, FontStyle.italic);
    final upright = _centroidSlope(uprightRaster);
    final italic = _centroidSlope(italicRaster);

    // The shear is a linear map, so it adds a constant to the slope of every
    // ink feature of the glyphs. Measured directly, the italic slope therefore
    // mixes the applied shear with the glyph's own baseline drift -- here the
    // ascender strokes of this face pull the upright centroid as well
    // (measured 0.0330) -- and reading that mix as "the oblique factor" is how
    // the first version of this probe mis-called a correct 0.25 emission. The
    // upright run is exactly the control that measures the drift, so the shear
    // is the *difference* of the two fits.
    final shear = upright - italic;

    // Publish before asserting: this is the measurement itself.
    publish('C6 italic probe measured', <String>[
      'upright slope=${upright.toStringAsFixed(4)}',
      'italic slope=${italic.toStringAsFixed(4)}',
      'shear (upright-italic)=${shear.toStringAsFixed(4)}',
      'emitted=${CanonicalText.syntheticObliqueShear}',
      'upright ink=${uprightRaster.inkBounds}',
      'italic ink=${italicRaster.inkBounds}',
      'raster=${italicRaster.width}x${italicRaster.height}',
    ]);

    // Control: the upright run must be *nearly* straight -- if the fit were
    // noise, the difference below would be noise with a larger amplitude.
    expect(upright.abs(), lessThan(0.08),
        reason: 'upright stems must stay close to vertical (measured '
            '$upright)');
    expect(shear, inInclusiveRange(0.05, 0.45),
        reason: 'an italic run must actually be slanted by the engine '
            '(measured shear $shear); a value near zero would mean this probe '
            'measures nothing but the upright control');
    // The factor the PDF emits is the factor the Preview renders.
    expect(shear,
        closeTo(CanonicalText.syntheticObliqueShear, 0.02),
        reason: 'the emitted shear ${CanonicalText.syntheticObliqueShear} must '
            'be the slant the Preview actually renders (measured $shear)');
  });
}
