import 'package:flutter/material.dart'
    show
        Color,
        FontStyle,
        FontWeight,
        TextAlign,
        TextDecoration,
        TextStyle;

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
      // التباعد يُصرَّح دائماً (صفراً عند غياب قيمة في العقد): `null` يعني
      // «ورّث»، فيرث حقل الورقة `letterSpacing` من `Theme.textTheme.bodyLarge`
      // (0.5px في Material 3). أثره المقيس: نصّ أوسع بـ≈11% من قياس المحرك
      // نفسه، فتنكسر الأسطر في المعاينة في موضع آخر غير PDF — وهو الاختلاف
      // نفسه الذي كانت تُحاول توسعة `wordSpacing` اليدوية تغطيته.
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

  // الضبط (justify) لا يُنفَّذ هنا: لا توسعة يدوية لـ`wordSpacing`. القاعدة
  // الواحدة يعرّفها محرك التخطيط القانوني: كل سطر في فقرة متعددة الأسطر يوزّع
  // فائضه على فواصله القابلة للكسر، والسطر الأخير لا يُمَدّ، والفقرة من سطر
  // واحد لا تُمَدّ أبداً. `TextAlign.justify` في Flutter وفي `TextField`
  // ينفّذ القاعدة نفسها، فإضافة توسعة ثانية كانت تُنتج عرضاً لا يطابق العمود
  // ولا PDF (أُزيلت، ودليلها بوابة preview_field_geometry_test).
}

/// نمط نصّي للعرض المباشر **يحمل دوره من العقد البصري** وقيمه المرجعية
/// غير المقاسة.
///
/// يُنشئه `PaperStyles` من [ExamTypography]، ثم يقرأ `PaperStyles.resolve`
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
          // صفر صريح لا `null`: لا وراثة تباعد محارف من ثيم Material في أي
          // نصّ ورقة (انظر التعليق في [VisualFlutterStyle.from]).
          letterSpacing: PaperMetrics.px(reference.letterSpacingPt ?? 0),
          wordSpacing: 0,
          color: reference.color != null
              ? Color(reference.color!)
              : (defaultColor ?? const Color(0xFF000000)),
        );

  /// دور العنصر في العقد البصري.
  final VisualRole role;

  /// القيم المرجعية قبل معاملَي الورقة العامّين وقبل تنسيق العنصر.
  final VisualTextStyle reference;
}
