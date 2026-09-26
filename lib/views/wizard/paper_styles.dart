import 'package:flutter/material.dart';

import '../../layout/paper_metrics.dart';
import '../../models/exam_font.dart';
import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_layout.dart';

/// أنماط نصوص ورقة المعاينة A4 — نفس مقاسات `ExamTextStyles` في محرك الـ PDF
/// (بالنقاط) محوّلة إلى بكسل اللوحة، وبنفس الخطوط المضمّنة،
/// حتى يتطابق التفاف الأسطر وارتفاع الكتل بين الشاشة والطباعة قدر الإمكان.
///
/// تنسيق أي عنصر يُحسم عبر [resolve] (نفس قرار `PaperStyleResolver.apply`
/// في محرك الطباعة) فلا ينحرف ما يُرى عما يُطبع.
abstract final class PaperStyles {
  static const String fontFamily = ExamFont.arabicFamily;

  /// الخط القرآني لآيات القرآن (Amiri) — نفس عائلة خط الـ PDF.
  static const String quranicFamily = ExamFont.quranicFamily;

  static const Color primary = Color(0xFF1E3A8A);
  static const Color muted = Color(0xFF4B5563);
  static const Color accent = Color(0xFF2563EB);
  static const Color danger = Color(0xFFDC2626);

  /// لون الإجابات النموذجية في «نموذج الإجابة» — مطابق لـ
  /// `ExamTextStyles.successColor` في محرك الطباعة.
  static const Color answer = Color(0xFF065F46);

  static TextStyle _style(
    double points, {
    bool bold = false,
    Color color = Colors.black,
    double height = 1.45,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: PaperMetrics.px(points),
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
      height: height,
    );
  }

  static TextStyle get headerLine => _style(10, height: 1.6);
  static TextStyle get headerCenter => _style(10, bold: true, height: 1.6);
  static TextStyle get headerTitle => _style(14, bold: true, color: primary, height: 1.6);
  static TextStyle get category => _style(12.5, bold: true, color: primary);
  static TextStyle get question => _style(11, bold: true, height: 1.7);
  static TextStyle get prompt => _style(11, height: 1.7);
  static TextStyle get small => _style(9, color: muted);
  static TextStyle get note => _style(9.5, color: muted);
  static TextStyle get footer => _style(8.5, color: muted);
  static TextStyle get option => _style(10.5, height: 1.4);
  static TextStyle get item => _style(10.5, height: 1.5);

  static TextStyle body(SubjectLayoutTemplate layout) =>
      _style(10.5, height: layout.lineHeightFactor);

  /// يطبّق تنسيق عنصر [override] فوق النمط الأساسي [base].
  ///
  /// [defaultFont] خط الورقة الافتراضي من إعداداتها. القيم الفارغة في
  /// [override] ترث من الأساس — وهو نفس قرار محرك الطباعة حرفياً.
  ///
  /// [fontScale]/[heightScale] معاملا القياس العامّان من إعدادات الورقة
  /// (حجم الخط الأساسي وتباعد الأسطر): يُطبَّقان على قيم الأساس فقط،
  /// ويبقى التنسيق المخصص لعنصر بعينه (حجم/تباعد مطلق) متقدماً عليهما.
  static TextStyle resolve(
    TextStyle base,
    PaperTextStyle? override, {
    PaperFont defaultFont = PaperFont.naskh,
    double fontScale = 1.0,
    double heightScale = 1.0,
  }) {
    final family = override?.font ?? defaultFont;
    final baseBold = base.fontWeight == FontWeight.bold;
    final bold = override?.bold ?? baseBold;
    final underline = override?.underline ?? false;
    return base.copyWith(
      fontFamily: family.family,
      fontSize: override?.fontSize != null
          ? PaperMetrics.px(override!.fontSize!)
          : (base.fontSize ?? 14) * fontScale,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle:
          (override?.italic ?? false) ? FontStyle.italic : FontStyle.normal,
      decoration: underline ? TextDecoration.underline : TextDecoration.none,
      height: override?.lineHeight ?? (base.height ?? 1.45) * heightScale,
      color: override?.color != null ? Color(override!.color!) : base.color,
    );
  }

  /// يقيس نمطاً أساسياً مباشراً (بلا تنسيق عنصر) بمعاملَي الورقة العامّين.
  ///
  /// يُستخدم للأنماط التي تُعرض كما هي دون [resolve] (الخيارات، النقاط،
  /// الملاحظات...) حتى تكبر الورقة كلها وتصغر معاً من مكان واحد —
  /// وهو نفس قرار محرك الطباعة حرفياً.
  static TextStyle scale(
    TextStyle base, {
    double fontScale = 1.0,
    double heightScale = 1.0,
  }) {
    if (fontScale == 1.0 && heightScale == 1.0) {
      return base;
    }
    return base.copyWith(
      fontSize: (base.fontSize ?? 14) * fontScale,
      height: (base.height ?? 1.45) * heightScale,
    );
  }

  /// يحوّل محاذاة الورقة إلى محاذاة Flutter (null = الافتراضي الممرّر).
  static TextAlign toTextAlign(PaperAlign? align, [TextAlign fallback = TextAlign.start]) {
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

  /// آية قرآنية قائمة بذاتها: خط قرآني وحجم أوضح وتوسيط (كما في المصحف).
  /// مقابله في الطباعة: نفس القرار داخل `PaginatedPdfExamEngine._renderText`.
  static TextStyle verse(SubjectLayoutTemplate layout) =>
      _style(12, height: layout.lineHeightFactor + 0.2)
          .copyWith(fontFamily: quranicFamily);

  /// مقطع قرآني سطري داخل نص عادي: يبقى بمقاس النص ويتغيّر خطه فقط.
  static TextStyle quranic(TextStyle base) => base.copyWith(fontFamily: quranicFamily);

  /// نص الإجابة النموذجية (فراغ/مقالي) على الورقة في وضع «نموذج الإجابة».
  static TextStyle answerBody(SubjectLayoutTemplate layout) => body(layout).copyWith(
        color: answer,
        fontWeight: FontWeight.bold,
      );

  static TextStyle hint(TextStyle base) => base.copyWith(color: Colors.grey);
}
