import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// جدول مقاسات الخطوط الذي كان المحرك يرسُم منه قبل العقد البصري.
///
/// القيم بنقاط A4 ثابتة؛ لا تعتمد على جهاز المستخدم النهائي إطلاقاً.
///
/// **الحال في P0 (مقيسة)**: لا يقرأ هذا الجدول أيّ راسم —
/// `PdfPaperBuilder.styles` حقلٌ يُمرَّر ولا يُستهلَك، والقيم المرجعية
/// الفعلية للطباعة كلها من `ExamTypography`/`PaperStyleResolver` (ومن ثم كان
/// `body` هنا 10.5/1.45 بينما العقد 11/1.7 ولا أثر لذلك على المخرَج).
/// الحذف يعني تغيير توقيع `PdfPaperBuilder` العام وألوان `PdfColor` العامة
/// في هذه الحزمة، وهو من ممنوعات P0؛ فيبقى الجدول ويُزال في P1 مع إعادة بناء
/// الراسمين. الدليل مُثبَّت في `test/export_gate/p0_export_gate_test.dart`
/// (P0-GATE-08 يفحص أن لا مستهلِك للحقل في المصدر).
class ExamTextStyles {
  const ExamTextStyles({
    required this.headerTitle,
    required this.headerBody,
    required this.badge,
    required this.category,
    required this.question,
    required this.option,
    required this.body,
    required this.small,
    required this.note,
    required this.footer,
  });

  final pw.TextStyle headerTitle;
  final pw.TextStyle headerBody;
  final pw.TextStyle badge;
  final pw.TextStyle category;
  final pw.TextStyle question;
  final pw.TextStyle option;
  final pw.TextStyle body;
  final pw.TextStyle small;
  final pw.TextStyle note;
  final pw.TextStyle footer;

  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1E3A8A);
  static const PdfColor successColor = PdfColor.fromInt(0xFF065F46);
  static const PdfColor dangerColor = PdfColor.fromInt(0xFFDC2626);
  static const PdfColor mutedColor = PdfColor.fromInt(0xFF4B5563);

  static final ExamTextStyles standard = ExamTextStyles(
    // lineSpacing هنا = نسبة ارتفاع السطر (Flutter height) — نفس قيم
    // PaperStyles على الشاشة حتى يتطابق ارتفاع السطر مطبوعاً ومنشوراً.
    headerTitle: _textStyle(
      fontSize: 15,
      bold: true,
      lineSpacing: 1.6,
    ),
    headerBody: _textStyle(fontSize: 10, lineSpacing: 1.6),
    badge: _textStyle(fontSize: 9.5, bold: true, lineSpacing: 1.5),
    category: _textStyle(
      fontSize: 12.5,
      bold: true,
      lineSpacing: 1.45,
    ),
    question: _textStyle(fontSize: 11, bold: true, lineSpacing: 1.7),
    option: _textStyle(fontSize: 10.5, lineSpacing: 1.4),
    body: _textStyle(fontSize: 10.5, lineSpacing: 1.45),
    small: _textStyle(fontSize: 9, color: mutedColor, lineSpacing: 1.45),
    note: _textStyle(fontSize: 9.5, color: mutedColor, lineSpacing: 1.45),
    footer: _textStyle(fontSize: 8.5, color: mutedColor, lineSpacing: 1.45),
  );

  /// نسخة مقاسة بمعاملَي الورقة العامّين (حجم الخط الأساسي وتباعد
  /// الأسطر).
  ExamTextStyles scaled({double fontScale = 1.0, double heightScale = 1.0}) {
    if (fontScale == 1.0 && heightScale == 1.0) {
      return this;
    }
    pw.TextStyle scale(pw.TextStyle style) => style.copyWith(
          fontSize: (style.fontSize ?? 10.5) * fontScale,
          lineSpacing: style.lineSpacing == null
              ? null
              : style.lineSpacing! * heightScale,
        );
    return ExamTextStyles(
      headerTitle: scale(headerTitle),
      headerBody: scale(headerBody),
      badge: scale(badge),
      category: scale(category),
      question: scale(question),
      option: scale(option),
      body: scale(body),
      small: scale(small),
      note: scale(note),
      footer: footer,
    );
  }

  /// بناء أسلوب نص في وقت التشغيل.
  ///
  /// يمرّ عبر دالة بدل const مباشرة لأن مكتبة pdf 3.11.x لا تحتمل
  /// التقييم الثابت لـ TextStyle داخل const contexts.
  static pw.TextStyle _textStyle({
    required double fontSize,
    bool bold = false,
    PdfColor? color,
    double? lineSpacing,
  }) {
    return pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : null,
      color: color,
      lineSpacing: lineSpacing,
    );
  }
}
