// نطاقات تنسيق النص (Rich text spans) — طبقة **تخزين** لا طبقة عرض.
//
// لماذا نطاقات لا نمط للعنصر كاملًا؟ لأن المطلوب «تنسيق التحديد وحده»: تلوين
// كلمة، تسطير جملة، تعريض كلمة داخل سؤال بلا مساس بجيرانه. `PaperTextStyle`
// يبقى نمط العنصر الافتراضي (خط/حجم/محاذاة/لون افتراضي)، وهذه النطاقات تُطبَّق
// فوقه على المحارف التي يغطيها النطاق فقط.
//
// القواعد المثبَّتة هنا والقابلة للاختبار:
//  1. النطاقات **مطلقة** على نص الحقل كما هو مخزَّن (وحدات UTF-16)، مرتّبة،
//     غير متداخلة بعد [TextFormatSpans.normalize].
//  2. التطبيق الجزئي لا يمسّ ما خارج النطاق: تلوين كلمة داخل جملة يُبقي بقية
//     الجملة بلونها السابق، والتنسيق المتداخل (عريض داخل مائل) لا يُمحى.
//  3. لا «تنسيق للسؤال كله» عند غياب التحديد: عند مؤشر مطوي يُنسَّق **الجزء
//     (الكلمة) الذي عليه المؤشر**، وإن لم يكن هناك نص فلا عملية إطلاقًا.
//  4. لا متغيّر لكل زر: كل تنسيق = [TextFormatSpan] واحد يُمرَّر إلى
//     [TextFormatSpans.apply]، والناتج هو المخزَّن الجديد.

// نطاق تنسيق واحد فوق نص حقل: `[start, end)` بإزاحات UTF-16.
//
// كل الحقول الاختيارية: `null` تعني «لا رأي لهذا النطاق في هذه الخاصية»،
// فتبقى القيمة القادمة من النمط الافتراضي أو من نطاق آخر. هذا هو ما يجعل
// التنسيق المتداخل غير مدمّر: تعريض كلمة داخل جملة مائلة يكتب `italic: null`
// فلا يُلغي الميل.

class TextFormatSpan {
  const TextFormatSpan({
    required this.start,
    required this.end,
    this.bold,
    this.italic,
    this.underline,
    this.color,
  });

  final int start;
  final int end;

  final bool? bold;
  final bool? italic;
  final bool? underline;

  /// لون النص ARGB (`null` = لا رأي؛ أي لون العنصر).
  final int? color;

  bool get hasAttributes =>
      bold != null || italic != null || underline != null || color != null;

  /// نطاق صالح للتطبيق: فاصل غير فارغ (لا تنسيق لمؤشر بلا تحديد).
  bool get isApplicable => start >= 0 && end > start && hasAttributes;

  int get length => end - start;

  bool covers(int offset) => offset >= start && offset < end;

  TextFormatSpan copyWith({
    int? start,
    int? end,
    bool? Function()? bold,
    bool? Function()? italic,
    bool? Function()? underline,
    int? Function()? color,
  }) {
    return TextFormatSpan(
      start: start ?? this.start,
      end: end ?? this.end,
      bold: bold != null ? bold() : this.bold,
      italic: italic != null ? italic() : this.italic,
      underline: underline != null ? underline() : this.underline,
      color: color != null ? color() : this.color,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'start': start,
        'end': end,
        if (bold != null) 'bold': bold,
        if (italic != null) 'italic': italic,
        if (underline != null) 'underline': underline,
        if (color != null) 'color': color,
      };

  /// قراءة متسامحة: أي قيمة تالفة تُهمَل بدل إسقاط المستند.
  factory TextFormatSpan.fromMap(Map<String, dynamic> map) {
    return TextFormatSpan(
      start: _int(map['start']) ?? 0,
      end: _int(map['end']) ?? 0,
      bold: _bool(map['bold']),
      italic: _bool(map['italic']),
      underline: _bool(map['underline']),
      color: _color(map['color']),
    );
  }

  /// قائمة نطاقات من قيمة مخزَّنة؛ غير القائمة أو التالف يُتجاهل.
  static List<TextFormatSpan> listFromValue(Object? value) {
    if (value is! List) {
      return const <TextFormatSpan>[];
    }
    final spans = <TextFormatSpan>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      // الإزاحات مطلوبة؛ قيمة تالفة تعني نطاقًا مجهول الموضع فلا يُخمَّن.
      if (_int(map['start']) == null || _int(map['end']) == null) continue;
      final span = TextFormatSpan.fromMap(map);
      if (span.isApplicable) {
        spans.add(span);
      }
    }
    return List<TextFormatSpan>.unmodifiable(spans);
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse('$value');
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  static int? _color(Object? value) {
    if (value is int) {
      return value < 0 || value > 0xFFFFFFFF
          ? null
          : (value <= 0xFFFFFF ? 0xFF000000 | value : value);
    }
    if (value is! String) return null;
    var text = value.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length != 6 && text.length != 8) return null;
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return null;
    return text.length == 6 ? 0xFF000000 | parsed : parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is TextFormatSpan &&
      other.start == start &&
      other.end == end &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, bold, italic, underline, color);

  @override
  String toString() => 'TextFormatSpan($start..$end'
      '${bold == null ? '' : ' bold=$bold'}'
      '${italic == null ? '' : ' italic=$italic'}'
      '${underline == null ? '' : ' underline=$underline'}'
      '${color == null ? '' : ' color=${color!.toRadixString(16)}'})';
}

/// عمليات النطاقات: تطبيع، تطبيق، إعادة تأسيس بعد تحرير النص، وتحديد الهدف.
class TextFormatSpans {
  const TextFormatSpans._();

  /// تطبيع: قصّ على طول النص، إسقاط الفارغ/غير الصالح، فرز، تسوية التداخل
  /// (اللاحق يسود)، ثم دمج المتجاور المتساوي.
  static List<TextFormatSpan> normalize(
    Iterable<TextFormatSpan> spans, {
    required int textLength,
  }) {
    final length = textLength < 0 ? 0 : textLength;
    final valid = <TextFormatSpan>[];
    for (final span in spans) {
      final start = span.start.clamp(0, length).toInt();
      final end = span.end.clamp(0, length).toInt();
      if (end <= start || !span.hasAttributes) continue;
      valid.add(span.copyWith(start: start, end: end));
    }
    if (valid.isEmpty) return const <TextFormatSpan>[];
    valid.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end));

    final boundaries = <int>{0, length};
    for (final span in valid) {
      boundaries.add(span.start);
      boundaries.add(span.end);
    }
    final sorted = boundaries.toList()..sort();

    final result = <TextFormatSpan>[];
    for (var index = 0; index + 1 < sorted.length; index++) {
      final start = sorted[index];
      final end = sorted[index + 1];
      if (end <= start) continue;
      bool? bold;
      bool? italic;
      bool? underline;
      int? color;
      var any = false;
      for (final span in valid) {
        if (!span.covers(start)) continue;
        any = true;
        bold = span.bold ?? bold;
        italic = span.italic ?? italic;
        underline = span.underline ?? underline;
        color = span.color ?? color;
      }
      if (!any) continue;
      final piece = TextFormatSpan(
        start: start,
        end: end,
        bold: bold,
        italic: italic,
        underline: underline,
        color: color,
      );
      if (!piece.hasAttributes) continue;
      final previous = result.isEmpty ? null : result.last;
      if (previous != null &&
          previous.end == piece.start &&
          previous.bold == piece.bold &&
          previous.italic == piece.italic &&
          previous.underline == piece.underline &&
          previous.color == piece.color) {
        result[result.length - 1] =
            previous.copyWith(end: piece.end);
      } else {
        result.add(piece);
      }
    }
    return List<TextFormatSpan>.unmodifiable(result);
  }

  /// يطبّق [operation] على [current]: يغطّي المقطع المحدد فقط، ويحفظ خصائص
  /// النطاقات الأخرى (خارج التحديد وداخله) ما لم يعطِها [operation] قيمة.
  static List<TextFormatSpan> apply(
    List<TextFormatSpan> current,
    TextFormatSpan operation, {
    required int textLength,
  }) {
    final existing = normalize(current, textLength: textLength);
    if (!operation.isApplicable) {
      return existing;
    }
    final start = operation.start.clamp(0, textLength).toInt();
    final end = operation.end.clamp(0, textLength).toInt();
    if (end <= start) {
      return existing;
    }

    final pieces = <TextFormatSpan>[];
    for (final span in existing) {
      if (span.end <= start || span.start >= end) {
        pieces.add(span);
        continue;
      }
      if (span.start < start) {
        pieces.add(span.copyWith(end: start));
      }
      final overlap = TextFormatSpan(
        start: span.start < start ? start : span.start,
        end: span.end > end ? end : span.end,
        bold: operation.bold ?? span.bold,
        italic: operation.italic ?? span.italic,
        underline: operation.underline ?? span.underline,
        color: operation.color ?? span.color,
      );
      if (overlap.hasAttributes) pieces.add(overlap);
      if (span.end > end) {
        pieces.add(span.copyWith(start: end));
      }
    }

    // الأجزاء غير المغطّاة بأي نطاق داخل التحديد تأخذ خصائص العملية وحدها.
    final covered = <int>[];
    for (final piece in pieces) {
      final from = piece.start < start ? start : piece.start;
      final to = piece.end > end ? end : piece.end;
      if (to > from) covered.addAll(<int>[from, to]);
    }
    covered.sort();
    var cursor = start;
    for (var index = 0; index + 1 < covered.length; index += 2) {
      final from = covered[index];
      final to = covered[index + 1];
      if (from > cursor) {
        pieces.add(_operationOnly(operation, cursor, from));
      }
      if (to > cursor) cursor = to;
    }
    if (cursor < end) {
      pieces.add(_operationOnly(operation, cursor, end));
    }

    return normalize(pieces, textLength: textLength);
  }

  static TextFormatSpan _operationOnly(
    TextFormatSpan operation,
    int start,
    int end,
  ) =>
      TextFormatSpan(
        start: start,
        end: end,
        bold: operation.bold,
        italic: operation.italic,
        underline: operation.underline,
        color: operation.color,
      );

  /// يزيل خصائص محدَّدة من نطاق، ويُبقي ما عداه — لعودة التنسيق إلى نمط العنصر
  /// (مثل «اللون الافتراضي» على كلمة محدَّدة).
  static List<TextFormatSpan> clear(
    List<TextFormatSpan> current, {
    required int start,
    required int end,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool color = false,
    required int textLength,
  }) {
    final from = start < end ? start : end;
    final to = start < end ? end : start;
    final pieces = <TextFormatSpan>[];
    for (final span in normalize(current, textLength: textLength)) {
      final overlapStart = span.start > from ? span.start : from;
      final overlapEnd = span.end < to ? span.end : to;
      if (overlapEnd <= overlapStart) {
        pieces.add(span);
        continue;
      }
      if (span.start < overlapStart) {
        pieces.add(span.copyWith(end: overlapStart));
      }
      final cleared = TextFormatSpan(
        start: overlapStart,
        end: overlapEnd,
        bold: bold ? null : span.bold,
        italic: italic ? null : span.italic,
        underline: underline ? null : span.underline,
        color: color ? null : span.color,
      );
      if (cleared.hasAttributes && cleared.end > cleared.start) {
        pieces.add(cleared);
      }
      if (span.end > overlapEnd) {
        pieces.add(span.copyWith(start: overlapEnd));
      }
    }
    return normalize(pieces, textLength: textLength);
  }

  /// نطاقات نصّ **مشذّب** من نص مخزَّن قد يحمل فراغات طرفية.
  ///
  /// المحرك يبني محتوى السؤال من `statement.trim()`؛ فتُزاح الإزاحات بمقدار
  /// الفراغات المحذوفة من البداية وتُقصّ عند نهاية النص المشذّب، كي يبقى
  /// التنسيق على المحارف نفسها التي حدّدها المدرس.
  static List<TextFormatSpan> forTrimmed(
    Iterable<TextFormatSpan> spans,
    String text,
  ) {
    if (text.isEmpty) return const <TextFormatSpan>[];
    final normalized = normalize(spans, textLength: text.length);
    if (normalized.isEmpty) return normalized;
    final trimmedLength = text.trim().length;
    final leading = text.length - text.trimLeft().length;
    if (trimmedLength == text.length) return normalized;
    final shifted = <TextFormatSpan>[];
    for (final span in normalized) {
      final start = span.start - leading;
      final end = span.end - leading;
      if (end <= 0 || start >= trimmedLength) continue;
      shifted.add(span.copyWith(
        start: start < 0 ? 0 : start,
        end: end > trimmedLength ? trimmedLength : end,
      ));
    }
    return normalize(shifted, textLength: trimmedLength);
  }

  /// إعادة تأسيس الإزاحات بعد تحرير نص الحقل.
  ///
  /// الجزء المتغيّر هو [بادئة مشتركة .. (الطول − لاحقة مشتركة)). ما بعد الجزء
  /// المتغيّر يُزاح بمقدار الفرق، وما يتقاطع معه يُقصّ عند بدايته (التنسيق يخصّ
  /// محارف موجودة بالفعل فلا يُمدّ إلى نص جديد لم يحدده المدرس).
  static List<TextFormatSpan> rebase(
    List<TextFormatSpan> spans, {
    required String previous,
    required String next,
  }) {
    if (spans.isEmpty) return const <TextFormatSpan>[];
    if (identical(previous, next) || previous == next) {
      return normalize(spans, textLength: next.length);
    }
    var prefix = 0;
    final shortest =
        previous.length < next.length ? previous.length : next.length;
    while (prefix < shortest && previous.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        previous.codeUnitAt(previous.length - 1 - suffix) ==
            next.codeUnitAt(next.length - 1 - suffix)) {
      suffix++;
    }
    final oldChangeEnd = previous.length - suffix;
    final delta = next.length - previous.length;

    final rebased = <TextFormatSpan>[];
    for (final span in spans) {
      // (أ) الجزء الواقع قبل موضع التغيير يبقى كما هو (مقصوصًا عند الموضع).
      if (span.start < prefix) {
        final end = span.end < prefix ? span.end : prefix;
        if (end > span.start) {
          rebased.add(span.copyWith(end: end));
        }
      }
      // (ب) الجزء الواقع بعد الجزء المتغيّر يُزاح بمقدار الفرق ويحتفظ
      // بتنسيقه؛ فمن يكتب داخل كلمة عريضة لا يفقد تعريض بقية الكلمة.
      if (span.end > oldChangeEnd) {
        final start = span.start > oldChangeEnd ? span.start : oldChangeEnd;
        if (span.end > start) {
          rebased.add(span.copyWith(
            start: start + delta,
            end: span.end + delta,
          ));
        }
      }
    }
    return normalize(rebased, textLength: next.length);
  }

  /// نطاق الهدف لعملية تنسيق من تحديد حقيقي.
  ///
  /// القاعدة المعلنة لغياب التحديد: المؤشر المطوي يعني **الكلمة التي عليها**،
  /// ويُعاد `null` إذا لم يكن هناك نص — فلا يُنسَّق السؤال كله بالتلميح.
  static TextFormatSpan? targetRange(
    String text, {
    required int start,
    required int end,
  }) {
    if (text.isEmpty) return null;
    final from = start < end ? start : end;
    final to = start < end ? end : start;
    if (to > from) {
      final clampedStart = from.clamp(0, text.length).toInt();
      final clampedEnd = to.clamp(0, text.length).toInt();
      if (clampedEnd <= clampedStart) return null;
      return TextFormatSpan(start: clampedStart, end: clampedEnd);
    }
    // مؤشر مطوي: الكلمة عند المؤشر (حدود UAX #29 المبسطة: حروف/أرقام/علامات
    // تشكيل عربية متصلة، وما عداها فاصل).
    final offset = from.clamp(0, text.length).toInt();
    var wordStart = offset;
    while (wordStart > 0 && _isWordCodeUnit(text.codeUnitAt(wordStart - 1))) {
      wordStart--;
    }
    var wordEnd = offset;
    while (wordEnd < text.length && _isWordCodeUnit(text.codeUnitAt(wordEnd))) {
      wordEnd++;
    }
    if (wordEnd <= wordStart) return null;
    return TextFormatSpan(start: wordStart, end: wordEnd);
  }

  static bool _isWordCodeUnit(int unit) {
    // أرقام 0-9 والعربية-الهندية.
    if (unit >= 0x30 && unit <= 0x39) return true;
    if (unit >= 0x0660 && unit <= 0x0669) return true;
    if (unit >= 0x06F0 && unit <= 0x06F9) return true;
    // حروف لاتينية.
    if (unit >= 0x41 && unit <= 0x5A) return true;
    if (unit >= 0x61 && unit <= 0x7A) return true;
    // تشكيل/علامات عربية تُبقي الكلمة موصولة.
    if (unit >= 0x064B && unit <= 0x065F) return true;
    if (unit == 0x0670 || unit == 0x0640) return true;
    if (unit >= 0x06D6 && unit <= 0x06ED) return true;
    // حروف عربية.
    if (unit >= 0x0621 && unit <= 0x063A) return true;
    if (unit >= 0x0641 && unit <= 0x064A) return true;
    if (unit >= 0x066E && unit <= 0x06D3) return true;
    if (unit >= 0x06FA && unit <= 0x06FF) return true;
    return false;
  }

  /// حزمة الخصائص عند إزاحة معيّنة (لتحديث حالة أزرار الشريط على التحديد).
  static TextFormatSpan? attributeAt(
    List<TextFormatSpan> spans,
    int offset,
  ) {
    TextFormatSpan? attribute;
    for (final span in spans) {
      if (!span.covers(offset)) continue;
      attribute = TextFormatSpan(
        start: 0,
        end: 0,
        bold: span.bold ?? attribute?.bold,
        italic: span.italic ?? attribute?.italic,
        underline: span.underline ?? attribute?.underline,
        color: span.color ?? attribute?.color,
      );
    }
    return attribute;
  }
}
