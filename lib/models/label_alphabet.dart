/// أبجدية الترقيم العربي الثابتة لخيارات الاختبار وفروع السؤال.
///
/// الترقيم مولَّد من الفهرس حتى يبقى متسقاً في بنك الأسئلة وورقة PDF
/// بدل اعتماده على حقل نصي حرّ قابل للتلاعب.
abstract final class LabelAlphabet {
  static const List<String> letters = <String>[
    'أ',
    'ب',
    'ج',
    'د',
    'هـ',
    'و',
    'ز',
    'ح',
    'ط',
    'ي',
    'ك',
    'ل',
  ];

  /// يعيد تسمية [index] (يبدأ من الصفر)؛ ما بعد الحروف يتحوّل لأرقام.
  static String at(int index) {
    if (index < 0) {
      return '1';
    }
    if (index < letters.length) {
      return letters[index];
    }
    return '${index + 1}';
  }
}
