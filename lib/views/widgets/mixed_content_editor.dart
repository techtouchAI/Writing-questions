import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show MathStyle;

import '../../models/tex_content.dart';
import '../../pdf_engine/latex/latex_svg_renderer.dart';
import 'safe_math_tex.dart';
import 'visual_equation_editor.dart';

/// محرر المحتوى المختلط: **نص + معادلات متعددة في الحقل نفسه**.
///
/// التخزين يبقى كما هو (`نص $معادلة$ نص $$معادلة منفردة$$`) فلا يتغير أي ملف
/// قديم ولا التصدير؛ وواجهة التحرير تتبع طبيعة المحتوى:
/// - **النص الرئيسي واحد لا يتجزأ**: يُكتب في حقوله بالترتيب، ولا يوجد زر
///   «إضافة نص» — فالمدرس يكتب منطوقاً واحداً والمعادلات تُغرَس داخله، فلا
///   تتكدس فقرات نصية متفرقة ولا يُحذف نصه سهواً (أقسام النص غير قابلة
///   للحذف، وحذف معادلة بين قسمين يعيد دمجهما نصاً واحداً متصلاً).
/// - **المعادلة تُدرج عند مؤشر الكتابة**: «إضافة معادلة» تقسم النص عند
///   المؤشر وتضع المعادلة هناك تماماً (كإدراج Word)، فإن كان المؤشر في آخر
///   النص أُضيفت بعده.
/// - كل معادلة تُعرض **مرئية** (لا كود) وتُحرَّر بمحرر المعادلات المرئي نفسه
///   ([VisualEquationEditor])، وتُنقل وتحذف وتُبدَّل بين سطرية ومنفردة.
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

  /// آخر خانة نصية نشطة وموضع المؤشر فيها — مرجع إدراج المعادلات.
  _MixedBlock? _activeText;
  int _activeCaret = 0;

  @override
  void initState() {
    super.initState();
    _blocks = _parse(widget.initialSource);
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  /// يقسم المصدر إلى أقسام نص/معادلات بالترتيب نفسه (بلا أي كود ظاهر).
  ///
  /// الضمان: قسم نصي واحد على الأقل دائماً — فالمصدر الخالص معادلاتٍ يُفتح
  /// بخانة نص فارغة تتيح إضافة المنطوق حولها، والنص لا يُفقد أبداً.
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
        blocks.add(_newTextBlock(segment.text));
      }
    }
    if (!blocks.any((block) => block.isText)) {
      blocks.add(_newTextBlock(''));
    }
    return blocks;
  }

  _MixedBlock _newTextBlock(String text) {
    final block = _MixedBlock.text(id: _nextBlockId++, initialText: text);
    block.controller!.addListener(() => _trackCaret(block));
    return block;
  }

  /// يسجّل الخانة النصية نشطةً بموضع مؤشّرها الحالي (يتغيّر مع الكتابة
  /// والتحريك) — فلا تحتاج الواجهة أزرار «نص جديد» ولا مواضع يدوية.
  void _trackCaret(_MixedBlock block) {
    final controller = block.controller!;
    block.text = controller.text;
    final selection = controller.selection;
    final caret = selection.isValid &&
            selection.baseOffset >= 0 &&
            selection.baseOffset <= controller.text.length
        ? selection.baseOffset
        : controller.text.length;
    _activeText = block;
    _activeCaret = caret;
  }

  _MixedBlock? get _lastTextBlock =>
      _blocks.isEmpty ? null : _blocks.lastWhere((block) => block.isText);

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
      buffer.write(block.isBlock ? '\$\$${latex}\$\$' : '\$${latex}\$');
    }
    return buffer.toString();
  }

  /// يدرج معادلة **عند مؤشر الكتابة** في الخانة النصية النشطة: النص يُقسم
  /// حول المؤشر وتستقر المعادلة في الفجوة — فإن كان المؤشر في نهاية نص
  /// فارغ أُضيفت بعده مباشرة.
  void _insertMathAtCaret() {
    setState(() {
      final target = _activeText ?? _lastTextBlock;
      if (target == null) {
        _blocks.add(_newTextBlock(''));
        _blocks.add(_MixedBlock.math(id: _nextBlockId++, latex: '', isBlock: false));
        return;
      }
      final index = _blocks.indexOf(target);
      final caret = _activeCaret.clamp(0, target.text.length);
      final pre = target.text.substring(0, caret);
      final post = target.text.substring(caret);
      final math = _MixedBlock.math(id: _nextBlockId++, latex: '', isBlock: false);
      // الخانة النشطة تحتفظ بما قبل المؤشر (وتبقى قابلة للكتابة وإن فرغت)،
      // وما بعده يصبح خانة تكملة — فلا يُفقد حرف ولا يُتلف متحكم حيّ.
      _setText(target, pre);
      _blocks.insertAll(index + 1, <_MixedBlock>[
        math,
        if (post.isNotEmpty) _newTextBlock(post),
      ]);
      _activeText = null;
      _activeCaret = 0;
    });
  }

  /// يكتب قيمة جديدة في خانة نصية بمؤشر في آخرها (المستمع يتبع المؤشر
  /// وحده فيحدّث موضع الإدراج التالي تلقائياً).
  void _setText(_MixedBlock block, String value) {
    block.text = value;
    final controller = block.controller!;
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  /// متحكمات الأقسام المدموجة تُحرَّر بعد اكتمال الإطار (كانت مربوطة بحقل
  /// ما زال في الشجرة لحظة الدمج) — تفريغ آمن بلا استخدام بعد التحرير.
  final List<_MixedBlock> _pendingDisposal = <_MixedBlock>[];
  bool _disposalScheduled = false;

  void _scheduleDisposal(_MixedBlock block) {
    _pendingDisposal.add(block);
    if (_disposalScheduled || !mounted) {
      return;
    }
    _disposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposalScheduled = false;
      if (!mounted) {
        return;
      }
      for (final pending in _pendingDisposal) {
        pending.dispose();
      }
      _pendingDisposal.clear();
    });
  }

  /// حذف معادلة: إن حُصرت بين قسمَي نص دُمجا قسماً واحداً — فالنص الرئيسي
  /// يبقى متصلاً كما كُتب، ولا تتكدس خانات فارغة.
  void _removeMath(int index) {
    if (index < 0 || index >= _blocks.length || _blocks[index].isText) {
      return;
    }
    setState(() {
      _blocks.removeAt(index);
      if (index > 0 &&
          index < _blocks.length &&
          _blocks[index - 1].isText &&
          _blocks[index].isText) {
        final first = _blocks[index - 1];
        final second = _blocks[index];
        _setText(first, first.text + second.text);
        _blocks.removeAt(index);
        _scheduleDisposal(second);
        if (identical(_activeText, second)) {
          _activeText = first;
        }
      }
      if (!_blocks.any((block) => block.isText)) {
        _blocks.add(_newTextBlock(''));
      }
    });
  }

  void _moveBlock(int index, int delta) {
    final target = index + delta;
    if (index < 0 ||
        index >= _blocks.length ||
        target < 0 ||
        target >= _blocks.length ||
        _blocks[index].isText) {
      return;
    }
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(target, block);
    });
  }

  void _save() {
    final hasEquation =
        _blocks.any((block) => !block.isText && block.latex.trim().isNotEmpty);
    final text =
        _blocks.where((block) => block.isText).map((b) => b.text).join().trim();
    if (!hasEquation && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المحتوى فارغ — اكتب النص أو أضف معادلة أولاً.')),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _insertMathAtCaret,
                icon: const Icon(Icons.functions, size: 18),
                label: const Text('إضافة معادلة'),
              ),
              const SizedBox(height: 4),
              const Text(
                'تُدرج المعادلة عند مؤشر الكتابة داخل النص — انقر داخل النص '
                'حدّد موضعها ثم أضفها.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
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
    final isFirstText = block.isText && _blocks.take(index + 1).where((b) => b.isText).length == 1;
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
                    ? (isFirstText ? 'النص الرئيسي' : 'تكملة النص')
                    : (block.isBlock ? 'معادلة منفردة' : 'معادلة سطرية'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (!block.isText) ...<Widget>[
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
                  tooltip: 'حذف المعادلة',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => _removeMath(index),
                ),
              ],
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
    final unsupported = LatexSvgRenderer.unsupportedCharacters(block.latex);
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
                  'معادلة فارغة — ابنِها من الشريط أدناه.',
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
        if (unsupported.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'لا يرسم خط الرياضيات: ${unsupported.join('، ')} — ستُطبع نصاً بديلاً.',
              style: const TextStyle(color: Colors.orange, fontSize: 11),
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

  void dispose() => controller?.dispose();
}
