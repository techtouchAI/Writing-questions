import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/equation_model.dart';
import 'package:writing_questions_app/models/math_symbols.dart';

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

    test('parses nested structures (scripts normalize to braces)', () {
      const latex = r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}';
      // التطبيع مقصود ومثبت في اختبار sup/sub أعلاه (H_2O ← H_{2}O):
      // لا يُفقد أي محتوى، والأقواس شكل قياسي مكافئ.
      expect(
        EquationModel.parse(latex).toLatex(),
        r'\frac{-b \pm \sqrt{b^{2}-4ac}}{2a}',
      );
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
      // الشارد لا يُسقِط ما بعده، ويُهرَّب عند الحفظ فلا يُفسد بنية الصيغة
      // في محركات العرض (`}` عارية كانت تكسر الرسم كله سابقاً).
      expect(EquationModel.parse('}').toLatex(), r'\}');
      expect(EquationModel.parse('a}b').toLatex(), r'a\}b');
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

  group('EquationModel: العرض المرئي بلا كود LaTeX', () {
    test('loads stored commands as visible glyphs in the editing slots', () {
      // المدرس يفتح معادلة قديمة: يرى α و× لا أوامر LaTeX خاماً، والفراغات
      // تبقى كما كتبها (عرض أمين للمصدر — لا ابتلاع ولا إضافة).
      final model = EquationModel.parse(r'\alpha \times 2');
      final texts = model.nodes.whereType<EqText>().map((node) => node.text);
      expect(texts.join(), 'α × 2');
      // والحفظ يعيد الأوامر القياسية نفسها بايت-ببايت (اتفاق كل المحركات،
      // والاستبدال في المخزون يتم بالفهارس فيتطلب مصدراً مستقراً).
      expect(model.toLatex(), r'\alpha \times 2');
    });

    test('a letter after a symbol command stays a separate token on save', () {
      // `\alphax` أمر آخر غير معروف يفسد الصيغة كلها — الفاصل اللاتيني
      // يفرض فراغ الإنهاء: «αx» تُحفظ `\alpha x`.
      expect(MathSymbols.toLatex('αx'), r'\alpha x');
      expect(EqText('αx').toLatex(), r'\alpha x');
      // الرقم والرمز ينهيان اسم الأمر وحدهما — بلا فراغ زائد.
      expect(MathSymbols.toLatex('α2'), r'\alpha2');
      expect(MathSymbols.toLatex('α×2'), r'\alpha\times2');
      // الأس اليونيكود ليس حرفاً لاتينياً: يبقى كما كُتب (يوسّعه
      // `MathSymbols.canonicalize` في محرك الرسم إلى `^{2}` عند اللزوم).
      expect(MathSymbols.toLatex('α²'), r'\alpha²');
    });

    test('keeps the visible glyph for symbols without a safe command', () {
      // الدرجة ° لا أمر آمناً لها في كل المحركات: تبقى محرفاً في الطرفين.
      expect(EquationModel.parse('90°').toLatex(), '90°');
      expect(EqText('°').toLatex(), '°');
    });

    test('normalizes equivalent unicode input on save', () {
      // ناقص يونيكود من زر المحرر ← ناقص قياسي في المخزون.
      expect(EqText('5−3').toLatex(), '5-3');
    });

    test('parses accents (\\vec, \\hat, \\bar) as editable structures', () {
      final vector = EquationModel.parse(r'\vec{F}');
      expect(vector.nodes.single, isA<EqAccent>());
      expect((vector.nodes.single as EqAccent).kind, EqAccentKind.vector);
      expect(vector.toLatex(), r'\vec{F}');

      final bar = EquationModel.parse(r'\overline{AB}');
      expect((bar.nodes.single as EqAccent).kind, EqAccentKind.bar);
      expect(bar.toLatex(), r'\bar{AB}');
    });
  });
}
