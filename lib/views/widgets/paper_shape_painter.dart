import 'package:flutter/material.dart';

import '../../models/floating_element.dart';

/// راسم الأشكال (مثلث/دائرة/مربع/مستطيل/خط/سهم/فاصل) بخطوط سوداء
/// وتعبئة بيضاء — مطابق لبنود SVG في محرك الـ PDF.
///
/// يُستخدم في لوحة المعاينة ([FloatingElementView]) وفي ترسيم الأشكال
/// صوراً عند تصدير Word ([ShapeImageRenderer]).
class PaperShapePainter extends CustomPainter {
  const PaperShapePainter(this.shape, {this.strokeWidth = 2.0});

  final FloatingShapeType shape;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth.clamp(0.5, 12).toDouble()
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = Colors.white;
    final half = paint.strokeWidth / 2;

    switch (shape) {
      case FloatingShapeType.square:
      case FloatingShapeType.rectangle:
        final rect = Offset(half, half) &
            Size(size.width - paint.strokeWidth, size.height - paint.strokeWidth);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, paint);
      case FloatingShapeType.circle:
        final center = Offset(size.width / 2, size.height / 2);
        final radius = (size.shortestSide / 2) - half;
        if (radius > 0) {
          canvas.drawCircle(center, radius, fill);
          canvas.drawCircle(center, radius, paint);
        }
      case FloatingShapeType.triangle:
        final path = Path()
          ..moveTo(size.width / 2, half)
          ..lineTo(half, size.height - half)
          ..lineTo(size.width - half, size.height - half)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, paint);
      case FloatingShapeType.line:
      case FloatingShapeType.divider:
        final y = size.height / 2;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case FloatingShapeType.arrow:
        final y = size.height / 2;
        final head = (paint.strokeWidth * 3).clamp(6.0, 18.0);
        canvas.drawLine(Offset(0, y), Offset(size.width - head, y), paint);
        final path = Path()
          ..moveTo(size.width, y)
          ..lineTo(size.width - head, y - head / 2)
          ..lineTo(size.width - head, y + head / 2)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, paint);
      case FloatingShapeType.textBox:
        // مربعات النص تُرسم كنص لا كشكل.
        break;
    }
  }

  @override
  bool shouldRepaint(PaperShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.strokeWidth != strokeWidth;
}
