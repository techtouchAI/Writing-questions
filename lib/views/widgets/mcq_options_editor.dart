import 'package:flutter/material.dart';

import '../../models/question_option.dart';

class McqOptionsEditor extends StatefulWidget {
  const McqOptionsEditor({
    super.key,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final List<QuestionOption> options;
  final ValueChanged<List<QuestionOption>> onChanged;
  final bool enabled;

  @override
  State<McqOptionsEditor> createState() => _McqOptionsEditorState();
}

class _McqOptionsEditorState extends State<McqOptionsEditor> {
  late List<QuestionOption> _localOptions;

  @override
  void initState() {
    super.initState();
    _localOptions = _copyOrCreateDefaults(widget.options);
  }

  @override
  void didUpdateWidget(covariant McqOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameOptions(widget.options, oldWidget.options)) {
      _localOptions = _copyOrCreateDefaults(widget.options);
    }
  }

  void _addOption() {
    setState(() {
      _localOptions = <QuestionOption>[
        ..._localOptions,
        QuestionOption(text: ''),
      ];
    });
    _notifyChanged();
  }

  void _removeOption(int index) {
    // لا حد أدنى للخيارات: تُحذف كلها إن أراد المدرس.
    if (index < 0 || index >= _localOptions.length) {
      return;
    }
    setState(() {
      _localOptions = <QuestionOption>[
        ..._localOptions.sublist(0, index),
        ..._localOptions.sublist(index + 1),
      ];
    });
    _notifyChanged();
  }

  void _updateOption(int index, QuestionOption option) {
    setState(() {
      _localOptions = <QuestionOption>[
        ..._localOptions.sublist(0, index),
        option,
        ..._localOptions.sublist(index + 1),
      ];
    });
    _notifyChanged();
  }

  /// فارغ = تلقائي (`null`)، `-` = إخفاء (`''`)، وإلا النص المخصص.
  static String? _normalizeLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed == '-' ? '' : trimmed;
  }

  void _notifyChanged() {
    widget.onChanged(
      _localOptions.map((option) => option.copyWith()).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            const Text(
              'خيارات الإجابة (حدد الإجابة الصحيحة):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: widget.enabled ? _addOption : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة خيار'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List<Widget>.generate(_localOptions.length, (index) {
          final option = _localOptions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: 'تحديد كإجابة صحيحة',
                  child: Checkbox(
                    value: option.isCorrect,
                    activeColor: Colors.green,
                    onChanged: widget.enabled
                        ? (value) => _updateOption(
                              index,
                              option.copyWith(isCorrect: value ?? false),
                            )
                        : null,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(option.id),
                    initialValue: option.text,
                    enabled: widget.enabled,
                    decoration: InputDecoration(
                      hintText: 'نص الخيار رقم ${index + 1}',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (text) => _updateOption(
                      index,
                      option.copyWith(text: text),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // تسمية الخيار: مخصصة حرفياً، فارغ = تلقائي، `-` = إخفاء.
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    key: ValueKey<String>('label-${option.id}'),
                    initialValue: option.labelOverride ?? '',
                    enabled: widget.enabled,
                    decoration: const InputDecoration(
                      hintText: 'تسمية',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (text) => _updateOption(
                      index,
                      option.copyWith(
                        labelOverride: () => _normalizeLabel(text),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  tooltip: 'حذف الخيار',
                  onPressed: widget.enabled ? () => _removeOption(index) : null,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static List<QuestionOption> _copyOrCreateDefaults(
    List<QuestionOption> options,
  ) {
    if (options.isNotEmpty) {
      return options.map((option) => option.copyWith()).toList(growable: false);
    }
    // بلا خيارات (حُذفت كلها): صف فارغ واحد لبداية جديدة.
    return <QuestionOption>[QuestionOption(text: '')];
  }

  static bool _sameOptions(
    List<QuestionOption> first,
    List<QuestionOption> second,
  ) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      final firstOption = first[index];
      final secondOption = second[index];
      if (firstOption.id != secondOption.id ||
          firstOption.text != secondOption.text ||
          firstOption.isCorrect != secondOption.isCorrect ||
          firstOption.labelOverride != secondOption.labelOverride) {
        return false;
      }
    }
    return true;
  }
}
