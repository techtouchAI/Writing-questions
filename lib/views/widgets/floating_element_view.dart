import 'package:flutter/material.dart';

import '../../models/floating_element.dart';

/// عرض عنصر عائم (صورة/شكل هندسي) فوق لوحة الورقة التفاعلية.
///
/// الأشكال تُرسم متجهةً (CustomPaint) تماماً كما تُرسم SVG في الـ PDF،
/// والصور تُعرض من البايتات المخزنة ([FloatingElement.bytes]).
class FloatingElementView extends StatelessWidget {
  const FloatingElementView({super.key, required this.element});

  final FloatingElement element;

  @override
  Widget build(BuildContext context) {
    switch (element.type) {
      case FloatingElementType.image:
        final bytes = element.bytes;
        if (bytes == null) {
          return const ColoredBox(color: Color(0xFFEEEEEE));
        }
        return Image.memory(bytes, fit: BoxFit.contain);
      case FloatingElementType.shape:
        return CustomPaint(
          painter: _ShapePainter(element.shape ?? FloatingShapeType.square),
        );
    }
  }
}

/// راسم الأشكال الهندسية الأساسية (مثلث/دائرة/مربع) بخطوط سوداء وتعبئة بيضاء
/// — مطابق لبنود SVG في محرك الـ PDF.
class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape);

  final FloatingShapeType shape;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()..color = Colors.white;

    switch (shape) {
      case FloatingShapeType.square:
        final rect = const Offset(2, 2) & Size(size.width - 4, size.height - 4);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, paint);
      case FloatingShapeType.circle:
        final center = Offset(size.width / 2, size.height / 2);
        final radius = (size.shortestSide / 2) - 2;
        canvas.drawCircle(center, radius, fill);
        canvas.drawCircle(center, radius, paint);
      case FloatingShapeType.triangle:
        final path = Path()
          ..moveTo(size.width / 2, 2)
          ..lineTo(2, size.height - 2)
          ..lineTo(size.width - 2, size.height - 2)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) => oldDelegate.shape != shape;
}
