// CanonicalText emission primitive (Batch 2): per-word trailing-TJ math,
// degenerate old-behavior preservation, shaping-dispatch wiring, and
// differential parity with the replaced pw.Text path (positions, ink,
// underline, color). Float assertions through PDF bytes allow 1e-4: PdfNum
// prints 5 decimals, so parsed values carry quantization, not error.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';

const double _floatQuantum = 1e-4;

Future<pw.Font> _loadRegular() async =>
    pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));

Future<PdfFont> _loadPdfFont() async =>
    PdfTtfFont(PdfDocument(), await rootBundle.load(ExamFonts.regularAsset));

/// Expected TJ hex for a fresh single-word document: putText assigns CIDs in
/// first-seen rune order starting at zero.
String _expectedHex(String shaped) {
  final cids = <int, int>{};
  final buffer = StringBuffer();
  for (final rune in shaped.runes) {
    final cid = cids.putIfAbsent(rune, () => cids.length);
    buffer.write(cid.toRadixString(16).padLeft(4, '0'));
  }
  return buffer.toString();
}

/// Unicodes in CID order from the file's ToUnicode map (fresh single-word
/// document, so CIDs are 0..n-1).
List<int> _unicodesByCid(String raw) {
  final entries = <int, int>{};
  for (final match in RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>')
      .allMatches(raw)) {
    entries[int.parse(match.group(1)!, radix: 16)] =
        int.parse(match.group(2)!, radix: 16);
  }
  return <int>[
    for (var cid = 0; cid < entries.length; cid++) entries[cid]!,
  ];
}

Future<String> _emit(pw.Widget Function(pw.Font font) build) async {
  final font = await _loadRegular();
  final document = pw.Document();
  document.addPage(pw.Page(build: (context) => build(font)));
  return latin1.decode(await document.save(), allowInvalid: true);
}

pw.Widget _positioned(pw.Widget child) => pw.Stack(
      fit: pw.StackFit.expand,
      overflow: pw.Overflow.visible,
      children: <pw.Widget>[
        pw.Positioned(left: 90, top: 50, child: child),
      ],
    );

/// The replaced pw.Text configuration, replicated exactly for the
/// differential parity test.
pw.Widget _legacyWordText({
  required String text,
  required pw.Font font,
  required double fontSize,
  required PdfColor color,
  required bool rtl,
  required bool underline,
}) =>
    _positioned(
      pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          fontWeight: pw.FontWeight.normal,
          fontStyle: pw.FontStyle.normal,
          color: color,
          letterSpacing: 0,
          wordSpacing: 0,
          lineSpacing: 0,
          height: 1,
          decoration: underline
              ? pw.TextDecoration.underline
              : pw.TextDecoration.none,
        ),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        textAlign: pw.TextAlign.left,
        softWrap: false,
        maxLines: 1,
        tightBounds: false,
        overflow: pw.TextOverflow.clip,
      ),
    );

pw.Widget _canonicalWordText({
  required String text,
  required pw.Font font,
  required double fontSize,
  required PdfColor color,
  required bool rtl,
  required bool underline,
  required double canonicalAdvance,
}) =>
    _positioned(
      CanonicalText(
        text: text,
        font: font,
        fontSizePt: fontSize,
        color: color,
        canonicalAdvancePt: canonicalAdvance,
        rtl: rtl,
        underline: underline,
      ),
    );

List<double> _td(String raw) {
  final match = RegExp(r'(-?[\d.]+)\s+(-?[\d.]+)\s+Td').firstMatch(raw)!;
  return <double>[
    double.parse(match.group(1)!),
    double.parse(match.group(2)!),
  ];
}

RegExpMatch? _tj(String raw) =>
    RegExp(r'\[<([0-9A-Fa-f]+)>(?:\s*(-?[\d.]+))?\]TJ').firstMatch(raw);

List<double>? _line(String raw) {
  final match = RegExp(r'(-?[\d.]+)\s+(-?[\d.]+)\s+m\s+(-?[\d.]+)\s+(-?[\d.]+)\s+l')
      .firstMatch(raw);
  if (match == null) {
    return null;
  }
  return <double>[
    double.parse(match.group(1)!),
    double.parse(match.group(2)!),
    double.parse(match.group(3)!),
    double.parse(match.group(4)!),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trailing TJ closes the font advance onto canonical (RTL+LTR)',
      () async {
    final pdfFont = await _loadPdfFont();
    for (final word in <String>['عِلْمًا', 'STA1']) {
      final rtl = word == 'عِلْمًا';
      final shaped = rtl ? logicalToVisual(word) : word;
      final pdfAdvance = pdfFont.stringMetrics(shaped).advanceWidth * 12;
      const canonicalAdvance = 10.0;
      final raw = await _emit((font) => _canonicalWordText(
            text: word,
            font: font,
            fontSize: 12,
            color: PdfColors.black,
            rtl: rtl,
            underline: false,
            canonicalAdvance: canonicalAdvance,
          ));
      final tj = _tj(raw)!;
      expect(tj.group(1), _expectedHex(shaped));
      expect(
        double.parse(tj.group(2)!),
        closeTo((pdfAdvance - canonicalAdvance) * 1000 / 12, _floatQuantum),
      );
    }
  });

  test('degenerate corrections keep the historical TJ bytes', () async {
    final pdfFont = await _loadPdfFont();
    final pdfAdvance =
        pdfFont.stringMetrics(logicalToVisual('عِلْمًا')).advanceWidth * 12;
    // Exact-zero residual: canonical equals the font advance bit-for-bit.
    var raw = await _emit((font) => _canonicalWordText(
          text: 'عِلْمًا',
          font: font,
          fontSize: 12,
          color: PdfColors.black,
          rtl: true,
          underline: false,
          canonicalAdvance: pdfAdvance,
        ));
    expect(_tj(raw)!.group(2), isNull);
    // Degenerate geometry: non-positive size or canonical advance.
    for (final params in <List<double>>[
      <double>[12, 0],
      <double>[12, -3],
      <double>[0, 10],
    ]) {
      raw = await _emit((font) => _canonicalWordText(
            text: 'عِلْمًا',
            font: font,
            fontSize: params[0],
            color: PdfColors.black,
            rtl: true,
            underline: false,
            canonicalAdvance: params[1],
          ));
      expect(
        _tj(raw)!.group(2),
        isNull,
        reason: 'fontSize=${params[0]} canonical=${params[1]}',
      );
    }
    // Empty text emits no TJ at all, like pw.Text('').
    raw = await _emit((font) => _canonicalWordText(
          text: '',
          font: font,
          fontSize: 12,
          color: PdfColors.black,
          rtl: true,
          underline: false,
          canonicalAdvance: 10,
        ));
    expect(_tj(raw), isNull);
  });

  test('shaping dispatch mirrors pw.Text (RTL shaped, LTR raw)', () async {
    var raw = await _emit((font) => _canonicalWordText(
          text: 'عِلْمًا',
          font: font,
          fontSize: 12,
          color: PdfColors.black,
          rtl: true,
          underline: false,
          canonicalAdvance: 10,
        ));
    // CIDs are order-based, so the TJ hex cannot prove shaping; the
    // ToUnicode map carries the emitted codepoints instead.
    expect(_unicodesByCid(raw), logicalToVisual('عِلْمًا').runes.toList());
    expect(_unicodesByCid(raw), isNot('عِلْمًا'.runes.toList()));
    raw = await _emit((font) => _canonicalWordText(
          text: 'AB',
          font: font,
          fontSize: 12,
          color: PdfColors.black,
          rtl: false,
          underline: false,
          canonicalAdvance: 10,
        ));
    expect(_tj(raw)!.group(1), _expectedHex('AB'));
    expect(_unicodesByCid(raw), 'AB'.runes.toList());
  });

  test('differential parity with pw.Text: origin, ink, underline, color',
      () async {
    final pdfFont = await _loadPdfFont();
    for (final rtl in <bool>[true, false]) {
      final word = rtl ? 'عِلْمًا' : 'STA1';
      final shaped = rtl ? logicalToVisual(word) : word;
      final pdfAdvance = pdfFont.stringMetrics(shaped).advanceWidth * 12;
      for (final underline in <bool>[false, true]) {
        final legacy = await _emit((font) => _legacyWordText(
              text: word,
              font: font,
              fontSize: 12,
              color: PdfColors.red,
              rtl: rtl,
              underline: underline,
            ));
        final canonical = await _emit((font) => _canonicalWordText(
              text: word,
              font: font,
              fontSize: 12,
              color: PdfColors.red,
              rtl: rtl,
              underline: underline,
              canonicalAdvance: 10,
            ));
        final label = 'rtl=$rtl underline=$underline';
        final legacyTd = _td(legacy);
        final canonicalTd = _td(canonical);
        expect(canonicalTd[0], legacyTd[0], reason: 'Td x $label');
        expect(canonicalTd[1], legacyTd[1], reason: 'Td y $label');
        final legacyTj = _tj(legacy)!;
        final canonicalTj = _tj(canonical)!;
        expect(
          canonicalTj.group(1),
          legacyTj.group(1),
          reason: 'ink hex $label',
        );
        expect(legacyTj.group(2), isNull, reason: 'legacy TJ $label');
        expect(
          double.parse(canonicalTj.group(2)!),
          closeTo((pdfAdvance - 10) * 1000 / 12, _floatQuantum),
          reason: 'correction $label',
        );
        expect(_line(canonical), _line(legacy), reason: 'underline $label');
        expect(canonical.contains('1 0 0 rg'), isTrue, reason: 'fill $label');
        expect(legacy.contains('1 0 0 rg'), isTrue, reason: 'fill $label');
        if (underline) {
          expect(canonical.contains('1 0 0 RG'), isTrue,
              reason: 'stroke $label');
          expect(legacy.contains('1 0 0 RG'), isTrue, reason: 'stroke $label');
        }
      }
    }
  });
}
