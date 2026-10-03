/// Canonical physical-unit conversions used by the P2 layout layer.
///
/// LayoutEngine and LayoutDocument store every length in points (pt, 1/72 in).
/// Conversion boundaries are explicit:
/// * 1 in = 25.4 mm = 72 pt = 96 Flutter logical px.
/// * 1 pt = 20 Word twips.
/// * A4 = 210 × 297 mm, never an implicit 794-pixel canvas width.
abstract final class LayoutUnits {
  static const double pointsPerInch = 72;
  static const double logicalPixelsPerInch = 96;
  static const double millimetersPerInch = 25.4;
  static const double twipsPerPoint = 20;

  static double mmToPt(double millimeters) =>
      millimeters * pointsPerInch / millimetersPerInch;

  static double ptToMm(double points) =>
      points * millimetersPerInch / pointsPerInch;

  static double pxToPt(double logicalPixels) =>
      logicalPixels * pointsPerInch / logicalPixelsPerInch;

  static double ptToPx(double points) =>
      points * logicalPixelsPerInch / pointsPerInch;

  static double twipsToPt(double twips) => twips / twipsPerPoint;

  static double ptToTwips(double points) => points * twipsPerPoint;

  static const LayoutSize a4 = LayoutSize(
    width: 210 * pointsPerInch / millimetersPerInch,
    height: 297 * pointsPerInch / millimetersPerInch,
  );
}

/// Renderer-independent point geometry. LayoutDocument deliberately avoids
/// `dart:ui`, Flutter, and package:pdf geometry types.
class LayoutSize {
  const LayoutSize({required this.width, required this.height});

  final double width;
  final double height;
}

class LayoutOffset {
  const LayoutOffset(this.dx, this.dy);

  final double dx;
  final double dy;
}

class LayoutRect {
  const LayoutRect.fromLTWH(this.left, this.top, this.width, this.height);

  const LayoutRect.fromLTRB(double left, double top, double right, double bottom)
      : left = left,
        top = top,
        width = right - left,
        height = bottom - top;

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  LayoutOffset get topLeft => LayoutOffset(left, top);
  bool get isEmpty => width <= 0 || height <= 0;

  LayoutRect translate(double dx, double dy) =>
      LayoutRect.fromLTWH(left + dx, top + dy, width, height);

  LayoutRect inflate(double delta) => LayoutRect.fromLTWH(
        left - delta,
        top - delta,
        width + 2 * delta,
        height + 2 * delta,
      );

  @override
  String toString() => 'LayoutRect($left, $top, $width, $height)';
}
