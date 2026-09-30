import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/question_type.dart';
import '../widgets/items_editor.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/rich_content_field.dart';

/// بطاقة تحرير فرع واحد (أ، ب، ج...) داخل خطوة «إعداد السؤال».
///
/// تُغلّف أدوات الإدخال الحالية بدل إعادة برمجتها: [ItemsEditor] للنقاط
/// و[LtrNumericField] للدرجة — مع نوع السؤال قابل للاختيار لكل فرع على حدة،
/// ووضع «نص حر»، ونقاط غير محدودة (1، 2، 3...).
///
/// التطبيق لكتابة الأسئلة وحدها، والحقول هنا هي: النص ← النقاط.
/// **خيارات «اختيار من متعدد» لا تُكتب في هذه البطاقة إطلاقاً**: مكانها
/// خانة الخيار على ورقة المعاينة (الخطوة 3) حيث تُعرض كما تُطبع حرفياً
/// وتُحرَّر في مكانها (والإضافة بزر «+ خيار» عند تحديد الفرع). لهذا لا يوجد
/// هنا محرر خيارات، بل سطر توجيه واحد لفرع «اختيار من متعدد».
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
              title: const Text('نص حر فقط', style: TextStyle(fontSize: 13)),
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
            // لا محرر خيارات هنا: خيارات «اختيار من متعدد» تُكتب على ورقة
            // المعاينة حيث تُعرض كما تُطبع حرفياً. السطر توجيه فقط، ولا يُنشئ
            // ولا يعدّل أي خيار (الخيارات الافتراضية الأربعة تبقى جاهزة هناك).
            if (_content.type == QuestionType.multipleChoice)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.touch_app_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'خيارات هذا الفرع تُكتب على ورقة المعاينة (الخطوة 3): '
                        'انقر خانة الخيار واكتب نصها، وزر «+ خيار» يظهر عند تحديد الفرع.',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
