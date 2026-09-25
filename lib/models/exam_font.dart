/// خطوط ورقة الامتحان: أسماء العائلات (للواجهة) ومسارات الأصول (لمحرك الطباعة).
///
/// مصدر واحد للحقيقة يستهلكه عرض الورقة (`PaperStyles`) ومحرك الـ PDF
/// (`ExamFonts`) معاً، فلا ينحرف اسم الخط بين ما يُرى على الشاشة وما يُطبع.
abstract final class ExamFont {
  /// خط الورقة الأساسي: Noto Naskh Arabic كامل التغطية (رخصة OFL).
  static const String arabicFamily = 'NotoNaskhArabic';

  /// الخط القرآني: Amiri (رخصة OFL) — يُستعمل لآيات القرآن «إن توفّر»،
  /// وإلا رُسمت بخط الورقة الأساسي بلا أي فقدان للنص.
  static const String quranicFamily = 'Amiri';

  static const String regularAsset = 'assets/fonts/NotoNaskhArabic-Regular.ttf';
  static const String boldAsset = 'assets/fonts/NotoNaskhArabic-Bold.ttf';
  static const String quranicAsset = 'assets/fonts/Amiri-Regular.ttf';
}
