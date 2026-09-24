import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/pdf_engine/latex/latex_svg_renderer.dart';

void main() {
  group('LatexSvgRenderer.toSvg', () {
    test('renders fractions (\\frac) as pure vector SVG', () {
      final result = LatexSvgRenderer.toSvg(r'\frac{a}{b}', fontSize: 12);

      expect(result.svg, startsWith('<svg'));
      expect(result.svg, contains('<path'));
      expect(result.svg, contains('</svg>'));
      expect(
        result.svg,
        contains('xmlns="http://www.w3.org/2000/svg"'),
        reason: 'SVG مكتفٍ ذاتياً لعرضه عبر pw.SvgImage',
      );
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      expect(result.baseline, greaterThan(0));
    });

    test('renders roots with optional index (\\sqrt[n]{x})', () {
      final root = LatexSvgRenderer.toSvg(r'\sqrt{x}', fontSize: 12);
      final indexed = LatexSvgRenderer.toSvg(r'\sqrt[3]{n}', fontSize: 12);

      expect(root.svg, contains('<path'));
      expect(indexed.svg, contains('<path'));
    });

    test('renders superscripts and subscripts (x^{2}, x_{1}, H_2O)', () {
      for (final formula in <String>[r'x^{2}', r'x_{1}', r'H_2O', r'x^2_1']) {
        final result = LatexSvgRenderer.toSvg(formula, fontSize: 12);
        expect(result.svg, contains('<path'), reason: formula);
      }
    });

    test('renders integrals, sums and limits with bounds', () {
      final integral =
          LatexSvgRenderer.toSvg(r'\int_{a}^{b} f(x)\,dx', fontSize: 12);
      final sum = LatexSvgRenderer.toSvg(r'\sum_{i=1}^{n} i', fontSize: 12);
      final limit = LatexSvgRenderer.toSvg(r'\lim_{x \to 0}', fontSize: 12);

      for (final result in <LatexSvg>[integral, sum, limit]) {
        expect(result.svg, contains('<path'));
        expect(result.height, greaterThan(0));
      }
    });

    test('renders physics/chemistry formulas used by the toolbar', () {
      for (final formula in <String>[
        r'F = ma',
        r'E = mc^2',
        r'V = IR',
        r'\vec{F}',
        r'CO_2 \rightarrow H_2O',
        r'Ag^+ + Cl^- \rightarrow AgCl',
        r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}',
      ]) {
        final result = LatexSvgRenderer.tryToSvg(formula, fontSize: 12);
        expect(result, isNotNull, reason: formula);
        expect(result!.svg, contains('<path'), reason: formula);
      }
    });

    test('tryToSvg returns null for unsupported input instead of crashing', () {
      // النص العربي و\\text خارج نطاق خط المتجهات — البديل النصي في المحرك.
      expect(LatexSvgRenderer.tryToSvg('نص عربي'), isNull);
      expect(LatexSvgRenderer.tryToSvg(r'\text{hello}'), isNull);
      expect(LatexSvgRenderer.tryToSvg(r'\unknownCommand'), isNull);
      expect(
        LatexSvgRenderer.tryToSvg(r'\frac{a}'),
        isNull,
        reason: 'بنية ناقصة = FormatException معزول',
      );
    });

    test('toSvg throws explicit FormatException on bad structure', () {
      expect(
        () => LatexSvgRenderer.toSvg(r'\frac{a}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
