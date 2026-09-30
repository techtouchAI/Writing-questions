import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/latex_plain_text.dart';

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

  @override
  Widget build(BuildContext context) {
    final trimmed = latex.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    try {
      return Math.tex(trimmed, mathStyle: mathStyle, textStyle: textStyle);
    } catch (_) {
      return Text(
        LatexPlainText.of(trimmed),
        style: fallbackTextStyle ?? textStyle,
        textDirection: TextDirection.ltr,
      );
    }
  }
}
