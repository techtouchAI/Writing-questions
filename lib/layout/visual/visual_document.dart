import '../../models/branch_item.dart';
import '../../models/exam_document.dart';
import '../../models/paper_divider.dart';
import '../../models/paper_text_style.dart';
import '../../models/question_option.dart';
import '../blueprint/exam_blueprint.dart';
import 'visual_content.dart';
import 'visual_metrics.dart';
import 'visual_style.dart';

/// نوع العنصر البصري داخل كتلة.
enum VisualElementKind {
  /// سطر قسم السؤال.
  category,

  /// سطر عنوان (رقم ← منطوق ← درجة).
  title,

  /// نص متن.
  body,

  /// نقطة مرقّمة (رقم ← نص ← ملحق ← درجة) مع خياراتها.
  point,

  /// فاصل رسومي بعد الكتلة.
  divider,
}

/// عنصر بصري واحد: ماذا يُرسم، وبأي دور نصّي، وبأي إزاحة وفجوة ومحاذاة.
///
/// **لا إحداثيات مطلقة هنا**: الموضع النهائي يحدده محرك التقسيم
/// ([PaginationEngine]) بنفس الكتلة، فيبقى مصدر واحد للصفحات، ويبقى هذا
/// العقد مسؤولاً عن *البنية والتنسيق* لا عن الإحداثيات.
class VisualElement {
  const VisualElement({
    required this.kind,
    required this.role,
    required this.content,
    required this.indentPx,
    required this.gapBeforePx,
    required this.gapAfterPx,
    this.style,
    this.align,
    this.title,
    this.point,
    this.divider,
  });

  final VisualElementKind kind;

  /// دور النص في عقد الطباعة ([ExamTypography]).
  final VisualRole role;

  /// المقاطع (نص/رياضيات/قرآن) — مصدر الرسم الوحيد.
  final RichContent content;

  /// إزاحة العنصر عن بداية الكتلة بالبكسل المنطقي.
  final double indentPx;

  /// الفجوة قبله/بعده بالبكسل المنطقي.
  final double gapBeforePx;
  final double gapAfterPx;

  /// تنسيق العنصر من النموذج (المصدر الذي كتبه المدرس).
  final PaperTextStyle? style;

  /// محاذاة العنصر النهائية (تنسيق العنصر ثم محاذاة السياق).
  final PaperAlign? align;

  /// أجزاء سطر العنوان (للنوع [VisualElementKind.title]).
  final VisualTitleParts? title;

  /// أجزاء النقطة (للنوع [VisualElementKind.point]).
  final VisualPointParts? point;

  /// الفاصل (للنوع [VisualElementKind.divider]).
  final PaperDivider? divider;
}

/// أجزاء سطر العنوان: الرقم ← المنطوق ← الدرجة.
class VisualTitleParts {
  const VisualTitleParts({
    required this.number,
    required this.statement,
    required this.marks,
  });

  final String number;
  final String statement;
  final String? marks;

  bool get hasStatement => statement.isNotEmpty;
}

/// خيار «اختيار من متعدد» في العقد البصري.
class VisualOptionParts {
  const VisualOptionParts({
    required this.model,
    required this.index,
    required this.label,
    required this.content,
  });

  final QuestionOption model;
  final int index;

  /// التسمية المطبوعة «( أ )» (فارغة = بلا تسمية).
  final String label;

  final RichContent content;
}

/// أجزاء النقطة: الرقم ← النص ← الملحق ← الدرجة، وتحتها الخيارات.
class VisualPointParts {
  const VisualPointParts({
    required this.number,
    required this.content,
    required this.trailer,
    required this.marks,
    required this.options,
    required this.model,
  });

  final String number;
  final RichContent content;

  /// ما يُلحق بالنص: قوسا «صح/خطأ» أو فراغ «إكمال الفراغ» (`null` = لا شيء).
  final String? trailer;
  final String? marks;
  final List<VisualOptionParts> options;

  /// العنصر النموذجي (للتمييز بين أنواع النقاط والخيارات في الراسم).
  final BranchItem model;
}

/// كتلة بصرية واحدة: الترويسة أو التذييل أو سؤال كامل بفروعه.
class VisualBlock {
  const VisualBlock({
    required this.id,
    required this.elements,
    required this.spacingAfterPx,
    this.questionIndex,
    this.isHeader = false,
    this.isFooter = false,
  });

  final String id;
  final List<VisualElement> elements;

  /// المسافة بعد الكتلة (من إعداد السؤال أو فجوة الكتل العامة).
  final double spacingAfterPx;

  final int? questionIndex;
  final bool isHeader;
  final bool isFooter;

  bool get isQuestion => questionIndex != null;
}

/// **المستند البصري**: قائمة الكتل ببنيتها وتنسيقها كما ستُرسم.
///
/// هو المصدر الوحيد الذي يقرأ منه الراسمون (المعاينة، PDF، Word) *بنية*
/// العناصر وإزاحاتها وفجواتها ومحاذاتها ومقاطع محتواها. الإحداثيات الرأسية
/// النهائية تنتج من [PaginationEngine] على هذه الكتل نفسها، فلا يوجد محرك
/// تخطيط ثالث يقسّم الصفحات منفرداً.
class VisualDocument {
  const VisualDocument({
    required this.blocks,
    required this.header,
    required this.footer,
  });

  final List<VisualBlock> blocks;
  final VisualBlock header;
  final VisualBlock footer;

  VisualBlock? questionBlock(String id) {
    for (final block in blocks) {
      if (block.id == id) {
        return block;
      }
    }
    return null;
  }
}

/// باني المستند البصري: يحوّل [ExamBlueprint] إلى بنية عناصر بأدوار وإزاحات
/// وفجوات ومحاذاة — بلا أي اعتماد على Flutter أو pdf أو XML.
abstract final class VisualLayoutEngine {
  /// يبني المستند البصري الكامل لـ[document].
  static VisualDocument build(ExamDocument document) {
    final blueprint = ExamBlueprint.from(document);
    final globalIds =
        document.floatingElements.map((element) => element.id).toSet();
    return VisualDocument(
      header: _headerBlock(blueprint),
      footer: _footerBlock(blueprint),
      blocks: <VisualBlock>[
        for (final question in blueprint.questions)
          _questionBlock(document, question, globalIds),
      ],
    );
  }

  // ------------------------------ الترويسة ------------------------------

  static VisualBlock _headerBlock(ExamBlueprint blueprint) {
    final header = blueprint.header;
    final elements = <VisualElement>[];

    double gap = 0;
    void addLines(List<String> lines, PaperAlign align, {bool bold = false}) {
      for (final line in lines) {
        elements.add(
          VisualElement(
            kind: VisualElementKind.body,
            role: bold ? VisualRole.headerTitle : VisualRole.headerBody,
            content: RichContent.parse(line),
            indentPx: VisualMetrics.blockStartIndentPx,
            gapBeforePx: gap,
            gapAfterPx: 0,
            align: align,
          ),
        );
        gap = VisualMetrics.elementGapPx;
      }
    }

    if (header.showBismillah) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.bismillah,
          content: RichContent.plain(header.bismillah),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          align: PaperAlign.center,
        ),
      );
    }
    addLines(header.rightLines, PaperAlign.center);
    addLines(header.centerLines, PaperAlign.center, bold: true);
    addLines(header.leftLines, PaperAlign.end);

    return VisualBlock(
      id: 'header',
      elements: elements,
      spacingAfterPx: VisualMetrics.blockSpacingPx,
      isHeader: true,
    );
  }

  static VisualBlock _footerBlock(ExamBlueprint blueprint) {
    final footer = blueprint.footer;
    final elements = <VisualElement>[];
    void signature(SignatureBlueprint source) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.headerBody,
          content: RichContent.parse(source.title),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: VisualMetrics.branchGapPx,
          align: PaperAlign.center,
          style: const PaperTextStyle(bold: true),
        ),
      );
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.headerBody,
          content: RichContent.parse(source.nameLine),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          align: PaperAlign.center,
        ),
      );
    }

    if (footer.secondary != null) {
      signature(footer.secondary!);
    }
    final phrase = footer.closingPhrase;
    if (phrase != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.headerBody,
          content: RichContent.parse(phrase),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          align: PaperAlign.center,
          style: const PaperTextStyle(bold: true),
        ),
      );
    }
    signature(footer.primary);

    return VisualBlock(
      id: 'footer',
      elements: elements,
      spacingAfterPx: VisualMetrics.blockSpacingPx,
      isFooter: true,
    );
  }

  // ------------------------------ السؤال ------------------------------

  static VisualBlock _questionBlock(
    ExamDocument document,
    QuestionBlueprint question,
    Set<String> globalIds,
  ) {
    final elements = <VisualElement>[];
    final model = question.model;
    final paragraphSpacing = model.style.paragraphSpacing;
    // فجوة أول عنصر بعد العنوان: تنسيق السؤال إن وُجد، وإلا العقد.
    final elementGap = paragraphSpacing ?? VisualMetrics.elementGapPx;

    if (question.section != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.category,
          role: VisualRole.category,
          content: RichContent.parse(question.section!),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          // القسم له تنسيق مستقل ومحاذاته الخاصة من النموذج، لا يرث السؤال.
          align: model.categoryAlign,
        ),
      );
    }
    elements.add(
      VisualElement(
        kind: VisualElementKind.title,
        role: VisualRole.questionTitle,
        content: RichContent.parse(question.title.line),
        indentPx: VisualMetrics.blockStartIndentPx,
        gapBeforePx: 0,
        gapAfterPx: elementGap,
        style: model.style,
        align: model.titleAlign ?? model.style.align,
        title: VisualTitleParts(
          number: question.title.number,
          statement: question.title.statement,
          marks: question.title.marks,
        ),
      ),
    );
    if (question.body != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.questionBody,
          content: RichContent.parse(question.body!),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: elementGap,
          gapAfterPx: 0,
          style: model.style,
          align: model.bodyAlign ?? model.style.align,
        ),
      );
    }
    _addPoints(
      elements,
      question.points,
      indentPx: VisualMetrics.pointIndentPx,
      firstGapPx: elementGap,
      spacingPx: paragraphSpacing,
      style: model.style,
      ownerAlign: model.style.align,
    );
    for (final branch in question.branches) {
      if (!branch.isPrintable(ignoredAttachmentIds: globalIds)) {
        continue;
      }
      _addBranch(
        elements,
        branch,
        // أول فرع يأخذ فجوة الكتلة نفسها، وبقية الفروع فجوة العنصر.
        gapBeforePx: elements.isEmpty ? 0 : elementGap,
        questionSpacing: paragraphSpacing,
      );
    }
    if (model.dividerAfter != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.divider,
          role: VisualRole.small,
          content: const RichContent(<VisualRun>[]),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          divider: model.dividerAfter,
        ),
      );
    }

    return VisualBlock(
      id: model.id,
      elements: elements,
      spacingAfterPx: model.spacingAfter,
      questionIndex: question.index,
    );
  }

  static void _addBranch(
    List<VisualElement> elements,
    BranchBlueprint branch, {
    required double gapBeforePx,
    required double? questionSpacing,
  }) {
    final style = branch.model.style;
    final paragraphSpacing = style.paragraphSpacing;
    final contentGap = paragraphSpacing ?? VisualMetrics.branchGapPx;
    // عنوان الفرع: فجوة السؤال إن وُجدت، وإلا فجوة العنصر من العقد.
    final titleGap = questionSpacing == null
        ? VisualMetrics.elementGapPx
        : paragraphSpacing ?? VisualMetrics.elementGapPx;

    elements.add(
      VisualElement(
        kind: VisualElementKind.title,
        role: VisualRole.branchTitle,
        content: RichContent.parse(branch.title.line),
        indentPx: VisualMetrics.branchIndentPx,
        gapBeforePx: gapBeforePx,
        gapAfterPx: titleGap,
        style: style,
        align: style.align,
        title: VisualTitleParts(
          number: branch.title.number,
          statement: branch.title.statement,
          marks: branch.title.marks,
        ),
      ),
    );
    if (branch.body != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.body,
          role: VisualRole.branchBody,
          content: RichContent.parse(branch.body!),
          indentPx: VisualMetrics.branchIndentPx,
          gapBeforePx: contentGap,
          gapAfterPx: 0,
          style: style,
          align: style.align,
        ),
      );
    }
    _addPoints(
      elements,
      branch.points,
      indentPx: VisualMetrics.branchIndentPx + VisualMetrics.pointIndentPx,
      firstGapPx: contentGap,
      spacingPx: paragraphSpacing,
      style: style,
      ownerAlign: style.align,
    );
    if (branch.model.dividerAfter != null) {
      elements.add(
        VisualElement(
          kind: VisualElementKind.divider,
          role: VisualRole.small,
          content: const RichContent(<VisualRun>[]),
          indentPx: VisualMetrics.blockStartIndentPx,
          gapBeforePx: 0,
          gapAfterPx: 0,
          divider: branch.model.dividerAfter,
        ),
      );
    }
  }

  static void _addPoints(
    List<VisualElement> elements,
    List<PointBlueprint> points, {
    required double indentPx,
    required double firstGapPx,
    required double? spacingPx,
    required PaperTextStyle? style,
    required PaperAlign? ownerAlign,
  }) {
    var written = 0;
    for (final point in points) {
      if (!point.isPrintable) {
        continue;
      }
      final gap = written == 0 ? firstGapPx : (spacingPx ?? VisualMetrics.itemGapPx);
      elements.add(
        VisualElement(
          kind: VisualElementKind.point,
          role: VisualRole.point,
          content: RichContent.parse(point.text),
          indentPx: indentPx,
          gapBeforePx: gap,
          gapAfterPx: spacingPx ?? 0,
          style: style,
          align: point.item.align ?? ownerAlign,
          point: VisualPointParts(
            number: point.label,
            content: RichContent.parse(point.text),
            trailer: point.trailer,
            marks: point.marks,
            model: point.item,
            options: <VisualOptionParts>[
              for (final option in point.options)
                VisualOptionParts(
                  model: option.option,
                  index: option.index,
                  label: option.label,
                  content: RichContent.parse(option.text),
                ),
            ],
          ),
        ),
      );
      written++;
    }
  }
}
