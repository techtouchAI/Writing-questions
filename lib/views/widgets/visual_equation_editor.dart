import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/equation_model.dart';
import '../../models/tex_content.dart';
import 'safe_math_tex.dart';

/// يفتح محرر المعادلات المرئي (بأسلوب Word) ويعيد المقطع الجاهز للإدراج.
///
/// النتيجة `$...$` (سطرية) أو `$$...$$` (منفردة) تُدرَج في الحقل النشط،
/// أو `null` عند الإلغاء. [initialLatex] يحمّل معادلة موجودة للتحرير
/// المرئي — والمستخدم لا يرى LaTeX الخام إطلاقاً أثناء التحرير.
Future<String?> showVisualEquationEditor({
  required BuildContext context,
  String? initialLatex,
  bool initialIsBlock = false,
  String saveLabel = 'إدراج',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: VisualEquationEditor(
          initialLatex: initialLatex ?? '',
          initialIsBlock: initialIsBlock,
          saveLabel: saveLabel,
        ),
      ),
    ),
  );
}

/// يختار المستخدم إحدى صيغ الحقل لتحريرها مرئياً (عند تعددها).
Future<TexMathSpan?> showEquationSpanPicker({
  required BuildContext context,
  required List<TexMathSpan> spans,
}) {
  return showModalBottomSheet<TexMathSpan>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'اختر المعادلة لتحريرها',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          for (final span in spans)
            ListTile(
              title: Directionality(
                textDirection: TextDirection.ltr,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: span.latex.trim().isEmpty
                      ? const Text('(معادلة فارغة)')
                      : SafeMathTex(
                          span.latex,
                          mathStyle: MathStyle.text,
                          textStyle: const TextStyle(fontSize: 17),
                        ),
                ),
              ),
              subtitle: Text(span.isBlock ? 'معادلة منفردة' : 'معادلة سطرية'),
              leading: const Icon(Icons.functions),
              onTap: () => Navigator.of(sheetContext).pop(span),
            ),
        ],
      ),
    ),
  );
}

/// محرر معادلات مرئي: بنى قابلة للنقر والتحرير (بسط/مقام، جذور، أسس...)
/// مع معاينة حية تُحدَّث فوراً — وLaTeX يبقى تمثيلاً داخلياً فقط.
///
/// يُستعمل في وضعين:
/// - **حوار مستقل** ([embedded] = false): أزرار «إلغاء/حفظ» تُعيد المقطع
///   الجاهز `$...$` أو `$$...$$` إلى من فتحه.
/// - **مضمَّن** ([embedded] = true): بلا حوار ولا أزرار، يبلغ عن الصيغة
///   الحالية عبر [onChanged] ليستعملها محرر المحتوى المختلط
///   (`mixed_content_editor.dart`) داخل قائمة أقسام المتن.
class VisualEquationEditor extends StatefulWidget {
  const VisualEquationEditor({
    super.key,
    required this.initialLatex,
    this.initialIsBlock = false,
    this.saveLabel = 'إدراج',
    this.embedded = false,
    this.onChanged,
  });

  final String initialLatex;
  final bool initialIsBlock;
  final String saveLabel;

  /// مضمَّن داخل محرر آخر: بلا ترويسة/معاينة/أزرار حفظ.
  final bool embedded;

  /// يُبلَّغ بعد كل تعديل بالصيغة الحالية (وضع التحليل المضمَّن).
  final void Function(String latex, bool isBlock)? onChanged;

  @override
  State<VisualEquationEditor> createState() => _VisualEquationEditorState();
}

class _VisualEquationEditorState extends State<VisualEquationEditor> {
  late EquationModel _model;
  late bool _isBlock;
  final Map<EqText, TextEditingController> _controllers = {};
  final Map<EqText, FocusNode> _foci = {};
  EqText? _activeText;

  @override
  void initState() {
    super.initState();
    _model = EquationModel.parse(widget.initialLatex);
    _isBlock = widget.initialIsBlock;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focus in _foci.values) {
      focus.dispose();
    }
    super.dispose();
  }

  String get _latex => _model.toLatex();

  // ---------------------------------------------------------- تحكمات النص

  TextEditingController _controllerFor(EqText node) {
    return _controllers.putIfAbsent(node, () {
      final controller = TextEditingController(text: node.text);
      controller.addListener(() {
        node.text = controller.text;
        if (mounted) {
          setState(() {});
        }
      });
      return controller;
    });
  }

  FocusNode _focusFor(EqText node) {
    return _foci.putIfAbsent(node, () {
      final focus = FocusNode();
      focus.addListener(() {
        if (focus.hasFocus && mounted) {
          setState(() => _activeText = node);
        }
      });
      return focus;
    });
  }

  void _focusAfterBuild(EqText node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusFor(node).requestFocus();
      }
    });
  }

  void _disposeTextNode(EqText node) {
    _controllers.remove(node)?.dispose();
    _foci.remove(node)?.dispose();
    if (identical(_activeText, node)) {
      _activeText = null;
    }
  }

  void _disposeSubtree(EqNode node) {
    if (node is EqText) {
      _disposeTextNode(node);
      return;
    }
    for (final slot in _slotsOf(node)) {
      for (final child in List<EqNode>.of(slot)) {
        _disposeSubtree(child);
      }
    }
  }

  /// خانات العقدة البنيوية (بسط/مقام، جسم/دليل...) — فارغة للنص.
  List<List<EqNode>> _slotsOf(EqNode node) {
    if (node is EqFraction) {
      return <List<EqNode>>[node.numerator, node.denominator];
    }
    if (node is EqSqrt) {
      return <List<EqNode>>[node.body, node.root];
    }
    if (node is EqSup) {
      return <List<EqNode>>[node.base, node.exponent];
    }
    if (node is EqSub) {
      return <List<EqNode>>[node.base, node.subscript];
    }
    if (node is EqFence) {
      return <List<EqNode>>[node.body];
    }
    if (node is EqAccent) {
      return <List<EqNode>>[node.body];
    }
    if (node is EqGroup) {
      return <List<EqNode>>[node.children];
    }
    return const <List<EqNode>>[];
  }

  /// يحدد القائمة الحاوية وفهرس [target] داخلها (أو null عند حذفها).
  (List<EqNode>, int)? _locate(EqText target) {
    (List<EqNode>, int)? found;
    void search(List<EqNode> list) {
      for (var index = 0; index < list.length; index++) {
        final node = list[index];
        if (identical(node, target)) {
          found = (list, index);
          return;
        }
        for (final slot in _slotsOf(node)) {
          search(slot);
          if (found != null) {
            return;
          }
        }
      }
    }

    search(_model.nodes);
    return found;
  }

  // ---------------------------------------------------------- الإدراج

  /// يدرج رمزاً/أمراً (`\alpha`، `+`...) عند المؤشر في الخانة النشطة.
  void _insertSymbol(String latex) {
    final target = _activeText;
    final located = target == null ? null : _locate(target);
    if (target == null || located == null) {
      final fresh = EqText(latex);
      setState(() {
        _model.nodes.add(fresh);
        _activeText = fresh;
      });
      _focusAfterBuild(fresh);
      return;
    }
    final controller = _controllerFor(target);
    final text = controller.text;
    final selection = controller.selection;
    if (selection.isValid && selection.start >= 0 && selection.end <= text.length) {
      controller.text = text.replaceRange(selection.start, selection.end, latex);
      controller.selection =
          TextSelection.collapsed(offset: selection.start + latex.length);
    } else {
      controller.text = text + latex;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
  }

  /// يدرج بنية (كسر، جذر...) مكان المؤشر: يقسم نص الخانة النشطة
  /// حول المؤشر ويضع البنية بينهما، ثم ينقل التركيز إلى [focusTarget].
  void _insertStructure(EqNode node, EqText focusTarget) {
    final target = _activeText;
    final located = target == null ? null : _locate(target);
    if (target == null || located == null) {
      setState(() {
        _model.nodes.add(node);
        _activeText = focusTarget;
      });
      _focusAfterBuild(focusTarget);
      return;
    }
    final (list, index) = located;
    final controller = _controllerFor(target);
    final text = controller.text;
    var start = text.length;
    var end = text.length;
    final selection = controller.selection;
    if (selection.isValid && selection.start >= 0 && selection.end <= text.length) {
      start = selection.start;
      end = selection.end;
    }
    final pre = text.substring(0, start);
    final post = text.substring(end);
    setState(() {
      list
        ..removeAt(index)
        ..insertAll(index, <EqNode>[
          if (pre.isNotEmpty) EqText(pre),
          node,
          if (post.isNotEmpty) EqText(post),
        ]);
      _disposeTextNode(target);
      _activeText = focusTarget;
    });
    _focusAfterBuild(focusTarget);
  }

  /// يدرج أسّاً/دليلاً: التحديد الحالي يصبح القاعدة، والتركيز للدليل.
  void _insertScript({required bool superscript}) {
    EqNode build(EqText base, EqText script) => superscript
        ? EqSup(base: <EqNode>[base], exponent: <EqNode>[script])
        : EqSub(base: <EqNode>[base], subscript: <EqNode>[script]);

    final target = _activeText;
    final located = target == null ? null : _locate(target);
    final script = EqText('');
    if (target == null || located == null) {
      setState(() {
        _model.nodes.add(build(EqText(''), script));
        _activeText = script;
      });
      _focusAfterBuild(script);
      return;
    }
    final (list, index) = located;
    final controller = _controllerFor(target);
    final text = controller.text;
    var start = text.length;
    var end = text.length;
    final selection = controller.selection;
    if (selection.isValid && selection.start >= 0 && selection.end <= text.length) {
      start = selection.start;
      end = selection.end;
    }
    final pre = text.substring(0, start);
    final selected = text.substring(start, end);
    final post = text.substring(end);
    setState(() {
      list
        ..removeAt(index)
        ..insertAll(index, <EqNode>[
          if (pre.isNotEmpty) EqText(pre),
          build(EqText(selected), script),
          if (post.isNotEmpty) EqText(post),
        ]);
      _disposeTextNode(target);
      _activeText = script;
    });
    _focusAfterBuild(script);
  }

  void _addFraction() {
    final numerator = EqText('');
    final denominator = EqText('');
    _insertStructure(
      EqFraction(numerator: <EqNode>[numerator], denominator: <EqNode>[denominator]),
      numerator,
    );
  }

  void _addSqrt({required bool withRoot}) {
    final body = EqText('');
    _insertStructure(
      EqSqrt(
        body: <EqNode>[body],
        root: withRoot ? <EqNode>[EqText('')] : <EqNode>[],
      ),
      body,
    );
  }

  void _addFence(String left, String right) {
    final body = EqText('');
    _insertStructure(EqFence(left: left, right: right, body: <EqNode>[body]), body);
  }

  void _addAccent(EqAccentKind kind) {
    final body = EqText('');
    _insertStructure(EqAccent(kind: kind, body: <EqNode>[body]), body);
  }

  void _removeNode(List<EqNode> parent, int index) {
    setState(() {
      _disposeSubtree(parent[index]);
      parent.removeAt(index);
      if (_activeText != null && _locate(_activeText!) == null) {
        _activeText = null;
      }
    });
  }

  void _save() {
    final latex = _latex.trim();
    if (latex.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المعادلة فارغة — أضف محتوى أولاً.')),
      );
      return;
    }
    Navigator.of(context).pop(_isBlock ? '\$\$$latex\$\$' : '\$$latex\$');
  }

  // ---------------------------------------------------------- البناء

  /// يبلّغ الوالد المضمَّن بالصيغة الحالية بعد اكتمال الإطار (لا أثناء البناء).
  void _scheduleNotify() {
    final onChanged = widget.onChanged;
    if (!widget.embedded || onChanged == null) {
      return;
    }
    final latex = _latex.trim();
    final isBlock = _isBlock;
    if (latex == _lastNotifiedLatex && isBlock == _lastNotifiedBlock) {
      return;
    }
    _lastNotifiedLatex = latex;
    _lastNotifiedBlock = isBlock;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onChanged?.call(latex, isBlock);
      }
    });
  }

  String? _lastNotifiedLatex;
  bool? _lastNotifiedBlock;

  @override
  Widget build(BuildContext context) {
    _scheduleNotify();
    final blockSwitch = SegmentedButton<bool>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          label: Text('سطرية', style: TextStyle(fontSize: 12)),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('منفردة', style: TextStyle(fontSize: 12)),
        ),
      ],
      selected: <bool>{_isBlock},
      onSelectionChanged: (selection) =>
          setState(() => _isBlock = selection.single),
    );
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 4 : 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.embedded)
              Row(
                children: <Widget>[
                  const Text('المعادلة:', style: TextStyle(fontSize: 12)),
                  const Spacer(),
                  blockSwitch,
                ],
              )
            else
              Row(
                children: <Widget>[
                  const Icon(Icons.functions),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'محرر المعادلات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  blockSwitch,
                ],
              ),
            const SizedBox(height: 10),
            if (!widget.embedded) ...[
              _buildPreview(context),
              const SizedBox(height: 10),
            ],
            _buildModelArea(context),
            const SizedBox(height: 10),
            _buildToolbar(context),
            if (!widget.embedded) ...[
              const SizedBox(height: 12),
              Row(
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
                      child: Text(widget.saveLabel),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// المعاينة الحية: تُحدَّث مع كل ضربة زر دون انتظار الحفظ.
  Widget _buildPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latex = _latex;
    final openBraces = '{'.allMatches(latex).length;
    final closeBraces = '}'.allMatches(latex).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (latex.trim().isEmpty)
            const Text(
              'ستظهر المعادلة هنا أثناء البناء...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            )
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Center(
                  child: SafeMathTex(
                    latex,
                    mathStyle: _isBlock ? MathStyle.display : MathStyle.text,
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          if (openBraces != closeBraces)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'تحقق من تطابق الأقواس { } — المعاينة قد لا تكتمل.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  /// منطقة البناء البصري: البنى قابلة للنقر والتحرير في مواضعها.
  Widget _buildModelArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_model.nodes.isEmpty) {
      return GestureDetector(
        onTap: () {
          final fresh = EqText('');
          setState(() {
            _model.nodes.add(fresh);
            _activeText = fresh;
          });
          _focusAfterBuild(fresh);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: const Text(
            'انقر هنا للكتابة، أو ابنِ المعادلة من الشريط أدناه.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: _buildSequence(_model.nodes),
    );
  }

  Widget _buildSequence(List<EqNode> nodes) {
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (var index = 0; index < nodes.length; index++)
          _buildNode(nodes[index], nodes, index),
      ],
    );
  }

  Widget _buildNode(EqNode node, List<EqNode> parent, int index) {
    if (node is EqText) {
      return _buildTextSlot(node);
    }
    if (node is EqFraction) {
      return _deletable(
        parent,
        index,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildSlotBox(node.numerator),
            Container(height: 1.5, width: 64, color: Colors.black87),
            _buildSlotBox(node.denominator),
          ],
        ),
      );
    }
    if (node is EqSqrt) {
      return _deletable(
        parent,
        index,
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (node.root.isNotEmpty) _buildSlotBox(node.root, small: true),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('√', style: TextStyle(fontSize: 22)),
            ),
            _buildSlotBox(node.body),
          ],
        ),
      );
    }
    if (node is EqSup) {
      return _deletable(
        parent,
        index,
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildSlotBox(node.base),
            Transform.translate(
              offset: const Offset(0, -8),
              child: _buildSlotBox(node.exponent, small: true),
            ),
          ],
        ),
      );
    }
    if (node is EqSub) {
      return _deletable(
        parent,
        index,
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            _buildSlotBox(node.base),
            Transform.translate(
              offset: const Offset(0, 8),
              child: _buildSlotBox(node.subscript, small: true),
            ),
          ],
        ),
      );
    }
    if (node is EqFence) {
      return _deletable(
        parent,
        index,
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              _fenceDisplay(node.left),
              style: const TextStyle(fontSize: 22),
            ),
            _buildSlotBox(node.body),
            Text(
              _fenceDisplay(node.right),
              style: const TextStyle(fontSize: 22),
            ),
          ],
        ),
      );
    }
    if (node is EqAccent) {
      return _deletable(
        parent,
        index,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _accentMark(node.kind),
            _buildSlotBox(node.body),
          ],
        ),
      );
    }
    if (node is EqGroup) {
      return _deletable(
        parent,
        index,
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: _buildSequence(node.children),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// علامة بصرية فوق خانة المتغير: سهم/قبعة/خط — نفس معنى الأمر المخزَّن.
  Widget _accentMark(EqAccentKind kind) {
    switch (kind) {
      case EqAccentKind.vector:
        return const Icon(Icons.arrow_forward, size: 16);
      case EqAccentKind.hat:
        return const Icon(Icons.expand_less, size: 16);
      case EqAccentKind.bar:
        return Container(
          height: 2,
          width: 26,
          margin: const EdgeInsets.only(bottom: 2),
          color: Colors.black87,
        );
    }
  }

  /// خانة تحرير نصية داخل بنية: انقر واكتب، والعرض يتحدث حياً.
  Widget _buildTextSlot(EqText node) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _controllerFor(node);
    final active = identical(_activeText, node);
    final width = (42 + controller.text.length * 9.0).clamp(42.0, 200.0);
    return GestureDetector(
      onTap: () {
        setState(() => _activeText = node);
        _focusFor(node).requestFocus();
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colorScheme.primaryContainer.withOpacity(0.4) : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outlineVariant,
            width: active ? 1.6 : 1,
          ),
        ),
        child: TextField(
          controller: controller,
          focusNode: _focusFor(node),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          // كتابة رياضية خالصة: بلا تصحيح تلقائي ولا اقتراحات لوحة المفاتيح
          // (كانا يحوّلان «x2» إلى كلمات ويقطعان الأرقام المتعددة).
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration.collapsed(hintText: '?'),
        ),
      ),
    );
  }

  /// صندوق خانة بنيوية (بسط، مقام، جسم جذر...) يحتضن متتالية.
  Widget _buildSlotBox(List<EqNode> slot, {bool small = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    if (slot.isEmpty) {
      return GestureDetector(
        onTap: () {
          final fresh = EqText('');
          setState(() {
            slot.add(fresh);
            _activeText = fresh;
          });
          _focusAfterBuild(fresh);
        },
        child: Container(
          width: small ? 30 : 46,
          height: small ? 26 : 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.grey),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: _buildSequence(slot),
    );
  }

  /// يغلّف بنية بزر حذف صغير (النص يُحرَّر ولا يُحذَف بزر).
  Widget _deletable(List<EqNode> parent, int index, Widget child) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: child,
        ),
        Positioned(
          left: -6,
          top: -6,
          child: GestureDetector(
            onTap: () => _removeNode(parent, index),
            child: const CircleAvatar(
              radius: 9,
              backgroundColor: Colors.red,
              child: Icon(Icons.close, size: 11, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// يعرض المحدد الرياضي بصرياً (`\left(` ← `(`، `\{` ← `{`).
  String _fenceDisplay(String delimiter) {
    return delimiter
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '')
        .replaceAll(r'\{', '{')
        .replaceAll(r'\}', '}')
        .trim();
  }

  // ---------------------------------------------------------- شريط الأدوات

  Widget _buildToolbar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _toolRow(context, 'البنى', <_Tool>[
          _Tool('كسر', _addFraction),
          _Tool('√', () => _addSqrt(withRoot: false)),
          _Tool('ⁿ√', () => _addSqrt(withRoot: true)),
          _Tool('x²', () => _insertScript(superscript: true)),
          _Tool('x₁', () => _insertScript(superscript: false)),
          // أقواس متكيفة: تُحفظ بـ\left...\right فيرسمها محرك الـ PDF
          // بارتفاع محتواها (كسر داخل قوسين يبقى داخلهما).
          _Tool('( )', () => _addFence(r'\left(', r'\right)')),
          _Tool('[ ]', () => _addFence(r'\left[', r'\right]')),
          _Tool('{ }', () => _addFence(r'\left\{', r'\right\}')),
          _Tool('→فوق', () => _addAccent(EqAccentKind.vector)),
          _Tool('ˆفوق', () => _addAccent(EqAccentKind.hat)),
          _Tool('―فوق', () => _addAccent(EqAccentKind.bar)),
        ]),
        // الرموز تُدرَج بمحارفها المرئية (×، α...) لا بأوامر LaTeX:
        // المستخدم لا يرى أي كود في أي مرحلة، والمحارف ترسمها كل المحركات
        // (الشاشة والـ PDF وWord) بالشكل نفسه.
        _toolRow(context, 'العمليات', <_Tool>[
          _Tool('+', () => _insertSymbol('+')),
          _Tool('−', () => _insertSymbol('−')),
          _Tool('×', () => _insertSymbol('×')),
          _Tool('÷', () => _insertSymbol('÷')),
          _Tool('/', () => _insertSymbol('/')),
          _Tool('·', () => _insertSymbol('·')),
          _Tool('±', () => _insertSymbol('±')),
          _Tool('∫', () => _insertSymbol('∫')),
          _Tool('∑', () => _insertSymbol('∑')),
        ]),
        _toolRow(context, 'العلاقات', <_Tool>[
          _Tool('=', () => _insertSymbol('=')),
          _Tool('<', () => _insertSymbol('<')),
          _Tool('>', () => _insertSymbol('>')),
          _Tool('≤', () => _insertSymbol('≤')),
          _Tool('≥', () => _insertSymbol('≥')),
          _Tool('≠', () => _insertSymbol('≠')),
          _Tool('≈', () => _insertSymbol('≈')),
          _Tool('∞', () => _insertSymbol('∞')),
          _Tool('→', () => _insertSymbol('→')),
          _Tool('«»', () => _insertSymbol('«»')),
        ]),
        _toolRow(context, 'اليونانية', <_Tool>[
          _Tool('α', () => _insertSymbol('α')),
          _Tool('β', () => _insertSymbol('β')),
          _Tool('γ', () => _insertSymbol('γ')),
          _Tool('δ', () => _insertSymbol('δ')),
          _Tool('θ', () => _insertSymbol('θ')),
          _Tool('λ', () => _insertSymbol('λ')),
          _Tool('μ', () => _insertSymbol('μ')),
          _Tool('π', () => _insertSymbol('π')),
          _Tool('σ', () => _insertSymbol('σ')),
          _Tool('φ', () => _insertSymbol('φ')),
          _Tool('ω', () => _insertSymbol('ω')),
          _Tool('Ω', () => _insertSymbol('Ω')),
        ]),
        _toolRow(context, 'تحرير', <_Tool>[
          _Tool('⌫ حذف الأخير', () {
            if (_model.nodes.isNotEmpty) {
              setState(() {
                _disposeSubtree(_model.nodes.removeLast());
                if (_activeText != null && _locate(_activeText!) == null) {
                  _activeText = null;
                }
              });
            }
          }),
          _Tool('مسح الكل', () {
            setState(() {
              for (final node in _model.nodes) {
                _disposeSubtree(node);
              }
              _model.nodes.clear();
              _activeText = null;
            });
          }),
        ]),
      ],
    );
  }

  Widget _toolRow(BuildContext context, String label, List<_Tool> tools) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final tool in tools)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: tool.onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant),
                        color: colorScheme.surface,
                      ),
                      child: Text(
                        tool.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// زر واحد في شريط أدوات المعادلات: [label] للعرض و[onTap] للإدراج.
class _Tool {
  const _Tool(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
