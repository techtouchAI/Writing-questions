import 'dart:math' as math;

import '../../models/math_symbols.dart';
import 'math_stroke_font.dart';

/// نتيجة تحويل صيغة LaTeX إلى صورة SVG متجهة.
class LatexSvg {
  const LatexSvg({
    required this.svg,
    required this.width,
    required this.height,
    required this.baseline,
  });

  /// نص SVG كامل (مسارات متجهة خالصة — بلا نصوص) يُرسم عبر `pw.SvgImage`.
  final String svg;

  /// المقاسات النهائية بالنقاط (pt) — نفس حجم الصيغة على الورقة.
  final double width;

  /// المقاسات النهائية بالنقاط (pt) — نفس حجم الصيغة على الورقة.
  final double height;

  /// موقع خط الأساس من أعلى الصورة (لدمج الصيغة سطرياً مع النص).
  final double baseline;
}

/// محوّل LaTeX → SVG لصيغ الاختبارات العلمية.
///
/// يدعم مجموعة موثّقة تغطي احتياجات الاختبارات المدرسية:
/// - الجذور: `\sqrt{x}` و`\sqrt[n]{x}`.
/// - الكسور: `\frac{a}{b}`.
/// - الدوال الفرعية/العليا: `x^{2}`، `x_{1}` (أو بلا أقواس لمحرف واحد).
/// - التكاملات والمجموعات والضربات: `\int_{a}^{b}`، `\sum_{i=1}^{n}`، `\prod`،
///   `\lim` وأسماء الدوال (`\sin`، `\log`...) وأي اسم حرفي.
/// - الأقواس المتكيّفة: `\left( ... \right)` بأي محدد (`(`، `[`، `\{`، `|`، `.`)
///   تُرسم **بارتفاع محتواها** لا بحرف ثابت — فالكسر داخل قوسين لا يخرج منه.
/// - الأسهم فوق المتغيرات: `\vec{F}`، `\hat{x}`، `\bar{x}`، `\overline{AB}`.
/// - النصوص: `\text{cm}` تُرسم محارفها إن كانت مدعومة (والعربية ترتد آمناً).
/// - الرموز: جدول [MathSymbols] كاملاً (يونانية، علاقات، مجموعات، عمليات).
///
/// ## التباعد
/// يُطبَّق تباعد TeX بين الذرات: فراغ حول العلاقات (=، ≤...) وحول العمليات
/// الثنائية (+، ×...) وبعد الفواصل — فالمعادلة `a=b` لا تُطبع ملتصقة.
/// العملية الثنائية في أول الصيغة (أو بعد قوس فتح/علاقة) تُعامَل أُحاديةً
/// (`-x` لا «ناقص ثنائي بلا طرف أيسر»).
///
/// كل محرف يُرسم بمسارات [MathStrokeFont] — لا يعتمد على أي خط خارجي،
/// فلا تنكسر المعادلات في الملف المطبوع إطلاقاً، والمنحنيات تُرسم Bézier
/// ناعمة (لا مضلعات) للمحارف الموسومة بذلك.
///
/// الصيغ غير المدعومة (نصوص عربية داخل `\text{}` مثلاً) تجعل [tryToSvg]
/// تعيد `null` ليستخدم المحرك الخط العادي كبديل آمن.
abstract final class LatexSvgRenderer {
  /// يحوّل [latex] إلى SVG؛ يرمي [FormatException] عند صيغة غير مدعومة.
  static LatexSvg toSvg(String latex, {double fontSize = 12}) {
    final parser = _Parser(MathSymbols.canonicalize(latex.trim()));
    final node = parser.parseExpression();
    parser.expectEnd();

    final unit = fontSize / MathStrokeFont.unitsPerEm;
    final metrics = node.measure(unit);

    const pad = 1.0;
    final width = metrics.width + 2 * pad;
    final height = metrics.ascent + metrics.descent + 2 * pad;
    final baselineY = metrics.ascent + pad;

    final ctx = _SvgContext(unit: unit, strokeWidth: math.max(0.5, fontSize * 0.07));
    node.emit(pad, baselineY, ctx, 1.0);

    final buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
      ..write('width="${_n(width)}" height="${_n(height)}" ')
      ..write('viewBox="0 0 ${_n(width)} ${_n(height)}">')
      ..write('<g fill="none" stroke="#000000" stroke-width="${_n(ctx.strokeWidth)}" ')
      ..write('stroke-linecap="round" stroke-linejoin="round">')
      ..writeAll(ctx.parts)
      ..write('</g></svg>');

    return LatexSvg(
      svg: buffer.toString(),
      width: width,
      height: height,
      baseline: baselineY,
    );
  }

  /// نسخة آمنة: `null` بدل رمي استثناء عند صيغة غير مدعومة.
  static LatexSvg? tryToSvg(String latex, {double fontSize = 12}) {
    try {
      return toSvg(latex, fontSize: fontSize);
    } on FormatException {
      return null;
    }
  }

  /// هل تُرسم الصيغة [latex] متجهةً بالكامل (بلا ارتداد إلى بديل نصي)؟
  ///
  /// يستعملها محرر المعادلات لتحذير المدرس **قبل** التصدير إن حملت صيغتُه
  /// ما لا يرسمه خط الرياضيات — فلا يفاجأ ببديل نصي في الملف.
  static bool canRender(String latex) => tryToSvg(latex) != null;

  /// المحارف التي يعجز خط الرياضيات عن رسمها داخل [latex] (فارغة إن رُسمت
  /// كلها). الفحص على مستوى المحارف لا البنية: البنية الناقصة تُبلغ عنها
  /// [canRender] وحدها.
  static Set<String> unsupportedCharacters(String latex) {
    final source = MathSymbols.canonicalize(latex);
    final result = <String>{};
    var index = 0;
    void check(String char) {
      if (char.trim().isEmpty) {
        return;
      }
      if (MathStrokeFont.strokesOf(char) == null) {
        result.add(char);
      }
    }

    while (index < source.length) {
      final char = source[index];
      if (char == r'\') {
        final match = MathSymbols.commandPattern.matchAsPrefix(source, index);
        if (match == null) {
          index++;
          continue;
        }
        index = match.end;
        final command = match.group(0)!;
        final glyph = MathSymbols.glyphFor(command);
        if (glyph != null) {
          for (final inner in glyph.split('')) {
            check(inner);
          }
        }
        continue;
      }
      if (char == '{' || char == '}' || char == '^' || char == '_') {
        index++;
        continue;
      }
      check(char);
      index++;
    }
    return result;
  }
}

String _n(double value) {
  final rounded = (value * 100).roundToDouble() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

// ==================== شجرة التخطيط ====================

class _Metrics {
  const _Metrics(this.width, this.ascent, this.descent);

  final double width;
  final double ascent;
  final double descent;
}

/// فئة الذرة الرياضية — تحدد تباعدها عن جيرانها (تباعد TeX).
enum _AtomClass { ord, bin, rel, punct, open, close, op, space }

class _SvgContext {
  _SvgContext({required this.unit, required this.strokeWidth});

  final double unit;
  final double strokeWidth;
  final List<String> parts = <String>[];

  /// يرسم خطاً من نقاط بمحاور الخط: [smooth] يحوّله منحنى Bézier ناعماً
  /// (Catmull-Rom عبر النقاط) بدل قطع مستقيمة.
  void addPolyline(
    List<double> points,
    double x,
    double baselineY,
    double scale, {
    bool smooth = false,
  }) {
    if (points.length < 4) {
      return;
    }
    final screen = <List<double>>[];
    for (var i = 0; i + 1 < points.length; i += 2) {
      screen.add(<double>[
        x + points[i] * unit * scale,
        baselineY - (MathStrokeFont.baseline - points[i + 1]) * unit * scale,
      ]);
    }
    final buffer = StringBuffer('M${_n(screen.first[0])} ${_n(screen.first[1])}');
    if (!smooth || screen.length < 3) {
      for (var i = 1; i < screen.length; i++) {
        buffer
          ..write(' L')
          ..write(_n(screen[i][0]))
          ..write(' ')
          ..write(_n(screen[i][1]));
      }
      parts.add('<path d="$buffer"/>');
      return;
    }
    // Catmull-Rom ← Bézier تكعيبي: منحنى ناعم يمر بكل نقاط التحكم.
    for (var i = 0; i + 1 < screen.length; i++) {
      final p0 = screen[i == 0 ? 0 : i - 1];
      final p1 = screen[i];
      final p2 = screen[i + 1];
      final p3 = screen[i + 2 < screen.length ? i + 2 : screen.length - 1];
      final c1x = p1[0] + (p2[0] - p0[0]) / 6;
      final c1y = p1[1] + (p2[1] - p0[1]) / 6;
      final c2x = p2[0] - (p3[0] - p1[0]) / 6;
      final c2y = p2[1] - (p3[1] - p1[1]) / 6;
      buffer
        ..write(' C')
        ..write(_n(c1x))
        ..write(' ')
        ..write(_n(c1y))
        ..write(' ')
        ..write(_n(c2x))
        ..write(' ')
        ..write(_n(c2y))
        ..write(' ')
        ..write(_n(p2[0]))
        ..write(' ')
        ..write(_n(p2[1]));
    }
    parts.add('<path d="$buffer"/>');
  }

  /// يرسم مضلعاً بإحداثيات شاشة جاهزة (نقاط PDF) — للمحددات الممتدة التي
  /// تُحسب إحداثياتها من ارتفاع محتواها لا من صندوق محرف ثابت.
  void addScreenPolyline(List<double> points, {bool smooth = false}) {
    if (points.length < 4) {
      return;
    }
    final screen = <List<double>>[];
    for (var i = 0; i + 1 < points.length; i += 2) {
      screen.add(<double>[points[i], points[i + 1]]);
    }
    final buffer = StringBuffer('M${_n(screen.first[0])} ${_n(screen.first[1])}');
    if (!smooth || screen.length < 3) {
      for (var i = 1; i < screen.length; i++) {
        buffer
          ..write(' L')
          ..write(_n(screen[i][0]))
          ..write(' ')
          ..write(_n(screen[i][1]));
      }
      parts.add('<path d="$buffer"/>');
      return;
    }
    for (var i = 0; i + 1 < screen.length; i++) {
      final p0 = screen[i == 0 ? 0 : i - 1];
      final p1 = screen[i];
      final p2 = screen[i + 1];
      final p3 = screen[i + 2 < screen.length ? i + 2 : screen.length - 1];
      buffer
        ..write(' C')
        ..write(_n(p1[0] + (p2[0] - p0[0]) / 6))
        ..write(' ')
        ..write(_n(p1[1] + (p2[1] - p0[1]) / 6))
        ..write(' ')
        ..write(_n(p2[0] - (p3[0] - p1[0]) / 6))
        ..write(' ')
        ..write(_n(p2[1] - (p3[1] - p1[1]) / 6))
        ..write(' ')
        ..write(_n(p2[0]))
        ..write(' ')
        ..write(_n(p2[1]));
    }
    parts.add('<path d="$buffer"/>');
  }

  void addRawPath(String d) {
    parts.add('<path d="$d"/>');
  }
}

abstract class _Node {
  _Metrics measure(double unit);

  /// يرسم العقدة عند (x, baselineY) بوحدة `ctx.unit * scale` — كل عقدة
  /// فرعية (كسور/دوال) تُمرِّر مقياسها الخاص إلى أبنائها.
  void emit(double x, double baselineY, _SvgContext ctx, double scale);

  /// فئة التباعد (افتراضاً ذرة عادية).
  _AtomClass get atomClass => _AtomClass.ord;
}

class _GlyphNode extends _Node {
  _GlyphNode(this.char);

  final String char;

  static const Set<String> _binary = <String>{
    '+', '-', '×', '÷', '±', '∓', '·', '∪', '∩',
  };
  static const Set<String> _relations = <String>{
    '=', '<', '>', '≤', '≥', '≠', '≈', '≡', '∼', '≃', '≅', '∝',
    '→', '←', '↔', '⇒', '⇔', '⇌', '∈', '∉', '⊂', '⊃', '⊆', '⊇',
  };
  static const Set<String> _punctuation = <String>{',', ';', ':', '!', '?'};
  static const Set<String> _opening = <String>{'(', '[', '{', '«'};
  static const Set<String> _closing = <String>{')', ']', '}', '»'};

  @override
  _AtomClass get atomClass {
    if (_binary.contains(char)) {
      return _AtomClass.bin;
    }
    if (_relations.contains(char)) {
      return _AtomClass.rel;
    }
    if (_punctuation.contains(char)) {
      return _AtomClass.punct;
    }
    if (_opening.contains(char)) {
      return _AtomClass.open;
    }
    if (_closing.contains(char)) {
      return _AtomClass.close;
    }
    return _AtomClass.ord;
  }

  @override
  _Metrics measure(double unit) {
    final strokes = MathStrokeFont.strokesOf(char);
    if (strokes == null) {
      throw FormatException('MathStrokeFont: محرف غير مدعوم في المعادلات ("$char").');
    }
    var minY = MathStrokeFont.baseline;
    var maxY = MathStrokeFont.baseline;
    for (final stroke in strokes.strokes) {
      for (var i = 1; i < stroke.length; i += 2) {
        minY = math.min(minY, stroke[i]);
        maxY = math.max(maxY, stroke[i]);
      }
    }
    return _Metrics(
      strokes.advance * unit,
      (MathStrokeFont.baseline - minY) * unit,
      (maxY - MathStrokeFont.baseline) * unit,
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final strokes = MathStrokeFont.strokesOf(char);
    if (strokes == null) {
      throw FormatException('MathStrokeFont: محرف غير مدعوم في المعادلات ("$char").');
    }
    for (final stroke in strokes.strokes) {
      ctx.addPolyline(
        stroke,
        x,
        baselineY,
        scale,
        smooth: strokes.smooth,
      );
    }
  }
}

class _RowNode extends _Node {
  _RowNode(this.children);

  final List<_Node> children;

  /// فراغات TeX بين الذرات (نقاط PDF بعد القياس) — تُحسب مرة واحدة ليقرأها
  /// القياس والرسم معاً فيتطابقان دائماً.
  List<double> _gaps(double unit) {
    final em = MathStrokeFont.unitsPerEm * unit;
    double left(_AtomClass cls) {
      switch (cls) {
        case _AtomClass.bin:
          return 0.22 * em;
        case _AtomClass.rel:
          return 0.28 * em;
        case _AtomClass.op:
          return 0.12 * em;
        case _AtomClass.close:
        case _AtomClass.punct:
        case _AtomClass.space:
        case _AtomClass.open:
        case _AtomClass.ord:
          return 0;
      }
    }

    double right(_AtomClass cls) {
      switch (cls) {
        case _AtomClass.bin:
          return 0.22 * em;
        case _AtomClass.rel:
          return 0.28 * em;
        case _AtomClass.punct:
          return 0.17 * em;
        case _AtomClass.op:
          return 0.12 * em;
        case _AtomClass.open:
        case _AtomClass.close:
        case _AtomClass.space:
        case _AtomClass.ord:
          return 0;
      }
    }

    final gaps = List<double>.filled(
      children.isEmpty ? 0 : children.length - 1,
      0,
      growable: false,
    );
    for (var i = 0; i + 1 < children.length; i++) {
      var previous = children[i].atomClass;
      // العملية الثنائية بلا طرف أيسر (أول الصيغة أو بعد فتح/علاقة/عملية)
      // تُعامَل أُحادية: `-x` و`(-3)` بلا فراغ ثنائي.
      if (previous == _AtomClass.bin) {
        final before = i == 0 ? null : children[i - 1].atomClass;
        if (before == null ||
            before == _AtomClass.open ||
            before == _AtomClass.rel ||
            before == _AtomClass.bin ||
            before == _AtomClass.op) {
          previous = _AtomClass.ord;
        }
      }
      gaps[i] = math.max(right(previous), left(children[i + 1].atomClass));
    }
    return gaps;
  }

  @override
  _Metrics measure(double unit) {
    final gaps = _gaps(unit);
    var width = 0.0;
    var ascent = 0.0;
    var descent = 0.0;
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        width += gaps[i - 1];
      }
      final metrics = children[i].measure(unit);
      width += metrics.width;
      ascent = math.max(ascent, metrics.ascent);
      descent = math.max(descent, metrics.descent);
    }
    return _Metrics(width, ascent, descent);
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final gaps = _gaps(ctx.unit * scale);
    var pen = x;
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        pen += gaps[i - 1];
      }
      children[i].emit(pen, baselineY, ctx, scale);
      pen += children[i].measure(ctx.unit * scale).width;
    }
  }
}

class _SpaceNode extends _Node {
  _SpaceNode(this.widthFactor);

  final double widthFactor;

  @override
  _AtomClass get atomClass => _AtomClass.space;

  @override
  _Metrics measure(double unit) =>
      _Metrics(widthFactor * unit, 0, 0);

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {}
}

class _FracNode extends _Node {
  _FracNode(this.numerator, this.denominator);

  final _Node numerator;
  final _Node denominator;

  @override
  _Metrics measure(double unit) {
    final childUnit = unit * 0.9;
    final num = numerator.measure(childUnit);
    final den = denominator.measure(childUnit);
    final width = math.max(num.width, den.width) + 4 * unit;
    final axis = 3.2 * unit;
    final gap = 1.6 * unit;
    final ascent = axis + gap + num.descent + num.ascent;
    final descent = den.ascent + den.descent + gap - axis;
    return _Metrics(width, ascent, math.max(descent, 1.5 * unit));
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    final childScale = scale * 0.9;
    final num = numerator.measure(unit * 0.9);
    final den = denominator.measure(unit * 0.9);
    final width = math.max(num.width, den.width) + 4 * unit;
    final axis = 3.2 * unit;
    final gap = 1.6 * unit;

    final ruleY = baselineY - axis;
    ctx.addRawPath(
      'M${_n(x + 1.5 * unit)} ${_n(ruleY)} '
      'L${_n(x + width - 1.5 * unit)} ${_n(ruleY)}',
    );

    final numBaseline = ruleY - gap - num.descent;
    numerator.emit(x + (width - num.width) / 2, numBaseline, ctx, childScale);
    final denBaseline = ruleY + gap + den.ascent;
    denominator.emit(x + (width - den.width) / 2, denBaseline, ctx, childScale);
  }
}

class _SqrtNode extends _Node {
  _SqrtNode(this.body, this.index);

  final _Node body;
  final _Node? index;

  @override
  _Metrics measure(double unit) {
    final bodyMetrics = body.measure(unit);
    final indexWidth = index == null ? 0.0 : index!.measure(unit * 0.7).width;
    return _Metrics(
      bodyMetrics.width + 6 * unit + indexWidth,
      bodyMetrics.ascent + 2.5 * unit,
      bodyMetrics.descent + 1 * unit,
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    final bodyMetrics = body.measure(unit);
    final indexMetrics = index?.measure(unit * 0.7);
    final indexWidth = indexMetrics?.width ?? 0.0;

    final radicalX = x + indexWidth;
    final topY = baselineY - bodyMetrics.ascent - 2 * unit;
    final hookY = baselineY + bodyMetrics.descent;

    ctx.addRawPath(
      'M${_n(radicalX)} ${_n(baselineY - 1.5 * unit)} '
      'L${_n(radicalX + 1.2 * unit)} ${_n(hookY)} '
      'L${_n(radicalX + 2.6 * unit)} ${_n(topY)} '
      'L${_n(radicalX + 5.5 * unit + bodyMetrics.width)} ${_n(topY)}',
    );

    body.emit(radicalX + 5.5 * unit, baselineY, ctx, scale);
    if (index != null) {
      index!.emit(x, baselineY - bodyMetrics.ascent * 0.55, ctx, scale * 0.7);
    }
  }
}

class _ScriptsNode extends _Node {
  _ScriptsNode(this.base, {this.sup, this.sub});

  final _Node base;
  final _Node? sup;
  final _Node? sub;

  @override
  _Metrics measure(double unit) {
    final baseMetrics = base.measure(unit);
    final scriptUnit = unit * 0.68;
    final supMetrics = sup?.measure(scriptUnit);
    final subMetrics = sub?.measure(scriptUnit);
    final scriptsWidth =
        math.max(supMetrics?.width ?? 0, subMetrics?.width ?? 0) + 1.2 * unit;
    final ascent = math.max(
      baseMetrics.ascent,
      4.2 * unit + (supMetrics?.ascent ?? 0) + (supMetrics?.descent ?? 0),
    );
    final descent = math.max(
      baseMetrics.descent,
      2.6 * unit + (subMetrics?.ascent ?? 0) + (subMetrics?.descent ?? 0),
    );
    return _Metrics(baseMetrics.width + scriptsWidth, ascent, descent);
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    base.emit(x, baselineY, ctx, scale);
    final scriptPen = x + base.measure(unit).width + 0.6 * unit;
    if (sup != null) {
      sup!.emit(scriptPen, baselineY - 4.2 * unit, ctx, scale * 0.68);
    }
    if (sub != null) {
      sub!.emit(scriptPen, baselineY + 2.6 * unit, ctx, scale * 0.68);
    }
  }
}

/// قوسان متكيّفان: `\left(...\right)` يُرسم محدّداه بارتفاع **المحتوى**
/// (لا بحرف ثابت) — فالكسر أو المجموع داخل قوسين يبقى داخلهما فعلاً.
class _FencedNode extends _Node {
  _FencedNode(this.body, {required this.left, required this.right});

  final _Node body;

  /// المحدد بصيغته (محرف أو `\{`) — [left] و[right] معاً.
  final String left;
  final String right;

  static double _delimiterWidth(String delimiter, double unit) {
    if (delimiter == '.') {
      return 0;
    }
    if (delimiter == '|') {
      return 1.6 * unit;
    }
    return 3.0 * unit;
  }

  @override
  _Metrics measure(double unit) {
    final inner = body.measure(unit);
    final width = inner.width +
        _delimiterWidth(left, unit) +
        _delimiterWidth(right, unit) +
        1.2 * unit;
    return _Metrics(
      width,
      inner.ascent + 1.2 * unit,
      inner.descent + 1.2 * unit,
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    final inner = body.measure(unit);
    final leftWidth = _delimiterWidth(left, unit);
    final rightWidth = _delimiterWidth(right, unit);
    final top = baselineY - inner.ascent - 1.2 * unit;
    final bottom = baselineY + inner.descent + 1.2 * unit;
    if (left != '.') {
      _drawDelimiter(ctx, left, x, top, bottom, unit);
    }
    body.emit(x + leftWidth + 0.6 * unit, baselineY, ctx, scale);
    if (right != '.') {
      _drawDelimiter(
        ctx,
        right,
        x + leftWidth + 0.6 * unit + inner.width + 0.6 * unit,
        top,
        bottom,
        unit,
      );
    }
  }

  /// يرسم محدداً ممتداً بين [top] و[bottom] عند [x] بعرض ثابت.
  static void _drawDelimiter(
    _SvgContext ctx,
    String delimiter,
    double x,
    double top,
    double bottom,
    double unit,
  ) {
    final height = bottom - top;
    final mid = (top + bottom) / 2;
    final w = 3.0 * unit;
    final List<double> points;
    switch (delimiter) {
      case '(':
      case r'\(':
        points = <double>[
          w, top, w * 0.45, top + height * 0.16, w * 0.18, mid,
          w * 0.45, bottom - height * 0.16, w, bottom,
        ];
        ctx.addScreenPolyline(points, smooth: true);
        return;
      case ')':
      case r'\)':
        points = <double>[
          0, top, w * 0.55, top + height * 0.16, w * 0.82, mid,
          w * 0.55, bottom - height * 0.16, 0, bottom,
        ];
        ctx.addScreenPolyline(points, smooth: true);
        return;
      case '[':
      case r'\[':
        ctx.addRawPath(
          'M${_n(x + w)} ${_n(top)} L${_n(x + 0.3 * unit)} ${_n(top)} '
          'L${_n(x + 0.3 * unit)} ${_n(bottom)} L${_n(x + w)} ${_n(bottom)}',
        );
        return;
      case ']':
      case r'\]':
        ctx.addRawPath(
          'M${_n(x)} ${_n(top)} L${_n(x + w - 0.3 * unit)} ${_n(top)} '
          'L${_n(x + w - 0.3 * unit)} ${_n(bottom)} L${_n(x)} ${_n(bottom)}',
        );
        return;
      case '{':
      case r'\{':
        points = <double>[
          w, top, w * 0.5, top + height * 0.08, w * 0.5, mid - height * 0.12,
          w * 0.1, mid, w * 0.5, mid + height * 0.12,
          w * 0.5, bottom - height * 0.08, w, bottom,
        ];
        ctx.addScreenPolyline(points, smooth: true);
        return;
      case '}':
      case r'\}':
        points = <double>[
          0, top, w * 0.5, top + height * 0.08, w * 0.5, mid - height * 0.12,
          w * 0.9, mid, w * 0.5, mid + height * 0.12,
          w * 0.5, bottom - height * 0.08, 0, bottom,
        ];
        ctx.addScreenPolyline(points, smooth: true);
        return;
      default: // '|' ومشتقاته
        ctx.addRawPath('M${_n(x + 0.6 * unit)} ${_n(top)} L${_n(x + 0.6 * unit)} ${_n(bottom)}');
        return;
    }
  }
}

/// سهم/قبعة/خط فوق متغير (`\vec`، `\hat`، `\bar`، `\overline`).
enum _AccentKind { arrow, hat, bar }

class _AccentNode extends _Node {
  _AccentNode(this.body, {this.kind = _AccentKind.arrow});

  /// سهم `\vec` فوق الحرف (شائع في صيغ الفيزياء).
  final _Node body;

  final _AccentKind kind;

  @override
  _Metrics measure(double unit) {
    final bodyMetrics = body.measure(unit);
    return _Metrics(
      math.max(bodyMetrics.width, 5.5 * unit),
      bodyMetrics.ascent + 3.5 * unit,
      bodyMetrics.descent,
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    final bodyMetrics = body.measure(unit);
    final width = math.max(bodyMetrics.width, 5.5 * unit);
    body.emit(x + (width - bodyMetrics.width) / 2, baselineY, ctx, scale);
    final accentY = baselineY - bodyMetrics.ascent - 1.5 * unit;
    switch (kind) {
      case _AccentKind.arrow:
        ctx.addRawPath(
          'M${_n(x + 0.5 * unit)} ${_n(accentY)} '
          'L${_n(x + width - 0.5 * unit)} ${_n(accentY)} '
          'M${_n(x + width - 2.2 * unit)} ${_n(accentY - 1.2 * unit)} '
          'L${_n(x + width - 0.5 * unit)} ${_n(accentY)} '
          'L${_n(x + width - 2.2 * unit)} ${_n(accentY + 1.2 * unit)}',
        );
      case _AccentKind.hat:
        ctx.addRawPath(
          'M${_n(x + 0.8 * unit)} ${_n(accentY + 1.2 * unit)} '
          'L${_n(x + width / 2)} ${_n(accentY)} '
          'L${_n(x + width - 0.8 * unit)} ${_n(accentY + 1.2 * unit)}',
        );
      case _AccentKind.bar:
        ctx.addRawPath(
          'M${_n(x + 0.3 * unit)} ${_n(accentY + 0.6 * unit)} '
          'L${_n(x + width - 0.3 * unit)} ${_n(accentY + 0.6 * unit)}',
        );
    }
  }
}

class _BigOpNode extends _Node {
  _BigOpNode(this.symbol, {this.sup, this.sub});

  final String symbol;
  final _Node? sup;
  final _Node? sub;

  @override
  _AtomClass get atomClass => _AtomClass.op;

  @override
  _Metrics measure(double unit) {
    final glyph = _GlyphNode(symbol).measure(unit * 1.6);
    final scriptUnit = unit * 0.68;
    final supMetrics = sup?.measure(scriptUnit);
    final subMetrics = sub?.measure(scriptUnit);
    final scriptsWidth =
        math.max(supMetrics?.width ?? 0, subMetrics?.width ?? 0) + 1.2 * unit;
    return _Metrics(
      glyph.width + scriptsWidth,
      math.max(glyph.ascent, 4 * unit + (supMetrics?.ascent ?? 0)),
      math.max(glyph.descent, 3 * unit + (subMetrics?.descent ?? 0)),
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    final glyph = _GlyphNode(symbol);
    glyph.emit(x, baselineY, ctx, scale * 1.6);
    final pen = x + glyph.measure(unit * 1.6).width + 1.2 * unit;
    sup?.emit(pen, baselineY - 3.2 * unit, ctx, scale * 0.7);
    sub?.emit(pen, baselineY + 3.2 * unit, ctx, scale * 0.7);
  }
}

class _OpNameNode extends _Node {
  _OpNameNode(this.name, {this.sup, this.sub});

  /// اسم العملية (lim أو sin مثلاً) — يُرسم كمحارف لاتينية صغيرة.
  final String name;
  final _Node? sup;
  final _Node? sub;

  @override
  _AtomClass get atomClass => _AtomClass.op;

  @override
  _Metrics measure(double unit) {
    var nameWidth = 0.0;
    for (final char in name.split('')) {
      // فراغ داخلي (lim sup): عرض فراغ لا محرفاً.
      nameWidth += char == ' '
          ? 1.5 * unit * 0.85
          : _GlyphNode(char).measure(unit * 0.85).width;
    }
    final scriptUnit = unit * 0.68;
    final supMetrics = sup?.measure(scriptUnit);
    final subMetrics = sub?.measure(scriptUnit);
    return _Metrics(
      math.max(nameWidth, math.max(supMetrics?.width ?? 0, subMetrics?.width ?? 0)) +
          3 * unit,
      math.max(5.5 * unit, (supMetrics?.ascent ?? 0) + 4.2 * unit),
      math.max(1.2 * unit, (subMetrics?.ascent ?? 0) + (subMetrics?.descent ?? 0) + 1.5 * unit),
    );
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    final unit = ctx.unit * scale;
    var pen = x + 1.5 * unit;
    for (final char in name.split('')) {
      if (char == ' ') {
        pen += 1.5 * unit * 0.85;
        continue;
      }
      final glyph = _GlyphNode(char);
      glyph.emit(pen, baselineY, ctx, scale * 0.85);
      pen += glyph.measure(unit * 0.85).width;
    }
    final metrics = measure(unit);
    final center = x + metrics.width / 2;
    if (sup != null) {
      final supWidth = sup!.measure(unit * 0.68).width;
      sup!.emit(center - supWidth / 2, baselineY - 4.2 * unit, ctx, scale * 0.68);
    }
    if (sub != null) {
      final subMetrics = sub!.measure(unit * 0.68);
      sub!.emit(
        center - subMetrics.width / 2,
        baselineY + 1.5 * unit + subMetrics.ascent,
        ctx,
        scale * 0.68,
      );
    }
  }
}

// ==================== محلل LaTeX ====================

class _Parser {
  _Parser(this.source);

  final String source;
  int _pos = 0;

  bool get _done => _pos >= source.length;

  String get _current => source[_pos];

  void expectEnd() {
    if (_pos < source.length) {
      throw FormatException('LaTeX: مدخلات متبقية غير معالجة "${source.substring(_pos)}".');
    }
  }

  /// يبني سطرًا من العقد حتى نهاية المصدر أو حتى حرف التوقف [stopAt]
  /// (`}` للأقواس، `]` لأس الجذر) دون استهلاكه.
  ///
  /// [stopAtRight] يوقف المتتالية عند `\right` دون استهلاكه (جسم القوسين).
  _Node parseExpression({String? stopAt, bool stopAtRight = false}) {
    final children = <_Node>[];
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == stopAt) {
        break;
      }
      if (stopAtRight && char == r'\') {
        final command = _peekCommand();
        if (command == r'\right') {
          break;
        }
        // `\left` داخل الجسم يُستهلك تركيبياً في [_parseAtom] فلا يصل هنا.
        if (command == r'\left') {
          children.add(_parseAtom());
          continue;
        }
      }
      if (char == '}') {
        throw const FormatException('LaTeX: قوس إغلاق زائد "}".');
      }
      if (char == '^' || char == '_') {
        if (children.isEmpty) {
          throw FormatException('LaTeX: "$char" بدون أساس قبله.');
        }
        final base = children.removeLast();
        children.add(_parseScripts(base));
        continue;
      }
      children.add(_parseAtom());
    }
    return children.length == 1 ? children.single : _RowNode(children);
  }

  _Node _parseAtom() {
    if (_pos >= source.length) {
      throw const FormatException('LaTeX: توقّع مدخلاً بعد الأمر لكن انتهى النص.');
    }
    final char = source[_pos];
    if (char == '{') {
      _pos++;
      final inner = parseExpression(stopAt: '}');
      _expect('}');
      return inner;
    }
    if (char == '\\') {
      return _parseCommand();
    }
    if (char == ' ' || char == '\n' || char == '\t') {
      _pos++;
      return _SpaceNode(1.5);
    }
    _pos++;
    return _GlyphNode(char);
  }

  _Node _parseScripts(_Node base) {
    _Node? sup;
    _Node? sub;
    while (_pos < source.length && (source[_pos] == '^' || source[_pos] == '_')) {
      final marker = source[_pos];
      _pos++;
      final arg = _parseScriptArgument();
      if (marker == '^') {
        if (sup != null) {
          throw const FormatException('LaTeX: أس مكرر "^".');
        }
        sup = arg;
      } else {
        if (sub != null) {
          throw const FormatException('LaTeX: فرعي مكرر "_".');
        }
        sub = arg;
      }
    }
    return _ScriptsNode(base, sup: sup, sub: sub);
  }

  _Node _parseScriptArgument() {
    if (_pos < source.length && source[_pos] == '{') {
      _pos++;
      final inner = parseExpression(stopAt: '}');
      _expect('}');
      return inner;
    }
    return _parseAtom();
  }

  _Node _parseCommand() {
    _pos++; // ابتلاع '\'
    if (_pos >= source.length) {
      throw const FormatException('LaTeX: شرطة مائلة في نهاية الصيغة.');
    }

    final start = _pos;
    while (_pos < source.length && _isLetter(source[_pos])) {
      _pos++;
    }
    final name = source.substring(start, _pos);
    if (name.isEmpty) {
      // أوامر بمحرف واحد: \{ \} \| \, \; \: \! \( \) \[ \] \% \& \# \^ \_
      final char = source[_pos];
      _pos++;
      switch (char) {
        case '{':
          return _GlyphNode('{');
        case '}':
          return _GlyphNode('}');
        case '|':
          return _GlyphNode('|');
        case '(':
          return _GlyphNode('(');
        case ')':
          return _GlyphNode(')');
        case '[':
          return _GlyphNode('[');
        case ']':
          return _GlyphNode(']');
        case '%':
          return _GlyphNode('%');
        case '&':
          return _GlyphNode('&');
        case '#':
          return _GlyphNode('#');
        case '^':
          return _GlyphNode('^');
        case '_':
          return _GlyphNode('_');
        case ',':
        case ';':
        case ':':
        case '!':
        case ' ':
          return _SpaceNode(
            MathSymbols.spaceCommands[char]! * MathStrokeFont.unitsPerEm,
          );
        default:
          throw FormatException('LaTeX: أمر غير معروف "\\$char".');
      }
    }

    if (name == 'frac' || name == 'dfrac' || name == 'tfrac') {
      final numerator = _parseScriptArgument();
      final denominator = _parseScriptArgument();
      return _FracNode(numerator, denominator);
    }
    if (name == 'sqrt') {
      _Node? index;
      if (_pos < source.length && source[_pos] == '[') {
        _pos++;
        index = parseExpression(stopAt: ']');
        _expect(']');
      }
      final body = _parseScriptArgument();
      return _SqrtNode(body, index);
    }
    if (name == 'vec') {
      return _AccentNode(_parseScriptArgument());
    }
    if (name == 'hat' || name == 'widehat') {
      return _AccentNode(_parseScriptArgument(), kind: _AccentKind.hat);
    }
    if (name == 'bar' || name == 'overline') {
      return _AccentNode(_parseScriptArgument(), kind: _AccentKind.bar);
    }
    if (name == 'left') {
      return _parseLeftFence();
    }
    if (name == 'right') {
      // \right شارد بلا \left: يُرسم محدِّده حرفاً (لا يُسقَط المحتوى).
      return _delimiterGlyph(_parseDelimiter());
    }
    if (MathSymbols.textCommands.contains(name)) {
      return _parseTextGroup();
    }
    if (name == 'quad' || name == 'qquad') {
      return _SpaceNode(name == 'quad' ? 8 : 16);
    }
    final symbol = MathSymbols.glyphFor('\\$name');
    if (symbol != null) {
      if (symbol.length == 1) {
        // العمليات الكبيرة (تكامل/مجموع/جداء) تُرسم مكبَّرةً بحدودها الجانبية.
        if (MathSymbols.bigOperators.containsKey(name)) {
          _Node? sup;
          _Node? sub;
          while (_pos < source.length &&
              (source[_pos] == '^' || source[_pos] == '_')) {
            final marker = source[_pos];
            _pos++;
            final arg = _parseScriptArgument();
            if (marker == '^') {
              sup = arg;
            } else {
              sub = arg;
            }
          }
          return _BigOpNode(symbol, sup: sup, sub: sub);
        }
        return _GlyphNode(symbol);
      }
      // اسم دالة/عملية (lim، sin، lim sup...) بمحارفه اللاتينية.
      return _OpNameNode(symbol);
    }
    // اسم حرفي غير معروف (دالة كتبها المدرس مثل \floor): يُرسم upright
    // بدل إسقاط الصيغة كلها إلى بديل نصي — لا يُفقَد محتوى أبداً.
    return _OpNameNode(name);
  }

  /// `\left <محدد> ... \right <محدد>` بقوسين ممتدين بارتفاع المحتوى.
  ///
  /// إن غاب `\right` المقابل (صيغة قديمة ناقصة) يُرسم المحدد حرفاً ويُكمَل
  /// التحليل — الارتداد إلى بديل نصي كامل آخر العلاج لا أوله.
  _Node _parseLeftFence() {
    final left = _parseDelimiter();
    final saved = _pos;
    try {
      final body = parseExpression(stopAtRight: true);
      if (!_done && _current == r'\') {
        if (_peekCommand() == r'\right') {
          _readCommand();
          final right = _parseDelimiter();
          return _FencedNode(body, left: left, right: right);
        }
      }
    } on FormatException {
      // بنية ناقصة داخل الجسم: يُعالَج الارتداد أدناه.
    }
    _pos = saved;
    return _delimiterGlyph(left);
  }

  _Node _delimiterGlyph(String delimiter) {
    if (delimiter == '.') {
      return _SpaceNode(0);
    }
    final clean = delimiter
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '');
    return _GlyphNode(clean == r'\{'
        ? '{'
        : clean == r'\}'
            ? '}'
            : clean == r'\|'
                ? '|'
                : clean);
  }

  /// نص حر `\text{...}`: تُرسم محارفه إن كانت كلها مدعومة (وحدات القياس
  /// مثل cm وkg)، والعربية وغيرها ترتد FORMATException ← بديل نصي آمن.
  _Node _parseTextGroup() {
    _skipSpaces();
    if (_done || _current != '{') {
      return _SpaceNode(0);
    }
    _pos++;
    final start = _pos;
    var depth = 1;
    while (!_done && depth > 0) {
      if (_current == '{') {
        depth++;
      } else if (_current == '}') {
        depth--;
        if (depth == 0) {
          break;
        }
      }
      _pos++;
    }
    final text = source.substring(start, _pos);
    if (!_done) {
      _pos++; // '}'
    }
    final nodes = <_Node>[];
    for (final char in text.split('')) {
      if (char == ' ') {
        nodes.add(_SpaceNode(1.5));
        continue;
      }
      nodes.add(_GlyphNode(char));
    }
    return nodes.length == 1 ? nodes.single : _RowNode(nodes);
  }

  /// محدد `\left`/`\right`: محرف أو أمر (`\{`، `\|`، `.`).
  String _parseDelimiter() {
    _skipSpaces();
    if (_done) {
      return '';
    }
    if (_current == r'\') {
      return _readCommand();
    }
    final delimiter = _current;
    _pos++;
    return delimiter;
  }

  /// يقرأ أمراً (`\alpha` أو `\{` أو `\,`...) ويتقدم بعده.
  String _readCommand() {
    final start = _pos;
    _pos++; // '\'
    if (!_done && RegExp(r'[A-Za-z]').hasMatch(_current)) {
      while (!_done && RegExp(r'[A-Za-z]').hasMatch(_current)) {
        _pos++;
      }
    } else if (!_done) {
      _pos++;
    }
    return source.substring(start, _pos);
  }

  /// يعاين الأمر عند المؤشر دون تقدم (لرصد `\right`).
  String _peekCommand() {
    if (_done || _current != r'\') {
      return '';
    }
    var end = _pos + 1;
    if (end < source.length && RegExp(r'[A-Za-z]').hasMatch(source[end])) {
      while (end < source.length && RegExp(r'[A-Za-z]').hasMatch(source[end])) {
        end++;
      }
    } else if (end < source.length) {
      end++;
    }
    return source.substring(_pos, end);
  }

  void _skipSpaces() {
    while (!_done && (_current == ' ' || _current == '\t' || _current == '\n')) {
      _pos++;
    }
  }

  void _expect(String char) {
    if (_pos >= source.length || source[_pos] != char) {
      throw FormatException('LaTeX: توقّع "$char" عند الموضع $_pos.');
    }
    _pos++;
  }

  static bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
