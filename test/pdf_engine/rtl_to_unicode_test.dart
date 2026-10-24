// قناة `/ToUnicode` لأسطر العربية: فصل **الرسم** عن **الاستخراج**.
//
// العَطل الذي يقيسه هذا الملف: محرك PDF يكتب المحارف بعد التشكيل (presentation
// forms) كي تُرسم الحروف متصلة، وكان يكتب الشكل نفسه في `/ToUnicode` أيضًا.
// فالنتيجة أن البحث والنسخ في أي قارئ PDF يخرجان «ﻟﻠﻌﺎﻡ» بدل «للعام»، ولا
// يطابقان أي بحث. الإصلاح يمرّ في قناة واحدة:
//
//   * `glyphText` = ما يُرسم (أشكال العرض) — لم يُلمس، فالحبر والحبر المتقدّم
//     وخطوط التقسيم الفرعي كلها كما كانت.
//   * `toUnicodeChars` = ما يُستخرج: حروف معجمية، واحد لكل شكل، وقد يكون
//     الشكل الواحد حرفين (رابطة لام-ألف) أو كلمة (روابط FDFx).
//
// الاختبارات هنا تقيس الشارح نفسه (لا ملف PDF)، وتثبت ثلاثة أمور: الجدول لا
// يُخرج شكل عرض أبدًا، والرسم يبقى مشكّلًا، والنصّ المستخرَج يساوي الكلمة
// المنطقية بترتيبها البصري — بحروفها كاملة بما فيها رابطة لام-ألف.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

/// الشكل البصري لكلمة عربية خالصة: عكس محارف الكلمة المنطقية.
///
/// مكتوب هنا بقواعد الحروف مباشرةً (لا عبر الشارح) كي تكون المقارنة مستقلة عن
/// الشيفرة المُختبَرة.
String _visualOrder(String logical) =>
    String.fromCharCodes(logical.runes.toList().reversed);

bool _isPresentationForm(int rune) =>
    (rune >= 0xFB50 && rune <= 0xFDFF) || (rune >= 0xFE70 && rune <= 0xFEFF);

void main() {
  group('جدول أشكال العرض ↔ الحروف المعجمية', () {
    test('كل قيمة حروف معجمية فقط (لا شكل عرض داخل قيمة)', () {
      expect(kArabicPresentationFormBase, isNotEmpty);
      for (final entry in kArabicPresentationFormBase.entries) {
        expect(_isPresentationForm(entry.key), isTrue,
            reason: 'المفتاح ${entry.key.toRadixString(16)} ليس شكل عرض.');
        expect(entry.value, isNotEmpty,
            reason: 'المفتاح ${entry.key.toRadixString(16)} يُفكّ إلى فراغ.');
        for (final rune in entry.value.runes) {
          expect(_isPresentationForm(rune), isFalse,
              reason: 'قيمة ${entry.key.toRadixString(16)} تحوي شكل عرض '
                  '${rune.toRadixString(16)} — التفكيك غير مكتمل.');
        }
      }
    });

    test('رابطة لام-ألف تُفكّ إلى حرفين لا حرف واحد', () {
      // U+FEFB لام-ألف معزولة، U+FEFC نهائية.
      expect(arabicBaseLetters(0xFEFB).runes.toList(), <int>[0x0644, 0x0627]);
      expect(arabicBaseLetters(0xFEFC).runes.toList(), <int>[0x0644, 0x0627]);
      // وألف بهمزة: FEF7/FEF8.
      expect(arabicBaseLetters(0xFEF7).runes.toList(), <int>[0x0644, 0x0623]);
    });

    test('الحرف المعجمي واللاتيني يُعاد كما هو', () {
      expect(arabicBaseLetters(0x0644), '\u0644');
      expect(arabicBaseLetters(0x0041), 'A');
      expect(isArabicPresentationForm(0x0644), isFalse);
    });
  });

  group('shapeRtlRun: الرسم مشكّل والاستخراج معجمي', () {
    test('كلمة عربية: أشكال عرض في القناة المرسومة وحروف أساسية في المستخرجة',
        () {
      const word = 'الرحمن';
      final run = shapeRtlRun(word);

      expect(run.glyphText.runes, isNotEmpty);
      for (final rune in run.glyphText.runes) {
        expect(rune, inInclusiveRange(0xFE70, 0xFEFF),
            reason: 'قناة الرسم يجب أن تبقى أشكال عرض (تشكيل): '
                '${rune.toRadixString(16)} في «${run.glyphText}»');
      }

      expect(run.toUnicodeChars, hasLength(run.glyphText.runes.length),
          reason: 'مدخل /ToUnicode واحد لكل شكل مرسوم.');
      for (final entry in run.toUnicodeChars) {
        expect(entry, isNotEmpty);
        for (final rune in entry.runes) {
          expect(isArabicPresentationForm(rune), isFalse,
              reason: 'قناة الاستخراج تحمل شكل عرض: $entry');
        }
      }

      // النصّ المستخرَج = الكلمة المنطقية بترتيبها البصري، لا شكلها المشكَّل.
      expect(run.toUnicodeText, _visualOrder(word));
    });

    test('رابطة لام-ألف: الاستخراج يعيد الحرفين كاملين', () {
      // «المعادلات» تحوي لامًا بعدها ألف — الشارح يجمعهما في شكل واحد.
      const word = 'المعادلات';
      final run = shapeRtlRun(word);
      expect(run.toUnicodeText, _visualOrder(word),
          reason: 'حرف ضائع من رابطة لام-ألف يعني نصًّا غير قابل للبحث: '
              '«${run.toUnicodeText}» مقابل «${_visualOrder(word)}»');
      // والدليل على أن الرابطة وقعت فعلًا: مدخل بطول حرفين لشكل واحد.
      expect(
        run.toUnicodeChars.where((entry) => entry.runes.length > 1),
        isNotEmpty,
        reason: 'لم تُفكّ أي رابطة: ${run.toUnicodeChars}',
      );
    });

    test('القوس المقلوب: الشكل مقلوب والنصّ المستخرَج منطقي', () {
      final run = shapeRtlRun('أ )');
      // UAX #9 Rule L4 يقلب شكل القوس في الرسم…
      expect(run.glyphText.contains('('), isTrue,
          reason: 'القوس المرسوم يجب أن يكون مقلوبًا: ${run.glyphText}');
      // …وقناة الاستخراج تحفظ القوس المنطقي نفسه.
      expect(run.toUnicodeText.contains(')'), isTrue);
      expect(run.toUnicodeText.contains('('), isFalse);
    });

    test('الأرقام لا تتغيّر في قناة الاستخراج', () {
      final run = shapeRtlRun('2026/2027');
      expect(run.toUnicodeText, '2026/2027');
    });

    test('النصّ الفارغ لا ينتج مداخل', () {
      final run = shapeRtlRun('');
      expect(run.glyphText, isEmpty);
      expect(run.toUnicodeChars, isEmpty);
      expect(run.toUnicodeText, isEmpty);
    });
  });
}
