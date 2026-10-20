import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/equation_model.dart';
import '../../models/math_symbols.dart';

/// يعرض صيغة رياضية مرئية — وإن تعذّر ترسيمها لأي سبب (صيغة قديمة غير
/// مدعومة) عرضها **نصاً رياضياً مقروءاً** بلا أي كود LaTeX.
///
/// هذا الضمان مقصود: لا يُعرض `\` ولا `$` على الشاشة إطلاقاً، ولا يسقط
/// العرض بخطأ بناء عند صيغة تالفة.
class SafeMathTex extends StatelessWidget {
  const SafeMathTex(
    this.latex, {
    super.key,
    this.mathStyle = MathStyle.text,
    this.textStyle,
    this.fallbackTextStyle,
  });

  final String latex;
  final MathStyle mathStyle;
  final TextStyle? textStyle;

  /// نمط البديل النصي عند تعذّر الترسيم (افتراضياً [textStyle]).
  final TextStyle? fallbackTextStyle;

  static final RegExp _unicodeRadicalBraced = RegExp(r'√\{([^}]*)\}');
  static final RegExp _unicodeRadicalAtom = RegExp(r'√([A-Za-z0-9]+)');

  static String _prepareForMathTex(String trimmed) {
    // مسار LaTeX القياسي (ASCII خالص) يمر كما هو حرفياً دون مساس بأي بكسل مرجعي.
    if (trimmed.codeUnits.every((unit) => unit < 0x80)) {
      return trimmed;
    }
    var prepared = MathSymbols.canonicalize(trimmed);
    if (prepared.contains('√')) {
      prepared = prepared
          .replaceAllMapped(_unicodeRadicalBraced, (m) => '\\sqrt{${m[1]}}')
          .replaceAllMapped(_unicodeRadicalAtom, (m) => '\\sqrt{${m[1]}}');
    }
    return prepared;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = latex.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    try {
      return Math.tex(
        _prepareForMathTex(trimmed),
        mathStyle: mathStyle,
        textStyle: textStyle,
      );
    } catch (_) {
      return Text(
        EquationModel.readableText(trimmed),
        style: fallbackTextStyle ?? textStyle,
        textDirection: TextDirection.ltr,
      );
    }
  }
}
