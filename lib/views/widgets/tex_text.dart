import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../layout/visual/visual_content.dart';
import '../../layout/visual/visual_metrics.dart';
import '../../models/exam_font.dart';
import '../wizard/measure_size.dart';
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
    this.textDirection,
    this.expandToWidth = true,
  }) : richContent = null;

  TexText.fromRichContent(
    RichContent content, {
    super.key,
    this.style,
    this.mathTextStyle,
    this.quranStyle,
    this.textAlign = TextAlign.start,
    this.textDirection,
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

  /// Paragraph direction from DocumentIR, independent of the app/UI locale.
  /// Null preserves inherited direction for legacy/edit-only callers.
  final TextDirection? textDirection;
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
      return Text('', style: style, textAlign: textAlign, textDirection: textDirection);
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
              textDirection: textDirection,
              style: effectiveStyle,
            ),
          );
          inlineSpans.clear();
        }

        for (final run in content.runs) {
          if (run.isMath && run.isBlockMath) {
            flushInline();
            blocks.add(
              // الحشوة ليست رقمًا ثابتًا: تُشتق من ارتفاع الصندوق المقيس
              // مقابل ارتفاع السطر، بنفس الدالة التي يستعملها المحرك
              // القانوني، فلا تُحسب الفجوة مرتين ولا تختلف المعاينة عن PDF.
              _DisplayMathParagraph(
                latex: run.text,
                style: effectiveStyle,
                mathTextStyle: mathTextStyle ?? style,
                textDirection: textDirection,
                lineHeightPx: _lineHeightPx(effectiveStyle),
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

/// ارتفاع السطر المرجعي لبكسل المعاينة: حجم الخط × معامل الارتفاع، وهو ما
/// يطبّقه محرك النص نفسه في `strutStyle`، ويقابله في المحرك
/// `LayoutTextStyle.fontSizePt * lineHeightFactor`.
double _lineHeightPx(TextStyle? style) {
  final fontSize = style?.fontSize ?? 14.0;
  final factor = style?.height ?? 1.0;
  return fontSize * factor;
}

/// معادلة مستقلة: فقرة مرتكزة على السطر نفسه (كما يقيسها المحرك القانوني)
/// بحشوة مشتقّة من **ارتفاع الصيغة الفعلي** بعد قياسها.
///
/// القياس يقيس الأثر قبل الحشوة (MeasureSize حول الصيغة وحدها)، والإبلاغ يأتي
/// بعد الإطار: أول إطار يُرسم بالأرضية (3pt)، ثم تستقر الفجوة على المشتقّ.
/// عتبة 0.5px تمنع حلقة قياس/إعادة بناء لا تنتهي.
class _DisplayMathParagraph extends StatefulWidget {
  const _DisplayMathParagraph({
    required this.latex,
    required this.style,
    required this.mathTextStyle,
    required this.textDirection,
    required this.lineHeightPx,
  });

  final String latex;
  final TextStyle? style;
  final TextStyle? mathTextStyle;
  final TextDirection textDirection;
  final double lineHeightPx;

  @override
  State<_DisplayMathParagraph> createState() => _DisplayMathParagraphState();
}

class _DisplayMathParagraphState extends State<_DisplayMathParagraph> {
  double _mathHeightPx = 0;

  void _onMeasured(Size size) {
    final height = size.height;
    if (!height.isFinite || height <= 0) return;
    if ((height - _mathHeightPx).abs() < 0.5) return;
    if (!mounted) return;
    setState(() => _mathHeightPx = height);
  }

  @override
  Widget build(BuildContext context) {
    final gap = VisualMetrics.displayMathGapPx(
      mathHeightPx: _mathHeightPx,
      lineHeightPx: widget.lineHeightPx,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: Text.rich(
        TextSpan(children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            style: widget.style,
            child: MeasureSize(
              onChange: _onMeasured,
              child: SafeMathTex(
                widget.latex,
                mathStyle: MathStyle.display,
                textStyle: widget.mathTextStyle,
              ),
            ),
          ),
        ]),
        style: widget.style,
        textAlign: TextAlign.center,
        textDirection: widget.textDirection,
      ),
    );
  }
}
