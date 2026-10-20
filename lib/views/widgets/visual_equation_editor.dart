import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.model,
    required this.activeLeafId,
    required this.caretOffset,
  });

  final EquationModel model;
  final String? activeLeafId;
  final int caretOffset;
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
  static const int _maxHistory = 80;
  static final RegExp _trailingAtomPattern = RegExp(r'([A-Za-z0-9.]+)$');

  late EquationModel _model;
  late bool _isBlock;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _foci = <String, FocusNode>{};
  final List<TextEditingController> _retiredControllers =
      <TextEditingController>[];
  final List<FocusNode> _retiredFoci = <FocusNode>[];
  bool _cleanupScheduled = false;
  bool _suppressControllerHistory = false;

  EqText? _activeText;
  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];

  @override
  void initState() {
    super.initState();
    _model = EquationModel.parse(widget.initialLatex);
    _isBlock = widget.initialIsBlock;
    final leaves = _model.allLeafTextSlots();
    if (leaves.isNotEmpty) {
      _activeText = leaves.last;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focus in _foci.values) {
      focus.dispose();
    }
    for (final controller in _retiredControllers) {
      controller.dispose();
    }
    for (final focus in _retiredFoci) {
      focus.dispose();
    }
    _controllers.clear();
    _foci.clear();
    _retiredControllers.clear();
    _retiredFoci.clear();
    super.dispose();
  }

  String get _latex => _model.toLatex();

  // ---------------------------------------------------------- سجل التراجع

  int _currentCaretOffset() {
    final active = _activeText;
    if (active == null) return 0;
    final controller = _controllers[active.id];
    if (controller == null || !controller.selection.isValid) {
      return active.text.length;
    }
    return controller.selection.extentOffset.clamp(0, controller.text.length);
  }

  void _recordUndoSnapshot() {
    _undoStack.add(
      _EditorSnapshot(
        model: _model.clone(preserveIds: true),
        activeLeafId: _activeText?.id,
        caretOffset: _currentCaretOffset(),
      ),
    );
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    _suppressControllerHistory = true;
    try {
      setState(() {
        _model = snapshot.model.clone(preserveIds: true);
        // تحديث نصوص المتحكمات القائمة وإنعاش المؤشر بأمان دون هدم الهوية.
        final liveIds = <String>{};
        for (final leaf in _model.allLeafTextSlots()) {
          liveIds.add(leaf.id);
          final existing = _controllers[leaf.id];
          if (existing != null && existing.text != leaf.text) {
            existing.text = leaf.text;
          }
        }
        final staleIds = _controllers.keys
            .where((id) => !liveIds.contains(id))
            .toList(growable: false);
        for (final id in staleIds) {
          _retireId(id);
        }
        EqText? restoredActive;
        if (snapshot.activeLeafId != null) {
          final loc = _model.locateById(snapshot.activeLeafId!);
          if (loc != null && loc.node is EqText) {
            restoredActive = loc.node as EqText;
          }
        }
        restoredActive ??= _model.allLeafTextSlots().isEmpty
            ? null
            : _model.allLeafTextSlots().last;
        _activeText = restoredActive;
      });
    } finally {
      _suppressControllerHistory = false;
    }
    if (_activeText != null) {
      _focusAfterBuild(_activeText!, caretOffset: snapshot.caretOffset);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final current = _EditorSnapshot(
      model: _model.clone(preserveIds: true),
      activeLeafId: _activeText?.id,
      caretOffset: _currentCaretOffset(),
    );
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _restoreSnapshot(previous);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final current = _EditorSnapshot(
      model: _model.clone(preserveIds: true),
      activeLeafId: _activeText?.id,
      caretOffset: _currentCaretOffset(),
    );
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _restoreSnapshot(next);
  }

  // ---------------------------------------------------------- تحكمات النص

  TextEditingController _controllerFor(EqText node) {
    final existing = _controllers[node.id];
    if (existing != null) {
      if (existing.text != node.text) {
        _suppressControllerHistory = true;
        final prevSelection = existing.selection;
        existing.text = node.text;
        if (prevSelection.isValid) {
          existing.selection = TextSelection.collapsed(
            offset: prevSelection.extentOffset.clamp(0, node.text.length),
          );
        }
        _suppressControllerHistory = false;
      }
      return existing;
    }
    final controller = TextEditingController(text: node.text);
    controller.addListener(() {
      final latestLoc = _model.locateById(node.id);
      final targetNode =
          latestLoc != null && latestLoc.node is EqText
              ? latestLoc.node as EqText
              : node;
      if (targetNode.text == controller.text) {
        return;
      }
      if (!_suppressControllerHistory) {
        _recordUndoSnapshot();
      }
      targetNode.text = controller.text;
      if (mounted) {
        setState(() {});
      }
    });
    _controllers[node.id] = controller;
    return controller;
  }

  KeyEventResult _handleSlotKeyEvent(EqText node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final controller = _controllers[node.id];
    if (controller == null || !controller.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final offset = controller.selection.extentOffset;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        offset >= controller.text.length) {
      _stepNextOrExit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && offset <= 0) {
      _stepPrevious();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  FocusNode _focusFor(EqText node) {
    return _foci.putIfAbsent(node.id, () {
      late final FocusNode focus;
      focus = FocusNode(
        onKeyEvent: (_, event) {
          final loc = _model.locateById(node.id);
          final live =
              loc != null && loc.node is EqText ? loc.node as EqText : node;
          return _handleSlotKeyEvent(live, event);
        },
      );
      focus.addListener(() {
        if (focus.hasFocus && mounted) {
          final loc = _model.locateById(node.id);
          final live =
              loc != null && loc.node is EqText ? loc.node as EqText : node;
          if (!identical(_activeText, live)) {
            setState(() => _activeText = live);
          }
        }
      });
      return focus;
    });
  }

  void _focusAfterBuild(EqText node, {int? caretOffset}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controllerFor(node);
      final targetOffset =
          (caretOffset ?? controller.text.length).clamp(0, controller.text.length);
      controller.selection = TextSelection.collapsed(offset: targetOffset);
      _focusFor(node).requestFocus();
    });
  }

  void _scheduleCleanup() {
    if (_cleanupScheduled) return;
    _cleanupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cleanupScheduled = false;
      for (final controller in _retiredControllers) {
        controller.dispose();
      }
      for (final focus in _retiredFoci) {
        focus.dispose();
      }
      _retiredControllers.clear();
      _retiredFoci.clear();
    });
  }

  void _retireId(String id) {
    final controller = _controllers.remove(id);
    if (controller != null) {
      _retiredControllers.add(controller);
    }
    final focus = _foci.remove(id);
    if (focus != null) {
      _retiredFoci.add(focus);
    }
    if (_retiredControllers.isNotEmpty || _retiredFoci.isNotEmpty) {
      _scheduleCleanup();
    }
  }

  void _disposeTextNode(EqText node) {
    _retireId(node.id);
    if (_activeText?.id == node.id) {
      _activeText = null;
    }
  }

  void _disposeSubtree(EqNode node) {
    if (node is EqText) {
      _disposeTextNode(node);
      return;
    }
    for (final slot in node.slots) {
      for (final child in List<EqNode>.of(slot)) {
        _disposeSubtree(child);
      }
    }
  }

  (List<EqNode>, int)? _locate(EqText target) {
    final loc = _model.locateById(target.id);
    if (loc == null) return null;
    return (loc.parentList, loc.index);
  }

  // ---------------------------------------------------------- التنقل والمكوّنات

  void _stepNextOrExit() {
    _recordUndoSnapshot();
    late EqText nextTarget;
    setState(() {
      nextTarget = _model.stepNextOrExit(_activeText?.id);
      _activeText = nextTarget;
    });
    _focusAfterBuild(nextTarget, caretOffset: nextTarget.text.length);
  }

  void _stepPrevious() {
    final prevTarget = _model.stepPrevious(_activeText?.id);
    if (prevTarget == null) return;
    setState(() => _activeText = prevTarget);
    _focusAfterBuild(prevTarget, caretOffset: prevTarget.text.length);
  }

  void _insertSlotBeforeActive() {
    _recordUndoSnapshot();
    late EqText slot;
    setState(() {
      slot = _model.insertSlotBefore(_activeText?.id);
      _activeText = slot;
    });
    _focusAfterBuild(slot, caretOffset: 0);
  }

  void _insertSlotAfterActive() {
    _recordUndoSnapshot();
    late EqText slot;
    setState(() {
      slot = _model.insertSlotAfter(_activeText?.id);
      _activeText = slot;
    });
    _focusAfterBuild(slot, caretOffset: slot.text.length);
  }

  void _deleteActiveComponent() {
    if (_model.nodes.isEmpty) return;
    final activeId = _activeText?.id;
    final compound =
        activeId == null ? null : _model.enclosingCompound(activeId);
    if (compound != null) {
      final loc = _model.locateById(compound.id);
      if (loc != null) {
        _removeNode(loc.parentList, loc.index);
        return;
      }
    }
    if (activeId != null) {
      final loc = _model.locateById(activeId);
      if (loc != null) {
        _removeNode(loc.parentList, loc.index);
        return;
      }
    }
    _removeNode(_model.nodes, _model.nodes.length - 1);
  }

  // ---------------------------------------------------------- الإدراج

  /// يدرج رمزاً/أمراً (`\alpha`، `+`، `=`...) عند المؤشر في الخانة النشطة.
  void _insertSymbol(String latex) {
    final target = _activeText;
    final located = target == null ? null : _locate(target);
    if (target == null || located == null) {
      _recordUndoSnapshot();
      final fresh = EqText(latex);
      setState(() {
        _model.nodes.add(fresh);
        _activeText = fresh;
      });
      _focusAfterBuild(fresh, caretOffset: latex.length);
      return;
    }
    _recordUndoSnapshot();
    final controller = _controllerFor(target);
    final text = controller.text;
    final selection = controller.selection;
    _suppressControllerHistory = true;
    try {
      if (selection.isValid &&
          selection.start >= 0 &&
          selection.end <= text.length) {
        final nextOffset = selection.start + latex.length;
        controller.text =
            text.replaceRange(selection.start, selection.end, latex);
        controller.selection = TextSelection.collapsed(offset: nextOffset);
      } else {
        controller.text = text + latex;
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      }
    } finally {
      _suppressControllerHistory = false;
    }
  }

  /// يدرج بنية (كسر، جذر...) مكان المؤشر: يقسم نص الخانة النشطة
  /// حول المؤشر ويضع البنية بينهما، ثم ينقل التركيز إلى [focusTarget].
  void _insertStructure(EqNode node, EqText focusTarget) {
    _recordUndoSnapshot();
    final target = _activeText;
    final located = target == null ? null : _locate(target);
    if (target == null || located == null) {
      setState(() {
        _model.nodes.add(node);
        _activeText = focusTarget;
      });
      _focusAfterBuild(focusTarget, caretOffset: 0);
      return;
    }
    final (list, index) = located;
    final controller = _controllerFor(target);
    final text = controller.text;
    var start = text.length;
    var end = text.length;
    final selection = controller.selection;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length) {
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
    _focusAfterBuild(focusTarget, caretOffset: 0);
  }

  /// يدرج أسّاً/دليلاً:
  /// - إن وجد تحديد نصي: التحديد يصبح القاعدة.
  /// - إن كان المؤشر منفرداً بعد عدد/متغير (مثل `5` أو `5 + 6`): يُلتقط الحدّ
  ///   المباشر قبل المؤشر (`5` أو `6`) تلقائياً كقاعدة للأس وينتقل المؤشر للأس!
  /// - إن كانت الخانة فارغة بعد قوس/بنية مركبة: تُرفع تلك البنية قاعدةً.
  /// - إن كان المحرر فارغاً تماماً: تُنشأ خانتان للقاعدة والأس (`x²`).
  void _insertScript({required bool superscript}) {
    EqNode build(List<EqNode> base, EqText script) => superscript
        ? EqSup(base: base, exponent: <EqNode>[script])
        : EqSub(base: base, subscript: <EqNode>[script]);

    _recordUndoSnapshot();
    final target = _activeText;
    final located = target == null ? null : _locate(target);
    final script = EqText('');
    if (target == null || located == null) {
      final baseSlot = EqText('');
      setState(() {
        _model.nodes.add(build(<EqNode>[baseSlot], script));
        _activeText = script;
      });
      _focusAfterBuild(script, caretOffset: 0);
      return;
    }
    final (list, index) = located;
    final controller = _controllerFor(target);
    final text = controller.text;
    var start = text.length;
    var end = text.length;
    final selection = controller.selection;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length) {
      start = selection.start;
      end = selection.end;
    }
    var pre = text.substring(0, start);
    var selected = text.substring(start, end);
    final post = text.substring(end);

    // إذا كان المؤشر منفرداً بعد حدّ عددي/جبري (مثل كتابة `5` ثم نقر `x²`)،
    // نلتقط هذا الحدّ قاعدةً للأس مباشرةً بدل إنتاج `{}^{2}` فارغة القاعدة!
    if (selected.isEmpty && pre.isNotEmpty) {
      final atomMatch = _trailingAtomPattern.firstMatch(pre);
      if (atomMatch != null) {
        selected = atomMatch.group(1)!;
        pre = pre.substring(0, atomMatch.start);
      }
    }

    // إذا كانت الخانة فارغة وجاءت مباشرةً بعد بنية مركبة (مثل قوس أو جذر)،
    // نرفع البنية السابقة قاعدةً للأس.
    if (selected.isEmpty &&
        pre.isEmpty &&
        index > 0 &&
        list[index - 1] is! EqText) {
      final previousNode = list[index - 1];
      setState(() {
        list
          ..removeAt(index)
          ..removeAt(index - 1)
          ..insertAll(index - 1, <EqNode>[
            build(<EqNode>[previousNode], script),
            if (post.isNotEmpty) EqText(post),
          ]);
        _disposeTextNode(target);
        _activeText = script;
      });
      _focusAfterBuild(script, caretOffset: 0);
      return;
    }

    setState(() {
      list
        ..removeAt(index)
        ..insertAll(index, <EqNode>[
          if (pre.isNotEmpty) EqText(pre),
          build(<EqNode>[EqText(selected)], script),
          if (post.isNotEmpty) EqText(post),
        ]);
      _disposeTextNode(target);
      _activeText = script;
    });
    _focusAfterBuild(script, caretOffset: 0);
  }

  void _addFraction() {
    final numerator = EqText('');
    final denominator = EqText('');
    _insertStructure(
      EqFraction(
        numerator: <EqNode>[numerator],
        denominator: <EqNode>[denominator],
      ),
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
    _insertStructure(
      EqFence(left: left, right: right, body: <EqNode>[body]),
      body,
    );
  }

  void _addAccent(EqAccentKind kind) {
    final body = EqText('');
    _insertStructure(EqAccent(kind: kind, body: <EqNode>[body]), body);
  }

  void _removeNode(List<EqNode> parent, int index) {
    if (index < 0 || index >= parent.length) return;
    _recordUndoSnapshot();
    late ({EqText? focus, int caretOffset}) refocus;
    setState(() {
      _disposeSubtree(parent[index]);
      refocus = _model.removeComponentAndRefocus(parent, index);
      // اعتزال أي متحكم لخانة نصية دُمجت في جارتها اليسرى أثناء الالتحام.
      final liveIds =
          _model.allLeafTextSlots().map((leaf) => leaf.id).toSet();
      for (final id
          in _controllers.keys.where((k) => !liveIds.contains(k)).toList()) {
        _retireId(id);
      }
      _activeText = refocus.focus;
    });
    if (refocus.focus != null) {
      _focusAfterBuild(refocus.focus!, caretOffset: refocus.caretOffset);
    }
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

  String _activeScopeLabel() {
    final active = _activeText;
    if (active == null) return 'اختر خانة أو أضف بنية للبدء';
    final compound = _model.enclosingCompound(active.id);
    if (compound == null) return 'المسار الرئيسي للمعادلة';
    if (compound is EqSqrt) {
      final inDegree = compound.root.any((n) => n.id == active.id);
      return inDegree
          ? 'داخل دليل الجذر (اضغط «التالي / خروج ▶» للانتقال للجسم)'
          : 'داخل الجذر √ (اضغط «التالي / خروج ▶» لإكمال المعادلة بعد الجذر)';
    }
    if (compound is EqSup) {
      final inBase = compound.base.any((n) => n.id == active.id);
      return inBase
          ? 'داخل قاعدة الأس (اضغط «التالي / خروج ▶» للانتقال للأس)'
          : 'داخل الأس (اضغط «التالي / خروج ▶» لإكمال المعادلة بعد الأس)';
    }
    if (compound is EqSub) {
      return 'داخل الدليل السفلي (اضغط «التالي / خروج ▶» للخروج)';
    }
    if (compound is EqFraction) {
      final inNum = compound.numerator.any((n) => n.id == active.id);
      return inNum
          ? 'داخل البسط (اضغط «التالي / خروج ▶» للانتقال للمقام)'
          : 'داخل المقام (اضغط «التالي / خروج ▶» لإكمال المعادلة بعد الكسر)';
    }
    if (compound is EqFence) {
      return 'داخل الأقواس (اضغط «التالي / خروج ▶» للخروج بعد القوس)';
    }
    return 'داخل مكوّن فرعي';
  }

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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  blockSwitch,
                ],
              ),
            const SizedBox(height: 10),
            if (!widget.embedded) ...<Widget>[
              _buildPreview(context),
              const SizedBox(height: 10),
            ],
            _buildModelArea(context),
            const SizedBox(height: 8),
            _buildNavigationBar(context),
            const SizedBox(height: 10),
            _buildToolbar(context),
            if (!widget.embedded) ...<Widget>[
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

  /// شريط التنقل وإدارة المكوّنات: يتيح الخروج السلس من الجذر/الأس/الكسر
  /// والإدراج قبل/بعد أي مكوّن والتراجع/الإعادة دون لمس LaTeX الخام.
  Widget _buildNavigationBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inCompound =
        _activeText != null && _model.enclosingCompound(_activeText!.id) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _activeScopeLabel(),
          key: const Key('eq_scope_status'),
          style: TextStyle(
            fontSize: 11,
            color: inCompound ? colorScheme.primary : Colors.grey.shade700,
            fontWeight: inCompound ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            _navChip(
              context,
              key: const Key('eq_nav_prev'),
              label: '◀ السابق',
              onTap: _model.nodes.isEmpty ? null : _stepPrevious,
            ),
            _navChip(
              context,
              key: const Key('eq_nav_next'),
              label: 'التالي / خروج ▶',
              emphasized: inCompound,
              onTap: _stepNextOrExit,
            ),
            _navChip(
              context,
              key: const Key('eq_insert_before'),
              label: '+ قبل',
              onTap: _insertSlotBeforeActive,
            ),
            _navChip(
              context,
              key: const Key('eq_insert_after'),
              label: '+ بعد',
              onTap: _insertSlotAfterActive,
            ),
            _navChip(
              context,
              key: const Key('eq_delete_active'),
              label: 'حذف المكوّن',
              destructive: true,
              onTap: _model.nodes.isEmpty ? null : _deleteActiveComponent,
            ),
            _navChip(
              context,
              key: const Key('eq_undo'),
              label: 'تراجع',
              onTap: _undoStack.isEmpty ? null : _undo,
            ),
            _navChip(
              context,
              key: const Key('eq_redo'),
              label: 'إعادة',
              onTap: _redoStack.isEmpty ? null : _redo,
            ),
          ],
        ),
      ],
    );
  }

  Widget _navChip(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback? onTap,
    bool emphasized = false,
    bool destructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final bgColor = !enabled
        ? colorScheme.surfaceContainerHighest.withOpacity(0.25)
        : emphasized
            ? colorScheme.primaryContainer
            : colorScheme.surface;
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withOpacity(0.5)
        : destructive
            ? Colors.red.shade300
            : emphasized
                ? colorScheme.primary
                : colorScheme.outlineVariant;
    final textColor = !enabled
        ? Colors.grey
        : destructive
            ? Colors.red.shade700
            : emphasized
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
          color: bgColor,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
            color: textColor,
          ),
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

  /// منطقة البناء البصري: اتجاه المعادلة الرياضي دائماً من اليسار إلى اليمين
  /// (`TextDirection.ltr`) حتى داخل واجهة التطبيق العربية (`RTL`)، فلا تنعكس
  /// مواقع الجذور أو الأسس أو الأقواس أو إشارة `=`.
  Widget _buildModelArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_model.nodes.isEmpty) {
      return GestureDetector(
        onTap: () {
          _recordUndoSnapshot();
          final fresh = EqText('');
          setState(() {
            _model.nodes.add(fresh);
            _activeText = fresh;
          });
          _focusAfterBuild(fresh, caretOffset: 0);
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // النقر في الفراغ بعد آخر مكوّن يفتح/يفعّل خانة في نهاية المعادلة.
        _recordUndoSnapshot();
        late EqText slot;
        setState(() {
          if (_model.nodes.isNotEmpty && _model.nodes.last is EqText) {
            slot = _model.nodes.last as EqText;
          } else {
            slot = EqText('');
            _model.nodes.add(slot);
          }
          _activeText = slot;
        });
        _focusAfterBuild(slot, caretOffset: slot.text.length);
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          key: const Key('eq_canvas_ltr'),
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: _buildSequence(_model.nodes),
        ),
      ),
    );
  }

  Widget _buildSequence(List<EqNode> nodes) {
    return Wrap(
      direction: Axis.horizontal,
      textDirection: TextDirection.ltr,
      alignment: WrapAlignment.start,
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (var index = 0; index < nodes.length; index++)
          _buildNode(nodes[index], nodes, index),
      ],
    );
  }

  bool _containsActiveLeaf(EqNode node) {
    final activeId = _activeText?.id;
    if (activeId == null) return false;
    if (node.id == activeId) return true;
    for (final slot in node.slots) {
      for (final child in slot) {
        if (_containsActiveLeaf(child)) return true;
      }
    }
    return false;
  }

  Widget _buildNode(EqNode node, List<EqNode> parent, int index) {
    if (node is EqText) {
      return _buildTextSlot(node);
    }
    if (node is EqFraction) {
      return _deletable(
        node,
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
        node,
        parent,
        index,
        Row(
          textDirection: TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (node.root.isNotEmpty) _buildSlotBox(node.root, small: true),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                '√',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 22),
              ),
            ),
            _buildSlotBox(node.body),
          ],
        ),
      );
    }
    if (node is EqSup) {
      return _deletable(
        node,
        parent,
        index,
        Row(
          textDirection: TextDirection.ltr,
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
        node,
        parent,
        index,
        Row(
          textDirection: TextDirection.ltr,
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
        node,
        parent,
        index,
        Row(
          textDirection: TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              _fenceDisplay(node.left),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 22),
            ),
            _buildSlotBox(node.body),
            Text(
              _fenceDisplay(node.right),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 22),
            ),
          ],
        ),
      );
    }
    if (node is EqAccent) {
      return _deletable(
        node,
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
        node,
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
    final active = _activeText?.id == node.id;
    final width = (42 + controller.text.length * 9.0).clamp(42.0, 220.0);
    return GestureDetector(
      key: ValueKey<String>(node.id),
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
          _recordUndoSnapshot();
          final fresh = EqText('');
          setState(() {
            slot.add(fresh);
            _activeText = fresh;
          });
          _focusAfterBuild(fresh, caretOffset: 0);
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

  /// يغلّف بنية بزر حذف صغير وتمييز بصري واضح عند نشاط إحدى خاناتها.
  Widget _deletable(EqNode node, List<EqNode> parent, int index, Widget child) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeInside = _containsActiveLeaf(node);
    return Stack(
      key: ValueKey<String>(node.id),
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(left: 4, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: activeInside
                  ? colorScheme.primary.withOpacity(0.65)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: child,
        ),
        Positioned(
          left: -6,
          top: -6,
          child: GestureDetector(
            key: ValueKey<String>('del_${node.id}'),
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
              _removeNode(_model.nodes, _model.nodes.length - 1);
            }
          }),
          _Tool('مسح الكل', () {
            if (_model.nodes.isEmpty) return;
            _recordUndoSnapshot();
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
