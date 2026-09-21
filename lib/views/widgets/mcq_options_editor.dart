import 'package:flutter/material.dart';
import '../../models/question.dart';

class McqOptionsEditor extends StatefulWidget {
  final List<QuestionOption> options;
  final ValueChanged<List<QuestionOption>> onChanged;

  const McqOptionsEditor({
    super.key,
    required this.options,
    required this.onChanged,
  });

  @override
  State<McqOptionsEditor> createState() => _McqOptionsEditorState();
}

class _McqOptionsEditorState extends State<McqOptionsEditor> {
  late List<QuestionOption> _localOptions;

  @override
  void initState() {
    super.initState();
    _localOptions = List.from(widget.options);
    if (_localOptions.isEmpty) {
      _localOptions = [
        QuestionOption(text: '', isCorrect: true),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
        QuestionOption(text: '', isCorrect: false),
      ];
    }
  }

  void _addOption() {
    setState(() {
      _localOptions.add(QuestionOption(text: '', isCorrect: false));
    });
    widget.onChanged(_localOptions);
  }

  void _removeOption(int index) {
    if (_localOptions.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب أن يحتوي سؤال الخيارات على خيارين على الأقل')),
      );
      return;
    }
    setState(() {
      _localOptions.removeAt(index);
    });
    widget.onChanged(_localOptions);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'خيارات الإجابة (حدد الإجابة الصحيحة):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة خيار'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_localOptions.length, (index) {
          final opt = _localOptions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Tooltip(
                  message: 'تحديد كإجابة صحيحة',
                  child: Checkbox(
                    value: opt.isCorrect,
                    activeColor: Colors.green,
                    onChanged: (val) {
                      setState(() {
                        opt.isCorrect = val ?? false;
                      });
                      widget.onChanged(_localOptions);
                    },
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: opt.text,
                    decoration: InputDecoration(
                      hintText: 'نص الخيار رقم ${index + 1}',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (text) {
                      opt.text = text;
                      widget.onChanged(_localOptions);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () => _removeOption(index),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
