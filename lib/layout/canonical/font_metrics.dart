import '../document_direction.dart';
import '../semantic/inline_nodes.dart';
import '../../models/paper_text_style.dart';
import 'layout_document.dart';

/// Input atom to the isolated text-layout/metrics backend. It is semantic data
/// plus resolved style; it contains no widget or PDF type.
class MetricSpan {
  const MetricSpan({
    required this.semanticNodeId,
    required this.semanticNode,
    required this.text,
    required this.contentKind,
    required this.semanticRole,
    required this.style,
    required this.direction,
    required this.logicalIndex,
    this.mathBox,
    this.fixedAdvancePt,
    this.isBlockMath = false,
  });

  final String semanticNodeId;
  final InlineNode? semanticNode;
  final String text;
  final LayoutContentKind contentKind;
  final LayoutSemanticRole semanticRole;
  final LayoutTextStyle style;
  final DocumentDirection direction;
  final int logicalIndex;
  final LayoutMathBox? mathBox;
  final double? fixedAdvancePt;
  final bool isBlockMath;

  bool get isFixedAdvance => fixedAdvancePt != null;
  bool get isMath => contentKind == LayoutContentKind.math;
}

/// A measured fragment of one input atom. A logical atom may create several
/// fragments when Unicode bidi places it in separate visual boxes.
class MeasuredRunFragment {
  const MeasuredRunFragment({
    required this.spanIndex,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.x,
    required this.width,
    required this.direction,
    required this.baselineOffset,
    required this.height,
    this.mathBox,
    this.fixedAdvancePt,
  });

  final int spanIndex;
  final String text;
  final int startOffset;
  final int endOffset;
  final double x;
  final double width;
  final DocumentDirection direction;
  final double baselineOffset;
  final double height;
  final LayoutMathBox? mathBox;
  final double? fixedAdvancePt;
}

class MeasuredLine {
  const MeasuredLine({
    required this.index,
    required this.top,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.leading,
    required this.height,
    required this.naturalWidth,
    required this.resolvedWidth,
    required this.isJustified,
    required this.justificationOpportunityCount,
    required this.extraSpacePerOpportunity,
    required this.fragments,
  });

  final int index;
  final double top;
  final double baseline;
  final double ascent;
  final double descent;
  final double leading;
  final double height;
  final double naturalWidth;
  final double resolvedWidth;
  final bool isJustified;
  final int justificationOpportunityCount;
  final double extraSpacePerOpportunity;
  final List<MeasuredRunFragment> fragments;
}

class MeasuredParagraph {
  const MeasuredParagraph({
    required this.width,
    required this.height,
    required this.lines,
  });

  final double width;
  final double height;
  final List<MeasuredLine> lines;
}

class FontRunMetrics {
  const FontRunMetrics({
    required this.advance,
    required this.ascent,
    required this.descent,
    required this.leading,
    required this.baseline,
  });

  final double advance;
  final double ascent;
  final double descent;
  final double leading;
  final double baseline;
  double get height => ascent + descent + leading;
}

/// Renderer-independent measurement contract. The Flutter TextPainter adapter
/// is the first production implementation; test adapters can be deterministic
/// and pure. All inputs/outputs are in points.
abstract interface class FontMetricsProvider {
  String get backendId;

  FontRunMetrics measureText(
    String text,
    LayoutTextStyle style,
    DocumentDirection direction,
  );

  double whitespaceAdvance(
    LayoutTextStyle style,
    DocumentDirection direction, {
    bool nonBreaking = false,
  });

  /// Shapes a complete paragraph once, resolving line breaks, bidi boxes,
  /// alignment, and (when requested and eligible) justification.
  MeasuredParagraph layoutParagraph({
    required List<MetricSpan> spans,
    required double width,
    required DocumentDirection direction,
    required PaperAlign? alignment,
    required bool resolveJustification,
  });
}
