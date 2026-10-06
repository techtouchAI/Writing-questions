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
  /// **الحال في P0 (مقيسة، لا مُسلَّمة)**: الحقل معلن في العقد ويُدمج في
  /// [merge] ويُحسب في [isEmpty]، لكنه **لا يُقرأ في أي راسم** ولا يكتبه أي
  /// مُنتِج محتوى اليوم: لا `w:position` في OOXML ولا إزاحة في Flutter —
  /// والدليل مُثبَّت في `test/export_gate/p0_export_gate_test.dart`
  /// (P0-GATE-08: كل جريان من `RichContent.parse` بلا إزاحة، ولا `w:position`
  /// في الملف الناتج). أما إزالته تُبقي توقيعاً عاماً وتُغلق مساراً مقصوداً
  /// للمؤشرات، فتُترك مع توصيلها إلى P1 حيث يُعاد بناء راسمي PDF/Word؛ ولم
  /// تدخل في أي تخزين (لا toMap/fromMap) فلا أثر لها على التوافق.
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
    this.sourceStartOffset = 0,
    this.sourceEndOffset = 0,
    this.sourceOffsetMap,
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

  /// UTF-16 source offsets in the complete editable field. For math this
  /// interval includes the source delimiters; plain-run offsets exclude no
  /// visible characters.
  final int sourceStartOffset;
  final int sourceEndOffset;

  /// Optional boundary map when displayed text differs from source text, such
  /// as an escaped literal dollar (`\\$` → `$`).
  final List<int>? sourceOffsetMap;

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
          sourceStartOffset: sourceStartOffset,
          sourceEndOffset: sourceEndOffset,
          sourceOffsetMap: sourceOffsetMap,
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
      if (segment.text.isEmpty) continue;
      if (segment.isMath) {
        runs.add(
          VisualRun(
            VisualRunKind.math,
            segment.text,
            isBlockMath: segment.isBlock,
            sourceStartOffset: segment.startOffset,
            sourceEndOffset: segment.endOffset,
          ),
        );
        continue;
      }
      int sourceOffsetAt(int localOffset) {
        final offsets = segment.sourceOffsets;
        if (localOffset >= 0 && localOffset < offsets.length) {
          return offsets[localOffset];
        }
        return segment.startOffset + localOffset;
      }

      // النص العادي نفسه قد يحمل آيات موسومة بقوسَي المصحف. استعمل
      // الحدود ذاتها التي أعادها محلّل القرآن المشترك، ثم مرّرها إلى IR.
      for (final piece in QuranText.split(segment.text)) {
        if (piece.text.isEmpty) continue;
        final sourceStart = sourceOffsetAt(piece.startOffset);
        final sourceEnd = sourceOffsetAt(piece.endOffset);
        final localMap = segment.sourceOffsets;
        final sourceMap = localMap.length > piece.endOffset
            ? List<int>.unmodifiable(
                localMap.sublist(piece.startOffset, piece.endOffset + 1),
              )
            : null;
        if (piece.isQuran) {
          // الخط القرآني جزء من **معنى المقطع** لا من قرار الراسم: يصل إلى
          // المعاينة وPDF وWord من مصدر واحد، فيُطبع بتنسيقه المعلن هنا.
          runs.add(
            VisualRun(
              VisualRunKind.quran,
              piece.text,
              style: const VisualRunStyle(font: PaperFont.amiri),
              sourceStartOffset: sourceStart,
              sourceEndOffset: sourceEnd,
              sourceOffsetMap: sourceMap,
            ),
          );
          continue;
        }
        runs.add(
          VisualRun(
            VisualRunKind.text,
            piece.text,
            sourceStartOffset: sourceStart,
            sourceEndOffset: sourceEnd,
            sourceOffsetMap: sourceMap,
          ),
        );
      }
    }
    return List<VisualRun>.unmodifiable(runs);
  }
}
