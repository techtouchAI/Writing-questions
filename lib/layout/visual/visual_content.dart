import '../../models/quran_text.dart';
import '../../models/tex_content.dart';

/// نوع مقطع المحتوى داخل نص الورقة.
enum VisualRunKind {
  /// نص عادي.
  text,

  /// صيغة رياضية `$...$`.
  math,

  /// آية قرآنية `﴿ ... ﴾`.
  quran,
}

/// مقطع محتوى واحد — **التمثيل الوحيد** الذي تقرأه المعاينة وPDF وWord.
///
/// الراسمون لا يعيدون تحليل النص؛ يقرؤون المقاطع ويطبع كل واحد بطريقته
/// (محرك الرياضيات للقطة، الخط القرآني للنص القرآني، النص العادي للنص).
class VisualRun {
  const VisualRun(this.kind, this.text);

  final VisualRunKind kind;

  /// النص كما هو (بلا وسوم) للمقطع النصي، أو محتوى الصيغة/الآية كما كُتب.
  final String text;

  bool get isMath => kind == VisualRunKind.math;
  bool get isQuran => kind == VisualRunKind.quran;
  bool get isText => kind == VisualRunKind.text;

  @override
  String toString() => 'VisualRun(${kind.name}, ${text.length} chars)';
}

/// محتوى نصّي غني: قائمة مقاطع مرتّبة + واجهات مساعدة.
///
/// هذا هو العقد الذي ينصّ على أن **String واحد ليس مصدر layout**: كود
/// `$...$` يبقى في المقاطع، ورسمه مسؤولية الراسم لا إعادة تحليله.
class RichContent {
  const RichContent(this.runs);

  /// نص عادي بلا صيغ ولا آيات.
  factory RichContent.plain(String text) =>
      RichContent(<VisualRun>[VisualRun(VisualRunKind.text, text)]);

  /// يحلّل [text] إلى مقاطع: آية ← صيغة ← نص، بترتيب الظهور (نفس تقسيم
  /// محرك المعاينة/الطباعة: [QuranText.split] ثم [TexContent.split]).
  factory RichContent.parse(String text) {
    return RichContent(_parse(text));
  }

  final List<VisualRun> runs;

  bool get isEmpty => runs.isEmpty || runs.every((run) => run.text.isEmpty);

  bool get isNotEmpty => !isEmpty;

  /// النص الخام كاملاً (للتصدير النصي والاختبارات والبحث).
  String get plainText => runs.map((run) => run.text).join();

  /// هل يحوي أي صيغة رياضية؟
  bool get hasMath => runs.any((run) => run.isMath);

  /// هل يحوي أي آية قرآنية؟
  bool get hasQuran => runs.any((run) => run.isQuran);

  static List<VisualRun> _parse(String text) {
    if (text.isEmpty) {
      return const <VisualRun>[];
    }
    final runs = <VisualRun>[];
    for (final quranSegment in QuranText.split(text)) {
      if (quranSegment.text.isEmpty) {
        continue;
      }
      if (quranSegment.isQuran) {
        runs.add(VisualRun(VisualRunKind.quran, quranSegment.text));
        continue;
      }
      for (final segment in TexContent.split(quranSegment.text)) {
        if (segment.text.isEmpty) {
          continue;
        }
        runs.add(
          VisualRun(
            segment.isMath ? VisualRunKind.math : VisualRunKind.text,
            segment.text,
          ),
        );
      }
    }
    return List<VisualRun>.unmodifiable(runs);
  }
}
