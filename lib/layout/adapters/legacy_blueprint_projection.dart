import '../../models/branch_item.dart';
import '../../models/exam_document.dart';
import '../../models/floating_element.dart';
import '../../models/question_option.dart';
import '../blueprint/exam_blueprint.dart';
import '../document_ir.dart';
import '../semantic/inline_nodes.dart';

/// Shared mechanical projection from semantic IR nodes into the old string-
/// shaped blueprint contract. It contains no numbering, filtering, or parsing
/// policy; those decisions have already been made upstream in ExamBlueprint
/// and represented by DocumentIR.
abstract final class LegacyBlueprintProjection {
  static ExamBlueprint build(DocumentIR ir, ExamDocument document) {
    final header = HeaderBlueprint(
      showBismillah: ir.header.showBismillah,
      rightLines: <String>[
        for (final line in ir.header.rightColumn) line.content.legacyText,
      ],
      centerLines: <String>[
        for (final line in ir.header.centerColumn) line.content.legacyText,
      ],
      leftLines: <String>[
        for (final line in ir.header.leftColumn) line.content.legacyText,
      ],
      framed: ir.header.framed,
      bismillahSemanticContent: ir.header.bismillah.content,
    );

    final footer = FooterBlueprint(
      closingPhrase: ir.footer.closingPhrase?.content.legacyText,
      primary: _signature(ir.footer.primary),
      secondary: ir.footer.secondary == null
          ? null
          : _signature(ir.footer.secondary!),
    );

    final questions = <QuestionBlueprint>[
      for (final question in ir.questions) _question(question, document),
    ];
    return ExamBlueprint(
      header: header,
      footer: footer,
      questions: List<QuestionBlueprint>.unmodifiable(questions),
      direction: ir.direction,
    );
  }

  /// Adds the semantic label from IR to the old geometry/payload-bearing
  /// floating-element model expected by the current exporters.
  static FloatingElement adaptFloatingElement(
    DocumentIR ir,
    FloatingElement source,
  ) {
    final reference = ir.floatingElementById(source.id);
    final label = reference?.label;
    if (reference == null || label == null) return source;

    if (reference.kind == FloatingReferenceKind.formula) {
      for (final node in label.nodes) {
        if (node is MathNode) {
          return source.copyWith(label: node.source);
        }
      }
    }
    return source.copyWith(label: label.legacyText);
  }

  static SignatureBlueprint _signature(SignatureBlock source) =>
      SignatureBlueprint(
        title: source.title.legacyText,
        name: source.nameIsPlaceholder ? '' : source.name.legacyText,
      );

  static QuestionBlueprint _question(
    QuestionBlock source,
    ExamDocument document,
  ) {
    final model = document.questions[source.index];
    final branches = <BranchBlueprint>[
      for (final branch in source.branches) _branch(branch, document),
    ];
    return QuestionBlueprint(
      model: model,
      index: source.index,
      section: source.category?.content.legacyText,
      title: _title(source.title),
      body: source.body?.content.legacyText,
      points: <PointBlueprint>[
        for (final point in source.points)
          _point(point, model.items[point.index]),
      ],
      branches: List<BranchBlueprint>.unmodifiable(branches),
    );
  }

  static BranchBlueprint _branch(
    BranchBlock source,
    ExamDocument document,
  ) {
    final question = document.questions[source.questionIndex];
    final model = question.branches[source.index];
    return BranchBlueprint(
      model: model,
      questionIndex: source.questionIndex,
      branchIndex: source.index,
      title: _title(source.title),
      body: source.body?.content.legacyText,
      bodyContent: source.body?.content,
      points: <PointBlueprint>[
        for (final point in source.points)
          _point(point, model.content.items[point.index]),
      ],
    );
  }

  static PointBlueprint _point(PointBlock source, BranchItem item) {
    final options = source.options?.options
            .where((option) => option.isPrintable)
            .map((option) => _option(option, item.options[option.index]))
            .toList(growable: false) ??
        const <OptionBlueprint>[];
    return PointBlueprint(
      item: item,
      index: source.index,
      label: source.labelContent.legacyText,
      text: source.content.legacyText,
      trailer: source.trailer?.legacyText,
      marks: source.marks?.legacyText,
      options: options,
    );
  }

  static OptionBlueprint _option(OptionNode source, QuestionOption option) =>
      OptionBlueprint(
        index: source.index,
        option: option,
        label: source.labelContent.legacyText,
      );

  static TitleLineBlueprint _title(TitleParagraphBlock source) =>
      TitleLineBlueprint(
        number: '${source.label.legacyText}${source.separator?.legacyText ?? ''}',
        statement: source.statement.legacyText,
        marks: source.marks?.legacyText,
      );
}
