import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/widgets.dart' as pw;

import '../models/exam_font.dart';
import '../models/paper_font.dart';

/// خطوط ورقة الامتحان محمّلة من أصول التطبيق.
///
/// النسخة الكاملة من Noto Naskh Arabic (رخصة OFL) تضم تغطية كاملة
/// لمحارف العرض العربي (Presentation Forms) واللاتينية معاً، وهو شرط
/// لرسم الحروف العربية متصلة داخل ملف الـ PDF.
///
/// ويُحمَّل معها الخط القرآني **Amiri** (رخصة OFL) اختيارياً لآيات القرآن في
/// قالب التربية الإسلامية (شرط «خطوط قرآنية إن توفّرت» في النموذج الوزاري):
/// إن غاب الأصل من حزمة التطبيق لا يُسقط التوليد ولا يُفقد النص، بل ترتد
/// الآية إلى خط الورقة الأساسي — لذلك الحقل [`quranic`] قابل للعدم.
///
/// إضافة إلى خطين عريضين اختياريين يختارهما المدرس لأي عنصر:
/// **Tajawal** (عصري) و**Rakkas** (للعناوين) — غياب أي منهما يرتد إلى
/// الخط الأساسي دون أي فقدان.
class ExamFonts {
  static const String regularAsset = ExamFont.regularAsset;
  static const String boldAsset = ExamFont.boldAsset;
  static const String quranicAsset = ExamFont.quranicAsset;

  const ExamFonts({
    required this.regular,
    required this.bold,
    this.quranic,
    this.tajawalRegular,
    this.tajawalBold,
    this.rakkas,
  });

  final pw.Font regular;
  final pw.Font bold;

  /// الخط القرآني (Amiri) — `null` إن لم يكن أصله متوفراً في الحزمة.
  final pw.Font? quranic;

  /// خط Tajawal (عادي/عريض) — `null` إن لم يكن متوفراً.
  final pw.Font? tajawalRegular;
  final pw.Font? tajawalBold;

  /// خط Rakkas (وزن واحد) — `null` إن لم يكن متوفراً.
  final pw.Font? rakkas;

  /// هل الخط القرآني متوفر فعلاً في هذه الحزمة؟
  bool get hasQuranic => quranic != null;

  /// يعيد خط عائلة [family] (عريضاً عند [bold]) مع الارتداد الآمن:
  /// العريض المفقود ← عادي العائلة ← عادي/عريض الأساسي. لا يعيد `null` أبداً.
  pw.Font fontFor(PaperFont family, {bool bold = false}) {
    switch (family) {
      case PaperFont.naskh:
        return bold ? this.bold : regular;
      case PaperFont.amiri:
        return quranic ?? (bold ? this.bold : regular);
      case PaperFont.tajawal:
        if (bold) {
          return tajawalBold ?? tajawalRegular ?? this.bold;
        }
        return tajawalRegular ?? regular;
      case PaperFont.rakkas:
        return rakkas ?? (bold ? this.bold : regular);
    }
  }

  /// يحمّل الخطوط من [bundle] (أصول التطبيق افتراضياً).
  ///
  /// [loadQuranic] يسمح للحزم التي لا تحتاج الطباعة القرآنية بتخطي تحميله،
  /// و[loadExtra] يسمح بتخطي الخطين الاختياريين (Tajawal/Rakkas).
  static Future<ExamFonts> load({
    AssetBundle? bundle,
    bool loadQuranic = true,
    bool loadExtra = true,
  }) async {
    final assets = bundle ?? rootBundle;
    final regularData = await assets.load(regularAsset);
    final boldData = await assets.load(boldAsset);
    return ExamFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      quranic: loadQuranic ? await _tryLoad(assets, quranicAsset) : null,
      tajawalRegular:
          loadExtra ? await _tryLoad(assets, ExamFont.tajawalRegularAsset) : null,
      tajawalBold: loadExtra ? await _tryLoad(assets, ExamFont.tajawalBoldAsset) : null,
      rakkas: loadExtra ? await _tryLoad(assets, ExamFont.rakkasRegularAsset) : null,
    );
  }

  static Future<pw.Font?> _tryLoad(AssetBundle assets, String asset) async {
    try {
      return pw.Font.ttf(await assets.load(asset));
    } catch (_) {
      // «إن توفرت»: غياب أي خط اختياري لا يمنع توليد الورقة.
      return null;
    }
  }
}
