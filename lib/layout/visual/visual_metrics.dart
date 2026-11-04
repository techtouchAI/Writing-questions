import '../paper_metrics.dart';

/// المسافات والإزاحات في العقد البصري — **المصدر الوحيد** لكل رقم هندسي
/// تتفق عليه المعاينة وPDF وWord.
///
/// الأرقام هنا بالبكسل المنطقي للوحة (96dpi) لأن لوحة المعاينة هي المرجع
/// الذي يراه المدرس؛ ويشتق كل راسم وحدته منها:
/// - المعاينة: البكسل كما هو.
/// - PDF: [PaperMetrics.pt] (نقطة = بكسل × 0.75).
/// - Word: [PaperMetrics.twips] (تويب = نقطة × 20).
///
/// كل رقم يظهر هنا يجب أن يُستهلك عبر هذه الطبقة، ولا يُكتب في أي راسم.
abstract final class VisualMetrics {
  /// المسافة بين كتلتين متتاليتين (سؤالين أو الترويسة وأول سؤال) —
  /// مرجعها [PaperMetrics.blockSpacingPx] حتى لا يوجد رقمان للشيء نفسه.
  static const double blockSpacingPx = PaperMetrics.blockSpacingPx;

  /// الفجوة الافتراضية بين عناصر الكتلة (عنوان ← نص ← نقاط ← فروع) عند
  /// غياب `paragraphSpacing` المخصص.
  static const double elementGapPx = PaperMetrics.elementGapPx;

  /// الفجوة الافتراضية بين عنصرين متكررين (نقطة ونقطة).
  static const double itemGapPx = PaperMetrics.itemGapPx;

  /// الفجوة الافتراضية بين عنوان الفرع ومحتواه.
  static const double branchGapPx = PaperMetrics.branchGapPx;

  /// إزاحة كتلة الفرع عن بداية السؤال (كما في المعاينة: `start: 26`).
  static const double branchIndentPx = 26;

  /// إزاحة صف النقطة عن بداية السؤال/الفرع (المعاينة: `start: 36`).
  static const double pointIndentPx = 36;

  /// إزاحة صف الخيارات داخل النقطة (المعاينة: `start: 20` إضافةً إلى إزاحة
  /// النقطة، أي 56px من بداية الكتلة).
  static const double optionIndentPx = 20;

  /// الفجوة بين تسمية الخيار («أ)») ونصه (المعاينة: `SizedBox(width: 6)`).
  static const double optionLabelGapPx = 6;

  /// Existing native option-label top padding; shared with print layout.
  static const double optionLabelTopInsetPx = 1;

  /// عرض صندوق الخيار الواحد: صفّ الخيارات يقسم السطر إلى صناديق ثابتة
  /// العرض (المعاينة وPDF وWord) فلا ينكسر الصف من راسم إلى آخر.
  static const double optionBoxWidthPx = 190;

  /// الفجوة بين تسمية النقطة («١-») ونصها في الصف نفسه.
  static const double pointLabelGapPx = 6;

  /// المسافة الأفقية بين خيارين متجاورين في صف واحد.
  static const double optionWrapSpacingPx = 14;

  /// الفجوة الرأسية بين سطر النقطة وصف خياراتها (المعاينة: `top: 2`).
  static const double optionTopGapPx = 2;

  /// المسافة الرأسية بين صفّي خيارات.
  static const double optionRunSpacingPx = 2;

  /// الفجوة بين «الرقم» و«المنطوق» في سطر العنوان، وبين المنطوق والدرجة.
  static const double titleGapPx = 4;

  /// حشوة إطار السؤال عندما يُفعَّل إطاره.
  static const double questionFramePaddingPx = 5;

  /// حشوة إطار الفرع عندما يُفعَّل إطاره.
  static const double branchFramePaddingPx = 4;

  /// سماكة خط الفاصل الافتراضي (نفسها في الشاشة والطباعة).
  static const double dividerThicknessPx = 1.2;

  /// ارتفاع شريط القسم؟ لا: لا عناصر زخرفية — القيمة أعلاه للفواصل فقط.

  /// إزاحة سطر القسم/العنوان عن حافة الكتلة (لا إزاحة).
  static const double blockStartIndentPx = 0;

  /// الحد الأدنى لفجوة المعادلة المستقلة قبلها وبعدها (4px = 3pt): هو الرقم
  /// الثابت القديم نفسه، لكنه صار **أرضية** لا القيمة الوحيدة.
  static const double displayMathMinGapPx = 4;

  /// فجوة المعادلة المستقلة مشتقّة من قياسها لا من رقم ثابت.
  ///
  /// القاعدة: نصف ما يزيده ارتفاع صندوق المعادلة المقيس على ارتفاع السطر
  /// المرجعي، بحدّ أدنى [displayMathMinGapPx]. معادلة بكسر أو جذر أو تكامل
  /// ارتفاعها ضعف السطر كانت تأخذ فجوة سطر عادي فتلتصق بالنص حولها؛ هذه
  /// الصيغة تجعل الفجوة تتبع الصندوق نفسه.
  ///
  /// المصدر واحد ويستهلكه مكانان فقط: قرار التخطيط في المحرك (قبل فقرة
  /// المعادلة وبعدها) وحشوة المعاينة في [TexText] — فلا تُحسب الفجوة مرتين
  /// ولا تختلف بين راسم وآخر.
  ///
  /// أي قيمة غير منتهية أو غير موجبة تُعيد الأرضية: لا تخطيط سالبًا ولا
  /// لانهائيًا.
  static double displayMathGapPx({
    required double mathHeightPx,
    required double lineHeightPx,
  }) {
    if (!mathHeightPx.isFinite ||
        !lineHeightPx.isFinite ||
        mathHeightPx <= 0 ||
        lineHeightPx <= 0) {
      return displayMathMinGapPx;
    }
    final extra = (mathHeightPx - lineHeightPx) / 2;
    return extra > displayMathMinGapPx ? extra : displayMathMinGapPx;
  }
}
