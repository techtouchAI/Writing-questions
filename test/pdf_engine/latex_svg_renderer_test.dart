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
      // النص العربي (داخل \\text أو عارياً) خارج نطاق خط المتجهات —
      // البديل النصي في المحرك؛ والبنية الناقصة معزولة باستثناء.
      expect(LatexSvgRenderer.tryToSvg('نص عربي'), isNull);
      expect(LatexSvgRenderer.tryToSvg(r'\text{نص عربي}'), isNull);
      expect(
        LatexSvgRenderer.tryToSvg(r'\frac{a}'),
        isNull,
        reason: 'بنية ناقصة = FormatException معزول',
      );
    });

    test('\\text of supported glyphs renders (units like cm and kg)', () {
      final result = LatexSvgRenderer.tryToSvg(r'5 \text{cm}^3', fontSize: 12);
      expect(result, isNotNull);
      expect(result!.svg, contains('<path'));
    });

    test('unknown letter commands render upright instead of dropping content', () {
      // دالة كتبها المدرس بلا دعم بنيوي: تُرسم اسماً ولا تُسقَط الصيغة كلها.
      final result = LatexSvgRenderer.tryToSvg(r'\floor{x} = 2', fontSize: 12);
      expect(result, isNotNull, reason: 'إسقاط المحتوى آخر العلاج لا أوله');
    });

    test('renders every symbol the visual equation editor inserts', () {
      // خلل سابق: محرف واحد ناقص (− أو « أو رقم مشرقي) كان يُسقط المعادلة
      // كلها إلى بديل نصي في PDF وWord.
      const symbols = <String>[
        '+', '−', '×', '÷', '/', '·', '±', '∫', '∑', '=', '<', '>',
        '≤', '≥', '≠', '≈', '∞', '→', '«', '»', 'α', 'β', 'γ', 'δ',
        'θ', 'λ', 'μ', 'π', 'σ', 'φ', 'ω', 'Ω', '٠', '١', '٢', '٣',
        '٤', '٥', '٦', '٧', '٨', '٩', '∈', '∉', '⊂', '⊃', '⊆', '⊇',
        '∪', '∩', '∅', '∀', '∃', '¬', '∧', '∨', '∠', '⊥', '∥', '∘',
        '√', '∼', '∝', '∂', '∇', '⇒', '⇔', '↔',
      ];
      for (final symbol in symbols) {
        final result = LatexSvgRenderer.tryToSvg(symbol, fontSize: 12);
        expect(result, isNotNull, reason: 'المحرف «$symbol» غير مرسوم');
        expect(result!.svg, contains('<path'), reason: symbol);
      }
    });

    test('unicode equivalents canonicalize to the same drawing', () {
      // ناقص يونيكود U+2212 وشرطة en-dash وعلامة النسبة العربية ← صورتها
      // القياسية: نفس الرسم مهما اختلفت لوحة المفاتيح.
      final minus = LatexSvgRenderer.tryToSvg('5 − 3', fontSize: 12);
      final ascii = LatexSvgRenderer.tryToSvg('5 - 3', fontSize: 12);
      expect(minus, isNotNull);
      expect(minus!.width, ascii!.width);

      final percent = LatexSvgRenderer.tryToSvg(r'50 ٪', fontSize: 12);
      expect(percent, isNotNull);
      expect(percent!.width, LatexSvgRenderer.tryToSvg(r'50 \%', fontSize: 12)!.width);
    });

    test('unicode super/subscripts become real scripts (x² ← x^{2})', () {
      final direct = LatexSvgRenderer.tryToSvg('x²', fontSize: 12);
      final explicit = LatexSvgRenderer.tryToSvg('x^{2}', fontSize: 12);
      expect(direct, isNotNull);
      expect(direct!.width, closeTo(explicit!.width, 0.01));
      expect(direct.height, closeTo(explicit.height, 0.01));
    });

    test('multi-digit numbers keep their digits in order and place value', () {
      for (final formula in <String>['1234', '3.14159', 'x_12 + y_345', '10^{23}']) {
        final result = LatexSvgRenderer.tryToSvg(formula, fontSize: 12);
        expect(result, isNotNull, reason: formula);
        expect(result!.width, greaterThan(0), reason: formula);
      }
      // عرض «12» أعرض من «1» وأضيق من «123»: الأرقام تتراص لا تتراكب.
      final one = LatexSvgRenderer.toSvg('1', fontSize: 12);
      final two = LatexSvgRenderer.toSvg('12', fontSize: 12);
      final three = LatexSvgRenderer.toSvg('123', fontSize: 12);
      expect(two.width, greaterThan(one.width));
      expect(three.width, greaterThan(two.width));
    });

    test('\\left...\\right fences stretch to their content height', () {
      final plain = LatexSvgRenderer.toSvg(r'\frac{a}{b}', fontSize: 12);
      final fenced = LatexSvgRenderer.toSvg(r'\left(\frac{a}{b}\right)', fontSize: 12);
      final braces = LatexSvgRenderer.toSvg(r'\left\{\frac{a}{b}\right\}', fontSize: 12);
      expect(fenced.height, greaterThan(plain.height + 1.5),
          reason: 'القوسان يجب أن يحيطا بالكسر لا أن يقصراه');
      expect(fenced.width, greaterThan(plain.width));
      expect(braces.svg, contains('<path'));
      // \\left بلا \\right لا يُسقط الصيغة: يرتد إلى قوس عادي ويُكمَل الرسم.
      expect(LatexSvgRenderer.tryToSvg(r'\left(x + 1', fontSize: 12), isNotNull);
    });

    test('relations and binary operators get TeX spacing', () {
      double w(String latex) => LatexSvgRenderer.toSvg(latex, fontSize: 12).width;
      // العرض الكلي يضمّ عرض رمز العملية نفسه وهامش حافة ثابتاً في كل صيغة؛
      // الفروق أدناه تلغي الاثنين فتعزل **الفراغ وحده** بين الذرات:
      // (a-x − ax) تحمل رمز الناقص + فراغه الثنائي، و(-x − x) تحمل الرمز
      // وحده (أحادي بلا فراغ) — والفرق هو مجموع فراغَي الجهتين الثنائيتين.
      final binarySpacing = (w('a-x') - w('ax')) - (w('-x') - w('x'));
      expect(binarySpacing, greaterThan(3.0)); // 0.22em لكل جهة ≈ 5.28
      expect(binarySpacing, lessThan(6.0));
      // العلاقة (~0.28em) أوسع من العملية الثنائية (~0.22em): الفرق يطرح
      // هوامش القياس وعرضي الرمزين معاً فيبقى فرق الفراغين خالصاً.
      final relationExtra =
          (w('a=b') - w('ab') - w('=')) - (w('a+b') - w('ab') - w('+'));
      expect(relationExtra, greaterThan(0.9)); // ≈ 2×(0.28−0.22)×12 = 1.44
      // الناقص الأحادي (أول الصيغة) لا يأخذ فراغاً ثنائياً.
      final unary = w('-x') - w('x') - w('-');
      final binary = w('a-x') - w('ax') - w('-');
      expect(unary, lessThan(binary));
    });

    test('toSvg throws explicit FormatException on bad structure', () {
      expect(
        () => LatexSvgRenderer.toSvg(r'\frac{a}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
