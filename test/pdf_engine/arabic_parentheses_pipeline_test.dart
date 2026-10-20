import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/font_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/pdf_math_rasters.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

const String _samplesDir = 'build/issue1_issue2_samples';

class _EmbeddedPdfFontGlyphs {
  const _EmbeddedPdfFontGlyphs({
    required this.parser,
    required this.cidToUnicode,
  });

  final TtfParser parser;
  final Map<int, int> cidToUnicode;
}

class _EmittedGlyphToken {
  const _EmittedGlyphToken({
    required this.fontKey,
    required this.x,
    required this.y,
    required this.cids,
    required this.unicodeText,
  });

  final String fontKey;
  final double x;
  final double y;
  final List<int> cids;
  final String unicodeText;
}

class _ParsedVectorPageGlyphs {
  const _ParsedVectorPageGlyphs({
    required this.fonts,
    required this.tokens,
  });

  final Map<String, _EmbeddedPdfFontGlyphs> fonts;
  final List<_EmittedGlyphToken> tokens;
}

/// Extracts real embedded `/FontFile2` TrueType subfonts (`glyf`/`loca`) and
/// emitted `[<HEX>]TJ` operators from compressed or uncompressed PDF bytes so
/// tests verify actual vector glyph outline bytes alongside `/ToUnicode`.
_ParsedVectorPageGlyphs _inspectVectorPdfGlyphOutlines(Uint8List pdfBytes) {
  final raw = latin1.decode(pdfBytes, allowInvalid: true);
  final objHeader = RegExp(r'(\d+)\s+\d+\s+obj\b');
  final objDicts = <int, String>{};
  final objStreams = <int, Uint8List>{};

  final matches = objHeader.allMatches(raw).toList(growable: false);
  for (var i = 0; i < matches.length; i++) {
    final id = int.parse(matches[i].group(1)!);
    final bodyStart = matches[i].end;
    final bodyEnd = i + 1 < matches.length ? matches[i + 1].start : raw.length;
    final slice = raw.substring(bodyStart, bodyEnd);
    final streamIdx = slice.indexOf('stream');
    final endStreamIdx = slice.lastIndexOf('endstream');
    if (streamIdx == -1 || endStreamIdx == -1 || endStreamIdx <= streamIdx) {
      objDicts[id] = slice;
      continue;
    }
    final dictPart = slice.substring(0, streamIdx);
    objDicts[id] = dictPart;
    var dataStart = bodyStart + streamIdx + 'stream'.length;
    if (dataStart < pdfBytes.length && pdfBytes[dataStart] == 0x0D) {
      dataStart++;
    }
    if (dataStart < pdfBytes.length && pdfBytes[dataStart] == 0x0A) {
      dataStart++;
    }
    var dataEnd = bodyStart + endStreamIdx;
    while (dataEnd > dataStart &&
        (pdfBytes[dataEnd - 1] == 0x0A || pdfBytes[dataEnd - 1] == 0x0D)) {
      dataEnd--;
    }
    final rawStream = Uint8List.sublistView(pdfBytes, dataStart, dataEnd);
    if (dictPart.contains('/FlateDecode')) {
      try {
        objStreams[id] = Uint8List.fromList(zlib.decode(rawStream));
      } catch (_) {
        objStreams[id] = rawStream;
      }
    } else {
      objStreams[id] = rawStream;
    }
  }

  final fonts = <String, _EmbeddedPdfFontGlyphs>{};
  for (final entry in objDicts.entries) {
    final dict = entry.value;
    if (!dict.contains('/Subtype /Type0') && !dict.contains('/Subtype/Type0')) {
      continue;
    }
    final nameMatch = RegExp(r'/Name\s*/([A-Za-z0-9]+)').firstMatch(dict);
    final toUniMatch = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(dict);
    final fontFileMatch =
        RegExp(r'/FontFile2\s+(\d+)\s+0\s+R').firstMatch(dict);
    if (nameMatch == null || toUniMatch == null || fontFileMatch == null) {
      continue;
    }
    final fontKey = '/${nameMatch.group(1)!}';
    final toUniBytes = objStreams[int.parse(toUniMatch.group(1)!)];
    final fontFileBytes = objStreams[int.parse(fontFileMatch.group(1)!)];
    if (toUniBytes == null || fontFileBytes == null) continue;

    final cmapText = latin1.decode(toUniBytes, allowInvalid: true);
    final cidToUnicode = <int, int>{
      for (final m in RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>')
          .allMatches(cmapText))
        int.parse(m.group(1)!, radix: 16): int.parse(m.group(2)!, radix: 16),
    };
    final alignedCopy = Uint8List.fromList(fontFileBytes);
    fonts[fontKey] = _EmbeddedPdfFontGlyphs(
      parser: TtfParser(ByteData.sublistView(alignedCopy)),
      cidToUnicode: cidToUnicode,
    );
  }

  // Parse first page content stream (`/Type /Page\b`, not `/Type /Pages`).
  Uint8List? contentBytes;
  final singlePageType = RegExp(r'/Type\s*/Page\b');
  for (final entry in objDicts.entries) {
    if (singlePageType.hasMatch(entry.value)) {
      final contentsRef =
          RegExp(r'/Contents\s+(\d+)\s+0\s+R').firstMatch(entry.value);
      if (contentsRef != null) {
        contentBytes = objStreams[int.parse(contentsRef.group(1)!)];
        if (contentBytes != null) break;
      }
    }
  }
  final content =
      contentBytes == null ? '' : latin1.decode(contentBytes, allowInvalid: true);

  final opPattern = RegExp(
    r'/(?<font>F\d+)\s+(?<size>-?[\d.]+)\s+Tf'
    r'|(?<a>-?[\d.]+)\s+(?<b>-?[\d.]+)\s+(?<c>-?[\d.]+)\s+'
    r'(?<d>-?[\d.]+)\s+(?<e>-?[\d.]+)\s+(?<f>-?[\d.]+)\s+cm'
    r'|(?<![A-Za-z0-9/])(?<save>[qQ])(?![A-Za-z0-9])'
    r'|(?<tdx>-?[\d.]+)\s+(?<tdy>-?[\d.]+)\s+Td'
    r'|\[<(?<hex>[0-9A-Fa-f]+)>(?:\s*-?[\d.]+)?\]TJ',
  );

  List<double> cat(List<double> a, List<double> b) => <double>[
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
      ];

  var ctm = <double>[1, 0, 0, 1, 0, 0];
  final stack = <List<double>>[];
  var activeFont = '';
  double? px;
  double? py;
  final tokens = <_EmittedGlyphToken>[];

  for (final m in opPattern.allMatches(content)) {
    if (m.namedGroup('font') != null) {
      activeFont = '/${m.namedGroup('font')!}';
      continue;
    }
    if (m.namedGroup('a') != null) {
      ctm = cat(ctm, <double>[
        double.parse(m.namedGroup('a')!),
        double.parse(m.namedGroup('b')!),
        double.parse(m.namedGroup('c')!),
        double.parse(m.namedGroup('d')!),
        double.parse(m.namedGroup('e')!),
        double.parse(m.namedGroup('f')!),
      ]);
      continue;
    }
    final save = m.namedGroup('save');
    if (save == 'q') {
      stack.add(ctm);
      continue;
    }
    if (save == 'Q') {
      if (stack.isNotEmpty) ctm = stack.removeLast();
      continue;
    }
    if (m.namedGroup('tdx') != null) {
      px = double.parse(m.namedGroup('tdx')!);
      py = double.parse(m.namedGroup('tdy')!);
      continue;
    }
    final hex = m.namedGroup('hex');
    if (hex != null && px != null && py != null) {
      final cids = <int>[
        for (var i = 0; i + 4 <= hex.length; i += 4)
          int.parse(hex.substring(i, i + 4), radix: 16),
      ];
      final fontData = fonts[activeFont];
      final decoded = fontData == null
          ? ''
          : String.fromCharCodes(
              cids.map((cid) => fontData.cidToUnicode[cid] ?? 0xFFFD),
            );
      tokens.add(
        _EmittedGlyphToken(
          fontKey: activeFont,
          x: ctm[0] * px + ctm[2] * py + ctm[4],
          y: ctm[1] * px + ctm[3] * py + ctm[5],
          cids: cids,
          unicodeText: decoded,
        ),
      );
      px = null;
      py = null;
    }
  }
  return _ParsedVectorPageGlyphs(fonts: fonts, tokens: tokens);
}

/// Measures whether rendered Skia RGBA ink inside [rectPx] curves open to the
/// right (`(` shape -> center apex sits LEFT of top/bottom tips, returning `< 0`)
/// or open to the left (`)` shape -> center apex sits RIGHT of top/bottom tips,
/// returning `> 0`).
double _measureBracketCurvatureDeltaPx(
  ByteData rgba,
  int imageWidth,
  int imageHeight,
  Rect rectPx,
) {
  final left = (rectPx.left.floor() - 2).clamp(0, imageWidth - 1);
  final right = (rectPx.right.ceil() + 2).clamp(0, imageWidth - 1);
  final top = (rectPx.top.floor() - 2).clamp(0, imageHeight - 1);
  final bottom = (rectPx.bottom.ceil() + 2).clamp(0, imageHeight - 1);

  final rowMeanX = <int, double>{};
  for (var y = top; y <= bottom; y++) {
    var weightedX = 0.0;
    var weightSum = 0.0;
    for (var x = left; x <= right; x++) {
      final base = (y * imageWidth + x) * 4;
      final r = rgba.getUint8(base);
      final g = rgba.getUint8(base + 1);
      final b = rgba.getUint8(base + 2);
      final darkness = (255.0 - (r + g + b) / 3.0).clamp(0.0, 255.0);
      if (darkness > 24.0) {
        weightedX += x * darkness;
        weightSum += darkness;
      }
    }
    if (weightSum > 0) {
      rowMeanX[y] = weightedX / weightSum;
    }
  }
  expect(rowMeanX.length, greaterThanOrEqualTo(6),
      reason: 'Expected visible glyph ink inside $rectPx');

  final ys = rowMeanX.keys.toList()..sort();
  final n = ys.length;
  final tipRows = <int>[
    ...ys.take((n * 0.22).ceil().clamp(1, n)),
    ...ys.skip((n * 0.78).floor().clamp(0, n - 1)),
  ];
  final midStart = (n * 0.38).floor();
  final midEnd = (n * 0.62).ceil().clamp(midStart + 1, n);
  final midRows = ys.sublist(midStart, midEnd);

  final meanMidX =
      midRows.map((y) => rowMeanX[y]!).reduce((a, b) => a + b) / midRows.length;
  final meanTipX =
      tipRows.map((y) => rowMeanX[y]!).reduce((a, b) => a + b) / tipRows.length;
  return meanMidX - meanTipX;
}

PdfMathRasters _sharedMathRasters(
  LayoutDocument layout,
  CanonicalLayoutPreviewAssets assets,
) {
  final cache = <String, MathRaster>{};
  for (final line in layout.allLines) {
    for (final run in line.runs) {
      final raster = assets.mathRasters[run.id];
      if (raster == null) continue;
      final key = PdfMathRasters.cacheKey(
        run.text,
        run.style.fontSizePt,
        display: false,
      );
      cache.putIfAbsent(key, () => raster);
    }
  }
  return PdfMathRasters.fromCache(cache);
}

bool _containsHiddenBidiControls(String text) => text.runes.any(
      (r) =>
          r == 0x200E ||
          r == 0x200F ||
          (r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 1 — Arabic Parentheses Pipeline (Storage -> Metrics -> Preview -> PDF -> DOCX)', () {
    test(
        'proves pre-fix bug vs single-pass UAX #9 Rule L4 fix without leaked BiDi controls',
        () {
      // 1. Pre-fix bug proof: isolated ')' / '(' passed to auto-level
      //    `logicalToVisual` resolves at LTR embedding level 0 and FAILS to mirror!
      expect(logicalToVisual(')'), ')');
      expect(logicalToVisual('('), '(');

      // 2. Post-fix proof: `shapeRtlRun` runs UAX #9 once at RTL paragraph
      //    embedding level 1, mirroring glyph outlines while keeping exact
      //    logical code points in `/ToUnicode` and stripping all control marks.
      final closingRtl = shapeRtlRun(')');
      expect(closingRtl.glyphText, '(');
      expect(closingRtl.toUnicodeText, ')');
      expect(_containsHiddenBidiControls(closingRtl.glyphText), isFalse);
      expect(_containsHiddenBidiControls(closingRtl.toUnicodeText), isFalse);

      final openingRtl = shapeRtlRun('(');
      expect(openingRtl.glyphText, ')');
      expect(openingRtl.toUnicodeText, '(');

      // 3. Single-pass guarantee: tokens that ALREADY contain Arabic letters
      //    plus a bracket (e.g. `'أولاً)'` or `'((أ))'`) are mirrored ONCE —
      //    never double-mirrored back to broken direction!
      final attached = shapeRtlRun('أ)');
      expect(attached.glyphText.codeUnitAt(0), 0x0028,
          reason: 'Leftmost visual glyph of "أ)" must be parenleft "("');
      expect(attached.toUnicodeText.codeUnitAt(0), 0x0029,
          reason: 'ToUnicode at that CID must stay logical ")"');

      final nested = shapeRtlRun('((أ))');
      expect(nested.glyphText.codeUnitAt(0), 0x0028);
      expect(nested.glyphText.codeUnitAt(1), 0x0028);
      expect(
        nested.glyphText.codeUnitAt(nested.glyphText.length - 1),
        0x0029,
      );
      expect(
        nested.glyphText.codeUnitAt(nested.glyphText.length - 2),
        0x0029,
      );
      expect(nested.toUnicodeText.codeUnitAt(0), 0x0029);
      expect(
        nested.toUnicodeText.codeUnitAt(nested.toUnicodeText.length - 1),
        0x0028,
      );
    });

    testWidgets(
        'ASCII digits + brackets ("1 )", "1 (", "(1)") stay RTL in auto-direction blocks matching Editor, while Latin stays LTR',
        (_) async {
      await loadAppFonts();
      const metrics = FlutterTextMetrics();
      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.3,
      );

      for (final rtlNumericCase in <String>['1 )', '1 (', '(1)']) {
        final measured = metrics.layoutParagraph(
          spans: <MetricSpan>[
            MetricSpan(
              semanticNodeId: 'num-bracket',
              semanticNode: null,
              text: rtlNumericCase,
              contentKind: LayoutContentKind.text,
              semanticRole: LayoutSemanticRole.text,
              style: style,
              direction: DocumentDirection.auto,
              logicalIndex: 0,
            ),
          ],
          width: 300,
          direction: DocumentDirection.rtl,
          alignment: PaperAlign.start,
          resolveJustification: false,
        );
        final line = measured.lines.single;
        final words = line.fragments.expand((f) => f.words).toList();
        if (rtlNumericCase == '1 )' || rtlNumericCase == '1 (') {
          final digitWord = words.firstWhere((w) => w.text == '1');
          final bracketWord =
              words.firstWhere((w) => w.text == ')' || w.text == '(');
          expect(digitWord.x, greaterThan(bracketWord.x),
              reason:
                  'In an RTL exam block, "$rtlNumericCase" must place "1" to the right of the bracket just like the RTL Editor!');
        }
      }

      // Pure English line with parentheses must still resolve as LTR!
      final englishMeasured = metrics.layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'eng-bracket',
            semanticNode: null,
            text: 'Solve (x + 1) = 5',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 0,
          ),
        ],
        width: 300,
        direction: DocumentDirection.rtl,
        alignment: PaperAlign.start,
        resolveJustification: false,
      );
      final engFrags = englishMeasured.lines.single.fragments;
      expect(engFrags.every((f) => f.direction == DocumentDirection.ltr), isTrue,
          reason: 'Pure English text must remain LTR without flipping brackets');
    });

    testWidgets(
        'End-to-end Editor/Storage -> Skia Preview pixels -> Vector PDF glyf contours & ToUnicode -> Exact PDF/DOCX across all bracket cases',
        (tester) async {
      await loadAppFonts();
      final sourceFontData = await rootBundle.load(ExamFonts.regularAsset);
      final sourceParser = TtfParser(sourceFontData);
      final expectedParenLeftOutline =
          sourceParser.readGlyph(sourceParser.charToGlyphIndexMap[0x0028]!).data;
      final expectedParenRightOutline =
          sourceParser.readGlyph(sourceParser.charToGlyphIndexMap[0x0029]!).data;
      expect(expectedParenLeftOutline, isNot(equals(expectedParenRightOutline)),
          reason: 'Sanity check: "(" and ")" contours in NotoNaskh differ');

      // Build comprehensive document with EVERY required case (plus compound math!).
      final originalDoc = ExamDocument(
        id: 'arabic-parens-e2e',
        name: 'اختبار شامل للأقواس والمعادلات المركبة',
        header: const ExamHeaderModel(
          schoolName: 'ثانوية المتفوقين (للبنين)',
          examType: 'اختبار (الفصل الأول)',
          academicYear: '2026 / 2027',
          subject: 'الرياضيات (العامة)',
          grade: 'الثالث المتوسط (أ)',
          time: 'ساعتان (120 دقيقة)',
        ),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'q-parens',
            questionNumber: 1,
            statement: 'أجب عن الفروع الآتية (جميعها) بدقة:',
            marksOverride: 20,
            items: <BranchItem>[
              BranchItem(id: 'case-close', labelOverride: '', text: 'أ )'),
              BranchItem(id: 'case-open', labelOverride: '', text: 'أ ('),
              BranchItem(
                id: 'case-sentence',
                text: 'اختر (الإجابة الصحيحة) مما يأتي ثم وضّح السبب.',
              ),
              BranchItem(
                id: 'case-digits',
                text: 'الفرع (١) يعادل (20 درجة) والترقيم 1 ) واضح.',
              ),
              BranchItem(
                id: 'case-english',
                text: 'مصطلح (Photosynthesis) مهم في مادة (Biology 101).',
              ),
              BranchItem(
                id: 'case-math',
                text: r'جد ناتج ($\sqrt{5}+\sqrt{8}=$) وكذلك ($5^{2}+6^{2}=$).',
              ),
              BranchItem(
                id: 'case-nested',
                text: 'القيمة النهائية للرمز ((أ)) تساوي ((١٠)).',
              ),
              BranchItem(
                id: 'case-pure-ltr',
                labelOverride: '',
                text: 'Solve (x + 1) = (2x - 3)',
              ),
            ],
            branches: <BranchModel>[
              BranchModel(
                id: 'b1',
                statement: 'اختر الجواب الصحيح من بين الأقواس:',
                items: <BranchItem>[
                  BranchItem(
                    id: 'mcq-1',
                    kind: PointKind.multipleChoice,
                    text: 'قيمة الجذر التربيعي في العبارة (أ):',
                    marks: 5,
                    options: <QuestionOption>[
                      QuestionOption(id: 'o1', text: 'خمسة (5)'),
                      QuestionOption(id: 'o2', text: 'ستة (6)'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      // 1. Storage save + reopen JSON round-trip check:
      //    Exact logical order preserved byte-for-byte, zero hidden controls.
      final encodedJson = jsonEncode(originalDoc.toJson());
      expect(_containsHiddenBidiControls(encodedJson), isFalse);
      final reopenedDoc = ExamDocument.fromJson(
        jsonDecode(encodedJson) as Map<String, dynamic>,
      );
      expect(reopenedDoc.questions.single.items[0].text, 'أ )');
      expect(reopenedDoc.questions.single.items[1].text, 'أ (');
      expect(
        reopenedDoc.questions.single.items[5].text,
        r'جد ناتج ($\sqrt{5}+\sqrt{8}=$) وكذلك ($5^{2}+6^{2}=$).',
      );
      expect(
        reopenedDoc.questions.single.items[6].text,
        'القيمة النهائية للرمز ((أ)) تساوي ((١٠)).',
      );

      // 2. Render through full Canonical Preview + MathSnapshotHost!
      final controller = ExamWizardController(document: reopenedDoc);
      addTearDown(controller.dispose);
      final settled = Completer<void>();

      tester.view.physicalSize = const Size(1600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MathSnapshotHost(child: child),
          home: ChangeNotifierProvider<ExamWizardController>.value(
            value: controller,
            child: ExamPreviewScreen(
              onBackToQuestions: () {},
              canonicalLayoutResolver: ({
                required document,
                required sourceIr,
              }) async =>
                  CanonicalLayoutService.resolve(
                document: document,
                sourceIr: sourceIr,
              ),
              canonicalPreviewAssetLoader: ({
                required layout,
                required document,
              }) async {
                try {
                  return await CanonicalLayoutPreviewAssets.load(
                    layout: layout,
                    document: document,
                  );
                } finally {
                  if (!settled.isCompleted) settled.complete();
                }
              },
            ),
          ),
        ),
      );

      for (var i = 0; i < 400 && !settled.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() async {
          await Future<void>(() {});
        });
      }
      expect(settled.isCompleted, isTrue);
      await tester.pump();

      final previewWidgets =
          find.byType(CanonicalLayoutPreviewPage).evaluate().toList();
      expect(previewWidgets, isNotEmpty);
      final firstPreviewWidget =
          previewWidgets.first.widget as CanonicalLayoutPreviewPage;
      final layout = firstPreviewWidget.layoutDocument;

      final viewHeight =
          (ExamCanvasGeometry.height + 32) * layout.pageCount + 500;
      tester.view.physicalSize = Size(1600, viewHeight);
      await tester.pumpAndSettle();

      final refW = LayoutUnits.ptToPx(layout.pages.first.pageSize.width);
      final refH = LayoutUnits.ptToPx(layout.pages.first.pageSize.height);
      final boundaries = tester
          .renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))
          .where((b) =>
              (b.size.width - refW).abs() < 0.2 &&
              (b.size.height - refH).abs() < 0.2)
          .toList(growable: false);
      expect(boundaries, hasLength(layout.pageCount));

      // Capture raw RGBA + PNG snapshots from actual Skia Preview pages!
      late List<PageSnapshot> snapshots;
      late ByteData page1Rgba;
      late int page1W;
      late int page1H;
      await tester.runAsync(() async {
        final built = <PageSnapshot>[];
        for (var idx = 0; idx < boundaries.length; idx++) {
          final img = await boundaries[idx].toImage(pixelRatio: 1.0);
          if (idx == 0) {
            page1W = img.width;
            page1H = img.height;
            page1Rgba =
                (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          }
          final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          img.dispose();
          built.add(
            PageSnapshot(
              pageIndex: idx,
              pngBytes: png.buffer.asUint8List(),
              widthPx: refW,
              heightPx: refH,
            ),
          );
        }
        snapshots = built;
      });

      // 3. Verify ACTUAL SKIA PIXEL CURVATURE of `أ )` vs `أ (` on Page 1!
      final page1 = layout.pages.first;
      LayoutLine? closeLine;
      LayoutLine? openLine;
      LayoutLine? pureLtrLine;
      for (final block in page1.blocks) {
        for (final line in block.lines) {
          final joined = line.runs.map((r) => r.text).join().trim();
          if (joined == 'أ )') closeLine = line;
          if (joined == 'أ (') openLine = line;
          if (joined.contains('Solve (x + 1)')) pureLtrLine = line;
        }
      }
      expect(closeLine, isNotNull, reason: 'Line "أ )" must exist on page 1');
      expect(openLine, isNotNull, reason: 'Line "أ (" must exist on page 1');
      expect(pureLtrLine, isNotNull,
          reason: 'Line "Solve (x + 1) = (2x - 3)" must exist on page 1');

      Rect bracketPixelRect(LayoutLine line, String ch) {
        final run = line.runs.firstWhere((r) => r.text.trim() == ch);
        return Rect.fromLTWH(
          LayoutUnits.ptToPx(run.x),
          LayoutUnits.ptToPx(line.top),
          LayoutUnits.ptToPx(run.width),
          LayoutUnits.ptToPx(line.height),
        );
      }

      final closeCurvature = _measureBracketCurvatureDeltaPx(
        page1Rgba,
        page1W,
        page1H,
        bracketPixelRect(closeLine!, ')'),
      );
      final openCurvature = _measureBracketCurvatureDeltaPx(
        page1Rgba,
        page1W,
        page1H,
        bracketPixelRect(openLine!, '('),
      );
      // `أ )` visually draws `(` on the left of `أ` (mid apex strictly LEFT of tips -> < 0)!
      // `أ (` visually draws `)` on the left of `أ` (mid apex strictly RIGHT of tips -> > 0)!
      expect(closeCurvature, lessThan(-0.35),
          reason:
              'Preview pixels of "أ )" must curve open to the right toward "أ" (measured delta=$closeCurvature)');
      expect(openCurvature, greaterThan(0.35),
          reason:
              'Preview pixels of "أ (" must curve open to the left away from "أ" (measured delta=$openCurvature)');

      // 4. Generate Vector PDF, Exact PDF, and Exact DOCX and verify ACTUAL
      //    embedded `/FontFile2` `glyf` contours + `/ToUnicode` + OOXML!
      Uint8List? vectorPdf;
      Uint8List? exactPdf;
      Uint8List? exactDocx;
      var exportsDone = false;
      Object? exportErr;
      StackTrace? exportSt;
      final sharedMath = _sharedMathRasters(layout, firstPreviewWidget.assets);

      unawaited(
        Future<void>(() async {
          try {
            vectorPdf = await PdfExportService.buildDocumentPdfBytes(
              document: controller.document,
              layoutDocument: layout,
              mathRasters: sharedMath,
            );
            exactPdf = await ExactExportService.buildPdfFromSnapshots(snapshots);
            exactDocx = ExactExportService.buildDocxFromSnapshots(snapshots);
            exportsDone = true;
          } catch (e, s) {
            exportErr = e;
            exportSt = s;
          }
        }),
      );
      for (var i = 0; i < 800 && !exportsDone && exportErr == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (exportErr != null) {
        Error.throwWithStackTrace(exportErr!, exportSt!);
      }
      expect(exportsDone, isTrue);

      final inspected = _inspectVectorPdfGlyphOutlines(vectorPdf!);
      expect(inspected.fonts, isNotEmpty);

      // Find emitted PDF tokens at the exact canonical x positions of:
      //  - RTL `أ )`: bracket word at run.x must have `/ToUnicode == ')'` AND
      //    embedded `glyf` contour == `parenleft` (`(`)!
      //  - RTL `أ (`: bracket word at run.x must have `/ToUnicode == '('` AND
      //    embedded `glyf` contour == `parenright` (`)`)!
      //  - LTR `Solve (x + 1) = (2x - 3)` ON THE SAME PAGE: `'('` word has
      //    `/ToUnicode == '('` AND `glyf` contour == `parenleft` (`(`), while
      //    `')'` word has `/ToUnicode == ')'` AND `glyf` contour == `parenright` (`)`)!
      final closeRun = closeLine.runs.firstWhere((r) => r.text.trim() == ')');
      final openRun = openLine.runs.firstWhere((r) => r.text.trim() == '(');
      final ltrOpenWord = pureLtrLine!.runs
          .expand((r) => r.words)
          .firstWhere((w) => w.text.startsWith('('));
      final ltrCloseWord = pureLtrLine.runs
          .expand((r) => r.words)
          .firstWhere((w) => w.text.endsWith(')'));

      _EmittedGlyphToken tokenAt(double targetX, double targetBaselinePt) {
        final expectedPdfY = page1.pageSize.height - targetBaselinePt;
        return inspected.tokens.firstWhere(
          (t) =>
              (t.x - targetX).abs() < 1.5 && (t.y - expectedPdfY).abs() < 2.5,
        );
      }

      final pdfCloseToken = tokenAt(closeRun.x, closeLine.baseline);
      expect(pdfCloseToken.unicodeText, ')',
          reason: 'Logical /ToUnicode of "أ )" bracket must remain ")"');
      final closeGlyphBytes = inspected
          .fonts[pdfCloseToken.fontKey]!.parser
          .readGlyph(pdfCloseToken.cids.single)
          .data;
      expect(closeGlyphBytes, equals(expectedParenLeftOutline),
          reason:
              'Vector PDF glyf outline for RTL "أ )" must be mirrored parenleft "(" matching Preview!');

      final pdfOpenToken = tokenAt(openRun.x, openLine.baseline);
      expect(pdfOpenToken.unicodeText, '(',
          reason: 'Logical /ToUnicode of "أ (" bracket must remain "("');
      final openGlyphBytes = inspected
          .fonts[pdfOpenToken.fontKey]!.parser
          .readGlyph(pdfOpenToken.cids.single)
          .data;
      expect(openGlyphBytes, equals(expectedParenRightOutline),
          reason:
              'Vector PDF glyf outline for RTL "أ (" must be mirrored parenright ")" matching Preview!');

      final pdfLtrOpen = tokenAt(ltrOpenWord.x, pureLtrLine.baseline);
      expect(pdfLtrOpen.unicodeText.codeUnitAt(0), 0x0028);
      expect(
        inspected.fonts[pdfLtrOpen.fontKey]!.parser
            .readGlyph(pdfLtrOpen.cids.first)
            .data,
        equals(expectedParenLeftOutline),
        reason: 'LTR "(" on the very same page must NOT be flipped!',
      );

      final pdfLtrClose = tokenAt(ltrCloseWord.x, pureLtrLine.baseline);
      expect(
        pdfLtrClose.unicodeText.codeUnitAt(pdfLtrClose.unicodeText.length - 1),
        0x0029,
      );
      expect(
        inspected.fonts[pdfLtrClose.fontKey]!.parser
            .readGlyph(pdfLtrClose.cids.last)
            .data,
        equals(expectedParenRightOutline),
        reason: 'LTR ")" on the very same page must NOT be flipped!',
      );

      // 5. Verify Exact DOCX OOXML structure & byte-exact snapshot embedding:
      final archive = ZipDecoder().decodeBytes(exactDocx!);
      final docXmlFile = archive.findFile('word/document.xml');
      expect(docXmlFile, isNotNull);
      final docXml = utf8.decode(docXmlFile!.content as List<int>);
      expect(docXml, contains('<w:bidi/>'),
          reason: 'DOCX paragraphs must preserve RTL <w:bidi/> property');
      final media1 = archive.findFile('word/media/page_1.png');
      expect(media1, isNotNull);
      expect(media1!.content as List<int>, equals(snapshots.first.pngBytes),
          reason: 'DOCX embedded PNG must match Preview snapshot byte-for-byte');
      expect(exactPdf!.length, greaterThan(1000));

      // Write real sample outputs for external Poppler + LibreOffice inspection!
      await tester.runAsync(() async {
        final outDir = Directory(_samplesDir);
        await outDir.create(recursive: true);
        for (var i = 0; i < snapshots.length; i++) {
          await File('$_samplesDir/preview_page_${i + 1}.png')
              .writeAsBytes(snapshots[i].pngBytes, flush: true);
        }
        await File('$_samplesDir/vector.pdf')
            .writeAsBytes(vectorPdf!, flush: true);
        await File('$_samplesDir/exact.pdf')
            .writeAsBytes(exactPdf!, flush: true);
        await File('$_samplesDir/exact.docx')
            .writeAsBytes(exactDocx!, flush: true);
        await File('$_samplesDir/manifest.json').writeAsString(
          jsonEncode(<String, Object>{
            'pageCount': snapshots.length,
            'widthPx': refW.round(),
            'heightPx': refH.round(),
          }),
          flush: true,
        );
      });
    });
  });
}
