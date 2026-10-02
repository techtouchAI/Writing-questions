import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/docx/omml_from_equation.dart';
import 'package:writing_questions_app/models/math_symbols.dart';

/// نص كل `m:t` في المنطقة الرياضية، بتر ورته — يثبت أن لا محرف فُقد ولا
/// كود LaTeX تسرّب، دون الاعتماد على تفصيل الوسوم.
List<String> _mathTexts(String xml) {
  final pattern = RegExp('<m:t xml:space="preserve">(.*?)</m:t>');
  return pattern
      .allMatches(xml)
      .map((match) => match
          .group(1)!
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&'))
      .toList();
}

/// يتحقق من توازن الوسوم ومن أن لا شرطة مائلة ولا دولار في المخرج.
void _expectCleanMathZone(String xml, {required String latex}) {
  final tags = RegExp(r'<(/?)([a-z]+:[A-Za-z0-9]+)[^>]*?(/)?>');
  final stack = <String>[];
  for (final match in tags.allMatches(xml)) {
    final closing = (match.group(1) ?? '').isNotEmpty;
    final selfClosing = (match.group(3) ?? '').isNotEmpty;
    final name = match.group(2)!;
    if (selfClosing) {
      continue;
    }
    if (closing) {
      expect(stack.isNotEmpty && stack.last == name, isTrue,
          reason: '$latex: وسم مغلق بلا مقابل </$name>');
      stack.removeLast();
      continue;
    }
    stack.add(name);
  }
  expect(stack, isEmpty, reason: '$latex: وسوم لم تُغلق $stack');
  expect(xml, isNot(contains(r'\')), reason: '$latex: كود LaTeX في المخرج');
  expect(xml, isNot(contains(r'$')), reason: '$latex: علامة دولار في المخرج');
  for (final text in _mathTexts(xml)) {
    expect(text, isNotEmpty, reason: '$latex: جريان فارغ');
  }
}

String _zone(String latex) {
  final xml = OmmlFromEquation.mathZoneXml(latex, fontSizePt: 11);
  expect(xml, isNotNull, reason: '$latex: كان يُمثَّل بُنيةً');
  // ignore: avoid_print
  print('OMML <$latex> → $xml');
  return xml!;
}

/// الصيغ التي يجب أن تُمثَّل كلها، مع محارفها المتوقعة بالترتيب.
const Map<String, String> _supported = <String, String>{
  r'5^{2}': '52',
  r'x_{1}': 'x1',
  r'{x_{1}}^{2}': 'x12',
  r'\sqrt{66}': '66',
  r'\sqrt[3]{x}': '3x',
  r'\frac{5}{8}': '58',
  r'\frac{\frac{1}{2}}{3}': '123',
  r'\vec{F}': 'F',
  r'\hat{x}': 'x',
  r'\overline{AB}': 'AB',
  r'\frac{a}{b} + \frac{c}{d}': 'ab + cd',
  r'\left(\frac{1}{2}\right)': '12',
  r'\left\{\frac{a}{b}\right\}': 'ab',
  r'\left|x\right|': 'x',
  r'\left(x\right]': 'x',
  r'\left(2x+1\right.': '2x+1',
  r'\frac{22}{7} \approx 3.14': '227 ≈ 3.14',
  r'a \ne b': 'a ≠ b',
  r'\pm\sqrt{2}': '±2',
  r'\int_{0}^{1} x\,dx': '01 x dx',
  r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}': '-b ± b2-4ac2a',
  '5²': '52',
  'x₁': 'x1',
  r'\frac{5}{8} \text{cm}': '58 cm',
  r'\sin 30^\circ': 'sin 30∘',
};

void main() {
  group('مُصدِّر OMML', () {
    test('كل صيغة يُمثّلها المحرر المرئي تخرج منطقة رياضيات نظيفة', () {
      _supported.forEach((latex, expectedText) {
        final xml = _zone(latex);
        expect(xml.startsWith('<m:oMath>') && xml.endsWith('</m:oMath>'), isTrue,
            reason: latex);
        _expectCleanMathZone(xml, latex: latex);
        expect(_mathTexts(xml).join(), expectedText, reason: latex);
      });
    });

    test('العقد البنيوية الصحيحة لكل شكل', () {
      expect(_zone(r'\frac{5}{8}'), contains('<m:f>'));
      expect(_zone(r'\frac{5}{8}'), contains('<m:num>'));
      expect(_zone(r'\sqrt{66}'), contains('<m:rad>'));
      expect(_zone(r'\sqrt{66}'), contains('<m:degHide m:val="1"/>'));
      expect(_zone(r'\sqrt[3]{x}'), contains('<m:deg>'));
      expect(_zone('x_{1}'), contains('<m:sSub>'));
      expect(_zone(r'5^{2}'), contains('<m:sSup>'));
      expect(_zone(r'{x_{1}}^{2}'), contains('<m:sSubSup>'));
      expect(_zone(r'\vec{F}'), contains('<m:acc>'));
      expect(_zone(r'\hat{x}'), contains('<m:acc>'));
      expect(_zone(r'\overline{AB}'), contains('<m:bar>'));
      expect(_zone(r'\left(x\right)'), contains('<m:d>'));
      expect(_zone(r'\left\{x\right\}'), contains('<m:begChr m:val="{"/>'));
      expect(_zone(r'\left\{x\right\}'), contains('<m:endChr m:val="}"/>'));
      // أقواس عادية بلا \left: محرفٌ كما في المعاينة، لا بنية متمددة.
      final plain = _zone('(x+y)');
      expect(plain, isNot(contains('<m:d>')));
      expect(plain, contains('('));
    });

    test('العامل الكبير: m:nary بحدوده، والأخوة بعد المنطقة', () {
      final sum = _zone(r'\sum_{i=1}^{n} i');
      expect(sum, contains('<m:nary>'));
      expect(sum, contains('<m:chr m:val="∑"/>'));
      expect(sum, contains('<m:limLoc m:val="subSup"/>'));
      expect(sum, contains('<m:subHide m:val="0"/>'));
      expect(sum, contains('<m:supHide m:val="0"/>'));
      expect(sum, contains('<m:e/></m:nary>'));
      // المُعامِل أخوٌ بعد المنطقة لا ابنٌ داخلها: هكذا تكتبه Word نفسها عند
      // إدخال \sum_{i=1}^{n} i يدوياً — لا فرق في التقدم الأفقي للسطر.
      expect(sum, contains('</m:nary><m:r>'));
      expect(sum, endsWith(' i</m:t></m:r></m:oMath>'));

      // معادلة بلا حدّين أصلاً: لا m:nary، فالعامل محرفٌ عاديٌّ في التسلسل.
      expect(_zone(r'\int x dx'), isNot(contains('<m:nary>')));

      // حدٌّ واحد فقط: العنصر الناقص يُعلَّم مخفياً ولا يُترك وسماً يتيماً.
      final half = _zone(r'\int_{0} x dx');
      expect(half, contains('<m:sub>'));
      expect(half, contains('<m:supHide m:val="1"/>'));
      expect(half, contains('<m:subHide m:val="0"/>'));

      // معادلة عرض (سطر مستقل): الحدود فوق وتحته.
      final display = OmmlFromEquation.mathParagraphXml(
        r'\sum_{i=1}^{n} i',
        fontSizePt: 14,
      );
      expect(display, contains('<m:limLoc m:val="undOvr"/>'));
      expect(display, contains('<m:oMathPara>'));
      expect(display, contains('<m:jc m:val="center"/>'));
    });

    test('حدّ واحد لأسْم دالة يصبح m:limLow، والأسماء قائمة', () {
      final limit = _zone(r'\lim_{x} x');
      expect(limit, contains('<m:limLow>'));
      expect(limit, contains('<m:sty m:val="p"/>'));
      expect(_zone(r'\sin 30'), isNot(contains('<m:limLow>')));
      expect(_zone(r'\sin 30'), contains('<m:sty m:val="p"/>'));
    });

    test('الحجم والتنسيق يورَّathan من الفقرة، بخط رياضيات مصرّح به', () {
      final xml = OmmlFromEquation.mathZoneXml(
        'x',
        fontSizePt: 11,
        extraRunProperties: '<w:b/><w:color w:val="C00000"/>',
      )!;
      expect(xml, contains('<w:sz w:val="22"/>'));
      expect(xml, contains('<w:szCs w:val="22"/>'));
      expect(xml, contains('<w:b/><w:color w:val="C00000"/>'));
      expect(xml, contains('w:ascii="Cambria Math"'));
      // لا rtl في جريان الرياضيات مهما كان الفقرة عربية.
      expect(xml, isNot(contains('rtl')));
      // حجم صغير جداً أو كبير جداً يُحصر في المدى الذي تقبله Word.
      expect(OmmlFromEquation.mathZoneXml('x', fontSizePt: 1),
          contains('<w:sz w:val="8"/>'));
      expect(OmmlFromEquation.mathZoneXml('x', fontSizePt: 900),
          contains('<w:sz w:val="144"/>'));
    });

    test('ما لا يُمثَّل يعيد null ولا يرمي: المصفوفات والأوامر الناقصة', () {
      for (final latex in <String>[
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
        r'\begin{cases}1&x>0\\-1&x<0\end{cases}',
        r'\left(x',
        r'x & y',
        r'a \\ b',
      ]) {
        expect(OmmlFromEquation.mathZoneXml(latex, fontSizePt: 11), isNull,
            reason: '$latex كان يجب أن يُرفض');
      }
      // وطرقات تالفة لا تُسقط شيئاً: null دائماً بدل الاستثناء.
      for (final broken in <String>[
        '',
        '   ',
        '{}',
        '}}{{{',
        r'\frac{',
        r'\sqrt',
        r'\text{',
        '&',
        r'\\',
        r'\left.\right.',
        '^',
        '_',
        r'\Bigl(1\Bigr)',
      ]) {
        expect(OmmlFromEquation.mathZoneXml(broken, fontSizePt: 11), isNull,
            reason: '$broken كان يجب أن يُرفض');
      }
    });

    test('الأساس المتّصل: ax² يرفع x وحدها، و 10² لا تفقد_one', () {
      expect(_mathTexts(_zone('ax^2')).join(), 'ax2');
      expect(_mathTexts(_zone('10^2')).join(), '102');
      expect(_mathTexts(_zone('x^2y')).join(), 'x2y');
      // وأمرٌ كامل يبقى وحدته واحدة: \alpha^2 يرفع ألفا كلها.
      final alpha = _zone(r'\alpha^2');
      expect(alpha, contains('<m:sSup>'));
      expect(_mathTexts(alpha).join(), 'α2');
    });

    test('محتوى لا يُفقد: صناديق المحرر الفارغة تبقى صناديق في Word', () {
      // `{}` فارغ يُكتب وسماً موجوداً بلا محتوى (Word تعرضه مربعاً متقطعاً).
      final empty = OmmlFromEquation.mathZoneXml(r'\frac{}{2}', fontSizePt: 11)!;
      expect(empty, contains('<m:num></m:num>'));
      expect(empty, contains('<m:den>'));
      final bare = OmmlFromEquation.mathZoneXml(r'^{2}', fontSizePt: 11)!;
      expect(bare, contains('<m:sSup>'));
      expect(bare, contains('<m:e></m:e>'));
    });

    test('الأوامر النصية والمسافات لا تخرج أكواداً', () {
      final texty = _zone(r'\mathrm{pH} + \operatorname{mod}');
      expect(texty, contains('<m:sty m:val="p"/>'));
      expect(_mathTexts(texty).join(), 'pH + mod');
      // أمر مسافة ← مسافة حقيقية، وأمر هروب ← محرفه.
      expect(_mathTexts(_zone(r'x \quad y')).join(), 'x    y');
      expect(_mathTexts(_zone(r'a\% b')).join(), 'a% b');
      expect(_mathTexts(_zone(r'x_{a\_b}')).join(), 'xa_b');
    });

    test('تغطية الرموز: كل أمر مسجَّل يخرج بُنيةً في Word بلا محرف ناقص', () {
      // حارس الخط الجديد — بديل «تغطية خط الرياضيات المتجه» المحذوف مع
      // نظامه: ما يستطيع المحرر إدخاله يجب أن يُمثَّل OMML. السقوط الفردي
      // إلى صورة مسموح، لكنه هنا يعني أن جدول الرموز والمُصدِّر افترقا.
      final commands = <String>[
        ...MathSymbols.glyphs.keys,
        ...MathSymbols.bigOperators.keys,
      ];
      final broken = <String>[];
      for (final command in commands) {
        final xml = OmmlFromEquation.mathZoneXml('\\$command', fontSizePt: 11);
        final display = MathSymbols.toDisplay('\\$command');
        final drawn = xml != null &&
            (xml.contains(display) ||
                // العوامل الكبيرة تُعلن محرفها في `m:chr` لا في `m:t`.
                xml.contains('m:chr m:val="$display"'));
        if (!drawn) {
          broken.add(command);
        }
      }
      expect(broken, isEmpty, reason: 'أوامر لا تُمثَّل بُنية: $broken');
    });

    test('العربية داخل الصيغة تبقى كما هي، بترتيبها في `m:t`', () {
      final arabic = _zone(r'\frac{\text{طول}}{\text{عرض}}');
      expect(_mathTexts(arabic), containsAllInOrder(<String>['طول', 'عرض']));
      _expectCleanMathZone(arabic, latex: 'عربي');
    });
  });
}
