// [C6-RASTER] TEMPORARY baseline sub-pixel probe (non-gating). Not for merge.
//
// Question: do the Preview (Flutter) and the vector PDF (rendered by poppler)
// place a text baseline the same way when the baseline falls at different
// fractions of a device pixel? One hypothesis is that one of the two
// rasterizers snaps the glyph baseline to whole pixels with a different rule.
//
// Single factor: the fractional part of the baseline, in device pixels. Every
// other input is held fixed (font, size, x, text, page scale).
//
// The Preview side mirrors CanonicalLayoutPreviewPage._paintText: a canvas
// scaled by LayoutUnits.ptToPx(1), a TextPainter with the same configuration,
// and the paint offset line.baseline - painter baseline.
//
// The PDF side reuses the production chain for one single-word run:
// PdfTextMetrics.baselineOffsetFromTop for the widget top, and CanonicalText
// for the ink. Nothing in lib/ is modified.
//
// Output (build/visual_parity/c6diag/baseline_raster/):
//   preview_raster.png  Flutter raster of the probe page (794 x 1123 px)
//   baseline_probe.pdf  the same lines as a vector PDF (A4)
//   probe.json          intended baselines per line, for tool/diag_c6_baseline_raster.py
// The measurement and the rasterization by poppler happen in that tool.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

const String _outDir = 'build/visual_parity/c6diag/baseline_raster';
const String _fontAsset = 'assets/fonts/Tajawal-Regular.ttf';
const String _family = 'Tajawal';
const String _probeText = 'HAMDxgyp';
const double _fontSizePt = 11;
const double _xPt = 56.7;
const int _pageWidthPx = 794;
const int _pageHeightPx = 1123;

/// Lines: 20 rows. The fractional part cycles through 0.0 .. 0.9 (device px),
/// and each row starts 50 px lower, so the base integer varies too.
const int _lineCount = 20;
const double _rowPitchPx = 50;
const double _firstBaselinePx = 60;

double _fractionOf(int index) => (index % 10) / 10.0;

double _baselinePxOf(int index) =>
    _firstBaselinePx + index * _rowPitchPx + _fractionOf(index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-RASTER] baseline sub-pixel probe (non-gating)',
    (tester) async {
      await tester.runAsync(() async {
        final loader = FontLoader(_family)
          ..addFont(rootBundle.load(_fontAsset));
        await loader.load();
        final fontBytes = await rootBundle.load(_fontAsset);

        Directory(_outDir).createSync(recursive: true);

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
        for (var i = 0; i < _lineCount; i++) {
          final baselinePx = _baselinePxOf(i);
          final baselinePt = LayoutUnits.pxToPt(baselinePx);
          final painter = TextPainter(
            text: const TextSpan(
              text: _probeText,
              style: TextStyle(
                fontFamily: _family,
                fontSize: _fontSizePt,
                fontWeight: FontWeight.w400,
                color: Color(0xFF000000),
              ),
            ),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
          )..layout(maxWidth: double.infinity);
          final innerBaselinePt = painter.computeLineMetrics().first.baseline;
          final paintTopPt = baselinePt - innerBaselinePt;
          painter.paint(canvas, Offset(_xPt, paintTopPt));
          painter.dispose();
          lines.add(<String, Object?>{
            'index': i,
            'fraction': _fractionOf(i),
            'baselinePx': baselinePx,
            'baselinePt': baselinePt,
            'previewInnerBaselinePt': innerBaselinePt,
            'previewPaintTopPt': paintTopPt,
          });
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
        final pdfFont = pw.Font.ttf(fontBytes);
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              final pdfFace = pdfFont.getFont(context);
              final children = <pw.Widget>[];
              for (final line in lines) {
                final baselinePt = line['baselinePt']! as double;
                final offsetPt = PdfTextMetrics.baselineOffsetFromTop(
                  font: pdfFace,
                  fontSizePt: _fontSizePt,
                  text: _probeText,
                );
                final top = baselinePt - offsetPt;
                final advancePt =
                    pdfFace.stringMetrics(_probeText).advanceWidth *
                        _fontSizePt;
                line['pdfTextTopOffsetPt'] = offsetPt;
                line['pdfWidgetTopPt'] = top;
                children.add(
                  pw.Positioned(
                    left: _xPt,
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
          'schema': 'c6-baseline-raster-v1',
          'synthetic': false,
          'family': _family,
          'fontAsset': _fontAsset,
          'text': _probeText,
          'fontSizePt': _fontSizePt,
          'xPt': _xPt,
          'pageWidthPx': _pageWidthPx,
          'pageHeightPx': _pageHeightPx,
          'scalePxPerPt': LayoutUnits.ptToPx(1),
          'lines': lines,
        };
        File('$_outDir/probe.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
        expect(lines, hasLength(_lineCount));
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
