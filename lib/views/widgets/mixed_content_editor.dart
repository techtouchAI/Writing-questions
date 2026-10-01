import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show MathStyle;

import '../../models/tex_content.dart';
import 'safe_math_tex.dart';
import 'visual_equation_editor.dart';

/// محرر المحتوى المختلط: **نص + معادلات متعددة في الحقل نفسه**.
///
/// التخزين يبقى كما هو (`نص $معادلة$ نص $$معادلة منفردة$$`) فلا يتغير أي ملف
/// قديم ولا التصدير؛ وواجهة التحرير فقط هي الجديدة:
/// - النص يُكتب في حقول نصية عادية.
/// - كل معادلة تُعرض **مرئية** (لا كود) وتُحرَّر بمحرر المعادلات المرئي
///   نفسه المستخدم في بقية التطبيق ([VisualEquationEditor]).
/// - يمكن إضافة أي عدد من المعادلات وحذفها والتنقل بين أقسام المتن.
///
/// الحفظ يعيد بناء المصدر من الأقسام، فيبقى الحقل قابلاً للتحرير لاحقاً
/// بالطريقة نفسها (إعادة التحليل ← تحرير ← حفظ).
class MixedContentEditor extends StatefulWidget {
  const MixedContentEditor({
    super.key,
    required this.initialSource,
    this.title = 'تحرير المحتوى',
  });

  final String initialSource;
  final String title;

  /// يفتح المحرر ويعيد المصدر الجديد، أو `null` عند الإلغاء.
  static Future<String?> show(
    BuildContext context, {
    required String source,
    String title = 'تحرير المحتوى',
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: MixedContentEditor(initialSource: source, title: title),
        ),
      ),
    );
  }

  @override
  State<MixedContentEditor> createState() => _MixedContentEditorState();
}

class _MixedContentEditorState extends State<MixedContentEditor> {
  late List<_MixedBlock> _blocks;
  int _nextBlockId = 0;

  @override
  void initState() {
    super.initState();
    _blocks = _parse(widget.initialSource);
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      block.controller?.dispose();
    }
    super.dispose();
  }

  /// يقسم المصدر إلى أقسام نص/معادلات بالترتيب نفسه (بلا أي كود ظاهر).
  List<_MixedBlock> _parse(String source) {
    final blocks = <_MixedBlock>[];
    for (final segment in TexContent.split(source)) {
      if (segment.isMath) {
        blocks.add(
          _MixedBlock.math(
            id: _nextBlockId++,
            latex: segment.text,
            isBlock: segment.isBlock,
          ),
        );
      } else {
        blocks.add(
          _MixedBlock.text(id: _nextBlockId++, initialText: segment.text),
        );
      }
    }
    if (blocks.isEmpty) {
      blocks.add(_MixedBlock.text(id: _nextBlockId++, initialText: ''));
    }
    return blocks;
  }

  /// يبني المصدر المخزَّن: النص كما هو (مع تهريب الدولار الحرفي)، وكل معادلة
  /// داخل `$...$` أو `$$...$$`.
  String _buildSource() {
    final buffer = StringBuffer();
    for (final block in _blocks) {
      if (block.isText) {
        buffer.write(TexContent.escapeLiteral(block.text));
        continue;
      }
      final latex = block.latex.trim();
      if (latex.isEmpty) {
        continue;
      }
      buffer.write(block.isBlock ? '\$\$$latex\$\$' : '\$$latex\$');
    }
    return buffer.toString();
  }

  void _addText() {
    setState(() {
      _blocks.add(_MixedBlock.text(id: _nextBlockId++, initialText: ''));
    });
  }

  void _addMath({int? afterIndex}) {
    setState(() {
      final block = _MixedBlock.math(id: _nextBlockId++, latex: '', isBlock: false);
      if (afterIndex == null) {
        _blocks.add(block);
      } else {
        _blocks.insert(afterIndex + 1, block);
      }
    });
  }

  void _removeBlock(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }
    setState(() {
      _blocks.removeAt(index).controller?.dispose();
      if (_blocks.isEmpty) {
        _blocks.add(_MixedBlock.text(id: _nextBlockId++, initialText: ''));
      }
    });
  }

  void _moveBlock(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= _blocks.length || target < 0 || target >= _blocks.length) {
      return;
    }
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(target, block);
    });
  }

  void _save() {
    final hasEquation = _blocks.any((block) => !block.isText && block.latex.trim().isNotEmpty);
    final text = _blocks.where((block) => block.isText).map((b) => b.text).join().trim();
    if (!hasEquation && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المحتوى فارغ — أضف نصاً أو معادلة أولاً.')),
      );
      return;
    }
    Navigator.of(context).pop(_buildSource());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: <Widget>[
              const Icon(Icons.edit_note, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            shrinkWrap: true,
            itemCount: _blocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildBlock(context, index, colorScheme),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => _addText(),
                icon: const Icon(Icons.text_fields, size: 18),
                label: const Text('إضافة نص'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addMath(),
                icon: const Icon(Icons.functions, size: 18),
                label: const Text('إضافة معادلة'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('حفظ المحتوى'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, int index, ColorScheme colorScheme) {
    final block = _blocks[index];
    return Container(
      key: ValueKey<int>(block.id),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
        color: block.isText
            ? null
            : colorScheme.surfaceContainerHighest.withOpacity(0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                block.isText ? Icons.text_fields : Icons.functions,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                block.isText
                    ? 'نص'
                    : (block.isBlock ? 'معادلة منفردة' : 'معادلة سطرية'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'نقل للأعلى',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: index == 0 ? null : () => _moveBlock(index, -1),
              ),
              IconButton(
                tooltip: 'نقل للأسفل',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed:
                    index == _blocks.length - 1 ? null : () => _moveBlock(index, 1),
              ),
              IconButton(
                tooltip: 'حذف هذا القسم',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _removeBlock(index),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (block.isText)
            TextField(
              controller: block.controller,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'اكتب النص هنا...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => block.text = value,
            )
          else
            _MathBlockEditor(
              block: block,
              onChanged: (latex, isBlock) {
                setState(() {
                  block.latex = latex;
                  block.isBlock = isBlock;
                });
              },
            ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 6,
              children: <Widget>[
                // المعادلة هي العنصر الوحيد الذي يُدرج مباشرة بعد هذا القسم.
                // النص يُكتب داخل القسم النصي الحالي أو يُضاف من شريط المحرر.
                TextButton.icon(
                  onPressed: () => _addMath(afterIndex: index),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('معادلة بعدها', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// معاينة المعادلة + محررها المرئي المضمَّن.
class _MathBlockEditor extends StatelessWidget {
  const _MathBlockEditor({required this.block, required this.onChanged});

  final _MixedBlock block;
  final void Function(String latex, bool isBlock) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: block.latex.trim().isEmpty
              ? const Text(
                  'معادلة فارغة — اكتبها من الشريط أدناه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                )
              : Directionality(
                  textDirection: TextDirection.ltr,
                  child: Center(
                    child: SafeMathTex(
                      block.latex,
                      mathStyle:
                          block.isBlock ? MathStyle.display : MathStyle.text,
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        VisualEquationEditor(
          key: ValueKey<String>('eq-${block.id}'),
          initialLatex: block.latex,
          initialIsBlock: block.isBlock,
          embedded: true,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// قسم واحد في المتن المختلط: نص أو معادلة.
class _MixedBlock {
  _MixedBlock.text({required this.id, required String initialText})
      : isText = true,
        text = initialText,
        latex = '',
        isBlock = false,
        controller = TextEditingController(text: initialText);

  _MixedBlock.math({
    required this.id,
    required this.latex,
    required this.isBlock,
  })  : isText = false,
        text = '',
        controller = null;

  final int id;
  final bool isText;

  /// نص القسم (لأقسام النص وحدها).
  String text;

  /// الصيغة (لأقسام المعادلات وحدها).
  String latex;

  /// معادلة منفردة (`$$...$$`) أم سطرية (`$...$`)؟
  bool isBlock;

  /// متحكم حقل النص ([isText] فقط).
  final TextEditingController? controller;
}
