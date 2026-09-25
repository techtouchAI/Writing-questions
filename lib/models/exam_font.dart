/// خطوط ورقة الامتحان: أسماء العائلات (للواجهة) ومسارات الأصول (لمحرك الطباعة).
///
/// مصدر واحد للحقيقة يستهلكه عرض الورقة (`PaperStyles`) ومحرك الـ PDF
/// (`ExamFonts`) معاً، فلا ينحرف اسم الخط بين ما يُرى على الشاشة وما يُطبع.
///
/// الخطوط الأربعة (كلها برخصة SIL OFL): Noto Naskh Arabic (الأساسي)،
/// Amiri (الأنيق/القرآني)، Tajawal (العصري)، Rakkas (للعناوين).
abstract final class ExamFont {
  /// خط الورقة الأساسي: Noto Naskh Arabic كامل التغطية (رخصة OFL).
  static const String arabicFamily = 'NotoNaskhArabic';

  /// الخط القرآني: Amiri (رخصة OFL) — يُستعمل لآيات القرآن «إن توفّر»،
  /// وإلا رُسمت بخط الورقة الأساسي بلا أي فقدان للنص.
  static const String quranicFamily = 'Amiri';

  /// خط عصري نظيف مناسب للمدارس (رخصة OFL).
  static const String tajawalFamily = 'Tajawal';

  /// خط عرض بأسلوب الرقعة للعناوين والترويسة (رخصة OFL).
  static const String rakkasFamily = 'Rakkas';

  static const String regularAsset = 'assets/fonts/NotoNaskhArabic-Regular.ttf';
  static const String boldAsset = 'assets/fonts/NotoNaskhArabic-Bold.ttf';
  static const String quranicAsset = 'assets/fonts/Amiri-Regular.ttf';
  static const String tajawalRegularAsset = 'assets/fonts/Tajawal-Regular.ttf';
  static const String tajawalBoldAsset = 'assets/fonts/Tajawal-Bold.ttf';
  static const String rakkasRegularAsset = 'assets/fonts/Rakkas-Regular.ttf';
}
