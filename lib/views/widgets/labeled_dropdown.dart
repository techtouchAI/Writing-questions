import 'package:flutter/material.dart';

/// قائمة منسدلة موحّدة الشكل لخيارات محدودة (قيم enum أو نصوص جاهزة).
///
/// [hint] يظهر حين لا قيمة مختارة، و[labelOf] يحوّل كل خيار إلى نصه المعروض.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final String hint;

  /// القيمة المختارة (`null` = لا اختيار فيظهر [hint]).
  final T? value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: Text(hint),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<T>>[
        for (final entry in values)
          DropdownMenuItem<T>(
            value: entry,
            child: Text(labelOf(entry), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (selected) {
        if (selected != null) {
          onChanged(selected);
        }
      },
    );
  }
}
