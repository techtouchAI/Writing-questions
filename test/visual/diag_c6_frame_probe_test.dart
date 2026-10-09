// [C6-DIAG-2] TEMPORARY frame matrix. Not for merge; removed in cleanup.
// Diagnostic only. No production file is changed. The SVG variants below are local
// copies of the production markup with one property varied at a time.
//
// Variants (PDF side):
//   svg_inset            production FloatingElementsPdf.shapeToSvg (inset stroke/2), SvgImage default clip
//   svg_full_clip        full-box rect, #111827 stroke, white fill, SvgImage default clip
//   svg_full_noclip      full-box rect, #111827 stroke, white fill, SvgImage clip:false
//   svg_full_noclip_black full-box rect, black stroke, white fill, clip:false
//   border_black         pw.Container + pw.Border.all (black), no fill
// Preview side: drawRect with stroke centred on the rect, black (as _paintFloatFrame).
// bg=true adds a black interior block (occlusion check: does the white fill hide content?).
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
const String _outDir = 'build/visual_parity/c6diag';
const double _w = 90;
const double _h = 67.5;

const List<List<double>> _positions = <List<double>>[
  <double>[87.75, 60.5],
  <double>[30.25, 30.5],
  <double>[30.5, 30.75],
  <double>[150.0, 20.25],
];
const List<double> _strokes = <double>[0.5, 1.0, 2.0];
const List<String> _variants = <String>[
  'svg_inset',
  'svg_full_clip',
  'svg_full_noclip',
  'svg_full_noclip_black',
  'border_black',
];

class _FramePainter extends CustomPainter {
  _FramePainter({required this.rect, required this.stroke, required this.bg});

  final ui.Rect rect;
  final double stroke;
  final bool bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(4 / 3);
    if (bg) {
      canvas.drawRect(
        rect.deflate(5),
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) => true;
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

String _svgFull(double w, double h, double s, String colour) {
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
      'viewBox="0 0 $w $h">'
      '<rect x="0" y="0" width="$w" height="$h" fill="#FFFFFF" '
      'stroke="$colour" stroke-width="$s" stroke-linejoin="round" '
      'stroke-linecap="round"/></svg>';
}

pw.Widget _pdfFrame(String variant, double w, double h, double s) {
  final child = switch (variant) {
    'svg_inset' => pw.SvgImage(
        svg: FloatingElementsPdf.shapeToSvg(
          FloatingShapeType.square,
          w,
          h,
          strokeWidth: s,
        ),
        fit: pw.BoxFit.fill,
      ),
    'svg_full_clip' => pw.SvgImage(
        svg: _svgFull(w, h, s, '#111827'),
        fit: pw.BoxFit.fill,
      ),
    'svg_full_noclip' => pw.SvgImage(
        svg: _svgFull(w, h, s, '#111827'),
        fit: pw.BoxFit.fill,
        clip: false,
      ),
    'svg_full_noclip_black' => pw.SvgImage(
        svg: _svgFull(w, h, s, '#000000'),
        fit: pw.BoxFit.fill,
        clip: false,
      ),
    _ => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: s),
        ),
      ),
  };
  return pw.SizedBox(width: w, height: h, child: child);
}

void main() {
  testWidgets('[C6-DIAG-2] frame matrix', (tester) async {
    Directory(_outDir).createSync(recursive: true);
    final cases = <Map<String, Object>>[];
    for (var p = 0; p < _positions.length; p++) {
      for (final s in _strokes) {
        for (final v in _variants) {
          cases.add(<String, Object>{'pos': p, 'stroke': s, 'variant': v, 'bg': false});
        }
      }
    }
    for (final v in _variants) {
      cases.add(<String, Object>{'pos': 0, 'stroke': 1.0, 'variant': v, 'bg': true});
    }

    final manifest = <Map<String, Object?>>[];
    for (final c in cases) {
      final p = c['pos']! as int;
      final s = c['stroke']! as double;
      final v = c['variant']! as String;
      final bg = c['bg']! as bool;
      final x = _positions[p][0];
      final y = _positions[p][1];
      final id = 'p${p}_s${s.toString().replaceAll('.', '_')}_$v${bg ? '_bg' : ''}';
      final rect = ui.Rect.fromLTWH(x, y, _w, _h);

      final key = GlobalKey();
      await tester.pumpWidget(_frame(key, _FramePainter(rect: rect, stroke: s, bg: bg)));
      await tester.pump();
      final pngPath = '$_outDir/f_fl_$id.png';
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
                  if (bg)
                    pw.Positioned(
                      left: x + 5,
                      top: y + 5,
                      child: pw.SizedBox(
                        width: _w - 10,
                        height: _h - 10,
                        child: pw.Container(color: PdfColors.black),
                      ),
                    ),
                  pw.Positioned(left: x, top: y, child: _pdfFrame(v, _w, _h, s)),
                ],
              ),
            ),
          ),
        );
        return doc.save();
      });
      final pdfPath = '$_outDir/f_pdf_$id.pdf';
      File(pdfPath).writeAsBytesSync(pdfBytes!);
      manifest.add(<String, Object?>{
        'id': id,
        'pos': p,
        'x': x,
        'y': y,
        'w': _w,
        'h': _h,
        'stroke': s,
        'variant': v,
        'bg': bg,
        'png': pngPath,
        'pdfPath': pdfPath,
      });
    }
    File('$_outDir/frame_manifest.json').writeAsStringSync(
      jsonEncode(<String, Object?>{'cases': manifest}),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
