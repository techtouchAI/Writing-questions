// انحدار: اتجاه الأقواس في النص العربي — إثبات مسار البيانات.
//
// النص يُخزَّن بالترتيب **المنطقي** دائماً (المحرر ← النموذج ←
// المستند ← المعاينة)، ولا يُحوَّل إلى ترتيب بصري إلا عند
// إصدار PDF (CanonicalText) — وهناك فقط تُكمل شيفرة BiDi
// قاعدتَي L2/L4 ضد اتجاه الجريان المحلول مسبقاً. فالمعنى
// والترتيب المقصودان ثابتان في التخزين، والمعاينة (Flutter
// UBA+L4) وPDF وWord (لقطة المعاينة) يتفقون على الرسم.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show logicalToVisual;
import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';

void main() {
  group('Arabic brackets: logical storage, visual emission', () {
    test('the logical order is preserved through parsing', () {
      for (final source in <String>[
        'أ )',
        'أ (',
        '(أ)',
        '( أ )',
        'نص (عربي) نص',
        'اقرأ (٢٠ درجة) ثم أجب',
        'سؤال (أ) مقابل (ب) هنا',
        'عربي (123) lat',
      ]) {
        final content = RichContent.parse(source);
        // لا عكس ولا تحويل بصري في التخزين — النص كما كُتب.
        expect(content.plainText, source,
            reason: 'النص المنطقي يجب أن يبقى كما كُتب: $source');
      }
    });

    test('a neutral-only RTL run is mirrored (L4) and reordered (L2)',
        () {
      // كلمة قوس منعزلة بلا محرف قوي: خوارزميتها المعزولة
      // تُسقط أساسها إلى LTR، فكانت تُرسم غير مرآوة. الإصدار
      // يكمل L2/L4 ضد اتجاه الجريان المحلول RTL.
      expect(shapeRtlRun(')'), '(');
      expect(shapeRtlRun('('), ')');
      expect(shapeRtlRun('(('), '))');
      expect(shapeRtlRun(')('), ')(');
      expect(shapeRtlRun('['), ']');
      expect(shapeRtlRun('{'), '}');
      expect(shapeRtlRun('<'), '>');
      expect(shapeRtlRun('«'), '»');
    });

    test('a run with a strong character keeps logicalToVisual', () {
      // كلمة تحمل محرفاً قوياً RTL تحسم أساسها الاتجاهي
      // بنفسها حتى معزولة — فلا يحتمل الحرف الأخير منها
      // سوى ما فعلته logicalToVisual أصلاً (لا مراوة مضاعفة).
      for (final word in <String>['أ)', 'أ(', '(أ)', 'عِلْمًا']) {
        expect(shapeRtlRun(word), logicalToVisual(word),
            reason: 'الكلمة «$word» تحمل محرفاً قوياً');
      }
      // وهذا الإصدار القائم يراو القوس فعلاً ويشكّل الألف
      // معزولة (U+FE83) — أرضية UBA كاملة: «أ)» تُرسم
      // «(ﺃ» و«(أ)» تُرسم «(ﺃ)».
      expect(shapeRtlRun('أ)'), '(ﺃ');
      expect(shapeRtlRun('(أ)'), '(ﺃ)');
    });

    test('a run with a digit keeps logicalToVisual (no reversal)', () {
      // الأرقام تُقرأ بالترتيب — لا يعكسها الإصلاح ولا يُراوها.
      for (final word in <String>['١٢٣', '(١)', '١-', '20']) {
        expect(shapeRtlRun(word), logicalToVisual(word),
            reason: 'الكلمة «$word» تحمل رقماً');
      }
    });

    test('nested brackets ride the full UBA (strong-RTL path)', () {
      // أقواس متداخلة داخل كلام عربي: الجريان يحمل محرفاً
      // قوياً فيمرّ بـ logicalToVisual (خوارزمية كاملة لا
      // يتغيرها الإصلاح)، فتبقى أزواجها متداخلة صحيحة.
      for (final word in <String>[
        '(أ(ب))',
        '((أ))',
        'نص(عربي)',
        '[أ{ب}ج]',
      ]) {
        expect(shapeRtlRun(word), logicalToVisual(word),
            reason: 'الكلمة «$word» تحمل محرفاً قوياً وأقواساً متداخلة');
      }
      // وأقواس محايدة صرفة متداخلة تُراوى كاملة
      // (L2 عكس ثم L4 مراوة): «([{» تُرسم «}])».
      expect(shapeRtlRun('([{'), '}])');
      expect(shapeRtlRun('(('), '))');
    });

    test('brackets around math symbols stay LTR islands', () {
      // قوس حول رمز/تعبير لاتيني: الجريان كله LTR فلا
      // مراوة ولا عكس — كما في المعاينة.
      expect(shapeRtlRun('(x+y)'), logicalToVisual('(x+y)'));
      expect(shapeRtlRun('√(x)'), logicalToVisual('√(x)'));
    });

    test('Latin and equation text is untouched by the RTL path', () {
      // جريان LTR لا يمرّ بالتشكيل أصلاً (rtl=false → خام)،
      // وجريان RTL يحمل لاتينياً يبقى كما كان بايتاً بايتاً.
      for (final word in <String>['STA1', 'x+1', 'Set A', 'sqrt']) {
        expect(shapeRtlRun(word), logicalToVisual(word),
            reason: 'الكلمة اللاتينية «$word»');
      }
    });
  });
}
