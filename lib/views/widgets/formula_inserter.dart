import 'package:flutter/material.dart';

/// هدف إدراج المعادلات: آخر حقل نصي حاضر التركيز على لوحة الورقة.
///
/// يمسكه محرر الأداة الذكية ([SmartExamToolbar]) ليُدرج مقاطع LaTeX
/// ($...$ / $$...$$) عند مؤشر الكتابة مباشرة داخل الحقل النشط — دون
/// أي حوارات منبثقة (تحرير WYSIWYG متكامل).
class FormulaInserter {
  FormulaInserter();

  /// تحكمات الحقل النشط حالياً (يسجّلها كل حقل عند التركيز).
  TextEditingController? controller;

  /// هل يوجد حقل نصي نشط يستقبل الإدراج؟
  bool get hasTarget => controller != null;

  /// يُدرج [snippet] عند المؤشر (أو في نهاية النص إن لا تحديد صالح).
  void insert(String snippet) {
    final active = controller;
    if (active == null) {
      return;
    }
    final selection = active.selection;
    final text = active.text;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length) {
      final start = selection.start;
      final end = selection.end;
      active.text = text.replaceRange(start, end, snippet);
      active.selection = TextSelection.collapsed(offset: start + snippet.length);
    } else {
      active.text = text + snippet;
      active.selection = TextSelection.collapsed(offset: active.text.length);
    }
  }

  /// يغلّف التحديد الحالي بـ [open] و[close] — يُستعمل لوسم آيات القرآن
  /// بالقوسين المزخرفين `﴿ ... ﴾`.
  ///
  /// إن لم يكن هناك تحديد، يُدرج القوسان ويوضع المؤشر **بينهما** ليكتب
  /// المستخدم الآية مباشرة داخلهما.
  void wrapSelection(String open, String close) {
    final active = controller;
    if (active == null) {
      return;
    }
    final selection = active.selection;
    final text = active.text;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length) {
      final start = selection.start;
      final end = selection.end;
      final selected = text.substring(start, end);
      active.text = text.replaceRange(start, end, '$open$selected$close');
      active.selection = TextSelection.collapsed(
        offset: start + open.length + (selected.isEmpty ? 0 : selected.length + close.length),
      );
      return;
    }
    active.text = '$text$open$close';
    active.selection = TextSelection.collapsed(offset: active.text.length - close.length);
  }
}
