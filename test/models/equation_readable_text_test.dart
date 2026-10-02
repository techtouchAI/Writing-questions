// العرض النصي المقروء للمعادلات (EquationModel.readableText) — آخر ارتداد
// عندما يعجز محرك الرسم نفسه عن ترسيم صيغة (تالفة/قديمة):
//   * لا رمز LaTeX في الناتج أبداً (`\` `$` `{` `}` ولا أمرٌ خام)،
//   * ولا فقد للمحتوى (كل رقم وحرف يصل إلى العرض)،
//   * البنى تُعرض بصورتها الخطية المقروءة: كسر (أ)/(ب)، جذر √(...)،
//     أسس/دلالات يونيكود (x² و x₁) بلا `^` ولا `_`.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/equation_model.dart';

/// المحارف الممنوعة في أي عرض مقروء (تفحصها اختبارات التصدير كلها).
const List<String> _forbidden = <String>[r'\', r'$', '{', '}'];

void _expectReadable(String latex, String expected) {
  final text = EquationModel.readableText(latex);
  expect(text, expected, reason: 'عرض «$latex»');
  for (final token in _forbidden) {
    expect(text, isNot(contains(token)),
        reason: 'العرض المقروء لـ«$latex» سرّب رمزاً خاماً «$token».');
  }
}

void main() {
  group('البنى الأساسية', () {
    test('كسر: (البسط)/(المقام)', () {
      _expectReadable(r'\frac{5}{8}', '(5)/(8)');
      _expectReadable(r'\frac{a}{b}', '(a)/(b)');
      // كسر في بسط كسر: تعشيش بلا فقد.
      _expectReadable(r'\frac{\frac{1}{2}}{3}', '((1)/(2))/(3)');
    });

    test('جذر: √(المحتوى) والدرجة صورة علوية', () {
      _expectReadable(r'\sqrt{66}', '√(66)');
      _expectReadable(r'\sqrt[3]{x}', '³√(x)');
      _expectReadable(r'\sqrt{b^{2}-4ac}', '√(b²-4ac)');
    });

    test('أسس ودلالات: صور يونيكود بلا ^ ولا _', () {
      _expectReadable(r'5^{2}', '5²');
      _expectReadable('5^2', '5²');
      _expectReadable(r'x_{1}', 'x₁');
      _expectReadable('x₁', 'x₁');
      _expectReadable('5²', '5²');
      // ما لا صورة يونيكود له يبقى مقروءاً بين قوسين بلا علامة خام.
      final noForm = EquationModel.readableText('e^{-x}');
      expect(noForm, isNot(contains('^')));
      expect(noForm, contains('e'));
      expect(noForm, contains('x'));
    });

    test('أقواس \\left...\\right: المحددات تبقى والأوامر تزول', () {
      _expectReadable(r'\left(\frac{1}{2}\right)', '((1)/(2))');
      _expectReadable(r'\left| x \right|', '| x |');
      // `\left` بلا `\right` يُحفظ خاماً في النموذج، والعرض المقروء يفكّ
      // بنيته الداخلية أيضاً (كسور وجذور داخل المقطع الخام).
      _expectReadable(r'\left(\frac{1}{2}', '((1)/(2)');
    });

    test('رموز وأوامر: محارف مرئية من سجل الرموز', () {
      _expectReadable(r'\alpha + \beta', 'α + β');
      _expectReadable(r'a \times b', 'a × b');
      // دليل بلا صور يونيكود لكل محارفه يبقى مقروءاً بين قوسين.
      _expectReadable(r'\sum_{i=1}^{n} i', '∑(i=1)ⁿ i');
      // علامة فوق محتوى: المحتوى وحده (لا صورة خطية للسهم/القبعة).
      _expectReadable(r'\vec{F}', 'F');
      _expectReadable(r'\overline{AB}', 'AB');
      // نص صريح يمر كما هو.
      _expectReadable(r'\text{سم}', 'سم');
    });
  });

  group('الصيغ التالفة والقديمة', () {
    test('لا ترمي أبداً ولا تسرّب رمزاً خاماً', () {
      for (final latex in <String>[
        r'\frac{1}{',
        r'\frac',
        r'{x',
        '}',
        r'\unknowncmd{y}',
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
        r'$$',
        r'\sqrt[',
        r'a ^ b',
      ]) {
        final text = EquationModel.readableText(latex);
        for (final token in _forbidden) {
          expect(text, isNot(contains(token)),
              reason: '«$latex» سرّب «$token» في «$text».');
        }
      }
    });

    test('كسر ناقص يبقى غير فارغ (لقطة بديلة صالحة)', () {
      // ضمان مضيف اللقطات: الصيغة التالفة تُلتقط نصاً مقروءاً غير فارغ.
      expect(EquationModel.readableText(r'\frac{1}{'), '(1)/()');
    });

    test('مصفوفة: محتوى كامل بلا أوامر بيئة', () {
      final text = EquationModel.readableText(
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
      );
      for (final digit in <String>['1', '2', '3', '4']) {
        expect(text, contains(digit));
      }
      // لا شرطة مائلة ولا أقواس معقوفة (حلقة المحارف الممنوعة أعلاه تكفلها).
      expect(text, isNot(contains(r'\begin')));
      expect(text, isNot(contains(r'\end')));
    });

    test('الفارغ يعيد فارغاً (لا اختراع محتوى)', () {
      expect(EquationModel.readableText(''), isEmpty);
      expect(EquationModel.readableText('   '), isEmpty);
    });
  });

  group('نموذج المعادلة نفسه', () {
    test('toDisplayText من العقد المبنية بصرياً', () {
      final model = EquationModel.parse(r'\frac{a}{b} + \sqrt{2}');
      expect(model.toDisplayText(), '(a)/(b) + √(2)');
    });
  });
}
