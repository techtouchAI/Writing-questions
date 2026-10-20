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

import 'math_symbols.dart';

/// يعقّم نصاً كتبه المستخدم داخل صيغة رياضية.
///
/// علامة الدولار وحدها تُفسد محددات الصيغة (`$...$`) فتُستبدل بـ `\$`
/// (دولار حرفي داخل وضع الرياضيات) بدل حذفها — لا يُفقَد أي محتوى.
String sanitizeMathText(String input) => input.replaceAll(r'$', r'\$');

String _joinNodes(List<EqNode> nodes) =>
    nodes.map((node) => node.toLatex()).join();

int _nextEqNodeSerial = 0;

String _allocateEqNodeId() => 'eq_${++_nextEqNodeSerial}';

/// عقدة واحدة في بنية المعادلة المرئية بمعرّف مستقر عبر التحديثات.
abstract class EqNode {
  EqNode({String? id}) : id = id ?? _allocateEqNodeId();

  /// معرّف مستقر للعقدة داخل جلسة التحرير والاختبارات لمنع انزياح المفاتيح.
  final String id;

  /// يولّد LaTeX الداخلي لهذه العقدة.
  String toLatex();

  /// الخانات الفرعية المرتبة من اليسار إلى اليمين (بسط ← مقام، قاعدة ← أس...).
  List<List<EqNode>> get slots => const <List<EqNode>>[];

  /// نسخة عميقة مستقلة (مع خيار الحفاظ على المعرّفات في سجل التراجع).
  EqNode clone({bool preserveIds = false});
}

/// نص رياضي حر (أرقام/حروف/رموز) يُكتب مباشرة داخل خانة.
///
/// الخانة تعرض **محارف مرئية** فقط (`α`، `×`، `{`) — والمحلّل يحوّل أوامر
/// LaTeX المخزَّنة القديمة إلى محارفها عند التحميل ([MathSymbols.toDisplay])،
/// فلا يرى المدرس كوداً في أي مرحلة. عند الحفظ يُعاد توليد LaTeX آمن:
/// المحارف الخاصة تُهرَّب (`{` ← `\{`) والمكافئة تُكتب أوامرها القياسية
/// (`α` ← `\alpha`) والناقصة تُطبَّع (`−` ← `-`) — انظر [MathSymbols.toLatex].
class EqText extends EqNode {
  EqText(this.text, {super.id});

  String text;

  @override
  String toLatex() => MathSymbols.toLatex(text);

  @override
  EqText clone({bool preserveIds = false}) =>
      EqText(text, id: preserveIds ? id : null);
}

/// كسر ببسط ومقام قابلين للتحرير (`\frac{num}{den}`).
class EqFraction extends EqNode {
  EqFraction({List<EqNode>? numerator, List<EqNode>? denominator, super.id})
      : numerator = numerator ?? <EqNode>[],
        denominator = denominator ?? <EqNode>[];

  final List<EqNode> numerator;
  final List<EqNode> denominator;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[numerator, denominator];

  @override
  String toLatex() =>
      '\\frac{${_joinNodes(numerator)}}{${_joinNodes(denominator)}}';

  @override
  EqFraction clone({bool preserveIds = false}) => EqFraction(
        id: preserveIds ? id : null,
        numerator: <EqNode>[
          for (final child in numerator) child.clone(preserveIds: preserveIds),
        ],
        denominator: <EqNode>[
          for (final child in denominator)
            child.clone(preserveIds: preserveIds),
        ],
      );
}

/// جذر تربيعي (أو نوني عند ملء [root]) قابل للتحرير.
class EqSqrt extends EqNode {
  EqSqrt({List<EqNode>? body, List<EqNode>? root, super.id})
      : body = body ?? <EqNode>[],
        root = root ?? <EqNode>[];

  final List<EqNode> body;

  /// دليل الجذر (`\sqrt[n]{x}`)؛ فارغ = جذر تربيعي.
  final List<EqNode> root;

  @override
  List<List<EqNode>> get slots => root.isNotEmpty
      ? <List<EqNode>>[root, body]
      : <List<EqNode>>[body];

  @override
  String toLatex() {
    if (root.isEmpty) {
      return '\\sqrt{${_joinNodes(body)}}';
    }
    return '\\sqrt[${_joinNodes(root)}]{${_joinNodes(body)}}';
  }

  @override
  EqSqrt clone({bool preserveIds = false}) => EqSqrt(
        id: preserveIds ? id : null,
        body: <EqNode>[
          for (final child in body) child.clone(preserveIds: preserveIds),
        ],
        root: <EqNode>[
          for (final child in root) child.clone(preserveIds: preserveIds),
        ],
      );
}

/// أسّ/قوة: قاعدة ودليل قابلان للتحرير (`x^{2}`).
class EqSup extends EqNode {
  EqSup({List<EqNode>? base, List<EqNode>? exponent, super.id})
      : base = base ?? <EqNode>[],
        exponent = exponent ?? <EqNode>[];

  final List<EqNode> base;
  final List<EqNode> exponent;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[base, exponent];

  @override
  String toLatex() => '${_scriptPart(base)}^{${_joinNodes(exponent)}}';

  @override
  EqSup clone({bool preserveIds = false}) => EqSup(
        id: preserveIds ? id : null,
        base: <EqNode>[
          for (final child in base) child.clone(preserveIds: preserveIds),
        ],
        exponent: <EqNode>[
          for (final child in exponent) child.clone(preserveIds: preserveIds),
        ],
      );
}

/// دليل سفري: قاعدة ودليل قابلان للتحرير (`x_{1}`).
class EqSub extends EqNode {
  EqSub({List<EqNode>? base, List<EqNode>? subscript, super.id})
      : base = base ?? <EqNode>[],
        subscript = subscript ?? <EqNode>[];

  final List<EqNode> base;
  final List<EqNode> subscript;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[base, subscript];

  @override
  String toLatex() => '${_scriptPart(base)}_{${_joinNodes(subscript)}}';

  @override
  EqSub clone({bool preserveIds = false}) => EqSub(
        id: preserveIds ? id : null,
        base: <EqNode>[
          for (final child in base) child.clone(preserveIds: preserveIds),
        ],
        subscript: <EqNode>[
          for (final child in subscript) child.clone(preserveIds: preserveIds),
        ],
      );
}

/// أقواس مرئية حول محتوى قابل للتحرير (`(...)` / `[...]` / `\{...\}`).
class EqFence extends EqNode {
  EqFence({
    required this.left,
    required this.right,
    List<EqNode>? body,
    super.id,
  }) : body = body ?? <EqNode>[];

  /// القوس الأيسر بصيغة LaTeX (`(` أو `[` أو `\{` أو `\left(`...).
  final String left;

  /// القوس الأيمن بصيغة LaTeX.
  final String right;

  final List<EqNode> body;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[body];

  @override
  String toLatex() => '$left${_joinNodes(body)}$right';

  @override
  EqFence clone({bool preserveIds = false}) => EqFence(
        id: preserveIds ? id : null,
        left: left,
        right: right,
        body: <EqNode>[
          for (final child in body) child.clone(preserveIds: preserveIds),
        ],
      );
}

/// علامة فوق متغير: سهم `\vec` أو قبعة `\hat` أو خط `\bar`/`\overline`.
class EqAccent extends EqNode {
  EqAccent({
    this.kind = EqAccentKind.vector,
    List<EqNode>? body,
    super.id,
  }) : body = body ?? <EqNode>[];

  final EqAccentKind kind;

  final List<EqNode> body;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[body];

  String get _command {
    switch (kind) {
      case EqAccentKind.vector:
        return r'\vec';
      case EqAccentKind.hat:
        return r'\hat';
      case EqAccentKind.bar:
        return r'\bar';
    }
  }

  @override
  String toLatex() => '$_command{${_joinNodes(body)}}';

  @override
  EqAccent clone({bool preserveIds = false}) => EqAccent(
        id: preserveIds ? id : null,
        kind: kind,
        body: <EqNode>[
          for (final child in body) child.clone(preserveIds: preserveIds),
        ],
      );
}

/// نوع العلامة فوق المتغير.
enum EqAccentKind { vector, hat, bar }

/// مجموعة صريحة بأقواس معقوفة (`{...}`) تحفظ تجميع LaTeX الأصلي.
class EqGroup extends EqNode {
  EqGroup([List<EqNode>? children, String? id])
      : children = children ?? <EqNode>[],
        super(id: id);

  final List<EqNode> children;

  @override
  List<List<EqNode>> get slots => <List<EqNode>>[children];

  @override
  String toLatex() => '{${_joinNodes(children)}}';

  @override
  EqGroup clone({bool preserveIds = false}) => EqGroup(
        <EqNode>[
          for (final child in children) child.clone(preserveIds: preserveIds),
        ],
        preserveIds ? id : null,
      );
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

  /// نسخة عميقة مستقلة من النموذج الكامل.
  EquationModel clone({bool preserveIds = false}) => EquationModel(
        nodes: <EqNode>[
          for (final node in nodes) node.clone(preserveIds: preserveIds),
        ],
      );

  /// كل خانات النص الورقية بترتيب القراءة الرياضي من اليسار إلى اليمين.
  List<EqText> allLeafTextSlots() {
    final result = <EqText>[];
    void visit(List<EqNode> list) {
      for (final node in list) {
        if (node is EqText) {
          result.add(node);
        } else {
          for (final slot in node.slots) {
            visit(slot);
          }
        }
      }
    }

    visit(nodes);
    return result;
  }

  /// موقع عقدة بالمعرّف داخل الشجرة (القائمة المالكة، الفهرس، العقدة الأم).
  ({List<EqNode> parentList, int index, EqNode node, EqNode? parentNode})?
      locateById(String targetId) {
    ({List<EqNode> parentList, int index, EqNode node, EqNode? parentNode})?
        found;
    void search(List<EqNode> list, EqNode? parentNode) {
      for (var index = 0; index < list.length; index++) {
        final node = list[index];
        if (node.id == targetId) {
          found = (
            parentList: list,
            index: index,
            node: node,
            parentNode: parentNode,
          );
          return;
        }
        for (final slot in node.slots) {
          search(slot, node);
          if (found != null) return;
        }
      }
    }

    search(nodes, null);
    return found;
  }

  /// سلسلة الأسلاف البنيوية (من الجذر إلى العقدة الحاضنة المباشرة).
  List<EqNode> ancestorChain(String targetId) {
    final chain = <EqNode>[];
    bool walk(List<EqNode> list) {
      for (final node in list) {
        if (node.id == targetId) return true;
        chain.add(node);
        for (final slot in node.slots) {
          if (walk(slot)) return true;
        }
        chain.removeLast();
      }
      return false;
    }

    walk(nodes);
    return chain;
  }

  /// العقدة المركبة الحاضنة المباشرة للخانة المعطاة (أو `null` في المستوى الأعلى).
  EqNode? enclosingCompound(String targetId) {
    final chain = ancestorChain(targetId);
    return chain.isEmpty ? null : chain.last;
  }

  /// ينتقل إلى الخانة التالية يساراً→يميناً، أو يخرج من البنية المركبة الحالية
  /// بإيجاد/إدراج خانة نص شقيقة بعدها مباشرةً في متتالية الأب.
  EqText stepNextOrExit(String? activeLeafId) {
    final leaves = allLeafTextSlots();
    if (activeLeafId == null) {
      if (leaves.isNotEmpty) return leaves.last;
      final fresh = EqText('');
      nodes.add(fresh);
      return fresh;
    }

    final compound = enclosingCompound(activeLeafId);
    if (compound != null) {
      final compoundLeaves = <EqText>[];
      void collect(EqNode n) {
        if (n is EqText) {
          compoundLeaves.add(n);
        } else {
          for (final s in n.slots) {
            for (final c in s) {
              collect(c);
            }
          }
        }
      }

      collect(compound);
      final posInCompound =
          compoundLeaves.indexWhere((leaf) => leaf.id == activeLeafId);
      if (posInCompound >= 0 && posInCompound + 1 < compoundLeaves.length) {
        return compoundLeaves[posInCompound + 1];
      }
      // آخر خانة داخل المكوّن المركب ← اخرج إلى شقيق بعده في قائمة الأب.
      final loc = locateById(compound.id);
      if (loc != null) {
        if (loc.index + 1 < loc.parentList.length &&
            loc.parentList[loc.index + 1] is EqText) {
          return loc.parentList[loc.index + 1] as EqText;
        }
        final nextSibling = EqText('');
        loc.parentList.insert(loc.index + 1, nextSibling);
        return nextSibling;
      }
    }

    final pos = leaves.indexWhere((leaf) => leaf.id == activeLeafId);
    if (pos >= 0 && pos + 1 < leaves.length) {
      return leaves[pos + 1];
    }
    if (nodes.isNotEmpty && nodes.last is EqText) {
      return nodes.last as EqText;
    }
    final trailing = EqText('');
    nodes.add(trailing);
    return trailing;
  }

  /// ينتقل إلى الخانة السابقة في الترتيب الرياضي من اليمين إلى اليسار.
  EqText? stepPrevious(String? activeLeafId) {
    final leaves = allLeafTextSlots();
    if (leaves.isEmpty) return null;
    if (activeLeafId == null) return leaves.first;
    final pos = leaves.indexWhere((leaf) => leaf.id == activeLeafId);
    if (pos > 0) return leaves[pos - 1];
    return leaves.first;
  }

  /// يدرج/يفعّل خانة نص شقيقة قبل المكوّن المركب الحالي أو الخانة الحالية.
  EqText insertSlotBefore(String? activeLeafId) {
    if (activeLeafId == null) {
      if (nodes.isNotEmpty && nodes.first is EqText) {
        return nodes.first as EqText;
      }
      final fresh = EqText('');
      nodes.insert(0, fresh);
      return fresh;
    }
    final anchorId = enclosingCompound(activeLeafId)?.id ?? activeLeafId;
    final loc = locateById(anchorId);
    if (loc == null) {
      final fresh = EqText('');
      nodes.insert(0, fresh);
      return fresh;
    }
    if (loc.index > 0 &&
        loc.parentList[loc.index - 1] is EqText &&
        (loc.parentList[loc.index - 1] as EqText).text.isEmpty) {
      return loc.parentList[loc.index - 1] as EqText;
    }
    final fresh = EqText('');
    loc.parentList.insert(loc.index, fresh);
    return fresh;
  }

  /// يدرج/يفعّل خانة نص شقيقة بعد المكوّن المركب الحالي أو الخانة الحالية.
  EqText insertSlotAfter(String? activeLeafId) {
    if (activeLeafId == null) {
      if (nodes.isNotEmpty && nodes.last is EqText) {
        return nodes.last as EqText;
      }
      final fresh = EqText('');
      nodes.add(fresh);
      return fresh;
    }
    final anchorId = enclosingCompound(activeLeafId)?.id ?? activeLeafId;
    final loc = locateById(anchorId);
    if (loc == null) {
      final fresh = EqText('');
      nodes.add(fresh);
      return fresh;
    }
    if (loc.index + 1 < loc.parentList.length &&
        loc.parentList[loc.index + 1] is EqText &&
        (loc.parentList[loc.index + 1] as EqText).text.isEmpty) {
      return loc.parentList[loc.index + 1] as EqText;
    }
    final fresh = EqText('');
    loc.parentList.insert(loc.index + 1, fresh);
    return fresh;
  }

  /// يحذف عقدة بنيوية ويدمج الخانات النصية المتجاورة حول موضع الحذف بسلاسة
  /// مع إرجاع الخانة النشطة الجديدة وموضع المؤشر الدقيق عند موضع الالتحام.
  ({EqText? focus, int caretOffset}) removeComponentAndRefocus(
    List<EqNode> parent,
    int index,
  ) {
    if (index < 0 || index >= parent.length) {
      final fallback = allLeafTextSlots();
      return (
        focus: fallback.isEmpty ? null : fallback.last,
        caretOffset: fallback.isEmpty ? 0 : fallback.last.text.length,
      );
    }
    parent.removeAt(index);

    // إذا التقى نصّان شقيقان حول موضع الحذف، يُدمجان دون فقد موضع المؤشر.
    if (index > 0 &&
        index <= parent.length &&
        index < parent.length &&
        parent[index - 1] is EqText &&
        parent[index] is EqText) {
      final left = parent[index - 1] as EqText;
      final right = parent[index] as EqText;
      final seam = left.text.length;
      left.text = left.text + right.text;
      parent.removeAt(index);
      return (focus: left, caretOffset: seam);
    }

    // إن أفرغ الحذف خانة فرعية (داخل بسط/جذر/قوس)، نضمن بقاء خانة قابلة للكتابة.
    if (!identical(parent, nodes) && parent.isEmpty) {
      final placeholder = EqText('');
      parent.add(placeholder);
      return (focus: placeholder, caretOffset: 0);
    }

    if (index < parent.length && parent[index] is EqText) {
      return (focus: parent[index] as EqText, caretOffset: 0);
    }
    if (index > 0 && parent[index - 1] is EqText) {
      final left = parent[index - 1] as EqText;
      return (focus: left, caretOffset: left.text.length);
    }
    final remaining = allLeafTextSlots();
    if (remaining.isEmpty) {
      return (focus: null, caretOffset: 0);
    }
    final clamped = index.clamp(0, remaining.length - 1);
    return (
      focus: remaining[clamped],
      caretOffset: remaining[clamped].text.length,
    );
  }

  static final RegExp _unicodeRadicalBraced = RegExp(r'√\{([^}]*)\}');
  static final RegExp _unicodeRadicalAtom = RegExp(r'√([A-Za-z0-9]+)');

  static String _normalizeLegacyInput(String latex) {
    if (!latex.contains('√') &&
        !latex.runes.any((r) => r >= 0x0080 && r != 0x00B0)) {
      return latex;
    }
    var normalized = MathSymbols.canonicalize(latex);
    if (normalized.contains('√')) {
      normalized = normalized
          .replaceAllMapped(_unicodeRadicalBraced, (m) => '\\sqrt{${m[1]}}')
          .replaceAllMapped(_unicodeRadicalAtom, (m) => '\\sqrt{${m[1]}}');
    }
    return normalized;
  }

  /// يحلّل LaTeX مخزَّناً إلى بنية مرئية قابلة للتحرير.
  ///
  /// البنى المدعومة تركيبياً: `\frac` و`\sqrt` (مع `[n]` الاختياري)
  /// والأسس والأدلة (`^`/`_`) والأقواس (`\left...\right`) والمجموعات.
  /// كل ما عداها (أوامر، رموز، نصوص) يُحفَظ حرفياً كـ [EqText] —
  /// فلا يُفقَد معنى أي معادلة قديمة ولا تُستبدل بأخرى فارغة.
  static EquationModel parse(String latex) {
    try {
      return EquationModel(
        nodes: _EqParser(_normalizeLegacyInput(latex)).parseTopLevel(),
      );
    } catch (_) {
      return EquationModel(nodes: <EqNode>[EqText(latex)]);
    }
  }

  /// نص مقروء لصيغة مخزَّنة — **آخر ارتداد** عندما يعجز محرك الرسم نفسه
  /// (`flutter_math_fork`) عن ترسيم صيغة (صيغة تالفة أو قديمة غير مدعومة):
  /// عرض خطي من شجرة العقد نفسها ([parse] لا يرمي أبداً) بلا أي رمز LaTeX
  /// (`\` و`$` و`{` و`}` لا تظهر) وبلا فقد محتوى.
  ///
  /// المسارات الطبيعية لا تصل إلى هنا إطلاقاً: المعاينة والـ PDF وWord
  /// ترتد كلها إلى المحرك نفسه (ودجت أو لقطة عالية الدقة) أو إلى OMML.
  static String readableText(String latex) => parse(latex).toDisplayText();

  /// عرض خطي مقروء لعقد المعادلة (انظر [readableText]).
  String toDisplayText() {
    final buffer = StringBuffer();
    for (final node in nodes) {
      _writeDisplayText(buffer, node);
    }
    return _tidyDisplayText(buffer.toString());
  }
}

/// يكتب العرض المقروء لعقدة واحدة (قواعد الخط الواحد في [EquationModel]).
void _writeDisplayText(StringBuffer buffer, EqNode node) {
  if (node is EqText) {
    buffer.write(_displayTextOfRaw(node.text));
    return;
  }
  if (node is EqGroup) {
    for (final child in node.children) {
      _writeDisplayText(buffer, child);
    }
    return;
  }
  if (node is EqFraction) {
    buffer.write('(');
    for (final child in node.numerator) {
      _writeDisplayText(buffer, child);
    }
    buffer.write(')/(');
    for (final child in node.denominator) {
      _writeDisplayText(buffer, child);
    }
    buffer.write(')');
    return;
  }
  if (node is EqSqrt) {
    if (node.root.isNotEmpty) {
      final root = _displayOfNodes(node.root);
      buffer.write(
        MathSymbols.hasSuperscriptForm(root)
            ? MathSymbols.toSuperscript(root)
            : '($root)',
      );
    }
    buffer.write('√(${_displayOfNodes(node.body)})');
    return;
  }
  if (node is EqSup) {
    buffer.write(_displayOfNodes(node.base));
    final exponent = _displayOfNodes(node.exponent);
    buffer.write(
      MathSymbols.hasSuperscriptForm(exponent)
          ? MathSymbols.toSuperscript(exponent)
          : '($exponent)',
    );
    return;
  }
  if (node is EqSub) {
    buffer.write(_displayOfNodes(node.base));
    final subscript = _displayOfNodes(node.subscript);
    buffer.write(
      MathSymbols.hasSubscriptForm(subscript)
          ? MathSymbols.toSubscript(subscript)
          : '($subscript)',
    );
    return;
  }
  if (node is EqFence) {
    buffer
      ..write(_displayDelimiter(node.left))
      ..write(_displayOfNodes(node.body))
      ..write(_displayDelimiter(node.right));
    return;
  }
  if (node is EqAccent) {
    // العلامة (سهم/قبعة/خط) لا صورة خطية لها: المحتوى وحده يُعرض كاملاً.
    buffer.write(_displayOfNodes(node.body));
    return;
  }
}

String _displayOfNodes(List<EqNode> nodes) {
  final buffer = StringBuffer();
  for (final node in nodes) {
    _writeDisplayText(buffer, node);
  }
  return buffer.toString();
}

/// محدد أقواس للعرض المقروء: `\left`/`\right` تُنزع، والمهروب `\{` محرف
/// حرفي، و`.` غير المرئي يُحذف — وبلا أي شرطة مائلة في الناتج.
String _displayDelimiter(String raw) {
  var value = raw.trim();
  for (final prefix in <String>[r'\left', r'\right']) {
    if (value.startsWith(prefix)) {
      value = value.substring(prefix.length).trim();
    }
  }
  if (value == '.') {
    return '';
  }
  return _displayTextOfRaw(value);
}

/// عرض نص حر: الأوامر من سجلّ [MathSymbols] (المعروف ← محرفه، والمجهول ←
/// اسمه بلا شرطة)، والبنى التي قد تصل خاماً داخل مقطع محفوظ حرفياً
/// (`\frac`/`\sqrt` داخل `\left` بلا `\right` مثلاً) تُعرض بنيتها نفسها،
/// والمحارف البنائية (`{` `}` `$` `\`) تُنزع، والأسس/الدلالات الشاردة
/// تُحوَّل صورها يونيكود عند القدرة — فلا يظهر كود LaTeX أبداً.
String _displayTextOfRaw(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  var index = 0;

  // وسيط واحد من المقطع الخام: مجموعة {...} متوازنة (أو ما بقي من غير
  // المغلقة) أو محرف واحد — ويُعرض داخلها عادياً.
  String readArgument() {
    while (index < raw.length && raw[index] == ' ') {
      index++;
    }
    if (index >= raw.length) {
      return '';
    }
    if (raw[index] != '{') {
      final char = raw[index];
      index++;
      return _displayTextOfRaw(char);
    }
    final start = index;
    var depth = 0;
    while (index < raw.length) {
      final char = raw[index];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          index++;
          break;
        }
      }
      index++;
    }
    final inner = depth == 0
        ? raw.substring(start + 1, index - 1)
        : raw.substring(start + 1);
    return _displayTextOfRaw(inner);
  }

  while (index < raw.length) {
    final char = raw[index];
    final match = MathSymbols.commandPattern.matchAsPrefix(raw, index);
    if (match != null) {
      index = match.end;
      final command = match.group(0)!;
      final escaped = MathSymbols.escapedCharacters[command];
      if (escaped != null) {
        // `\{` و`\$`... محارف حرفية كتبها المدرس فتبقى كما هي.
        buffer.write(escaped);
        continue;
      }
      final name = command.substring(1);
      if (name == 'left' || name == 'right') {
        // المحدد بعد `\left`/`\right` محرف عادي يليهما، و`.` غير المرئي يُحذف.
        if (index < raw.length && raw[index] == '.') {
          index++;
        }
        continue;
      }
      if (name == 'frac' || name == 'dfrac' || name == 'tfrac') {
        buffer.write('(${readArgument()})/(${readArgument()})');
        continue;
      }
      if (name == 'sqrt') {
        while (index < raw.length && raw[index] == ' ') {
          index++;
        }
        if (index < raw.length && raw[index] == '[') {
          final close = raw.indexOf(']', index);
          final root = close == -1
              ? raw.substring(index + 1)
              : raw.substring(index + 1, close);
          index = close == -1 ? raw.length : close + 1;
          final rootText = _displayTextOfRaw(root);
          buffer.write(
            MathSymbols.hasSuperscriptForm(rootText)
                ? MathSymbols.toSuperscript(rootText)
                : '($rootText)',
          );
        }
        buffer.write('√(${readArgument()})');
        continue;
      }
      final spacing = MathSymbols.spaceCommands[name];
      if (spacing != null) {
        if (spacing > -0.05) {
          buffer.write(spacing > 0.6 ? '  ' : ' ');
        }
        continue;
      }
      if (MathSymbols.textCommands.contains(name)) {
        // محتوى `\text{...}` نص حر يليها في المقطع نفسه.
        continue;
      }
      final glyph = MathSymbols.glyphFor(command);
      if (glyph != null) {
        buffer.write(glyph);
        continue;
      }
      // أمر مجهول: اسمه مقروءاً (`\foo` ← `foo`)، و`\` و`\\` فراغ.
      buffer.write(RegExp(r'^[A-Za-z]+$').hasMatch(name) ? name : ' ');
      continue;
    }
    index++;
    if (char == '{' || char == '}' || char == r'$' || char == r'\') {
      continue;
    }
    if (char == '^' || char == '_') {
      // أسّ/دليل شارد (من مقطع حرفي محفوظ): صورته يونيكود إن قُدر، وإلا
      // يبقى المحتوى وحده بلا علامة خام.
      if (index < raw.length) {
        final next = raw[index];
        final mapped = char == '^'
            ? MathSymbols.superscriptOf(next)
            : MathSymbols.subscriptOf(next);
        if (mapped != null) {
          buffer.write(mapped);
          index++;
          continue;
        }
      }
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

/// تطبيع نهائي للعرض المقروء: فراغات مفردة وبلا أطراف.
String _tidyDisplayText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

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
          final previous = nodes.removeLast();
          if (previous is EqGroup) {
            // `{x+1}^{2}` ← القاعدة هي محتوى المجموعة مباشرةً دون تكرار `{}`.
            base = previous.children.isEmpty
                ? <EqNode>[EqText('')]
                : previous.children;
          } else if (previous is EqText && previous.text.length > 1) {
            // في TeX يرتبط `^`/`_` بالمحرف الرياضي الأخير فقط (`5 + 6^{2}` ←
            // نص `'5 + '` يتبعه `6^{2}`، لا `'{5 + 6}^{2}'`).
            final runes = previous.text.runes.toList(growable: false);
            if (runes.length > 1) {
              final prefix =
                  String.fromCharCodes(runes.sublist(0, runes.length - 1));
              final lastAtom = String.fromCharCode(runes.last);
              nodes.add(EqText(prefix));
              base = <EqNode>[EqText(lastAtom)];
            } else {
              base = <EqNode>[previous];
            }
          } else {
            base = <EqNode>[previous];
          }
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
    if (command == r'\vec' || command == r'\hat' || command == r'\bar' ||
        command == r'\overline' || command == r'\widehat') {
      final kind = command == r'\vec'
          ? EqAccentKind.vector
          : (command == r'\hat' || command == r'\widehat')
              ? EqAccentKind.hat
              : EqAccentKind.bar;
      return EqAccent(kind: kind, body: _parseRequiredGroup());
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
    // الرمز المعروف يُعرض محرفاً مرئياً في خانة التحرير (بلا كود LaTeX)،
    // وما لا يُعرف يبقى حرفياً فلا يُفقَد معناه أبداً.
    return EqText(MathSymbols.toDisplay(command));
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
  ///
  /// الفراغ بعد الأمر **محتوى محفوظ** لا يُبتلع: العرض يبقى أميناً للمصدر
  /// (`\alpha \times 2` تُرى «α × 2» كما كُتبت)، والحفظ يعيد المصدر حرفياً —
  /// واستقرار البايت مطلب لأن الاستبدال في المخزون يتم بالفهارس
  /// (`TexContent.findSpans`).
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
