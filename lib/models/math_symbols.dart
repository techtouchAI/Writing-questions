/// جدول الرموز الرياضية: يقابل كل أمر LaTeX الشائع **محرفه المرئي**.
///
/// التطبيق يمنع ظهور أكواد LaTeX في أي مرحلة (إدخال/عرض/تصدير)، فهذا الجدول
/// هو المرجع الوحيد الذي:
/// - يحوّل أوامر الصيغ المخزَّنة إلى محارف مرئية عند التحرير المرئي،
/// - ويستخرج تمثيلاً مقروءاً (بلا `\` ولا `$`) عند تعذّر ترسيم صيغة قديمة.
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
    'equiv': '≡',
    'sim': '∼',
    'propto': '∝',
    'to': '→',
    'rightarrow': '→',
    'leftarrow': '←',
    'leftrightarrow': '↔',
    'rightleftharpoons': '⇌',
    'infty': '∞',
    'partial': '∂',
    'nabla': '∇',
    'degree': '°',
    'angle': '∠',
    'perp': '⊥',
    'circ': '∘',
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
    'Phi': 'Φ',
    'Psi': 'Ψ',
    'Omega': 'Ω',
  };

  /// الأوامر التي تُرسم كبيرةً (تكامل/مجموع/جداء) بمحارفها.
  static const Map<String, String> bigOperators = <String, String>{
    'int': '∫',
    'iint': '∬',
    'iiint': '∭',
    'oint': '∮',
    'sum': '∑',
    'prod': '∏',
    'lim': 'lim',
    'log': 'log',
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

  /// المحرف المرئي لأمر LaTeX (بلا `\`) — أو `null` إن لم يكن رمزاً معروفاً.
  static String? glyphFor(String command) {
    final name = command.startsWith(r'\') ? command.substring(1) : command;
    return glyphs[name] ?? bigOperators[name];
  }

  /// هل الأمر المعطى رمزاً مرئياً معروفاً؟
  static bool isKnownCommand(String command) => glyphFor(command) != null;

  /// يحوّل المحرف المرئي إلى أمر LaTeX المقابل — لعكس الاتجاه عند الحاجة
  /// فقط (لا يُعرض للمستخدم أبداً).
  static String? commandForGlyph(String glyph) {
    final trimmed = glyph.trim();
    for (final entry in glyphs.entries) {
      if (entry.value == trimmed) {
        return '\\${entry.key}';
      }
    }
    for (final entry in bigOperators.entries) {
      if (entry.value == trimmed) {
        return '\\${entry.key}';
      }
    }
    return null;
  }

  /// تعبير نمطي يطابق أمر LaTeX واحداً: `\alpha` أو `\{`.
  static final RegExp commandPattern = RegExp(r'\\[A-Za-z]+|\\.');
}
