/// مقاطع النص القرآني: فصل آيات القرآن المحصورة بين ﴿ ... ﴾ عن بقية النص.
///
/// النموذج الوزاري للتربية الإسلامية يعتمد إبراز الآيات بخط قرآني مستقل
/// (خطوط المصحف)؛ ولذلك تُوسَم الآية على الورقة بالقوسين المزخرفين
/// `﴿ ... ﴾` (U+FD3E / U+FD3F) — كما في المصاحف — ويستهلك هذا القطعَ
/// **كلٌّ من** لوحة المعاينة ومحرك الـ PDF معاً، فيتطابق العرض والطباعة.
///
/// المنطق خالص بلا أي اعتماد على Flutter أو pdf ليكون قابلاً للاختبار وحده.
abstract final class QuranText {
  /// قوس بداية الآية: `﴿`.
  static const String openMarker = '\uFD3E';

  /// قوس نهاية الآية: `﴾`.
  static const String closeMarker = '\uFD3F';

  /// هل يحتوي [source] آية قرآنية موسومة؟
  static bool containsQuran(String source) => source.contains(openMarker);

  /// يقسم [source] إلى مقاطع نص عادي/آيات بالترتيب نفسه الذي يُعرض به.
  ///
  /// قاعدة الفصل: `﴿` تبدأ مقطعاً قرآنياً ينتهي عند أول `﴾` بعده (ضمناً
  /// القوسين)؛ وإن غاب القوس الختامي (أثناء الكتابة مثلاً) يُعتبر ما بعده
  /// قرآناً حتى نهاية النص. النص خارج القوسين يبقى نصاً عادياً كما هو.
  static List<QuranSegment> split(String source) {
    if (source.isEmpty) {
      return const <QuranSegment>[];
    }
    if (!containsQuran(source)) {
      return <QuranSegment>[QuranSegment.plain(source)];
    }

    final segments = <QuranSegment>[];
    var cursor = 0;
    while (cursor < source.length) {
      final open = source.indexOf(openMarker, cursor);
      if (open == -1) {
        final rest = source.substring(cursor);
        if (rest.isNotEmpty) {
          segments.add(QuranSegment.plain(rest));
        }
        break;
      }
      if (open > cursor) {
        segments.add(QuranSegment.plain(source.substring(cursor, open)));
      }
      final close = source.indexOf(closeMarker, open + openMarker.length);
      final end = close == -1 ? source.length : close + closeMarker.length;
      segments.add(QuranSegment.quran(source.substring(open, end)));
      cursor = end;
    }
    return segments;
  }

  /// هل النص كله آية واحدة قائمة بذاتها؟ (تُوسَّط على الورقة كما في المصحف)
  static bool isStandaloneVerse(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty || !containsQuran(trimmed)) {
      return false;
    }
    final segments = split(trimmed);
    return segments.length == 1 && segments.single.isQuran;
  }

  /// يوسم [verse] بالقوسين المزخرفين: `﴿verse﴾`.
  static String wrap(String verse) => '$openMarker$verse$closeMarker';
}

/// مقطع واحد من النص: نص عادي أو آية قرآنية (بقوسيها).
class QuranSegment {
  const QuranSegment.plain(this.text) : isQuran = false;

  const QuranSegment.quran(this.text) : isQuran = true;

  /// نص المقطع؛ في الآية يشمل القوسين المزخرفين.
  final String text;

  /// هل المقطع آية قرآنية؟
  final bool isQuran;

  @override
  bool operator ==(Object other) =>
      other is QuranSegment && other.text == text && other.isQuran == isQuran;

  @override
  int get hashCode => Object.hash(text, isQuran);

  @override
  String toString() => isQuran ? 'QuranSegment.quran($text)' : 'QuranSegment.plain($text)';
}
