import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import 'ltr_numeric_field.dart';

/// محرر النقاط المرقَّمة (1، 2، 3...) — **المكوّن المشترك** بين «النقاط
/// داخل الفرع» و«النقاط داخل السؤال» (سؤال بلا فروع).
///
/// الترقيم تلقائي من الفهرس (يخصص أو يُخفى عبر حقل التسمية)، والتحرير
/// متسلسل: تسمية ← إجابة صح/خطأ (اختياري) ← النص ← ترتيب ← حذف، مع
/// ضبط العدد دفعة واحدة (0..200).
///
/// الحالة الوحيدة هنا هي متحكمات النصوص (تُدار بمعرف النقطة فلا تختلط
/// عند النقل)؛ والقائمة النهائية تُسلَّم كاملة عبر [onChanged].
class ItemsEditor extends StatefulWidget {
  const ItemsEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.showTrueFalseAnswers = false,
    this.enabled = true,
  });

  /// النقاط الحالية (تُعرض كما هي؛ التعديلات تُسلَّم كاملة).
  final List<BranchItem> items;

  /// يستقبل القائمة بعد كل تعديل (نص/تسمية/إجابة/ترتيب/حذف/إضافة/عدد).
  final ValueChanged<List<BranchItem>> onChanged;

  /// يُظهر أزرار «صح | خطأ» لكل نقطة (فروع صح/خطأ فقط).
  final bool showTrueFalseAnswers;

  final bool enabled;

  @override
  State<ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<ItemsEditor> {
  final TextEditingController _countController = TextEditingController();
  final Map<String, TextEditingController> _itemFields = <String, TextEditingController>{};

  @override
  void didUpdateWidget(covariant ItemsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مزامنة النصوص عند تغيير خارجي (تراجع/نقل) — لا نسرق الكتابة الجارية.
    for (final item in widget.items) {
      final field = _itemFields[item.id];
      if (field != null && field.text != item.text && !field.selection.isValid) {
        field.text = item.text;
      }
    }
    // التخلص من حقول النقاط المحذوفة.
    final liveIds = widget.items.map((item) => item.id).toSet();
    final stale = _itemFields.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      _itemFields.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    for (final field in _itemFields.values) {
      field.dispose();
    }
    super.dispose();
  }

  TextEditingController _itemField(BranchItem item) {
    return _itemFields.putIfAbsent(
      item.id,
      () => TextEditingController(text: item.text),
    );
  }

  void _emit(List<BranchItem> items) => widget.onChanged(items);

  void _replaceAt(int index, BranchItem item) {
    final updated = List<BranchItem>.of(widget.items);
    updated[index] = item;
    _emit(updated);
  }

  /// فارغ = تلقائي (`null`)، `-` = إخفاء (`''`)، وإلا النص المخصص.
  static String? _normalizeLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed == '-' ? '' : trimmed;
  }

  void _applyItemCount() {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 0 || count > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل عدد عناصر بين 0 و 200.')),
      );
      return;
    }
    final safe = count.clamp(0, 200);
    if (widget.items.length == safe) {
      return;
    }
    if (widget.items.length > safe) {
      _emit(widget.items.sublist(0, safe));
      return;
    }
    _emit(<BranchItem>[
      ...widget.items,
      for (var i = widget.items.length; i < safe; i++) BranchItem(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = widget.items;
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
                  'النقاط المرقمة (1، 2، 3...)',
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
                  // ترقيم النقطة: مخصص حرفي، فارغ = تلقائي، `-` = إخفاء.
                  SizedBox(
                    width: 64,
                    child: TextFormField(
                      key: ValueKey<String>('item-label-${items[index].id}'),
                      initialValue: items[index].labelOverride ?? '',
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        hintText: '${index + 1}-',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      onChanged: (value) => _replaceAt(
                        index,
                        items[index].copyWith(
                          labelOverride: () => _normalizeLabel(value),
                        ),
                      ),
                    ),
                  ),
                  // إجابة النقطة لنموذج المعلم (صح/خطأ فقط).
                  if (widget.showTrueFalseAnswers)
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
                            ? (selection) => _replaceAt(
                                  index,
                                  items[index].copyWith(
                                    isCorrect: () => selection.single,
                                  ),
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
                      onChanged: (value) => _replaceAt(
                        index,
                        items[index].copyWith(text: value),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'نقل لأعلى',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_up, size: 20),
                    onPressed: widget.enabled && index > 0
                        ? () => _emit(List<BranchItem>.of(items)
                          ..[index] = items[index - 1]
                          ..[index - 1] = items[index])
                        : null,
                  ),
                  IconButton(
                    tooltip: 'نقل لأسفل',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    onPressed: widget.enabled && index < items.length - 1
                        ? () => _emit(List<BranchItem>.of(items)
                          ..[index] = items[index + 1]
                          ..[index + 1] = items[index])
                        : null,
                  ),
                  IconButton(
                    tooltip: 'حذف النقطة',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: widget.enabled
                        ? () => _emit(items.where((it) => it.id != items[index].id).toList())
                        : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: widget.enabled
                ? () => _emit(<BranchItem>[...items, BranchItem()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إضافة نقطة', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
