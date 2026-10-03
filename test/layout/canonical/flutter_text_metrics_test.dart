import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/font_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';

void main() {
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
            semanticRole: LayoutSemanticRole.questionNumber,
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
