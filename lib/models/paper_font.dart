/// خطوط الورقة الامتحانية العربية (4 عائلات برخصة SIL Open Font License).
///
/// جميعها مختارة لتغطية محارف العرض العربي (Presentation Forms) التي
/// يعتمد عليها محرك الـ PDF في تشكيل الحروف، حتى يبقى ما يُرى على
/// الشاشة مطابقاً لما يُطبع (WYSIWYG):
/// - [naskh]: Noto Naskh Arabic — خط المتن الأساسي الواضح.
/// - [amiri]: Amiri — خط أنيق للعناوين والآيات القرآنية.
/// - [tajawal]: Tajawal — خط عصري نظيف مناسب للمدارس.
/// - [rakkas]: Rakkas — خط عرض بأسلوب الرقعة للعناوين والترويسة.
///
/// القراءة متسامحة عمداً ([parse] يرتد إلى [naskh]) حتى لا تفشل
/// المستندات القديمة أو القيم المستقبلية غير المعروفة.
enum PaperFont {
  naskh,
  amiri,
  tajawal,
  rakkas;

  /// اسم عائلة الخط كما هو مسجّل في `pubspec.yaml` (للواجهة).
  String get family {
    switch (this) {
      case PaperFont.naskh:
        return 'NotoNaskhArabic';
      case PaperFont.amiri:
        return 'Amiri';
      case PaperFont.tajawal:
        return 'Tajawal';
      case PaperFont.rakkas:
        return 'Rakkas';
    }
  }

  /// التسمية العربية المعروضة للمدرس.
  String get arabicLabel {
    switch (this) {
      case PaperFont.naskh:
        return 'نسخ واضح (الأساسي)';
      case PaperFont.amiri:
        return 'أميري أنيق';
      case PaperFont.tajawal:
        return 'تجوال عصري';
      case PaperFont.rakkas:
        return 'رقعة للعناوين';
    }
  }

  /// مسار ملف الوزن العادي داخل الأصول (لمحرك الطباعة).
  String get regularAsset {
    switch (this) {
      case PaperFont.naskh:
        return 'assets/fonts/NotoNaskhArabic-Regular.ttf';
      case PaperFont.amiri:
        return 'assets/fonts/Amiri-Regular.ttf';
      case PaperFont.tajawal:
        return 'assets/fonts/Tajawal-Regular.ttf';
      case PaperFont.rakkas:
        return 'assets/fonts/Rakkas-Regular.ttf';
    }
  }

  /// مسار ملف الوزن العريض؛ الخطوط أحادية الوزن ترتد إلى العادي.
  String get boldAsset {
    switch (this) {
      case PaperFont.naskh:
        return 'assets/fonts/NotoNaskhArabic-Bold.ttf';
      case PaperFont.tajawal:
        return 'assets/fonts/Tajawal-Bold.ttf';
      case PaperFont.amiri:
      case PaperFont.rakkas:
        return regularAsset;
    }
  }

  /// هل يملك الخط ملف وزن عريض مستقل؟
  bool get hasBoldWeight => this == PaperFont.naskh || this == PaperFont.tajawal;

  /// قراءة متسامحة: أي قيمة مجهولة أو مفقودة ترتد إلى [naskh].
  static PaperFont parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final font in PaperFont.values) {
      if (font.name == normalized) {
        return font;
      }
    }
    return PaperFont.naskh;
  }
}
