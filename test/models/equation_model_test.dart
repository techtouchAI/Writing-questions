import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/equation_model.dart';

void main() {
  group('EquationModel.parse', () {
    test('parses plain text into a single text node', () {
      final model = EquationModel.parse('x+1');

      expect(model.nodes, hasLength(1));
      expect(model.nodes.single, isA<EqText>());
      expect(model.toLatex(), 'x+1');
    });

    test('parses fractions with numerator and denominator slots', () {
      final model = EquationModel.parse(r'\frac{a}{b}');

      expect(model.nodes.single, isA<EqFraction>());
      final fraction = model.nodes.single as EqFraction;
      expect((fraction.numerator.single as EqText).text, 'a');
      expect((fraction.denominator.single as EqText).text, 'b');
      expect(model.toLatex(), r'\frac{a}{b}');
    });

    test('parses square and nth roots', () {
      final square = EquationModel.parse(r'\sqrt{x}');
      expect(square.nodes.single, isA<EqSqrt>());
      expect((square.nodes.single as EqSqrt).root, isEmpty);
      expect(square.toLatex(), r'\sqrt{x}');

      final nth = EquationModel.parse(r'\sqrt[3]{x}');
      final sqrt = nth.nodes.single as EqSqrt;
      expect(sqrt.root, hasLength(1));
      expect(nth.toLatex(), r'\sqrt[3]{x}');
    });

    test('parses superscripts and subscripts', () {
      expect(EquationModel.parse('x^{2}').toLatex(), 'x^{2}');
      expect(EquationModel.parse('H_2O').toLatex(), 'H_{2}O');
      expect(EquationModel.parse('x_1').toLatex(), 'x_{1}');
    });

    test('parses nested structures losslessly', () {
      const latex = r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}';
      expect(EquationModel.parse(latex).toLatex(), latex);
    });

    test('keeps unsupported commands verbatim instead of losing them', () {
      expect(EquationModel.parse(r'\alpha + \beta').toLatex(), r'\alpha + \beta');
      expect(EquationModel.parse(r'\vec{F}').toLatex(), r'\vec{F}');
    });

    test('never throws on malformed input and preserves stray text', () {
      for (final broken in <String>[
        r'\frac{a}',
        r'\sqrt',
        'x^{',
        'a_b_c',
        r'\left(',
        '}',
        'a}b',
        '',
      ]) {
        expect(() => EquationModel.parse(broken), returnsNormally,
            reason: 'parse($broken) must not throw');
      }
      // الشارد يُحفَظ حرفياً ولا يُسقِط ما بعده.
      expect(EquationModel.parse('}').toLatex(), '}');
      expect(EquationModel.parse('a}b').toLatex(), 'a}b');
      expect(EquationModel.parse('').isEmpty, isTrue);
    });
  });

  group('EqNode.toLatex', () {
    test('builds structures programmatically', () {
      final fraction = EqFraction(
        numerator: <EqNode>[EqText('a')],
        denominator: <EqNode>[EqText('b')],
      );
      expect(fraction.toLatex(), r'\frac{a}{b}');

      final power = EqSup(
        base: <EqNode>[EqText('x')],
        exponent: <EqNode>[EqText('2')],
      );
      expect(power.toLatex(), 'x^{2}');

      // القاعدة المركبة تُحاط بأقواس حفاظاً على المعنى.
      final complex = EqSup(
        base: <EqNode>[EqText('x+1')],
        exponent: <EqNode>[EqText('2')],
      );
      expect(complex.toLatex(), '{x+1}^{2}');

      final fence = EqFence(left: '(', right: ')', body: <EqNode>[EqText('x')]);
      expect(fence.toLatex(), '(x)');
    });

    test('escapes dollar signs inside math text', () {
      expect(sanitizeMathText(r'a$b'), r'a\$b');
      expect(EqText(r'5$').toLatex(), r'5\$');
    });
  });
}
