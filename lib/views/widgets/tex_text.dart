import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/tex_content.dart';

/// نص علمي يعرض مقاطع LaTeX ($...$ سطرية، $$...$$ منفردة) بجانب النص العادي.
///
/// يعتمد على حزمة flutter_math_fork (Math.tex) لعرض الجذور والكسور
/// والتكاملات والدوال الفرعية/العليا؛ نفس منطق القطع [TexContent.split]
/// المستخدم في محرك الـ PDF — مطابقة 1:1 بين الشاشة والطباعة.
class TexText extends StatelessWidget {
  const TexText(
    this.text, {
    super.key,
    this.style,
    this.mathTextStyle,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? mathTextStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final segments = TexContent.split(text);
    if (segments.isEmpty) {
      return Text('', style: style, textAlign: textAlign);
    }

    final blocks = <Widget>[];
    final inlineSpans = <InlineSpan>[];

    void flushInline() {
      if (inlineSpans.isEmpty) {
        return;
      }
      blocks.add(
        Text.rich(
          TextSpan(children: List<InlineSpan>.of(inlineSpans)),
          textAlign: textAlign,
          style: style,
        ),
      );
      inlineSpans.clear();
    }

    for (final segment in segments) {
      if (segment.isMath && segment.isBlock) {
        flushInline();
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Math.tex(
                segment.text,
                mathStyle: MathStyle.display,
                textStyle: mathTextStyle ?? style,
              ),
            ),
          ),
        );
      } else if (segment.isMath) {
        inlineSpans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              segment.text,
              mathStyle: MathStyle.text,
              textStyle: mathTextStyle ?? style,
            ),
          ),
        );
      } else if (segment.text.isNotEmpty) {
        inlineSpans.add(TextSpan(text: segment.text));
      }
    }
    flushInline();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
