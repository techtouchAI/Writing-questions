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
class CanonicalEditingLayer extends StatefulWidget {
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
  State<CanonicalEditingLayer> createState() => _CanonicalEditingLayerState();
}

class _CanonicalEditingLayerState extends State<CanonicalEditingLayer> {
  Rect? _anchorPx;
  var _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollChanges.addListener(_scheduleMeasurement);
  }

  @override
  void didUpdateWidget(covariant CanonicalEditingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollChanges != widget.scrollChanges) {
      oldWidget.scrollChanges.removeListener(_scheduleMeasurement);
      widget.scrollChanges.addListener(_scheduleMeasurement);
    }
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    widget.scrollChanges.removeListener(_scheduleMeasurement);
    super.dispose();
  }

  void _scheduleMeasurement() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final page = widget.pageKey.currentContext?.findRenderObject();
      final viewport = widget.viewportKey.currentContext?.findRenderObject();
      Rect? next;
      if (page is RenderBox && viewport is RenderBox &&
          page.attached && viewport.attached && page.hasSize && viewport.hasSize) {
        final rect = widget.anchorPt;
        // FittedBox computes its paint transform from child sizes. Reading it
        // during a sibling's performLayout violates Flutter's size ownership
        // contract. Read it AFTER layout instead; never disable that assertion.
        next = MatrixUtils.transformRect(page.getTransformTo(viewport), Rect.fromLTWH(
          LayoutUnits.ptToPx(rect.left), LayoutUnits.ptToPx(rect.top),
          LayoutUnits.ptToPx(rect.width), LayoutUnits.ptToPx(rect.height),
        ));
      }
      if (next != _anchorPx) setState(() => _anchorPx = next);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        _scheduleMeasurement();
        return CustomSingleChildLayout(
          delegate: _EditorPlacement(anchorPx: _anchorPx),
          // Keep the same field element/FocusNode, including while its target
          // page is initially laying out or being replaced after pagination.
          child: IgnorePointer(
            ignoring: _anchorPx == null,
            child: Opacity(opacity: _anchorPx == null ? 0 : 1, child: widget.child),
          ),
        );
      });
}

class _EditorPlacement extends SingleChildLayoutDelegate {
  _EditorPlacement({required this.anchorPx});

  final Rect? anchorPx;

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
    final anchor = anchorPx;
    if (anchor == null) return Offset(inset, inset);
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
