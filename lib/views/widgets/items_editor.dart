import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import 'ltr_numeric_field.dart';
import 'rich_content_field.dart';

/// محرر النقاط المرقَّمة (1، 2، 3...) — **المكوّن المشترك** بين «النقاط
/// داخل الفرع» و«النقاط داخل السؤال» (سؤال بلا فروع).
///
/// الترقيم بتسلسل تلقائي من الفهرس (1-، 2-، 3-...)، والتحرير متسلسل:
/// تسلسل تلقائي ← كتابة النص ← حذف، مع إمكانية ضبط العدد دفعة واحدة
/// (0..200). أُزيلت أزرار التقديم والتأخير لعدم الحاجة إليها.
///
/// التطبيق لكتابة الأسئلة وحدها: كل نقطة نص ودرجة وتسمية ومحاذاة فقط،
/// وتُطبع نصاً مرقّماً.
class ItemsEditor extends StatefulWidget {
  const ItemsEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  /// النقاط الحالية (تُعرض كما هي؛ التعديلات تُسلَّم كاملة).
  final List<BranchItem> items;

  /// يستقبل القائمة بعد كل تعديل (نص/تسمية/حذف/إضافة/عدد).
  final ValueChanged<List<BranchItem>> onChanged;

  final bool enabled;

  @override
  State<ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<ItemsEditor> {
  final TextEditingController _countController = TextEditingController();

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  void _emit(List<BranchItem> items) => widget.onChanged(items);

  void _replaceAt(int index, BranchItem item) {
    final updated = List<BranchItem>.of(widget.items);
    updated[index] = item;
    _emit(updated);
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
                  // تسلسل تلقائي للنقطة (1-، 2-، 3-...)
                  Container(
                    width: 44,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Text(
                      items[index].labelOverride?.isNotEmpty == true
                          ? items[index].labelOverride!
                          : '${index + 1}-',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // نص النقطة: يُعرض بشكله النهائي (والمعادلات مرسومة) ويُحرَّر
                  // في محرر المحتوى المختلط — بلا أي كود LaTeX على الشاشة.
                  Expanded(
                    child: RichContentField(
                      value: items[index].text,
                      enabled: widget.enabled,
                      hint: 'نص النقطة ${index + 1}...',
                      title: 'تحرير نص النقطة',
                      minHeight: 40,
                      onChanged: (value) => _replaceAt(
                        index,
                        items[index].copyWith(text: value),
                      ),
                    ),
                  ),
                  // زر حذف النقطة (بدون أزرار تقديم أو تأخير)
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
