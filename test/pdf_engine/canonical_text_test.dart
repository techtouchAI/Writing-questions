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

import 'pdf_content_probe.dart';

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

/// Plain (uncompressed) file bytes for one word emission, so the test
/// parses the same operators a viewer executes. Compression is orthogonal:
/// streams deflate only when smaller, which would hide ASCII operators
/// (the shared probe inflates; these focused tests read plain bytes).
Future<Uint8List> _emitBytes(pw.Widget Function(pw.Font font) build) async {
  final font = await _loadRegular();
  final document = pw.Document(compress: false);
  document.addPage(pw.Page(build: (context) => build(font)));
  return document.save();
}

Future<String> _emit(pw.Widget Function(pw.Font font) build) async =>
    latin1.decode(await _emitBytes(build), allowInvalid: true);

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
  bool italic = false,
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
        italic: italic,
      ),
    );

/// Every applied shear in one emission: `cm` operands whose linear part is a
/// pure horizontal shear (`a = d = 1`, `b = f = 0`, `c != 0`). Widget
/// translations share the operator but have `c == 0`, so they never appear.
List<List<double>> _shearMatrices(String raw) {
  final pattern = RegExp(
    r'(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+'
    r'(-?[\d.]+)\s+(-?[\d.]+)\s+cm',
  );
  return <List<double>>[
    for (final match in pattern.allMatches(raw))
      if ((double.parse(match.group(2)!) - 0).abs() < 1e-9 &&
          (double.parse(match.group(3)!) - 0).abs() > 1e-9)
        <double>[
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
          double.parse(match.group(4)!),
          double.parse(match.group(5)!),
          double.parse(match.group(6)!),
        ],
  ];
}

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

  group('clip covers the shaped word ink', _clipRegressionTests);

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
      // قناتان: الرسم مشكَّل، والاستخراج معجمي.
      //  * الشكل يُقاس على الشارح نفسه: كل محارف RTL صور عرض متصلة، وLTR خام.
      //  * `/ToUnicode` (ما يقرؤه البحث/النسخ) يُقاس من الملف: حروف أساسية
      //    بترتيب المجرى البصري، فيعطي عكسها الكلمة المنطقية.
      final run = shapeRtlRun(entry.key);
      final glyphRunes = entry.value ? run.glyphText.runes.toList() : entry.key.runes.toList();
      if (entry.value) {
        expect(
          glyphRunes.every((rune) => rune >= 0xFE70 && rune <= 0xFEFF),
          isTrue,
          reason: 'قناة الرسم يجب أن تكون صورًا تقديمية متصلة: $glyphRunes',
        );
      } else {
        expect(glyphRunes, entry.key.runes.toList(),
            reason: 'النصّ اللاتيني يجب ألا يُشكَّل ولا يُقلَب.');
      }
      final unicodeByCid = <int, String>{};
      for (final pair in RegExp(
        r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4}(?:\s+[0-9A-Fa-f]{4})*)>',
      ).allMatches(raw)) {
        final hex = pair.group(2)!.replaceAll(RegExp(r'\s+'), '');
        unicodeByCid[int.parse(pair.group(1)!, radix: 16)] =
            String.fromCharCodes(<int>[
          for (var index = 0; index + 4 <= hex.length; index += 4)
            int.parse(hex.substring(index, index + 4), radix: 16),
        ]);
      }
      final decoded = <int>[
        for (var index = 0; index < emission.hex.length; index += 4)
          ...unicodeByCid[
                  int.parse(emission.hex.substring(index, index + 4), radix: 16)]!
              .runes,
      ];
      final expected = entry.value
          ? entry.key.runes.toList().reversed.toList()
          : entry.key.runes.toList();
      expect(decoded, expected,
          reason: 'قناة الاستخراج يجب أن تحمل الحروف المعجمية بترتيب المجرى '
              '(عكسها = الكلمة المنطقية)، لا الأشكال المشكَّلة.');
      if (entry.value) {
        expect(
          decoded.every((rune) => !isArabicPresentationForm(rune)),
          isTrue,
          reason: 'شكل عرض بقي في /ToUnicode: $decoded',
        );
      }
    }
  });

  test('differential parity with pw.Text: viewer-composed ink, underline, '
      'color; only the TJ number and the widened clip differ', () async {
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
        // The canonical widget's own metrics, for the underline assertions:
        // the baseline sits `boxHeight - ascent` from the box's bottom edge
        // (this package's canvas is y-up, see CanonicalText.paint).
        final metrics = pdfFont.stringMetrics(shaped) * 12;
        final boxHeight = metrics.maxHeight;
        final inkY = boxHeight - metrics.ascent;
        // Viewer-composed ink position: identical.
        expect(canonicalOps.x, closeTo(legacyOps.x, _floatQuantum),
            reason: 'ink x $label');
        expect(canonicalOps.y, closeTo(legacyOps.y, _floatQuantum),
            reason: 'ink y $label');
        // Same shaped bytes, same colors. The clip is no longer identical:
        // it is now the legacy line box unioned with the shaped word's real
        // glyph ink, because that box truncated printed content (see the
        // dedicated clip tests below).
        expect(canonicalOps.hex, legacyOps.hex, reason: 'hex $label');
        expect(_clipContains(canonicalOps.clip!, legacyOps.clip!), isTrue,
            reason: 'clip still covers the legacy line box $label');
        expect(canonicalOps.fillColor, legacyOps.fillColor,
            reason: 'fill $label');
        expect(canonicalOps.strokeColor, legacyOps.strokeColor,
            reason: 'stroke $label');
        // The stroke width is the rule's thickness and follows the same
        // decision as the rule's position: the engine's `fontSize / 14`, not
        // the package's `0.05 em`. Both are asserted so neither can drift.
        expect(legacyOps.lineWidth, closeTo(12 * 0.05, _floatQuantum),
            reason: 'legacy width (package rule) $label');
        expect(canonicalOps.lineWidth,
            closeTo(CanonicalText.underlineThicknessPt(12), _floatQuantum),
            reason: 'canonical width (engine rule) $label');
        if (underline) {
          // The underline is the one place the canonical emission must NOT
          // copy the replaced path. The replaced path uses the package's own
          // rule (fontDescent / 2 below the baseline, thickness 0.05 em); the
          // Preview uses the engine's (`fontSize / 14`, positioned that far
          // below the baseline — see
          // [CanonicalText.underlineThicknessPt]), and the Preview is the
          // reference the printed page has to match. Both rules are asserted
          // here so that neither can drift silently.
          final thickness = CanonicalText.underlineThicknessPt(12);
          // The parsed y is the canvas's own coordinate. The package's rule,
          // term for term as the replaced `pw.Text` path computes it: the
          // line box's bottom plus the scaled descent, lowered by half the
          // font's own descent (`foregroundPaint`'s
          // `base = -descent * fontSize / 2`, in this package's y-up canvas).
          final legacyY = boxHeight -
              metrics.ascent +
              metrics.descent -
              pdfFont.descent * 12 / 2;
          expect(canonicalOps.underline![1],
              closeTo(inkY - thickness, _floatQuantum),
              reason: 'canonical underline y (engine rule) $label');
          expect(legacyOps.underline![1], closeTo(legacyY, _floatQuantum),
              reason: 'legacy underline y (package rule) $label');
          expect((legacyY - (inkY - thickness)).abs(),
              greaterThan(0.5 * thickness),
              reason: 'the two rules must actually differ, or this test '
                  'proves nothing $label');
          // Each rule must be horizontal (its end y equals its start y), and
          // the two must span the same width: only the height differs.
          expect(canonicalOps.underline![3],
              closeTo(canonicalOps.underline![1], _floatQuantum),
              reason: 'canonical rule is horizontal $label');
          expect(legacyOps.underline![3],
              closeTo(legacyOps.underline![1], _floatQuantum),
              reason: 'legacy rule is horizontal $label');
          for (final index in <int>[0, 2]) {
            expect(canonicalOps.underline![index],
                closeTo(legacyOps.underline![index], _floatQuantum),
                reason: 'underline[$index] $label');
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
        // There are now two intended deltas, so both are normalised and the
        // rest of the content stream must still match byte for byte: the
        // trailing TJ number, and the clip rectangle (the legacy line box
        // unioned with the word's ink extents). What the clip must contain is
        // pinned by the parsed assertions above and by the dedicated clip
        // tests; nothing else in the emission may drift.
        String withoutClip(String stream) => stream.replaceFirst(
              RegExp(r'-?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ re W n'),
              'CLIP re W n',
            );
        // Third intended delta: the underline's geometry, which follows the
        // engine's rule rather than the package's (asserted numerically
        // above). Its coordinates and stroke width are normalised here so the
        // rest of the stream still has to match byte for byte.
        String withoutUnderline(String stream) => stream
            .replaceFirst(
              RegExp(r'-?[\d.]+ -?[\d.]+ m -?[\d.]+ -?[\d.]+ l S'),
              'UNDERLINE m l S',
            )
            .replaceFirst(RegExp(r'-?[\d.]+ w'), 'W w');
        final normalized = withoutUnderline(withoutClip(contentStream(canonical)))
            .replaceFirst(
          RegExp(r'\[<[0-9A-Fa-f]+>\s*-?[\d.]+\]TJ'),
          '[<${canonicalOps.hex}>]TJ',
        );
        expect(normalized, withoutUnderline(withoutClip(contentStream(legacy))),
            reason: 'byte parity $label');
      }
    }
  });

  test('probe-measured advance lands on canonical (Batch 4 end-to-end)',
      () async {
    for (final word in <String>['عِلْمًا', 'STA1']) {
      final rtl = word != 'STA1';
      final shaped = rtl ? logicalToVisual(word) : word;
      const canonicalAdvance = 10.0;
      final bytes = await _emitBytes(
        (font) => _canonicalWordText(
          font,
          word,
          rtl: rtl,
          underline: false,
          canonicalAdvance: canonicalAdvance,
        ),
      );
      final probe = PdfContentProbe.fromBytes(bytes);
      expect(probe.words, hasLength(1));
      // The shared probe executes the trailing TJ number exactly as a
      // viewer does, so the measured advance is the canonical advance.
      expect(probe.words.single.advanceWidth,
          closeTo(canonicalAdvance, _floatQuantum));
      // Control: the same probe reads the uncorrected font advance from
      // the replaced emission (numberless TJ measures exactly as before).
      final legacyBytes = await _emitBytes(
        (font) => _legacyWordText(font, word, rtl: rtl, underline: false),
      );
      final pdfAdvance =
          _pdfFontOf(await _loadRegular()).stringMetrics(shaped).advanceWidth *
              12;
      expect(PdfContentProbe.fromBytes(legacyBytes).words.single.advanceWidth,
          closeTo(pdfAdvance, _floatQuantum));
    }
  });

  test('italic shears the emitted glyphs by Skia\'s synthetic oblique, '
      'about the ink origin, and upright text emits none', () async {
    final font = await _loadRegular();
    final pdfFont = _pdfFontOf(font);
    const word = 'STA1';
    const canonicalAdvance = 10.0;
    // Same quantities the emitter uses: the widget box height and the ink
    // origin are the shaped word's own metrics, so the shear must pivot on
    // exactly this y.
    final metrics = pdfFont.stringMetrics(word) * 12;
    final inkY = metrics.maxHeight - metrics.ascent;

    Future<_WordEmission> emit({required bool italic}) async =>
        _parseWordEmission(
          await _emit(
            (font) => _canonicalWordText(
              font,
              word,
              rtl: false,
              underline: false,
              canonicalAdvance: canonicalAdvance,
              italic: italic,
            ),
          ),
        );

    final uprightOps = await emit(italic: false);
    final italicOps = await emit(italic: true);
    final uprightRaw = await _emit(
      (font) => _canonicalWordText(font, word,
          rtl: false, underline: false, canonicalAdvance: canonicalAdvance),
    );
    final italicRaw = await _emit(
      (font) => _canonicalWordText(font, word,
          rtl: false,
          underline: false,
          canonicalAdvance: canonicalAdvance,
          italic: true),
    );

    // Upright runs are untouched: no shear operator at all.
    expect(_shearMatrices(uprightRaw), isEmpty,
        reason: 'upright emission must not shear');

    // Italic runs carry exactly one shear, with the synthetic oblique factor
    // and the compensating translation that keeps the ink origin fixed.
    final shears = _shearMatrices(italicRaw);
    expect(shears, hasLength(1), reason: 'exactly one shear per italic run');
    final shear = shears.single;
    const factor = CanonicalText.syntheticObliqueShear;
    expect(shear[0], closeTo(1, _floatQuantum), reason: 'a');
    expect(shear[1], closeTo(0, _floatQuantum), reason: 'b');
    expect(shear[2], closeTo(factor, _floatQuantum), reason: 'c');
    expect(shear[3], closeTo(1, _floatQuantum), reason: 'd');
    expect(shear[4], closeTo(-factor * inkY, _floatQuantum), reason: 'e');
    expect(shear[5], closeTo(0, _floatQuantum), reason: 'f');

    // Geometry as a viewer executes it: the ink origin is a fixed point, and a
    // point one point above the baseline moves right by the factor — the
    // direction the Preview slants (its ascenders lean towards the end of the
    // line). Everything that is not the shear is unchanged.
    double mapX(double x, double y) => shear[0] * x + shear[2] * y + shear[4];
    expect(mapX(0, inkY), closeTo(0, _floatQuantum),
        reason: 'the text origin must not move');
    expect(mapX(0, inkY + 1), closeTo(factor, _floatQuantum),
        reason: 'ascenders lean right by the oblique factor');
    expect(italicOps.x, closeTo(uprightOps.x, _floatQuantum),
        reason: 'viewer-composed ink x is the canonical origin');
    expect(italicOps.y, closeTo(uprightOps.y, _floatQuantum),
        reason: 'viewer-composed ink y is the canonical baseline');
    expect(italicOps.hex, uprightOps.hex, reason: 'same shaped glyphs');
    expect(italicOps.tjNumber, uprightOps.tjNumber, reason: 'same TJ number');
    expect(italicOps.clip, uprightOps.clip, reason: 'same clip box');
    expect(italicOps.underline, uprightOps.underline, reason: 'same underline');
    expect(italicOps.fillColor, uprightOps.fillColor, reason: 'same fill');
    expect(italicOps.strokeColor, uprightOps.strokeColor, reason: 'same stroke');
    expect(italicOps.lineWidth, uprightOps.lineWidth, reason: 'same width');
  });
}

/// True when the rectangle [outer] contains [inner] (both `x, y, w, h`).
bool _clipContains(List<double> outer, List<double> inner) {
  final outerLeft = outer[0];
  final outerTop = outer[1];
  final outerRight = outerLeft + outer[2];
  final outerBottom = outerTop + outer[3];
  final innerLeft = inner[0];
  final innerTop = inner[1];
  final innerRight = innerLeft + inner[2];
  final innerBottom = innerTop + inner[3];
  return outerLeft <= innerLeft + _floatQuantum &&
      outerTop <= innerTop + _floatQuantum &&
      outerRight >= innerRight - _floatQuantum &&
      outerBottom >= innerBottom - _floatQuantum;
}

/// The clip must contain the shaped word's real ink, not just the `hhea` line
/// box. This is the regression guard for the content the PDF used to truncate:
/// `PdfFontMetrics.maxHeight` is `hhea` ascent-descent, and the fixture fonts
/// reach past it (Noto Naskh ascent 1.069 em against glyphs at 1.405 em,
/// Tajawal 0.643 em against glyphs at 0.803 em), so the legacy clip cut the top
/// of hamzas, maddas, harakat and of letters such as ث — ink the preview
/// paints and the printed page did not.
void _clipRegressionTests() {
  test('the clip contains the shaped word ink, not only the hhea line box',
      () async {
    final font = await _loadRegular();
    final pdfFont = _pdfFontOf(font);
    const fontSizePt = 12.0;
    for (final word in <String>['عِلْمًا', 'ثَابِت', 'إِنَّا', 'STA1']) {
      final relevantRtl = word != 'STA1';
      final shaped = relevantRtl ? logicalToVisual(word) : word;
      final metrics = pdfFont.stringMetrics(shaped) * fontSizePt;
      final emission = _parseWordEmission(
        await _emit(
          (font) => _canonicalWordText(
            font,
            word,
            rtl: relevantRtl,
            underline: false,
            canonicalAdvance: metrics.advanceWidth,
          ),
        ),
      );
      final clip = emission.clip!;
      final clipLeft = clip[0];
      final clipTop = clip[1];
      final clipRight = clipLeft + clip[2];
      final clipBottom = clipTop + clip[3];
      // Glyph outlines are y-up from the baseline; the box measures y-down
      // from its top, and the emitted baseline sits `maxHeight - ascent`
      // below that top.
      final baseline = metrics.maxHeight - metrics.ascent;
      final inkTop = baseline - metrics.bottom;
      final inkBottom = baseline - metrics.top;
      final inkLeft = metrics.left;
      final inkRight = metrics.right;
      // Sanity: this word really does overflow the legacy line box, so the
      // test would be vacuous otherwise.
      expect(inkTop < 0 || inkRight > metrics.advanceWidth + _floatQuantum,
          isTrue,
          reason: 'fixture word "$word" must overflow the line box '
              '(inkTop $inkTop, advance ${metrics.advanceWidth}, '
              'inkRight $inkRight)');
      expect(clipTop, lessThanOrEqualTo(inkTop + _floatQuantum),
          reason: 'clip top covers the ink of "$word" ($clipTop vs $inkTop)');
      expect(clipBottom, greaterThanOrEqualTo(inkBottom - _floatQuantum),
          reason: 'clip bottom covers the ink of "$word" '
              '($clipBottom vs $inkBottom)');
      expect(clipLeft, lessThanOrEqualTo(inkLeft + _floatQuantum),
          reason: 'clip left covers the ink of "$word" ($clipLeft vs $inkLeft)');
      expect(clipRight, greaterThanOrEqualTo(inkRight - _floatQuantum),
          reason: 'clip right covers the ink of "$word" '
              '($clipRight vs $inkRight)');
    }
  });

}
