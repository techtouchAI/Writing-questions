import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/widgets.dart' as pw;

import '../models/exam_font.dart';

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
class ExamFonts {
  static const String regularAsset = ExamFont.regularAsset;
  static const String boldAsset = ExamFont.boldAsset;
  static const String quranicAsset = ExamFont.quranicAsset;

  const ExamFonts({required this.regular, required this.bold, this.quranic});

  final pw.Font regular;
  final pw.Font bold;

  /// الخط القرآني (Amiri) — `null` إن لم يكن أصله متوفراً في الحزمة.
  final pw.Font? quranic;

  /// هل الخط القرآني متوفر فعلاً في هذه الحزمة؟
  bool get hasQuranic => quranic != null;

  /// يحمّل الخطوط من [bundle] (أصول التطبيق افتراضياً).
  ///
  /// [loadQuranic] يسمح للحزم التي لا تحتاج الطباعة القرآنية بتخطي تحميله.
  static Future<ExamFonts> load({AssetBundle? bundle, bool loadQuranic = true}) async {
    final assets = bundle ?? rootBundle;
    final regularData = await assets.load(regularAsset);
    final boldData = await assets.load(boldAsset);
    return ExamFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      quranic: loadQuranic ? await _loadQuranic(assets) : null,
    );
  }

  static Future<pw.Font?> _loadQuranic(AssetBundle assets) async {
    try {
      return pw.Font.ttf(await assets.load(quranicAsset));
    } catch (_) {
      // «إن توفرت»: غياب الخط القرآني لا يمنع توليد الورقة.
      return null;
    }
  }
}
