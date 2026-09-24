import 'package:pdf/widgets.dart' as pw;

import '../models/floating_element.dart';
import 'latex/latex_svg_renderer.dart';

/// تحويل العناصر العائمة من لوحة الـ WYSIWYG إلى عناصر `pw` (خطوة 5).
///
/// - الصور: `pw.MemoryImage` بنفس البايتات المعروضة على اللوحة.
/// - الأشكال (مثلث/دائرة/مربع): SVG متجه مولَّد بنفس هندسة راسم اللوحة
///   ويُرسم عبر `pw.SvgImage` — نفس الموضع والمقاس تماماً.
/// - أي مصدر `svg` مخزَّن مع العنصر يُرسم مباشرة كما هو.
abstract final class FloatingElementsPdf {
  /// يبني محتوى عنصر عائم بمقاس [widthPt]×[heightPt] نقاط PDF.
  static pw.Widget build(
    FloatingElement element, {
    required double widthPt,
    required double heightPt,
  }) {
    switch (element.type) {
      case FloatingElementType.image:
        final bytes = element.bytes;
        if (bytes == null) {
          return pw.SizedBox(width: widthPt, height: heightPt);
        }
        return pw.SizedBox(
          width: widthPt,
          height: heightPt,
          child: pw.Image(
            pw.MemoryImage(bytes),
            fit: pw.BoxFit.contain,
          ),
        );
      case FloatingElementType.shape:
        final svg = element.svgSource ??
            shapeToSvg(
              element.shape ?? FloatingShapeType.square,
              element.width,
              element.height,
            );
        return pw.SizedBox(
          width: widthPt,
          height: heightPt,
          child: pw.SvgImage(svg: svg, fit: pw.BoxFit.fill),
        );
    }
  }

  /// يولد SVG لشكل هندسي أساسي بنفس بنية `_ShapePainter` في الواجهة:
  /// خطوط سوداء (2 بكسل) وتعبئة بيضاء فوق خلفية شفافة.
  static String shapeToSvg(
    FloatingShapeType shape,
    double width,
    double height,
  ) {
    const stroke = 2.0;
    final buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
      ..write('width="$width" height="$height" ')
      ..write('viewBox="0 0 $width $height">');

    void closeShape(String geometry) {
      buffer.write(
        '<$geometry fill="#FFFFFF" stroke="#111827" stroke-width="$stroke" '
        'stroke-linejoin="round"/>',
      );
    }

    switch (shape) {
      case FloatingShapeType.square:
        closeShape(
          'rect x="${stroke / 2}" y="${stroke / 2}" '
          'width="${width - stroke}" height="${height - stroke}"',
        );
      case FloatingShapeType.circle:
        final cx = width / 2;
        final cy = height / 2;
        final radius = (width < height ? width : height) / 2 - stroke;
        closeShape('circle cx="$cx" cy="$cy" r="$radius"');
      case FloatingShapeType.triangle:
        closeShape(
          'path d="M${width / 2} ${stroke / 2} '
          'L${stroke / 2} ${height - stroke / 2} '
          'L${width - stroke / 2} ${height - stroke / 2} Z"',
        );
    }
    buffer.write('</svg>');
    return buffer.toString();
  }

  /// SVG جاهز لصيغة LaTeX (خطوة 5.3) — يُعاد استخدام نفس المحوّل المتجه.
  static LatexSvg? formulaToSvg(String latex, {double fontSize = 10.5}) {
    return LatexSvgRenderer.tryToSvg(latex, fontSize: fontSize);
  }
}
