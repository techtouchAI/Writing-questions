import 'package:pdf/widgets.dart' as pw;

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
  static pw.TextStyle apply(
    pw.TextStyle base,
    PaperTextStyle? override, {
    required ExamFonts fonts,
    required PaperFont defaultFont,
  }) {
    final family = override?.font ?? defaultFont;
    final baseBold = base.fontWeight == pw.FontWeight.bold;
    final bold = override?.bold ?? baseBold;
    return base.copyWith(
      font: fonts.fontFor(family, bold: bold),
      fontSize: override?.fontSize ?? base.fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: (override?.italic ?? false) ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: (override?.underline ?? false)
          ? (base.decoration ?? pw.TextDecoration.none).merge(pw.TextDecoration.underline)
          : base.decoration,
      lineSpacing: override?.lineHeight != null
          ? (override!.lineHeight! * 2)
          : base.lineSpacing,
    );
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
