// [C6-RASTER] TEMPORARY baseline sub-pixel probe v5 (non-gating). Not for merge.
//
// Question: does the Preview (Flutter) vs vector PDF (poppler) difference in
// the vertical ink position depend on the FONT, at fixed baseline fractions?
//
// v4 single factor: the font family (the four production families).
//   v5 keeps every v4 factor and changes only the glyph set to a single flat-
//   bottomed 'H', so the ink bottom edge equals the baseline and can be
//   measured below one pixel (descenders g y p would contaminate it).
//   Every column uses the same size (11 pt), the same production line-height
//   factor on the preview side (LayoutConfiguration().lineHeightFactor), the
//   same text, the same 20 baseline fractions 0.025 .. 0.975 device px, and
//   the same integer row grid. Only the font changes, by column.
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
//   probe.json          intended baselines, font and column per line
// The measurement and the rasterization by poppler happen in that tool.
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

/// 20 rows per font. Rows are 50 px apart; the same 20 fractions and the same
/// integer row grid are used in every column.
const int _rowsPerFont = 20;
const double _rowPitchPx = 50;
const double _firstBaselinePx = 60;
const double _columnPitchPx = 195;
const double _firstColumnPx = 20;

double _fractionOf(int row) => 0.025 + 0.05 * row;

double _baselinePxOf(int row) =>
    _firstBaselinePx + row * _rowPitchPx + _fractionOf(row);

double _columnXPx(int column) => _firstColumnPx + column * _columnPitchPx;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-RASTER] baseline sub-pixel probe v5 (non-gating)',
    (tester) async {
      await tester.runAsync(() async {
        final fontBytes = <String, ByteData>{};
        for (final font in _fonts) {
          final bytes = await rootBundle.load(font.asset);
          final loader = FontLoader(font.family)..addFont(rootBundle.load(font.asset));
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
        for (var c = 0; c < _fonts.length; c++) {
          final font = _fonts[c];
          final xPx = _columnXPx(c);
          final xPt = LayoutUnits.pxToPt(xPx);
          for (var r = 0; r < _rowsPerFont; r++) {
            final baselinePx = _baselinePxOf(r);
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
            final paintTopPt = baselinePt - innerBaselinePt;
            painter.paint(canvas, Offset(xPt, paintTopPt));
            painter.dispose();
            lines.add(<String, Object?>{
              'index': lines.length,
              'group': font.family,
              'column': c,
              'xPx': xPx,
              // Horizontal measurement window for this column only. Covers the
              // column's ink (about 21..86, 215..284, 410..489, 605..676 px) and
              // no neighbouring column.
              'winX0': (xPx - 4).round(),
              'winX1': (xPx + 150).round(),
              'heightFactor': height,
              'fraction': _fractionOf(r),
              'baselinePx': baselinePx,
              'baselinePt': baselinePt,
              'xPt': xPt,
              'previewInnerBaselinePt': innerBaselinePt,
              'previewPaintTopPt': paintTopPt,
            });
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
                final font = _fonts[line['column']! as int];
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
                    pdfFace.stringMetrics(_probeText).advanceWidth *
                        _fontSizePt;
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
          'schema': 'c6-baseline-raster-v5',
          'synthetic': false,
          'text': _probeText,
          'fontSizePt': _fontSizePt,
          'pageWidthPx': _pageWidthPx,
          'pageHeightPx': _pageHeightPx,
          'scalePxPerPt': LayoutUnits.ptToPx(1),
          'productionLineHeightFactor': height,
          'fonts': [for (final f in _fonts) f.family],
          'lines': lines,
        };
        File('$_outDir/probe.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
        expect(lines, hasLength(_fonts.length * _rowsPerFont));
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
