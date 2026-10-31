import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exam_document.dart';
import '../../providers/exam_wizard_controller.dart';

/// Native-size editing chrome. Neither its rows nor its scroll height enters
/// the print layout. Payloads are stable IDs, never captured model indices.
/// Branches keep the existing within-owner MOVE / between-owner SWAP contract.
class CanonicalReorderPanel extends StatefulWidget {
  const CanonicalReorderPanel({super.key, required this.controller,
    required this.locked, required this.onClose, required this.onChanged});

  final ExamWizardController controller;
  final bool locked;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<CanonicalReorderPanel> createState() => _CanonicalReorderPanelState();
}

class _Entity {
  const _Entity(this.id, this.isQuestion);
  final String id;
  final bool isQuestion;
}

class _CanonicalReorderPanelState extends State<CanonicalReorderPanel> {
  final _scroll = ScrollController();
  final _window = GlobalKey();
  Timer? _timer;
  Offset? _pointer;

  BranchRef? _branch(String id) {
    final questions = widget.controller.document.questions;
    for (var q = 0; q < questions.length; q++) {
      final b = questions[q].branches.indexWhere((branch) => branch.id == id);
      if (b >= 0) return BranchRef(questionIndex: q, branchIndex: b);
    }
    return null;
  }

  int _question(String id) => widget.controller.questions.indexWhere((q) => q.id == id);

  bool _canDrop(_Entity source, _Entity target) {
    if (widget.locked || source.id == target.id || source.isQuestion != target.isQuestion) return false;
    return source.isQuestion
        ? _question(source.id) >= 0 && _question(target.id) >= 0
        : _branch(source.id) != null && _branch(target.id) != null;
  }

  void _drop(_Entity source, _Entity target) {
    _stopScroll();
    if (!_canDrop(source, target)) return;
    final controller = widget.controller;
    if (source.isQuestion) {
      controller.moveQuestion(_question(source.id), _question(target.id));
    } else {
      final from = _branch(source.id)!, to = _branch(target.id)!;
      if (from.questionIndex == to.questionIndex) {
        controller.moveBranch(from.questionIndex, from.branchIndex, to.branchIndex);
      } else {
        controller.swapBranchContent(from, to);
      }
    }
    widget.onChanged();
  }

  void _stopScroll() {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
  }

  void _autoScroll(Offset pointer) {
    _pointer = pointer;
    _timer ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      final box = _window.currentContext?.findRenderObject();
      if (!mounted || !_scroll.hasClients || box is! RenderBox || _pointer == null) return;
      final y = box.globalToLocal(_pointer!).dy;
      final direction = y < 48 ? -1 : y > box.size.height - 48 ? 1 : 0;
      final next = (_scroll.offset + direction * 12).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
      if (next != _scroll.offset) _scroll.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _stopScroll();
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(_Entity entity, String label) => DragTarget<_Entity>(
    key: ValueKey<String>('canonical-drop-${entity.id}'),
    onWillAcceptWithDetails: (details) => _canDrop(details.data, entity),
    onAcceptWithDetails: (details) => _drop(details.data, entity),
    builder: (context, candidates, _) => ColoredBox(
      color: candidates.isEmpty ? Colors.transparent : Theme.of(context).colorScheme.primaryContainer,
      child: SizedBox(height: 56, child: Row(children: [
        LongPressDraggable<_Entity>(
          key: ValueKey<String>('canonical-drag-${entity.id}'),
          data: entity,
          maxSimultaneousDrags: widget.locked ? 0 : 1,
          onDragUpdate: (details) => _autoScroll(details.globalPosition),
          onDragEnd: (_) => _stopScroll(),
          feedback: Material(elevation: 4, child: SizedBox(width: 240, height: 56,
            child: Padding(padding: const EdgeInsets.all(8), child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)))),
          child: Listener(behavior: HitTestBehavior.opaque,
            child: Semantics(button: true, enabled: !widget.locked,
            label: 'اضغط مطولاً واسحب: $label',
            child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_indicator,
              color: widget.locked ? Theme.of(context).disabledColor : null)))),
        ),
        Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
      ])),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final document = widget.controller.document;
    final entries = <({_Entity entity, String label})>[
      for (var q = 0; q < document.questions.length; q++) ...[
        (entity: _Entity(document.questions[q].id, true),
          label: 'سؤال ${document.formatNumber(q + 1)}: ${document.questions[q].statement}'),
        for (var b = 0; b < document.questions[q].branches.length; b++)
          (entity: _Entity(document.questions[q].branches[b].id, false),
            label: 'سؤال ${document.formatNumber(q + 1)} — فرع ${document.formatNumber(b + 1)}: ${document.questions[q].branches[b].content.statement}'),
      ],
    ];
    // The source row can be recycled while edge-scrolling. Its Draggable
    // onDragEnd is then not guaranteed to run. The panel stays in the original
    // pointer route, so cancellation/up ALWAYS stops the timer, including an
    // outside drop or a concurrently deleted source.
    return Listener(onPointerMove: (event) {
      if (_timer != null) _pointer = event.position;
    }, onPointerUp: (_) => _stopScroll(),
      onPointerCancel: (_) => _stopScroll(),
      child: Material(color: Theme.of(context).colorScheme.surface, elevation: 2,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 48, child: Row(children: [
          const SizedBox(width: 8),
          const Expanded(child: Text('ترتيب الأسئلة والفروع بالسحب', maxLines: 2)),
          IconButton(onPressed: widget.onClose, visualDensity: VisualDensity.standard, tooltip: 'إغلاق أدوات الترتيب',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48), icon: const Icon(Icons.close)),
        ])),
        SizedBox(key: _window, height: math.min(entries.length * 56.0,
          math.min(280.0, MediaQuery.sizeOf(context).height * .35)),
          child: ListView.builder(controller: _scroll, padding: EdgeInsets.zero,
            itemCount: entries.length,
            findChildIndexCallback: (key) {
              final index = entries.indexWhere((entry) => key == ValueKey<String>('canonical-drop-${entry.entity.id}'));
              return index < 0 ? null : index;
            },
            itemBuilder: (context, index) =>
              _row(entries[index].entity, entries[index].label))),
      ])));
  }
}
