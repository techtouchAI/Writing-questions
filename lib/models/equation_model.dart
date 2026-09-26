/// النموذج البصري للمعادلات الرياضية فوق التمثيل الداخلي LaTeX.
///
/// LaTeX هو **تفصيل تنفيذي داخلي** وليس واجهة مستخدم: يُخزَّن في النصوص
/// داخل `$...$` / `$$...$$` كما كان دائماً (فلا يتغير التخزين ولا
/// التصدير)، ويوفّر هذا النموذج طبقة تحرير مرئية فوقه:
///
/// ```text
/// المحرر المرئي ← EquationModel ← LaTeX المخزَّن ← التصدير (PDF/Word)
/// ```
///
/// - الإنشاء المرئي يبني [EqNode] ثم يولّد LaTeX عبر [EquationModel.toLatex].
/// - المعادلات القديمة تُحمَّل عبر [EquationModel.parse] وتُعرض بصرياً.
/// - ما لا يمثَّله المحلل تركيبياً (كـ `\int` و`\sum`...) يُحفَظ حرفياً
///   داخل [EqText] فلا يُفقَد أي محتوى أبداً — مع بديل آمن عند الفشل.
library equation_model;

/// يعقّم نصاً كتبه المستخدم داخل صيغة رياضية.
///
/// علامة الدولار وحدها تُفسد محددات الصيغة (`$...$`) فتُستبدل بـ `\$`
/// (دولار حرفي داخل وضع الرياضيات) بدل حذفها — لا يُفقَد أي محتوى.
String sanitizeMathText(String input) => input.replaceAll(r'$', r'\$');

String _joinNodes(List<EqNode> nodes) =>
    nodes.map((node) => node.toLatex()).join();

/// عقدة واحدة في بنية المعادلة المرئية.
abstract class EqNode {
  /// يولّد LaTeX الداخلي لهذه العقدة.
  String toLatex();
}

/// نص رياضي حر (أرقام/حروف/رموز) يُكتب مباشرة داخل خانة.
///
/// يستقبل أيضاً أوامر LaTeX المتقدمة حرفياً (كـ `\alpha` و`\times`)
/// فيبقى معناها محفوظاً وقابلاً للتحرير والعرض الحي.
class EqText extends EqNode {
  EqText(this.text);

  String text;

  @override
  String toLatex() => sanitizeMathText(text);
}

/// كسر ببسط ومقام قابلين للتحرير (`\frac{num}{den}`).
class EqFraction extends EqNode {
  EqFraction({List<EqNode>? numerator, List<EqNode>? denominator})
      : numerator = numerator ?? <EqNode>[],
        denominator = denominator ?? <EqNode>[];

  final List<EqNode> numerator;
  final List<EqNode> denominator;

  @override
  String toLatex() =>
      '\\frac{${_joinNodes(numerator)}}{${_joinNodes(denominator)}}';
}

/// جذر تربيعي (أو نوني عند ملء [root]) قابل للتحرير.
class EqSqrt extends EqNode {
  EqSqrt({List<EqNode>? body, List<EqNode>? root})
      : body = body ?? <EqNode>[],
        root = root ?? <EqNode>[];

  final List<EqNode> body;

  /// دليل الجذر (`\sqrt[n]{x}`)؛ فارغ = جذر تربيعي.
  final List<EqNode> root;

  @override
  String toLatex() {
    if (root.isEmpty) {
      return '\\sqrt{${_joinNodes(body)}}';
    }
    return '\\sqrt[${_joinNodes(root)}]{${_joinNodes(body)}}';
  }
}

/// أسّ/قوة: قاعدة ودليل قابلان للتحرير (`x^{2}`).
class EqSup extends EqNode {
  EqSup({List<EqNode>? base, List<EqNode>? exponent})
      : base = base ?? <EqNode>[],
        exponent = exponent ?? <EqNode>[];

  final List<EqNode> base;
  final List<EqNode> exponent;

  @override
  String toLatex() => '${_scriptPart(base)}^{${_joinNodes(exponent)}}';
}

/// دليل سفري: قاعدة ودليل قابلان للتحرير (`x_{1}`).
class EqSub extends EqNode {
  EqSub({List<EqNode>? base, List<EqNode>? subscript})
      : base = base ?? <EqNode>[],
        subscript = subscript ?? <EqNode>[];

  final List<EqNode> base;
  final List<EqNode> subscript;

  @override
  String toLatex() => '${_scriptPart(base)}_{${_joinNodes(subscript)}}';
}

/// أقواس مرئية حول محتوى قابل للتحرير (`(...)` / `[...]` / `\{...\}`).
class EqFence extends EqNode {
  EqFence({required this.left, required this.right, List<EqNode>? body})
      : body = body ?? <EqNode>[];

  /// القوس الأيسر بصيغة LaTeX (`(` أو `[` أو `\{` أو `\left(`...).
  final String left;

  /// القوس الأيمن بصيغة LaTeX.
  final String right;

  final List<EqNode> body;

  @override
  String toLatex() => '$left${_joinNodes(body)}$right';
}

/// مجموعة صريحة بأقواس معقوفة (`{...}`) تحفظ تجميع LaTeX الأصلي.
class EqGroup extends EqNode {
  EqGroup([List<EqNode>? children]) : children = children ?? <EqNode>[];

  final List<EqNode> children;

  @override
  String toLatex() => '{${_joinNodes(children)}}';
}

/// قاعدة الأسّ/الدليل: المحرف الواحد يُكتب عارياً (`x^2`)، وغيره
/// يُحاط بأقواس (`{x+1}^{2}`) حفاظاً على المعنى.
String _scriptPart(List<EqNode> nodes) {
  if (nodes.length == 1 && nodes.single is EqText) {
    final text = (nodes.single as EqText).text;
    if (text.length == 1 && RegExp(r'[A-Za-z0-9]').hasMatch(text)) {
      return text;
    }
  }
  return '{${_joinNodes(nodes)}}';
}

/// نموذج معادلة كاملة: متتالية عقد قابلة للتحرير المرئي.
///
/// يُبنى برمجياً من المحرر المرئي، أو يُحلَّل من LaTeX مخزَّن عبر
/// [EquationModel.parse] — والتحليل لا يرمي أبداً: أي فشل يعيد النص
/// الأصلي حرفياً داخل [EqText] واحد.
class EquationModel {
  EquationModel({List<EqNode>? nodes}) : nodes = nodes ?? <EqNode>[];

  /// عقد المتتالية الجذرية (تُعدَّل مباشرة من المحرر أثناء التحرير).
  final List<EqNode> nodes;

  /// هل المعادلة فارغة (بلا عقد أو بلا نص في أي عقدة)؟
  bool get isEmpty => toLatex().trim().isEmpty;

  /// يولّد LaTeX الداخلي للمعادلة كاملة.
  String toLatex() => _joinNodes(nodes);

  /// يحلّل LaTeX مخزَّناً إلى بنية مرئية قابلة للتحرير.
  ///
  /// البنى المدعومة تركيبياً: `\frac` و`\sqrt` (مع `[n]` الاختياري)
  /// والأسس والأدلة (`^`/`_`) والأقواس (`\left...\right`) والمجموعات.
  /// كل ما عداها (أوامر، رموز، نصوص) يُحفَظ حرفياً كـ [EqText] —
  /// فلا يُفقَد معنى أي معادلة قديمة ولا تُستبدل بأخرى فارغة.
  static EquationModel parse(String latex) {
    try {
      return EquationModel(nodes: _EqParser(latex).parseTopLevel());
    } catch (_) {
      return EquationModel(nodes: <EqNode>[EqText(latex)]);
    }
  }
}

/// محلل LaTeX تنازلي متساهل — يحفظ حرفياً كل ما لا يمثّله تركيبياً.
class _EqParser {
  _EqParser(this.source);

  final String source;
  int _pos = 0;

  bool get _done => _pos >= source.length;

  String get _current => source[_pos];

  List<EqNode> parseTopLevel() => _parseSequence(topLevel: true);

  /// يحلّل متتالية حتى نهاية المصدر أو `}` المغلقة أو `\right`.
  ///
  /// `}` الشاردة في المستوى الجذري نص حرفي (لا تُسقِط ما بعدها).
  List<EqNode> _parseSequence({bool stopAtRight = false, bool topLevel = false}) {
    final nodes = <EqNode>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isNotEmpty) {
        nodes.add(EqText(text.toString()));
        text.clear();
      }
    }

    while (!_done) {
      final char = _current;
      if (char == '}') {
        if (topLevel) {
          text.write(char);
          _pos++;
          continue;
        }
        break;
      }
      if (char == '{') {
        flushText();
        nodes.add(_parseBraceGroup());
        continue;
      }
      if (char == r'\') {
        final command = _peekCommand();
        if (stopAtRight && command == r'\right') {
          break;
        }
        flushText();
        nodes.add(_parseCommand());
        continue;
      }
      if (char == '^' || char == '_') {
        flushText();
        _pos++;
        _skipSpaces();
        final argument = _parseScriptArgument();
        final List<EqNode> base;
        if (nodes.isEmpty) {
          base = <EqNode>[EqText('')];
        } else {
          base = <EqNode>[nodes.removeLast()];
        }
        nodes.add(
          char == '^'
              ? EqSup(base: base, exponent: argument)
              : EqSub(base: base, subscript: argument),
        );
        continue;
      }
      text.write(char);
      _pos++;
    }
    flushText();
    return nodes;
  }

  /// مجموعة `{...}`؛ غير المغلقة تُحفَظ حرفياً كما كُتبت.
  EqNode _parseBraceGroup() {
    final open = _pos;
    _pos++; // '{'
    final inner = _parseSequence();
    if (!_done && _current == '}') {
      _pos++;
      return EqGroup(inner);
    }
    return EqText(source.substring(open, _pos));
  }

  /// وسيط أسّ/دليل: مجموعة أو أمر أو محرف واحد.
  List<EqNode> _parseScriptArgument() {
    _skipSpaces();
    if (_done) {
      return <EqNode>[EqText('')];
    }
    if (_current == '{') {
      final group = _parseBraceGroup();
      if (group is EqGroup) {
        return group.children;
      }
      return <EqNode>[group];
    }
    if (_current == r'\') {
      return <EqNode>[_parseCommand()];
    }
    final char = _current;
    _pos++;
    return <EqNode>[EqText(char)];
  }

  /// أمر LaTeX: البنى المعروفة تركيبياً، وما عداها حرفياً.
  EqNode _parseCommand() {
    final start = _pos;
    final command = _readCommand();
    if (command == r'\frac') {
      final numerator = _parseRequiredGroup();
      final denominator = _parseRequiredGroup();
      return EqFraction(numerator: numerator, denominator: denominator);
    }
    if (command == r'\sqrt') {
      _skipSpaces();
      var root = <EqNode>[];
      if (!_done && _current == '[') {
        root = _parseBracketGroup();
        _skipSpaces();
      }
      return EqSqrt(body: _parseRequiredGroup(), root: root);
    }
    if (command == r'\left') {
      final left = _parseDelimiter();
      final body = _parseSequence(stopAtRight: true);
      var right = '';
      if (_peekCommand() == r'\right') {
        _readCommand();
        right = _parseDelimiter();
      }
      if (right.isEmpty) {
        // `\left` بلا `\right`: يُحفَظ المقطع حرفياً.
        return EqText(source.substring(start, _pos));
      }
      return EqFence(left: '\\left$left', right: '\\right$right', body: body);
    }
    return EqText(command);
  }

  /// مجموعة واجبة بعد `\frac`/`\sqrt`؛ الغائبة تُعوَّض بفارغ.
  List<EqNode> _parseRequiredGroup() {
    _skipSpaces();
    if (!_done && _current == '{') {
      final group = _parseBraceGroup();
      if (group is EqGroup) {
        return group.children;
      }
      return <EqNode>[group];
    }
    return <EqNode>[EqText('')];
  }

  /// مجموعة `[n]` لدليل الجذر؛ غير المغلقة تُحفَظ حرفياً.
  List<EqNode> _parseBracketGroup() {
    final start = _pos;
    _pos++; // '['
    final text = StringBuffer();
    var depth = 1;
    while (!_done && depth > 0) {
      final char = _current;
      if (char == '[') {
        depth++;
      } else if (char == ']') {
        depth--;
        if (depth == 0) {
          _pos++;
          break;
        }
      }
      if (depth > 0) {
        text.write(char);
      }
      _pos++;
    }
    if (depth > 0) {
      return <EqNode>[EqText(source.substring(start, _pos))];
    }
    return EquationModel.parse(text.toString()).nodes;
  }

  /// محدد `\left`/`\right` (محرف أو أمر كـ `\{` أو `.`).
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
}
