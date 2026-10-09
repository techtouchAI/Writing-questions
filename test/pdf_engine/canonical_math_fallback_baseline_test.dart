import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/equation_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/pdf_engine/canonical_layout_pdf_painter.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/pdf_text_metrics.dart';

/// Math run in the text-fallback path: `text` is the LaTeX source, while the
/// painter emits `EquationModel.readableText(text)`.
LayoutRun _mathFallbackRun(String latex) => LayoutRun(
      id: 'math-$latex',
      semanticNodeId: 'math-node',
      semanticNode: null,
      contentKind: LayoutContentKind.math,
      semanticRole: LayoutSemanticRole.text,
      text: latex,
      x: 10,
      advance: 40,
      width: 40,
      height: 12,
      baselineOffset: 9,
      direction: DocumentDirection.ltr,
      style: const LayoutTextStyle(
        font: PaperFont.naskh,
        fontSizePt: 12,
        lineHeightFactor: 1.4,
      ),
      logicalIndex: 0,
      visualIndex: 0,
      words: const <LayoutWord>[],
    );

void main() {
  // Regression (C6): the fallback math baseline offset was measured from the
  // LaTeX source while the painter emitted the readable text. The maximum word
  // ascent of the two strings differs, so the emitted baseline drifted from
  // the canonical baseline. Both values must come from the emitted text.
  test('math fallback baseline offset is measured from the emitted text',
      () async {
    final font = pw.Font.ttf(await rootBundle.load(ExamFonts.regularAsset));
    const candidates = <String>[
      r'\frac{a}{b}',
      r'\sqrt{x^{2}+1}',
      r'\frac{1}{2}',
      r'\int_{0}^{1} f(x)\,dx',
      r'\alpha^{2}+\beta',
      r'\sum_{i=1}^{n} i',
      r'\left(x\right)',
    ];
    var divergent = 0;
    for (final latex in candidates) {
      final run = _mathFallbackRun(latex);
      final emitted = CanonicalLayoutPdfPainter.emittedRunText(run);
      expect(emitted, EquationModel.readableText(latex), reason: latex);

      final expected = PdfTextMetrics.baselineOffsetFromTop(
        font: font,
        fontSizePt: 12,
        text: emitted,
      );
      expect(
        CanonicalLayoutPdfPainter.textTopOffset(run: run, font: font),
        expected,
        reason: 'offset for "$latex" must use the emitted readable text',
      );

      final fromSource = PdfTextMetrics.baselineOffsetFromTop(
        font: font,
        fontSizePt: 12,
        text: latex,
      );
      if (fromSource != expected) {
        divergent++;
      }
    }
    // Without at least one divergent case the regression is not exercised.
    expect(divergent, greaterThan(0),
        reason: 'no candidate separates LaTeX source from readable text');
  });
}
