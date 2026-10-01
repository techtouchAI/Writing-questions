import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import '../../models/point_kind.dart';
import '../../models/question_option.dart';
import 'labeled_dropdown.dart';
import 'ltr_numeric_field.dart';
import 'rich_content_field.dart';

/// محرر النقاط المرقّمة بأنواعها المختلطة — **المكوّن المشترك** بين «نقاط
/// السؤال» و«نقاط الفرع».
///
/// لكل نقطة نوعها (نص حر / صح أو خطأ / إكمال الفراغ / اختيار من متعدد)
/// وتختلط الأنواع في المجموعة نفسها بحرية؛ والترقيم تسلسل واحد متصل يُشتق من
/// الفهرس ([labelOf]). نقطة «اختيار من متعدد» تُحرَّر خياراتها هنا مباشرةً
/// (٤ خيارات فارغة افتراضياً، والعدد حر).
///
/// التطبيق لكتابة الأسئلة وحدها: لا اختيار «إجابة صحيحة» لأي نوع.
class PointsEditor extends StatefulWidget {
  const PointsEditor({
    super.key,
    required this.points,
    required this.labelOf,
    required this.optionLabelOf,
    required this.onChanged,
    this.enabled = true,
  });

  /// النقاط الحالية (تُعرض كما هي؛ التعديلات تُسلَّم كاملة).
  final List<BranchItem> points;

  /// الرقم المعروض للنقطة (تلقائي بالفهرس أو مخصص) — «١-».
  final String Function(int index, BranchItem point) labelOf;

  /// تسمية الخيار المعروضة (تلقائية بالفهرس «( أ )» أو مخصصة).
  final String Function(int index, QuestionOption option) optionLabelOf;

  /// يستقبل القائمة بعد كل تعديل (نص/نوع/خيارات/حذف/إضافة/عدد).
  final ValueChanged<List<BranchItem>> onChanged;

  final bool enabled;

  @override
  State<PointsEditor> createState() => _PointsEditorState();
}

class _PointsEditorState extends State<PointsEditor> {
  final TextEditingController _countController = TextEditingController();

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  void _emit(List<BranchItem> points) => widget.onChanged(points);

  void _replaceAt(int index, BranchItem point) {
    final updated = List<BranchItem>.of(widget.points);
    updated[index] = point;
    _emit(updated);
  }

  void _applyCount() {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 0 || count > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل عدد نقاط بين 0 و200.')),
      );
      return;
    }
    final points = widget.points;
    if (points.length == count) {
      return;
    }
    if (points.length > count) {
      _emit(points.sublist(0, count));
      return;
    }
    _emit(<BranchItem>[
      ...points,
      for (var i = points.length; i < count; i++) BranchItem(),
    ]);
  }

  /// خيارات نقطة «اختيار من متعدد»: حقل لكل خيار + إضافة/حذف.
  Widget _buildOptions(int index, BranchItem point) {
    final options = point.options;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, start: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 44,
                    child: Text(
                      widget.optionLabelOf(i, options[i]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey<String>('point-option-${options[i].id}'),
                      initialValue: options[i].text,
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        hintText: 'اكتب الخيار ${i + 1} هنا',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final updated = List<QuestionOption>.of(point.options);
                        updated[i] = updated[i].copyWith(text: value);
                        _replaceAt(index, point.copyWith(options: updated));
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف الخيار',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: widget.enabled
                        ? () {
                            final updated = List<QuestionOption>.of(point.options)
                              ..removeAt(i);
                            _replaceAt(index, point.copyWith(options: updated));
                          }
                        : null,
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: widget.enabled
                  ? () => _replaceAt(
                        index,
                        point.copyWith(
                          options: <QuestionOption>[...options, QuestionOption(text: '')],
                        ),
                      )
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('إضافة خيار', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoint(int index, BranchItem point) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('point-${point.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // الرقم التلقائي المتصل (١-، ٢-، ٣-...) مهما كان نوع النقطة.
              Container(
                width: 44,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  widget.labelOf(index, point),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LabeledDropdown<PointKind>(
                  label: 'نوع النقطة',
                  hint: 'اختر نوع النقطة',
                  value: point.kind,
                  values: PointKind.values,
                  labelOf: (kind) => kind.arabicLabel,
                  onChanged: (kind) {
                    if (widget.enabled && kind != point.kind) {
                      _replaceAt(index, point.copyWith(kind: kind));
                    }
                  },
                ),
              ),
              IconButton(
                tooltip: 'حذف النقطة',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.enabled
                    ? () => _emit(<BranchItem>[
                          for (final other in widget.points)
                            if (other.id != point.id) other,
                        ])
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // نص النقطة: يُعرض بشكله النهائي (والمعادلات مرسومة) ويُحرَّر في
          // محرر المحتوى المختلط — بلا أي كود LaTeX على الشاشة.
          RichContentField(
            value: point.text,
            enabled: widget.enabled,
            hint: point.kind.textHint,
            title: 'تحرير نص النقطة',
            minHeight: 40,
            onChanged: (value) => _replaceAt(index, point.copyWith(text: value)),
          ),
          if (point.kind == PointKind.multipleChoice) _buildOptions(index, point),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final points = widget.points;
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
                  'النقاط المرقمة (١-، ٢-، ٣-...)',
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
                onPressed: widget.enabled ? _applyCount : null,
                child: const Text('تطبيق', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'بلا نقاط — حدد عدد النقاط أو أضف نقطة (صح/خطأ، إكمال فراغ، اختيار من متعدد).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          for (var index = 0; index < points.length; index++)
            _buildPoint(index, points[index]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.enabled
                ? () => _emit(<BranchItem>[...points, BranchItem()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إضافة نقطة', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
