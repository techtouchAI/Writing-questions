import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';

import '../document_direction.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// A screen-space rectangle paired with canonical page geometry. The Flutter
/// render tree may scale/scroll the page, but the returned page coordinates are
/// always LayoutDocument points.
class CanonicalPageTransform {
  const CanonicalPageTransform({
    required this.screenLeft,
    required this.screenTop,
    required this.screenWidth,
    required this.screenHeight,
    required this.pageWidthPt,
    required this.pageHeightPt,
  })  : assert(screenWidth > 0),
        assert(screenHeight > 0),
        assert(pageWidthPt > 0),
        assert(pageHeightPt > 0);

  final double screenLeft;
  final double screenTop;
  final double screenWidth;
  final double screenHeight;
  final double pageWidthPt;
  final double pageHeightPt;

  ({double x, double y}) pagePointFromScreen(double screenX, double screenY) =>
      (
        x: ((screenX - screenLeft) / screenWidth * pageWidthPt)
            .clamp(0.0, pageWidthPt)
            .toDouble(),
        y: ((screenY - screenTop) / screenHeight * pageHeightPt)
            .clamp(0.0, pageHeightPt)
            .toDouble(),
      );

  ({double x, double y}) screenPointFromPage(double xPt, double yPt) =>
      (
        x: screenLeft + xPt / pageWidthPt * screenWidth,
        y: screenTop + yPt / pageHeightPt * screenHeight,
      );
}

/// Canonical target found under a page coordinate. Source offsets are UTF-16
/// offsets into the owning semantic inline node and end offsets are exclusive.
class CanonicalPagePointerEvent {
  const CanonicalPagePointerEvent({
    required this.localPositionPx,
    required this.pagePositionPt,
    required this.hit,
  });

  final Offset localPositionPx;
  final Offset pagePositionPt;
  final CanonicalHitTestResult? hit;
}

class CanonicalHitTestResult {
  const CanonicalHitTestResult({
    required this.pageIndex,
    required this.semanticNodeId,
    required this.rect,
    this.blockId,
    this.blockKind,
    this.lineId,
    this.runId,
    this.sourceStartOffset,
    this.sourceEndOffset,
    this.sourceOffset,
    this.floatingElementId,
  });

  final int pageIndex;
  final String semanticNodeId;
  final LayoutRect rect;
  final String? blockId;
  final LayoutBlockKind? blockKind;
  final String? lineId;
  final String? runId;
  final int? sourceStartOffset;
  final int? sourceEndOffset;
  final int? sourceOffset;
  final String? floatingElementId;

  bool get isText => runId != null;
  bool get isFloatingElement => floatingElementId != null;
}

/// Hit-testing and caret-offset mapping over final canonical geometry. This
/// class does not wrap, align, or paginate: it maps input coordinates onto
/// the page/run rectangles already stored in LayoutDocument.
abstract final class CanonicalLayoutHitTester {
  static CanonicalHitTestResult? hitTest({
    required LayoutPage page,
    required int pageIndex,
    required double xPt,
    required double yPt,
  }) {
    if (!xPt.isFinite || !yPt.isFinite || pageIndex < 0) return null;

    // Floats are painted above flow content, so they win hit testing too.
    for (final placement in page.floatingElements.reversed) {
      if (!_contains(placement.rect, xPt, yPt)) continue;
      final floatRun = _hitLines(
        pageIndex: pageIndex,
        lines: placement.labelLines,
        xPt: xPt,
        yPt: yPt,
        blockId: placement.reference.id,
        blockKind: LayoutBlockKind.floatingElement,
        floatingElementId: placement.reference.id,
      );
      return floatRun ?? CanonicalHitTestResult(
        pageIndex: pageIndex,
        semanticNodeId: placement.semanticNodeId,
        blockId: placement.reference.id,
        blockKind: LayoutBlockKind.floatingElement,
        rect: placement.rect,
        floatingElementId: placement.reference.id,
      );
    }

    final blocks = <LayoutBlock>[];
    void addBlocks(Iterable<LayoutBlock> values) {
      for (final block in values) {
        blocks.add(block);
        addBlocks(block.children);
      }
    }

    addBlocks(page.blocks);
    // Visit deepest/later-painted candidates first; parent question frames do
    // not consume taps intended for a title, body, point, or option.
    for (final block in blocks.reversed) {
      if (!_contains(block.rect, xPt, yPt)) continue;
      final lineResult = _hitLines(
        pageIndex: pageIndex,
        lines: block.lines,
        xPt: xPt,
        yPt: yPt,
        blockId: block.id,
        blockKind: block.kind,
      );
      if (lineResult != null) return lineResult;
      for (final line in block.lines.reversed) {
        if (!_contains(line.rect, xPt, yPt)) continue;
        return CanonicalHitTestResult(
          pageIndex: pageIndex,
          semanticNodeId: line.semanticNodeId,
          blockId: block.id,
          blockKind: block.kind,
          lineId: line.id,
          rect: line.rect,
        );
      }
      return CanonicalHitTestResult(
        pageIndex: pageIndex,
        semanticNodeId: block.semanticNodeId,
        blockId: block.id,
        blockKind: block.kind,
        rect: block.rect,
      );
    }

    return null;
  }

  static CanonicalHitTestResult? _hitLines({
    required int pageIndex,
    required Iterable<LayoutLine> lines,
    required double xPt,
    required double yPt,
    required String blockId,
    required LayoutBlockKind blockKind,
    String? floatingElementId,
  }) {
    for (final line in lines.toList().reversed) {
      if (!_contains(line.rect.inflate(1), xPt, yPt)) continue;
      LayoutRun? selected;
      var selectedDistance = double.infinity;
      for (final run in line.runs) {
        final runRect = _runRect(line, run);
        final distance = _distanceTo(runRect, xPt, yPt);
        if (distance < selectedDistance) {
          selected = run;
          selectedDistance = distance;
        }
        if (_contains(runRect.inflate(1), xPt, yPt)) {
          selected = run;
          selectedDistance = 0;
          break;
        }
      }
      if (selected == null) continue;
      final run = selected;
      final sourceStart = run.sourceStartOffset;
      final sourceEnd = run.sourceEndOffset > sourceStart
          ? run.sourceEndOffset
          : sourceStart + run.text.length;
      return CanonicalHitTestResult(
        pageIndex: pageIndex,
        semanticNodeId: run.semanticNodeId,
        blockId: blockId,
        blockKind: blockKind,
        lineId: line.id,
        runId: run.id,
        sourceStartOffset: sourceStart,
        sourceEndOffset: sourceEnd,
        sourceOffset: _sourceOffsetAt(run, xPt),
        floatingElementId: floatingElementId,
        rect: _runRect(line, run),
      );
    }
    return null;
  }

  static int _sourceOffsetAt(LayoutRun run, double xPt) {
    final start = run.sourceStartOffset;
    final end = run.sourceEndOffset > start
        ? run.sourceEndOffset
        : start + run.text.length;
    if (run.text.isEmpty || run.isMath) {
      return xPt <= run.x + run.width / 2 ? start : end;
    }
    final direction = run.direction == DocumentDirection.rtl
        ? TextDirection.rtl
        : TextDirection.ltr;
    final style = run.style;
    final painter = TextPainter(
      text: TextSpan(
        text: run.text,
        style: TextStyle(
          fontFamily: style.font.family,
          fontSize: LayoutUnits.ptToPx(style.fontSizePt),
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: style.letterSpacingPt == null
              ? null
              : LayoutUnits.ptToPx(style.letterSpacingPt!),
          height: style.lineHeightFactor,
          decoration: style.underline ? TextDecoration.underline : null,
        ),
      ),
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    try {
      final position = painter.getPositionForOffset(
        Offset(
          LayoutUnits.ptToPx((xPt - run.x).clamp(0.0, run.width).toDouble()),
          painter.height / 2,
        ),
      );
      final sourceMap = run.sourceOffsetMap;
      if (sourceMap != null && sourceMap.isNotEmpty) {
        final sourceIndex = position.offset
            .clamp(0, sourceMap.length - 1)
            .toInt();
        return sourceMap[sourceIndex];
      }
      return (start + position.offset).clamp(start, end).toInt();
    } finally {
      painter.dispose();
    }
  }

  static LayoutRect _runRect(LayoutLine line, LayoutRun run) =>
      LayoutRect.fromLTWH(
        run.x,
        line.baseline - run.baselineOffset,
        run.width,
        run.height,
      );

  static bool _contains(LayoutRect rect, double x, double y) =>
      x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;

  static double _distanceTo(LayoutRect rect, double x, double y) {
    final dx = x < rect.left ? rect.left - x : (x > rect.right ? x - rect.right : 0.0);
    final dy = y < rect.top ? rect.top - y : (y > rect.bottom ? y - rect.bottom : 0.0);
    return dx * dx + dy * dy;
  }
}
