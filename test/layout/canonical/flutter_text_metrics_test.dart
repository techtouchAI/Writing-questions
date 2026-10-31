import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/font_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';

void main() {
  testWidgets('LTR title Arabic island words keep their native intervals before Latin marks', (_) async {
    await FlutterTextMetrics.ensureFontsLoaded();
    const source = 'QALPHA نص مختلط (5 marks)';
    for (final width in [220.0, 250.0]) {
      const style = LayoutTextStyle(font: PaperFont.naskh, fontSizePt: 12,
        lineHeightFactor: 1.2, bold: true);
      final paragraph = const FlutterTextMetrics().layoutParagraph(spans: const [
        MetricSpan(semanticNodeId: 'reorder-title', semanticNode: null, text: source,
          contentKind: LayoutContentKind.text, semanticRole: LayoutSemanticRole.text,
          style: style, direction: DocumentDirection.ltr, logicalIndex: 0),
      ], width: width, direction: DocumentDirection.ltr, alignment: null, resolveJustification: false);
      final native = TextPainter(text: TextSpan(text: source, style: TextStyle(
        fontFamily: PaperFont.naskh.family, fontWeight: FontWeight.bold,
        fontSize: LayoutUnits.ptToPx(12), height: 1.2)), textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling)..layout(minWidth: LayoutUnits.ptToPx(width), maxWidth: LayoutUnits.ptToPx(width));
      try {
        final words = paragraph.lines.expand((line) => line.fragments)
          .expand((fragment) => fragment.words).toList();
        final intervals = <({double x, double right})>[];
        for (final text in ['نص', 'مختلط']) {
          final start = source.indexOf(text);
          final reference = native.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + text.length),
            boxHeightStyle: ui.BoxHeightStyle.strut, boxWidthStyle: ui.BoxWidthStyle.tight).single;
          final actual = words.singleWhere((word) => word.text == text);
          expect(actual.x, closeTo(LayoutUnits.pxToPt(reference.left), 1e-6), reason: text);
          expect(actual.textAdvance, closeTo(LayoutUnits.pxToPt(reference.right - reference.left), 1e-6), reason: text);
          intervals.add((x: actual.x, right: actual.x + actual.textAdvance));
        }
        intervals.sort((a, b) => a.x.compareTo(b.x));
        expect(intervals.first.right, lessThan(intervals.last.x));
      } finally { native.dispose(); }
    }
  });

  testWidgets('rounded-up and rounded-down native flow bands neither overlap nor grow the paragraph', (_) async {
    await FlutterTextMetrics.ensureFontsLoaded();
    const metrics = FlutterTextMetrics();
    final text = List.filled(12, 'هذا نص عربي مع English لفحص تدفق السطر').join(' ');
    for (final factor in <double>[1.3, 1.35, 1.7]) {
      final style = LayoutTextStyle(font: PaperFont.naskh, fontSizePt: 14, lineHeightFactor: factor);
      final paragraph = metrics.layoutParagraph(spans: <MetricSpan>[
        MetricSpan(semanticNodeId: 'body', semanticNode: null, text: text,
          contentKind: LayoutContentKind.text, semanticRole: LayoutSemanticRole.text,
          style: style, direction: DocumentDirection.rtl, logicalIndex: 0),
      ], width: 300, direction: DocumentDirection.rtl, alignment: null,
        resolveJustification: false);
      final painter = TextPainter(text: TextSpan(text: text, style: TextStyle(
        fontFamily: PaperFont.naskh.family, fontSize: LayoutUnits.ptToPx(14), height: factor)),
        textDirection: TextDirection.rtl, textScaler: TextScaler.noScaling)
        ..layout(minWidth: LayoutUnits.ptToPx(300), maxWidth: LayoutUnits.ptToPx(300));
      try {
        final native = painter.computeLineMetrics();
        expect(native.length, greaterThan(1));
        expect(paragraph.lines.length, native.length);
        var nativeFlowTop = 0.0;
        for (var i = 0; i < native.length; i++) {
          final line = paragraph.lines[i];
          expect(line.top, closeTo(LayoutUnits.pxToPt(nativeFlowTop), 1e-6));
          expect(line.height, closeTo(LayoutUnits.pxToPt(native[i].height), 1e-6));
          expect(line.baseline, closeTo(LayoutUnits.pxToPt(native[i].baseline), 1e-6));
          nativeFlowTop += native[i].height;
        }
        expect(nativeFlowTop, closeTo(painter.height, 1e-6));
        expect(paragraph.lines.last.top + paragraph.lines.last.height,
          closeTo(paragraph.height, 1e-6));
      } finally {
        painter.dispose();
      }
    }
  });

  testWidgets('glyph overhang is recorded without inflating native paragraph flow', (_) async {
    await FlutterTextMetrics.ensureFontsLoaded();
    const metrics = FlutterTextMetrics();
    for (final font in <PaperFont>[PaperFont.amiri, PaperFont.naskh]) {
      const text = 'بسم الله الرحمن الرحيم';
      final style = LayoutTextStyle(font: font, fontSizePt: 17, lineHeightFactor: 1);
      final paragraph = metrics.layoutParagraph(spans: <MetricSpan>[
        MetricSpan(semanticNodeId: 'header', semanticNode: null, text: text,
          contentKind: LayoutContentKind.text, semanticRole: LayoutSemanticRole.text,
          style: style, direction: DocumentDirection.rtl, logicalIndex: 0),
      ], width: 300, direction: DocumentDirection.rtl, alignment: PaperAlign.center,
        resolveJustification: false);
      final painter = TextPainter(text: TextSpan(text: text, style: TextStyle(
        fontFamily: font.family, fontSize: LayoutUnits.ptToPx(17), height: 1)),
        textDirection: TextDirection.rtl, textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling)
        ..layout(minWidth: LayoutUnits.ptToPx(300), maxWidth: LayoutUnits.ptToPx(300));
      try {
        final boxes = painter.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: text.length));
        final line = paragraph.lines.single;
        expect(paragraph.height, closeTo(LayoutUnits.pxToPt(painter.height), 1e-6));
        expect(line.top + line.height, lessThanOrEqualTo(paragraph.height + 1e-6));
        expect(line.glyphTop, closeTo(LayoutUnits.pxToPt(boxes.map((b) => b.top).reduce((a, b) => a < b ? a : b)), 1e-6));
        expect(line.glyphBottom, closeTo(LayoutUnits.pxToPt(boxes.map((b) => b.bottom).reduce((a, b) => a > b ? a : b)), 1e-6));
      } finally {
        painter.dispose();
      }
    }
  });

  testWidgets('styled run hit bounds use the actual preview paint baseline and box height', (_) async {
    await FlutterTextMetrics.ensureFontsLoaded();
    const metrics = FlutterTextMetrics();
    const text = 'اختيار';
    for (final factor in <double>[1, 1.2, 1.45, 1.7]) {
      final style = LayoutTextStyle(font: PaperFont.naskh, fontSizePt: 14, lineHeightFactor: factor);
      final paragraph = metrics.layoutParagraph(spans: <MetricSpan>[
        MetricSpan(semanticNodeId: 'point/content', semanticNode: null, text: text,
          contentKind: LayoutContentKind.text, semanticRole: LayoutSemanticRole.text,
          style: style, direction: DocumentDirection.rtl, logicalIndex: 0),
      ], width: 300, direction: DocumentDirection.rtl, alignment: null, resolveJustification: false);
      final fragment = paragraph.lines.single.fragments.single;
      // Independent one-line painter with the exact style used by preview,
      // not a height=1 baseline borrowed from a differently styled box.
      final painter = TextPainter(text: TextSpan(text: text, style: TextStyle(
        fontFamily: PaperFont.naskh.family, fontSize: LayoutUnits.ptToPx(14), height: factor)),
        textDirection: TextDirection.rtl, textScaler: TextScaler.noScaling, maxLines: 1)
        ..layout(maxWidth: double.infinity);
      try {
        final baseline = LayoutUnits.pxToPt(painter.computeLineMetrics().single.baseline);
        final boxes = painter.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: text.length),
          boxHeightStyle: ui.BoxHeightStyle.strut);
        expect(boxes, hasLength(1));
        expect(fragment.baselineOffset, closeTo(baseline, 1e-6), reason: 'style height $factor');
        expect(fragment.height, closeTo(LayoutUnits.pxToPt(boxes.single.bottom - boxes.single.top), 1e-6));
        final actualTop = paragraph.lines.single.baseline - baseline;
        final plannedTop = paragraph.lines.single.baseline - fragment.baselineOffset;
        expect(plannedTop, closeTo(actualTop, 1e-6));
      } finally {
        painter.dispose();
      }
    }
  });

  testWidgets('directional runs preserve mixed bidi source text losslessly', (_) async {
    const source = '، قبل (MIX 123) بعد\u00a0؛';
    for (final fallback in <DocumentDirection>[
      DocumentDirection.rtl,
      DocumentDirection.ltr,
    ]) {
      final runs = FlutterTextMetrics.resolveDirectionalRuns(
        source,
        fallbackDirection: fallback,
      );
      expect(runs, isNotEmpty);
      expect(runs.every((run) => run.text.isNotEmpty), isTrue);
      expect(runs.map((run) => run.text).join(), source);
      expect(
        runs.any((run) =>
            run.direction == DocumentDirection.rtl && run.text.contains('قبل')),
        isTrue,
      );
      expect(
        runs.any((run) =>
            run.direction == DocumentDirection.ltr && run.text.contains('MIX')),
        isTrue,
      );
      expect(runs.map((run) => run.text).join(), contains('\u00a0'));
    }
  });

  testWidgets(
    'alignment offsets are part of canonical run geometry for Preview and PDF',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const metrics = FlutterTextMetrics();
      const width = 300.0;
      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.2,
      );
      MeasuredRunFragment measure(PaperAlign alignment) =>
          metrics
              .layoutParagraph(
                spans: const <MetricSpan>[
                  MetricSpan(
                    semanticNodeId: 'category',
                    semanticNode: null,
                    text: 'Cat',
                    contentKind: LayoutContentKind.text,
                    semanticRole: LayoutSemanticRole.text,
                    style: style,
                    direction: DocumentDirection.rtl,
                    logicalIndex: 0,
                  ),
                ],
                width: width,
                direction: DocumentDirection.rtl,
                alignment: alignment,
                resolveJustification: false,
              )
              .lines
              .single
              .fragments
              .single;

      final left = measure(PaperAlign.left);
      final center = measure(PaperAlign.center);
      final right = measure(PaperAlign.right);
      final start = measure(PaperAlign.start);
      expect(left.x, closeTo(0, 0.1));
      expect(center.x + center.width / 2, closeTo(width / 2, 0.25));
      expect(right.x + right.width, closeTo(width, 0.25));
      expect(start.x + start.width, closeTo(width, 0.25));
    },
  );

  testWidgets(
    'adjacent full stops remain one measured dotted placeholder run',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const dotted = '....................';
      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 10,
        lineHeightFactor: 1.45,
      );
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'blank-field',
            semanticNode: null,
            text: dotted,
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
          ),
        ],
        width: 300,
        direction: DocumentDirection.rtl,
        alignment: PaperAlign.center,
        resolveJustification: false,
      );
      expect(paragraph.lines, hasLength(1));
      expect(paragraph.lines.single.fragments, hasLength(1));
      expect(paragraph.lines.single.fragments.single.text, dotted);
    },
  );

  testWidgets(
    'all text fragments on a line share the measured natural baseline',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 10.5,
        lineHeightFactor: 1.45,
      );
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'item-body',
            semanticNode: null,
            text: 'البند الأول قصير',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
          ),
        ],
        width: 300,
        direction: DocumentDirection.rtl,
        alignment: null,
        resolveJustification: false,
      );
      final fragments = paragraph.lines.single.fragments;
      expect(fragments.length, greaterThan(2));
      for (final fragment in fragments.skip(1)) {
        expect(fragment.baselineOffset, closeTo(fragments.first.baselineOffset, 0.01));
      }
    },
  );

  testWidgets(
    'mixed Arabic and Latin words map each visual box to its own source run',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.2,
      );
      const source = 'المتوسطHDG1';
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'mixed-header-field',
            semanticNode: null,
            text: source,
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
          ),
        ],
        width: 180,
        direction: DocumentDirection.rtl,
        alignment: null,
        resolveJustification: false,
      );

      final fragments = paragraph.lines
          .expand((line) => line.fragments)
          .toList()
        ..sort((a, b) => a.startOffset.compareTo(b.startOffset));
      expect(fragments.map((fragment) => fragment.text).join(), source);
      expect(
        fragments.where((fragment) => fragment.direction == DocumentDirection.rtl)
            .map((fragment) => fragment.text).join(),
        'المتوسط',
      );
      expect(
        fragments.where((fragment) => fragment.direction == DocumentDirection.ltr)
            .map((fragment) => fragment.text).join(),
        'HDG1',
      );
    },
  );

  testWidgets(
    'justified paragraphs expand breakable spaces but not the final line',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 10.5,
        lineHeightFactor: 1.45,
      );
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'justified-copy',
            semanticNode: null,
            text: 'هذه فقرة عربية طويلة لاختبار تمديد المسافات بين الكلمات '
                'على الأسطر الملتفة مع إبقاء السطر الأخير طبيعياً',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
          ),
        ],
        width: 220,
        direction: DocumentDirection.rtl,
        alignment: PaperAlign.justify,
        resolveJustification: true,
      );

      expect(paragraph.lines.length, greaterThan(1));
      for (final line in paragraph.lines.take(paragraph.lines.length - 1)) {
        expect(line.isJustified, isTrue);
        expect(line.justificationOpportunityCount, greaterThan(0));
        expect(line.extraSpacePerOpportunity, greaterThan(0));
        expect(line.resolvedWidth, greaterThan(line.naturalWidth));
      }
      expect(paragraph.lines.last.isJustified, isFalse);
      expect(paragraph.lines.last.extraSpacePerOpportunity, 0);
    },
  );

  testWidgets(
    'auto-direction math stays between Latin anchors in an RTL document',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.2,
      );
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'left-anchor',
            semanticNode: null,
            text: 'F5A ',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 0,
          ),
          MetricSpan(
            semanticNodeId: 'inline-equation',
            semanticNode: null,
            text: r'\frac{5}{8}',
            contentKind: LayoutContentKind.math,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 1,
            mathBox: LayoutMathBox(
              widthPt: 14.8,
              heightPt: 15.4,
              baselinePt: 12,
            ),
          ),
          MetricSpan(
            semanticNodeId: 'right-anchor',
            semanticNode: null,
            text: ' F5B',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 2,
          ),
        ],
        width: 300,
        direction: DocumentDirection.rtl,
        alignment: PaperAlign.start,
        resolveJustification: false,
      );
      final fragments = paragraph.lines.single.fragments;
      final anchorA = fragments.firstWhere(
        (fragment) => fragment.spanIndex == 0 && fragment.text.trim() == 'F5A',
      );
      final equation = fragments.firstWhere((fragment) => fragment.spanIndex == 1);
      final anchorB = fragments.firstWhere(
        (fragment) => fragment.spanIndex == 2 && fragment.text.trim() == 'F5B',
      );

      expect(anchorA.x + anchorA.width, lessThan(equation.x + 0.25));
      expect(equation.x + equation.width, lessThan(anchorB.x + 0.25));
    },
  );

  testWidgets(
    'inline math follows its neighboring run inside an RTL title',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.2,
      );
      final paragraph = const FlutterTextMetrics().layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'question-label',
            semanticNode: null,
            text: 'السؤال الأول — ',
            contentKind: LayoutContentKind.number,
            semanticRole: LayoutSemanticRole.number,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
          ),
          MetricSpan(
            semanticNodeId: 'left-anchor',
            semanticNode: null,
            text: 'F5A ',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 1,
          ),
          MetricSpan(
            semanticNodeId: 'inline-equation',
            semanticNode: null,
            text: r'\frac{5}{8}',
            contentKind: LayoutContentKind.math,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 2,
            mathBox: LayoutMathBox(
              widthPt: 14.8,
              heightPt: 15.4,
              baselinePt: 12,
            ),
          ),
          MetricSpan(
            semanticNodeId: 'right-anchor',
            semanticNode: null,
            text: ' F5B',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.auto,
            logicalIndex: 3,
          ),
        ],
        width: 300,
        direction: DocumentDirection.rtl,
        alignment: PaperAlign.start,
        resolveJustification: false,
      );
      final fragments = paragraph.lines.single.fragments;
      final anchorA = fragments.firstWhere(
        (fragment) => fragment.spanIndex == 1 && fragment.text.trim() == 'F5A',
      );
      final equation = fragments.firstWhere((fragment) => fragment.spanIndex == 2);
      final anchorB = fragments.firstWhere(
        (fragment) => fragment.spanIndex == 3 && fragment.text.trim() == 'F5B',
      );

      expect(anchorA.x + anchorA.width, lessThan(equation.x + 0.25));
      expect(equation.x + equation.width, lessThan(anchorB.x + 0.25));
    },
  );

  testWidgets(
    'Arabic word ranges stay aligned after inline math placeholders',
    (_) async {
      final fontLoader = FontLoader(PaperFont.naskh.family)
        ..addFont(rootBundle.load(PaperFont.naskh.regularAsset));
      await fontLoader.load();

      const style = LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.2,
      );
      const metrics = FlutterTextMetrics();
      final paragraph = metrics.layoutParagraph(
        spans: const <MetricSpan>[
          MetricSpan(
            semanticNodeId: 'equation',
            semanticNode: null,
            text: 'x squared',
            contentKind: LayoutContentKind.math,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 0,
            mathBox: LayoutMathBox(widthPt: 24, heightPt: 14, baselinePt: 11),
          ),
          MetricSpan(
            semanticNodeId: 'arabic-text',
            semanticNode: null,
            text: 'هذه فقرة عربية للنص الذي يلي عنصر المعادلة مباشرة',
            contentKind: LayoutContentKind.text,
            semanticRole: LayoutSemanticRole.text,
            style: style,
            direction: DocumentDirection.rtl,
            logicalIndex: 1,
          ),
        ],
        width: 110,
        direction: DocumentDirection.rtl,
        alignment: null,
        resolveJustification: false,
      );

      expect(paragraph.lines, isNotEmpty);
      expect(
        paragraph.lines
            .expand((line) => line.fragments)
            .any((fragment) => fragment.text.contains('المعادلة')),
        isTrue,
      );
    },
  );
}
