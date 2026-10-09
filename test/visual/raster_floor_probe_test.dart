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
  const _Case(this.tag, this.text, this.sizePt, this.rtl);
  final String tag;
  final String text;
  final double sizePt;
  final bool rtl;
}

const List<_Case> _cases = <_Case>[
  _Case('9_lI', 'lI', 9, false),
  _Case('11_lI', 'lI', 11, false),
  _Case('14_lI', 'lI', 14, false),
  _Case('11_ar', 'واختبار', 11, true),
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
      final baselineFromTop =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
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
                      Positioned(
                        left: _leftPx,
                        top: _baselinePx - baselineFromTop,
                        child: Text(
                          probeCase.text,
                          style: style,
                          textDirection: direction,
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
              final baselinePt = _baselinePx * 0.75;
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
                      top: baselinePt - offset,
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
