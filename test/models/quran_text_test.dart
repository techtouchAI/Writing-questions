import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/quran_text.dart';

void main() {
  group('QuranText', () {
    test('detects the ornate Quranic markers', () {
      expect(QuranText.containsQuran('نص عادي بلا آيات'), isFalse);
      expect(QuranText.containsQuran('قال تعالى ﴿ إنا أعطيناك الكوثر ﴾'), isTrue);
    });

    test('returns no segments for empty text', () {
      expect(QuranText.split(''), isEmpty);
    });

    test('keeps plain text as one plain segment', () {
      final segments = QuranText.split('اشرح مفهوم العدالة');
      expect(segments, <QuranSegment>[const QuranSegment.plain('اشرح مفهوم العدالة')]);
    });

    test('splits prefix, verse and suffix in drawing order', () {
      final segments = QuranText.split('قال تعالى ﴿ إنا أعطيناك الكوثر ﴾ فاحفظ الآية');
      expect(segments, hasLength(3));
      expect(segments[0], const QuranSegment.plain('قال تعالى '));
      expect(segments[1].isQuran, isTrue);
      expect(segments[1].text, '﴿ إنا أعطيناك الكوثر ﴾');
      expect(segments[2], const QuranSegment.plain(' فاحفظ الآية'));
    });

    test('supports two verses in the same branch text', () {
      final segments = QuranText.split('﴿ الأولى ﴾ ثم ﴿ الثانية ﴾');
      expect(segments.where((segment) => segment.isQuran), hasLength(2));
      expect(segments.last, const QuranSegment.plain(' '));
    });

    test('treats an unterminated verse as quranic until the end of the text', () {
      // حالة الكتابة الحيّة: أُدخل قوس البداية ولم يُغلق بعد.
      final segments = QuranText.split('قال تعالى ﴿ ولم يُغلق');
      expect(segments, hasLength(2));
      expect(segments.last.isQuran, isTrue);
      expect(segments.last.text, '﴿ ولم يُغلق');
    });

    test('isStandaloneVerse is true only for a single verse covering the text', () {
      expect(QuranText.isStandaloneVerse('﴿ إنا أعطيناك الكوثر ﴾'), isTrue);
      expect(QuranText.isStandaloneVerse('   ﴿ إنا أعطيناك الكوثر ﴾  '), isTrue);
      expect(QuranText.isStandaloneVerse('مقدمة ﴿ إنا أعطيناك الكوثر ﴾'), isFalse);
      expect(QuranText.isStandaloneVerse('﴿ الأولى ﴾ ﴿ الثانية ﴾'), isFalse);
      expect(QuranText.isStandaloneVerse('نص عادي'), isFalse);
      expect(QuranText.isStandaloneVerse('   '), isFalse);
    });

    test('wrap adds both ornate parentheses and split round-trips it', () {
      final wrapped = QuranText.wrap('سبحان الله');
      expect(wrapped, '﴿سبحان الله﴾');
      final segments = QuranText.split(wrapped);
      expect(segments, hasLength(1));
      expect(segments.single.isQuran, isTrue);
      expect(segments.single.text, wrapped);
    });
  });
}
