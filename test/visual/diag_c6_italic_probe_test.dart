// [C6-DIAG-2] TEMPORARY italic isolation probe. Not for merge; removed in cleanup.
// Preview mirrors CanonicalLayoutPreview._paintText (pt mode, canvas scaled 4/3,
// baseline from computeLineMetrics). line-height factor is an assumed 1.45 (not
// measured from production data). PDF uses the regular embedded TTF, with and
// without TextStyle.fontStyle=italic, which is what the canonical PDF engine does.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const double _pageWpx = 420;
const double _pageHpx = 200;
const double _pageWpt = 315;
const double _pageHpt = 150;
const String _outDir = 'build/visual_parity/c6diag';
const String _regularAsset = 'assets/fonts/NotoNaskhArabic-Regular.ttf';

/// y = top of the line box in pt; baseline is y + 14 pt.
const List<Map<String, Object>> _lines = <Map<String, Object>>[
  <String, Object>{'id': 'lat_a', 'text': 'Vocabulary words 0123', 'size': 10.5, 'y': 12.0, 'rtl': false, 'pdf': true},
  <String, Object>{'id': 'lat_b', 'text': 'answer words Latin', 'size': 14.0, 'y': 42.0, 'rtl': false, 'pdf': true},
  <String, Object>{'id': 'ar_a', 'text': 'بسم الله الرحمن الرحيم', 'size': 10.5, 'y': 72.0, 'rtl': true, 'pdf': false},
  <String, Object>{'id': 'mix_a', 'text': 'answer واختبار', 'size': 10.5, 'y': 102.0, 'rtl': false, 'pdf': false},
];

class _TextPainterProbe extends CustomPainter {
  _TextPainterProbe({required this.italic});

  final bool italic;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(4 / 3);
    for (final line in _lines) {
      final text = line['text']! as String;
      final fontSize = line['size']! as double;
      final top = line['y']! as double;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'NotoNaskhArabic',
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: const Color(0xFF000000),
            height: 1.45,
          ),
        ),
        textDirection:
            (line['rtl']! as bool) ? TextDirection.rtl : TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout(maxWidth: double.infinity);
      try {
        final metrics = painter.computeLineMetrics();
        final baselineOffset = metrics.isEmpty ? 0.0 : metrics.first.baseline;
        painter.paint(canvas, Offset(20, top + 14 - baselineOffset));
      } finally {
        painter.dispose();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TextPainterProbe oldDelegate) => true;
}

Widget _frame(GlobalKey key, CustomPainter painter) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: SizedBox(
              width: _pageWpx,
              height: _pageHpx,
              child: CustomPaint(
                painter: painter,
                size: const Size(_pageWpx, _pageHpx),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(png!);
}

void main() {
  testWidgets('[C6-DIAG-2] italic isolation', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final fontData = await tester.runAsync(() => rootBundle.load(_regularAsset));
    final font = pw.Font.ttf(fontData!);

    final manifest = <Map<String, Object?>>[];
    for (final variant in <String>['pv_up', 'pv_it', 'pdf_up', 'pdf_it']) {
      final pngPath = '$_outDir/i_$variant.png';
      final pdfPath = '$_outDir/i_$variant.pdf';
      if (variant.startsWith('pv_')) {
        final key = GlobalKey();
        await tester.pumpWidget(
          _frame(key, _TextPainterProbe(italic: variant == 'pv_it')),
        );
        await tester.pump();
        await _capture(tester, key, pngPath);
      } else {
        final pdfBytes = await tester.runAsync(() async {
          final doc = pw.Document();
          doc.addPage(
            pw.Page(
              pageFormat: const PdfPageFormat(_pageWpt, _pageHpt),
              margin: pw.EdgeInsets.zero,
              build: (context) => pw.SizedBox(
                width: _pageWpt,
                height: _pageHpt,
                child: pw.Stack(
                  children: <pw.Widget>[
                    for (final line in _lines)
                      if (line['pdf']! as bool)
                        pw.Positioned(
                          left: 20,
                          top: line['y']! as double,
                          child: pw.Text(
                            line['text']! as String,
                            style: pw.TextStyle(
                              font: font,
                              fontSize: line['size']! as double,
                              color: PdfColors.black,
                              fontStyle: variant == 'pdf_it'
                                  ? pw.FontStyle.italic
                                  : pw.FontStyle.normal,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          );
          return doc.save();
        });
        File(pdfPath).writeAsBytesSync(pdfBytes!);
      }
      manifest.add(<String, Object?>{
        'variant': variant,
        'png': variant.startsWith('pv_') ? pngPath : null,
        'pdfPath': variant.startsWith('pdf_') ? pdfPath : null,
      });
    }
    File('$_outDir/italic_manifest.json').writeAsStringSync(
      jsonEncode(<String, Object?>{'lines': _lines, 'variants': manifest}),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
