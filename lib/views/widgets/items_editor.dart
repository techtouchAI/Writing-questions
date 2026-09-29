import 'package:flutter/material.dart';

import '../../models/branch_item.dart';
import 'ltr_numeric_field.dart';

/// محرر النقاط المرقَّمة (1، 2، 3...) — **المكوّن المشترك** بين «النقاط
/// داخل الفرع» و«النقاط داخل السؤال» (سؤال بلا فروع).
///
/// الترقيم بتسلسل تلقائي من الفهرس (1-، 2-، 3-...)، والتحرير متسلسل:
/// تسلسل تلقائي ← كتابة النص ← وضع علامة صح وخطأ أو كلمة صح أو خطأ ← حذف،
/// مع إمكانية ضبط العدد دفعة واحدة (0..200). أُزيلت أزرار التقديم والتأخير لعدم الحاجة إليها.
class ItemsEditor extends StatefulWidget {
  const ItemsEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.showTrueFalseAnswers = false,
    this.trueFalseFormat = 'words',
    this.onFormatChanged,
    this.enabled = true,
  });

  /// النقاط الحالية (تُعرض كما هي؛ التعديلات تُسلَّم كاملة).
  final List<BranchItem> items;

  /// يستقبل القائمة بعد كل تعديل (نص/تسمية/إجابة/حذف/إضافة/عدد).
  final ValueChanged<List<BranchItem>> onChanged;

  /// يُظهر أزرار «صح | خطأ» أو «✓ | ✗» لكل نقطة (فروع صح/خطأ فقط).
  final bool showTrueFalseAnswers;

  /// نمط الإجابة: 'words' (صح/خطأ) أو 'symbols' (✓/✗).
  final String trueFalseFormat;

  /// يُستدعى عند تغيير نمط الإجابة (علامات أو كلمات).
  final ValueChanged<String>? onFormatChanged;

  final bool enabled;

  @override
  State<ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<ItemsEditor> {
  final TextEditingController _countController = TextEditingController();
  final Map<String, TextEditingController> _itemFields = <String, TextEditingController>{};
  late String _format;

  @override
  void initState() {
    super.initState();
    _format = widget.trueFalseFormat;
  }

  @override
  void didUpdateWidget(covariant ItemsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trueFalseFormat != oldWidget.trueFalseFormat) {
      _format = widget.trueFalseFormat;
    }
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

  Widget _buildTrueFalseButtons(int index, BranchItem item) {
    final isTrue = item.isCorrect == true;
    final isFalse = item.isCorrect == false;
    final isSymbols = _format == 'symbols';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: isSymbols ? 'علامة صح (✓)' : 'كلمة صح',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.enabled
                ? () => _replaceAt(
                      index,
                      item.copyWith(isCorrect: () => isTrue ? null : true),
                    )
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isTrue ? Colors.green.shade100 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isTrue ? Colors.green.shade700 : Colors.grey.shade400,
                  width: isTrue ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                isSymbols ? '✓' : 'صح',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isTrue ? Colors.green.shade800 : Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: isSymbols ? 'علامة خطأ (✗)' : 'كلمة خطأ',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.enabled
                ? () => _replaceAt(
                      index,
                      item.copyWith(isCorrect: () => isFalse ? null : false),
                    )
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isFalse ? Colors.red.shade100 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFalse ? Colors.red.shade700 : Colors.grey.shade400,
                  width: isFalse ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                isSymbols ? '✗' : 'خطأ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isFalse ? Colors.red.shade800 : Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
          if (widget.showTrueFalseAnswers)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: <Widget>[
                  const Text(
                    'نمط علامة الإجابة:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('علامات (✓ / ✗)', style: TextStyle(fontSize: 11)),
                    selected: _format == 'symbols',
                    visualDensity: VisualDensity.compact,
                    onSelected: widget.enabled
                        ? (selected) {
                            if (selected) {
                              setState(() => _format = 'symbols');
                              widget.onFormatChanged?.call('symbols');
                            }
                          }
                        : null,
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('كلمات (صح / خطأ)', style: TextStyle(fontSize: 11)),
                    selected: _format == 'words',
                    visualDensity: VisualDensity.compact,
                    onSelected: widget.enabled
                        ? (selected) {
                            if (selected) {
                              setState(() => _format = 'words');
                              widget.onFormatChanged?.call('words');
                            }
                          }
                        : null,
                  ),
                ],
              ),
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
                  // كتابة نص النقطة
                  Expanded(
                    child: TextFormField(
                      controller: _itemField(items[index]),
                      enabled: widget.enabled,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: widget.showTrueFalseAnswers
                            ? 'نص العبارة ${index + 1}...'
                            : 'نص النقطة ${index + 1}...',
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
                  // وضع علامة صح وخطأ أو كلمة صح أو خطأ
                  if (widget.showTrueFalseAnswers) ...<Widget>[
                    const SizedBox(width: 6),
                    _buildTrueFalseButtons(index, items[index]),
                  ],
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
