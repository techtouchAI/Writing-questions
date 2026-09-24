/// مقاطع النص العلمي: فصل النص العادي عن صيغ LaTeX ($...$ سطرية، $$...$$ منفردة).
///
/// تُستخدم هذه الوحدة **بشكل مشترك** بين لوحة التحرير التفاعلية ومحرك
/// الـ PDF لضمان مطابقة 1:1 — نفس منطق القطع في الواجهة والطباعة.
abstract final class TexContent {
  static final RegExp _blockPattern = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
  static final RegExp _inlinePattern = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true);

  /// هل يحتوي النص صيغ LaTeX قابلة للعرض كمعادلات؟
  static bool containsMath(String source) {
    return _blockPattern.hasMatch(source) || _inlinePattern.hasMatch(source);
  }

  /// يقسم [source] إلى مقاطع نص/معادلات بالترتيب نفسه تظهر في الورقة.
  ///
  /// الشرطة المائلة `\$` تُعامَل كعلامة دولار حرفية ولا تبدأ صيغة.
  static List<TexSegment> split(String source) {
    final normalized = source.replaceAll(r'\$', '\u0000');
    final segments = <TexSegment>[];

    var cursor = 0;
    for (final match in _blockPattern.allMatches(normalized)) {
      if (match.start > cursor) {
        segments.addAll(_splitInline(normalized.substring(cursor, match.start)));
      }
      segments.add(TexSegment.math(match.group(1) ?? '', isBlock: true));
      cursor = match.end;
    }
    if (cursor < normalized.length) {
      segments.addAll(_splitInline(normalized.substring(cursor)));
    }

    return segments
        .map((segment) => segment.isMath
            ? TexSegment.math(segment.text, isBlock: segment.isBlock)
            : TexSegment.plain(segment.text.replaceAll('\u0000', r'\$')))
        .toList(growable: false);
  }

  static List<TexSegment> _splitInline(String source) {
    final segments = <TexSegment>[];
    var cursor = 0;
    for (final match in _inlinePattern.allMatches(source)) {
      if (match.start > cursor) {
        segments.add(TexSegment.plain(source.substring(cursor, match.start)));
      }
      segments.add(TexSegment.math(match.group(1) ?? ''));
      cursor = match.end;
    }
    if (cursor < source.length) {
      segments.add(TexSegment.plain(source.substring(cursor)));
    }
    return segments;
  }
}

/// مقطع واحد من نص علمي: إما نص عادي أو صيغة LaTeX.
class TexSegment {
  const TexSegment.plain(this.text) : isMath = false, isBlock = false;

  const TexSegment.math(this.text, {this.isBlock = false}) : isMath = true;

  /// نص المقطع؛ لصيغ LaTeX يكون هو جسم الصيغة بدون علامات الدولارات.
  final String text;

  /// هل هو صيغة LaTeX؟
  final bool isMath;

  /// هل الصيغة منفردة على سطر خاص ($$...$$)؟
  final bool isBlock;

  @override
  bool operator ==(Object other) =>
      other is TexSegment &&
      other.text == text &&
      other.isMath == isMath &&
      other.isBlock == isBlock;

  @override
  int get hashCode => Object.hash(text, isMath, isBlock);
}
