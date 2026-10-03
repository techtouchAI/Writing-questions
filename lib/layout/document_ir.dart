import '../models/exam_document.dart';
import '../models/floating_element.dart';
import '../models/paper_text_style.dart';
import '../models/point_kind.dart';
import 'blueprint/exam_blueprint.dart';
import 'document_direction.dart';
import 'semantic/inline_nodes.dart';
import 'visual/visual_style.dart';

/// A renderer-independent semantic block with explicit direction metadata.
/// It carries no pagination policy, measured geometry, or page assignments.
abstract class DocumentBlock {
  const DocumentBlock({this.direction = DocumentDirection.inherit});

  final DocumentDirection direction;
}

/// Renderer-neutral style reference: semantic role plus source override. It
/// contains no resolved size, measured metrics, or renderer objects.
class DocumentStyleReference {
  const DocumentStyleReference({this.role, this.override});

  final VisualRole? role;
  final PaperTextStyle? override;
}

/// Basic paragraph block used for body text and header/footer lines.
class ParagraphBlock extends DocumentBlock {
  const ParagraphBlock({
    required this.content,
    this.style = const DocumentStyleReference(),
    this.alignment,
    super.direction,
  });

  final InlineContent content;
  final DocumentStyleReference style;
  final PaperAlign? alignment;
}

/// A category label remains an explicit document block rather than being
/// folded into the following question title.
class CategoryBlock extends ParagraphBlock {
  const CategoryBlock({
    required this.questionId,
    required InlineContent content,
    PaperAlign? alignment,
    DocumentDirection direction = DocumentDirection.inherit,
  }) : super(
          content: content,
          style: const DocumentStyleReference(role: VisualRole.category),
          alignment: alignment,
          direction: direction,
        );

  final String questionId;
}

/// Structured question/branch heading. `label` and `separator` never become
/// part of [statement]; [marks] remains a typed MarksNode.
class TitleParagraphBlock extends DocumentBlock {
  const TitleParagraphBlock({
    required this.label,
    required this.statement,
    this.separator,
    this.marks,
    required this.style,
    this.alignment,
    super.direction,
  });

  final InlineNode label;
  final SeparatorNode? separator;
  final InlineContent statement;
  final MarksNode? marks;
  final DocumentStyleReference style;
  final PaperAlign? alignment;

  InlineContent get labelContent => InlineContent(<InlineNode>[
        label,
        if (separator != null) separator!,
      ]);
}

/// A box/container is semantic grouping and frame intent only. Its children
/// retain document order; no dimensions or coordinates are stored.
class ContainerBlock extends DocumentBlock {
  const ContainerBlock({
    required this.kind,
    required this.children,
    this.framed = false,
    super.direction,
  });

  final ContainerKind kind;
  final List<DocumentBlock> children;
  final bool framed;
}

enum ContainerKind { question, branch, generic }

/// A branch title, body, points, attachments, and divider.
class BranchBlock extends DocumentBlock {
  const BranchBlock({
    required this.id,
    required this.questionId,
    required this.questionIndex,
    required this.index,
    required this.title,
    required this.body,
    required this.points,
    required this.attachments,
    required this.container,
    required this.hasDividerAfter,
    required this.style,
    required this.alignment,
    required this.isPrintable,
    super.direction,
  });

  final String id;
  final String questionId;
  final int questionIndex;
  final int index;
  final TitleParagraphBlock title;
  final ParagraphBlock? body;
  final List<PointBlock> points;
  final AttachmentBlock? attachments;
  final ContainerBlock container;
  final bool hasDividerAfter;
  final DocumentStyleReference style;
  final PaperAlign? alignment;
  final bool isPrintable;

  LabelNode get label => title.label is LabelNode
      ? title.label as LabelNode
      : LabelNode.fromSource(title.label.legacyText, role: LabelRole.branch);
  SeparatorNode? get separator => title.separator;
  InlineContent get content => title.statement;
  MarksNode? get marks => title.marks;
}

/// Numbered question block with separate label/separator/statement/marks,
/// category, body, points, branches, attachments and optional frame intent.
class QuestionBlock extends DocumentBlock {
  const QuestionBlock({
    required this.id,
    required this.index,
    required this.number,
    required this.separator,
    required this.content,
    required this.marks,
    required this.title,
    required this.category,
    required this.body,
    required this.points,
    required this.branches,
    required this.attachments,
    required this.container,
    required this.hasDividerAfter,
    required this.style,
    required this.titleAlignment,
    required this.bodyAlignment,
    required this.categoryAlignment,
    required this.isPrintable,
    super.direction,
  });

  final String id;
  final int index;
  final InlineNode number;
  final SeparatorNode? separator;
  final InlineContent content;
  final MarksNode? marks;
  final TitleParagraphBlock title;
  final CategoryBlock? category;
  final ParagraphBlock? body;
  final List<PointBlock> points;
  final List<BranchBlock> branches;
  final AttachmentBlock? attachments;
  final ContainerBlock container;
  final bool hasDividerAfter;
  final DocumentStyleReference style;
  final PaperAlign? titleAlignment;
  final PaperAlign? bodyAlignment;
  final PaperAlign? categoryAlignment;
  final bool isPrintable;

  String get sourceId => id;
}

/// One question item. Generated item numbers are NumberNodes with a separate
/// dash SeparatorNode; custom labels are LabelNodes with no generated dash.
class PointBlock extends DocumentBlock {
  const PointBlock({
    required this.id,
    required this.index,
    required this.number,
    required this.label,
    required this.separator,
    required this.content,
    required this.trailer,
    required this.marks,
    required this.options,
    required this.kind,
    required this.alignment,
    required this.isPrintable,
    super.direction,
  });

  final String id;
  final int index;
  final NumberNode? number;
  final LabelNode? label;
  final SeparatorNode? separator;
  final InlineContent content;
  final InlineContent? trailer;
  final MarksNode? marks;
  final OptionsBlock? options;
  final PointKind kind;
  final PaperAlign? alignment;
  final bool isPrintable;

  InlineNode? get labelOrNumber => number ?? label;
  InlineContent get labelContent => InlineContent(<InlineNode>[
        if (labelOrNumber != null) labelOrNumber!,
        if (separator != null) separator!,
      ]);
}

/// Multiple-choice options remain a list. Legacy spacing is a renderer policy
/// and is intentionally not stored here.
class OptionsBlock extends DocumentBlock {
  const OptionsBlock({
    required this.options,
    super.direction,
  });

  final List<OptionNode> options;
}

class OptionNode {
  const OptionNode({
    required this.id,
    required this.index,
    required this.label,
    required this.labelPrefix,
    required this.labelSuffix,
    required this.labelTextSeparator,
    required this.content,
    required this.alignment,
    required this.isPrintable,
    this.direction = DocumentDirection.auto,
  });

  final String id;
  final int index;
  final LabelNode label;
  final List<SeparatorNode> labelPrefix;
  final List<SeparatorNode> labelSuffix;
  final SeparatorNode? labelTextSeparator;
  final InlineContent content;
  final PaperAlign? alignment;
  final bool isPrintable;
  final DocumentDirection direction;

  InlineContent get labelContent => InlineContent(<InlineNode>[
        ...labelPrefix,
        label,
        ...labelSuffix,
      ]);
}

/// Bismillah and the three physical header columns. Each line declares the
/// field (class, grade, time, year, etc.) and its content nodes.
class HeaderBlock extends DocumentBlock {
  const HeaderBlock({
    required this.showBismillah,
    required this.bismillah,
    required this.rightColumn,
    required this.centerColumn,
    required this.leftColumn,
    required this.framed,
    super.direction = DocumentDirection.rtl,
  });

  final bool showBismillah;
  final ParagraphBlock bismillah;
  final List<HeaderLineBlock> rightColumn;
  final List<HeaderLineBlock> centerColumn;
  final List<HeaderLineBlock> leftColumn;
  final bool framed;

  Iterable<HeaderLineBlock> get allLines sync* {
    yield* rightColumn;
    yield* centerColumn;
    yield* leftColumn;
  }
}

class HeaderLineBlock extends ParagraphBlock {
  const HeaderLineBlock({
    required this.field,
    required InlineContent content,
    this.bold = false,
    PaperAlign? alignment,
    DocumentDirection direction = DocumentDirection.rtl,
  }) : super(
          content: content,
          style: const DocumentStyleReference(role: VisualRole.headerBody),
          alignment: alignment,
          direction: direction,
        );

  final HeaderFieldKind field;
  final bool bold;
}

/// Closing phrase and signature fields. Names/placeholder are kept distinct
/// from signature titles.
class FooterBlock extends DocumentBlock {
  const FooterBlock({
    required this.closingPhrase,
    required this.primary,
    required this.secondary,
    super.direction = DocumentDirection.rtl,
  });

  final ParagraphBlock? closingPhrase;
  final SignatureBlock primary;
  final SignatureBlock? secondary;

  Iterable<SignatureBlock> get signatures sync* {
    if (secondary != null) yield secondary!;
    yield primary;
  }
}

class SignatureBlock extends DocumentBlock {
  const SignatureBlock({
    required this.title,
    required this.name,
    required this.nameIsPlaceholder,
    super.direction = DocumentDirection.rtl,
  });

  final LabelNode title;
  final InlineContent name;
  final bool nameIsPlaceholder;
}

/// A semantic reference to an attachment. It intentionally omits the source
/// FloatingElement's bytes, x/y, size, rotation, and page index; adapters use
/// the stable ID to look up those legacy rendering inputs when needed.
class FloatingElementReference {
  const FloatingElementReference({
    required this.id,
    required this.kind,
    required this.shape,
    required this.ownerQuestionId,
    required this.ownerBranchId,
    required this.label,
  });

  final String id;
  final FloatingReferenceKind kind;
  final FloatingShapeType? shape;
  final String? ownerQuestionId;
  final String? ownerBranchId;
  final InlineContent? label;
}

enum FloatingReferenceKind { image, shape, textBox, formula }

/// Document-scope floating elements in source order; this is an overlay
/// semantic collection, not a positioned layout object.
class FloatingElementsBlock extends DocumentBlock {
  const FloatingElementsBlock({
    required this.elements,
    super.direction = DocumentDirection.inherit,
  });

  final List<FloatingElementReference> elements;
}

/// Nested legacy attachments are represented by semantic references too.
class AttachmentBlock extends DocumentBlock {
  const AttachmentBlock({
    required this.elements,
    super.direction = DocumentDirection.inherit,
  });

  final List<FloatingElementReference> elements;
}

/// Divider presence/style reference. Geometry stays in the source domain
/// object and is resolved by the legacy adapters.
class DividerBlock extends DocumentBlock {
  const DividerBlock({required this.sourceId, super.direction});

  final String sourceId;
}

/// Canonical renderer-independent document. `blocks` has one deterministic
/// logical order: header, ordered questions, document-scope floats (if any),
/// footer. Page assignment and absolute floating placement are not included.
class DocumentIR {
  const DocumentIR({
    required this.direction,
    required this.header,
    required this.questions,
    required this.footer,
    required this.floatingElements,
  });

  factory DocumentIR.fromBlueprint({
    required ExamBlueprint blueprint,
    required ExamDocument document,
  }) =>
      _DocumentIRBuilder(blueprint, document).build();

  final DocumentDirection direction;
  final HeaderBlock header;
  final List<QuestionBlock> questions;
  final FooterBlock footer;
  final FloatingElementsBlock? floatingElements;

  List<DocumentBlock> get blocks => <DocumentBlock>[
        header,
        ...questions,
        if (floatingElements != null) floatingElements!,
        footer,
      ];

  QuestionBlock? questionById(String id) {
    for (final question in questions) {
      if (question.id == id) return question;
    }
    return null;
  }

  FloatingElementReference? floatingElementById(String id) {
    for (final reference in floatingElements?.elements ??
        const <FloatingElementReference>[]) {
      if (reference.id == id) return reference;
    }
    for (final question in questions) {
      for (final reference in question.attachments?.elements ??
          const <FloatingElementReference>[]) {
        if (reference.id == id) return reference;
      }
      for (final branch in question.branches) {
        for (final reference in branch.attachments?.elements ??
            const <FloatingElementReference>[]) {
          if (reference.id == id) return reference;
        }
      }
    }
    return null;
  }

  bool get hasQuranContent {
    bool referencesHaveQuran(Iterable<FloatingElementReference> references) =>
        references.any((reference) => reference.label?.hasQuran ?? false);

    if (header.showBismillah ||
        header.allLines.any((line) => line.content.hasQuran)) {
      return true;
    }
    if ((footer.closingPhrase?.content.hasQuran ?? false) ||
        footer.signatures.any(
          (signature) => signature.title.hasQuran || signature.name.hasQuran,
        )) {
      return true;
    }
    if (floatingElements != null &&
        referencesHaveQuran(floatingElements!.elements)) {
      return true;
    }
    for (final question in questions) {
      if ((question.category?.content.hasQuran ?? false) ||
          question.number.hasQuran ||
          question.content.hasQuran ||
          (question.marks?.hasQuran ?? false) ||
          (question.body?.content.hasQuran ?? false) ||
          (question.attachments != null &&
              referencesHaveQuran(question.attachments!.elements))) {
        return true;
      }
      for (final point in question.points) {
        if (point.labelContent.hasQuran ||
            point.content.hasQuran ||
            (point.trailer?.hasQuran ?? false) ||
            (point.marks?.hasQuran ?? false)) {
          return true;
        }
        if (point.options != null &&
            point.options!.options.any(
              (option) => option.labelContent.hasQuran || option.content.hasQuran,
            )) {
          return true;
        }
      }
      for (final branch in question.branches) {
        if (branch.label.hasQuran ||
            branch.content.hasQuran ||
            (branch.marks?.hasQuran ?? false) ||
            (branch.body?.content.hasQuran ?? false) ||
            (branch.attachments != null &&
                referencesHaveQuran(branch.attachments!.elements))) {
          return true;
        }
        for (final point in branch.points) {
          if (point.labelContent.hasQuran ||
              point.content.hasQuran ||
              (point.trailer?.hasQuran ?? false) ||
              (point.marks?.hasQuran ?? false) ||
              (point.options != null &&
                  point.options!.options.any(
                    (option) => option.labelContent.hasQuran || option.content.hasQuran,
                  ))) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class _DocumentIRBuilder {
  _DocumentIRBuilder(this.blueprint, this.document);

  final ExamBlueprint blueprint;
  final ExamDocument document;

  DocumentIR build() {
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final direction = blueprint.direction == DocumentDirection.auto
        ? (document.layout.isLtr ? DocumentDirection.ltr : DocumentDirection.rtl)
        : blueprint.direction;
    final header = _header(blueprint.header);
    final questions = <QuestionBlock>[
      for (final question in blueprint.questions)
        _question(question, direction, globalIds),
    ];
    final footer = _footer(blueprint.footer);
    final floatingReferences = <FloatingElementReference>[
      for (final element in document.floatingElements)
        _floatingReference(element),
    ];
    return DocumentIR(
      direction: direction,
      header: header,
      questions: List<QuestionBlock>.unmodifiable(questions),
      footer: footer,
      floatingElements: floatingReferences.isEmpty
          ? null
          : FloatingElementsBlock(
              elements: List<FloatingElementReference>.unmodifiable(
                floatingReferences,
              ),
              direction: direction,
            ),
    );
  }

  HeaderBlock _header(HeaderBlueprint source) {
    HeaderLineBlock line(HeaderLineBlueprint line, PaperAlign alignment) =>
        HeaderLineBlock(
          field: line.field,
          content: line.content,
          bold: line.bold,
          alignment: alignment,
          direction: DocumentDirection.rtl,
        );

    return HeaderBlock(
      showBismillah: source.showBismillah,
      bismillah: ParagraphBlock(
        content: source.bismillahContent,
        style: const DocumentStyleReference(role: VisualRole.bismillah),
        alignment: PaperAlign.center,
        direction: DocumentDirection.rtl,
      ),
      rightColumn: List<HeaderLineBlock>.unmodifiable(
        source.rightSemanticLines.map((entry) => line(entry, PaperAlign.center)),
      ),
      centerColumn: List<HeaderLineBlock>.unmodifiable(
        source.centerSemanticLines.map((entry) => line(entry, PaperAlign.center)),
      ),
      leftColumn: List<HeaderLineBlock>.unmodifiable(
        source.leftSemanticLines.map((entry) => line(entry, PaperAlign.end)),
      ),
      framed: source.framed,
    );
  }

  FooterBlock _footer(FooterBlueprint source) {
    ParagraphBlock? phrase;
    final phraseContent = source.closingPhraseContent;
    if (phraseContent != null) {
      phrase = ParagraphBlock(
        content: phraseContent,
        style: const DocumentStyleReference(role: VisualRole.headerBody),
        alignment: PaperAlign.center,
        direction: DocumentDirection.rtl,
      );
    }

    SignatureBlock signature(SignatureBlueprint entry) => SignatureBlock(
          title: entry.semanticTitle ??
              LabelNode.fromSource(
                entry.title,
                role: LabelRole.signature,
                direction: DocumentDirection.rtl,
              ),
          name: entry.nameLineContent,
          nameIsPlaceholder: entry.name.isEmpty,
          direction: DocumentDirection.rtl,
        );

    return FooterBlock(
      closingPhrase: phrase,
      primary: signature(source.primary),
      secondary: source.secondary == null ? null : signature(source.secondary!),
    );
  }

  QuestionBlock _question(
    QuestionBlueprint source,
    DocumentDirection direction,
    Set<String> globalIds,
  ) {
    final model = source.model;
    final title = TitleParagraphBlock(
      label: source.title.semanticNumber,
      separator: source.title.separatorNode,
      statement: source.title.semanticStatement,
      marks: source.title.marksNode,
      style: DocumentStyleReference(
        role: VisualRole.questionTitle,
        override: model.style,
      ),
      alignment: model.titleAlign ?? model.style.align,
      direction: direction,
    );
    final category = source.category == null
        ? null
        : CategoryBlock(
            questionId: model.id,
            content: source.category!.content,
            alignment: model.categoryAlign,
            direction: direction,
          );
    final body = source.semanticBody == null
        ? null
        : ParagraphBlock(
            content: source.semanticBody!,
            style: DocumentStyleReference(
              role: VisualRole.questionBody,
              override: model.style,
            ),
            alignment: model.bodyAlign ?? model.style.align,
            direction: direction,
          );
    final points = <PointBlock>[
      for (final point in source.points) _point(point, direction),
    ];
    final branches = <BranchBlock>[
      for (final branch in source.branches)
        _branch(branch, direction, globalIds),
    ];
    final attachments = _attachments(
      model.attachments,
      questionId: model.id,
      globalIds: globalIds,
      direction: direction,
    );
    final children = <DocumentBlock>[
      if (category != null) category,
      title,
      if (body != null) body,
      ...points,
      ...branches,
      if (attachments != null) attachments,
      if (model.dividerAfter != null)
        DividerBlock(sourceId: 'question:${model.id}', direction: direction),
    ];
    final container = ContainerBlock(
      kind: ContainerKind.question,
      children: List<DocumentBlock>.unmodifiable(children),
      framed: model.showFrame,
      direction: direction,
    );
    return QuestionBlock(
      id: model.id,
      index: source.index,
      number: title.label,
      separator: title.separator,
      content: title.statement,
      marks: title.marks,
      title: title,
      category: category,
      body: body,
      points: List<PointBlock>.unmodifiable(points),
      branches: List<BranchBlock>.unmodifiable(branches),
      attachments: attachments,
      container: container,
      hasDividerAfter: model.dividerAfter != null,
      style: DocumentStyleReference(
        role: VisualRole.questionBody,
        override: model.style,
      ),
      titleAlignment: model.titleAlign ?? model.style.align,
      bodyAlignment: model.bodyAlign ?? model.style.align,
      categoryAlignment: model.categoryAlign,
      isPrintable: source.isPrintable(ignoredAttachmentIds: globalIds),
      direction: direction,
    );
  }

  BranchBlock _branch(
    BranchBlueprint source,
    DocumentDirection direction,
    Set<String> globalIds,
  ) {
    final model = source.model;
    final title = TitleParagraphBlock(
      label: source.title.semanticNumber,
      separator: source.title.separatorNode,
      statement: source.title.semanticStatement,
      marks: source.title.marksNode,
      style: DocumentStyleReference(
        role: VisualRole.branchTitle,
        override: model.style,
      ),
      alignment: model.style.align,
      direction: direction,
    );
    final bodyContent = source.bodyContent ??
        (source.body == null ? null : InlineContent.fromSource(source.body!));
    final body = bodyContent == null
        ? null
        : ParagraphBlock(
            content: bodyContent,
            style: DocumentStyleReference(
              role: VisualRole.branchBody,
              override: model.style,
            ),
            alignment: model.style.align,
            direction: direction,
          );
    final points = <PointBlock>[
      for (final point in source.points) _point(point, direction),
    ];
    final attachments = _attachments(
      model.attachments,
      questionId: document.questions[source.questionIndex].id,
      branchId: model.id,
      globalIds: globalIds,
      direction: direction,
    );
    final children = <DocumentBlock>[
      title,
      if (body != null) body,
      ...points,
      if (attachments != null) attachments,
      if (model.dividerAfter != null)
        DividerBlock(sourceId: 'branch:${model.id}', direction: direction),
    ];
    final container = ContainerBlock(
      kind: ContainerKind.branch,
      children: List<DocumentBlock>.unmodifiable(children),
      framed: model.showFrame,
      direction: direction,
    );
    return BranchBlock(
      id: model.id,
      questionId: document.questions[source.questionIndex].id,
      questionIndex: source.questionIndex,
      index: source.branchIndex,
      title: title,
      body: body,
      points: List<PointBlock>.unmodifiable(points),
      attachments: attachments,
      container: container,
      hasDividerAfter: model.dividerAfter != null,
      style: DocumentStyleReference(
        role: VisualRole.branchBody,
        override: model.style,
      ),
      alignment: model.style.align,
      isPrintable: source.isPrintable(ignoredAttachmentIds: globalIds),
      direction: direction,
    );
  }

  PointBlock _point(PointBlueprint source, DocumentDirection direction) {
    final labelNode = source.labelNode;
    final options = source.kind == PointKind.multipleChoice
        ? OptionsBlock(
            options: List<OptionNode>.unmodifiable(<OptionNode>[
              for (final option in source.semanticOptions) _option(option),
            ]),
            direction: direction,
          )
        : null;
    return PointBlock(
      id: source.item.id,
      index: source.index,
      number: labelNode is NumberNode ? labelNode : null,
      label: labelNode is LabelNode ? labelNode : null,
      separator: source.labelSeparator,
      content: source.semanticText,
      trailer: source.trailerContent,
      marks: source.marksNode,
      options: options,
      kind: source.kind,
      alignment: source.item.align,
      isPrintable: source.isPrintable,
      direction: direction,
    );
  }

  OptionNode _option(OptionBlueprint source) => OptionNode(
        id: source.option.id,
        index: source.index,
        label: source.labelNode ??
            LabelNode.fromSource(
              source.label,
              role: LabelRole.option,
              direction: DocumentDirection.auto,
            ),
        labelPrefix: source.labelPrefix,
        labelSuffix: source.labelSuffix,
        labelTextSeparator: source.labelTextSeparator,
        content: source.semanticText,
        alignment: source.option.align,
        isPrintable: source.isPrintable,
      );

  AttachmentBlock? _attachments(
    List<FloatingElement> source, {
    required String questionId,
    String? branchId,
    required Set<String> globalIds,
    required DocumentDirection direction,
  }) {
    final references = <FloatingElementReference>[
      for (final element in source)
        if (!globalIds.contains(element.id))
          _floatingReference(
            element,
            ownerQuestionId: questionId,
            ownerBranchId: branchId,
          ),
    ];
    if (references.isEmpty) return null;
    return AttachmentBlock(
      elements: List<FloatingElementReference>.unmodifiable(references),
      direction: direction,
    );
  }

  FloatingElementReference _floatingReference(
    FloatingElement element, {
    String? ownerQuestionId,
    String? ownerBranchId,
  }) {
    final referenceKind = switch (element.type) {
      FloatingElementType.image => FloatingReferenceKind.image,
      FloatingElementType.formula => FloatingReferenceKind.formula,
      FloatingElementType.shape when element.isTextBox => FloatingReferenceKind.textBox,
      FloatingElementType.shape => FloatingReferenceKind.shape,
    };
    InlineContent? label;
    if (element.isFormula) {
      label = InlineContent(<InlineNode>[
        MathNode(source: element.label, isBlock: true),
      ]);
    } else if (element.label.isNotEmpty) {
      label = InlineContent.fromSource(element.label);
    }
    return FloatingElementReference(
      id: element.id,
      kind: referenceKind,
      shape: element.shape,
      ownerQuestionId: ownerQuestionId ?? element.ownerQuestionId,
      ownerBranchId: ownerBranchId,
      label: label,
    );
  }
}
