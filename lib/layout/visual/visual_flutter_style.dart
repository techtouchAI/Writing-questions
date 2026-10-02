import 'package:flutter/material.dart'
    show Color, FontStyle, FontWeight, TextAlign, TextDecoration, TextStyle;

import '../../models/paper_text_style.dart';
import '../paper_metrics.dart';
import 'visual_style.dart';

/// مُلحِق Flutter لعقد النمط البصري: يترجم [VisualTextStyle] إلى [TextStyle]
/// بوحدة لوحة المعاينة (بكسل 96dpi) — فتبقى المعاينة وPDF وWord تقرأ
/// الأرقام نفسها من العقد، ويختلف التحويل وحده.
abstract final class VisualFlutterStyle {
  /// يحوّل نمط العقد إلى نمط Flutter.
  ///
  /// [defaultColor] يُستعمل حين لا يحدد النمط لوناً (حبر الورقة الأسود).
  static TextStyle from(VisualTextStyle style, {Color? defaultColor}) {
    return TextStyle(
      fontFamily: style.font.family,
      fontSize: PaperMetrics.px(style.fontSizePt),
      fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          style.underline ? TextDecoration.underline : TextDecoration.none,
      height: style.lineHeight,
      letterSpacing: style.letterSpacingPt == null
          ? null
          : PaperMetrics.px(style.letterSpacingPt!),
      color: style.color != null
          ? Color(style.color!)
          : (defaultColor ?? const Color(0xFF000000)),
    );
  }

  /// يحوّل محاذاة الورقة إلى محاذاة Flutter (null = الافتراضي الممرَّر).
  static TextAlign toTextAlign(
    PaperAlign? align, [
    TextAlign fallback = TextAlign.start,
  ]) {
    switch (align) {
      case null:
        return fallback;
      case PaperAlign.start:
        return TextAlign.start;
      case PaperAlign.center:
        return TextAlign.center;
      case PaperAlign.end:
        return TextAlign.end;
      case PaperAlign.justify:
        return TextAlign.justify;
      case PaperAlign.left:
        return TextAlign.left;
      case PaperAlign.right:
        return TextAlign.right;
    }
  }
}

/// نمط نصّي للعرض المباشر **يحمل دوره من العقد البصري** وقيمه المرجعية
/// غير المقاسة.
///
/// يُنشئه `PaperStyles` من [VisualTypography]، ثم يقرأ `PaperStyles.resolve`
/// دوره ليعيد اشتقاق القيم النهائية من العقد نفسه الذي يقرأه PDF وWord —
/// فلا توجد ثلاثة جداول أحجام، ويبقى كل من يستعمل النمط للرسم المباشر يرى
/// القيم الافتراضية نفسها السابقة حرفياً.
class PaperRoleTextStyle extends TextStyle {
  PaperRoleTextStyle(this.role, this.reference, {Color? defaultColor})
      : super(
          fontFamily: reference.font.family,
          fontSize: PaperMetrics.px(reference.fontSizePt),
          fontWeight: reference.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle:
              reference.italic ? FontStyle.italic : FontStyle.normal,
          decoration: reference.underline
              ? TextDecoration.underline
              : TextDecoration.none,
          height: reference.lineHeight,
          letterSpacing: reference.letterSpacingPt == null
              ? null
              : PaperMetrics.px(reference.letterSpacingPt!),
          color: reference.color != null
              ? Color(reference.color!)
              : (defaultColor ?? const Color(0xFF000000)),
        );

  /// دور العنصر في العقد البصري.
  final VisualRole role;

  /// القيم المرجعية قبل معاملَي الورقة العامّين وقبل تنسيق العنصر.
  final VisualTextStyle reference;
}
