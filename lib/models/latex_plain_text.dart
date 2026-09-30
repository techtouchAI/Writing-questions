import 'math_symbols.dart';

/// تمثيل نصي مقروء لصيغة رياضية — **بلا أي رمز LaTeX إطلاقاً**.
///
/// هذا هو خط الدفاع الأخير: أي مسار عرض أو تصدير يعجز عن ترسيم صيغة (صيغة
/// قديمة غير مدعومة، أو فشل ترسيم) يستعمل هذه النتيجة بدل طباعة المصدر،
/// فلا يظهر `\` ولا `$` في أي ملف أو شاشة مهما حدث.
///
/// التحويل يحافظ على المعنى الرياضي قدر الإمكان:
/// - `\frac{a}{b}` ← `(a)/(b)`، و`\sqrt{x}` ← `√(x)`، و`\sqrt[3]{x}` ← `³√(x)`.
/// - الأسس والأدلة: `x^{2}` ← `x²`، و`x_{1}` ← `x₁`، وغيرها `^(...)`.
/// - الأوامر الرمزية (`\alpha`، `\times`...) ← محارفها المرئية (α، ×).
/// - أي أمر مجهول يُكتب باسمه بلا شرطة مائلة (`\lim` ← `lim`).
abstract final class LatexPlainText {
  /// يحوّل [latex] إلى نص مقروء مضمون الخلو من رموز LaTeX.
  static String of(String latex) {
    if (latex.trim().isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    var cursor = 0;
    while (cursor < latex.length) {
      final char = latex[cursor];
      if (char == r'\') {
        final match = MathSymbols.commandPattern.matchAsPrefix(latex, cursor);
        if (match == null) {
          cursor++;
          continue;
        }
        cursor = match.end;
        final name = match.group(0)!.substring(1);
        switch (name) {
          case 'frac':
          case 'dfrac':
          case 'tfrac':
            final numerator = _readArgument(latex, cursor);
            final denominator = _readArgument(latex, numerator.next);
            cursor = denominator.next;
            buffer.write('(${numerator.value})/(${denominator.value})');
          case 'sqrt':
            var root = '';
            final afterSqrt = _skipSpaces(latex, cursor);
            if (afterSqrt < latex.length && latex[afterSqrt] == '[') {
              final close = latex.indexOf(']', afterSqrt);
              if (close != -1) {
                root = latex.substring(afterSqrt + 1, close).trim();
                cursor = close + 1;
              }
            }
            final body = _readArgument(latex, cursor);
            cursor = body.next;
            buffer.write(
              root.isEmpty ? '√(${body.value})' : '${_superscript(root)}√(${body.value})',
            );
          case 'left':
          case 'right':
            final delimiter = _skipSpaces(latex, cursor);
            if (delimiter < latex.length) {
              cursor = delimiter + 1;
            }
          case 'text':
          case 'mathrm':
          case 'operatorname':
          case 'mathbf':
          case 'mathit':
            final group = _readArgument(latex, cursor);
            cursor = group.next;
            buffer.write(group.value);
          case ',':
          case ';':
          case '!':
          case ' ':
          case 'quad':
          case 'qquad':
            buffer.write(' ');
          default:
            buffer.write(MathSymbols.glyphFor(name) ?? name);
        }
        continue;
      }
      if (char == '{') {
        final group = _readBraced(latex, cursor + 1);
        cursor = group.next;
        buffer.write(group.value);
        continue;
      }
      if (char == '}' || char == r'$') {
        cursor++;
        continue;
      }
      if (char == '^' || char == '_') {
        final argument = _readArgument(latex, cursor + 1);
        cursor = argument.next;
        buffer.write(
          char == '^' ? _superscript(argument.value) : _subscript(argument.value),
        );
        continue;
      }
      buffer.write(char);
      cursor++;
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// يقرأ وسيط أمر: مجموعة `{...}` أو محرفاً واحداً.
  static ({String value, int next}) _readArgument(String source, int cursor) {
    var index = _skipSpaces(source, cursor);
    if (index >= source.length) {
      return (value: '', next: index);
    }
    if (source[index] == '{') {
      return _readBraced(source, index + 1);
    }
    if (source[index] == r'\') {
      final match = MathSymbols.commandPattern.matchAsPrefix(source, index);
      if (match != null) {
        return (
          value: of(source.substring(index, match.end)),
          next: match.end,
        );
      }
    }
    index++;
    return (value: of(source.substring(index - 1, index)), next: index);
  }

  /// يقرأ محتوى مجموعة مقوَّسة بدأت بعد [start] ويتجاوز أقواسها المتداخلة.
  static ({String value, int next}) _readBraced(String source, int start) {
    var index = start;
    var depth = 1;
    while (index < source.length) {
      final char = source[index];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return (value: of(source.substring(start, index)), next: index + 1);
        }
      }
      index++;
    }
    return (value: of(source.substring(start)), next: source.length);
  }

  static int _skipSpaces(String source, int cursor) {
    var index = cursor;
    while (index < source.length &&
        (source[index] == ' ' ||
            source[index] == '\t' ||
            source[index] == '\n')) {
      index++;
    }
    return index;
  }

  static const Map<String, String> _superscripts = <String, String>{
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '−': '⁻', '(': '⁽', ')': '⁾',
    'n': 'ⁿ', 'i': 'ⁱ',
  };

  static const Map<String, String> _subscripts = <String, String>{
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', '−': '₋', '(': '₍', ')': '₎',
    'a': 'ₐ', 'e': 'ₑ', 'i': 'ᵢ', 'j': 'ⱼ', 'n': 'ₙ',
    'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ',
    'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
  };

  static String _superscript(String value) =>
      _script(value, _superscripts, marker: '^');

  static String _subscript(String value) =>
      _script(value, _subscripts, marker: '_');

  static String _script(
    String value,
    Map<String, String> table, {
    required String marker,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final rune in trimmed.runes) {
      final glyph = table[String.fromCharCode(rune)];
      if (glyph == null) {
        return '$marker($trimmed)';
      }
      buffer.write(glyph);
    }
    return buffer.toString();
  }
}
