// [C6-DIAG] TEMPORARY element probe: frames, dividers and borders, Preview paint
// path vs PDF paint path, each condition isolated on its own page. Not for merge.
// Diagnostic only: no production code is touched and no expected image is written.
//
// Preview mirrors the production calls exactly:
//   _paintFloatFrame / _paintShape(square) / _paintDecoration(border): drawRect, stroke
//   centred on the rect, colour black;  _paintDecoration(divider): filled drawRect.
// PDF mirrors the production paths exactly:
//   'svg'    : FloatingElementsPdf.shapeToSvg(square) inside SvgImage (shape path)
//   'border' : pw.Container + pw.Border.all (text-box frame and decoration border)
//   'divider': pw.Container with colour (decoration divider)
//
// Writes build/visual_parity/eprobe/{manifest.json, e_fl_<id>.png, e_pdf_<id>.pdf}.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/pdf_engine/floating_elements_pdf.dart';

const double _pageWpx = 420;
const double _pageHpx = 200;
const double _pageWpt = 315;
const double _pageHpt = 150;
const String _outDir = 'build/visual_parity/eprobe';

/// preview: frame | divider ; pdf: svg | border | divider
const List<Map<String, Object>> _cases = <Map<String, Object>>[
  <String, Object>{'id': 'frame2_svg', 'preview': 'frame', 'pdf': 'svg', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 2.0},
  <String, Object>{'id': 'frame2_border', 'preview': 'frame', 'pdf': 'border', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 2.0},
  <String, Object>{'id': 'frame1_svg', 'preview': 'frame', 'pdf': 'svg', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 1.0},
  <String, Object>{'id': 'frame1_border', 'preview': 'frame', 'pdf': 'border', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 1.0},
  <String, Object>{'id': 'frame05_svg', 'preview': 'frame', 'pdf': 'svg', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 0.5},
  <String, Object>{'id': 'frame05_border', 'preview': 'frame', 'pdf': 'border', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 0.5},
  <String, Object>{'id': 'divider_12_y30', 'preview': 'divider', 'pdf': 'divider', 'x': 30.0, 'y': 30.0, 'w': 250.0, 'h': 1.2, 'stroke': 0.0},
  <String, Object>{'id': 'divider_12_y3025', 'preview': 'divider', 'pdf': 'divider', 'x': 30.0, 'y': 30.25, 'w': 250.0, 'h': 1.2, 'stroke': 0.0},
  <String, Object>{'id': 'divider_12_y305', 'preview': 'divider', 'pdf': 'divider', 'x': 30.0, 'y': 30.5, 'w': 250.0, 'h': 1.2, 'stroke': 0.0},
  <String, Object>{'id': 'border1_border', 'preview': 'frame', 'pdf': 'border', 'x': 30.0, 'y': 30.0, 'w': 200.0, 'h': 100.0, 'stroke': 1.0},
];

class _ElemPainter extends CustomPainter {
  _ElemPainter({required this.preview, required this.rect, required this.stroke});

  final String preview;
  final ui.Rect rect;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(4 / 3);
    if (preview == 'divider') {
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.black
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ElemPainter oldDelegate) => true;
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

pw.Widget _pdfElement(String mode, double x, double y, double w, double h, double stroke) {
  final child = switch (mode) {
    'svg' => pw.SizedBox(
        width: w,
        height: h,
        child: pw.SvgImage(
          svg: FloatingElementsPdf.shapeToSvg(
            FloatingShapeType.square,
            w,
            h,
            strokeWidth: stroke,
          ),
          fit: pw.BoxFit.fill,
        ),
      ),
    'border' => pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: stroke),
        ),
      ),
    _ => pw.Container(width: w, height: h, color: PdfColors.black),
  };
  return pw.Positioned(left: x, top: y, child: child);
}

void main() {
  testWidgets('[C6-DIAG] element probe', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final manifest = <Map<String, Object?>>[];
    for (final c in _cases) {
      final id = c['id']! as String;
      final preview = c['preview']! as String;
      final pdfMode = c['pdf']! as String;
      final x = c['x']! as double;
      final y = c['y']! as double;
      final w = c['w']! as double;
      final h = c['h']! as double;
      final stroke = c['stroke']! as double;

      final key = GlobalKey();
      await tester.pumpWidget(
        _frame(
          key,
          _ElemPainter(
            preview: preview,
            rect: ui.Rect.fromLTWH(x, y, w, h),
            stroke: stroke,
          ),
        ),
      );
      await tester.pump();
      final pngPath = '$_outDir/e_fl_$id.png';
      await _capture(tester, key, pngPath);

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
                  _pdfElement(pdfMode, x, y, w, h, stroke),
                ],
              ),
            ),
          ),
        );
        return doc.save();
      });
      final pdfPath = '$_outDir/e_pdf_$id.pdf';
      File(pdfPath).writeAsBytesSync(pdfBytes!);
      manifest.add(<String, Object?>{
        'id': id,
        'preview': preview,
        'pdf': pdfMode,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'stroke': stroke,
        'png': pngPath,
        'pdfPath': pdfPath,
      });
    }
    File('$_outDir/manifest.json').writeAsStringSync(
      jsonEncode(<String, Object?>{'cases': manifest}),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
