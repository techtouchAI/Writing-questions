/// مقاطع النص العلمي: فصل النص العادي عن صيغ LaTeX ($...$ سطرية، $$...$$ منفردة).
///
/// تُستخدم هذه الوحدة **بشكل مشترك** بين لوحة التحرير التفاعلية ومحرك
/// الـ PDF لضمان مطابقة 1:1 — نفس منطق القطع في الواجهة والطباعة.
abstract final class TexContent {
  static final RegExp _blockPattern = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
  static final RegExp _inlinePattern = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true);

  /// يهرّب علامات الدولار الحرفية في نص عادي (`$` ← `\$`) كي لا يبدأ
  /// محتواه صيغةً عند التخزين. العرض يعيدها دولاراً عادياً بلا أي شرطة مائلة.
  static String escapeLiteral(String text) => text.replaceAll(r'$', r'\$');

  /// هل يحتوي النص صيغ LaTeX قابلة للعرض كمعادلات؟
  ///
  /// تُطبَّع أولاً علامات الدولار الحرفية (`\$`) كي لا تُحسب صيغةً — تماماً
  /// كما في [split]، فيتطابق الفحص مع القطع دائماً.
  static bool containsMath(String source) {
    final normalized = source.replaceAll(r'\$', '\u0000');
    return _blockPattern.hasMatch(normalized) ||
        _inlinePattern.hasMatch(normalized);
  }

  /// يقسم [source] إلى مقاطع نص/معادلات بالترتيب نفسه تظهر في الورقة.
  ///
  /// تُعاد حدود المصدر إلى جانب كل مقطع من محلّل الصيغ المشترك نفسه؛ بذلك
  /// لا تعيد المعاينة أو hit testing تخمين موضع المقطع من نصه بعد إسقاط
  /// محددات LaTeX أو تهريب الدولار الحرفي.
  static List<TexSegment> split(String source) {
    if (source.isEmpty) return const <TexSegment>[];
    final spans = findSpans(source);
    if (spans.isEmpty) {
      final plain = _decodePlainRange(source, 0, source.length);
      return <TexSegment>[
        TexSegment.plain(
          plain.text,
          startOffset: 0,
          endOffset: source.length,
          sourceOffsets: plain.sourceOffsets,
        ),
      ];
    }

    final segments = <TexSegment>[];
    var cursor = 0;
    for (final span in spans) {
      if (span.start > cursor) {
        final plain = _decodePlainRange(source, cursor, span.start);
        if (plain.text.isNotEmpty) {
          segments.add(
            TexSegment.plain(
              plain.text,
              startOffset: cursor,
              endOffset: span.start,
              sourceOffsets: plain.sourceOffsets,
            ),
          );
        }
      }
      segments.add(
        TexSegment.math(
          span.latex,
          isBlock: span.isBlock,
          startOffset: span.start,
          endOffset: span.end,
        ),
      );
      cursor = span.end;
    }
    if (cursor < source.length) {
      final plain = _decodePlainRange(source, cursor, source.length);
      if (plain.text.isNotEmpty) {
        segments.add(
          TexSegment.plain(
            plain.text,
            startOffset: cursor,
            endOffset: source.length,
            sourceOffsets: plain.sourceOffsets,
          ),
        );
      }
    }
    return List<TexSegment>.unmodifiable(segments);
  }

  /// Decodes literal `\\$` using the same source grammar while retaining an
  /// insertion-point map for UTF-16 caret coordinates.
  static ({String text, List<int> sourceOffsets}) _decodePlainRange(
    String source,
    int start,
    int end,
  ) {
    final text = StringBuffer();
    final offsets = <int>[start];
    var cursor = start;
    while (cursor < end) {
      if (source[cursor] == '\\' &&
          cursor + 1 < end &&
          source[cursor + 1] == r'$') {
        text.write(r'$');
        cursor += 2;
        offsets.add(cursor);
      } else {
        text.writeCharCode(source.codeUnitAt(cursor));
        cursor++;
        offsets.add(cursor);
      }
    }
    return (text: text.toString(), sourceOffsets: List<int>.unmodifiable(offsets));
  }

  /// يحدد مواقع صيغ LaTeX داخل [source] بفهارسها الأصلية.
  ///
  /// يُستخدم لفتح معادلة موجودة في المحرر المرئي ثم استبدالها بنتيجته
  /// في الموضع نفسه تماماً — بنفس منطق [split] (الكتل أولاً ثم السطرية).
  static List<TexMathSpan> findSpans(String source) {
    // تطبيع يحفظ خريطة الفهارس: `\\$` حرفان يُستبدلان بمحرف واحد،
    // فيُحفظ لكل محرف مطبّع فهرسه الأصلي لاسترجاع المواضع بدقة.
    final normalizedBuffer = StringBuffer();
    final indexMap = <int>[];
    var cursor = 0;
    while (cursor < source.length) {
      if (source[cursor] == '\\' &&
          cursor + 1 < source.length &&
          source[cursor + 1] == r'$') {
        normalizedBuffer.write('\u0000');
        indexMap.add(cursor);
        cursor += 2;
      } else {
        normalizedBuffer.write(source[cursor]);
        indexMap.add(cursor);
        cursor += 1;
      }
    }
    final normalized = normalizedBuffer.toString();
    int toSource(int normalizedIndex) => normalizedIndex < indexMap.length
        ? indexMap[normalizedIndex]
        : source.length;

    final spans = <TexMathSpan>[];
    void collectInline(String gap, int base) {
      for (final match in _inlinePattern.allMatches(gap)) {
        spans.add(
          TexMathSpan(
            start: toSource(base + match.start),
            end: toSource(base + match.end),
            latex: (match.group(1) ?? '').replaceAll('\u0000', r'\$'),
            isBlock: false,
          ),
        );
      }
    }

    cursor = 0;
    for (final match in _blockPattern.allMatches(normalized)) {
      if (match.start > cursor) {
        collectInline(normalized.substring(cursor, match.start), cursor);
      }
      spans.add(
        TexMathSpan(
          start: toSource(match.start),
          end: toSource(match.end),
          latex: (match.group(1) ?? '').replaceAll('\u0000', r'\$'),
          isBlock: true,
        ),
      );
      cursor = match.end;
    }
    if (cursor < normalized.length) {
      collectInline(normalized.substring(cursor), cursor);
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    return spans;
  }
}

/// موقع صيغة LaTeX واحدة داخل النص الأصلي.
///
/// [start]/[end] يغطيان الصيغة مع علامات الدولارات، و[latex] هو جسم
/// الصيغة وحده — جاهز للتحميل في المحرر المرئي والاستبدال بعده.
class TexMathSpan {
  const TexMathSpan({
    required this.start,
    required this.end,
    required this.latex,
    required this.isBlock,
  });

  final int start;
  final int end;
  final String latex;
  final bool isBlock;

  @override
  bool operator ==(Object other) =>
      other is TexMathSpan &&
      other.start == start &&
      other.end == end &&
      other.latex == latex &&
      other.isBlock == isBlock;

  @override
  int get hashCode => Object.hash(start, end, latex, isBlock);
}

/// مقطع واحد من نص علمي: إما نص عادي أو صيغة LaTeX.
class TexSegment {
  const TexSegment.plain(
    this.text, {
    this.startOffset = 0,
    this.endOffset = 0,
    this.sourceOffsets = const <int>[],
  }) : isMath = false,
       isBlock = false;

  const TexSegment.math(
    this.text, {
    this.isBlock = false,
    this.startOffset = 0,
    this.endOffset = 0,
  }) : isMath = true,
       sourceOffsets = const <int>[];

  /// نص المقطع؛ لصيغ LaTeX يكون هو جسم الصيغة بدون علامات الدولارات.
  final String text;

  /// UTF-16 source interval in the original String passed to [TexContent.split].
  /// Math intervals include their dollar delimiters.
  final int startOffset;
  final int endOffset;

  /// For plain text, maps every displayed UTF-16 caret boundary to source.
  /// Literal escaped dollars consume two source units and one displayed unit.
  final List<int> sourceOffsets;

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
