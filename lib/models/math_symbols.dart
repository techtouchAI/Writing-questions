/// السجلّ canonical للرموز الرياضية — **مصدر الحقيقة الوحيد** لكل المحركات.
///
/// التطبيق يمنع ظهور أكواد LaTeX في أي مرحلة (إدخال/عرض/تصدير)، وفي الوقت
/// نفسه يجب أن يُطبع كل ما يكتبه المدرس معادلةً مرسومةً في الـ PDF وWord.
/// هذان الشرطان يتحقّقان فقط إن اتفقت كل المحركات على جدول واحد:
///
/// ```text
/// خانة التحرير المرئية  ←(عرض)←  [toDisplay]  ←  LaTeX المخزَّن
///                        →(حفظ)→  [toLatex]    →  LaTeX المخزَّن
/// الـ PDF / Word         ←  [canonicalize]  ←  LaTeX المخزَّن
/// البديل النصي الآمن     ←  [glyphFor]      ←  LaTeX المخزَّن
/// ```
///
/// - [glyphs] و[bigOperators]: أمر LaTeX ← محرفه المرئي.
/// - [aliases]: كل محرف مكافئ (شرطة ناقص يونيكود، أرقام عربية العلامة،
///   أشكال بعرض كامل...) ← صورته القياسية، فلا يفشل الرسم بسبب طريقة الكتابة.
/// - [latexSafe]: الأوامر التي تعرفها **كل** المحركات (الشاشة عبر
///   flutter_math_fork، والمتجه في الـ PDF، والبديل النصي) — وحدها تُستعمل
///   عند تحويل محرف مرئي إلى أمر، فلا يُنتَج أمر يعجز محرّك عنه.
abstract final class MathSymbols {
  /// المحارف المرئية لأوامر LaTeX المعروفة (بلا الشرطة المائلة).
  static const Map<String, String> glyphs = <String, String>{
    'times': '×',
    'div': '÷',
    'pm': '±',
    'mp': '∓',
    'cdot': '·',
    'leq': '≤',
    'le': '≤',
    'geq': '≥',
    'ge': '≥',
    'neq': '≠',
    'ne': '≠',
    'approx': '≈',
    'cong': '≅',
    'equiv': '≡',
    'sim': '∼',
    'simeq': '≃',
    'propto': '∝',
    'to': '→',
    'rightarrow': '→',
    'leftarrow': '←',
    'leftrightarrow': '↔',
    'Rightarrow': '⇒',
    'Leftrightarrow': '⇔',
    'rightleftharpoons': '⇌',
    'infty': '∞',
    'partial': '∂',
    'nabla': '∇',
    'degree': '°',
    'angle': '∠',
    'perp': '⊥',
    'parallel': '∥',
    'circ': '∘',
    'in': '∈',
    'notin': '∉',
    'subset': '⊂',
    'supset': '⊃',
    'subseteq': '⊆',
    'supseteq': '⊇',
    'cup': '∪',
    'cap': '∩',
    'emptyset': '∅',
    'forall': '∀',
    'exists': '∃',
    'neg': '¬',
    'lnot': '¬',
    'land': '∧',
    'wedge': '∧',
    'lor': '∨',
    'vee': '∨',
    'oplus': '⊕',
    'otimes': '⊗',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'varepsilon': 'ε',
    'zeta': 'ζ',
    'eta': 'η',
    'theta': 'θ',
    'vartheta': 'ϑ',
    'iota': 'ι',
    'kappa': 'κ',
    'lambda': 'λ',
    'mu': 'μ',
    'nu': 'ν',
    'xi': 'ξ',
    'pi': 'π',
    'rho': 'ρ',
    'sigma': 'σ',
    'tau': 'τ',
    'upsilon': 'υ',
    'phi': 'φ',
    'varphi': 'ϕ',
    'chi': 'χ',
    'psi': 'ψ',
    'omega': 'ω',
    'Gamma': 'Γ',
    'Delta': 'Δ',
    'Theta': 'Θ',
    'Lambda': 'Λ',
    'Xi': 'Ξ',
    'Pi': 'Π',
    'Sigma': 'Σ',
    'Upsilon': 'Υ',
    'Phi': 'Φ',
    'Psi': 'Ψ',
    'Omega': 'Ω',
  };

  /// الأوامر التي تُرسم كبيرةً (تكامل/مجموع/جداء/دوال) بمحارفها.
  static const Map<String, String> bigOperators = <String, String>{
    'int': '∫',
    'iint': '∬',
    'iiint': '∭',
    'oint': '∮',
    'sum': '∑',
    'prod': '∏',
    'lim': 'lim',
    'log': 'log',
    'lg': 'lg',
    'ln': 'ln',
    'sin': 'sin',
    'cos': 'cos',
    'tan': 'tan',
    'cot': 'cot',
    'sec': 'sec',
    'csc': 'csc',
    'exp': 'exp',
    'max': 'max',
    'min': 'min',
  };

  /// أوامر الأوامر النصية التي تُعرض بمحتواها حرفياً (`\text{cm}` ← `cm`).
  static const Set<String> textCommands = <String>{
    'text',
    'mathrm',
    'textrm',
    'mathbf',
    'textbf',
    'mathit',
    'textit',
    'operatorname',
    'mbox',
    'hbox',
  };

  /// أوامر تُنتج مسافة (لا محرفاً).
  static const Map<String, double> spaceCommands = <String, double>{
    ',': 0.17,
    ':': 0.22,
    ';': 0.28,
    '!': -0.09,
    ' ': 0.25,
    'quad': 1.0,
    'qquad': 2.0,
    'enspace': 0.5,
    'thinspace': 0.17,
  };

  /// محارف مكافئة ← صورتها القياسية.
  ///
  /// طريقة الكتابة تختلف بين لوحات المفاتيح (ناقص يونيكود U+2212 بدل `-`،
  /// شرطة عربية `٪` بدل `%`، أشكال بعرض كامل...) والرسم يجب ألا يفشل بسببها؛
  /// لذلك تُطبَّع قبل أي تحليل في كل المحركات.
  static const Map<String, String> aliases = <String, String>{
    // شرائط وعلامات ناقص بكل أشكالها ← ناقص قياسي واحد.
    '\u2212': '-', // − MINUS SIGN
    '\u2010': '-', // ‐ HYPHEN
    '\u2011': '-', // ‑ NON-BREAKING HYPHEN
    '\u2012': '-', // ‒ FIGURE DASH
    '\u2013': '-', // – EN DASH
    '\u2014': '-', // — EM DASH
    '\u2015': '-', // ― HORIZONTAL BAR
    '\u2043': '-', // ⁃ HYPHEN BULLET
    '\uFF0D': '-', // － FULLWIDTH HYPHEN-MINUS
    // عمليات
    '\u2217': '*', // ∗ ASTERISK OPERATOR
    '\uFF0A': '*', // ＊
    '\u2022': '·', // • BULLET ← نقطة ضرب
    '\u22C5': '·', // ⋅ DOT OPERATOR
    '\uFF0B': '+', // ＋
    '\uFF1D': '=', // ＝
    '\uFF1C': '<', // ＜
    '\uFF1E': '>', // ＞
    '\u2044': '/', // ⁄ FRACTION SLASH
    '\u2215': '/', // ∕ DIVISION SLASH
    '\uFF0F': '/', // ／
    '\u2715': '×', // ✕
    '\u2716': '×', // ✖
    '\u2717': '×', // ✗
    '\uFF5C': '|', // ｜
    '\u2032': "'", // ′ PRIME
    '\u2033': "''", // ″ DOUBLE PRIME
    // علاقات
    '\u2A7D': '≤', // ⩽ LESS-THAN OR SLANTED EQUAL
    '\u2266': '≤', // ≦ LESS-THAN OVER EQUAL
    '\u2A7E': '≥', // ⩾ GREATER-THAN OR SLANTED EQUAL
    '\u2267': '≥', // ≧ GREATER-THAN OVER EQUAL
    '\u2248': '≈', // ≈ (قياسي نفسه — يُثبَّت هنا توثيقاً)
    '\u27F6': '→', // ⟶ LONG RIGHTWARDS ARROW
    '\u27F5': '←', // ⟵ LONG LEFTWARDS ARROW
    '\u27F7': '↔', // ⟷ LONG LEFT RIGHT ARROW
    '\u2039': '«', // ‹ SINGLE LEFT-POINTING ANGLE QUOTATION
    '\u203A': '»', // › SINGLE RIGHT-POINTING ANGLE QUOTATION
    // علامات الترقيم العربية ← مقابلاتها الرياضية (كتابة بلوحة عربية)
    '\u066A': '%', // ٪ ARABIC PERCENT SIGN
    '\u066B': '.', // ٫ ARABIC DECIMAL SEPARATOR
    '\u066C': ',', // ٬ ARABIC THOUSANDS SEPARATOR
    '\u061B': ';', // ؛ ARABIC SEMICOLON
    '\u061F': '?', // ؟ ARABIC QUESTION MARK
    '\u060C': ',', // ، ARABIC COMMA
    // أقواس بعرض كامل ← أقواس قياسية
    '\uFF08': '(',
    '\uFF09': ')',
    '\uFF3B': '[',
    '\uFF3D': ']',
    '\uFF5B': '{',
    '\uFF5D': '}',
    // يونانية
    '\u03C2': 'σ', // ς SIGMA FINAL ← sigma
    // فراغات غير قياسية ← فراغ عادي
    '\u00A0': ' ',
    '\u2007': ' ',
    '\u202F': ' ',
    '\u2009': ' ',
  };

  /// أوامر مهرَّبة تمثّل محرفاً حرفياً (`\{` ← `{`) — تُعرض محرفاً في
  /// خانة التحرير وتُهرَّب عند الحفظ، فلا تُفسَد بنية الصيغة أبداً.
  static const Map<String, String> escapedCharacters = <String, String>{
    r'\{': '{',
    r'\}': '}',
    r'\%': '%',
    r'\&': '&',
    r'\#': '#',
    r'\$': r'$',
    r'\_': '_',
  };

  /// الأوامر التي تعرفها **كل** المحركات (الشاشة/المتجه/البديل النصي).
  ///
  /// وحدها تُستعمل في [commandForGlyph]: تحويل محرف مرئي إلى أمر غير مدعوم
  /// في الشاشة (مثل `\degree`) كان يُسقط المعاينة كلها إلى النص البديل.
  static const Set<String> latexSafe = <String>{
    'times', 'div', 'pm', 'mp', 'cdot', 'leq', 'geq', 'neq', 'approx',
    'equiv', 'sim', 'propto', 'to', 'rightarrow', 'leftarrow',
    'leftrightarrow', 'Rightarrow', 'Leftrightarrow', 'rightleftharpoons',
    'infty', 'partial', 'nabla', 'angle', 'perp', 'circ', 'in', 'notin',
    'subset', 'supset', 'cup', 'cap', 'emptyset', 'forall', 'exists',
    'neg', 'land', 'lor', 'oplus', 'otimes',
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta',
    'eta', 'theta', 'vartheta', 'iota', 'kappa', 'lambda', 'mu', 'nu',
    'xi', 'pi', 'rho', 'sigma', 'tau', 'upsilon', 'phi', 'varphi', 'chi',
    'psi', 'omega',
    'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi', 'Sigma', 'Upsilon',
    'Phi', 'Psi', 'Omega',
    'int', 'iint', 'iiint', 'oint', 'sum', 'prod',
    'lim', 'log', 'ln', 'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'exp', 'max', 'min',
  };

  /// المحرف المرئي لأمر LaTeX (بلا `\\`) — أو `null` إن لم يكن معروفاً.
  static String? glyphFor(String command) {
    final name = command.startsWith(r'\') ? command.substring(1) : command;
    return glyphs[name] ?? bigOperators[name];
  }

  /// هل الأمر المعطى رمزاً مرئياً معروفاً؟
  static bool isKnownCommand(String command) => glyphFor(command) != null;

  /// أمر LaTeX المكافئ لمحرف مرئي — **فقط** إن كان آمناً في كل المحركات،
  /// وإلا `null` فيبقى المحرف كما كُتب (وهو ما ترسمه المحركات كلها).
  static String? commandForGlyph(String glyph) {
    final trimmed = glyph.trim();
    if (trimmed.isEmpty || trimmed.length > 2) {
      return null;
    }
    for (final entry in glyphs.entries) {
      if (entry.value == trimmed && latexSafe.contains(entry.key)) {
        return '\\${entry.key}';
      }
    }
    for (final entry in bigOperators.entries) {
      if (entry.value == trimmed && latexSafe.contains(entry.key)) {
        return '\\${entry.key}';
      }
    }
    return null;
  }

  /// تعبير نمطي يطابق أمر LaTeX واحداً: `\alpha` أو `\{`.
  static final RegExp commandPattern = RegExp(r'\\[A-Za-z]+|\\.');

  /// هل المحرف من محارف LaTeX الخاصة التي يجب تهريبها داخل الصيغة؟
  static bool isSpecialCharacter(String char) =>
      char == '{' || char == '}' || char == '%' || char == '&' || char == '#';

  /// يطبّع [source]: كل محرف مكافئ ← صورته القياسية، والأُسُس/Dلالات
  /// الجاهزة في يونيكود (`²`، `₁`) ← بنى LaTeX (`^{2}`، `_{1}`).
  ///
  /// يُستعمل قبل أي تحليل في محركَي الـ PDF وWord، فلا يعتمد الرسم على
  /// لوحة المفاتيح التي كُتب بها النص.
  static String canonicalize(String source) =>
      _expandScripts(_foldAliases(source));

  /// تطبيق [aliases] محرفاً محرفاً (بلا تغيير في الطول إلا للثنائيات).
  static String _foldAliases(String source) {
    if (source.isEmpty) {
      return source;
    }
    var changed = false;
    for (var index = 0; index < source.length; index++) {
      if (aliases.containsKey(source[index])) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return source;
    }
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      buffer.write(aliases[char] ?? char);
    }
    return buffer.toString();
  }

  /// محارف الأسس/Dلالات الجاهزة في يونيكود ← بنيتها في LaTeX.
  static const Map<String, String> _superscriptChars = <String, String>{
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4',
    '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
    '⁺': '+', '⁻': '-', '⁼': '=', '⁽': '(', '⁾': ')',
    'ⁿ': 'n', 'ⁱ': 'i',
  };

  static const Map<String, String> _subscriptChars = <String, String>{
    '₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4',
    '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9',
    '₊': '+', '₋': '-', '₌': '=', '₍': '(', '₎': ')',
    'ₐ': 'a', 'ₑ': 'e', 'ₒ': 'o', 'ₓ': 'x', 'ₕ': 'h',
    'ₖ': 'k', 'ₗ': 'l', 'ₘ': 'm', 'ₙ': 'n', 'ₚ': 'p',
    'ₛ': 's', 'ₜ': 't',
  };

  /// الصورة العليا يونيكود لمحرف عادي واحد (`2` ← `²`) — `null` إن لا صورة.
  ///
  /// الجدول العكسي لـ[_superscriptChars]: يُستعمل في العرض النصي المقروء
  /// (آخر ارتداد عندما يعجز محرك الرسم نفسه) فلا يظهر `^` ولا `_` خامتين.
  static final Map<String, String> _toSuperscript = <String, String>{
    for (final entry in _superscriptChars.entries) entry.value: entry.key,
  };

  /// الصورة السفلى يونيكود لمحرف عادي واحد (`1` ← `₁`) — `null` إن لا صورة.
  static final Map<String, String> _toSubscript = <String, String>{
    for (final entry in _subscriptChars.entries) entry.value: entry.key,
  };

  /// هل لكل محرف من [value] صورة علوية يونيكود؟ (فارغ ← `false`).
  static bool hasSuperscriptForm(String value) =>
      value.isNotEmpty && value.runes.every(
            (rune) => _toSuperscript.containsKey(String.fromCharCode(rune)),
          );

  /// هل لكل محرف من [value] صورة سفلية يونيكود؟ (فارغ ← `false`).
  static bool hasSubscriptForm(String value) =>
      value.isNotEmpty && value.runes.every(
            (rune) => _toSubscript.containsKey(String.fromCharCode(rune)),
          );

  /// الصورة العليا يونيكود لمحرف واحد — `null` إن لا صورة له.
  static String? superscriptOf(String char) => _toSuperscript[char];

  /// الصورة السفلى يونيكود لمحرف واحد — `null` إن لا صورة له.
  static String? subscriptOf(String char) => _toSubscript[char];

  /// يحوّل [value] إلى صورته العلوية يونيكود محرفاً محرفاً.
  static String toSuperscript(String value) => _mapScript(value, _toSuperscript);

  /// يحوّل [value] إلى صورته السفلية يونيكود محرفاً محرفاً.
  static String toSubscript(String value) => _mapScript(value, _toSubscript);

  static String _mapScript(String value, Map<String, String> table) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(table[char] ?? char);
    }
    return buffer.toString();
  }

  /// متتالية محارف أسس/دلالات متجاورة ← بنية واحدة (`x²³` ← `x^{23}`).
  static String _expandScripts(String source) {
    if (!_hasScriptChar(source)) {
      return source;
    }
    final buffer = StringBuffer();
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      final isSuperscript = _superscriptChars.containsKey(char);
      final isSubscript = !isSuperscript && _subscriptChars.containsKey(char);
      if (!isSuperscript && !isSubscript) {
        buffer.write(char);
        index++;
        continue;
      }
      final table = isSuperscript ? _superscriptChars : _subscriptChars;
      final body = StringBuffer();
      while (index < source.length && table.containsKey(source[index])) {
        body.write(table[source[index]]!);
        index++;
      }
      buffer.write(isSuperscript ? '^' : '_');
      buffer.write('{$body}');
    }
    return buffer.toString();
  }

  static bool _hasScriptChar(String source) {
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (_superscriptChars.containsKey(char) ||
          _subscriptChars.containsKey(char)) {
        return true;
      }
    }
    return false;
  }

  /// يحوّل أمراً مخزَّناً إلى ما يُعرض في خانة التحرير المرئية:
  /// `\alpha` ← `α`، و`\{` ← `{`، وما لا يُعرف يبقى كما هو (لا يُفقَد).
  ///
  /// هذا ما يمنع ظهور أي كود LaTeX أمام المدرس أثناء تحرير معادلة قديمة.
  static String toDisplay(String command) {
    final escaped = escapedCharacters[command];
    if (escaped != null) {
      return escaped;
    }
    return glyphFor(command) ?? command;
  }

  /// يحوّل نصاً مرئياً (ما كتبه المدرس في خانة) إلى LaTeX مخزَّن آمن:
  /// - المحارف الخاصة تُهرَّب (`{` ← `\{`) فلا تُفسَد بنية الصيغة.
  /// - العلامة `$` تُهرَّب (`\$`) فلا تُغلق مقطع الصيغة.
  /// - المحارف المرئية المكافئة لأوامر آمنة تُكتب أوامرها (`α` ← `\alpha`)
  ///   لتتطابق مع ما تتوقعه محركات العرض، وما عداها يبقى محرفاً.
  /// - المحارف المكافئة تُطبَّع إلى صورتها القياسية (`−` ← `-`).
  static String toLatex(String display) {
    if (display.isEmpty) {
      return display;
    }
    final folded = _foldAliases(display);
    final runes = folded.runes.toList(growable: false);
    final buffer = StringBuffer();
    for (var index = 0; index < runes.length; index++) {
      final char = String.fromCharCode(runes[index]);
      if (char == r'$') {
        buffer.write(r'\$');
        continue;
      }
      if (isSpecialCharacter(char)) {
        buffer
          ..write(r'\')
          ..write(char);
        continue;
      }
      final command = commandForGlyph(char);
      if (command == null) {
        buffer.write(char);
        continue;
      }
      buffer.write(command);
      // الأمر الحرفي يبتلع كل حرف لاتيني يليه: «αx» يجب أن تُحفظ
      // `\alpha x` لا `\alphax` (أمر آخر غير معروف يفسد الصيغة كلها).
      // الرمز أو الرقم ينهي اسم الأمر وحده فلا يحتاج فراغاً.
      if (index + 1 < runes.length &&
          _latinLetter.hasMatch(String.fromCharCode(runes[index + 1]))) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  /// حرف لاتيني — فاصل اسم الأمر الضروري (انظر [toLatex]).
  static final RegExp _latinLetter = RegExp('[A-Za-z]');

  /// كل المحارف المرئية التي يستعملها التطبيق في المعادلات (جدول الرموز
  /// بجهتيه) — يفحص الاختبار أن خط الرياضيات المتجه يرسمها كلها، فلا تسقط
  /// أي معادلة إلى بديل نصي بسبب محرف ناقص.
  static Set<String> allDisplayGlyphs() {
    final result = <String>{
      for (final glyph in glyphs.values) ...glyph.runes.map(String.fromCharCode),
      for (final glyph in bigOperators.values)
        ...glyph.runes.map(String.fromCharCode),
      for (final glyph in aliases.values) ...glyph.runes.map(String.fromCharCode),
      for (final char in escapedCharacters.values) char,
      for (final char in _superscriptChars.values) char,
      for (final char in _subscriptChars.values) char,
    };
    result.removeWhere((char) => char.trim().isEmpty);
    return result;
  }
}
