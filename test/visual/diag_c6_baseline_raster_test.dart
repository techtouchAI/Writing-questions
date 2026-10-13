// [C6-RASTER] TEMPORARY baseline sub-pixel probe v3 (non-gating). Not for merge.
//
// Question: do the Preview (Flutter) and the vector PDF (rendered by poppler)
// place a text baseline the same way when the baseline falls at different
// fractions of a device pixel?
//
// v3 single factor: TextStyle.height on the PREVIEW side only.
//   Group A: height unset (the v1/v2 setup, which did not match production).
//   Group B: height = LayoutConfiguration().lineHeightFactor (1.45), the
//            production default passed by CanonicalLayoutPreviewPage._paintText.
// The PDF side is produced identically for both groups. Its equality across
// groups is measured as a control in tool/diag_c6_baseline_raster.py.
//
// Every other input is held fixed (font, size, x, text, page scale).
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
//   probe.json          intended baselines per line, group and height factor
// The measurement and the rasterization by poppler happen in that tool.
import 'dart:convert';
import 'dart:io';
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
const String _fontAsset = 'assets/fonts/Tajawal-Regular.ttf';
const String _family = 'Tajawal';
const String _probeText = 'HAMDxgyp';
const double _fontSizePt = 11;
const double _xPt = 56.7;
const int _pageWidthPx = 794;
const int _pageHeightPx = 1123;

/// 40 rows in two groups of 20. Rows are 27 px apart, so each row's
/// measurement window (16 px up, 10 px down) does not reach its neighbours.
/// The fraction sweeps 0.025 .. 0.975 in both groups (same fractions, same
/// PDF), and the integer part differs between the groups.
const int _rowsPerGroup = 20;
const int _lineCount = 2 * _rowsPerGroup;
const double _rowPitchPx = 27;
const double _firstBaselinePx = 40;

double _fractionOf(int index) => 0.025 + 0.05 * (index % _rowsPerGroup);

String _groupOf(int index) => index < _rowsPerGroup ? 'A' : 'B';

/// Group A: unset (v1/v2). Group B: the production default line-height factor.
double? _previewHeightOf(String group) =>
    group == 'B' ? const LayoutConfiguration().lineHeightFactor : null;

double _baselinePxOf(int index) =>
    _firstBaselinePx + index * _rowPitchPx + _fractionOf(index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-RASTER] baseline sub-pixel probe v3 (non-gating)',
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
          final group = _groupOf(i);
          final height = _previewHeightOf(group);
          final baselinePx = _baselinePxOf(i);
          final baselinePt = LayoutUnits.pxToPt(baselinePx);
          final painter = TextPainter(
            text: TextSpan(
              text: _probeText,
              style: TextStyle(
                fontFamily: _family,
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
          final paintTopPt = baselinePt - innerBaselinePt;
          painter.paint(canvas, Offset(_xPt, paintTopPt));
          painter.dispose();
          lines.add(<String, Object?>{
            'index': i,
            'group': group,
            'heightFactor': height,
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
          'schema': 'c6-baseline-raster-v3',
          'synthetic': false,
          'family': _family,
          'fontAsset': _fontAsset,
          'text': _probeText,
          'fontSizePt': _fontSizePt,
          'xPt': _xPt,
          'pageWidthPx': _pageWidthPx,
          'pageHeightPx': _pageHeightPx,
          'scalePxPerPt': LayoutUnits.ptToPx(1),
          'productionLineHeightFactor': const LayoutConfiguration().lineHeightFactor,
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
