import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../layout/canonical/layout_units.dart';

/// Native-size editing chrome, outside the printable page's render subtree.
///
/// [anchorPt] MUST come from the current canonical page, not from measuring an
/// editor. Only the page's actual render transform converts it to viewport
/// coordinates. No height or wrapping measurement flows back into pagination.
///
/// Put this in a Positioned.fill sibling of the paper scroll views. Keep one
/// instance/child at that location while changing [pageKey] for continuations;
/// moving the anchor must not reparent a focused TextField or its IME session.
/// The caller supplies a scrollable editor, existing controllers and handlers.
class CanonicalEditingLayer extends StatelessWidget {
  const CanonicalEditingLayer({
    super.key,
    required this.viewportKey,
    required this.pageKey,
    required this.anchorPt,
    required this.scrollChanges,
    required this.child,
  });

  final GlobalKey viewportKey;
  final GlobalKey pageKey;
  final LayoutRect anchorPt;
  final Listenable scrollChanges;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
        delegate: _EditorPlacement(
          viewportKey: viewportKey,
          pageKey: pageKey,
          anchorPt: anchorPt,
          scrollChanges: scrollChanges,
        ),
        child: child,
      );
}

class _EditorPlacement extends SingleChildLayoutDelegate {
  _EditorPlacement({
    required this.viewportKey,
    required this.pageKey,
    required this.anchorPt,
    required Listenable scrollChanges,
  }) : super(relayout: scrollChanges);

  final GlobalKey viewportKey;
  final GlobalKey pageKey;
  final LayoutRect anchorPt;

  double _inset(Size size) => math.min(8.0, math.min(size.width, size.height) / 2);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final inset = _inset(size);
    final width = math.min(560.0, math.max(0.0, size.width - 2 * inset));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.min(360.0, math.max(0.0, size.height - 2 * inset)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final inset = _inset(size);
    final page = pageKey.currentContext?.findRenderObject();
    final viewport = viewportKey.currentContext?.findRenderObject();
    // Before a target exists, do not invent another page/field layout. The
    // native editor remains mounted; the next real layout resolves its anchor.
    if (page is! RenderBox || viewport is! RenderBox || !page.hasSize) {
      return Offset(inset, inset);
    }
    final sourceRect = Rect.fromLTWH(
      LayoutUnits.ptToPx(anchorPt.left),
      LayoutUnits.ptToPx(anchorPt.top),
      LayoutUnits.ptToPx(anchorPt.width),
      LayoutUnits.ptToPx(anchorPt.height),
    );
    final anchor = MatrixUtils.transformRect(page.getTransformTo(viewport), sourceRect);
    final maxLeft = math.max(inset, size.width - inset - childSize.width);
    final maxTop = math.max(inset, size.height - inset - childSize.height);
    final below = anchor.bottom + 8;
    final top = below + childSize.height <= size.height - inset
        ? below
        : anchor.top - childSize.height - 8;
    return Offset(
      (anchor.right - childSize.width).clamp(inset, maxLeft).toDouble(),
      top.clamp(inset, maxTop).toDouble(),
    );
  }

  @override
  // A parent rebuild can change the page's zoom/transform without replacing
  // either key or the canonical rectangle. Read that actual transform again.
  bool shouldRelayout(covariant _EditorPlacement oldDelegate) => true;
}
