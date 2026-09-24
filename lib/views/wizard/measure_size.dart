import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// يقيس حجم ابنه بعد كل تخطيط ويُبلّغ [onChange] عند تغيّره فقط.
///
/// هذه هي لبنة **القياس الديناميكي** لمحرك التقسيم الورقي: كل كتلة (ترويسة
/// أو سؤال كامل) تُبلّغ ارتفاعها الحقيقي، فيُعاد توزيع الكتل على الصفحات
/// دون تخمين. الإبلاغ يتم بعد انتهاء الإطار لتجنّب تعديل الحالة أثناء
/// التخطيط.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = child?.size;
    if (measured == null || measured == _reported) {
      return;
    }
    _reported = measured;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) {
        onChange(measured);
      }
    });
  }
}
