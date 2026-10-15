// [C6-RASTER] TEMPORARY baseline sub-pixel probe v7 (non-gating). Not for merge.
//
// Hypothesis H4 (rounding / rendering): for a single text line, Flutter (the
// preview raster) and Poppler (pdftoppm of the vector PDF) place the ink at
// different whole-pixel positions because of how each rounds the baseline.
//
// Single factor: the baseline fraction B - floor(B), 0.0 .. 0.9 in steps of
// 0.1 (device px). Everything else is held fixed between the lines of one
// font: text 'H' (flat bottom at the baseline), size 11 pt, the production
// line-height factor on the preview side, the same page 794 x 1123 px at
// 96 dpi, and the same PDF content chain (PdfTextMetrics + CanonicalText).
//
// Layout (all on one page):
//   - 4 plain columns, one per production font (the preview paints at B).
//   - 4 control columns, the same fonts, whose preview paint baseline is first
//     snapped to floor(B) whole device px. This is a diagnostic arm only.
//   - Each (font, arm) has 10 fractions x 2 repeats. Repeat 0 sits at integer
//     baselines near 60 px, repeat 1 near 610 px, so the integer part differs
//     and the result can be checked for independence from it.
//
// Output (build/visual_parity/c6diag/baseline_raster/):
//   preview_raster.png  Flutter raster of the probe page (794 x 1123 px)
//   baseline_probe.pdf  the same lines as a vector PDF (A4)
//   probe.json          intended baselines, font, arm, repeat per line
// The measurement and the rasterization by poppler (pdftoppm -r 96) happen in
// tool/diag_c6_baseline_raster.py.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/layout/canonical/layout_configuration.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

const String _outDir = 'build/visual_parity/c6diag/baseline_raster';
const String _probeText = 'H';
const double _fontSizePt = 11;
const int _pageWidthPx = 794;
const int _pageHeightPx = 1123;

/// One column per production font family (names as in pubspec.yaml).
class _ProbeFont {
  const _ProbeFont(this.family, this.asset);
  final String family;
  final String asset;
}

const List<_ProbeFont> _fonts = <_ProbeFont>[
  _ProbeFont('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
  _ProbeFont('Amiri', 'assets/fonts/Amiri-Regular.ttf'),
  _ProbeFont('NotoNaskhArabic', 'assets/fonts/NotoNaskhArabic-Regular.ttf'),
  _ProbeFont('Rakkas', 'assets/fonts/Rakkas-Regular.ttf'),
];

/// Fractions 0.0 .. 0.9 in steps of 0.1 (exact decimals).
const List<double> _fractions = <double>[
  0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
];

/// Two repeats: integer base of repeat 0 and repeat 1 (device px).
const List<double> _repeatBasePx = <double>[60, 610];
const double _rowPitchPx = 50;

const int _columnCount = 8;
const int _snapColumnFrom = 4;
const String _snapSuffix = '+snap';
const double _columnPitchPx = 97;
const double _firstColumnPx = 20;

double _columnXPx(int column) => _firstColumnPx + column * _columnPitchPx;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-RASTER] baseline sub-pixel probe v7 H4 (non-gating)',
    (tester) async {
      await tester.runAsync(() async {
        final fontBytes = <String, ByteData>{};
        for (final font in _fonts) {
          final bytes = await rootBundle.load(font.asset);
          final loader = FontLoader(font.family)
            ..addFont(rootBundle.load(font.asset));
          await loader.load();
          fontBytes[font.family] = bytes;
        }

        Directory(_outDir).createSync(recursive: true);
        final height = const LayoutConfiguration().lineHeightFactor;

        // ---- Preview side (Flutter raster) ----
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(
          recorder,
          Rect.fromLTWH(0, 0, _pageWidthPx.toDouble(), _pageHeightPx.toDouble()),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, _pageWidthPx.toDouble(), _pageHeightPx.toDouble()),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.scale(LayoutUnits.ptToPx(1));

        final lines = <Map<String, Object?>>[];
        for (var c = 0; c < _columnCount; c++) {
          final fontIndex = c % _fonts.length;
          final snapped = c >= _snapColumnFrom;
          final font = _fonts[fontIndex];
          final xPx = _columnXPx(c);
          final xPt = LayoutUnits.pxToPt(xPx);
          for (var repeat = 0; repeat < _repeatBasePx.length; repeat++) {
            for (var k = 0; k < _fractions.length; k++) {
              final fraction = _fractions[k];
              final baselinePx = _repeatBasePx[repeat] + k * _rowPitchPx + fraction;
              final baselinePt = LayoutUnits.pxToPt(baselinePx);
              final painter = TextPainter(
                text: TextSpan(
                  text: _probeText,
                  style: TextStyle(
                    fontFamily: font.family,
                    fontSize: _fontSizePt,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF000000),
                    height: height,
                  ),
                ),
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
              )..layout(maxWidth: double.infinity);
              final innerBaselinePt = painter.computeLineMetrics().first.baseline;
              // Snapped (control) columns paint at floor(B) whole device px.
              final paintBaselinePt = snapped
                  ? LayoutUnits.pxToPt(baselinePx.floorToDouble())
                  : baselinePt;
              final paintTopPt = paintBaselinePt - innerBaselinePt;
              painter.paint(canvas, Offset(xPt, paintTopPt));
              painter.dispose();
              lines.add(<String, Object?>{
                'index': lines.length,
                'group': snapped ? '${font.family}$_snapSuffix' : font.family,
                'column': c,
                'fontIndex': fontIndex,
                'snapped': snapped,
                'repeat': repeat,
                'fractionIndex': k,
                'xPx': xPx,
                // Measurement window for this column only. The H ink spans
                // about x+1 .. x+11 px; the next column starts at x+97 px.
                'winX0': (xPx - 4).round(),
                'winX1': (xPx + 40).round(),
                'heightFactor': height,
                'fraction': fraction,
                'baselinePx': baselinePx,
                'baselinePt': baselinePt,
                'xPt': xPt,
                'previewInnerBaselinePt': innerBaselinePt,
                'previewPaintTopPt': paintTopPt,
                'paintBaselinePx': LayoutUnits.ptToPx(paintBaselinePt),
              });
            }
          }
        }

        final picture = recorder.endRecording();
        final image = await picture.toImage(_pageWidthPx, _pageHeightPx);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        expect(png, isNotNull, reason: 'preview raster must encode to PNG');
        File('$_outDir/preview_raster.png')
            .writeAsBytesSync(png!.buffer.asUint8List());

        // ---- PDF side (production chain: PdfTextMetrics + CanonicalText) ----
        final pdfFonts = <String, pw.Font>{
          for (final font in _fonts)
            font.family: pw.Font.ttf(fontBytes[font.family]!),
        };
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              final children = <pw.Widget>[];
              for (final line in lines) {
                final font = _fonts[line['fontIndex']! as int];
                final pdfFont = pdfFonts[font.family]!;
                final pdfFace = pdfFont.getFont(context);
                final baselinePt = line['baselinePt']! as double;
                final offsetPt = PdfTextMetrics.baselineOffsetFromTop(
                  font: pdfFace,
                  fontSizePt: _fontSizePt,
                  text: _probeText,
                );
                final top = baselinePt - offsetPt;
                final advancePt =
                    pdfFace.stringMetrics(_probeText).advanceWidth * _fontSizePt;
                line['pdfTextTopOffsetPt'] = offsetPt;
                line['pdfWidgetTopPt'] = top;
                children.add(
                  pw.Positioned(
                    left: line['xPt']! as double,
                    top: top,
                    child: CanonicalText(
                      text: _probeText,
                      font: pdfFont,
                      fontSizePt: _fontSizePt,
                      color: PdfColors.black,
                      canonicalAdvancePt: advancePt,
                      rtl: false,
                      underline: false,
                    ),
                  ),
                );
              }
              return pw.Stack(
                fit: pw.StackFit.expand,
                overflow: pw.Overflow.visible,
                children: children,
              );
            },
          ),
        );
        final pdfBytes = await doc.save();
        File('$_outDir/baseline_probe.pdf').writeAsBytesSync(pdfBytes);

        final out = <String, Object?>{
          'schema': 'c6-baseline-raster-v7',
          'synthetic': false,
          'hypothesis': 'H4',
          'text': _probeText,
          'fontSizePt': _fontSizePt,
          'pageWidthPx': _pageWidthPx,
          'pageHeightPx': _pageHeightPx,
          'scalePxPerPt': LayoutUnits.ptToPx(1),
          'productionLineHeightFactor': height,
          'fonts': [for (final f in _fonts) f.family],
          'fractions': _fractions,
          'repeatBasePx': _repeatBasePx,
          'lines': lines,
        };
        File('$_outDir/probe.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
        expect(lines, hasLength(_columnCount * _repeatBasePx.length * _fractions.length));
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
