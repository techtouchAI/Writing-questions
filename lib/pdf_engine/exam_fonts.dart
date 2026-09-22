import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// خطوط ورقة الامتحان محمّلة من أصول التطبيق.
///
/// النسخة الكاملة من Noto Naskh Arabic (رخصة OFL) تضم تغطية كاملة
/// لمحارف العرض العربي (Presentation Forms) واللاتينية معاً، وهو شرط
/// لرسم الحروف العربية متصلة داخل ملف الـ PDF.
class ExamFonts {
  static const String regularAsset = 'assets/fonts/NotoNaskhArabic-Regular.ttf';
  static const String boldAsset = 'assets/fonts/NotoNaskhArabic-Bold.ttf';

  const ExamFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static Future<ExamFonts> load() async {
    final regularData = await rootBundle.load(regularAsset);
    final boldData = await rootBundle.load(boldAsset);
    return ExamFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
  }
}
