// CanonicalText emission primitive (Batch 2): per-word canonical emission
// must replicate the replaced pw.Text ink geometry term-for-term and close
// the viewer-executed advance onto canonical geometry with a trailing TJ
// number derived mathematically from the embedded font's own advance.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';

/// Viewer float quantum: emission rounds through 5-decimal PDF numbers.
const _floatQuantum = 2e-5;

Future<pw.Font> _loadRegular() async =>
    pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));

/// A font subset bound to a throwaway in-memory document, for computing the
/// mathematically expected correction independently of any emission.
PdfFont _pdfFontOf(pw.Font font) {
  final pdfDocument = PdfDocument();
  final page = PdfPage(pdfDocument, pageFormat: PdfPageFormat.a4);
  final context = pw.Context(
    document: pdfDocument,
    page: page,
    canvas: page.getGraphics(),
  );
  return font.getFont(context);
}

/// Plain (uncompressed) content bytes for one word emission, so the test
/// parses the same operators a viewer executes. Compression is orthogonal:
/// streams deflate only when smaller, which would hide ASCII operators.
Future<String> _emit(pw.Widget Function(pw.Font font) build) async {
  final font = await _loadRegular();
  final document = pw.Document(compress: false);
  document.addPage(pw.Page(build: (context) => build(font)));
  return latin1.decode(await document.save(), allowInvalid: true);
}

/// Production placement shape: one word in a Positioned inside a Stack.
pw.Widget _positioned(pw.Widget child) => pw.Stack(
      fit: pw.StackFit.expand,
      overflow: pw.Overflow.visible,
      children: <pw.Widget>[
        pw.Positioned(left: 90, top: 50, child: child),
      ],
    );

/// The replaced production emission for one word.
pw.Widget _legacyWordText(
  pw.Font font,
  String word, {
  required bool rtl,
  required bool underline,
}) =>
    _positioned(
      pw.Text(
        word,
        style: pw.TextStyle(
          font: font,
          fontSize: 12,
          color: PdfColors.red,
          decoration:
              underline ? pw.TextDecoration.underline : pw.TextDecoration.none,
        ),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        textAlign: pw.TextAlign.left,
        softWrap: false,
        maxLines: 1,
        tightBounds: false,
        overflow: pw.TextOverflow.clip,
      ),
    );

pw.Widget _canonicalWordText(
  pw.Font font,
  String word, {
  required bool rtl,
  required bool underline,
  required double canonicalAdvance,
}) =>
    _positioned(
      CanonicalText(
        text: word,
        font: font,
        fontSizePt: 12,
        color: PdfColors.red,
        canonicalAdvancePt: canonicalAdvance,
        rtl: rtl,
        underline: underline,
      ),
    );

/// One parsed word emission: viewer-composed ink position, TJ bytes,
/// underline stroke, colors, and clip box.
class _WordEmission {
  _WordEmission({
    required this.x,
    required this.y,
    required this.hex,
    required this.tjNumber,
    required this.underline,
    required this.fillColor,
    required this.strokeColor,
    required this.lineWidth,
    required this.clip,
  });

  final double x;
  final double y;
  final String hex;
  final double? tjNumber;
  final List<double>? underline;
  final List<double>? fillColor;
  final List<double>? strokeColor;
  final double? lineWidth;
  final List<double>? clip;
}

List<double> _mul(List<double> m, List<double> v) => <double>[
      m[0] * v[0] + m[2] * v[1] + m[4],
      m[1] * v[0] + m[3] * v[1] + m[5],
    ];

List<double> _cat(List<double> a, List<double> b) => <double>[
      a[0] * b[0] + a[2] * b[1],
      a[1] * b[0] + a[3] * b[1],
      a[0] * b[2] + a[2] * b[3],
      a[1] * b[2] + a[3] * b[3],
      a[0] * b[4] + a[2] * b[5] + a[4],
      a[1] * b[4] + a[3] * b[5] + a[5],
    ];

/// Parses one single-word emission probe-style: tracks the q/Q/cm graphics
/// state, associates each TJ with its pending Td, and composes the ink
/// position exactly as a viewer does.
_WordEmission _parseWordEmission(String raw) {
  final token = RegExp(
    r'(?<a>-?[\d.]+)\s+(?<b>-?[\d.]+)\s+(?<c>-?[\d.]+)\s+'
    r'(?<d>-?[\d.]+)\s+(?<e>-?[\d.]+)\s+(?<f>-?[\d.]+)\s+cm'
    r'|(?<![A-Za-z0-9/])(?<save>[qQ])(?![A-Za-z0-9])'
    r'|(?<tdx>-?[\d.]+)\s+(?<tdy>-?[\d.]+)\s+Td'
    r'|\[<(?<hex>[0-9A-Fa-f]+)>(?:\s*(?<tj>-?[\d.]+))?\]TJ'
    r'|(?<r>-?[\d.]+)\s+(?<g>-?[\d.]+)\s+(?<bl>-?[\d.]+)\s+(?<rg>rg|RG)'
    r'|(?<w>-?[\d.]+)\s+w'
    r'|(?<x1>-?[\d.]+)\s+(?<y1>-?[\d.]+)\s+m\s+'
    r'(?<x2>-?[\d.]+)\s+(?<y2>-?[\d.]+)\s+l'
    r'|(?<cx>-?[\d.]+)\s+(?<cy>-?[\d.]+)\s+'
    r'(?<cw>-?[\d.]+)\s+(?<ch>-?[\d.]+)\s+re',
  );
  var ctm = <double>[1, 0, 0, 1, 0, 0];
  final stack = <List<double>>[];
  double? pendingX;
  double? pendingY;
  var x = double.nan;
  var y = double.nan;
  var hex = '';
  double? tjNumber;
  var tjCount = 0;
  List<double>? underline;
  List<double>? fillColor;
  List<double>? strokeColor;
  double? lineWidth;
  List<double>? clip;
  for (final match in token.allMatches(raw)) {
    if (match.namedGroup('a') != null) {
      ctm = _cat(ctm, <double>[
        double.parse(match.namedGroup('a')!),
        double.parse(match.namedGroup('b')!),
        double.parse(match.namedGroup('c')!),
        double.parse(match.namedGroup('d')!),
        double.parse(match.namedGroup('e')!),
        double.parse(match.namedGroup('f')!),
      ]);
      continue;
    }
    final save = match.namedGroup('save');
    if (save == 'q') {
      stack.add(ctm);
      continue;
    }
    if (save == 'Q') {
      if (stack.isNotEmpty) {
        ctm = stack.removeLast();
      }
      continue;
    }
    if (match.namedGroup('tdx') != null) {
      pendingX = double.parse(match.namedGroup('tdx')!);
      pendingY = double.parse(match.namedGroup('tdy')!);
      continue;
    }
    final foundHex = match.namedGroup('hex');
    if (foundHex != null) {
      tjCount++;
      final composed = _mul(ctm, <double>[pendingX!, pendingY!]);
      x = composed[0];
      y = composed[1];
      hex = foundHex;
      final number = match.namedGroup('tj');
      tjNumber = number == null ? null : double.parse(number);
      pendingX = null;
      pendingY = null;
      continue;
    }
    if (match.namedGroup('rg') != null) {
      final triple = <double>[
        double.parse(match.namedGroup('r')!),
        double.parse(match.namedGroup('g')!),
        double.parse(match.namedGroup('bl')!),
      ];
      if (match.namedGroup('rg') == 'rg') {
        fillColor = triple;
      } else {
        strokeColor = triple;
      }
      continue;
    }
    if (match.namedGroup('w') != null) {
      lineWidth = double.parse(match.namedGroup('w')!);
      continue;
    }
    if (match.namedGroup('x1') != null) {
      underline = <double>[
        double.parse(match.namedGroup('x1')!),
        double.parse(match.namedGroup('y1')!),
        double.parse(match.namedGroup('x2')!),
        double.parse(match.namedGroup('y2')!),
      ];
      continue;
    }
    if (match.namedGroup('cx') != null) {
      clip = <double>[
        double.parse(match.namedGroup('cx')!),
        double.parse(match.namedGroup('cy')!),
        double.parse(match.namedGroup('cw')!),
        double.parse(match.namedGroup('ch')!),
      ];
      continue;
    }
  }
  assert(tjCount == 1, 'expected one word TJ, found $tjCount');
  return _WordEmission(
    x: x,
    y: y,
    hex: hex,
    tjNumber: tjNumber,
    underline: underline,
    fillColor: fillColor,
    strokeColor: strokeColor,
    lineWidth: lineWidth,
    clip: clip,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trailing TJ closes the font advance onto canonical (RTL+LTR)',
      () async {
    for (final word in <String>['عِلْمًا', 'STA1']) {
      final rtl = word != 'STA1';
      final shaped = rtl ? logicalToVisual(word) : word;
      const canonicalAdvance = 10.0;
      final pdfFont = _pdfFontOf(await _loadRegular());
      final pdfAdvance =
          pdfFont.stringMetrics(shaped).advanceWidth * 12;
      final raw = await _emit(
        (font) => _canonicalWordText(
          font,
          word,
          rtl: rtl,
          underline: false,
          canonicalAdvance: canonicalAdvance,
        ),
      );
      final emission = _parseWordEmission(raw);
      expect(emission.tjNumber, isNotNull);
      expect(
        emission.tjNumber!,
        closeTo(
          (pdfAdvance - canonicalAdvance) * 1000 / 12,
          _floatQuantum,
        ),
      );
    }
  });

  test('degenerate corrections keep the historical TJ bytes', () async {
    // Exactly-zero correction: canonical equals the font advance.
    const word = 'عِلْمًا';
    final pdfFont = _pdfFontOf(await _loadRegular());
    final pdfAdvance =
        pdfFont.stringMetrics(logicalToVisual(word)).advanceWidth * 12;
    final raw = await _emit(
      (font) => _canonicalWordText(
        font,
        word,
        rtl: true,
        underline: false,
        canonicalAdvance: pdfAdvance,
      ),
    );
    expect(_parseWordEmission(raw).tjNumber, isNull);
    // Degenerate geometry: non-positive size or canonical advance.
    for (final params in <List<double>>[
      <double>[12, 0],
      <double>[12, -4],
      <double>[0, 10],
      <double>[-3, 10],
    ]) {
      final widget = CanonicalText(
        text: word,
        font: await _loadRegular(),
        fontSizePt: params[0],
        color: PdfColors.black,
        canonicalAdvancePt: params[1],
        rtl: true,
        underline: false,
      );
      expect(widget.trailingTjAdjustment(pdfFont), isNull);
    }
    // Empty emits no TJ at all; a blank whose canonical advance equals its
    // font advance takes the same exactly-zero rule (no correction number).
    final spaceAdvance =
        pdfFont.stringMetrics(' ').advanceWidth * 12;
    for (final blank in <String>['', ' ']) {
      final blankRaw = await _emit(
        (font) => _positioned(
          CanonicalText(
            text: blank,
            font: font,
            fontSizePt: 12,
            color: PdfColors.black,
            canonicalAdvancePt:
                blank.isEmpty ? 10 : spaceAdvance,
            rtl: true,
            underline: false,
          ),
        ),
      );
      expect(blankRaw.contains('TJ'), blank.isEmpty ? isFalse : isTrue,
          reason: 'blank=${blank.isEmpty}');
      if (blank.isNotEmpty) {
        expect(_parseWordEmission(blankRaw).tjNumber, isNull);
      }
    }
  });

  test('shaping dispatch mirrors pw.Text (RTL shaped, LTR raw)', () async {
    for (final entry in <MapEntry<String, bool>>[
      const MapEntry<String, bool>('عِلْمًا', true),
      const MapEntry<String, bool>('STA1', false),
    ]) {
      final raw = await _emit(
        (font) => _canonicalWordText(
          font,
          entry.key,
          rtl: entry.value,
          underline: false,
          canonicalAdvance: 10,
        ),
      );
      final emission = _parseWordEmission(raw);
      // The TJ hex decodes through the file's own ToUnicode map to the
      // shaped runes (presentation forms for RTL, raw ASCII for LTR).
      final unicodesByCid = <int, int>{
        for (final pair in RegExp(
                r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>')
            .allMatches(raw))
          int.parse(pair.group(1)!, radix: 16):
              int.parse(pair.group(2)!, radix: 16),
      };
      final decoded = <int>[
        for (var index = 0; index < emission.hex.length; index += 4)
          unicodesByCid[
              int.parse(emission.hex.substring(index, index + 4), radix: 16)]!,
      ];
      final expected =
          (entry.value ? logicalToVisual(entry.key) : entry.key).runes.toList();
      expect(decoded, expected);
    }
  });

  test('differential parity with pw.Text: viewer-composed ink, underline, '
      'color, clip; only the TJ number differs', () async {
    for (final rtl in <bool>[true, false]) {
      for (final underline in <bool>[true, false]) {
        final word = rtl ? 'عِلْمًا' : 'STA1';
        final shaped = rtl ? logicalToVisual(word) : word;
        const canonicalAdvance = 10.0;
        final pdfFont = _pdfFontOf(await _loadRegular());
        final pdfAdvance =
            pdfFont.stringMetrics(shaped).advanceWidth * 12;
        final legacy = await _emit(
          (font) => _legacyWordText(font, word,
              rtl: rtl, underline: underline),
        );
        final canonical = await _emit(
          (font) => _canonicalWordText(font, word,
              rtl: rtl,
              underline: underline,
              canonicalAdvance: canonicalAdvance),
        );
        final label = 'rtl=$rtl underline=$underline';
        final legacyOps = _parseWordEmission(legacy);
        final canonicalOps = _parseWordEmission(canonical);
        // Viewer-composed ink position: identical.
        expect(canonicalOps.x, closeTo(legacyOps.x, _floatQuantum),
            reason: 'ink x $label');
        expect(canonicalOps.y, closeTo(legacyOps.y, _floatQuantum),
            reason: 'ink y $label');
        // Same shaped bytes, same clip, same colors.
        expect(canonicalOps.hex, legacyOps.hex, reason: 'hex $label');
        expect(canonicalOps.clip, legacyOps.clip, reason: 'clip $label');
        expect(canonicalOps.fillColor, legacyOps.fillColor,
            reason: 'fill $label');
        expect(canonicalOps.strokeColor, legacyOps.strokeColor,
            reason: 'stroke $label');
        if (underline) {
          expect(canonicalOps.lineWidth,
              closeTo(legacyOps.lineWidth!, _floatQuantum),
              reason: 'width $label');
          for (var i = 0; i < 4; i++) {
            expect(canonicalOps.underline![i],
                closeTo(legacyOps.underline![i], _floatQuantum),
                reason: 'underline[$i] $label');
          }
        } else {
          expect(canonicalOps.underline, isNull, reason: 'no line $label');
          expect(legacyOps.underline, isNull, reason: 'no line $label');
        }
        // The ONLY intended delta: the trailing TJ correction number.
        expect(legacyOps.tjNumber, isNull, reason: 'legacy TJ $label');
        expect(
          canonicalOps.tjNumber,
          closeTo((pdfAdvance - canonicalAdvance) * 1000 / 12, _floatQuantum),
          reason: 'canonical TJ $label',
        );
        // Strong form: modulo that number, the content-stream bytes are
        // identical (same operators, order, and formatting; /Length and
        // xref offsets legitimately differ by the number's digits, so the
        // comparison is scoped to the page content stream itself).
        String contentStream(String file) => RegExp(
              // Object 4 (the page content) is the first stream in these
              // single-word files; non-greedy so font streams are excluded.
              r'>>stream\r?\n(.*?)\r?\nendstream',
              dotAll: true,
            ).firstMatch(file)!.group(1)!;
        final normalized = contentStream(canonical).replaceFirst(
          RegExp(r'\[<[0-9A-Fa-f]+>\s*-?[\d.]+\]TJ'),
          '[<${canonicalOps.hex}>]TJ',
        );
        expect(normalized, contentStream(legacy), reason: 'byte parity $label');
      }
    }
  });
}
