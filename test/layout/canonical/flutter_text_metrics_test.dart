import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/font_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/paper_font.dart';

void main() {
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
