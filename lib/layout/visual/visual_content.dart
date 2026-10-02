import '../../models/paper_font.dart';
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

/// تنسيق مقطع واحد داخل العنصر — كل قيمة اختيارية: ما يُترك `null` يتبع
/// تنسيق العنصر من عقد الطباعة. فالتنسيق الخاص بمقطع (خط آية، حجم صيغة،
/// لون كلمة) لا يُكتب في أي راسم، بل يُقرأ من هنا في الثلاثة.
class VisualRunStyle {
  const VisualRunStyle({
    this.font,
    this.fontSizePt,
    this.bold,
    this.italic,
    this.underline,
    this.colorArgb,
    this.baselineShiftPt,
  });

  final PaperFont? font;
  final double? fontSizePt;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final int? colorArgb;

  /// إزاحة عن خط الأساس بالنقاط (سلبية للنزول) — للصيغ والمؤشرات.
  ///
  /// خاصية جريان حقيقية في الراسمين: `w:position` في Word و
  /// `Transform.translate` في Flutter؛ ولذلك موضعها هنا لا في واجهة الراسم.
  final double? baselineShiftPt;

  bool get isEmpty =>
      font == null &&
      fontSizePt == null &&
      bold == null &&
      italic == null &&
      underline == null &&
      colorArgb == null &&
      baselineShiftPt == null;

  VisualRunStyle merge(VisualRunStyle? other) {
    if (other == null || other.isEmpty) {
      return this;
    }
    return VisualRunStyle(
      font: other.font ?? font,
      fontSizePt: other.fontSizePt ?? fontSizePt,
      bold: other.bold ?? bold,
      italic: other.italic ?? italic,
      underline: other.underline ?? underline,
      colorArgb: other.colorArgb ?? colorArgb,
      baselineShiftPt: other.baselineShiftPt ?? baselineShiftPt,
    );
  }
}

/// مقطع محتوى واحد — **التمثيل الوحيد** الذي تقرأه المعاينة وPDF وWord.
///
/// الراسمون لا يعيدون تحليل النص؛ يقرؤون المقاطع ويطبع كل واحد بطريقته
/// (محرك الرياضيات للقطة، الخط القرآني للنص القرآني، النص العادي للنص)،
/// ويقرؤون [style] لتنسيقه الخاص إن وُجد.
class VisualRun {
  const VisualRun(
    this.kind,
    this.text, {
    this.style,
    this.isBlockMath = false,
  });

  final VisualRunKind kind;

  /// النص كما هو (الآية **بقوسَيها** الضمنيين) للمقطع النصي/القرآني، أو متن
  /// LaTeX بلا محددات للمقطع الرياضي — تماماً كما يقرؤه الراسمون.
  final String text;

  /// تنسيق خاص بالمقطع (`null` = يتبع تنسيق العنصر).
  final VisualRunStyle? style;

  /// هل الصيغة منفصلة (`$$...$$`) أم سطرية (`$...$`)؟ قرار **محتوى** لا
  /// قرار راسم: المعاينة ترسم المنفصلة في كتلة مستقلة، وWord يبنيها منطقة
  /// رياضية منفصلة، وPDF يرثها من المعاينة.
  final bool isBlockMath;

  bool get isMath => kind == VisualRunKind.math;
  bool get isQuran => kind == VisualRunKind.quran;
  bool get isText => kind == VisualRunKind.text;

  /// نسخة بتنسيق إضافي يُدمج فوق تنسيق المقطع القائم.
  VisualRun withStyle(VisualRunStyle? extra) => extra == null || extra.isEmpty
      ? this
      : VisualRun(
          kind,
          text,
          style: (style ?? const VisualRunStyle()).merge(extra),
          isBlockMath: isBlockMath,
        );

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

  /// يحلّل [text] إلى مقاطع: صيغة ← آية ← نص، بترتيب الظهور.
  ///
  /// الترتيب هو ترتيب الراسمين أنفسهم حرفياً: [TexContent.split] أولاً (فما
  /// داخل `$...$` يبقى رياضيات ولا تُفسَّر أقواس المصحف داخله)، ثم
  /// [QuranText.split] على كل مقطع نصي — فلا يختلف القطع بين المعاينة
  /// وWord، ويقرأ الراسمان القائمة نفسها بلا إعادة تحليل.
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
    for (final segment in TexContent.split(text)) {
      if (segment.text.isEmpty) {
        continue;
      }
      if (segment.isMath) {
        runs.add(
          VisualRun(
            VisualRunKind.math,
            segment.text,
            isBlockMath: segment.isBlock,
          ),
        );
        continue;
      }
      // النص العادي نفسه قد يحمل آيات موسومة بقوسَي المصحف.
      for (final piece in QuranText.split(segment.text)) {
        if (piece.text.isEmpty) {
          continue;
        }
        if (piece.isQuran) {
          // الخط القرآني جزء من **معنى المقطع** لا من قرار الراسم: يصل إلى
          // المعاينة وPDF وWord من مصدر واحد، فيُطبع بتنسيقه المعلن هنا.
          runs.add(
            VisualRun(
              VisualRunKind.quran,
              piece.text,
              style: const VisualRunStyle(font: PaperFont.amiri),
            ),
          );
          continue;
        }
        runs.add(VisualRun(VisualRunKind.text, piece.text));
      }
    }
    return List<VisualRun>.unmodifiable(runs);
  }
}
