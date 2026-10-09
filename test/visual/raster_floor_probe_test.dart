// [C6-DIAG] TEMPORARY raster-floor probe (not for merge).
//
// Renders the same glyph string at the same geometry twice: once as the Flutter
// preview would (TextPainter/Text with the app's NotoNaskh asset, 11pt -> px at
// 96/72), and once as a Vector PDF (package:pdf drawString at the same baseline).
// A solid calibration rectangle sits in both. tool/diag_visual_geometry.py
// rasterizes the PDF with poppler and MuPDF and compares ink coverage, so the
// rendering stack can be measured on identical geometry without the fixture.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';

const String _family = 'ProbeNaskh';
const String _probeText = 'lI';
const double _sizePt = 11;
const double _sizePx = _sizePt * 96 / 72;
const double _baselinePx = 40;
const double _leftPx = 20;
// Page is 200x60 px at 96 dpi => 150x45 pt (1px = 0.75pt).
const double _pageWpx = 200;
const double _pageHpx = 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('[C6-DIAG] raster floor probe writes Flutter PNG and PDF',
      (tester) async {
    Directory('build/visual_parity').createSync(recursive: true);

    final loader = FontLoader(_family)
      ..addFont(rootBundle.load(ExamFonts.regularAsset));
    await loader.load();

    tester.view.physicalSize = const Size(_pageWpx, _pageHpx);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const style = TextStyle(
      fontFamily: _family,
      fontSize: _sizePx,
      color: Color(0xFF000000),
    );
    final painter = TextPainter(
      text: const TextSpan(text: _probeText, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baselineFromTop =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.dispose();

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _pageWpx,
              height: _pageHpx,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Positioned(
                    left: _leftPx,
                    top: _baselinePx - baselineFromTop,
                    child: const Text(_probeText, style: style),
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
    );
    await tester.pump();

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('build/visual_parity/raster_probe_flutter.png')
        .writeAsBytesSync(png!);

    final pdfBytes = await tester.runAsync(() async {
      final font = pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
      final doc = PdfDocument();
      final page = PdfPage(doc, pageFormat: const PdfPageFormat(150, 45));
      final graphics = page.getGraphics();
      final context = pw.Context(
        document: doc,
        page: page,
        canvas: graphics,
      );
      graphics.drawString(
        font.getFont(context),
        _sizePt,
        _probeText,
        _leftPx * 0.75,
        (_pageHpx - _baselinePx) * 0.75,
      );
      graphics.setFillColor(PdfColors.black);
      graphics.drawRect(100 * 0.75, (_pageHpx - 20) * 0.75, 20 * 0.75,
          10 * 0.75);
      graphics.fillPath();
      return doc.save();
    });
    File('build/visual_parity/raster_probe.pdf')
        .writeAsBytesSync(pdfBytes!);
  });
}
