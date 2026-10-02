import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../layout/visual/visual_content.dart';
import '../../models/exam_font.dart';
import 'safe_math_tex.dart';

/// نص علمي يعرض مقاطع LaTeX ($...$ سطرية، $$...$$ منفردة) بجانب النص العادي،
/// ويُبرز آيات القرآن الموسومة بـ `﴿ ... ﴾` بالخط القرآني (Amiri).
///
/// يعتمد على حزمة flutter_math_fork (Math.tex) لعرض الجذور والكسور
/// والتكاملات والدوال الفرعية/العليا.
///
/// **قطع النص ليس هنا**: يُقرأ من عقد المحتوى [RichContent.parse] نفسه الذي
/// يقرأه مصدِّر Word، فلا يوجد تحليلان للنص يفترقان مع الزمن — ومن يعدّل
/// قواعد القطع يعدّلها في العقد فيسري التغيير على الثلاثة.
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

  /// نمط الآيات القرآنية؛ عند غيابه يُشتق من [style] بعائلة الخط القرآني
  /// المعلنة في المقطع نفسه ([VisualRunStyle.font])، فإن لم تُعلن فبعائلة
  /// الخط القرآني في التطبيق.
  final TextStyle? quranStyle;

  final TextAlign textAlign;

  TextStyle? _resolvedQuranStyle(VisualRun run) {
    if (quranStyle != null) {
      return quranStyle;
    }
    final declared = run.style?.font?.family ?? ExamFont.quranicFamily;
    return (style ?? const TextStyle()).copyWith(fontFamily: declared);
  }

  @override
  Widget build(BuildContext context) {
    // المقاطع تأتي من عقد المحتوى لا من تحليل محلي (انظر توثيق الصنف).
    final content = RichContent.parse(text);
    if (content.isEmpty) {
      return Text('', style: style, textAlign: textAlign);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final blocks = <Widget>[];
        final inlineSpans = <InlineSpan>[];

        TextStyle? effectiveStyle = style;
        if (textAlign == TextAlign.justify &&
            constraints.hasBoundedWidth &&
            text.trim().isNotEmpty) {
          final words = text.trim().split(RegExp(r'\s+'));
          if (words.length > 1) {
            final naturalPainter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.rtl,
            )..layout();
            final gap = constraints.maxWidth - naturalPainter.width;
            if (gap > 0) {
              final maxPerWord = (constraints.maxWidth / words.length).clamp(12.0, 60.0);
              final rawSpacing = gap / (words.length - 1);
              final addedSpacing = rawSpacing.clamp(0.0, maxPerWord);
              effectiveStyle = (style ?? const TextStyle()).copyWith(
                wordSpacing: ((style?.wordSpacing) ?? 0) + addedSpacing,
              );
            }
          }
        }

        void flushInline() {
          if (inlineSpans.isEmpty) {
            return;
          }
          blocks.add(
            Text.rich(
              TextSpan(children: List<InlineSpan>.of(inlineSpans)),
              textAlign: textAlign,
              style: effectiveStyle,
            ),
          );
          inlineSpans.clear();
        }

        for (final run in content.runs) {
          if (run.isMath && run.isBlockMath) {
            flushInline();
            blocks.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: SafeMathTex(
                    run.text,
                    mathStyle: MathStyle.display,
                    textStyle: mathTextStyle ?? style,
                  ),
                ),
              ),
            );
          } else if (run.isMath) {
            inlineSpans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SafeMathTex(
                  run.text,
                  mathStyle: MathStyle.text,
                  textStyle: mathTextStyle ?? style,
                ),
              ),
            );
          } else if (run.text.isNotEmpty) {
            inlineSpans.add(
              TextSpan(
                text: run.text,
                style: run.isQuran ? _resolvedQuranStyle(run) : null,
              ),
            );
          }
        }
        flushInline();

        return SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks,
          ),
        );
      },
    );
  }
}
