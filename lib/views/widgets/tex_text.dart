import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../layout/visual/visual_content.dart';
import '../../models/exam_font.dart';
import 'safe_math_tex.dart';

/// Rich text renderer for legacy source strings or already-segmented
/// RichContent supplied by DocumentIR.
///
/// Preview's canonical path uses [TexText.fromRichContent], so it does not
/// rebuild text/math/Quran semantics from a flattened string. The legacy
/// constructor remains for edit-only surfaces and compatibility callers.
class TexText extends StatelessWidget {
  static String _measurementText(RichContent content) {
    final buffer = StringBuffer();
    for (final run in content.runs) {
      if (run.isMath) {
        final delimiter = run.isBlockMath ? r'$$' : r'$';
        buffer
          ..write(delimiter)
          ..write(run.text)
          ..write(delimiter);
      } else {
        buffer.write(run.text);
      }
    }
    return buffer.toString();
  }

  const TexText(
    this.text, {
    super.key,
    this.style,
    this.mathTextStyle,
    this.quranStyle,
    this.textAlign = TextAlign.start,
    this.expandToWidth = true,
  }) : richContent = null;

  TexText.fromRichContent(
    RichContent content, {
    super.key,
    this.style,
    this.mathTextStyle,
    this.quranStyle,
    this.textAlign = TextAlign.start,
    this.expandToWidth = true,
  })  : richContent = content,
        text = _measurementText(content);

  final String text;
  final RichContent? richContent;

  final TextStyle? style;
  final TextStyle? mathTextStyle;

  /// Quran style; when absent it follows the font intent on each VisualRun.
  final TextStyle? quranStyle;
  final TextAlign textAlign;
  final bool expandToWidth;

  TextStyle? _resolvedQuranStyle(VisualRun run) {
    if (quranStyle != null) {
      return quranStyle;
    }
    final declared = run.style?.font?.family ?? ExamFont.quranicFamily;
    return (style ?? const TextStyle()).copyWith(fontFamily: declared);
  }

  @override
  Widget build(BuildContext context) {
    final content = richContent ?? RichContent.parse(text);
    if (content.isEmpty) {
      return Text('', style: style, textAlign: textAlign);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final blocks = <Widget>[];
        final inlineSpans = <InlineSpan>[];

        // الضبط قرار المحرك وحده: `TextAlign.justify` يمدّ كل سطر ما عدا
        // الأخير، بلا توسعة يدوية مضافة (كانت تُمدّ السطر مرتين وتنحرف عن
        // هندسة العمود/PDF — انظر test/layout/canonical/preview_field_geometry_test.dart).
        final TextStyle? effectiveStyle = style;

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
                // The canonical engine measures display math as a centered
                // baseline placeholder paragraph, not a bare centered box.
                // Use that same paragraph/strut contract in the source flow.
                child: Text.rich(
                  TextSpan(children: <InlineSpan>[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      style: effectiveStyle,
                      child: SafeMathTex(
                        run.text,
                        mathStyle: MathStyle.display,
                        textStyle: mathTextStyle ?? style,
                      ),
                    ),
                  ]),
                  style: effectiveStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          } else if (run.isMath) {
            inlineSpans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                style: effectiveStyle,
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
          width: expandToWidth ? double.infinity : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: expandToWidth
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: blocks,
          ),
        );
      },
    );
  }
}
