import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// مقاسات الخطوط والمسافات الموحدة لورقة الامتحان.
///
/// القيم بنقاط A4 ثابتة؛ لا تعتمد على جهاز المستخدم النهائي إطلاقاً.
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
    headerTitle: _textStyle(
      fontSize: 15,
      bold: true,
      color: primaryColor,
      lineSpacing: 1.5,
    ),
    headerBody: _textStyle(fontSize: 10, lineSpacing: 1.5),
    badge: _textStyle(fontSize: 9.5, bold: true, lineSpacing: 1.5),
    category: _textStyle(
      fontSize: 12.5,
      bold: true,
      color: primaryColor,
      lineSpacing: 1.5,
    ),
    question: _textStyle(fontSize: 11, bold: true, lineSpacing: 2),
    option: _textStyle(fontSize: 10.5, lineSpacing: 1.4),
    body: _textStyle(fontSize: 10.5, lineSpacing: 1.5),
    small: _textStyle(fontSize: 9, color: mutedColor, lineSpacing: 1.4),
    note: _textStyle(fontSize: 9.5, color: mutedColor, lineSpacing: 1.5),
    footer: _textStyle(fontSize: 8.5, color: mutedColor),
  );

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
