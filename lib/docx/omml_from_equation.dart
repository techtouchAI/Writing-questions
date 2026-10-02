/// مُصدِّر صيغ LaTeX إلى OMML (Office Math Markup Language) لملفات Word.
///
/// الهدف المعماري: أن تكون المعادلة في Word **معادلة أصلية قابلة للتحرير**،
/// لا صورة مضمّنة. لذلك لا يرسم هذا الملف أي محرف ولا يقيس أي صندوق: يحوّل
/// شجرة [EquationModel] — التمثيل البنيوي الواحد في التطبيق، وهو نفسه ما
/// يبنيه محرر المعادلات المرئي — إلى عناصر `m:` المعيارية (ECMA-376)، ثم
/// تتكفّل Word ذاتها بالتخطيط والخط (Cambria Math):
///
/// ```text
/// LaTeX المخزَّن ($…$ / $$…$$)
///   → MathSymbols.canonicalize      (تطبيع المكافئ و ² ← ^{2}، ₁ ← _{1})
///   → EquationModel.parse           (شجرة العقد نفسها)
///   → OMML: <m:oMath>…</m:oMath>    (معادلة Word حقيقية)
/// ```
///
/// لا محرك رياضيات ثانياً هنا: لا تباعد TeX يدوي، لا أقواس ممتدة مرسومة،
/// لا ascent/descent مخترَعة — كلها تنتقل إلى Word، فيختفي سبب اختلاف
/// الشكل بين المعاينة والملف.
///
/// ## ما لا يُمثَّل
/// المصفوفات و`cases` و`&` و`\\` (أسطر متعددة) و`\left…` بلا `\right` المقابل
/// — وهي أصلاً غير مدعومة في محرر المعادلات ولا في أي محرك آخر في التطبيق —
/// ترمي [OmmlUnsupportedError] فتعيد الواجهة العامة `null`؛ وعندها يرتدّ
/// المستدعي إلى رسم المعادلة **بمحرك التطبيق نفسه** (صورة عالية الدقة) لا
/// إلى نص كود LaTeX.
///
/// ## قواعد مضمونة بالفحص
/// * لا `\` ولا `$` في مخرَج واحد: ما لا يُمثَّل بُنيةً يُبلَّغ عن تعذّره.
/// * لا قياس ولا رسم ولا `dart:ui`: ملف Word يبقى pure Dart بالكامل.
/// * عمق التعشيش محدود بـ[maxDepth]، وصيغة تالفة لا تُسقط المستند كله.
library omml_from_equation;

import '../models/equation_model.dart';
import '../models/math_symbols.dart';

/// صيغة تخرج عن المجموعة التي تُمثَّل بنيةً في OMML.
class OmmlUnsupportedError implements Exception {
  OmmlUnsupportedError(this.message);

  final String message;

  @override
  String toString() => 'OMML غير مدعوم: $message';
}

/// تحويل صيغة LaTeX واحدة إلى منطقة رياضيات OMML جاهزة للإدراج في `<w:p>`.
abstract final class OmmlFromEquation {
  /// أقصى عمق تعشيش مقبول (حماية من صيغة تالفة متداخلة بلا نهاية).
  static const int maxDepth = 64;

  /// إعلان مساحة أسماء الرياضيات — يلزم على جذر كل جزء `word/*.xml`.
  static const String mathNamespaceDeclaration =
      'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"';

  /// خط المعادلات الذي تفتحه Word افتراضياً؛ يُذكر صراحةً ليعرض الملف
  /// كما هو في LibreOffice وWord للجوال/الويب.
  static const String mathFont = 'Cambria Math';

  /// يبني `<m:oMath>…</m:oMath>` (منطقة رياضيات **سطرية** تُدرَج داخل
  /// الفقرة بجانب `<w:r>`، فتنزل حيث نزلت `$…$` في الجملة تماماً).
  ///
  /// يعيد `null` عند التعذّر (صيغة خارج المجموعة الممثَّلة، أو فراغ تام).
  ///
  /// [fontSizePt] حجم خط الفقرة بالنقاط (يُحوَّل إلى أنصاف النقاط في
  /// `w:sz`)، و[extraRunProperties] إضافات `w:rPr` المورَّثة من جيران
  /// المعادلة (`<w:b/>`/`<w:i/>`/`<w:color …/>`) لتبقى المعادلة على تنسيق
  /// سطر نفسه.
  static String? mathZoneXml(
    String latex, {
    required double fontSizePt,
    String extraRunProperties = '',
    bool display = false,
  }) {
    try {
      final emitter = _OmmlEmitter(
        sizeHalfPoints: _halfPoints(fontSizePt),
        extraRunProperties: extraRunProperties,
        display: display,
      );
      final content = emitter.emitSequence(parseNodes(latex));
      if (content.trim().isEmpty) {
        return null;
      }
      return '<m:oMath>$content</m:oMath>';
    } catch (_) {
      // أي تعذّر — محلّل أو مُصدِّر — ارتدادٌ إلى رسم المحرك الأصلي.
      return null;
    }
  }

  /// يبني `<m:oMathPara>` (معادلة **سطر مستقل**، تُستعمل للمعادلة الحرة
  /// العائمة وللمرفقات): فقرة رياضيات بمحاذاة كاملة.
  static String? mathParagraphXml(
    String latex, {
    required double fontSizePt,
    String extraRunProperties = '',
    String justification = 'center',
  }) {
    final zone = mathZoneXml(
      latex,
      fontSizePt: fontSizePt,
      extraRunProperties: extraRunProperties,
      display: true,
    );
    if (zone == null) {
      return null;
    }
    return '<m:oMathPara><m:oMathParaPr><m:jc m:val="$justification"/>'
        '</m:oMathParaPr>$zone</m:oMathPara>';
  }

  /// يحوّل LaTeX إلى عقد [EquationModel] بعد التطبيع، ويرفض ما لا يُمثَّل.
  ///
  /// الرفض هنا — لا أثناء البناء — لأن `[&]` و`\begin{…}` و`\\` تُخزن
  /// **نصاً حرفياً** داخل العقد (بنيّة «لا يُفقَد أي محتوى») فتمرّ على أي
  /// محلّل، بينما هي في OMML تحتاج `m:m`/`m:eqArr` لا يولّدهما هذا المُصدِّر.
  static List<EqNode> parseNodes(String latex) {
    final source = MathSymbols.canonicalize(latex.trim());
    if (source.isEmpty) {
      throw OmmlUnsupportedError('صيغة فارغة.');
    }
    if (source.contains('&') ||
        source.contains(r'\begin') ||
        source.contains(r'\end') ||
        source.contains(r'\\')) {
      throw OmmlUnsupportedError('تخطيط متعدد الأسطر أو مصفوفة.');
    }
    // أقواس معقوفة غير متوازنة = صيغة مبتورة: ما يُبتر لا يُمثَّل (المعاينة
    // ترفضه أيضاً وترتد إلى النص، فترفضه هنا لتُرسَم صورتُه بدل أن تخرج
    // شجرةً ناقصة بلا معنى).
    var depth = 0;
    for (final char in source.codeUnits) {
      if (char == 0x7B) {
        depth++;
      } else if (char == 0x7D) {
        depth--;
        if (depth < 0) {
          throw OmmlUnsupportedError('قوس } زائد غير مغلق.');
        }
      }
    }
    if (depth != 0) {
      throw OmmlUnsupportedError('مجموعة غير مغلقة.');
    }
    final model = EquationModel.parse(source);
    if (model.toLatex().trim().isEmpty) {
      throw OmmlUnsupportedError('لا محتوى قابل للتمثيل.');
    }
    return model.nodes;
  }

  /// `w:sz` بأنصاف النقاط، في المدى الذي تقبله Word فعلاً.
  static int _halfPoints(double fontSizePt) {
    final rounded = (fontSizePt * 2).round();
    return rounded.clamp(8, 144);
  }
}

/// بانِي عناصر `m:` من شجرة العقد.
class _OmmlEmitter {
  _OmmlEmitter({
    required this.sizeHalfPoints,
    required this.extraRunProperties,
    required this.display,
  });

  final int sizeHalfPoints;
  final String extraRunProperties;

  /// معادلة عرض (سطر مستقل أو `$$…$$`): الحدود فوق العامل الكبير وتحته.
  final bool display;

  int _depth = 0;

  /// محارف العوامل الكبيرة من سجلّ الرموز نفسه (طول محرف واحد).
  static final Set<String> _bigOperatorGlyphs = <String>{
    for (final glyph in MathSymbols.bigOperators.values)
      if (glyph.length == 1) glyph,
  };

  /// أسماء الدوال ذات المحارف المتعددة (`lim`، `sin`…) — تُكتب قائمةً
  /// (upright) بلا ميل، ولها حدّ واحد تحتها `m:limLow`/فوقها `m:limUpp`.
  static final Set<String> _operatorNames = <String>{
    for (final glyph in MathSymbols.bigOperators.values)
      if (glyph.length > 1) glyph,
  };

  /// المحددات التي تُمثَّل في `m:dPr` (سواها يُلغي الصيغة كلها ← رسم).
  static const Map<String, String> _delimiters = <String, String>{
    '(': '(',
    ')': ')',
    '[': '[',
    ']': ']',
    r'\{': '{',
    r'\}': '}',
    r'\lbrace': '{',
    r'\rbrace': '}',
    '|': '|',
    r'\|': '\u2016',
    r'\vert': '|',
    r'\Vert': '\u2016',
    r'\langle': '\u27E8',
    r'\rangle': '\u27E9',
    r'\lfloor': '\u230A',
    r'\rfloor': '\u230B',
    r'\lceil': '\u2308',
    r'\rceil': '\u2309',
    '.': '',
  };

  /// متتالية عقد ← XML.
  String emitSequence(List<EqNode> nodes, {bool upright = false}) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < nodes.length) {
      final node = nodes[index];
      // `\text{cm}` و`\mathrm{…}` و`\operatorname{…}`: المحلّل يترك الأمر
      // نصاً والمجموعة عقدة تالية — هنا تُدمجان في جريان قائمة واحد.
      if (node is EqText && index + 1 < nodes.length) {
        final command = _textCommandName(node.text);
        final next = nodes[index + 1];
        if (command != null && next is EqGroup) {
          buffer.write(emitSequence(next.children, upright: true));
          index += 2;
          continue;
        }
      }
      buffer.write(emitNode(node, upright: upright));
      index++;
    }
    return buffer.toString();
  }

  String emitNode(EqNode node, {bool upright = false}) {
    if (_depth >= OmmlFromEquation.maxDepth) {
      throw OmmlUnsupportedError('تعشيش أعمق من ${OmmlFromEquation.maxDepth}.');
    }
    _depth++;
    try {
      if (node is EqText) {
        final buffer = StringBuffer();
        emitText(buffer, node.text, upright: upright);
        return buffer.toString();
      }
      if (node is EqGroup) {
        // المجموعة تحديدٌ تركيبي في LaTeX لا صندوق في OMML: الأبناء يكتفون
        // بوعاء `m:e`/`m:num`/`m:den` الذي يحويهم أصلاً.
        return emitSequence(node.children, upright: upright);
      }
      if (node is EqFraction) {
        return '<m:f>'
            '<m:num>${emitSequence(node.numerator)}</m:num>'
            '<m:den>${emitSequence(node.denominator)}</m:den>'
            '</m:f>';
      }
      if (node is EqSqrt) {
        return _radical(node);
      }
      if (node is EqSup) {
        return _scripts(base: node.base, sup: node.exponent);
      }
      if (node is EqSub) {
        return _scripts(base: node.base, sub: node.subscript);
      }
      if (node is EqFence) {
        return _fence(node);
      }
      if (node is EqAccent) {
        return _accent(node);
      }
      throw OmmlUnsupportedError('عقدة غير معروفة (${node.runtimeType}).');
    } finally {
      _depth--;
    }
  }

  // ------------------------------ النصوص ------------------------------ //

  /// نص حر ← جريانات `m:r`. والأوامر التي لا بناء لها ههنا تُعامَل كما
  /// تُعامَل في المعاينة: أمر مسافة ← مسافة، واسم دالة ← اسمٌ قائم — فلا
  /// يظهر `\` في الملف أبداً، ولا يضيع محتوى.
  void emitText(StringBuffer buffer, String raw, {required bool upright}) {
    if (raw.isEmpty) {
      return;
    }
    final plain = StringBuffer();
    void flushPlain() {
      if (plain.isEmpty) {
        return;
      }
      buffer.write(_run(plain.toString(), upright: upright));
      plain.clear();
    }

    var index = 0;
    while (index < raw.length) {
      final char = raw[index];
      final match = MathSymbols.commandPattern.matchAsPrefix(raw, index);
      if (match == null) {
        // اسم دالة معروف (`sin` في `\sin x` أو في المكتوب حرفياً): قائمٌ
        // كما تُصلحه Word نفسها، لا مائل ولا كود.
        final nameEnd = _operatorNameEnd(raw, index);
        if (nameEnd > index) {
          flushPlain();
          buffer.write(_run(raw.substring(index, nameEnd), upright: true));
          index = nameEnd;
          continue;
        }
        plain.write(char);
        index++;
        continue;
      }
      final command = match.group(0) ?? '';
      index = match.end;
      final name = command.substring(1);
      if (_manualSizeCommands.contains(name)) {
        throw OmmlUnsupportedError('محدد بحجم يدوي ($command).');
      }
      final spacing = MathSymbols.spaceCommands[name];
      if (spacing != null) {
        flushPlain();
        // لا أوامر مسافة في `m:t`؛ تُقارَب بمسافات نصية: ما دون نصف
        // em←مسافة واحدة، وquad فما فوق←مسافتان، و\! ← لا شيء.
        final spaces = spacing <= -0.05 ? 0 : (spacing <= 0.6 ? 1 : 2);
        if (spaces > 0) {
          buffer.write(_run(' ' * spaces, upright: true));
        }
        continue;
      }
      final glyph = MathSymbols.glyphFor(command);
      if (glyph != null) {
        // الرمز أحادي المحرف يبقى على ميل الرياضيات، واسم الدالة قائمة.
        flushPlain();
        if (glyph.length == 1) {
          plain.write(glyph);
        } else {
          buffer.write(_run(glyph, upright: true));
        }
        continue;
      }
      // اسم حرّ كتبه المدرس (`\floor`…) — يُرسم قائماً بلا شرطة مائلة.
      flushPlain();
      buffer.write(_run(name, upright: true));
    }
    flushPlain();
  }

  /// نهاية اسم دالة معروفة يبدأ عند [index]، أو -1 إن لم يكن.
  /// تُؤخذ كل الحروف دفعةً واحدة: `sinx` متغيرات لا دالة، فلا تُقام.
  int _operatorNameEnd(String source, int index) {
    if (!_isAsciiLetter(source.codeUnitAt(index))) {
      return -1;
    }
    var end = index;
    while (end < source.length && _isAsciiLetter(source.codeUnitAt(end))) {
      end++;
    }
    if (!_operatorNames.contains(source.substring(index, end))) {
      return -1;
    }
    return end;
  }

  /// أوامر أحجام المحددات وبيئات النص: لا تُمثَّل في هذه المجموعة.
  static const Set<String> _manualSizeCommands = <String>{
    'left', 'right', 'begin', 'end', 'middle',
    'big', 'Big', 'bigg', 'Bigg',
    'bigl', 'Bigl', 'biggl', 'Biggl',
    'bigr', 'Bigr', 'biggr', 'Biggr',
    'bigm', 'Bigm',
  };

  static bool _isAsciiLetter(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  /// جريان رياضيات واحد: `m:rPr` (اختياري) ثم `w:rPr` ثم `m:t`.
  /// الترتيب مفروض بمخطط `CT_R`.
  String _run(String text, {required bool upright}) {
    final escaped = _escape(text);
    if (escaped.isEmpty) {
      return '';
    }
    const font = OmmlFromEquation.mathFont;
    final buffer = StringBuffer('<m:r>');
    if (upright) {
      buffer.write('<m:rPr><m:sty m:val="p"/></m:rPr>');
    }
    buffer
      ..write('<w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>')
      ..write(extraRunProperties)
      ..write('<w:sz w:val="$sizeHalfPoints"/>')
      ..write('<w:szCs w:val="$sizeHalfPoints"/></w:rPr>')
      ..write('<m:t xml:space="preserve">$escaped</m:t></m:r>');
    return buffer.toString();
  }

  String _escape(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
        buffer.write(' ');
        continue;
      }
      final valid = rune == 0x20 ||
          (rune >= 0x20 && rune <= 0xD7FF) ||
          (rune >= 0xE000 && rune <= 0xFFFD) ||
          (rune >= 0x10000 && rune <= 0x10FFFF);
      if (!valid) {
        continue;
      }
      final char = String.fromCharCode(rune);
      switch (char) {
        case '&':
          buffer.write('&amp;');
        case '<':
          buffer.write('&lt;');
        case '>':
          buffer.write('&gt;');
        case '"':
          buffer.write('&quot;');
        default:
          buffer.write(char);
      }
    }
    return buffer.toString();
  }

  // ------------------------------ البنى ------------------------------ //

  String _radical(EqSqrt node) {
    if (!_hasContent(node.body)) {
      throw OmmlUnsupportedError('جذر بلا ما تحته.');
    }
    final hasDegree = _hasContent(node.root);
    final degree = hasDegree
        ? '<m:deg>${emitSequence(node.root)}</m:deg>'
        : '<m:deg/>';
    final hideDegree = hasDegree ? '' : '<m:degHide m:val="1"/>';
    return '<m:rad><m:radPr>$hideDegree</m:radPr>$degree'
        '<m:e>${emitSequence(node.body)}</m:e></m:rad>';
  }

  /// أسّ/دليل — مع تصحيحين لازمَين للسلوك الصحيح:
  /// 1. `{x_{1}}^{2}` (ما يخزنه المحرر لـ `x_1^2`) تُدمج في `m:sSubSup`
  ///    كما تفعل Word نفسها، فلا تخرج (x₁)² بسطر أدلة متكدّس.
  /// 2. العامل الكبير (`∑`/`∫`…) يصبح `m:nary` بحدوده، لا حرفاً وعقداً.
  String _scripts({
    required List<EqNode> base,
    List<EqNode>? sub,
    List<EqNode>? sup,
  }) {
    var baseNodes = base;
    var subNodes = sub;
    var supNodes = sup;
    // المجموعة حول الأساس تحديدٌ تركيبي لا صندوق: {x_{1}}^{2} تُقرأ x_{1}^{2}.
    baseNodes = _unwrapGroup(baseNodes);
    if (subNodes == null &&
        supNodes != null &&
        baseNodes.length == 1 &&
        baseNodes.single is EqSub) {
      final inner = baseNodes.single as EqSub;
      baseNodes = inner.base;
      subNodes = inner.subscript;
    } else if (supNodes == null &&
        subNodes != null &&
        baseNodes.length == 1 &&
        baseNodes.single is EqSup) {
      final inner = baseNodes.single as EqSup;
      baseNodes = inner.base;
      supNodes = inner.exponent;
    }

    final operatorGlyph = _singleGlyphOf(baseNodes);
    if (operatorGlyph != null && _bigOperatorGlyphs.contains(operatorGlyph)) {
      return _nary(operatorGlyph, subNodes, supNodes);
    }
    final operatorName = _singleTextOf(baseNodes);
    if (operatorName != null && _operatorNames.contains(operatorName)) {
      if (subNodes != null && supNodes == null) {
        return '<m:limLow>'
            '<m:e>${_run(operatorName, upright: true)}</m:e>'
            '<m:lim>${emitSequence(subNodes)}</m:lim>'
            '</m:limLow>';
      }
      if (supNodes != null && subNodes == null) {
        return '<m:limUpp>'
            '<m:e>${_run(operatorName, upright: true)}</m:e>'
            '<m:lim>${emitSequence(supNodes)}</m:lim>'
            '</m:limUpp>';
      }
    }

    // TeX يرفع **آخر وحدة** فقط: في `ax^2` تُرفع x وحدها، لا "ax". والمحلّل
    // يخزّن النص المتّصلاً كتشغيلة واحدة أساساً، فتُقدَّم ما قبل الوحدة
    // الأخيرة جرياناً عادياً وتُرفع هي وحدها — كما تفعل المعاينة تماماً.
    var lead = '';
    if ((subNodes != null || supNodes != null) &&
        baseNodes.length == 1 &&
        baseNodes.single is EqText) {
      final atoms = _atoms((baseNodes.single as EqText).text);
      if (atoms.length > 1 && _raisable(atoms.last)) {
        final prefix = StringBuffer();
        emitText(prefix, atoms.take(atoms.length - 1).join(), upright: false);
        lead = prefix.toString();
        baseNodes = <EqNode>[EqText(atoms.last)];
      }
    }

    final body = emitSequence(baseNodes);
    final subXml = subNodes == null ? null : emitSequence(subNodes);
    final supXml = supNodes == null ? null : emitSequence(supNodes);
    if (body.isEmpty && (subXml ?? '').isEmpty && (supXml ?? '').isEmpty) {
      // `^` وحدها بلا أساس ولا أسّ: لا شيء يُعرض، والمعاينة ترفضها أيضاً.
      throw OmmlUnsupportedError('أسّ أو دليل بلا طرفين.');
    }
    if (subXml != null && supXml != null) {
      return '$lead<m:sSubSup><m:e>$body</m:e>'
          '<m:sub>$subXml</m:sub><m:sup>$supXml</m:sup></m:sSubSup>';
    }
    if (subXml != null) {
      return '$lead<m:sSub><m:e>$body</m:e><m:sub>$subXml</m:sub></m:sSub>';
    }
    if (supXml != null) {
      return '$lead<m:sSup><m:e>$body</m:e><m:sup>$supXml</m:sup></m:sSup>';
    }
    return body;
  }

  /// عامل كبير بحدوده. `m:e` (المُعامِل) يبقى فارغاً: ما بعد العامل في المخزون
  /// عقدٌ أخوة لا أبناء، فتُطبع جريانات تالية بعد المنطقة — وهو موضعها نفسه
  /// حين تُدخل المعادلة في Word يدوياً.
  String _nary(String glyph, List<EqNode>? sub, List<EqNode>? sup) {
    final limitLocation = display ? 'undOvr' : 'subSup';
    final buffer = StringBuffer('<m:nary><m:naryPr>')
      ..write('<m:chr m:val="${_escape(glyph)}"/>')
      ..write('<m:limLoc m:val="$limitLocation"/>')
      ..write('<m:subHide m:val="${sub == null ? '1' : '0'}"/>')
      ..write('<m:supHide m:val="${sup == null ? '1' : '0'}"/>')
      ..write('</m:naryPr>')
      ..write('<m:sub>${sub == null ? '' : emitSequence(sub)}</m:sub>')
      ..write('<m:sup>${sup == null ? '' : emitSequence(sup)}</m:sup>')
      ..write('<m:e/></m:nary>');
    return buffer.toString();
  }

  String _fence(EqFence node) {
    if (!_hasContent(node.body)) {
      throw OmmlUnsupportedError('قوسان بلا ما بينهما.');
    }
    final stretchy =
        node.left.startsWith(r'\left') || node.right.startsWith(r'\right');
    if (!stretchy) {
      // أقواس عادية (بلا `\left`): تُكتب محرفاً كما في المعاينة — بلا تمدّد،
      // فيبقى شكلها مطابقاً للوحة.
      final buffer = StringBuffer();
      emitText(buffer, node.left, upright: false);
      buffer.write(emitSequence(node.body));
      emitText(buffer, node.right, upright: false);
      return buffer.toString();
    }
    final left = _delimiter(node.left, r'\left');
    final right = _delimiter(node.right, r'\right');
    if (left == null || right == null) {
      throw OmmlUnsupportedError(r'محدد غير معروف في `\left…\right`.');
    }
    final properties = StringBuffer('<m:dPr>');
    if (left.isEmpty) {
      properties.write('<m:begChr m:val=""/>');
    }
    if (right.isEmpty) {
      properties.write('<m:endChr m:val=""/>');
    }
    if (left.isNotEmpty && left != '(') {
      properties.write('<m:begChr m:val="${_escape(left)}"/>');
    }
    if (right.isNotEmpty && right != ')') {
      properties.write('<m:endChr m:val="${_escape(right)}"/>');
    }
    properties.write('</m:dPr>');
    return '<m:d>$properties<m:e>${emitSequence(node.body)}</m:e></m:d>';
  }

  String _accent(EqAccent node) {
    if (!_hasContent(node.body)) {
      throw OmmlUnsupportedError('علامة بلا ما فوقها.');
    }
    final body = emitSequence(node.body);
    // تغطية كاملة للأنواع الثلاثة، والخط فوق تنسيق Word الأصيل لا محرف
    // مركّب (يبقى قابلاً للتحرير كامتداد حرف بدل رمز ملتحق).
    return switch (node.kind) {
      EqAccentKind.bar => '<m:bar><m:barPr><m:pos m:val="top"/></m:barPr>'
          '<m:e>$body</m:e></m:bar>',
      EqAccentKind.hat => _accentMark('\u0302', body),
      EqAccentKind.vector => _accentMark('\u20D7', body),
    };
  }

  String _accentMark(String character, String body) =>
      '<m:acc><m:accPr><m:chr m:val="$character"/></m:accPr>'
      '<m:e>$body</m:e></m:acc>';

  // ------------------------------ أدوات ------------------------------ //

  /// اسم أمر نصي (`\text`، `\mathrm`…) إن كان نص العقدة الأمر وحده، وإلا null.
  static String? _textCommandName(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 2 || !trimmed.startsWith(r'\')) {
      return null;
    }
    final name = trimmed.substring(1);
    if (!MathSymbols.textCommands.contains(name)) {
      return null;
    }
    if (MathSymbols.commandPattern.matchAsPrefix(trimmed)?.group(0) != trimmed) {
      return null;
    }
    return name;
  }

  static String? _delimiter(String raw, String prefix) {
    var value = raw.trim();
    if (value.startsWith(prefix)) {
      value = value.substring(prefix.length).trim();
    }
    return _delimiters[value];
  }

  static bool _hasContent(List<EqNode> nodes) {
    for (final node in nodes) {
      if (node is EqText) {
        if (node.text.trim().isNotEmpty) {
          return true;
        }
        continue;
      }
      return true;
    }
    return false;
  }

  /// تقسيم نص إلى وحدات TeX: أمرٌ كامل (`\\alpha`) أو زوج مُرمَّز أو محرف.
  static List<String> _atoms(String source) {
    final atoms = <String>[];
    var index = 0;
    while (index < source.length) {
      final match = MathSymbols.commandPattern.matchAsPrefix(source, index);
      if (match != null) {
        atoms.add(match.group(0) ?? '');
        index = match.end;
        continue;
      }
      final code = source.codeUnitAt(index);
      if (code >= 0xD800 &&
          code <= 0xDBFF &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) >= 0xDC00 &&
          source.codeUnitAt(index + 1) <= 0xDFFF) {
        atoms.add(source.substring(index, index + 2));
        index += 2;
        continue;
      }
      atoms.add(source[index]);
      index++;
    }
    return atoms;
  }

  /// هل تصلح الوحدة أساساً لأسّ/دليل؟ حرف أو رقم (لاتيني/لايني/يوناني/
  /// سيريلي) أو أمر كامل — لا رمز عملية ولا مسافة: في `x ^ 2` تقابل المسافة
  /// آخر وحدة، والرفع بلا معنى؛ والمقصود رفع الحرف.
  static bool _raisable(String atom) {
    if (atom.isEmpty) {
      return false;
    }
    if (atom.startsWith(r'\')) {
      return atom.length > 1;
    }
    return _isLetterOrDigit(atom.runes.last);
  }

  static bool _isLetterOrDigit(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0xC0 && code <= 0x24F) ||
      (code >= 0x370 && code <= 0x3FF) ||
      (code >= 0x400 && code <= 0x4FF);

  /// مجموعة واحدة التفّت حول الأساس ← أبناؤها مباشرةً.
  static List<EqNode> _unwrapGroup(List<EqNode> nodes) {
    if (nodes.length == 1 && nodes.single is EqGroup) {
      final inner = (nodes.single as EqGroup).children;
      if (inner.isNotEmpty) {
        return inner;
      }
    }
    return nodes;
  }

  /// المحرف الوحيد إن كانت العقدة نصاً واحداً (أو مجموعةً تحوي نصاً واحداً).
  static String? _singleGlyphOf(List<EqNode> nodes) {
    final text = _singleTextOf(nodes);
    if (text == null || text.length != 1) {
      return null;
    }
    return text;
  }

  static String? _singleTextOf(List<EqNode> nodes) {
    if (nodes.length != 1) {
      return null;
    }
    final node = nodes.single;
    if (node is EqText) {
      final trimmed = node.text.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (node is EqGroup) {
      return _singleTextOf(node.children);
    }
    return null;
  }
}
