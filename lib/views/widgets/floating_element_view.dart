import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exam_canvas_geometry.dart';
import '../../models/floating_element.dart';
import '../../models/paper_font.dart';
import '../../models/subject_layout.dart';
import '../../models/tex_content.dart';
import '../wizard/paper_styles.dart';
import 'paper_shape_painter.dart';
import 'safe_math_tex.dart';
import 'tex_text.dart';

/// عرض عنصر عائم (صورة/شكل/مربع نص) فوق لوحة الورقة التفاعلية.
///
/// الأشكال تُرسم متجهةً (CustomPaint) تماماً كما تُرسم SVG في الـ PDF،
/// والصور تُعرض من البايتات المخزنة ([FloatingElement.bytes])، ومربعات
/// النص تعرض نصها بتنسيقها — والتدوير حول المركز كما في الطباعة.
class FloatingElementView extends StatelessWidget {
  const FloatingElementView({
    super.key,
    required this.element,
    this.defaultFont,
    this.fontScale = 1.0,
    this.heightScale = 1.0,
  });

  final FloatingElement element;

  /// خط الورقة الافتراضي (لمربعات النص).
  final PaperFont? defaultFont;

  /// معاملا القياس العامّان من إعدادات الورقة (لنص مربع النص).
  final double fontScale;
  final double heightScale;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    switch (element.type) {
      case FloatingElementType.image:
        content = _buildImage();
      case FloatingElementType.shape:
        content = _buildShape();
      case FloatingElementType.formula:
        content = _buildFormula();
    }
    if (element.rotationDegrees == 0) {
      return content;
    }
    return Transform.rotate(
      angle: element.rotationDegrees * math.pi / 180,
      child: content,
    );
  }

  Widget _buildImage() {
    final bytes = element.bytes;
    if (bytes == null) {
      return const ColoredBox(color: Color(0xFFEEEEEE));
    }
    return Image.memory(bytes, fit: BoxFit.contain);
  }

  Widget _buildShape() {
    final shape = element.shape ?? FloatingShapeType.square;
    if (shape == FloatingShapeType.textBox) {
      return _buildTextBox();
    }
    return CustomPaint(
      painter: PaperShapePainter(shape, strokeWidth: element.strokeWidth),
    );
  }

  /// معادلة حرة: تُرسم معادلةً (Math) بحجم أساس ثابت ثم تُقاس داخل الصندوق
  /// بنسبة ثابتة — فتكبير الصندوق يكبّر المعادلة كما في PDF و Word.
  Widget _buildFormula() {
    return Container(
      decoration: element.framed
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF111827), width: 1),
            )
          : null,
      padding: const EdgeInsets.all(2),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SafeMathTex(
          element.label,
          textStyle: const TextStyle(
            fontSize: ExamCanvasGeometry.formulaBaseFontSize,
          ),
        ),
      ),
    );
  }

  Widget _buildTextBox() {
    final style = PaperStyles.resolve(
      PaperStyles.body(SubjectLayoutTemplate.generic),
      element.textStyle,
      defaultFont: defaultFont ?? PaperFont.naskh,
      fontScale: fontScale,
      heightScale: heightScale,
    );
    final text = element.label.trim().isEmpty ? 'مربع نص...' : element.label;
    final isEmpty = element.label.trim().isEmpty;
    return Container(
      decoration: element.framed
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF111827), width: 1),
            )
          : null,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.topRight,
      // الصيغ (`$...$`) في مربع النص تُعرض معادلاتٍ كاملة لا أكواداً خامة،
      // بنفس ودجت النص العلمي المستخدم على الورقة ([TexText]).
      child: isEmpty || !TexContent.containsMath(text)
          ? Text(
              text,
              style: isEmpty ? PaperStyles.hint(style) : style,
              textAlign: PaperStyles.toTextAlign(element.textStyle.align),
            )
          : TexText(
              text,
              style: style,
              textAlign: PaperStyles.toTextAlign(element.textStyle.align),
            ),
    );
  }
}
