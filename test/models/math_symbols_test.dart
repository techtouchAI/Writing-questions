// حراس جدول الرموز أنفسهم — بعد حذف محرك الـ SVG المتجه بقيت هذه الخصائص
// صحيحة على النموذج وحده (محارف ↔ أوامر، تطبيع المكافئات، تهريب المحارف
// الخاصة)، وتنتقل هنا من `test/pdf_engine/math_symbol_coverage_test.dart`.
// مطابقة «هل يُرسم المحرف؟» صارت سؤال المحرك الواحد (flutter_math_fork)
// و`OmmlFromEquation`، فتُغطّى هناك لا هنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/math_symbols.dart';

void main() {
  group('جدول الرموز: محرف ↔ أمر', () {
    test('كل أمر مسجَّل له محرف مرئي، والاسم المجهول يعيد نفسه', () {
      for (final entry in MathSymbols.glyphs.entries) {
        expect(MathSymbols.glyphFor('\\${entry.key}'), entry.value,
            reason: entry.key);
      }
      for (final entry in MathSymbols.bigOperators.entries) {
        expect(MathSymbols.glyphFor('\\${entry.key}'), entry.value,
            reason: entry.key);
      }
      // أمر لا يعرفه الجدول يبقى كما كُتب: لا يختفي ولا ينقلب نصاً فارغاً.
      expect(MathSymbols.toDisplay(r'\unknowncommand'), r'\unknowncommand');
      expect(MathSymbols.glyphFor(r'\unknowncommand'), isNull);
    });

    test('محارف الهروب تُقرأ كما كُتبت (`\\{` ← `{` …)', () {
      for (final entry in MathSymbols.escapedCharacters.entries) {
        expect(MathSymbols.toDisplay(entry.key), entry.value,
            reason: entry.key);
      }
    });

    test('الأمر الآمن فقط يُستعمل بديلاً للمحرف، والمحرر يرجع إليه', () {
      for (final entry in MathSymbols.glyphs.entries) {
        final glyph = entry.value;
        if (glyph.length != 1) {
          continue;
        }
        final command = MathSymbols.commandForGlyph(glyph);
        if (MathSymbols.latexSafe.contains(entry.key)) {
          expect(command, isNotNull, reason: entry.key);
          expect(MathSymbols.glyphFor(command!), glyph, reason: entry.key);
        } else if (command != null) {
          // غير الآمن لا يجوز أن يتسلل إلى الشاشة: إما بلا أمر وإما آمن.
          expect(MathSymbols.latexSafe, contains(command.substring(1)),
              reason: entry.key);
        }
      }
    });

    test('ما يكتبه المدرس محرفاً يرجع LaTeX لا يفقد شيئاً', () {
      for (final glyph in <String>{
        ...MathSymbols.glyphs.values,
        ...MathSymbols.bigOperators.values,
      }) {
        final single = glyph.length == 1 ? glyph : null;
        if (single == null) {
          continue;
        }
        final latex = MathSymbols.toLatex(single);
        expect(latex, isNotEmpty, reason: glyph);
        // إما بقي محرفاً كما هو، وإما صار أمراً معروفاً يرجع إليه.
        if (latex == single) {
          continue;
        }
        expect(MathSymbols.glyphFor(latex), single, reason: '$glyph ← $latex');
      }
    });
  });

  group('تطبيع المكافئات', () {
    test('كل مكافئ يُطبَّع إلى صورته القياسية بلا فقدان ولا إضافة', () {
      for (final entry in MathSymbols.aliases.entries) {
        expect(MathSymbols.canonicalize(entry.key), entry.value,
            reason: entry.key);
        // الهدف محرف مرئي معروف (أو محرف ascii عادي) — لا سلسلة مجهولة.
        expect(entry.value, isNotEmpty, reason: entry.key);
      }
    });

    test('محارف الأسس الجاهزة تتحول بنية LaTeX ثم تُقرأ من جديد', () {
      // `5²` ← `5^{2}` و`x₁` ← `x_{1}`: خاصية المحرر والـ OMML معاً.
      expect(MathSymbols.canonicalize('5²'), r'5^{2}');
      expect(MathSymbols.canonicalize('x₁'), r'x_{1}');
      expect(MathSymbols.canonicalize('{x₁}²'), r'{x_{1}}^{2}');
    });

    test('المحارف الخاصة تُهرَّب فلا تفسد بنية الصيغة', () {
      expect(MathSymbols.toLatex('a{b}c%d&e#f\$g'),
          r'a\{b\}c\%d\&e\#f\$g');
    });

    test('كل محرف عرض مسجَّل يبقى ممثلاً بعد التطبيع', () {
      final lost = <String>[];
      for (final char in MathSymbols.allDisplayGlyphs()) {
        final folded = MathSymbols.canonicalize(char);
        if (folded.isEmpty) {
          lost.add(char);
        }
      }
      expect(lost, isEmpty, reason: 'محرف يطبَّع إلى فراغ: $lost');
    });
  });
}
