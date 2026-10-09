// [C6-DIAG] TEMPORARY baseline-model probe. Not for merge; removed in cleanup.
//
// Production-equivalent, pt mode:
// * Preview mirrors CanonicalLayoutPreview._paintText: TextStyle with fontSize
//   in pt, TextPainter(height: lineHeight, maxLines: 1, noScaling), painted at
//   Offset(x, baseline - computeLineMetrics().first.baseline) on a canvas scaled
//   by 4/3 (ptToPx(1)).
// * PDF mirrors the production path: CanonicalText placed at
//   baseline - PdfTextMetrics.baselineOffsetFromTop(run text).
//
// Writes build/visual_parity/bprobe/{manifest.json, *.png, *.pdf}. All analysis
// happens in tool/diag_baseline_model.py (Poppler + MuPDF, numpy).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

const double _pageWpx = 420;
const double _pageHpx = 60;
const double _baselineBasePx = 40;
const double _leftPx = 20;
const double _ptPerPx = 0.75;
const double _pageWpt = _pageWpx * _ptPerPx;
const double _pageHpt = _pageHpx * _ptPerPx;
const String _outDir = 'build/visual_parity/bprobe';
const String _latText = 'lI';
const String _arText = 'ااا';
const List<double> _fracs = <double>[
  0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, //
];

const Map<String, List<String>> _familyAssets = <String, List<String>>{
  'NotoNaskhArabic': <String>[ExamFont.regularAsset, ExamFont.boldAsset],
  'Amiri': <String>[ExamFont.quranicAsset],
  'Tajawal': <String>[ExamFont.tajawalRegularAsset, ExamFont.tajawalBoldAsset],
  'Rakkas': <String>[ExamFont.rakkasRegularAsset],
};

const List<String> _ladderTexts = <String>[
  'ااا',
  'واختبار',
  'واختبار   السطر',
  '٢٠٢٦ ٢٠٢٧',
  '2026 2027',
  '(   ) . مدنية',
  'lI',
  'answer words',
];
const List<bool> _ladderRtl = <bool>[
  true,
  true,
  true,
  true,
  false,
  true,
  false,
  false,
];

TextStyle _style(
  String family,
  double sizePt,
  bool bold,
  bool italic,
  double lineHeight,
) {
  return TextStyle(
    fontFamily: family,
    fontSize: sizePt,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: Colors.black,
    height: lineHeight,
  );
}

/// Advance in pt (layout runs in pt units; no canvas scale involved).
double _advancePt(
  String text,
  String family,
  double sizePt,
  bool bold,
  bool italic,
  double lineHeight,
  bool rtl,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _style(family, sizePt, bold, italic, lineHeight),
    ),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Mirrors CanonicalLayoutPreview._paintText on a 4/3-scaled canvas.
class _ProdLinePainter extends CustomPainter {
  const _ProdLinePainter({
    required this.text,
    required this.family,
    required this.sizePt,
    required this.bold,
    required this.italic,
    required this.lineHeight,
    required this.rtl,
    required this.baselinePt,
    required this.leftPt,
  });

  final String text;
  final String family;
  final double sizePt;
  final bool bold;
  final bool italic;
  final double lineHeight;
  final bool rtl;
  final double baselinePt;
  final double leftPt;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(4 / 3);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _style(family, sizePt, bold, italic, lineHeight),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    try {
      final metrics = painter.computeLineMetrics();
      final baselineOffset = metrics.isEmpty ? 0.0 : metrics.first.baseline;
      painter.paint(canvas, Offset(leftPt, baselinePt - baselineOffset));
    } finally {
      painter.dispose();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ProdLinePainter oldDelegate) => true;
}

Widget _frame(GlobalKey key, CustomPainter painter) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      // Align loosens the Scaffold body constraints so the boundary is exactly
      // _pageWpx x _pageHpx and anchored at the top-left (device pixel origin).
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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String path,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(png!);
}

Future<Uint8List> _sweepPdf({
  required ExamFonts fonts,
  required PaperFont paperFont,
  required bool bold,
  required String text,
  required bool rtl,
  required double sizePt,
  required double advancePt,
}) async {
  final font = fonts.fontFor(paperFont, bold: bold);
  final doc = pw.Document();
  for (final frac in _fracs) {
    final baselinePt = (_baselineBasePx + frac) * _ptPerPx;
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_pageWpt, _pageHpt),
        margin: pw.EdgeInsets.zero,
        build: (context) {
          // Production C1 mapping: top = baseline - offsetFromTop(run text).
          final offset = PdfTextMetrics.baselineOffsetFromTop(
            font: font.getFont(context),
            fontSizePt: sizePt,
            text: text,
          );
          return pw.SizedBox(
            width: _pageWpt,
            height: _pageHpt,
            child: pw.Stack(
              children: <pw.Widget>[
                pw.Positioned(
                  left: _leftPx * _ptPerPx,
                  top: baselinePt - offset,
                  child: CanonicalText(
                    text: text,
                    font: font,
                    fontSizePt: sizePt,
                    color: PdfColors.black,
                    canonicalAdvancePt: advancePt,
                    rtl: rtl,
                    underline: false,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  return doc.save();
}

String _tagOf(String family, double size, bool bold, bool italic, double lh) {
  final raw =
      '${family}_s${(size * 100).round()}_${bold ? 'b' : 'r'}'
      '${italic ? 'i' : 'n'}_lh${(lh * 100).round()}';
  return raw;
}

void main() {
  testWidgets(
    '[C6-DIAG] baseline model probe',
    (tester) async {
      final geoFile = File('build/visual_parity/diag_geometry.json');
      expect(
        geoFile.existsSync(),
        isTrue,
        reason: 'fixture test must write diag_geometry.json first',
      );
      Directory(_outDir).createSync(recursive: true);

      await tester.runAsync(() async {
        for (final entry in _familyAssets.entries) {
          final loader = FontLoader(entry.key);
          for (final asset in entry.value) {
            loader.addFont(rootBundle.load(asset));
          }
          await loader.load();
        }
      });
      final fonts = (await tester.runAsync(() => ExamFonts.load()))!;

      // Style combos exactly as used by the fixture (font, size, bold, italic, lh).
      final geo = jsonDecode(geoFile.readAsStringSync()) as Map<String, dynamic>;
      final combos = <String, Map<String, Object>>{};
      for (final page in (geo['pages'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        for (final w in (page['words'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
          final family = w['font'] as String;
          final size = (w['size'] as num).toDouble();
          final bold = w['bold'] as bool;
          final italic = w['italic'] as bool;
          final lh = (w['lh'] as num?)?.toDouble() ?? -1;
          final tag = _tagOf(family, size, bold, italic, lh);
          combos.putIfAbsent(
            tag,
            () => <String, Object>{
              'family': family,
              'size': size,
              'bold': bold,
              'italic': italic,
              'lh': lh,
              'tag': tag,
            },
          );
        }
      }

      final sweep = <Map<String, Object?>>[];
      final scripts = <String, List<Object>>{
        'lat': <Object>[_latText, false],
        'ar': <Object>[_arText, true],
      };
      for (final combo in combos.values) {
        final family = combo['family']! as String;
        final size = combo['size']! as double;
        final bold = combo['bold']! as bool;
        final italic = combo['italic']! as bool;
        final lh = combo['lh']! as double;
        final tag = combo['tag']! as String;
        final paperFont = PaperFont.values.firstWhere(
          (f) => f.family == family,
        );
        for (final scriptEntry in scripts.entries) {
          final text = scriptEntry.value[0] as String;
          final rtl = scriptEntry.value[1] as bool;
          final script = scriptEntry.key;
          final pngs = <String>[];
          for (var i = 0; i < _fracs.length; i++) {
            final baselinePt = (_baselineBasePx + _fracs[i]) * _ptPerPx;
            final key = GlobalKey();
            await tester.pumpWidget(
              _frame(
                key,
                _ProdLinePainter(
                  text: text,
                  family: family,
                  sizePt: size,
                  bold: bold,
                  italic: italic,
                  lineHeight: lh,
                  rtl: rtl,
                  baselinePt: baselinePt,
                  leftPt: _leftPx * _ptPerPx,
                ),
              ),
            );
            await tester.pump();
            final path = '$_outDir/fl_${tag}_${script}_f$i.png';
            await _capture(tester, key, path);
            pngs.add(path);
          }
          final advance = _advancePt(
            text,
            family,
            size,
            bold,
            italic,
            lh,
            rtl,
          );
          final pdfBytes = await tester.runAsync(
            () => _sweepPdf(
              fonts: fonts,
              paperFont: paperFont,
              bold: bold,
              text: text,
              rtl: rtl,
              sizePt: size,
              advancePt: advance,
            ),
          );
          final pdfPath = '$_outDir/pdf_${tag}_$script.pdf';
          File(pdfPath).writeAsBytesSync(pdfBytes!);
          sweep.add(<String, Object?>{
            'tag': tag,
            'family': family,
            'size': size,
            'bold': bold,
            'italic': italic,
            'lh': lh,
            'script': script,
            'rtl': rtl,
            'text': text,
            'pdf': pdfPath,
            'png': pngs,
          });
        }
      }

      // Ladder: fixed style, Flutter whole-string draw at f = 0; PDF per word at
      // Flutter's word boxes (production places words at layout word.x) with the
      // top offset taken from the whole run text.
      const ladderFamily = 'NotoNaskhArabic';
      const ladderSize = 11.0;
      const ladderLh = 1.7;
      final ladderItems = <Map<String, Object?>>[];
      final naskh = PaperFont.naskh;
      for (var i = 0; i < _ladderTexts.length; i++) {
        final text = _ladderTexts[i];
        final rtl = _ladderRtl[i];
        final key = GlobalKey();
        await tester.pumpWidget(
          _frame(
            key,
            _ProdLinePainter(
              text: text,
              family: ladderFamily,
              sizePt: ladderSize,
              bold: false,
              italic: false,
              lineHeight: ladderLh,
              rtl: rtl,
              baselinePt: _baselineBasePx * _ptPerPx,
              leftPt: _leftPx * _ptPerPx,
            ),
          ),
        );
        await tester.pump();
        final pngPath = '$_outDir/ladder_fl_$i.png';
        await _capture(tester, key, pngPath);

        final measure = TextPainter(
          text: TextSpan(
            text: text,
            style: _style(ladderFamily, ladderSize, false, false, ladderLh),
          ),
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);
        final words = <Map<String, Object?>>[];
        for (final m in RegExp(r'\S+').allMatches(text)) {
          final boxes = measure.getBoxesForRange(
            TextSelection(baseOffset: m.start, extentOffset: m.end),
          );
          var left = double.infinity;
          var right = double.negativeInfinity;
          for (final b in boxes) {
            left = left < b.left ? left : b.left;
            right = right > b.right ? right : b.right;
          }
          words.add(<String, Object?>{
            'w': m.group(0),
            'x': left,
            'adv': right - left,
          });
        }
        measure.dispose();

        final pdfBytes = await tester.runAsync(() async {
          final font = fonts.fontFor(naskh, bold: false);
          final doc = pw.Document();
          doc.addPage(
            pw.Page(
              pageFormat: const PdfPageFormat(_pageWpt, _pageHpt),
              margin: pw.EdgeInsets.zero,
              build: (context) {
                final offset = PdfTextMetrics.baselineOffsetFromTop(
                  font: font.getFont(context),
                  fontSizePt: ladderSize,
                  text: text,
                );
                final top = _baselineBasePx * _ptPerPx - offset;
                return pw.SizedBox(
                  width: _pageWpt,
                  height: _pageHpt,
                  child: pw.Stack(
                    children: <pw.Widget>[
                      for (final word in words)
                        pw.Positioned(
                          left: _leftPx * _ptPerPx + (word['x']! as double),
                          top: top,
                          child: CanonicalText(
                            text: word['w']! as String,
                            font: font,
                            fontSizePt: ladderSize,
                            color: PdfColors.black,
                            canonicalAdvancePt: word['adv']! as double,
                            rtl: rtl,
                            underline: false,
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
        final pdfPath = '$_outDir/ladder_$i.pdf';
        File(pdfPath).writeAsBytesSync(pdfBytes!);
        ladderItems.add(<String, Object?>{
          'i': i,
          'text': text,
          'rtl': rtl,
          'png': pngPath,
          'pdf': pdfPath,
          'words': words,
        });
      }

      File('$_outDir/manifest.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'fracs': _fracs,
          'sweep': sweep,
          'ladder': <String, Object?>{
            'family': ladderFamily,
            'size': ladderSize,
            'lh': ladderLh,
            'items': ladderItems,
          },
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
