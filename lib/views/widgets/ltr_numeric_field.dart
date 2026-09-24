import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// حقل رقمي (درجات/إحداثيات/مقاسات) **باتجاه LTR قسري** داخل واجهة RTL.
///
/// يمنع انعكاس الكسور العشرية (1.5 ← 5.1) عند الكتابة والقراءة في واجهة
/// عربية RTL، ويقبل الأرقام والفاصلة العشرية فقط (خطوة 1.2 — Strict
/// Directionality).
class LtrNumericField extends StatelessWidget {
  const LtrNumericField({
    super.key,
    this.controller,
    this.initialValue,
    this.decoration,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.collapsed = false,
    this.textAlign = TextAlign.left,
    this.style,
  }) : assert(controller == null || initialValue == null);

  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration? decoration;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// نمط اللوحة التفاعلية: حقل مسطّح بلا إطار (InputDecoration.collapsed).
  final bool collapsed;
  final bool enabled;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      enabled: enabled,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,،-]')),
      ],
      style: style,
      decoration: collapsed
          ? InputDecoration.collapsed(hintText: hintText)
          : (decoration ??
              InputDecoration(
                hintText: hintText,
                isDense: true,
                border: const OutlineInputBorder(),
              )),
    );
  }
}
