// [C6-DIAG] TEMPORARY raster-floor probe (not for merge).
//
// For each case, renders the same word at the same geometry twice:
//  * Flutter: Text with the app's NotoNaskh asset on a white boundary
//    (pt -> px at 96/72), exactly as the preview paints a line.
//  * PDF: the production per-word path (CanonicalText + the C1 baseline
//    mapping from PdfTextMetrics), with the Flutter-measured advance.
// Both carry a solid calibration rectangle. tool/diag_raster_probe.py
// rasterizes the PDFs with poppler and MuPDF and compares ink coverage on
// identical geometry, without the fixture.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

const String _family = 'ProbeNaskh';
const double _pageWpx = 200;
const double _pageHpx = 60;
const double _baselinePx = 40;
const double _leftPx = 20;

class _Case {
  const _Case(this.tag, this.text, this.sizePt, this.rtl,
      [this.extraPx = 0, this.lineHeight = 1.45, this.ptLogical = false]);
  final String tag;
  final String text;
  final double sizePt;
  final bool rtl;
  // Extra baseline shift (px) applied identically to Flutter and PDF, to test
  // whether Skia snaps baselines to whole device pixels.
  final double extraPx;
  // Paragraph line-height factor (production: document.layout.lineHeightFactor;
  // the visual fixture uses 1.8).
  final double lineHeight;
  // true: lay out in pt on a canvas scaled by 4/3, exactly as
  // CanonicalLayoutPreview._paintText does. false: lay out in px (the earlier
  // probe mode, which does NOT match production).
  final bool ptLogical;
}

const List<_Case> _cases = <_Case>[
  _Case('9_lI', 'lI', 9, false),
  _Case('11_lI', 'lI', 11, false),
  _Case('14_lI', 'lI', 14, false),
  _Case('11_ar', 'واختبار', 11, true),
  _Case('11_lI_b25', 'lI', 11, false, 0.25),
  _Case('11_lI_b50', 'lI', 11, false, 0.5),
  _Case('11_lI_b75', 'lI', 11, false, 0.75),

  _Case('11_lI_f41', 'lI', 11, false, 0.41),
  _Case('11_lI_f88', 'lI', 11, false, 0.88),
  _Case('11_lI_f69', 'lI', 11, false, 0.69),
  _Case('11_lI_p10', 'lI', 11, false, 0.1),
  _Case('11_lI_p20', 'lI', 11, false, 0.2),
  _Case('11_lI_p30', 'lI', 11, false, 0.3),
  _Case('11_lI_p40', 'lI', 11, false, 0.4),
  _Case('11_lI_p50', 'lI', 11, false, 0.5),
  _Case('11_lI_p60', 'lI', 11, false, 0.6),
  _Case('11_lI_p70', 'lI', 11, false, 0.7),
  _Case('11_lI_p80', 'lI', 11, false, 0.8),
  _Case('11_lI_p90', 'lI', 11, false, 0.9),
  _Case('11_lI_h18_p00', 'lI', 11, false, 0.0, 1.8),
  _Case('11_lI_h18_p20', 'lI', 11, false, 0.2, 1.8),
  _Case('11_lI_h18_p40', 'lI', 11, false, 0.4, 1.8),
  _Case('11_lI_h18_p50', 'lI', 11, false, 0.5, 1.8),
  _Case('11_lI_h18_p60', 'lI', 11, false, 0.6, 1.8),
  _Case('11_lI_h18_p70', 'lI', 11, false, 0.7, 1.8),
  _Case('11_lI_h18_p80', 'lI', 11, false, 0.8, 1.8),
  _Case('11_lI_h18_p90', 'lI', 11, false, 0.9, 1.8),
  _Case('11_lI_h10_p00', 'lI', 11, false, 0.0, 1.0),
  _Case('11_lI_h10_p50', 'lI', 11, false, 0.5, 1.0),
  _Case('11_lI_h10_p70', 'lI', 11, false, 0.7, 1.0),
  _Case('11_lI_pt18_p00', 'lI', 11, false, 0.0, 1.8, true),
  _Case('11_lI_pt18_p20', 'lI', 11, false, 0.2, 1.8, true),
  _Case('11_lI_pt18_p40', 'lI', 11, false, 0.4, 1.8, true),
  _Case('11_lI_pt18_p50', 'lI', 11, false, 0.5, 1.8, true),
  _Case('11_lI_pt18_p60', 'lI', 11, false, 0.6, 1.8, true),
  _Case('11_lI_pt18_p70', 'lI', 11, false, 0.7, 1.8, true),
  _Case('11_lI_pt18_p80', 'lI', 11, false, 0.8, 1.8, true),
  _Case('11_lI_pt18_p90', 'lI', 11, false, 0.9, 1.8, true),
  _Case('11_lI_pt145_p00', 'lI', 11, false, 0.0, 1.45, true),
  _Case('11_lI_pt145_p50', 'lI', 11, false, 0.5, 1.45, true),
  _Case('11_lI_pt145_p70', 'lI', 11, false, 0.7, 1.45, true),
  _Case('11_lI_pt10_p00', 'lI', 11, false, 0.0, 1.0, true),
  _Case('11_lI_pt10_p50', 'lI', 11, false, 0.5, 1.0, true),
  _Case('11_lI_pt10_p70', 'lI', 11, false, 0.7, 1.0, true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('[C6-DIAG] raster floor probe writes Flutter PNGs and PDFs',
      (tester) async {
    Directory('build/visual_parity').createSync(recursive: true);

    final loader = FontLoader(_family)
      ..addFont(rootBundle.load(ExamFonts.regularAsset));
    await loader.load();

    tester.view.physicalSize = const Size(_pageWpx, _pageHpx);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final probeCase in _cases) {
      final sizePx = probeCase.sizePt * 96 / 72;
      final direction =
          probeCase.rtl ? TextDirection.rtl : TextDirection.ltr;
      final style = TextStyle(
        fontFamily: _family,
        fontSize: sizePx,
        color: const Color(0xFF000000),
      );
      final painter = TextPainter(
        text: TextSpan(text: probeCase.text, style: style),
        textDirection: direction,
      )..layout();
      final advancePx = painter.width;
      painter.dispose();

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: SizedBox(
                  width: _pageWpx,
                  height: _pageHpx,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ProductionLinePainter(
                            text: probeCase.text,
                            family: _family,
                            sizePx: sizePx,
                            rtl: probeCase.rtl,
                            baselineY: _baselinePx + probeCase.extraPx,
                            leftX: _leftPx,
                            lineHeight: probeCase.lineHeight,
                            ptLogical: probeCase.ptLogical,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 100,
                        top: 10,
                        child: ColoredBox(
                          color: Color(0xFF000000),
                          child: SizedBox(width: 20, height: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('build/visual_parity/raster_probe_flutter_${probeCase.tag}.png')
          .writeAsBytesSync(png!);

      final pdfBytes = await tester.runAsync(() async {
        final font =
            pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(150, 45),
            margin: pw.EdgeInsets.zero,
            build: (context) {
              // Production C1 mapping: top = baseline - offsetFromTop.
              // Baseline is 40px from the top = 30pt; the probe is 45pt tall.
              const baselinePt = (_baselinePx) * 0.75;
              final pdfBaselinePt = baselinePt + probeCase.extraPx * 0.75;
              final offset = PdfTextMetrics.baselineOffsetFromTop(
                font: font.getFont(context),
                fontSizePt: probeCase.sizePt,
                text: probeCase.text,
              );
              return pw.SizedBox(
                width: 150,
                height: 45,
                child: pw.Stack(
                  children: <pw.Widget>[
                    pw.Positioned(
                      left: _leftPx * 0.75,
                      top: pdfBaselinePt - offset,
                      child: CanonicalText(
                        text: probeCase.text,
                        font: font,
                        fontSizePt: probeCase.sizePt,
                        color: PdfColors.black,
                        canonicalAdvancePt: advancePx * 0.75,
                        rtl: probeCase.rtl,
                        underline: false,
                      ),
                    ),
                    pw.Positioned(
                      left: 100 * 0.75,
                      top: 10 * 0.75,
                      child: pw.Container(
                        width: 20 * 0.75,
                        height: 10 * 0.75,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        return doc.save();
      });
      File('build/visual_parity/raster_probe_${probeCase.tag}.pdf')
          .writeAsBytesSync(pdfBytes!);
    }
  });
}

// [C6-DIAG] Mirrors CanonicalLayoutPreview._paintText exactly: TextPainter with
// the production line-height factor, painted at baseline - the first line
// metric's baseline (no Text widget, no computeDistanceToActualBaseline).

class _ProductionLinePainter extends CustomPainter {
  const _ProductionLinePainter({
    required this.text,
    required this.family,
    required this.sizePx,
    required this.rtl,
    required this.baselineY,
    required this.leftX,
    required this.lineHeight,
    required this.ptLogical,
  });

  final String text;
  final String family;
  final double sizePx;
  final bool rtl;
  final double baselineY;
  final double leftX;
  final double lineHeight;
  final bool ptLogical;

  @override
  void paint(Canvas canvas, Size size) {
    // Production: fontSize in pt, canvas scaled by LayoutUnits.ptToPx(1) (4/3).
    final scale = ptLogical ? 4 / 3 : 1.0;
    canvas.save();
    if (ptLogical) {
      canvas.scale(scale);
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: ptLogical ? sizePx * 0.75 : sizePx,
          color: const Color(0xFF000000),
          height: lineHeight,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    try {
      final metrics = painter.computeLineMetrics();
      final baseline = metrics.isEmpty ? 0.0 : metrics.first.baseline;
      painter.paint(
        canvas,
        Offset(leftX / scale, (baselineY / scale) - baseline),
      );
    } finally {
      painter.dispose();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ProductionLinePainter oldDelegate) => false;
}
