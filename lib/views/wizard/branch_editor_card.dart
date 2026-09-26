import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/question_type.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/mcq_options_editor.dart';

/// بطاقة تحرير فرع واحد (أ، ب، ج...) داخل خطوة «إعداد السؤال».
///
/// تُغلّف أدوات الإدخال الحالية بدل إعادة برمجتها: [McqOptionsEditor]
/// للخيارات، و[LtrNumericField] للدرجة، ونموذج صح/خطأ والفراغات بنفس منطق
/// محرر بنك الأسئلة — مع نوع السؤال قابل للاختيار لكل فرع على حدة،
/// ووضع «نص حر» (بلا مساحة إجابة مولّدة)، ونقاط غير محدودة (1، 2، 3...).
class BranchEditorCard extends StatefulWidget {
  const BranchEditorCard({
    super.key,
    required this.label,
    required this.autoLabel,
    required this.branch,
    required this.onChanged,
    this.onRemove,
    this.enabled = true,
  });

  /// التسمية المعروضة للفرع (يدوية إن ثُبّتت، وإلا تلقائية من الفهرس).
  final String label;

  /// التسمية التلقائية من الفهرس (تلميح حقل التسمية المخصصة).
  final String autoLabel;

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
  late final TextEditingController _labelController;
  final TextEditingController _countController = TextEditingController();
  final Map<String, TextEditingController> _itemFields = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.branch.content.text);
    _marksController = TextEditingController(text: _formatMarks(widget.branch.marks));
    _modelAnswerController =
        TextEditingController(text: widget.branch.content.modelAnswer);
    _labelController =
        TextEditingController(text: widget.branch.labelOverride ?? '');
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
    final labelOverride = widget.branch.labelOverride ?? '';
    if (labelOverride != _labelController.text) {
      _labelController.text = labelOverride;
    }
    final parsedMarks = _parseMarks(_marksController.text);
    if (parsedMarks == null || parsedMarks != widget.branch.marks) {
      _marksController.text = _formatMarks(widget.branch.marks);
    }
    // التخلص من حقول النقاط المحذوفة.
    final liveIds = widget.branch.content.items.map((item) => item.id).toSet();
    final stale = _itemFields.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      _itemFields.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _marksController.dispose();
    _modelAnswerController.dispose();
    _labelController.dispose();
    _countController.dispose();
    for (final field in _itemFields.values) {
      field.dispose();
    }
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

  TextEditingController _itemField(BranchItem item) {
    return _itemFields.putIfAbsent(
      item.id,
      () => TextEditingController(text: item.text),
    );
  }

  void _applyItemCount() {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 0 || count > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل عدد عناصر بين 0 و 200.')),
      );
      return;
    }
    _emitContent(_content.withItemCount(count));
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
            TextFormField(
              controller: _labelController,
              enabled: widget.enabled,
              decoration: InputDecoration(
                labelText: 'تسمية الفرع (فارغ = تلقائي)',
                hintText: 'تلقائي: ${widget.autoLabel}',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => widget.onChanged(
                widget.branch.copyWith(
                  labelOverride: () => value.trim().isEmpty ? null : value.trim(),
                ),
              ),
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('نص حر فقط (بدون مساحة إجابة)', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                'يعرض النص والنقاط كما كتبتها تماماً',
                style: TextStyle(fontSize: 11),
              ),
              value: _content.plainText,
              onChanged: widget.enabled
                  ? (value) => _emitContent(_content.copyWith(plainText: value))
                  : null,
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 4),
            _buildItemsEditor(colorScheme),
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

  /// محرر النقاط داخل الفرع (1، 2، 3...): إضافة/حذف/ترتيب + ضبط العدد.
  Widget _buildItemsEditor(ColorScheme colorScheme) {
    final items = _content.items;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'النقاط داخل الفرع (1، 2، 3...)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              SizedBox(
                width: 76,
                child: LtrNumericField(
                  controller: _countController,
                  enabled: widget.enabled,
                  hintText: 'العدد',
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                onPressed: widget.enabled ? _applyItemCount : null,
                child: const Text('تطبيق', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'بلا نقاط — حدد عدد العناصر أو أضف نقطة.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Text('${index + 1}-',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  // إجابة النقطة لنموذج المعلم (صح/خطأ فقط).
                  if (_content.type == QuestionType.trueFalse)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: SegmentedButton<bool?>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<bool?>>[
                          ButtonSegment<bool?>(
                            value: true,
                            label: Text('صح', style: TextStyle(fontSize: 11)),
                          ),
                          ButtonSegment<bool?>(
                            value: false,
                            label: Text('خطأ', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                        selected: items[index].isCorrect == null
                            ? const <bool?>{}
                            : <bool?>{items[index].isCorrect},
                        onSelectionChanged: widget.enabled
                            ? (selection) => _emitContent(
                                  _content.withItemAnswer(index, selection.single),
                                )
                            : null,
                      ),
                    ),
                  Expanded(
                    child: TextFormField(
                      controller: _itemField(items[index]),
                      enabled: widget.enabled,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'نص النقطة ${index + 1}...',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        final updated = List<BranchItem>.of(items);
                        updated[index] = updated[index].copyWith(text: value);
                        _emitContent(_content.copyWith(items: updated));
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'نقل لأعلى',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_up, size: 20),
                    onPressed: widget.enabled && index > 0
                        ? () => _emitContent(_content.withItemMoved(index, index - 1))
                        : null,
                  ),
                  IconButton(
                    tooltip: 'نقل لأسفل',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    onPressed: widget.enabled && index < items.length - 1
                        ? () => _emitContent(_content.withItemMoved(index, index + 1))
                        : null,
                  ),
                  IconButton(
                    tooltip: 'حذف النقطة',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: widget.enabled
                        ? () => _emitContent(_content.withItemRemoved(index))
                        : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed:
                widget.enabled ? () => _emitContent(_content.withItemAdded()) : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إضافة نقطة', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
