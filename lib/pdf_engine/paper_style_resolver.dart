import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/visual/visual_style.dart';
import '../models/paper_font.dart';
import '../models/paper_text_style.dart';
import 'exam_fonts.dart';

/// تطبيق تنسيق عنصر ([PaperTextStyle]) على أنماط PDF الأساسية.
///
/// نفس القرار يُتخذ على لوحة المعاينة عبر `PaperStyles.resolve` — أي
/// تغيير هنا يجب أن يعكسه هناك حتى يبقى WYSIWYG حقيقياً.
abstract final class PaperStyleResolver {
  /// يطبّق [override] فوق [base] (القيم الفارغة ترث من الأساس).
  ///
  /// [defaultFont] خط الورقة الافتراضي من الإعدادات، و[fonts] الخطوط
  /// المحمّلة فعلياً (مع الارتداد الآمن داخل [ExamFonts.fontFor]).
  /// [fontScale]/[heightScale] معاملا القياس العامّان من إعدادات الورقة:
  /// يُطبَّقان على قيم الأساس فقط، والتنسيق المخصص لعنصر بعينه مطلق.
  static pw.TextStyle apply(
    pw.TextStyle base,
    PaperTextStyle? override, {
    required ExamFonts fonts,
    required PaperFont defaultFont,
    double fontScale = 1.0,
    double heightScale = 1.0,
  }) {
    final family = override?.font ?? defaultFont;
    final baseBold = base.fontWeight == pw.FontWeight.bold;
    final bold = override?.bold ?? baseBold;
    final font = fonts.fontFor(family, bold: bold);
    final fontSize = override?.fontSize ?? (base.fontSize ?? 10.5) * fontScale;
    // ارتفاع السطر المنشود بنفس دلالة Flutter: baseline-to-baseline = height ×
    // fontSize. مكتبة pdf تزيح السطر التالي بمقدار (natural + lineSpacing) حيث
    // natural = (ascent−descent)×fontSize من ملف TTF نفسه، فنحسب lineSpacing
    // = المنشود − الطبيعي حتى يطابق المطبوع شاشة المعاينة (WYSIWYG) لكل
    // حجم/خط/تباعد.
    final heightRatio = override?.lineHeight ??
        (base.lineSpacing == null ? null : base.lineSpacing! * heightScale);
    return base.copyWith(
      font: font,
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: (override?.italic ?? false) ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: (override?.underline ?? false)
          ? (base.decoration ?? pw.TextDecoration.none).merge(pw.TextDecoration.underline)
          : base.decoration,
      lineSpacing: heightRatio == null
          ? null
          : fontSize * (heightRatio - naturalLineRatio(font)),
      color: override?.color != null ? PdfColor.fromInt(override!.color!) : base.color,
    );
  }

  /// يحوّل نمط العقد البصري [VisualTextStyle] إلى نمط pdf.
  ///
  /// القيم تصل **نهائية** من [ExamTypography] (بعد معاملَي الورقة مرة واحدة)،
  /// فلا يُقاس شيء هنا: يبقى تحويل الوحدة وترجمة ارتفاع السطر إلى إزاحة
  /// `lineSpacing` التي تفهمها مكتبة pdf (المنشود − الطبيعي).
  static pw.TextStyle fromVisual(
    VisualTextStyle style, {
    required ExamFonts fonts,
  }) {
    final font = fonts.fontFor(style.font, bold: style.bold);
    return pw.TextStyle(
      font: font,
      fontSize: style.fontSizePt,
      fontWeight: style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle:
          style.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: style.underline ? pw.TextDecoration.underline : null,
      color: style.color != null ? PdfColor.fromInt(style.color!) : null,
      lineSpacing:
          style.fontSizePt * (style.lineHeight - naturalLineRatio(font)),
    );
  }

  /// (ascent − descent)/unitsPerEm للخط — نفس الارتفاع الطبيعي الذي يقيسه
  /// مخطط النص في مكتبة pdf قبل أي lineSpacing.
  static double naturalLineRatio(pw.Font font) {
    if (font is pw.TtfFont) {
      final parser = TtfParser(font.data);
      final upem = parser.unitsPerEm;
      if (upem > 0) {
        return (parser.ascent - parser.descent) / upem;
      }
    }
    // احتياطي: Noto Naskh Arabic (1069 + 634)/1000.
    return 1.703;
  }

  /// يحوّل محاذاة الورقة إلى محاذاة PDF (null = الافتراضي).
  static pw.TextAlign? toPdfAlign(PaperAlign? align) {
    switch (align) {
      case null:
      case PaperAlign.start:
        return null;
      case PaperAlign.center:
        return pw.TextAlign.center;
      case PaperAlign.end:
        return pw.TextAlign.end;
      case PaperAlign.justify:
        return pw.TextAlign.justify;
      case PaperAlign.left:
        return pw.TextAlign.left;
      case PaperAlign.right:
        return pw.TextAlign.right;
    }
  }
}
