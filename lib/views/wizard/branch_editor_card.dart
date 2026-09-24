import 'package:flutter/material.dart';

import '../../models/branch_model.dart';
import '../../models/question_type.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/mcq_options_editor.dart';

/// بطاقة تحرير فرع واحد (أ، ب، ج...) داخل خطوة «إعداد السؤال».
///
/// تُغلّف أدوات الإدخال الحالية بدل إعادة برمجتها: [McqOptionsEditor]
/// للخيارات، و[LtrNumericField] للدرجة، ونموذج صح/خطأ والفراغات بنفس منطق
/// محرر بنك الأسئلة — مع نوع السؤال قابل للاختيار لكل فرع على حدة.
class BranchEditorCard extends StatefulWidget {
  const BranchEditorCard({
    super.key,
    required this.label,
    required this.branch,
    required this.onChanged,
    this.onRemove,
    this.enabled = true,
  });

  final String label;
  final BranchModel branch;
  final ValueChanged<BranchModel> onChanged;
  final VoidCallback? onRemove;
  final bool enabled;

  @override
  State<BranchEditorCard> createState() => _BranchEditorCardState();
}

class _BranchEditorCardState extends State<BranchEditorCard> {
  late final TextEditingController _textController;
  late final TextEditingController _marksController;
  late final TextEditingController _modelAnswerController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.branch.content.text);
    _marksController = TextEditingController(text: _formatMarks(widget.branch.marks));
    _modelAnswerController =
        TextEditingController(text: widget.branch.content.modelAnswer);
  }

  @override
  void didUpdateWidget(covariant BranchEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مزامنة الحقول عند تبديل المحتوى خارجياً (مثلاً بعد السحب والإفلات).
    if (widget.branch.content.text != _textController.text) {
      _textController.text = widget.branch.content.text;
    }
    if (widget.branch.content.modelAnswer != _modelAnswerController.text) {
      _modelAnswerController.text = widget.branch.content.modelAnswer;
    }
    final parsedMarks = _parseMarks(_marksController.text);
    if (parsedMarks == null || parsedMarks != widget.branch.marks) {
      _marksController.text = _formatMarks(widget.branch.marks);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _marksController.dispose();
    _modelAnswerController.dispose();
    super.dispose();
  }

  BranchContent get _content => widget.branch.content;

  void _emitContent(BranchContent content) {
    widget.onChanged(widget.branch.copyWith(content: content));
  }

  void _onMarksChanged(String value) {
    final marks = _parseMarks(value);
    if (marks != null) {
      widget.onChanged(widget.branch.copyWith(marks: marks));
    }
  }

  static double? _parseMarks(String value) {
    final normalized = value.trim().replaceAll('،', '.').replaceAll(',', '.');
    if (normalized.isEmpty) {
      return 0;
    }
    final marks = double.tryParse(normalized);
    return marks != null && marks.isFinite && marks >= 0 ? marks : null;
  }

  static String _formatMarks(double marks) {
    if (marks == 0) {
      return '';
    }
    return marks == marks.truncateToDouble() ? marks.toInt().toString() : marks.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الفرع (${widget.label})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: LtrNumericField(
                    controller: _marksController,
                    enabled: widget.enabled,
                    hintText: 'الدرجة',
                    onChanged: _onMarksChanged,
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    tooltip: 'حذف الفرع',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.enabled ? widget.onRemove : null,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<QuestionType>(
              value: _content.type,
              decoration: const InputDecoration(
                labelText: 'نوع السؤال',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: QuestionType.values
                  .map(
                    (type) => DropdownMenuItem<QuestionType>(
                      value: type,
                      child: Text(type.arabicLabel, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.enabled
                  ? (type) {
                      if (type != null && type != _content.type) {
                        _emitContent(_content.copyWith(type: type));
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _textController,
              enabled: widget.enabled,
              maxLines: null,
              minLines: 2,
              decoration: InputDecoration(
                labelText: _content.type == QuestionType.fillInTheBlank
                    ? 'نص الفرع (ضع _____ مكان الفراغ)'
                    : 'نص الفرع',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (value) => _emitContent(_content.copyWith(text: value)),
            ),
            const SizedBox(height: 10),
            _buildTypeSpecificEditor(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSpecificEditor() {
    switch (_content.type) {
      case QuestionType.multipleChoice:
        return McqOptionsEditor(
          options: _content.options,
          enabled: widget.enabled,
          onChanged: (options) => _emitContent(
            _content.copyWith(
              options: options.map((option) => option.copyWith()).toList(growable: false),
            ),
          ),
        );
      case QuestionType.trueFalse:
        return Row(
          children: <Widget>[
            Expanded(
              child: RadioListTile<bool>(
                dense: true,
                title: const Text('صح'),
                value: true,
                groupValue: _content.trueFalseAnswer,
                onChanged: widget.enabled
                    ? (value) => _emitContent(_content.withTrueFalseAnswer(value ?? true))
                    : null,
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                dense: true,
                title: const Text('خطأ'),
                value: false,
                groupValue: _content.trueFalseAnswer,
                onChanged: widget.enabled
                    ? (value) => _emitContent(_content.withTrueFalseAnswer(value ?? false))
                    : null,
              ),
            ),
          ],
        );
      case QuestionType.fillInTheBlank:
      case QuestionType.essay:
        return TextFormField(
          controller: _modelAnswerController,
          enabled: widget.enabled,
          maxLines: _content.type == QuestionType.essay ? 3 : 1,
          decoration: InputDecoration(
            labelText: _content.type == QuestionType.essay
                ? 'الإجابة النموذجية / معايير التصحيح (لنموذج المعلم)'
                : 'الكلمة الصحيحة للفراغ (لنموذج المعلم)',
            isDense: true,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: (value) => _emitContent(_content.copyWith(modelAnswer: value)),
        );
    }
  }
}
