import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../models/exam_canvas_geometry.dart';
import '../models/floating_element.dart';
import '../models/equation_model.dart';
import '../models/paper_font.dart';
import '../models/tex_content.dart';
import 'exam_fonts.dart';
import 'paper_style_resolver.dart';
import 'pdf_math_rasters.dart';

/// تحويل العناصر العائمة من لوحة الـ WYSIWYG إلى عناصر `pw`.
///
/// - الصور: `pw.MemoryImage` بنفس البايتات المعروضة على اللوحة.
/// - الأشكال: SVG متجه مولَّد بنفس هندسة راسم اللوحة ويُرسم عبر
///   `pw.SvgImage` — نفس الموضع والمقاس والسماكة تماماً.
/// - مربعات النص: نص بخط الورقة وتنسيقه، مع إطار اختياري.
/// - التدوير: `pw.Transform.rotateBox` حول المركز (نفس زاوية اللوحة).
/// - أي مصدر `svg` مخزَّن مع العنصر يُرسم مباشرة كما هو.
/// - المعادلة الحرة ونص المربع: لقطات من محرك العرض نفسه عبر [PdfMathRasters]
///   (نفس صورة المعادلة في المتن)، فلا محرك رياضيات ثانياً في الملف.
abstract final class FloatingElementsPdf {
  /// يبني محتوى عنصر عائم بمقاس [widthPt]×[heightPt] نقاط PDF.
  static pw.Widget build(
    FloatingElement element, {
    required double widthPt,
    required double heightPt,
    ExamFonts? fonts,
    PaperFont defaultFont = PaperFont.naskh,
    double fontScale = 1.0,
    double heightScale = 1.0,
    PdfMathRasters? mathRasters,
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
          fontScale: fontScale,
          heightScale: heightScale,
          mathRasters: mathRasters,
        );
      case FloatingElementType.formula:
        content = _buildFormula(element, widthPt, heightPt, mathRasters);
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
    double fontScale = 1.0,
    double heightScale = 1.0,
    PdfMathRasters? mathRasters,
  }) {
    final shape = element.shape ?? FloatingShapeType.square;
    if (shape == FloatingShapeType.textBox) {
      return _buildTextBox(
        element,
        widthPt,
        heightPt,
        fonts,
        defaultFont,
        fontScale: fontScale,
        heightScale: heightScale,
        mathRasters: mathRasters,
      );
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
    PaperFont defaultFont, {
    double fontScale = 1.0,
    double heightScale = 1.0,
    PdfMathRasters? mathRasters,
  }) {
    final style = PaperStyleResolver.apply(
      const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
      element.textStyle,
      fonts: fonts ?? _fallbackFonts,
      defaultFont: element.textStyle.font ?? defaultFont,
      fontScale: fontScale,
      heightScale: heightScale,
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
        child: _textWithMath(
          text,
          style,
          PaperStyleResolver.toPdfAlign(element.textStyle.align) ??
              pw.TextAlign.start,
          mathRasters,
        ),
      ),
    );
  }

  /// نص مربع النص مع رسم صيغ LaTeX (`$...$`) لقطاتٍ من محرك العرض — بنفس
  /// منطق `_renderText` في محرك الصفحات، فلا تظهر الأكواد الخامة في المربع.
  static pw.Widget _textWithMath(
    String text,
    pw.TextStyle style,
    pw.TextAlign align,
    PdfMathRasters? mathRasters,
  ) {
    final segments = TexContent.split(text);
    if (!segments.any((segment) => segment.isMath)) {
      return pw.Text(text, style: style, textAlign: align);
    }
    final fontSize = style.fontSize ?? 10.5;
    final rows = <pw.Widget>[];
    var inline = <pw.Widget>[];

    void flushInline() {
      if (inline.isEmpty) {
        return;
      }
      rows.add(
        pw.Wrap(
          spacing: 1,
          runSpacing: 2,
          alignment: _wrapAlign(align),
          crossAxisAlignment: pw.WrapCrossAlignment.center,
          children: List<pw.Widget>.of(inline),
        ),
      );
      inline = <pw.Widget>[];
    }

    for (final segment in segments) {
      if (!segment.isMath) {
        if (segment.text.isNotEmpty) {
          inline.add(pw.Text(segment.text, style: style, textAlign: align));
        }
        continue;
      }
      final raster = mathRasters?.lookup(segment.text, fontSize);
      if (raster == null) {
        inline.add(
          pw.Text(EquationModel.readableText(segment.text), style: style, textAlign: align),
        );
        continue;
      }
      final image = pw.Image(
        pw.MemoryImage(raster.pngBytes),
        width: raster.widthPt,
        height: raster.heightPt,
        fit: pw.BoxFit.fill,
      );
      if (segment.isBlock) {
        flushInline();
        rows.add(pw.Center(child: image));
      } else {
        inline.add(image);
      }
    }
    flushInline();
    return pw.Column(
      crossAxisAlignment: _columnAlign(align),
      mainAxisSize: pw.MainAxisSize.min,
      children: rows,
    );
  }

  static pw.WrapAlignment _wrapAlign(pw.TextAlign align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.WrapAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.WrapAlignment.end;
      default:
        return pw.WrapAlignment.start;
    }
  }

  static pw.CrossAxisAlignment _columnAlign(pw.TextAlign align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.CrossAxisAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
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
      // overflow=visible: a centred stroke's outer half lies on the viewBox edge
      // and must not be clipped (clipping halved the frame weight in the probe).
      ..write('viewBox="0 0 $width $height" overflow="visible">');

    void shapeTag(String geometry, {bool filled = true}) {
      buffer.write(
        '<$geometry fill="${filled ? '#FFFFFF' : 'none'}" stroke="#111827" '
        'stroke-width="$stroke" stroke-linejoin="round" stroke-linecap="round"/>',
      );
    }

    switch (shape) {
      case FloatingShapeType.square:
      case FloatingShapeType.rectangle:
        // Centred on the layout box, as the preview draws it (drawRect, stroke
        // centred on the edge). An inset of stroke/2 moved the PDF outline
        // inward by about one pixel per side (C6 measurement).
        shapeTag('rect x="0" y="0" width="$width" height="$height"');
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

  /// معادلة حرة: تُلتقط بمحرك العرض نفسه (كمتن الورقة) ثم تُقاس داخل الصندوق
  /// بلا تشويه — فإن غابت اللقطة كُتبت الصيغة نصاً بديلاً مقروءاً.
  static pw.Widget _buildFormula(
    FloatingElement element,
    double widthPt,
    double heightPt,
    PdfMathRasters? mathRasters,
  ) {
    final rendered = mathRasters?.lookup(
      element.label,
      ExamCanvasGeometry.formulaBaseFontSize,
    );
    return pw.SizedBox(
      width: widthPt,
      height: heightPt,
      child: pw.Container(
        decoration: element.framed
            ? pw.BoxDecoration(border: pw.Border.all(width: 1))
            : null,
        padding: const pw.EdgeInsets.all(2),
        child: rendered == null
            ? pw.Center(
                child: pw.Text(
                  // معادلة قديمة تعذّر ترسيمها: نص رياضي مقروء بلا كود.
                  EquationModel.readableText(element.label),
                  style: const pw.TextStyle(fontSize: 10.5),
                  textAlign: pw.TextAlign.center,
                ),
              )
            // بلا SizedBox داخلي ثابت: الحشوة والإطار يحيطان بالمعادلة
            // فعلاً فتُملاء المساحة المتاحة بلا تجاوز ولا قصّ (اللقطة صورة
            // فتُوضع بـ contain كما كانت، بلا تمطيط ولا تغيير مقياس يدوي).
            : pw.Center(
                child: pw.Image(
                  pw.MemoryImage(rendered.pngBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
      ),
    );
  }

  /// خطوط احتياطية عند غياب المحمّلة (تُستخدم خطوط PDF الأربعة عشر فقط
  /// كنص بديل؛ الحالة الطبيعية تمرّر [fonts] دائماً).
  static ExamFonts get _fallbackFonts => ExamFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
}
