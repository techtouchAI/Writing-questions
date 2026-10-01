import 'package:flutter/material.dart';

/// حقل نص حر مع قائمة اقتراحات جاهزة: يكتب المدرس ما يشاء، أو يختار من القائمة
/// المنسدلة في طرف الحقل فيُملأ الحقل بالقيمة المختارة.
///
/// يُستعمل لحقول الترويسة التي يجمع إدخالها بين «الكتابة» و«الاختيار» (العام
/// الدراسي، نوع الامتحان، الوقت). [hint] إلزامي: لكل حقل إدخال تلميح إرشادي.
class SuggestionTextField extends StatelessWidget {
  const SuggestionTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: PopupMenuButton<String>(
          tooltip: 'اختيار من القائمة',
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: (value) {
            controller.text = value;
            controller.selection = TextSelection.collapsed(offset: value.length);
            onChanged(value);
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            for (final suggestion in suggestions)
              PopupMenuItem<String>(value: suggestion, child: Text(suggestion)),
          ],
        ),
      ),
    );
  }
}
