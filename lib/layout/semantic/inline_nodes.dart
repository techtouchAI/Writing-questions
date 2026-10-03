import '../../models/paper_font.dart';
import '../../models/quran_text.dart';
import '../../models/tex_content.dart';
import '../document_direction.dart';
import '../visual/visual_content.dart';

/// Semantic purpose of a generated or manually supplied label.
enum LabelRole {
  question,
  branch,
  item,
  option,
  category,
  headerField,
  signature,
  generic,
}

/// Semantic purpose of a number, independent of the formatting chosen for it.
enum NumberRole { question, item, marks }

/// Punctuation/spacing tokens retained as nodes instead of being appended to
/// adjacent labels or text.
enum SeparatorRole {
  question,
  branch,
  item,
  optionLabel,
  labelValue,
  marks,
  punctuation,
  generic,
}

/// Semantic classification of a Quran run. `verse` is the current domain
/// classification supplied by [QuranText].
enum QuranSemanticKind { verse }

/// Base class for semantic inline items. Each item can carry its own direction
/// so mixed-direction content remains representable at run/node level.
abstract class InlineNode {
  const InlineNode({this.direction = DocumentDirection.auto});

  final DocumentDirection direction;

  /// Source-form text used only at legacy renderer adapter boundaries.
  String get legacyText;

  /// Existing visual rich-run representation for the current renderers.
  List<VisualRun> get visualRuns;

  bool get hasMath => false;
  bool get hasQuran => false;
}

/// A compatibility wrapper around the existing [VisualRun] nucleus.
///
/// New IR code uses the more specific [TextNode], [MathNode], and [QuranNode]
/// subclasses; retaining the source run avoids reparsing rich text while
/// adapting it for the current renderers.
abstract class RichRunNode extends InlineNode {
  const RichRunNode(this.run, {super.direction});

  final VisualRun run;

  String get text => run.text;

  @override
  List<VisualRun> get visualRuns => <VisualRun>[run];

  @override
  String get legacyText {
    switch (run.kind) {
      case VisualRunKind.text:
        // `$` in a plain run is escaped at the legacy boundary so it cannot
        // become a new math delimiter when the legacy renderer parses it.
        return TexContent.escapeLiteral(run.text);
      case VisualRunKind.math:
        final marker = run.isBlockMath ? r'$$' : r'$';
        return '$marker${run.text}$marker';
      case VisualRunKind.quran:
        return run.text;
    }
  }

  @override
  bool get hasMath => run.isMath;

  @override
  bool get hasQuran => run.isQuran;
}

/// Plain textual run. It keeps the existing `VisualRunStyle` if one was
/// supplied by [RichContent].
class TextNode extends RichRunNode {
  TextNode(
    String text, {
    VisualRunStyle? style,
    DocumentDirection direction = DocumentDirection.auto,
  }) : super(
          VisualRun(VisualRunKind.text, text, style: style),
          direction: direction,
        );

  const TextNode.fromRun(super.run, {super.direction});
}

/// A label run whose semantic role is explicit (question/branch/item/option,
/// header field, or signature). Rich labels can themselves contain math or
/// Quran runs without losing their identity as labels.
class LabelNode extends InlineNode {
  const LabelNode(
    this.content, {
    this.role = LabelRole.generic,
    super.direction,
  });

  factory LabelNode.fromSource(
    String source, {
    LabelRole role = LabelRole.generic,
    DocumentDirection direction = DocumentDirection.auto,
  }) =>
      LabelNode(
        InlineContent.fromSource(source, direction: direction),
        role: role,
        direction: direction,
      );

  final InlineContent content;
  final LabelRole role;

  @override
  String get legacyText => content.legacyText;

  @override
  List<VisualRun> get visualRuns => content.visualRuns;

  @override
  bool get hasMath => content.hasMath;

  @override
  bool get hasQuran => content.hasQuran;
}

/// A number with an explicit numeric value and a legacy-compatible display
/// spelling (for example, 2 / `٢`, or question 1 / `السؤال الأول`).
class NumberNode extends InlineNode {
  const NumberNode({
    required this.value,
    required this.displayText,
    required this.role,
    super.direction,
  });

  final num value;
  final String displayText;
  final NumberRole role;

  @override
  String get legacyText => TexContent.escapeLiteral(displayText);

  @override
  List<VisualRun> get visualRuns => <VisualRun>[
        VisualRun(VisualRunKind.text, displayText),
      ];
}

/// Punctuation or a logical delimiter kept separate from labels/content.
class SeparatorNode extends InlineNode {
  const SeparatorNode(
    this.text, {
    this.role = SeparatorRole.generic,
    super.direction,
  });

  final String text;
  final SeparatorRole role;

  @override
  String get legacyText => text;

  @override
  List<VisualRun> get visualRuns => <VisualRun>[
        VisualRun(VisualRunKind.text, text),
      ];
}

/// A LaTeX expression remains a math node, with its source and display/block
/// intent. Raster data, OMML, widgets, and measured geometry are not stored.
class MathNode extends RichRunNode {
  MathNode({
    required String source,
    bool isBlock = false,
    VisualRunStyle? style,
    DocumentDirection direction = DocumentDirection.auto,
  }) : super(
          VisualRun(
            VisualRunKind.math,
            source,
            style: style,
            isBlockMath: isBlock,
          ),
          direction: direction,
        );

  const MathNode.fromRun(super.run, {super.direction});

  String get source => run.text;
  bool get isBlock => run.isBlockMath;
  VisualRunStyle? get style => run.style;
}

/// Quran content remains identifiable, including the source verse markers,
/// Quran font intent, classification, run style, and per-node direction.
class QuranNode extends RichRunNode {
  QuranNode({
    required String source,
    this.classification = QuranSemanticKind.verse,
    this.fontIntent = PaperFont.amiri,
    VisualRunStyle? style,
    DocumentDirection direction = DocumentDirection.auto,
  }) : super(
          VisualRun(
            VisualRunKind.quran,
            source,
            style: style ?? const VisualRunStyle(font: PaperFont.amiri),
          ),
          direction: direction,
        );

  const QuranNode.fromRun(
    super.run, {
    this.classification = QuranSemanticKind.verse,
    this.fontIntent = PaperFont.amiri,
    super.direction,
  });

  final QuranSemanticKind classification;
  final PaperFont fontIntent;

  String get source => run.text;
  VisualRunStyle? get style => run.style;
}

/// Marks remain a typed semantic unit instead of a preformatted string such
/// as `(٢٠ درجة)`. The punctuation, numeric value, and unit are inspectable.
class MarksNode extends InlineNode {
  const MarksNode({
    required this.value,
    required this.number,
    required this.unit,
    this.opening = const SeparatorNode('(', role: SeparatorRole.marks),
    this.numberUnitGap = const SeparatorNode(' ', role: SeparatorRole.marks),
    this.closing = const SeparatorNode(')', role: SeparatorRole.marks),
    super.direction,
  });

  final double value;
  final NumberNode number;
  final LabelNode unit;
  final SeparatorNode opening;
  final SeparatorNode numberUnitGap;
  final SeparatorNode closing;

  @override
  String get legacyText =>
      '${opening.legacyText}${number.legacyText}${numberUnitGap.legacyText}'
      '${unit.legacyText}${closing.legacyText}';

  @override
  List<VisualRun> get visualRuns => <VisualRun>[
        ...opening.visualRuns,
        ...number.visualRuns,
        ...numberUnitGap.visualRuns,
        ...unit.visualRuns,
        ...closing.visualRuns,
      ];

  @override
  bool get hasMath => number.hasMath || unit.hasMath;

  @override
  bool get hasQuran => number.hasQuran || unit.hasQuran;
}

/// An immutable sequence of inline nodes. `fromSource` delegates all legacy
/// parsing to the existing RichContent/VisualRun implementation, then keeps
/// the resulting run identities in the IR.
class InlineContent {
  InlineContent(Iterable<InlineNode> nodes)
      : nodes = List<InlineNode>.unmodifiable(nodes);

  factory InlineContent.empty() => InlineContent(const <InlineNode>[]);

  factory InlineContent.literal(
    String text, {
    DocumentDirection direction = DocumentDirection.auto,
  }) =>
      InlineContent(<InlineNode>[
        TextNode(text, direction: direction),
      ]);

  factory InlineContent.fromSource(
    String source, {
    DocumentDirection direction = DocumentDirection.auto,
  }) =>
      InlineContent.fromRichContent(
        RichContent.parse(source),
        direction: direction,
      );

  factory InlineContent.fromRichContent(
    RichContent content, {
    DocumentDirection direction = DocumentDirection.auto,
  }) {
    final nodes = <InlineNode>[];
    for (final run in content.runs) {
      switch (run.kind) {
        case VisualRunKind.text:
          nodes.add(TextNode.fromRun(run, direction: direction));
          break;
        case VisualRunKind.math:
          nodes.add(MathNode.fromRun(run, direction: direction));
          break;
        case VisualRunKind.quran:
          nodes.add(QuranNode.fromRun(run, direction: direction));
          break;
      }
    }
    return InlineContent(nodes);
  }

  final List<InlineNode> nodes;

  bool get isEmpty => nodes.every((node) => node.legacyText.isEmpty);
  bool get isNotEmpty => !isEmpty;

  bool get hasMath => nodes.any((node) => node.hasMath);
  bool get hasQuran => nodes.any((node) => node.hasQuran);

  bool get isStandaloneQuranVerse {
    final meaningful = nodes.where((node) {
      return !(node is TextNode && node.text.trim().isEmpty);
    }).toList(growable: false);
    return meaningful.length == 1 && meaningful.single is QuranNode;
  }

  /// Legacy source spelling; used only by temporary adapters and editable
  /// controls. It reconstructs math delimiters but does not merge node data in
  /// the IR itself.
  String get legacyText => nodes.map((node) => node.legacyText).join();

  List<VisualRun> get visualRuns => <VisualRun>[
        for (final node in nodes) ...node.visualRuns,
      ];

  /// RichContent view of the existing visual nucleus without reparsing source.
  RichContent get richContent => RichContent(visualRuns);

  InlineContent operator +(InlineContent other) =>
      InlineContent(<InlineNode>[...nodes, ...other.nodes]);
}
