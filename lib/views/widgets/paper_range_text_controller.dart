import 'package:flutter/material.dart';

import '../../layout/visual/visual_content.dart';

/// [TextEditingController] يرسم **تنسيق النطاقات المخزَّن** داخل حقل التحرير
/// نفسه، بدل أن يبقى التنسيق في الطباعة وحدها.
///
/// لماذا في المتحكم؟ لأن `EditableText` يبني ما يرسمه من
/// [buildTextSpan] وحده؛ فأي تجميل بعد الرسم (طبقة فوق الحقل) يفقد الإيماءات
/// والمؤشر والتحديد. هنا يبقى المصدر هو `controller.text` نفسه، وتُضاف إليه
/// الأنماط فقط، فلا يوجد نصّ ثانٍ ولا إحداثيات موازية.
///
/// القيود المعلنة:
///  * التنسيق **مقاطع** بين حدود النطاقات (كما يفعل المنطق والطباعة)، وليس
///    تداخل أنماط داخل المحرف نفسه.
///  * منطقة التركيب (IME) تُترك لـ[TextEditingController] الأصلي: رسمها
///    بخطّ تسطير خاص سلوك إدخال لا يجوز تعطيله.
class PaperRangeTextEditingController extends TextEditingController {
  PaperRangeTextEditingController({super.text});

  List<RunStyle> _runs = const <RunStyle>[];

  /// يحدّث الأنماط ويعيد `true` إن تغيّرت فعلاً (فلا إعادة رسم بلا داعٍ).
  bool setRuns(List<RunStyle> runs) {
    if (_same(runs, _runs)) {
      return false;
    }
    _runs = List<RunStyle>.unmodifiable(runs);
    return true;
  }

  List<RunStyle> get runs => _runs;

  static bool _same(List<RunStyle> a, List<RunStyle> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = value.composing;
    if (withComposing && composing.isValid && !composing.isCollapsed) {
      // أثناء التركيب لا يُعاد تشكيل النصّ: يبقى خطّ التركيب الأصلي.
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final base = style ?? const TextStyle();
    final text = this.text;
    if (_runs.isEmpty || text.isEmpty) {
      return TextSpan(style: base, text: text);
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final run in _runs) {
      final start = run.start.clamp(0, text.length).toInt();
      final end = run.end.clamp(start, text.length).toInt();
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      if (end > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, end),
            style: _merged(base, run.style),
          ),
        );
      }
      if (end > cursor) cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: base, children: spans);
  }

  /// يدمج خصائص النطاق فوق النمط الأساسي. الخاصية الغائبة في النطاق (`null`)
  /// تترك قيمة النمط الأساسي كما هي — ومنها الخاصية التي تُطفأ صراحةً
  /// (`bold: false`) فتعود إلى `normal` ولا ترث تعريض العنصر.
  static TextStyle _merged(TextStyle base, VisualRunStyle run) {
    return base.copyWith(
      fontWeight: run.bold == null
          ? null
          : (run.bold! ? FontWeight.bold : FontWeight.normal),
      fontStyle: run.italic == null
          ? null
          : (run.italic! ? FontStyle.italic : FontStyle.normal),
      decoration: run.underline == null
          ? null
          : (run.underline! ? TextDecoration.underline : TextDecoration.none),
      color: run.colorArgb == null ? null : Color(run.colorArgb!),
    );
  }
}

/// نطاق نمط داخل نصّ الحقل (إزاحة مصدرية بنفس وحدات [TextSelection]).
@immutable
class RunStyle {
  const RunStyle({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final VisualRunStyle style;

  @override
  bool operator ==(Object other) =>
      other is RunStyle &&
      other.start == start &&
      other.end == end &&
      other.style.bold == style.bold &&
      other.style.italic == style.italic &&
      other.style.underline == style.underline &&
      other.style.colorArgb == style.colorArgb;

  @override
  int get hashCode => Object.hash(
        start,
        end,
        style.bold,
        style.italic,
        style.underline,
        style.colorArgb,
      );
}
