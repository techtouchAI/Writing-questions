import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/quran_text.dart';

/// يبني آية موسومة برمزين تهريبيين صريحين (`U+FD3F` فتح ثم `U+FD3E` غلق)
/// بدل كتابة المحرفين حرفيَّين: كلاهما من صنف Bidi Neutral فتقلبهما المحرّرات
/// البصرية، ولهذا وقع أول تشغيل للاختبارات في فخ انعكاسهما. الرموز
/// التهريبية تجعل الترتيب المقصود قطعياً لا يقبل الالتباس.
String _verse(String text) => '\uFD3F$text\uFD3E';

void main() {
  group('QuranText', () {
    test('marker code units follow the Unicode open/close categories', () {
      // U+FD3F صنفه Ps (فتح) وهو القوس الفاتح، وU+FD3E صنفه Pe (إغلاق) وهو
      // الغالق — رغم أن اسميهما التاريخيين «ORNATE RIGHT/LEFT PARENTHESIS»
      // يشيران إلى جهة الظهور في الكتابة من اليمين إلى اليسار. هذا الاختبار
      // هو الحارس ضد إعادة قلبهما.
      expect(QuranText.openMarker, '\uFD3F');
      expect(QuranText.closeMarker, '\uFD3E');
      expect(QuranText.openMarkerCodeUnit, 0xFD3F);
      expect(QuranText.closeMarkerCodeUnit, 0xFD3E);
      expect(QuranText.openMarker.codeUnitAt(0), 0xFD3F);
      expect(QuranText.closeMarker.codeUnitAt(0), 0xFD3E);
      expect(QuranText.openMarker, isNot(QuranText.closeMarker));
    });

    test('detects the ornate Quranic markers', () {
      expect(QuranText.containsQuran('نص عادي بلا آيات'), isFalse);
      expect(QuranText.containsQuran('قال تعالى ${_verse('إنا أعطيناك الكوثر')}'), isTrue);
    });

    test('returns no segments for empty text', () {
      expect(QuranText.split(''), isEmpty);
    });

    test('keeps plain text as one plain segment', () {
      final segments = QuranText.split('اشرح مفهوم العدالة');
      expect(segments, <QuranSegment>[const QuranSegment.plain('اشرح مفهوم العدالة')]);
    });

    test('splits prefix, verse and suffix in drawing order', () {
      final segments = QuranText.split('قال تعالى ${_verse(' إنا أعطيناك الكوثر ')} فاحفظ الآية');
      expect(segments, hasLength(3));
      expect(segments[0], const QuranSegment.plain('قال تعالى '));
      expect(segments[1].isQuran, isTrue);
      expect(segments[1].text, _verse(' إنا أعطيناك الكوثر '));
      expect(segments[1].text.codeUnitAt(0), QuranText.openMarkerCodeUnit);
      expect(segments[1].text.codeUnitAt(segments[1].text.length - 1),
          QuranText.closeMarkerCodeUnit);
      expect(segments[2], const QuranSegment.plain(' فاحفظ الآية'));
    });

    test('supports two verses in the same branch text', () {
      final segments = QuranText.split('${_verse(' الأولى ')} ثم ${_verse(' الثانية ')}');
      expect(segments.where((segment) => segment.isQuran), hasLength(2));
      expect(segments.last, const QuranSegment.plain(' '));
    });

    test('treats an unterminated verse as quranic until the end of the text', () {
      // حالة الكتابة الحيّة: أُدخل قوس البداية ولم يُغلق بعد.
      final segments = QuranText.split('قال تعالى ${_verse(' ولم يُغلق')}');
      expect(segments, hasLength(2));
      expect(segments.last.isQuran, isTrue);
      expect(segments.last.text, _verse(' ولم يُغلق'));
    });

    test('isStandaloneVerse is true only for a single verse covering the text', () {
      expect(QuranText.isStandaloneVerse(_verse(' إنا أعطيناك الكوثر ')), isTrue);
      expect(QuranText.isStandaloneVerse('   ${_verse(' إنا أعطيناك الكوثر ')}  '), isTrue);
      expect(QuranText.isStandaloneVerse('مقدمة ${_verse(' إنا أعطيناك الكوثر ')}'), isFalse);
      expect(QuranText.isStandaloneVerse('${_verse(' الأولى ')} ${_verse(' الثانية ')}'), isFalse);
      expect(QuranText.isStandaloneVerse('نص عادي'), isFalse);
      expect(QuranText.isStandaloneVerse('   '), isFalse);
    });

    test('wrap adds both ornate parentheses and split round-trips it', () {
      final wrapped = QuranText.wrap('سبحان الله');
      expect(wrapped, _verse('سبحان الله'));
      expect(wrapped.codeUnitAt(0), QuranText.openMarkerCodeUnit);
      expect(wrapped.codeUnitAt(wrapped.length - 1), QuranText.closeMarkerCodeUnit);
      final segments = QuranText.split(wrapped);
      expect(segments, hasLength(1));
      expect(segments.single.isQuran, isTrue);
      expect(segments.single.text, wrapped);
      expect(QuranText.isStandaloneVerse(wrapped), isTrue);
    });
  });
}
