import 'dart:math' as math;

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
  final double height;

  /// موقع خط الأساس من أعلى الصورة (لدمج الصيغة سطرياً مع النص).
  final double baseline;
}

/// محوّل LaTeX → SVG لصيغ الاختبارات العلمية (خطوة 5.3).
///
/// يدعم مجموعة موثّقة تغطي احتياجات الاختبارات المدرسية:
/// - الجذور: `\sqrt{x}` و`\sqrt[n]{x}`.
/// - الكسور: `\frac{a}{b}`.
/// - الدوال الفرعية/العليا: `x^{2}`، `x_{1}` (أو بلا أقواس لمحرف واحد).
/// - التكاملات والمجموعات والضربات: `\int_{a}^{b}`، `\sum_{i=1}^{n}`، `\prod`، `\lim`.
/// - `\vec{F}` ورموز: `\times \div \pm \cdot \leq \geq \neq \approx \equiv
///   \to \rightarrow \leftarrow \rightleftharpoons \infty` واليونانية الشائعة.
/// - تكبير الأقواس: `\left( ... \right)` وأقواس `{ } [ ] |`.
///
/// كل محرف يُرسم بمسارات [MathStrokeFont] — لا يعتمد على أي خط خارجي،
/// فلا تنكسر المعادلات في الملف المطبوع إطلاقاً.
///
/// الصيغ غير المدعومة (نصوص عربية داخل `\text{}` مثلاً) تجعل [tryToSvg]
/// تعيد `null` ليستخدم المحرك الخط العادي كبديل آمن.
abstract final class LatexSvgRenderer {
  /// يحوّل [latex] إلى SVG؛ يرمي [FormatException] عند صيغة غير مدعومة.
  static LatexSvg toSvg(String latex, {double fontSize = 12}) {
    final parser = _Parser(latex.trim());
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

class _SvgContext {
  _SvgContext({required this.unit, required this.strokeWidth});

  final double unit;
  final double strokeWidth;
  final List<String> parts = <String>[];

  void addPolyline(
    List<double> points,
    double x,
    double baselineY,
    double scale,
  ) {
    if (points.length < 4) {
      return;
    }
    final buffer = StringBuffer('M');
    for (var i = 0; i + 1 < points.length; i += 2) {
      final px = x + points[i] * unit * scale;
      final py = baselineY - (MathStrokeFont.baseline - points[i + 1]) * unit * scale;
      buffer
        ..write(_n(px))
        ..write(' ')
        ..write(_n(py));
      if (i + 3 < points.length) {
        buffer.write(' L');
      }
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
}

class _GlyphNode extends _Node {
  _GlyphNode(this.char);

  final String char;

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
      ctx.addPolyline(stroke, x, baselineY, scale);
    }
  }
}

class _RowNode extends _Node {
  _RowNode(this.children);

  final List<_Node> children;

  @override
  _Metrics measure(double unit) {
    var width = 0.0;
    var ascent = 0.0;
    var descent = 0.0;
    for (final child in children) {
      final metrics = child.measure(unit);
      width += metrics.width;
      ascent = math.max(ascent, metrics.ascent);
      descent = math.max(descent, metrics.descent);
    }
    return _Metrics(width, ascent, descent);
  }

  @override
  void emit(double x, double baselineY, _SvgContext ctx, double scale) {
    var pen = x;
    for (final child in children) {
      child.emit(pen, baselineY, ctx, scale);
      pen += child.measure(ctx.unit * scale).width;
    }
  }
}

class _SpaceNode extends _Node {
  _SpaceNode(this.widthFactor);

  final double widthFactor;

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
    final pen = x + base.measure(unit).width + 1.2 * unit;
    sup?.emit(pen, baselineY - 4.2 * unit, ctx, scale * 0.68);
    sub?.emit(pen, baselineY + 2.6 * unit, ctx, scale * 0.68);
  }
}

class _BigOpNode extends _Node {
  _BigOpNode(this.symbol, {this.sup, this.sub});

  /// رمز العملية الكبيرة (∫ أو ∑ أو ∏).
  final String symbol;
  final _Node? sup;
  final _Node? sub;

  @override
  _Metrics measure(double unit) {
    final opUnit = unit * 1.6;
    final glyph = _GlyphNode(symbol).measure(opUnit);
    final scriptUnit = unit * 0.7;
    final supMetrics = sup?.measure(scriptUnit);
    final subMetrics = sub?.measure(scriptUnit);
    final sideWidth =
        math.max(supMetrics?.width ?? 0, subMetrics?.width ?? 0) + 1.2 * unit;
    return _Metrics(
      glyph.width + sideWidth,
      math.max(glyph.ascent, (supMetrics?.ascent ?? 0) + 3.2 * unit),
      math.max(glyph.descent, (subMetrics?.descent ?? 0) + 3.2 * unit),
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

  /// اسم العملية (lim مثلاً) — يُرسم كمحارف لاتينية صغيرة.
  final String name;
  final _Node? sup;
  final _Node? sub;

  @override
  _Metrics measure(double unit) {
    var nameWidth = 0.0;
    for (final char in name.split('')) {
      nameWidth += _GlyphNode(char).measure(unit * 0.85).width;
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

class _AccentNode extends _Node {
  _AccentNode(this.body);

  /// سهم `\vec` فوق الحرف (شائع في صيغ الفيزياء).
  final _Node body;

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
    final arrowY = baselineY - bodyMetrics.ascent - 1.5 * unit;
    ctx.addRawPath(
      'M${_n(x + 0.5 * unit)} ${_n(arrowY)} '
      'L${_n(x + width - 0.5 * unit)} ${_n(arrowY)} '
      'M${_n(x + width - 2.2 * unit)} ${_n(arrowY - 1.2 * unit)} '
      'L${_n(x + width - 0.5 * unit)} ${_n(arrowY)} '
      'L${_n(x + width - 2.2 * unit)} ${_n(arrowY + 1.2 * unit)}',
    );
  }
}

// ==================== محلل LaTeX ====================

class _Parser {
  _Parser(this.source);

  final String source;
  int _pos = 0;

  static const Map<String, String> _commandSymbols = <String, String>{
    'times': '×',
    'div': '÷',
    'pm': '±',
    'mp': '±',
    'cdot': '·',
    'leq': '≤',
    'le': '≤',
    'geq': '≥',
    'ge': '≥',
    'neq': '≠',
    'ne': '≠',
    'approx': '≈',
    'equiv': '≡',
    'to': '→',
    'rightarrow': '→',
    'leftarrow': '←',
    'rightleftharpoons': '⇌',
    'infty': '∞',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'theta': 'θ',
    'lambda': 'λ',
    'mu': 'μ',
    'pi': 'π',
    'sigma': 'σ',
    'tau': 'τ',
    'phi': 'φ',
    'omega': 'ω',
    'Gamma': 'Γ',
    'Delta': 'Δ',
    'Omega': 'Ω',
  };

  static const Set<String> _bigOpCommands = <String>{'int', 'sum', 'prod'};

  static const Map<String, String> _bigOpSymbols = <String, String>{
    'int': '∫',
    'sum': '∑',
    'prod': '∏',
  };

  void expectEnd() {
    if (_pos < source.length) {
      throw FormatException('LaTeX: مدخلات متبقية غير معالجة "${source.substring(_pos)}".');
    }
  }

  /// يبني سطرًا من العقد حتى نهاية المصدر أو حتى حرف التوقف [stopAt]
  /// (`}` للأقواس، `]` لأس الجذر) دون استهلاكه.
  _Node parseExpression({String? stopAt}) {
    final children = <_Node>[];
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == stopAt) {
        break;
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
    var name = source.substring(start, _pos);
    if (name.isEmpty) {
      // أوامر بمحرف واحد: \{ \} \| \, \; \: \! \( \) \[ \]
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
        case ',':
        case ';':
        case ':':
        case '!':
        case ' ':
          return _SpaceNode(char == ',' ? 1.2 : char == '!' ? 0.4 : 2.5);
        default:
          throw FormatException('LaTeX: أمر غير معروف "\\$char".');
      }
    }

    if (name == 'frac') {
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
    if (name == 'left' || name == 'right') {
      if (_pos >= source.length) {
        throw const FormatException('LaTeX: أمر left أو right بلا قوس بعده.');
      }
      final char = source[_pos];
      _pos++;
      return _scaledBracket(char);
    }
    if (name == 'lim') {
      return _parseOpName('lim');
    }
    if (_bigOpCommands.contains(name)) {
      return _parseBigOp(name);
    }
    if (name == 'quad') {
      return _SpaceNode(8);
    }
    if (name == 'qquad') {
      return _SpaceNode(16);
    }
    if (name == 'text') {
      // النصوص الحرة (خصوصاً العربية) خارج نطاق خط المتجهات.
      throw const FormatException('LaTeX: \\text غير مدعوم في رسوم SVG.');
    }
    final symbol = _commandSymbols[name];
    if (symbol != null) {
      return _GlyphNode(symbol);
    }
    throw FormatException('LaTeX: أمر غير معروف "\\$name".');
  }

  _Node _scaledBracket(String char) {
    if (char == '.' ) {
      return _SpaceNode(0);
    }
    return _GlyphNode(char);
  }

  _Node _parseOpName(String name) {
    _Node? sup;
    _Node? sub;
    while (_pos < source.length && (source[_pos] == '^' || source[_pos] == '_')) {
      final marker = source[_pos];
      _pos++;
      final arg = _parseScriptArgument();
      if (marker == '^') {
        sup = arg;
      } else {
        sub = arg;
      }
    }
    return _OpNameNode(name, sup: sup, sub: sub);
  }

  _Node _parseBigOp(String name) {
    _Node? sup;
    _Node? sub;
    while (_pos < source.length && (source[_pos] == '^' || source[_pos] == '_')) {
      final marker = source[_pos];
      _pos++;
      final arg = _parseScriptArgument();
      if (marker == '^') {
        sup = arg;
      } else {
        sub = arg;
      }
    }
    return _BigOpNode(_bigOpSymbols[name]!, sup: sup, sub: sub);
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
