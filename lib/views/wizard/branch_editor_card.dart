import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/question_type.dart';
import '../widgets/items_editor.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/mcq_options_editor.dart';
import '../widgets/rich_content_field.dart';

/// بطاقة تحرير فرع واحد (أ، ب، ج...) داخل خطوة «إعداد السؤال».
///
/// تُغلّف أدوات الإدخال الحالية بدل إعادة برمجتها: [McqOptionsEditor]
/// للخيارات، و[LtrNumericField] للدرجة — مع نوع السؤال قابل للاختيار لكل
/// فرع على حدة، ووضع «نص حر»، ونقاط غير محدودة (1، 2، 3...).
///
/// **لا عنصر إجابة إطلاقاً**: التطبيق لكتابة الأسئلة وحدها، فلا حقل إجابة
/// نموذجية ولا خيار تصحيح — والحقول هي: النص ← النقاط ← الخيارات
/// (نفس ترتيب العرض في المعاينة والـ PDF وWord حرفياً).
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
  late final TextEditingController _marksController;
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _marksController = TextEditingController(text: _formatMarks(widget.branch.marks));
    _labelController =
        TextEditingController(text: widget.branch.labelOverride ?? '');
  }

  @override
  void didUpdateWidget(covariant BranchEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مزامنة الحقول عند تبديل المحتوى خارجياً (مثلاً بعد السحب والإفلات).
    final labelOverride = widget.branch.labelOverride ?? '';
    if (labelOverride != _labelController.text) {
      _labelController.text = labelOverride;
    }
    final parsedMarks = _parseMarks(_marksController.text);
    if (parsedMarks == null || parsedMarks != widget.branch.marks) {
      _marksController.text = _formatMarks(widget.branch.marks);
    }
  }

  @override
  void dispose() {
    _marksController.dispose();
    _labelController.dispose();
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
                        var next = _content.copyWith(type: type);
                        if (type == QuestionType.trueFalse && next.items.isEmpty) {
                          next = next.copyWith(items: <BranchItem>[BranchItem()]);
                        }
                        _emitContent(next);
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
            RichContentField(
              label: _content.type == QuestionType.fillInTheBlank
                  ? 'نص الفرع (ضع _____ مكان الفراغ)'
                  : 'نص الفرع',
              value: _content.text,
              enabled: widget.enabled,
              title: 'تحرير نص الفرع',
              minHeight: 64,
              onChanged: (value) => _emitContent(_content.copyWith(text: value)),
            ),
            const SizedBox(height: 10),
            // النقاط (1، 2، 3...) بترتيب الطباعة نفسه.
            ItemsEditor(
              items: _content.items,
              enabled: widget.enabled,
              onChanged: (items) => _emitContent(_content.copyWith(items: items)),
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
          onChanged: (options) => _emitContent(_content.copyWith(options: options)),
        );
      case QuestionType.trueFalse:
        // «صح/خطأ» = عبارات مرقّمة فقط: تُطبع في نقاطها بالترتيب، ولا يُكتب
        // عنها أي شيء آخر ولا يُضبط لها أي عنصر إجابة (كتابة أسئلة فقط).
        return const SizedBox.shrink();
      case QuestionType.fillInTheBlank:
      case QuestionType.definitions:
      case QuestionType.essay:
        // لا حقل إجابة نموذجية: التطبيق لكتابة الأسئلة وحدها.
        return const SizedBox.shrink();
    }
  }
}
