import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/question_option.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/points_editor.dart';
import '../widgets/rich_content_field.dart';

/// بطاقة تحرير فرع واحد (أ، ب، ج...) داخل خطوة «إعداد السؤال».
///
/// الحقول بترتيب الطباعة نفسه (وهو ترتيب السؤال): الرقم ← المنطوق ← الدرجة
/// (رقم خام يطبعه النظام «(٥ درجة)») ← النص (يُحذف من الورقة عند فراغه) ←
/// النقاط المرقّمة ذات النص الحر ([PointsEditor]).
class BranchEditorCard extends StatefulWidget {
  const BranchEditorCard({
    super.key,
    required this.label,
    required this.autoLabel,
    required this.branch,
    required this.pointLabelOf,
    required this.optionLabelOf,
    required this.onChanged,
    this.pointMarksHelperOf,
    this.onRemove,
    this.enabled = true,
  });

  /// التسمية المعروضة للفرع (يدوية إن ثُبّتت، وإلا تلقائية من الفهرس).
  final String label;

  /// التسمية التلقائية من الفهرس (تلميح حقل الرقم المخصص).
  final String autoLabel;

  final BranchModel branch;

  /// الرقم المعروض لنقطة (تسلسل متصل) وتسمية خيار — من مستند الورقة.
  final String Function(int index, BranchItem point) pointLabelOf;
  final String Function(int index, QuestionOption option) optionLabelOf;

  /// تلميح درجة النقطة كما ستُطبع («(٢ درجة)») — يُمرَّر إلى [PointsEditor].
  final String Function(double marks)? pointMarksHelperOf;

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
    _labelController = TextEditingController(text: widget.branch.labelOverride ?? '');
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
                labelText: 'رقم الفرع (فارغ = تلقائي)',
                hintText: 'تلقائي: ${widget.autoLabel} — يُضاف القوس تلقائياً',
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
            RichContentField(
              label: 'منطوق الفرع',
              hint: 'اكتب منطوق الفرع هنا (مثال: عرّف ما يأتي)',
              value: _content.statement,
              enabled: widget.enabled,
              title: 'تحرير منطوق الفرع',
              minHeight: 48,
              onChanged: (value) => _emitContent(_content.copyWith(statement: value)),
            ),
            const SizedBox(height: 10),
            LtrNumericField(
              controller: _marksController,
              enabled: widget.enabled,
              decoration: const InputDecoration(
                labelText: 'درجة الفرع',
                hintText: 'اكتب الرقم فقط، مثال: 5',
                suffixText: 'درجة',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _onMarksChanged,
            ),
            const SizedBox(height: 10),
            RichContentField(
              label: 'نص الفرع (اختياري)',
              hint: 'يُحذف من الورقة تلقائياً إذا تُرك فارغاً',
              value: _content.body,
              enabled: widget.enabled,
              title: 'تحرير نص الفرع',
              minHeight: 48,
              onChanged: (value) => _emitContent(_content.copyWith(body: value)),
            ),
            const SizedBox(height: 10),
            // النقاط (١-، ٢-، ٣-...) بترتيب الطباعة نفسه وأنواعها مختلطة.
            PointsEditor(
              points: _content.items,
              enabled: widget.enabled,
              labelOf: widget.pointLabelOf,
              optionLabelOf: widget.optionLabelOf,
              marksHelperOf: widget.pointMarksHelperOf,
              onChanged: (items) => _emitContent(_content.copyWith(items: items)),
            ),
          ],
        ),
      ),
    );
  }
}
