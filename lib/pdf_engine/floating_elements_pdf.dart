import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../models/floating_element.dart';
import '../models/paper_font.dart';
import 'exam_fonts.dart';
import 'latex/latex_svg_renderer.dart';
import 'paper_style_resolver.dart';

/// تحويل العناصر العائمة من لوحة الـ WYSIWYG إلى عناصر `pw`.
///
/// - الصور: `pw.MemoryImage` بنفس البايتات المعروضة على اللوحة.
/// - الأشكال: SVG متجه مولَّد بنفس هندسة راسم اللوحة ويُرسم عبر
///   `pw.SvgImage` — نفس الموضع والمقاس والسماكة تماماً.
/// - مربعات النص: نص بخط الورقة وتنسيقه، مع إطار اختياري.
/// - التدوير: `pw.Transform.rotateBox` حول المركز (نفس زاوية اللوحة).
/// - أي مصدر `svg` مخزَّن مع العنصر يُرسم مباشرة كما هو.
abstract final class FloatingElementsPdf {
  /// يبني محتوى عنصر عائم بمقاس [widthPt]×[heightPt] نقاط PDF.
  static pw.Widget build(
    FloatingElement element, {
    required double widthPt,
    required double heightPt,
    ExamFonts? fonts,
    PaperFont defaultFont = PaperFont.naskh,
  }) {
    final pw.Widget content;
    switch (element.type) {
      case FloatingElementType.image:
        content = _buildImage(element, widthPt, heightPt);
      case FloatingElementType.shape:
        content = _buildShape(
          element,
          widthPt: widthPt,
          heightPt: heightPt,
          fonts: fonts,
          defaultFont: defaultFont,
        );
    }
    if (element.rotationDegrees == 0) {
      return content;
    }
    return pw.Transform.rotateBox(
      angle: element.rotationDegrees * math.pi / 180,
      child: content,
    );
  }

  static pw.Widget _buildImage(FloatingElement element, double widthPt, double heightPt) {
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
  }

  static pw.Widget _buildShape(
    FloatingElement element, {
    required double widthPt,
    required double heightPt,
    required ExamFonts? fonts,
    required PaperFont defaultFont,
  }) {
    final shape = element.shape ?? FloatingShapeType.square;
    if (shape == FloatingShapeType.textBox) {
      return _buildTextBox(element, widthPt, heightPt, fonts, defaultFont);
    }
    final svg = element.svgSource ??
        shapeToSvg(
          shape,
          element.width,
          element.height,
          strokeWidth: element.strokeWidth,
        );
    return pw.SizedBox(
      width: widthPt,
      height: heightPt,
      child: pw.SvgImage(svg: svg, fit: pw.BoxFit.fill),
    );
  }

  static pw.Widget _buildTextBox(
    FloatingElement element,
    double widthPt,
    double heightPt,
    ExamFonts? fonts,
    PaperFont defaultFont,
  ) {
    final style = PaperStyleResolver.apply(
      pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
      element.textStyle,
      fonts: fonts ?? _fallbackFonts,
      defaultFont: element.textStyle.font ?? defaultFont,
    );
    final text = element.label.trim().isEmpty ? ' ' : element.label;
    return pw.SizedBox(
      width: widthPt,
      height: heightPt,
      child: pw.Container(
        decoration: element.framed
            ? pw.BoxDecoration(border: pw.Border.all(width: 1))
            : null,
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: style,
          textAlign: PaperStyleResolver.toPdfAlign(element.textStyle.align) ??
              pw.TextAlign.start,
        ),
      ),
    );
  }

  /// يولد SVG لشكل بنفس بنية راسم اللوحة: خطوط سوداء وتعبئة بيضاء.
  static String shapeToSvg(
    FloatingShapeType shape,
    double width,
    double height, {
    double strokeWidth = 2.0,
  }) {
    final stroke = strokeWidth.clamp(0.5, 12).toDouble();
    final buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
      ..write('width="$width" height="$height" ')
      ..write('viewBox="0 0 $width $height">');

    void shapeTag(String geometry, {bool filled = true}) {
      buffer.write(
        '<$geometry fill="${filled ? '#FFFFFF' : 'none'}" stroke="#111827" '
        'stroke-width="$stroke" stroke-linejoin="round" stroke-linecap="round"/>',
      );
    }

    switch (shape) {
      case FloatingShapeType.square:
      case FloatingShapeType.rectangle:
        shapeTag(
          'rect x="${stroke / 2}" y="${stroke / 2}" '
          'width="${width - stroke}" height="${height - stroke}"',
        );
      case FloatingShapeType.circle:
        final cx = width / 2;
        final cy = height / 2;
        final radius = (width < height ? width : height) / 2 - stroke / 2;
        shapeTag('circle cx="$cx" cy="$cy" r="$radius"');
      case FloatingShapeType.triangle:
        shapeTag(
          'path d="M${width / 2} ${stroke / 2} '
          'L${stroke / 2} ${height - stroke / 2} '
          'L${width - stroke / 2} ${height - stroke / 2} Z"',
        );
      case FloatingShapeType.line:
      case FloatingShapeType.divider:
        final y = height / 2;
        buffer.write(
          '<line x1="0" y1="$y" x2="$width" y2="$y" stroke="#111827" '
          'stroke-width="$stroke" stroke-linecap="round"/>',
        );
      case FloatingShapeType.arrow:
        final y = height / 2;
        final head = (stroke * 3).clamp(6.0, 18.0);
        buffer.write(
          '<line x1="0" y1="$y" x2="${width - head}" y2="$y" stroke="#111827" '
          'stroke-width="$stroke" stroke-linecap="round"/>',
        );
        shapeTag(
          'path d="M$width $y L${width - head} ${y - head / 2} '
          'L${width - head} ${y + head / 2} Z"',
        );
      case FloatingShapeType.textBox:
        // مربعات النص تُرسم نصاً (انظر _buildTextBox) لا SVG.
        shapeTag(
          'rect x="${stroke / 2}" y="${stroke / 2}" '
          'width="${width - stroke}" height="${height - stroke}"',
          filled: false,
        );
    }
    buffer.write('</svg>');
    return buffer.toString();
  }

  /// SVG جاهز لصيغة LaTeX — يُعاد استخدام نفس المحوّل المتجه.
  static LatexSvg? formulaToSvg(String latex, {double fontSize = 10.5}) {
    return LatexSvgRenderer.tryToSvg(latex, fontSize: fontSize);
  }

  /// خطوط احتياطية عند غياب المحمّلة (تُستخدم خطوط PDF الأربعة عشر فقط
  /// كنص بديل؛ الحالة الطبيعية تمرّر [fonts] دائماً).
  static ExamFonts get _fallbackFonts => ExamFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
}
