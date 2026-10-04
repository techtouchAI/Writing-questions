import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../document_direction.dart';
import '../document_ir.dart';
import '../semantic/inline_nodes.dart';
import 'layout_units.dart';

/// Why a page boundary was introduced. `explicitBreak` is reserved for a
/// semantic page-break block should that feature be added to DocumentIR.
enum PageBreakReason {
  naturalOverflow,
  explicitBreak,
  assignedPageBoundary,
  keepTogether,
  forcedSplit,
  headerFooterReservation,
}

enum LayoutBlockKind {
  header,
  footer,
  question,
  branch,
  category,
  title,
  body,
  point,
  option,
  attachment,
  divider,
  floatingElement,
  generic,
}

/// Drawing kind and semantic role are separate: e.g. a math run can still be
/// owned by a label node, while number/separator/marks remain distinguishable.
enum LayoutContentKind { text, math, quran, label, number, separator, marks, image }

enum LayoutSemanticRole { text, label, number, separator, marks, image }

enum FloatAnchorPolicy { inline, blockFlow, pageAnchored, contentAreaAnchored }

enum LayoutDecorationKind { border, divider }

/// Geometry-only decoration consumed by Preview/PDF painters.
class LayoutDecoration {
  const LayoutDecoration({
    required this.id,
    required this.semanticNodeId,
    required this.kind,
    required this.rect,
    required this.strokeWidthPt,
    this.colorArgb = 0xFF000000,
    this.radiusPt = 0,
  });

  final String id;
  final String semanticNodeId;
  final LayoutDecorationKind kind;
  final LayoutRect rect;
  final double strokeWidthPt;
  final int colorArgb;
  final double radiusPt;
}

/// Resolved, renderer-neutral text style. All lengths are points.
class LayoutTextStyle {
  const LayoutTextStyle({
    required this.font,
    required this.fontSizePt,
    required this.lineHeightFactor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.colorArgb,
    this.letterSpacingPt,
    this.alignment,
    this.baselineShiftPt = 0,
  });

  final PaperFont font;
  final double fontSizePt;
  final double lineHeightFactor;
  final bool bold;
  final bool italic;
  final bool underline;
  final int? colorArgb;
  final double? letterSpacingPt;
  final PaperAlign? alignment;
  final double baselineShiftPt;

  LayoutTextStyle copyWith({
    PaperFont? font,
    double? fontSizePt,
    double? lineHeightFactor,
    bool? bold,
    bool? italic,
    bool? underline,
    int? Function()? colorArgb,
    double? Function()? letterSpacingPt,
    PaperAlign? Function()? alignment,
    double? baselineShiftPt,
  }) =>
      LayoutTextStyle(
        font: font ?? this.font,
        fontSizePt: fontSizePt ?? this.fontSizePt,
        lineHeightFactor: lineHeightFactor ?? this.lineHeightFactor,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        colorArgb: colorArgb == null ? this.colorArgb : colorArgb(),
        letterSpacingPt: letterSpacingPt == null
            ? this.letterSpacingPt
            : letterSpacingPt(),
        alignment: alignment == null ? this.alignment : alignment(),
        baselineShiftPt: baselineShiftPt ?? this.baselineShiftPt,
      );
}

/// A resolved math box provided by the shared math measurement/cache service.
/// `baselinePt == null` means the math backend did not report one; the engine
/// uses the box bottom without inventing a descent value.
class LayoutMathBox {
  const LayoutMathBox({
    required this.widthPt,
    required this.heightPt,
    this.baselinePt,
    this.source = 'mathSnapshot',
  });

  final double widthPt;
  final double heightPt;
  final double? baselinePt;
  final String source;
}

class LayoutSplitMetadata {
  const LayoutSplitMetadata({
    this.fragmentIndex = 0,
    this.fragmentCount = 1,
    this.firstLineIndex = 0,
    this.lastLineIndexExclusive = 0,
    this.continuesFromPrevious = false,
    this.continuesOnNext = false,
  });

  final int fragmentIndex;
  final int fragmentCount;
  final int firstLineIndex;
  final int lastLineIndexExclusive;
  final bool continuesFromPrevious;
  final bool continuesOnNext;

  bool get isSplit => fragmentCount > 1;
}

/// Semantic paragraph line with final point-space geometry. y/baseline and all
/// run x positions are absolute from the top-left of their page.
class LayoutLine {
  const LayoutLine({
    required this.id,
    required this.semanticNodeId,
    required this.semanticNode,
    required this.paragraphIndex,
    required this.lineIndex,
    required this.rect,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.leading,
    required this.direction,
    required this.alignment,
    required this.runs,
    required this.logicalRunIds,
    required this.visualRunIds,
    required this.naturalWidth,
    required this.resolvedWidth,
    required this.isJustified,
    required this.justificationOpportunityCount,
    required this.extraSpacePerOpportunity,
  });

  final String id;
  final String semanticNodeId;
  final Object? semanticNode;
  final int paragraphIndex;
  final int lineIndex;
  final LayoutRect rect;
  final double baseline;
  final double ascent;
  final double descent;
  final double leading;
  final DocumentDirection direction;
  final PaperAlign? alignment;
  final List<LayoutRun> runs;
  final List<String> logicalRunIds;
  final List<String> visualRunIds;
  final double naturalWidth;
  final double resolvedWidth;
  final bool isJustified;
  final int justificationOpportunityCount;
  final double extraSpacePerOpportunity;

  double get y => rect.top;
  double get height => rect.height;
}

/// A visual fragment of a semantic inline node. `semanticNode` retains the
/// actual DocumentIR object reference; IDs are deterministic tree paths and
/// never depend on matching text after layout.
class LayoutRun {
  const LayoutRun({
    required this.id,
    required this.semanticNodeId,
    required this.semanticNode,
    required this.contentKind,
    required this.semanticRole,
    required this.text,
    required this.x,
    required this.advance,
    required this.width,
    required this.height,
    required this.baselineOffset,
    required this.direction,
    required this.style,
    required this.logicalIndex,
    required this.visualIndex,
    this.mathBox,
    this.measurementSource = 'fontMetrics',
  });

  final String id;
  final String semanticNodeId;
  final InlineNode? semanticNode;
  final LayoutContentKind contentKind;
  final LayoutSemanticRole semanticRole;
  final String text;
  final double x;
  final double advance;
  final double width;
  final double height;
  final double baselineOffset;
  final DocumentDirection direction;
  final LayoutTextStyle style;
  final int logicalIndex;
  final int visualIndex;
  final LayoutMathBox? mathBox;
  final String measurementSource;

  bool get isMath => contentKind == LayoutContentKind.math;
  bool get isQuran => contentKind == LayoutContentKind.quran;
  bool get isImage => contentKind == LayoutContentKind.image;
}

/// Layout block (or page fragment) linked to an exact semantic block/node.
class LayoutBlock {
  const LayoutBlock({
    required this.id,
    required this.semanticNodeId,
    required this.semanticNode,
    required this.kind,
    required this.rect,
    required this.lines,
    this.children = const <LayoutBlock>[],
    this.decorations = const <LayoutDecoration>[],
    this.split = const LayoutSplitMetadata(),
    this.breakReason,
    this.scaleFactor = 1,
    this.keepTogether = false,
    this.continuation = false,
  });

  /// Layout occurrence ID. A split semantic block has one occurrence per page.
  final String id;
  final String semanticNodeId;
  final Object? semanticNode;
  final LayoutBlockKind kind;
  final LayoutRect rect;
  final List<LayoutLine> lines;
  final List<LayoutBlock> children;
  final List<LayoutDecoration> decorations;
  final LayoutSplitMetadata split;
  final PageBreakReason? breakReason;
  final double scaleFactor;
  final bool keepTogether;
  final bool continuation;

  Iterable<LayoutBlock> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  /// Lines directly owned by this block and all nested blocks, in tree order.
  Iterable<LayoutLine> get allLines sync* {
    yield* lines;
    for (final child in children) {
      yield* child.allLines;
    }
  }
}

class LayoutFloatPlacement {
  const LayoutFloatPlacement({
    required this.semanticNodeId,
    required this.reference,
    required this.policy,
    required this.pageIndex,
    required this.rect,
    this.rotationDegrees = 0,
    this.strokeWidthPt = 0,
    this.framed = false,
    this.labelLines = const <LayoutLine>[],
    this.deferredReason,
  });

  final String semanticNodeId;
  final FloatingElementReference reference;
  final FloatAnchorPolicy policy;
  final int pageIndex;
  final LayoutRect rect;
  final double rotationDegrees;
  final double strokeWidthPt;
  final bool framed;
  final List<LayoutLine> labelLines;
  final String? deferredReason;
}

class LayoutPage {
  const LayoutPage({
    required this.index,
    required this.pageSize,
    required this.contentBounds,
    required this.bodyBounds,
    required this.blocks,
    required this.floatingElements,
    this.decorations = const <LayoutDecoration>[],
    this.headerBounds,
    this.footerBounds,
    this.breakReason,
    this.usedBodyHeight = 0,
    this.scaleFactor = 1,
  });

  final int index;
  final LayoutSize pageSize;
  final LayoutRect contentBounds;
  final LayoutRect bodyBounds;
  final LayoutRect? headerBounds;
  final LayoutRect? footerBounds;
  final List<LayoutBlock> blocks;
  final List<LayoutFloatPlacement> floatingElements;
  final List<LayoutDecoration> decorations;
  final PageBreakReason? breakReason;
  final double usedBodyHeight;
  final double scaleFactor;

  bool get isEmpty => blocks.isEmpty;
}

/// Renderer-independent final layout. The source DocumentIR is retained for
/// traceability, not copied into renderer-specific fields.
class LayoutDocument {
  LayoutDocument({
    required this.source,
    required this.pageSize,
    required this.direction,
    required List<LayoutPage> pages,
    required this.headerBlock,
    required this.footerBlock,
    required this.measurementBackend,
    this.pageFrameImagePath,
  }) : pages = List<LayoutPage>.unmodifiable(pages);

  final DocumentIR source;
  final LayoutSize pageSize;
  final DocumentDirection direction;
  final List<LayoutPage> pages;
  final LayoutBlock? headerBlock;
  final LayoutBlock? footerBlock;

  /// Identifier for the external, isolated metrics backend. No backend object
  /// or renderer object leaks into the layout result.
  final String measurementBackend;
  final String? pageFrameImagePath;

  int get pageCount => pages.length;

  /// Question IDs assigned to each page, in visual/source reading order.
  List<List<String>> get questionPageAssignments =>
      List<List<String>>.unmodifiable(<List<String>>[
        for (final page in pages)
          List<String>.unmodifiable(page.blocks
              .where((block) => block.kind == LayoutBlockKind.question)
              .map((block) => block.semanticNodeId)),
      ]);

  int? pageIndexOf(String semanticBlockId) {
    for (final page in pages) {
      for (final block in page.blocks) {
        if (block.semanticNodeId == semanticBlockId) return page.index;
        if (block.descendants.any((child) => child.semanticNodeId == semanticBlockId)) {
          return page.index;
        }
      }
    }
    for (final page in pages) {
      if (page.floatingElements.any((placement) =>
          placement.semanticNodeId == semanticBlockId ||
          placement.reference.id == semanticBlockId)) {
        return page.index;
      }
    }
    return null;
  }

  Iterable<LayoutBlock> get allBlocks sync* {
    for (final page in pages) {
      for (final block in page.blocks) {
        yield block;
        yield* block.descendants;
      }
    }
  }

  Iterable<LayoutLine> get allLines sync* {
    for (final page in pages) {
      for (final block in page.blocks) {
        yield* block.allLines;
      }
      for (final float in page.floatingElements) {
        yield* float.labelLines;
      }
    }
  }

  LayoutBlock? blockBySemanticId(String semanticBlockId) {
    for (final block in allBlocks) {
      if (block.semanticNodeId == semanticBlockId) return block;
    }
    return null;
  }

  List<LayoutRun> runsForSemanticId(String semanticNodeId) =>
      List<LayoutRun>.unmodifiable(<LayoutRun>[
        for (final block in allBlocks)
          for (final line in block.lines)
            for (final run in line.runs)
              if (run.semanticNodeId == semanticNodeId) run,
      ]);
}
