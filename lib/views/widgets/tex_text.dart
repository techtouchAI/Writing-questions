import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/exam_font.dart';
import '../../models/quran_text.dart';
import '../../models/tex_content.dart';

/// نص علمي يعرض مقاطع LaTeX ($...$ سطرية، $$...$$ منفردة) بجانب النص العادي،
/// ويُبرز آيات القرآن الموسومة بـ `﴿ ... ﴾` بالخط القرآني (Amiri).
///
/// يعتمد على حزمة flutter_math_fork (Math.tex) لعرض الجذور والكسور
/// والتكاملات والدوال الفرعية/العليا؛ نفس منطق القطع [TexContent.split] و
/// [QuranText.split] المستخدم في محرك الـ PDF — مطابقة 1:1 بين الشاشة
/// والطباعة.
class TexText extends StatelessWidget {
  const TexText(
    this.text, {
    super.key,
    this.style,
    this.mathTextStyle,
    this.quranStyle,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? mathTextStyle;

  /// نمط الآيات القرآنية؛ عند غيابه يُشتق من [style] بعائلة الخط القرآني.
  final TextStyle? quranStyle;

  final TextAlign textAlign;

  TextStyle? get _resolvedQuranStyle =>
      quranStyle ?? (style ?? const TextStyle()).copyWith(fontFamily: ExamFont.quranicFamily);

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
        // النص العادي نفسه قد يحمل آيات موسومة بالقوسين المزخرفين.
        for (final piece in QuranText.split(segment.text)) {
          if (piece.text.isEmpty) {
            continue;
          }
          inlineSpans.add(
            TextSpan(
              text: piece.text,
              style: piece.isQuran ? _resolvedQuranStyle : null,
            ),
          );
        }
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
