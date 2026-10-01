// حراسة التغطية: كل رمز يستطيع التطبيق إدخاله أو تخزينه يجب أن يرسمه خط
// الرياضيات المتجه — فلا تسقط أي معادلة إلى بديل نصي في PDF أو Word بسبب
// محرف ناقص (وهو خلل كان يُكتشف بعد التصدير لا قبله).
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/math_symbols.dart';
import 'package:writing_questions_app/pdf_engine/latex/latex_svg_renderer.dart';
import 'package:writing_questions_app/pdf_engine/latex/math_stroke_font.dart';

void main() {
  group('تغطية خط الرياضيات المتجه', () {
    test('every display glyph in the canonical registry is drawable', () {
      final missing = MathSymbols.allDisplayGlyphs()
          .where((char) => MathStrokeFont.strokesOf(char) == null)
          .toList(growable: false);
      expect(missing, isEmpty, reason: 'محارف مسجلة بلا رسم متجه: $missing');
    });

    test('every registered LaTeX command renders as vector math', () {
      final commands = <String>[
        ...MathSymbols.glyphs.keys,
        ...MathSymbols.bigOperators.keys,
      ];
      final broken = <String>[];
      for (final command in commands) {
        if (LatexSvgRenderer.tryToSvg('\\$command') == null) {
          broken.add(command);
        }
      }
      expect(broken, isEmpty, reason: 'أوامر تسقط إلى بديل نصي: $broken');
    });

    test('glyph to command conversion stays inside the safe command set', () {
      for (final entry in MathSymbols.glyphs.entries) {
        final glyph = entry.value;
        if (glyph.length != 1) {
          continue;
        }
        final command = MathSymbols.commandForGlyph(glyph);
        if (MathSymbols.latexSafe.contains(entry.key)) {
          expect(command, isNotNull, reason: entry.key);
          expect(MathSymbols.glyphFor(command!), glyph, reason: entry.key);
        } else {
          // غير الآمن في الشاشة يبقى محرفاً: والمحرف مرسوم متجهًا على كل حال.
          expect(MathStrokeFont.strokesOf(glyph), isNotNull, reason: entry.key);
        }
      }
    });

    test('alias targets are always canonical drawable characters', () {
      for (final target in MathSymbols.aliases.values) {
        for (final char in target.split('')) {
          if (char.trim().isEmpty) {
            continue;
          }
          expect(
            MathStrokeFont.strokesOf(char),
            isNotNull,
            reason: 'هدف التطبيع «$char» غير مرسوم',
          );
        }
      }
    });

    test('the coverage probe reports exactly the unsupported characters', () {
      expect(LatexSvgRenderer.unsupportedCharacters(r'\frac{a}{b} + ٥'), isEmpty);
      expect(
        LatexSvgRenderer.unsupportedCharacters('نص'),
        containsAll(<String>['ن', 'ص']),
      );
      expect(LatexSvgRenderer.canRender(r'x^{2} = \frac{1}{2}'), isTrue);
      expect(LatexSvgRenderer.canRender('معادلة عربية'), isFalse);
    });
  });
}
