import 'package:flutter/material.dart';

import '../../models/tex_content.dart';
import 'mixed_content_editor.dart';
import 'tex_text.dart';

/// حقل محتوى غني: يعرض النص **بشكله النهائي** (وال معادلات مرسومة مرئية)،
/// ويفتح عند النقر محرر المحتوى المختلط ([MixedContentEditor]) الذي يمزج
/// النص والمعادلات في الحقل نفسه.
///
/// يُستعمل في خطوات المعالج بدل حقول النص المجرّدة، فيبقى كل حقل محتوى
/// قابلاً لتحرير النص والمعادلات معاً دون أن يرى المستخدم كود LaTeX إطلاقاً.
class RichContentField extends StatelessWidget {
  const RichContentField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'انقر للكتابة أو لإضافة معادلة...',
    this.enabled = true,
    this.title = 'تحرير المحتوى',
    this.minHeight = 48,
  });

  /// المصدر المخزَّن (نص، وقد يحوي `$معادلة$`).
  final String value;

  final ValueChanged<String> onChanged;

  /// وصف الحقل (يظهر أعلى الإطار).
  final String? label;

  /// نص التلميح حين يكون الحقل فارغاً.
  final String hint;

  final bool enabled;

  /// عنوان نافذة التحرير.
  final String title;

  final double minHeight;

  Future<void> _edit(BuildContext context) async {
    final result = await MixedContentEditor.show(
      context,
      source: value,
      title: title,
    );
    if (result != null && result != value) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMath = TexContent.containsMath(value);
    final isEmpty = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
        ],
        InkWell(
          onTap: enabled ? () => _edit(context) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: enabled
                    ? colorScheme.outlineVariant
                    : colorScheme.outlineVariant.withOpacity(0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: isEmpty
                      ? Text(
                          hint,
                          style: TextStyle(
                            color: Theme.of(context).disabledColor,
                            fontSize: 13,
                          ),
                        )
                      : TexText(
                          value,
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: hasMath ? 'تحرير النص والمعادلات' : 'تحرير المحتوى',
                  child: Icon(
                    hasMath ? Icons.functions : Icons.edit_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
