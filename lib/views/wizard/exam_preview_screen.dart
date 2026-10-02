import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../layout/blueprint/exam_blueprint.dart';
import '../../layout/pagination_engine.dart';
import '../../layout/paper_metrics.dart';
import '../../models/branch_item.dart';
import '../../models/exam_canvas_geometry.dart';
import '../../models/exam_document.dart';
import '../../models/equation_model.dart';
import '../../models/floating_element.dart';
import '../../models/paper_divider.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/point_kind.dart';
import '../../models/question_model.dart';
import '../../models/quran_text.dart';
import '../../models/subject_layout.dart';
import '../../models/tex_content.dart';
import '../../providers/exam_document_provider.dart';
import '../../providers/exam_wizard_controller.dart';
import '../../services/docx_document_export_service.dart';
import '../../services/export_file_service.dart';
import '../../services/math_image_renderer.dart';
import '../../services/page_frame_store.dart';
import '../../services/pdf_export_service.dart';
import '../../services/shape_image_renderer.dart';
import '../widgets/floating_element_view.dart';
import '../widgets/formula_inserter.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/paper_field.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/smart_exam_toolbar.dart';
import '../widgets/tex_text.dart';
import '../widgets/visual_equation_editor.dart';
import 'header_footer_forms.dart';
import 'measure_size.dart';
import 'paper_header_footer_view.dart';
import 'paper_styles.dart';
import 'preview_toolbar.dart';

/// مرجع عنصر عائم (مستندياً، أو مرفق قديم داخل سؤال/فرع).
class _AttachmentRef {
  const _AttachmentRef({
    required this.questionIndex,
    this.branchIndex,
    required this.elementId,
  });

  final int questionIndex;
  final int? branchIndex;
  final String elementId;

  factory _AttachmentRef.global(String elementId) => _AttachmentRef(
        questionIndex: -1,
        elementId: elementId,
      );

  bool get isGlobal => questionIndex < 0;
  bool get isQuestionLevel => !isGlobal && branchIndex == null;
}

/// حوار إدخال نصي/رقمي مشترك يملك دورة حياة الـ controller داخليًا.
///
/// تحرير الـ controller فور عودة `showDialog` غير آمن: مسار الخروج المتحرك
/// يعيد بناء الحقل ويعيد الاشتراك في الـ controller المحرَّر
/// (استخدام-بعد-التحرير) — لذا يُحرَّر هنا في `dispose` فقط.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialText,
    this.hintText,
    this.helperText,
    this.saveLabel = 'حفظ',
    this.numeric = false,
    this.maxLines,
  });

  final String title;
  final String initialText;
  final String? hintText;
  final String? helperText;
  final String saveLabel;
  final bool numeric;

  /// عدد أسطر الحقل النصي (null = سطر واحد) — يُتجاهل في الوضع الرقمي.
  final int? maxLines;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: widget.numeric
          ? LtrNumericField(
              controller: _field,
              hintText: widget.hintText,
              decoration: InputDecoration(
                hintText: widget.hintText,
                helperText: widget.helperText,
                border: const OutlineInputBorder(),
              ),
            )
            : TextField(
              controller: _field,
              autofocus: true,
              maxLines: widget.maxLines,
              decoration: InputDecoration(
                hintText: widget.hintText,
                helperText: widget.helperText,
                border: const OutlineInputBorder(),
              ),
            ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

/// الخطوة 3: محرك المعاينة والتحرير البصري (WYSIWYG A4 Engine).
///
/// - **التقسيم الورقي الديناميكي**: كل كتلة (الترويسة/السؤال الكامل) تُقاس
///   عبر [MeasureSize] وتُبلّغ [ExamWizardController] الذي يعيد التوزيع عبر
///   `PaginationEngine` — السؤال لا يُفصل عن فروعه أبداً.
/// - **التحرير المباشر**: كل نص على الورقة حقل مسطّح قابل للكتابة في مكانه.
/// - **التحديد والتنسيق**: تحديد سؤال/فرع/ترويسة/مربع نص (منفرد أو متعدد)
///   ثم تنسيقه من شريط المعاينة (خط/حجم/عريض/محاذاة/إطار).
/// - **إعادة الترتيب**: سحب سؤال كامل أو فرع داخل سؤاله؛ الإفلات على فرع
///   في سؤال آخر يبدّل المحتوى فقط (العناوين ثابتة).
/// - **العناصر العائمة**: صور/أشكال/مربعات نص ومعادلات على مستوى المستند
///   وصفحة A4، مستقلة عن السؤال والفرع؛ وتبقى المرفقات القديمة مدعومة.
///   تحريك بالسحب المباشر بين الصفحات، تغيير حجم (الصور بنسبة ثابتة)، تدوير،
///   إطار، حذف — والنقرة المزدوجة على مربع النص تفتح محرّره.
/// - **العرض**: تكبير/تصغير/ملاءمة/توسيط، وقفل يمنع التحريك العرضي.
class ExamPreviewScreen extends StatefulWidget {
  const ExamPreviewScreen({super.key, required this.onBackToQuestions});

  final VoidCallback onBackToQuestions;

  @override
  State<ExamPreviewScreen> createState() => _ExamPreviewScreenState();
}

class _ExamPreviewScreenState extends State<ExamPreviewScreen> {
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{};
  final FormulaInserter _inserter = FormulaInserter();
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final Map<int, GlobalKey> _pageCanvasKeys = <int, GlobalKey>{};
  ExamWizardController? _controller;
  _AttachmentRef? _selectedAttachment;
  String? _selectedDividerKey;
  String? _activeItemFieldKey;
  String? _activeFieldKey;
  final Map<String, PaperAlign> _fieldAlignments = <String, PaperAlign>{};
  bool _isBusy = false;

  /// سحب فوري لأي عنصر حر. نقطة الإمساك تبقى ثابتة داخل العنصر، ويُعاد
  /// تحويل المؤشر إلى إحداثيات الصفحة التي يمر فوقها؛ لذلك يمكن نقله بين
  /// صفحات A4 دون المرور على سؤال أو إعادة إرفاقه يدوياً.
  int? _dragPointer;
  Offset? _dragStartScreen;
  Offset? _dragLastScreen;
  Offset? _dragLastPaper;
  Offset? _dragAnchorWithinElement;
  int? _dragPageIndex;
  _AttachmentRef? _dragRef;

  /// هل تحرّك الإصبع فعليًّا في السحب الجاري؟ (للتفريق بين السحب والنقر).
  bool _dragMoved = false;

  /// آخر نقر على أي عنصر عائم (معرّفه ووقته) — لكشف النقر المزدوج على
  /// مربع النص يدويًّا: الفوز الفوري بساحة الإيماءات في مسار السحب يمنع
  /// وصول النقرة إلى [GestureDetector].
  String? _lastAttachmentTapId;
  Duration? _lastAttachmentTapTime;

  /// وقت آخر لمس على أي عنصر عائم (يقيسه الغلاف الخارجي في [Listener]).
  Duration? _lastPointerDownTime;

  /// معادلة حُرِّرت للتوّ وتنتظر أن يختار المستخدم موضعها على الورقة
  /// (نقرة على المكان المطلوب، أو سحبها من الشريط إلى الموضع).
  String? _stagedFormula;

  /// هل كتبت المعادلة المرشّحة كصيغة منفردة (`$$...$$`)?
  bool _stagedFormulaIsBlock = false;

  /// قفل التحريك: يمنع السحب وتغيير الحجم (التكبير والتمرير متاحان).
  bool _locked = false;

  /// التحديد المتعدد للتنسيق الجماعي.
  bool _multiSelect = false;
  final Set<String> _selectedQuestions = <String>{};
  final Set<BranchRef> _selectedBranches = <BranchRef>{};
  bool _headerSelected = false;
  bool _showFormulas = true;

  double _zoom = 1.0;
  double _viewportWidth = 0;
  bool _didAutoFit = false;

  static const double _minZoom = 0.4;
  static const double _maxZoom = 2.5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ExamWizardController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_syncFieldsFromModel);
      _controller = controller..addListener(_syncFieldsFromModel);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_syncFieldsFromModel);
    for (final field in _fields.values) {
      field.dispose();
    }
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // حقول التحرير المباشر
  // ------------------------------------------------------------------

  bool _syncingFields = false;
  final Map<String, ValueChanged<String>> _fieldEdits = {};

  TextEditingController _field(String key, String initial, ValueChanged<String> onEdit) {
    // Refresh index-based callbacks after moves/deletions; controllers keep
    // their stable IDs, but their owners may now occupy different indices.
    _fieldEdits[key] = onEdit;
    return _fields.putIfAbsent(key, () {
      final field = TextEditingController(text: initial);
      var previousText = initial;
      field.addListener(() {
        final text = field.text;
        if (text == previousText) return; // Cursor/focus changes are not edits.
        previousText = text;
        if (!_syncingFields) _fieldEdits[key]?.call(text);
      });
      return field;
    });
  }

  static String _statementKey(String questionId) => 'statement-$questionId';
  static String _bodyKey(String questionId) => 'body-$questionId';
  static String _categoryKey(String questionId) => 'category-$questionId';
  static String _branchStatementKey(String branchId) => 'branch-statement-$branchId';
  static String _branchBodyKey(String branchId) => 'branch-body-$branchId';
  static String _itemKey(String itemId) => 'item-$itemId';
  static String _optionKey(String itemId, int index) => 'option-$itemId-$index';

  /// يزامن الحقول مع النموذج بعد تغيّر خارجي (تبديل المحتوى بالسحب مثلاً).
  ///
  /// أثناء الكتابة يكون النموذج مساوياً للحقل أصلاً فلا يحدث أي تعديل.
  void _syncFieldsFromModel() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_syncingFields) return;
    _syncingFields = true;
    try {
      final document = controller.document;
      void sync(String key, String value) {
        final field = _fields[key];
        if (field != null && field.text != value) {
          field.text = value;
        }
      }

      void syncPoints(List<BranchItem> points) {
        for (final point in points) {
          sync(_itemKey(point.id), point.text);
          for (var index = 0; index < point.options.length; index++) {
            sync(_optionKey(point.id, index), point.options[index].text);
          }
        }
      }

      for (final question in document.questions) {
        sync(_statementKey(question.id), question.statement);
        sync(_bodyKey(question.id), question.body);
        sync(_categoryKey(question.id), question.category);
        syncPoints(question.items);
        for (final branch in question.branches) {
          sync(_branchStatementKey(branch.id), branch.content.statement);
          sync(_branchBodyKey(branch.id), branch.content.body);
          syncPoints(branch.content.items);
        }
      }
      _disposeStaleFields(document);
    } finally {
      _syncingFields = false;
    }
  }

  /// يتخلّص من تحكمات الحقول التي حُذف أصحابها (سؤال أو فرع أو نقطة) فلا
  /// تتراكم تحكمات بلا مالك. الحذف يتم **بعد اكتمال الإطار** كي لا يُحرَّر
  /// تحكم ما زال مربوطاً بحقل في الشجرة الحالية.
  void _disposeStaleFields(ExamDocument document) {
    final live = <String>{};
    void addPoints(List<BranchItem> points) {
      for (final point in points) {
        live.add(_itemKey(point.id));
        for (var index = 0; index < point.options.length; index++) {
          live.add(_optionKey(point.id, index));
        }
      }
    }

    for (final question in document.questions) {
      live
        ..add(_statementKey(question.id))
        ..add(_bodyKey(question.id))
        ..add(_categoryKey(question.id));
      addPoints(question.items);
      for (final branch in question.branches) {
        live
          ..add(_branchStatementKey(branch.id))
          ..add(_branchBodyKey(branch.id));
        addPoints(branch.content.items);
      }
    }
    final stale = _fields.keys.where((key) => !live.contains(key)).toList(growable: false);
    if (stale.isEmpty) {
      return;
    }
    // يُزال القيد فوراً (فلا يُعاد استخدام تحكم نقطة محذوفة)، ويُحرَّر التحكم
    // بعد اكتمال إطارين — فالإطار الأول يُسقط الحقول من الشجرة، والثاني
    // يضمن أن التحكم لم يبق مربوطاً بأي حقل قبل تحريره.
    for (final key in stale) {
      if (identical(_inserter.controller, _fields[key])) _inserter.controller = null;
      _fieldEdits.remove(key);
    }
    final orphaned = <TextEditingController>[
      for (final key in stale) _fields.remove(key)!,
    ];
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final controller in orphaned) {
          controller.dispose();
        }
      });
    });
  }

  static double? _parseMarks(String value) {
    final normalized = value.trim().replaceAll('،', '.').replaceAll(',', '.');
    if (normalized.isEmpty) {
      return 0;
    }
    final marks = double.tryParse(normalized);
    return marks != null && marks.isFinite && marks >= 0 ? marks : null;
  }

  static String _formatMarksInput(double marks) {
    if (marks == 0) {
      return '';
    }
    return marks == marks.truncateToDouble() ? marks.toInt().toString() : marks.toString();
  }

  // ------------------------------------------------------------------
  // التحديد
  // ------------------------------------------------------------------

  void _clearSelection() {
    _selectedQuestions.clear();
    _selectedBranches.clear();
    _headerSelected = false;
    _selectedAttachment = null;
    _selectedDividerKey = null;
    _activeItemFieldKey = null;
    _activeFieldKey = null;
  }

  void _tapQuestion(int index) {
    final controller = _controller!;
    final id = controller.questions[index].id;
    setState(() {
      if (_multiSelect) {
        if (!_selectedQuestions.remove(id)) {
          _selectedQuestions.add(id);
        }
      } else {
        _clearSelection();
        _selectedQuestions.add(id);
      }
      controller.selectQuestion(index);
      if (!_multiSelect) {
        controller.selectBranch(null);
      }
    });
  }

  void _tapBranch(BranchRef ref) {
    final controller = _controller!;
    setState(() {
      if (_multiSelect) {
        if (!_selectedBranches.remove(ref)) {
          _selectedBranches.add(ref);
        }
        controller.selectBranch(ref);
      } else {
        _clearSelection();
        _selectedBranches.add(ref);
        controller.selectBranch(ref);
      }
    });
  }

  void _tapHeader() {
    setState(() {
      final was = _headerSelected;
      _clearSelection();
      _headerSelected = !was;
    });
  }

  /// هل الفرع [ref] محدد حالياً (منفرداً أو ضمن متعدد)؟
  bool _isBranchSelected(BranchRef ref) {
    if (_selectedBranches.contains(ref)) {
      return true;
    }
    return !_multiSelect && _controller?.selectedBranch == ref;
  }

  /// هل السؤال [index] محدد؟
  bool _isQuestionSelected(int index) {
    final questions = _controller!.questions;
    // حارس أمان: فهرس قديم أثناء إعادة بناء متداخلة = غير محدد لا عطل.
    if (index < 0 || index >= questions.length) {
      return false;
    }
    final id = questions[index].id;
    if (_selectedQuestions.contains(id)) {
      return true;
    }
    return !_multiSelect && _controller?.selectedQuestionIndex == index;
  }

  String _selectionLabel(ExamDocument document) {
    if (_selectedAttachment != null) {
      final ref = _selectedAttachment!;
      final element = _findAttachment(document, ref);
      if (element == null) {
        return '';
      }
      if (element.isImage) {
        return 'صورة';
      }
      if (element.isTextBox) {
        return 'مربع نص';
      }
      return 'شكل: ${element.shape?.arabicLabel ?? ''}';
    }
    if (_selectedDividerKey != null) {
      return 'فاصل';
    }
    final branches = _selectedBranches.where(document.containsRef).toList();
    if (_headerSelected) {
      return 'الترويسة';
    }
    if (branches.isNotEmpty && _selectedQuestions.isNotEmpty) {
      return 'تحديد متعدد (${document.formatNumber(branches.length + _selectedQuestions.length)})';
    }
    if (branches.length == 1) {
      final ref = branches.single;
      return 'الفرع ${document.displayBranchLabel(ref.questionIndex, ref.branchIndex)}'
          ' — ${document.displayQuestionLabel(document.questions[ref.questionIndex])}';
    }
    if (branches.length > 1) {
      return '${document.formatNumber(branches.length)} فروع';
    }
    if (_selectedQuestions.length == 1) {
      final question = document.questionById(_selectedQuestions.single);
      if (question != null) {
        return document.displayQuestionLabel(question);
      }
    }
    if (_selectedQuestions.length > 1) {
      return '${document.formatNumber(_selectedQuestions.length)} أسئلة';
    }
    final single = _controller?.selectedBranch;
    if (single != null && document.containsRef(single)) {
      return 'الفرع ${document.displayBranchLabel(single.questionIndex, single.branchIndex)}';
    }
    if (document.questions.isNotEmpty) {
      final index = _controller!.selectedQuestionIndex ?? _controller!.currentQuestionIndex;
      return document.displayQuestionLabel(document.questions[index]);
    }
    return '';
  }

  FloatingElement? _findAttachment(ExamDocument document, _AttachmentRef ref) {
    final freeElement = document.floatingElementById(ref.elementId);
    if (freeElement != null || ref.isGlobal) {
      return freeElement;
    }
    if (ref.questionIndex < 0 || ref.questionIndex >= document.questions.length) {
      return null;
    }
    final question = document.questions[ref.questionIndex];
    final list = ref.branchIndex == null
        ? question.attachments
        : (ref.branchIndex! < 0 || ref.branchIndex! >= question.branches.length
            ? const <FloatingElement>[]
            : question.branches[ref.branchIndex!].attachments);
    for (final element in list) {
      if (element.id == ref.elementId) {
        return element;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // التحكم بالمسافة بين الأسئلة
  // ------------------------------------------------------------------

  List<int> _questionSpacingTargets() {
    final controller = _controller;
    if (controller == null ||
        controller.questions.isEmpty ||
        _selectedAttachment != null ||
        _headerSelected ||
        _selectedDividerKey != null) {
      return const <int>[];
    }
    final indexes = <int>{};
    for (final id in _selectedQuestions) {
      final index = controller.document.indexOfQuestion(id);
      if (index >= 0) indexes.add(index);
    }
    for (final ref in _selectedBranches) {
      if (controller.document.containsRef(ref)) indexes.add(ref.questionIndex);
    }
    if (indexes.isNotEmpty) return indexes.toList()..sort();
    final branch = controller.selectedBranch;
    if (branch != null && controller.document.containsRef(branch)) {
      return <int>[branch.questionIndex];
    }
    final question = controller.selectedQuestionIndex;
    if (question != null) return <int>[question];
    return <int>[controller.currentQuestionIndex];
  }

  double? _activeQuestionSpacing() {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) return null;
    final first = _controller!.questions[targets.first].spacingAfter;
    return targets.every(
      (index) => (_controller!.questions[index].spacingAfter - first).abs() < 0.01,
    )
        ? first
        : null;
  }

  void _applyQuestionSpacing(double spacing) {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) {
      _showMessage('حدد سؤالاً أو فرعاً لتغيير المسافة بعد السؤال.');
      return;
    }
    for (final index in targets) {
      _controller!.updateQuestionSpacing(index, spacing);
    }
  }

  Future<void> _showCustomQuestionSpacing() async {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) {
      _showMessage('حدد سؤالاً أولاً لتغيير المسافة بينه وبين السؤال التالي.');
      return;
    }
    final current = _controller!.questions[targets.first].spacingAfter;
    final saved = await _showTextInputDialog(
      title: 'المسافة بين الأسئلة',
      initialText: current.toString(),
      hintText: '0 = بلا فراغ إضافي',
      helperText: 'أدخل قيمة من 0 إلى 200 بكسل.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) return;
    final spacing = double.tryParse(saved.trim().replaceAll('،', '.').replaceAll(',', '.'));
    if (spacing == null || !spacing.isFinite || spacing < 0 || spacing > 200) {
      _showMessage('المسافة يجب أن تكون بين 0 و200 بكسل.', isError: true);
      return;
    }
    _applyQuestionSpacing(spacing);
  }

  // ------------------------------------------------------------------
  // تنسيق التحديد
  // ------------------------------------------------------------------

  /// يجمع أهداف التنسيق: فروع، أسئلة، ترويسة، مربعات نص.
  ///
  /// بلا تحديد صريح يُستخدم «العنصر النشط»: الفرع المحدد، وإلا السؤال
  /// المحدد، وإلا السؤال المفتوح حالياً.
  ({List<BranchRef> branches, List<int> questions, bool header, List<_AttachmentRef> boxes})
      _styleTargets() {
    final controller = _controller!;
    final document = controller.document;
    if (_selectedAttachment != null) {
      final element = _findAttachment(document, _selectedAttachment!);
      if (element != null && element.isTextBox) {
        return (branches: const [], questions: const [], header: false, boxes: [_selectedAttachment!]);
      }
      return (branches: const [], questions: const [], header: false, boxes: const []);
    }
    final branches =
        _selectedBranches.where(document.containsRef).toList(growable: false);
    final questions = <int>[];
    for (final id in _selectedQuestions) {
      final index = document.indexOfQuestion(id);
      if (index != -1) {
        questions.add(index);
      }
    }
    if (branches.isNotEmpty || questions.isNotEmpty || _headerSelected) {
      return (branches: branches, questions: questions, header: _headerSelected, boxes: const []);
    }
    final single = controller.selectedBranch;
    if (single != null && document.containsRef(single)) {
      return (branches: [single], questions: const [], header: false, boxes: const []);
    }
    final selectedQuestion = controller.selectedQuestionIndex;
    if (selectedQuestion != null) {
      return (branches: const [], questions: [selectedQuestion], header: false, boxes: const []);
    }
    if (document.questions.isEmpty) {
      return (
        branches: const [],
        questions: const [],
        header: false,
        boxes: const [],
      );
    }
    return (
      branches: const [],
      questions: [controller.currentQuestionIndex],
      header: false,
      boxes: const [],
    );
  }

  /// النمط المعروض في الشريط (من أول هدف).
  PaperTextStyle _activeStyle() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.textStyle ??
          PaperTextStyle.empty;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).style;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].style;
    }
    if (targets.header) {
      return document.header.style;
    }
    return PaperTextStyle.empty;
  }

  int? _activeColor() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.textStyle.color;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).style.color;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].effectiveTitleColor;
    }
    if (targets.header) {
      return document.header.style.color;
    }
    return null;
  }

  String _colorTooltip() {
    final targets = _styleTargets();
    return targets.questions.isNotEmpty &&
            targets.branches.isEmpty &&
            !targets.header &&
            targets.boxes.isEmpty
        ? 'لون عنوان السؤال'
        : 'لون النص';
  }

  /// معاملا القياس العامّان من إعدادات الورقة (حجم الخط الأساسي وتباعد
  /// الأسطر) — يُمرَّران لكل أنماط اللوحة حتى تكبر الورقة وتصغر معاً.
  double get _fontScale => _controller!.document.settings.fontScale;
  double get _heightScale => _controller!.document.settings.heightScale;

  /// يقيس نمطاً أساسياً مباشراً بمعاملَي الورقة (للأنماط بلا [resolve]).
  TextStyle _scaled(TextStyle base) => PaperStyles.scale(
        base,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );

  bool? _activeFrame() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.framed;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).showFrame;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].showFrame;
    }
    if (targets.header) {
      return document.settings.headerBorder;
    }
    return null;
  }

  /// مجموعة النقاط التي تحمل النقطة [pointId] (سؤال أو فرع) أو `null`.
  PointsOwner? _ownerOfPoint(ExamDocument document, String pointId) {
    for (var q = 0; q < document.questions.length; q++) {
      final question = document.questions[q];
      if (question.items.any((point) => point.id == pointId)) {
        return PointsOwner.question(q);
      }
      for (var b = 0; b < question.branches.length; b++) {
        if (question.branches[b].content.items.any((point) => point.id == pointId)) {
          return PointsOwner.branch(BranchRef(questionIndex: q, branchIndex: b));
        }
      }
    }
    return null;
  }

  BranchItem? _findItem(String itemId) {
    final doc = _controller?.document;
    if (doc == null) return null;
    final owner = _ownerOfPoint(doc, itemId);
    if (owner == null) return null;
    for (final point in doc.pointsOf(owner)) {
      if (point.id == itemId) return point;
    }
    return null;
  }

  /// مفاتيح الحقول التي لها نظير مباشر في الموديل — تُقرأ من الموديل دائماً
  /// (ولا تتأثر ببقايا _fieldAlignments بعد التراجع).
  bool _isModelBackedAlignKey(String fieldKey) =>
      fieldKey.startsWith('statement-') ||
      fieldKey.startsWith('body-') ||
      fieldKey.startsWith('branch-') ||
      fieldKey.startsWith('option-') ||
      fieldKey.startsWith('item-');

  static final RegExp _optionKeyPattern = RegExp(r'^option-(.+)-(\d+)$');

  /// المحاذاة المحفوظة في الموديل لمفتاح حقل (null = غير محددة).
  PaperAlign? _modelAlignFor(String fieldKey) {
    final doc = _controller?.document;
    if (doc == null) {
      return null;
    }
    if (fieldKey.startsWith('statement-')) {
      final question = doc.questionById(fieldKey.substring('statement-'.length));
      return question == null ? null : question.titleAlign ?? question.style.align;
    }
    if (fieldKey.startsWith('body-')) {
      final question = doc.questionById(fieldKey.substring('body-'.length));
      return question == null ? null : question.bodyAlign ?? question.style.align;
    }
    for (final prefix in const <String>['branch-statement-', 'branch-body-']) {
      if (fieldKey.startsWith(prefix)) {
        final ref = _findBranchRef(doc, fieldKey.substring(prefix.length));
        return ref == null ? null : doc.branchAt(ref).style.align;
      }
    }
    if (fieldKey.startsWith('option-')) {
      final match = _optionKeyPattern.firstMatch(fieldKey);
      if (match == null) {
        return null;
      }
      final options = _findItem(match.group(1)!)?.options;
      final optionIndex = int.parse(match.group(2)!);
      return options != null && optionIndex >= 0 && optionIndex < options.length
          ? options[optionIndex].align
          : null;
    }
    if (fieldKey.startsWith('item-')) {
      return _findItem(fieldKey.substring('item-'.length))?.align;
    }
    return null;
  }

  BranchRef? _findBranchRef(ExamDocument document, String branchId) {
    for (var q = 0; q < document.questions.length; q++) {
      final bIdx = document.questions[q].indexOfBranch(branchId);
      if (bIdx != -1) {
        return BranchRef(questionIndex: q, branchIndex: bIdx);
      }
    }
    return null;
  }

  TextAlign _textAlignFor(String fieldKey, {TextAlign fallback = TextAlign.start}) {
    if (_isModelBackedAlignKey(fieldKey)) {
      final model = _modelAlignFor(fieldKey);
      return model != null ? PaperStyles.toTextAlign(model) : fallback;
    }
    if (_fieldAlignments.containsKey(fieldKey)) {
      return PaperStyles.toTextAlign(_fieldAlignments[fieldKey]);
    }
    return fallback;
  }

  PaperAlign? _activeAlign() {
    if (_activeFieldKey != null) {
      if (_isModelBackedAlignKey(_activeFieldKey!)) {
        final model = _modelAlignFor(_activeFieldKey!);
        if (model != null) {
          return model;
        }
      } else if (_fieldAlignments.containsKey(_activeFieldKey)) {
        return _fieldAlignments[_activeFieldKey];
      }
    }
    return _activeStyle().align;
  }

  /// يطبّق محاذاة على الحقل النشط وحده (كما في Word: الفقرة الحالية)؛ وبلا
  /// حقل نشط تُطبَّق على عناصر التحديد.
  void _onAlignChanged(PaperAlign align) {
    setState(() {
      if (_activeFieldKey != null) {
        _fieldAlignments[_activeFieldKey!] = align;
      }
    });

    final controller = _controller!;
    final document = controller.document;
    final key = _activeFieldKey;
    if (key == null) {
      // لا حقل نشط: تُطبَّق على الأهداف المحددة (سؤال/فرع كامل).
      _applyStyle((current) => current.copyWith(align: () => align));
      return;
    }

    // 1. نقطة محددة: تتغير محاذاة تلك النقطة وحدها (في الموديل مباشرةً
    //    فتصل إلى PDF/Word أيضاً).
    if (key.startsWith('item-')) {
      final pointId = key.substring('item-'.length);
      final owner = _ownerOfPoint(document, pointId);
      if (owner != null) {
        controller.updatePointAlign(owner, pointId, align);
      }
      return;
    }

    // 2. خيار «اختيار من متعدد» محدد: محاذاته وحده.
    final optionMatch = _optionKeyPattern.firstMatch(key);
    if (optionMatch != null) {
      final pointId = optionMatch.group(1)!;
      final owner = _ownerOfPoint(document, pointId);
      if (owner != null) {
        controller.updatePointOptionAlign(
          owner,
          pointId,
          int.parse(optionMatch.group(2)!),
          align,
        );
      }
      return;
    }

    // 3. منطوق السؤال (سطر العنوان).
    if (key.startsWith('statement-')) {
      final index = document.indexOfQuestion(key.substring('statement-'.length));
      if (index != -1) {
        controller.updateQuestionTitleAlign(index, align);
      }
      return;
    }

    // 4. نص السؤال: تحديث واحد يكتب bodyAlign وstyle.align معاً = خطوة
    //    تراجع واحدة.
    if (key.startsWith('body-')) {
      final index = document.indexOfQuestion(key.substring('body-'.length));
      if (index != -1) {
        controller.updateQuestionBodyAlign(index, align);
      }
      return;
    }

    // 5. منطوق الفرع ونصه: محاذاة نمط الفرع.
    for (final prefix in const <String>['branch-statement-', 'branch-body-']) {
      if (key.startsWith(prefix)) {
        final ref = _findBranchRef(document, key.substring(prefix.length));
        if (ref != null) {
          controller.updateBranchStyle(
            ref,
            document.branchAt(ref).style.copyWith(align: () => align),
          );
        }
        return;
      }
    }
    // حقل بلا موديل مخصص بعد (مثل قسم السؤال) — يبقى في خريطة الشاشة.
  }

  void _applyStyle(PaperTextStyle Function(PaperTextStyle current) update) {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    // تنسيق واحد على كل الأهداف = خطوة تراجع واحدة (MSO): دفعة واحدة
    // تجمع الفروع والأسئلة بدل commit لكل هدف.
    final branchStyles = <BranchRef, PaperTextStyle>{
      for (final ref in targets.branches) ref: update(document.branchAt(ref).style),
    };
    final questionStyles = <int, PaperTextStyle>{
      for (final index in targets.questions) index: update(document.questions[index].style),
    };
    if (branchStyles.isNotEmpty || questionStyles.isNotEmpty) {
      controller.applyStyleBatch(
        branchStyles: branchStyles,
        questionStyles: questionStyles,
      );
      applied = true;
    }
    if (targets.header) {
      controller.updateHeaderStyle(update(document.header.style));
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) {
        continue;
      }
      _updateAttachmentElement(ref, element.copyWith(textStyle: update(element.textStyle)));
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق التنسيق.');
    }
  }

  /// عند تحديد سؤال يلوّن هذا الأمر عنوانه فقط؛ الفروع ومربعات النص
  /// والترويسة تحتفظ بتنسيقها المعتاد.
  void _applyColor(int? color) {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    for (final ref in targets.branches) {
      controller.updateBranchStyle(
        ref,
        document.branchAt(ref).style.copyWith(color: () => color),
      );
      applied = true;
    }
    for (final index in targets.questions) {
      controller.updateQuestionTitleColor(index, color);
      applied = true;
    }
    if (targets.header) {
      controller.updateHeaderStyle(
        document.header.style.copyWith(color: () => color),
      );
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) continue;
      _updateAttachmentElement(
        ref,
        element.copyWith(
          textStyle: element.textStyle.copyWith(color: () => color),
        ),
      );
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق اللون.');
    }
  }

  void _toggleFrame() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    for (final ref in targets.branches) {
      controller.toggleBranchFrame(ref);
      applied = true;
    }
    for (final index in targets.questions) {
      controller.toggleQuestionFrame(index);
      applied = true;
    }
    if (targets.header) {
      controller.updateSettings(
        document.settings.copyWith(headerBorder: !document.settings.headerBorder),
      );
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) {
        continue;
      }
      _updateAttachmentElement(ref, element.copyWith(framed: !element.framed));
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد عنصراً أولاً لإضافة إطار حوله.');
    }
  }

  // ------------------------------------------------------------------
  // إجراءات
  // ------------------------------------------------------------------

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// موضع افتراضي لعنصر جديد بإحداثيات الورقة **المطلقة**: رأس كتلة السؤال
  /// المحدد (فتظهر الصورة/الشكل قريباً من سياقه كما كان)، ويسحبه المستخدم بعد
  /// ذلك إلى أي نقطة على الورقة.
  ///
  /// العناصر تُرسم الآن في طبقة الصفحة بإحداثي مطلق، فلو تُرك (0،0) لظهرت في
  /// أعلى الورقة بعيداً عن السؤال — ومن هنا جاء هذا الحساب.
  /// السؤال المحدد حالياً (مالك العناصر الجديدة) أو `null` إن لا تحديد.
  String? _selectedOwnerQuestionId() {
    final controller = _controller;
    if (controller == null || controller.questions.isEmpty) {
      return null;
    }
    final index = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex;
    if (index == null || index < 0 || index >= controller.questions.length) {
      return null;
    }
    return controller.questions[index].id;
  }

  /// موضع افتراضي للعنصر الجديد: داخل السؤال المحدد (مرتبطاً به) إن وُجد
  /// تحديد — وإلا موضع حر على صفحة السؤال النشط.
  FloatingElement _withDefaultPosition(FloatingElement element) {
    final controller = _controller;
    if (controller == null) {
      return element;
    }
    final owner = _selectedOwnerQuestionId();
    if (owner != null) {
      final rect = controller.questionRect(owner);
      if (rect != null) {
        final maxDx = math.max(0.0, rect.width - element.width);
        final maxDy = math.max(0.0, rect.height - element.height);
        return element.withOwner(owner).copyWith(
              pageIndex: rect.pageIndex,
              dx: maxDx / 2,
              dy: math.min(maxDy, 8),
            );
      }
    }
    if (controller.questions.isEmpty) {
      return element.copyWith(
        pageIndex: 0,
        dx: ExamCanvasGeometry.defaultElementDx,
        dy: ExamCanvasGeometry.defaultElementDy,
      );
    }
    final questionIndex = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex ?? controller.currentQuestionIndex;
    final pageIndex = controller.pagination.pageIndexOf(
          controller.questions[questionIndex].id,
        ) ??
        0;
    final top = _blockTopOnPage(questionIndex);
    return element.copyWith(
      pageIndex: pageIndex,
      dx: 8,
      dy: (top ?? ExamCanvasGeometry.defaultElementDy) + 8,
    );
  }

  /// إحداثيات العنصر **المطلقة على ورقته**: العنصر المرتبط بسؤال يُزاح
  /// بمستطيل سؤاله (والسؤال قد ينتقل بين الصفحات)، والعنصر الحر كما هو.
  ({int pageIndex, double dx, double dy}) _elementGeometry(
    ExamWizardController controller,
    FloatingElement element,
  ) {
    final owner = element.ownerQuestionId;
    if (owner == null) {
      return (pageIndex: element.pageIndex, dx: element.dx, dy: element.dy);
    }
    final rect = controller.questionRect(owner);
    if (rect == null) {
      return (pageIndex: element.pageIndex, dx: element.dx, dy: element.dy);
    }
    final margin = ExamCanvasGeometry.marginFor(controller.document.settings.marginMm);
    return (
      pageIndex: rect.pageIndex,
      dx: margin + element.dx,
      dy: rect.top + element.dy,
    );
  }

  /// أعلى كتلة السؤال [questionIndex] داخل صفحتها (إحداثي ورقة مطلق)، أو
  /// `null` إن لم تُقسَّم الورقة بعد.
  double? _blockTopOnPage(int questionIndex) {
    final controller = _controller;
    final questions = controller?.questions;
    if (controller == null || questions == null || questions.isEmpty) {
      return null;
    }
    final index = questionIndex < 0 || questionIndex >= questions.length
        ? questions.length - 1
        : questionIndex;
    final document = controller.document;
    final margin = ExamCanvasGeometry.marginFor(document.settings.marginMm);
    final blockId = questions[index].id;
    final pageIndex = controller.pagination.pageIndexOf(blockId);
    if (pageIndex == null) {
      return null;
    }
    final page = controller.pagination.pages[pageIndex];
    final position = page.blockIds.indexOf(blockId);
    if (position < 0) {
      return null;
    }
    var top = margin;
    for (final id in page.blockIds.take(position)) {
      final previousQuestion = document.questionById(id);
      final spacingAfter = previousQuestion?.spacingAfter ?? PaperMetrics.blockSpacingPx;
      top += (controller.blockHeight(id) ?? 0) + spacingAfter;
    }
    return top;
  }

  /// يفتح محرّر المعادلات ثم يُنتج معادلة **حرة** تُحدّد موضعها بنفسك.
  ///
  /// بعد الإكمال في المحرّر تصبح المعادلة بطاقةً جاهزة (في شريط الصيغ):
  /// تُسحب إلى أي نقطة على الورقة فتُقام هناك، أو تنقر مكانها على الورقة
  /// فتستقر تحته — بلا التزام بحقل نصي ولا بسؤال معيّن. (من أراد معادلة
  /// سطرية وسط الجملة فبإمكانه تحرير الصيغ داخل الحقول عبر «تحرير معادلة».)
  Future<void> _openEquationEditor({
    String? template,
    bool preferBlock = false,
    bool editExisting = false,
  }) async {
    // «تحرير معادلة»: صيغة موجودة داخل حقل نصي تُحرَّر في مكانها (لمن أراد
    // معادلة سطرية وسط الجملة). أمّا مكتبة الصيغ و«محرر المعادلات» فتُنتج
    // معادلة **حرة** تُسحب إلى أي موضع.
    if (editExisting) {
      final active = _inserter.controller;
      if (active == null) {
        _showMessage('انقر داخل حقل نصي أولاً لتحرير معادلته.');
        return;
      }
      await _editEquationInFieldController(
        active,
        template: template,
        preferBlock: preferBlock,
        editExisting: true,
      );
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: template ?? _stagedFormula,
      initialIsBlock: preferBlock || _stagedFormulaIsBlock,
    );
    if (snippet == null || !mounted) {
      return;
    }
    final latex = _formulaBodyOf(snippet);
    if (latex.trim().isEmpty) {
      return;
    }
    setState(() {
      _stagedFormula = latex;
      _stagedFormulaIsBlock = snippet.startsWith(r'$$');
    });
    _showMessage('اختر موضع المعادلة: اضغط على الورقة — أو اسحبها من الشريط إلى مكانها.');
  }

  /// يستخرج جسم الصيغة ([FloatingElement.label]) من مقطع المحرّر.
  static String _formulaBodyOf(String snippet) {
    var body = snippet.trim();
    if (body.startsWith(r'$$') && body.endsWith(r'$$') && body.length >= 4) {
      body = body.substring(2, body.length - 2);
    } else if (body.startsWith(r'$') && body.endsWith(r'$') && body.length >= 2) {
      body = body.substring(1, body.length - 1);
    }
    return body.trim();
  }

  /// يوضع المرشح عند [tapPosition] داخل صفحة A4 محددة، كنقطة حرة مستقلة
  /// عن السؤال أو الفرع. نقطة النقر تصبح مركز المعادلة.
  void _placeStagedFormula(
    Offset tapPosition, {
    required int pageIndex,
  }) {
    final latex = _stagedFormula;
    if (latex == null) {
      return;
    }
    const elementWidth = 170.0;
    const elementHeight = 80.0;
    final board = _boardPositionFromLocal(
      tapPosition,
      width: elementWidth,
      height: elementHeight,
    );
    final element = FloatingElement(
      type: FloatingElementType.formula,
      label: latex,
      dx: board.dx,
      dy: board.dy,
      pageIndex: pageIndex,
      width: elementWidth,
      height: elementHeight,
    );
    // مع سؤال محدد: المعادلة تصير جزءاً من السؤال وتُحصر داخل حدوده؛
    // وبلا تحديد تبقى عنصراً حراً في أي نقطة من الورقة.
    final owner = _selectedOwnerQuestionId();
    final added = _controller!.addFloatingElement(
      element,
      pageIndex: pageIndex,
      ownerQuestionId: owner,
    );
    if (!added) {
      _showMessage('تعذر إدراج المعادلة. حاول اختيار موضع آخر على الورقة.');
      return;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(element.id);
    });
    _showMessage(
      owner == null
          ? 'أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.'
          : 'أُدرجت المعادلة داخل السؤال المحدد — حركتها محصورة فيه.',
    );
  }

  /// يضيف عنصراً إلى الورقة: إن كان سؤال محدداً ارتبط به ووُضع داخله، وإلا
  /// صار عنصراً حراً على صفحة السؤال النشط.
  void _addAttachmentToSelection(FloatingElement element) {
    element = _withDefaultPosition(element);
    final controller = _controller!;
    final added = controller.addFloatingElement(
      element,
      pageIndex: element.pageIndex,
      ownerQuestionId: element.ownerQuestionId,
    );
    if (added) {
      setState(() => _selectedAttachment = _AttachmentRef.global(element.id));
      if (element.ownerQuestionId != null) {
        _showMessage('أُضيف العنصر داخل السؤال المحدد — حرّكته محصورة فيه.');
      }
      return;
    }
    _showMessage('تعذر إضافة العنصر إلى الورقة.');
  }

  void _addImageToSelection(List<int> bytes) {
    _addAttachmentToSelection(
      FloatingElement(
        type: FloatingElementType.image,
        bytes: Uint8List.fromList(bytes),
        dx: 0,
        dy: 0,
        width: ExamCanvasGeometry.defaultElementSize,
        height: ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  Future<void> _pickImageToSelection() async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage('تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.', isError: true),
    );
    if (!mounted) return;
    if (bytes != null) {
      _addImageToSelection(bytes);
    }
  }

  void _addShapeToSelection(FloatingShapeType shape) {
    _addAttachmentToSelection(
      FloatingElement(
        type: FloatingElementType.shape,
        shape: shape,
        dx: 0,
        dy: 0,
        width: shape == FloatingShapeType.line || shape == FloatingShapeType.divider
            ? ExamCanvasGeometry.defaultElementSize * 2
            : ExamCanvasGeometry.defaultElementSize,
        height: shape == FloatingShapeType.line || shape == FloatingShapeType.divider
            ? 24
            : ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  void _addTextBox() {
    final element = _newTextBoxElement();
    _addAttachmentToSelection(element);
    _editNewTextBox(element.id);
  }

  /// مربع نص افتراضي (180×90 بكسل لوحة) عند موضع العنصر الافتراضي في الصفحة.
  static FloatingElement _newTextBoxElement() => FloatingElement(
        type: FloatingElementType.shape,
        shape: FloatingShapeType.textBox,
        dx: 0,
        dy: 0,
        width: 180,
        height: 90,
      );

  /// يفتح محرّر نص المربع المضاف للتوّ ثم يذكّر بأن السحب المباشر يحرّكه.
  ///
  /// يُشترط أن يكون المربع [elementId] هو **المحدد حالياً** للتأكد من
  /// نجاح إضافته قبل فتح المحرر.
  void _editNewTextBox(String elementId) {
    if (_selectedAttachment?.elementId != elementId) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final ref = _selectedAttachment;
      if (!mounted || ref == null || ref.elementId != elementId) {
        return;
      }
      await _editTextBox(ref);
      if (mounted) {
        _showMessage('اسحب مربع النص مباشرةً لتحريكه في أي موضع داخل الورقة.');
      }
    });
  }

  void _addDividerToSelection() {
    final controller = _controller!;
    final document = controller.document;
    final branches = _selectedBranches.where(document.containsRef).toList();
    if (branches.length == 1) {
      controller.setBranchDivider(branches.single, const PaperDivider());
      _showMessage('تمت إضافة فاصل بعد الفرع.');
      return;
    }
    final single = controller.selectedBranch;
    if (single != null && _selectedQuestions.isEmpty && _selectedBranches.isEmpty) {
      controller.setBranchDivider(single, const PaperDivider());
      _showMessage('تمت إضافة فاصل بعد الفرع.');
      return;
    }
    var questionTarget = controller.selectedQuestionIndex;
    if (questionTarget == null && _selectedQuestions.length == 1) {
      questionTarget = document.indexOfQuestion(_selectedQuestions.single);
      if (questionTarget == -1) {
        questionTarget = null;
      }
    }
    questionTarget ??= controller.currentQuestionIndex;
    controller.setQuestionDivider(questionTarget, const PaperDivider());
    _showMessage('تمت إضافة فاصل بعد السؤال.');
  }

  void _updateAttachmentElement(
    _AttachmentRef ref,
    FloatingElement element, {
    bool preservePageIndex = false,
  }) {
    final controller = _controller!;
    if (ref.isGlobal || controller.document.floatingElementById(element.id) != null) {
      controller.updateFloatingElement(element);
      return;
    }
    // رفع المرفق المحفوظ بصيغة قديمة عند أول تعديل، مع إبقائه على صفحة
    // سؤاله الحالية ما لم يغيّر المستخدم الصفحة أثناء السحب.
    final ownerPage = controller.pagination.pageIndexOf(
          controller.questions[ref.questionIndex].id,
        ) ??
        element.pageIndex;
    final placed = element.copyWith(
      pageIndex: preservePageIndex || element.pageIndex != 0 ? element.pageIndex : ownerPage,
    );
    if (ref.branchIndex == null) {
      controller.updateQuestionAttachment(
        ref.questionIndex,
        placed,
        pageIndex: placed.pageIndex,
      );
    } else {
      controller.updateAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        placed,
        pageIndex: placed.pageIndex,
      );
    }
  }

  /// يربط العنصر بالسؤال المحدد أو يفصل ارتباطه عنه.
  void _toggleElementOwner(_AttachmentRef ref, FloatingElement element) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (element.isQuestionOwned) {
      controller.setElementOwner(element.id, null);
      _showMessage('فُصل العنصر عن السؤال — صار حراً في أي موضع على الورقة.');
      return;
    }
    final owner = _selectedOwnerQuestionId();
    if (owner == null) {
      _showMessage('حدد سؤالاً أولاً (بنقرة عليه) ثم اربط العنصر به.');
      return;
    }
    controller.setElementOwner(element.id, owner);
    _showMessage('رُبط العنصر بالسؤال — حركته محصورة داخل حدوده.');
  }

  void _removeAttachmentElement(_AttachmentRef ref) {
    final controller = _controller!;
    if (ref.isGlobal || controller.document.floatingElementById(ref.elementId) != null) {
      controller.removeFloatingElement(ref.elementId);
    } else if (ref.branchIndex == null) {
      controller.removeQuestionAttachment(ref.questionIndex, ref.elementId);
    } else {
      controller.removeAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        ref.elementId,
      );
    }
    setState(() => _selectedAttachment = null);
  }

  /// يفتح محرّر المعادلات المرئي لمعادلة قائمة على الورقة ويحفظ نتيجتها.
  ///
  /// التعديل لا يمسّ الموضع: يبقى العنصر حيث وضعه المستخدم تماماً.
  Future<void> _editFormulaElement(_AttachmentRef ref) async {
    final document = _controller!.document;
    final element = _findAttachment(document, ref);
    if (element == null) {
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: element.label,
      saveLabel: 'حفظ',
    );
    if (snippet == null || !mounted) {
      return;
    }
    final latex = _formulaBodyOf(snippet);
    if (latex.isEmpty) {
      return;
    }
    _updateAttachmentElement(ref, element.copyWith(label: latex));
  }

  Future<void> _editTextBox(_AttachmentRef ref) async {
    final document = _controller!.document;
    final element = _findAttachment(document, ref);
    if (element == null) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'مربع نص',
      initialText: element.label,
      hintText: 'اكتب النص هنا... (ملاحظة، تمنيات...)',
      maxLines: 4,
    );
    if (saved == null) {
      return;
    }
    _updateAttachmentElement(ref, element.copyWith(label: saved));
  }

  /// يعرض حوار [_TextInputDialog] المشترك ويعيد النص المحفوظ
  /// (أو null عند الإلغاء) — الـ controller مملوك للحوار نفسه.
  Future<String?> _showTextInputDialog({
    required String title,
    required String initialText,
    String? hintText,
    String? helperText,
    String saveLabel = 'حفظ',
    bool numeric = false,
    int? maxLines,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: title,
        initialText: initialText,
        hintText: hintText,
        helperText: helperText,
        saveLabel: saveLabel,
        numeric: numeric,
        maxLines: maxLines,
      ),
    );
  }

  /// رقم السؤال: ما يكتبه المدرس يُطبع حرفياً («س١/»، «السؤال الاول/»)،
  /// والفارغ = ترقيم تلقائي من نمط التسمية العام.
  Future<void> _editQuestionLabel(int questionIndex) async {
    final controller = _controller!;
    final document = controller.document;
    final question = document.questions[questionIndex];
    final saved = await _showTextInputDialog(
      title: 'رقم السؤال',
      initialText: question.numberOverride ?? '',
      hintText: 'مثال: س١/ أو السؤال الاول/ — تلقائي: '
          '${document.autoQuestionLabel(question)}${document.layout.questionSeparator}',
      helperText: 'يُطبع كما تكتبه تماماً. اتركه فارغاً للعودة للترقيم التلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateQuestionNumberOverride(questionIndex, saved);
  }

  /// درجة السؤال: يكتب المدرس الرقم الخام فقط («20») فيطبعه النظام
  /// «(٢٠ درجة)»؛ والفارغ = مجموع درجات الفروع والنقاط تلقائياً.
  Future<void> _editQuestionMarks(int questionIndex) async {
    final controller = _controller!;
    final document = controller.document;
    final question = document.questions[questionIndex];
    final saved = await _showTextInputDialog(
      title: 'درجة السؤال',
      initialText: _formatMarksInput(question.marksOverride ?? 0),
      hintText: 'اكتب الرقم فقط، مثال: 20',
      helperText: 'تُطبع تلقائياً بصيغة (${document.formatNumber(20)} ${document.layout.marksUnit}). '
          'فارغ = مجموع درجات الفروع تلقائياً.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    if (saved.trim().isEmpty) {
      controller.updateQuestionMarksOverride(questionIndex, null);
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 20).', isError: true);
      return;
    }
    controller.updateQuestionMarksOverride(questionIndex, marks);
  }

  /// رقم الفرع («أ»...) — يُضاف القوس تلقائياً؛ فارغ = تلقائي من الفهرس.
  Future<void> _editBranchLabel(BranchRef ref) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final branch = document.branchAt(ref);
    final saved = await _showTextInputDialog(
      title: 'رقم الفرع',
      initialText: branch.labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoBranchLabel(ref.branchIndex)}',
      helperText: 'مثال: أ — يُضاف القوس تلقائياً. فارغ = تلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateBranchLabelOverride(ref, saved);
  }

  /// درجة الفرع: الرقم الخام فقط، ويطبعه النظام «(٥ درجة)».
  Future<void> _editBranchMarks(BranchRef ref) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'درجة الفرع',
      initialText: _formatMarksInput(document.branchAt(ref).marks),
      hintText: 'اكتب الرقم فقط، مثال: 5',
      helperText: 'تُطبع تلقائياً بصيغة (${document.formatNumber(5)} ${document.layout.marksUnit}).',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 5).', isError: true);
      return;
    }
    controller.updateBranchMarks(ref, marks);
  }

  void _addBranchToSelected() {
    final controller = _controller!;
    final target = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex ?? controller.currentQuestionIndex;
    controller.addBranch(target);
  }

  /// مزود المكتبة إن وُجد فوق الشاشة (قد تُفتح الشاشة مستقلة في الاختبارات).
  ExamDocumentProvider? _libraryProvider() {
    try {
      return context.read<ExamDocumentProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final provider = _libraryProvider();
    if (provider == null) {
      _showMessage('الحفظ غير متاح في هذا السياق.', isError: true);
      return;
    }
    setState(() => _isBusy = true);
    try {
      await provider.saveDocument(_controller!.document.touched());
      if (mounted) {
        _showMessage('تم حفظ الورقة.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر حفظ الورقة. حاول مرة أخرى.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _exportPdf({List<List<String>>? pageAssignments}) async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    final document = controller.document;
    setState(() => _isBusy = true);
    try {
      final printAssignments = pageAssignments ??
          await PdfExportService.resolvePageAssignments(document: document);
      final bytes = await PdfExportService.buildDocumentPdfBytes(
        document: document,
        // القياس من محتوى الطباعة فقط؛ ارتفاع أدوات التحرير لا يترك فراغاً.
        pageAssignments: printAssignments,
      );
      if (!mounted) {
        return;
      }
      await _saveToLibrary();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            title: 'معاينة ورقة الأسئلة',
            fileName: '${controller.document.name}_ورقة_الامتحان.pdf',
          ),
        ),
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('Wizard PDF export failed', error, stackTrace);
      if (mounted) {
        _showMessage('تعذر إنشاء ملف الـ PDF. حاول مرة أخرى.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _exportWord({List<List<String>>? pageAssignments}) async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    final document = controller.document;
    setState(() => _isBusy = true);
    try {
      final printAssignments = pageAssignments ??
          await PdfExportService.resolvePageAssignments(document: document);
      if (!mounted) return;
      final file = await DocxDocumentExportService.exportDocumentToDocx(
        document: document,
        shapeRasterizer: ShapeImageRenderer.asRasterizer,
        pageAssignments: printAssignments,
        // معادلات LaTeX تُرسم صوراً في Word (لا أكواد خامة) بنفس مرسّم PDF.
        mathRasterizer: MathImageRenderer.asRasterizer,
      );
      if (!mounted) {
        return;
      }
      await _saveToLibrary();
      if (!mounted) {
        return;
      }
      _showMessage('تم إنشاء ملف Word.');
      await DocxDocumentExportService.shareDocxFile(file);
    } catch (error, stackTrace) {
      ExportFileService.logError('Wizard Word export failed', error, stackTrace);
      if (mounted) {
        _showMessage('تعذر إنشاء ملف الـ Word. حاول مرة أخرى.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// كل ورقة تصل للتصدير تُحفظ في مكتبة الأوراق تلقائياً.
  Future<void> _saveToLibrary() async {
    final provider = _libraryProvider();
    if (provider == null) {
      return;
    }
    try {
      await provider.saveDocument(_controller!.document.touched());
    } catch (_) {
      // فشل الحفظ الصامت لا يمنع إتمام التصدير؛ يُبلغ المستخدم برسالة.
      if (mounted) {
        _showMessage('تم التصدير، لكن تعذّر حفظ الورقة في المكتبة.', isError: true);
      }
    }
  }

  /// حوار إدخال حجم خط حر (6..32) للتحديد الحالي.
  Future<void> _showCustomFontSize() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق الحجم.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'حجم خط مخصص',
      initialText: _activeStyle().fontSize?.toStringAsFixed(0) ?? '',
      hintText: 'مثال: 13 (بين 6 و 32)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final size = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (size == null || !size.isFinite || size < 6 || size > 32) {
      _showMessage('أدخل حجماً بين 6 و 32.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(fontSize: () => size));
  }

  /// تباعد أسطر مخصص (حوار حر) — يطبق على التحديد الحالي.
  Future<void> _showCustomLineHeight() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق التباعد.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'تباعد أسطر مخصص',
      initialText: _activeStyle().lineHeight?.toString() ?? '',
      hintText: 'مثال: 1.3 (بين 0.5 و 4.0)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final value = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value < 0.5 || value > 4.0) {
      _showMessage('أدخل تباعداً بين 0.5 و 4.0.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(lineHeight: () => value));
  }

  /// مسافة مخصصة بين الفقرات (بكسل منطقي)، مستقلة عن تباعد السطر.
  Future<void> _showCustomParagraphSpacing() async {
    final targets = _styleTargets();
    if (targets.branches.isEmpty && targets.questions.isEmpty) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق المسافة.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'المسافة بين الفقرات',
      initialText: _activeStyle().paragraphSpacing?.toString() ?? '',
      hintText: 'مثال: 4 (بين 0 و 40 بكسل)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) return;
    final value = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value < 0 || value > 40) {
      _showMessage('أدخل مسافة بين 0 و 40 بكسل.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(paragraphSpacing: () => value));
  }

  /// لون نص مخصص HEX (حوار حر) — يطبق على التحديد الحالي.
  Future<void> _showCustomColor() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق اللون.');
      return;
    }
    final activeColor = _activeColor();
    final initialColor = activeColor == null
        ? ''
        : (activeColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final saved = await _showTextInputDialog(
      title: _colorTooltip() == 'لون عنوان السؤال'
          ? 'لون عنوان السؤال المخصص'
          : 'لون نص مخصص',
      initialText: initialColor,
      hintText: 'مثال: 1E3A8A أو #B91C1C',
      saveLabel: 'تطبيق',
    );
    if (saved == null) {
      return;
    }
    var hex = saved.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null || (hex.length != 6 && hex.length != 8)) {
      _showMessage('أدخل لون HEX صحيحاً (6 خانات مثل 1E3A8A).', isError: true);
      return;
    }
    final argb = hex.length == 6 ? 0xFF000000 | parsed : parsed;
    _applyColor(argb);
  }

  /// ترقيم النقطة (سؤال أو فرع): مخصص حرفي، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editPointLabel(PointsOwner owner, String pointId) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final points = document.pointsOf(owner);
    final index = points.indexWhere((point) => point.id == pointId);
    if (index < 0) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'ترقيم النقطة',
      initialText: points[index].labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoItemLabel(index)}',
      helperText: 'مثال: أ-، 1) — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updatePointLabel(owner, pointId, saved);
  }

  /// درجة النقطة: الرقم الخام فقط («2») فيطبعه النظام «(٢ درجة)».
  ///
  /// الفارغ يعيد الدرجة صفراً (بلا درجة معلنة)، والإعداد «إظهار درجات
  /// الأسئلة» وحده يقرر ظهورها على الورقة.
  Future<void> _editPointMarks(PointsOwner owner, String pointId) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final points = document.pointsOf(owner);
    final index = points.indexWhere((point) => point.id == pointId);
    if (index < 0) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'درجة النقطة',
      initialText: _formatMarksInput(points[index].marks),
      hintText: 'اكتب الرقم فقط، مثال: 2',
      helperText:
          'تُطبع بصيغة (${document.formatNumber(2)} ${document.layout.marksUnit}). '
          'فارغ = بلا درجة.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    if (saved.trim().isEmpty) {
      controller.updatePointMarks(owner, pointId, 0);
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 2).', isError: true);
      return;
    }
    controller.updatePointMarks(owner, pointId, marks);
  }

  /// تسمية الخيار: مخصصة حرفياً، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editOptionLabel(PointsOwner owner, String pointId, int index) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final options = document.pointsOf(owner)
        .where((point) => point.id == pointId)
        .expand((point) => point.options)
        .toList(growable: false);
    if (index < 0 || index >= options.length) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'تسمية الخيار',
      initialText: options[index].labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoOptionLabel(index)}',
      helperText: 'مثال: ( أ )، A. — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updatePointOptionLabel(owner, pointId, index, saved);
  }

  /// يفتح محرر المعادلات المرئي للحقل النشط (مسار شريط الصيغ).
  ///
  /// - [template] صيغة جاهزة تُحمَّل في المحرر (أو null لمعادلة فارغة).
  /// - [preferBlock] يقترح النمط المنفرد `$$...$$`.
  /// - [editExisting] يحرّر صيغة موجودة في الحقل بدل إدراج جديدة.
  /// يحرّر صيغ الحقل [fieldKey] (زر الفرع/المعاينة الغنية) أو يدرج جديدة.
  Future<void> _editEquationInField(String fieldKey) async {
    final field = _fields[fieldKey];
    if (field == null) {
      return;
    }
    _inserter.controller = field;
    await _editEquationInFieldController(field, editExisting: true);
  }

  Future<void> _editEquationInFieldController(
    TextEditingController active, {
    String? template,
    bool preferBlock = false,
    bool editExisting = false,
  }) async {
    TexMathSpan? editingSpan;
    var initialLatex = template;
    var initialIsBlock = preferBlock;
    if (template == null && editExisting) {
      final spans = TexContent.findSpans(active.text);
      if (spans.length == 1) {
        editingSpan = spans.single;
      } else if (spans.length > 1) {
        final offset = active.selection.isValid ? active.selection.start : -1;
        final atCursor = spans
            .where((span) => offset >= span.start && offset <= span.end)
            .toList(growable: false);
        if (atCursor.isNotEmpty) {
          editingSpan = atCursor.first;
        } else {
          editingSpan = await showEquationSpanPicker(
            context: context,
            spans: spans,
          );
          if (editingSpan == null) {
            return;
          }
        }
      }
      if (editingSpan != null) {
        initialLatex = editingSpan.latex;
        initialIsBlock = editingSpan.isBlock;
      }
    }
    if (!mounted) {
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: initialLatex,
      initialIsBlock: initialIsBlock,
      saveLabel: editingSpan == null ? 'إدراج' : 'حفظ',
    );
    if (snippet == null || !mounted) {
      return;
    }
    if (editingSpan != null) {
      // يستبدل الصيغة في موضعها الأصلي تماماً (بفهارس findSpans).
      active.text =
          active.text.replaceRange(editingSpan.start, editingSpan.end, snippet);
      active.selection =
          TextSelection.collapsed(offset: editingSpan.start + snippet.length);
    } else {
      _inserter.controller = active;
      _inserter.insert(snippet);
    }
  }

  /// يُلغي المعادلة المرشّحة (إن أراد المستخدم التراجع قبل إقامتها).
  void _clearStagedFormula() {
    if (_stagedFormula == null) {
      return;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
    });
    _showMessage('أُلغي إدراج المعادلة.');
  }

  /// نهاية سحب بطاقة المعادلة من الشريط: يُسقطها [DragTarget] على الورقة.
  ///
  /// إن لم تُسقط على الورقة (سحب ملغى) تبقى مرشّحة كي ينقر المستخدم موضعها
  /// بنفسه، فنرشده إلى ذلك.
  void _handleFormulaDragEnd(DraggableDetails details) {
    if (_stagedFormula == null) {
      return;
    }
    _showMessage('لم يُسقط العنصر على الورقة: انقر داخل الورقة لتحديد موضع المعادلة.');
  }

  Future<void> _showReview() async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    final document = controller.document;
    var pageAssignments = <List<String>>[];
    setState(() => _isBusy = true);
    try {
      // اعرض عدد الصفحات الفعلي للتصدير، لا صفحات مساحة التحرير التي قد
      // تحتوي على أسئلة فارغة غير قابلة للطباعة.
      pageAssignments = await PdfExportService.resolvePageAssignments(
        document: document,
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('Preview pagination failed', error, stackTrace);
      if (mounted) {
        _showMessage('تعذر حساب توزيع صفحات التصدير.');
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
    if (!mounted) {
      return;
    }
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final exportableQuestions = document.questions
        .where((question) => question.hasExportableContent(
              ignoredAttachmentIds: globalElementIds,
            ))
        .toList(growable: false);
    final exportableBranchCount = exportableQuestions
        .expand((question) => question.branches)
        .where((branch) => branch.hasExportableContentIn(
              ignoredAttachmentIds: globalElementIds,
            ))
        .length;
    final exportableMarks = exportableQuestions.fold<double>(
      0,
      (sum, question) => sum + question.marks,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مراجعة الورقة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _reviewRow(
                'عدد الأسئلة',
                document.formatNumber(exportableQuestions.length),
              ),
              _reviewRow('عدد الفروع', document.formatNumber(exportableBranchCount)),
              _reviewRow(
                'عدد الصفحات',
                document.formatNumber(pageAssignments.length),
              ),
              _reviewRow(
                'الدرجة الكلية',
                '${document.formatNumber(exportableMarks)} ${document.layout.marksUnit}',
              ),
              _reviewRow('حجم الورق', 'A4'),
              _reviewRow('الخط الافتراضي', document.settings.defaultFont.arabicLabel),
              _reviewRow('نمط التسمية', document.settings.questionLabelStyle.arabicLabel),
              _reviewRow(
                'الهوامش',
                '${document.settings.marginMm.toStringAsFixed(0)} مم',
              ),
              _reviewRow(
                'تباعد الأسطر',
                document.settings.lineSpacing.toStringAsFixed(2),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('رجوع'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportPdf(pageAssignments: pageAssignments);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('تصدير PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportWord(pageAssignments: pageAssignments);
            },
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('تصدير Word'),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSlider({
    required String label,
    required String value,
    required double sliderValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: sliderValue,
          min: min,
          max: max,
          divisions: divisions,
          label: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _showSettings() async {
    final controller = _controller!;
    final originalSettings = controller.document.settings;
    var settings = originalSettings;
    // ملفات الإطار المختارة داخل هذا الحوار: تُحذف المتروكة منها عند الإلغاء أو
    // الاستبدال حتى لا تتراكم ملفات يتيمة.
    final sessionFramePaths = <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('إعدادات الورقة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SwitchListTile(
                  dense: true,
                  title: const Text('ترقيم تلقائي للأسئلة', style: TextStyle(fontSize: 13)),
                  value: settings.autoNumberQuestions,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(autoNumberQuestions: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('ترميز تلقائي للفروع (أ، ب...)', style: TextStyle(fontSize: 13)),
                  value: settings.autoLetterBranches,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(autoLetterBranches: value),
                  ),
                ),
                DropdownButtonFormField<PaperNumerals>(
                  value: settings.numerals,
                  decoration: const InputDecoration(
                    labelText: 'نسق الأرقام',
                    hintText: 'اختر شكل الأرقام المطبوعة (١٢٣ أو 123)',
                    helperText: 'يسري على الأسئلة والفروع والنقاط والتواريخ في الورقة.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PaperNumerals.values
                      .map((n) => DropdownMenuItem<PaperNumerals>(
                            value: n,
                            child: Text(n.arabicLabel, style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => settings = settings.copyWith(numerals: value));
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<QuestionLabelStyle>(
                  value: settings.questionLabelStyle,
                  decoration: const InputDecoration(
                    labelText: 'نمط تسمية الأسئلة',
                    hintText: 'اختر «رسمي (السؤال الأول)» أو «مختصر (س1)»',
                    helperText: 'ما تكتبه يدوياً في رقم أي سؤال يتقدم على النمط دائماً.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: QuestionLabelStyle.values
                      .map((style) => DropdownMenuItem<QuestionLabelStyle>(
                            value: style,
                            child: Text(
                              style.arabicLabel,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(
                        () => settings = settings.copyWith(questionLabelStyle: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PaperFont>(
                  value: settings.defaultFont,
                  decoration: const InputDecoration(
                    labelText: 'الخط الافتراضي للورقة',
                    hintText: 'اختر خط متن الورقة الافتراضي',
                    helperText: 'يسري على كل نص لم تخصّص له خطاً من شريط التنسيق.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PaperFont.values
                      .map((font) => DropdownMenuItem<PaperFont>(
                            value: font,
                            child: Text(
                              font.arabicLabel,
                              style: TextStyle(fontSize: 13, fontFamily: font.family),
                            ),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => settings = settings.copyWith(defaultFont: value));
                    }
                  },
                ),
                _settingsSlider(
                  label: 'هوامش الصفحة',
                  value: '${settings.marginMm.toStringAsFixed(0)} مم',
                  sliderValue: settings.marginMm,
                  min: PaperSettings.minMarginMm,
                  max: PaperSettings.maxMarginMm,
                  divisions: 17,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(marginMm: value),
                  ),
                ),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'الهامش هو حشوة الإطار: يبتعد النص بقدره عن حافة الورقة فلا يتداخل مع الإطار.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                _settingsSlider(
                  label: 'حجم الخط الأساسي',
                  value: settings.baseFontSize.toStringAsFixed(1),
                  sliderValue: settings.baseFontSize,
                  min: 8,
                  max: 16,
                  divisions: 16,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(baseFontSize: value),
                  ),
                ),
                _settingsSlider(
                  label: 'تباعد الأسطر العام',
                  value: settings.lineSpacing.toStringAsFixed(2),
                  sliderValue: settings.lineSpacing,
                  min: 1,
                  max: 2.5,
                  divisions: 15,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(lineSpacing: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إظهار درجات الأسئلة', style: TextStyle(fontSize: 13)),
                  value: settings.showQuestionMarks,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(showQuestionMarks: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إطار حول الصفحة', style: TextStyle(fontSize: 13)),
                  value: settings.pageBorder,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(pageBorder: value),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text(
                    'صورة إطار الصفحة (PNG شفاف)',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    settings.hasFrameImage
                        ? 'صورة مختارة: تُرسم خلف النص بحجم الورقة كاملة'
                        : 'اختر صورة PNG شفافة بحجم A4 (اختياري) — يبتعد النص عنها بقدر الهوامش',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextButton(
                        onPressed: () async {
                          final path = await _pickFrameImage();
                          if (path != null) {
                            sessionFramePaths.add(path);
                            setDialogState(
                              () => settings = settings.copyWith(
                                frameImagePath: () => path,
                                pageBorder: true,
                              ),
                            );
                          }
                        },
                        child: Text(settings.hasFrameImage ? 'تغيير' : 'اختيار'),
                      ),
                      if (settings.hasFrameImage)
                        IconButton(
                          tooltip: 'إزالة صورة الإطار',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => setDialogState(
                            () => settings = settings.copyWith(frameImagePath: () => null),
                          ),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إطار حول الترويسة', style: TextStyle(fontSize: 13)),
                  value: settings.headerBorder,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(headerBorder: value),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                for (final path in sessionFramePaths) {
                  unawaited(PageFrameStore.delete(path));
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                controller.updateSettings(settings);
                final kept = settings.frameImagePath;
                for (final path in <String?>[
                  originalSettings.frameImagePath,
                  ...sessionFramePaths,
                ]) {
                  if (path != null && path != kept) {
                    unawaited(PageFrameStore.delete(path));
                  }
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  /// يختار صورة إطار PNG من المعرض ويحفظها في مساحة التطبيق (يعيد مسارها).
  Future<String?> _pickFrameImage() async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage(
        'تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.',
        isError: true,
      ),
    );
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      return await PageFrameStore.save(bytes);
    } catch (error, stackTrace) {
      ExportFileService.logError('Page frame save failed', error, stackTrace);
      _showMessage('تعذر حفظ صورة الإطار على الجهاز.', isError: true);
      return null;
    }
  }

  // ------------------------------------------------------------------
  // التكبير والعرض
  // ------------------------------------------------------------------

  void _zoomBy(double factor) {
    setState(() => _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom));
  }

  void _fitToScreen() {
    if (_viewportWidth <= 0) {
      return;
    }
    setState(
      () => _zoom = ((_viewportWidth - 24) / ExamCanvasGeometry.width)
          .clamp(_minZoom, 1.5),
    );
  }

  /// يوسّط الورقة مع الحفاظ على الزوم الحالي (لا يعيد الملاءمة).
  void _centerPaper() {
    if (_vScroll.hasClients) {
      _vScroll.jumpTo(0);
    }
    if (_hScroll.hasClients && _hScroll.position.maxScrollExtent > 0) {
      _hScroll.jumpTo(_hScroll.position.maxScrollExtent / 2);
    }
  }

  void _maybeAutoFit() {
    if (_didAutoFit || _viewportWidth <= 0) {
      return;
    }
    _didAutoFit = true;
    if (_viewportWidth < ExamCanvasGeometry.width + 24) {
      _fitToScreen();
    }
  }

  // ------------------------------------------------------------------
  // البناء
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final layout = controller.layout;
    final pagination = controller.pagination;
    final document = controller.document;
    final activeStyle = _activeStyle();

    return Scaffold(
      appBar: AppBar(
        // العنوان ثابت حرفياً (تعتمد عليه اختبارات الواجهة)؛ عدد الصفحات
        // يظهر في حوار المراجعة قبل التصدير.
        title: const Text('الخطوة 3: معاينة A4'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'العودة للأسئلة',
          onPressed: widget.onBackToQuestions,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'إعدادات الورقة',
            onPressed: _isBusy ? null : _showSettings,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'حفظ الورقة',
            onPressed: _isBusy ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          PreviewToolbar(
            selectionLabel: _selectionLabel(document),
            canUndo: controller.canUndo,
            onUndo: controller.undo,
            canRedo: controller.canRedo,
            onRedo: controller.redo,
            locked: _locked,
            onToggleLock: () => setState(() => _locked = !_locked),
            zoom: _zoom,
            onZoomIn: () => _zoomBy(1.2),
            onZoomOut: () => _zoomBy(1 / 1.2),
            onZoomReset: () => setState(() => _zoom = 1.0),
            onFit: _fitToScreen,
            onCenter: _centerPaper,
            multiSelect: _multiSelect,
            onToggleMultiSelect: () => setState(() {
              _multiSelect = !_multiSelect;
              _clearSelection();
            }),
            activeFont: activeStyle.font,
            onFontChanged: (font) => _applyStyle(
              (current) => current.copyWith(font: () => font),
            ),
            activeFontSize: activeStyle.fontSize,
            onFontSizeChanged: (size) {
              // القيمة المميزة NaN تعني «حجم مخصص» من قائمة الشريط.
              if (size != null && size.isNaN) {
                _showCustomFontSize();
                return;
              }
              _applyStyle((current) => current.copyWith(fontSize: () => size));
            },
            isBold: activeStyle.bold,
            onToggleBold: () => _applyStyle(
              (current) => current.copyWith(bold: () => !(current.bold ?? false)),
            ),
            isItalic: activeStyle.italic,
            onToggleItalic: () => _applyStyle(
              (current) => current.copyWith(italic: () => !(current.italic ?? false)),
            ),
            isUnderline: activeStyle.underline,
            onToggleUnderline: () => _applyStyle(
              (current) =>
                  current.copyWith(underline: () => !(current.underline ?? false)),
            ),
            activeAlign: _activeAlign(),
            onAlignChanged: _onAlignChanged,
            activeLineHeight: activeStyle.lineHeight,
            onLineHeightChanged: (value) {
              // القيمة المميزة NaN تعني «تباعد مخصص» من قائمة الشريط.
              if (value != null && value.isNaN) {
                _showCustomLineHeight();
                return;
              }
              _applyStyle((current) => current.copyWith(lineHeight: () => value));
            },
            activeParagraphSpacing: activeStyle.paragraphSpacing,
            onParagraphSpacingChanged: (value) {
              if (value != null && value.isNaN) {
                _showCustomParagraphSpacing();
                return;
              }
              _applyStyle(
                (current) => current.copyWith(paragraphSpacing: () => value),
              );
            },
            activeQuestionSpacing: _activeQuestionSpacing(),
            onQuestionSpacingChanged: (spacing) {
              if (spacing.isNaN) {
                _showCustomQuestionSpacing();
                return;
              }
              _applyQuestionSpacing(spacing);
            },
            activeColor: _activeColor(),
            colorTooltip: _colorTooltip(),
            onColorChanged: (value) {
              // القيمة المميزة -1 تعني «لون مخصص» (HEX) من قائمة الشريط.
              if (value != null && value == PreviewToolbar.customColorSentinel) {
                _showCustomColor();
                return;
              }
              _applyColor(value);
            },
            hasFrame: _activeFrame(),
            onToggleFrame: _toggleFrame,
            onAddImage: _pickImageToSelection,
            onAddShape: _addShapeToSelection,
            onAddTextBox: _addTextBox,
            onAddDivider: _addDividerToSelection,
            showFormulas: _showFormulas,
            onToggleFormulas: () => setState(() => _showFormulas = !_showFormulas),
            onSave: _save,
            onExportPdf: _showReview,
            onExportWord: _showReview,
            isBusy: _isBusy,
          ),
          if (_showFormulas)
            SmartExamToolbar(
              inserter: _inserter,
              onInsertText: _insertText,
              onAddImage: _addImageToSelection,
              onAddShape: _addShapeToSelection,
              onAddQuestion: controller.addQuestion,
              onAddBranch: _addBranchToSelected,
              onAddTextBox: _addTextBox,
              onAddDivider: _addDividerToSelection,
              stagedFormula: _stagedFormula,
              onEquationEditor: _openEquationEditor,
              onAddFormula: _openEquationEditor,
              onFormulaDragEnd: _handleFormulaDragEnd,
              onClearStagedFormula: _clearStagedFormula,
            ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportWidth = constraints.maxWidth;
                SchedulerBinding.instance.addPostFrameCallback((_) => _maybeAutoFit());
                final contentWidth = (_viewportWidth > ExamCanvasGeometry.width * _zoom + 24
                        ? _viewportWidth
                        : ExamCanvasGeometry.width * _zoom + 24)
                    .toDouble();
                return SingleChildScrollView(
                  key: const ValueKey<String>('paper-v-scroll'),
                  controller: _vScroll,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('paper-h-scroll'),
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        children: <Widget>[
                          for (final page in pagination.pages)
                            _buildZoomedPage(controller, layout, page, pagination.pageCount),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomedPage(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    PaginatedPage page,
    int pageCount,
  ) {
    // FittedBox بنفس نسبة الأبعاد = تكبير تخطيطي صحيح (القياس الداخلي
    // يبقى بالمقاس الحقيقي، والتفاعل مع الحقول يعمل تحت كل تكبير).
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: ExamCanvasGeometry.width * _zoom,
        height: ExamCanvasGeometry.height * _zoom,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: ExamCanvasGeometry.width,
            height: ExamCanvasGeometry.height,
            child: _buildPage(controller, layout, page, pageCount),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    PaginatedPage page,
    int pageCount,
  ) {
    final document = controller.document;
    final blueprint = controller.blueprint;
    final blocks = <Widget>[];
    String? previousBlockId;
    for (final blockId in page.blockIds) {
      if (blocks.isNotEmpty) {
        final previousQuestion = previousBlockId == null
            ? null
            : document.questionById(previousBlockId);
        blocks.add(
          SizedBox(
            height: previousQuestion?.spacingAfter ?? PaperMetrics.blockSpacingPx,
          ),
        );
      }
      if (blockId == PaperMetrics.headerBlockId) {
        blocks.add(
          MeasureSize(
            key: const ValueKey<String>('measure-header'),
            onChange: (size) => controller.reportBlockHeight(blockId, size.height),
            child: _buildHeaderBlock(controller),
          ),
        );
        previousBlockId = blockId;
        continue;
      }
      final questionData = blueprint.questionById(blockId);
      if (questionData == null) {
        continue;
      }
      // بحث بالمعرف لا بالهوية: نسخ المستند تستبدل النسخ لا المعرفات.
      final questionIndex = questionData.index;
      // إفلات سؤال مسحوب هنا يعيد ترتيبه (السؤال وحدة لا تتجزأ).
      blocks.add(
        DragTarget<int>(
          onWillAcceptWithDetails: (details) => !_locked && details.data != questionIndex,
          onAcceptWithDetails: (details) => controller.moveQuestion(details.data, questionIndex),
          builder: (context, candidates, _) {
            final highlighted = candidates.isNotEmpty;
            return Container(
              decoration: highlighted
                  ? BoxDecoration(
                      color: const Color(0x1A2563EB),
                      border: Border.all(color: PaperStyles.accent, width: 1.4),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: MeasureSize(
                key: ValueKey<String>('measure-$blockId'),
                onChange: (size) => controller.reportBlockHeight(blockId, size.height),
                child: _buildQuestionBlock(controller, layout, questionData),
              ),
            );
          },
        ),
      );
      previousBlockId = blockId;
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
    // كتلة واحدة أطول من الصفحة كاملة: تُصغَّر بتناسق (كما في الـ PDF) بدل قصّها.
    if (page.overflows) {
      content = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: PaperMetrics.contentWidthFor(document.settings.marginMm),
          child: content,
        ),
      );
    }

    // كل العناصر العائمة تُرسم في طبقة **الصفحة** بإحداثياتها المطلقة:
    // فيصير موضعها حرًّا فعلًا في أي نقطة على الورقة (أعلى/أسفل/جوانب)،
    // وقابلةً للمس والسحب في أي مكان (اختبار الإصابة لا يتجاوز حدود الأب،
    // والطبقة بحجم الورقة كاملة)، وبنفس الإحداثيات في PDF و Word.
    final pageAttachments = <_AttachmentRef>[];
    final globalElementIds = document.floatingElements.map((element) => element.id).toSet();
    final seenElementIds = <String>{};
    int resolvedPageIndex(FloatingElement element) => _elementGeometry(controller, element)
        .pageIndex
        .clamp(0, math.max(0, pageCount - 1))
        .toInt();

    for (final element in document.floatingElements) {
      if (resolvedPageIndex(element) == page.index && seenElementIds.add(element.id)) {
        pageAttachments.add(_AttachmentRef.global(element.id));
      }
    }

    void collect(QuestionModel question, int index) {
      for (final element in question.attachments) {
        if (globalElementIds.contains(element.id) || !seenElementIds.add(element.id)) {
          continue;
        }
        pageAttachments.add(
          _AttachmentRef(questionIndex: index, elementId: element.id),
        );
      }
      for (var branchIndex = 0;
          branchIndex < question.branches.length;
          branchIndex++) {
        for (final element in question.branches[branchIndex].attachments) {
          if (globalElementIds.contains(element.id) || !seenElementIds.add(element.id)) {
            continue;
          }
          pageAttachments.add(
            _AttachmentRef(
              questionIndex: index,
              branchIndex: branchIndex,
              elementId: element.id,
            ),
          );
        }
      }
    }

    for (final blockId in page.blockIds) {
      final index = document.indexOfQuestion(blockId);
      if (index == -1) {
        continue;
      }
      collect(document.questions[index], index);
    }
    // عناصر الملفات القديمة التي لم تُقَس أسئلتها بعد تُعرض مؤقتاً على الصفحة الأولى.
    if (!controller.isFullyMeasured &&
        page.index == 0 &&
        pageAttachments.isEmpty) {
      for (var index = 0; index < document.questions.length; index++) {
        collect(document.questions[index], index);
      }
    }

    return Directionality(
      textDirection: layout.textDirection,
      child: Container(
        key: _pageCanvasKeys.putIfAbsent(
          page.index,
          () => GlobalKey(debugLabel: 'a4-page-canvas-${page.index}'),
        ),
        width: ExamCanvasGeometry.width,
        height: ExamCanvasGeometry.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        // هدف إسقاط المعادلات المسحوبة من الشريط يغطي **الورقة كلها** (بما
        // فيها الهوامش) فتُقام المعادلة حيث أُفلتت بالضبط، وطبقة المعادلات
        // فوق كل شيء بالإحداثيات المطلقة نفسها.
        child: KeyedSubtree(
          key: ValueKey<String>('a4-page-${page.index}'),
          child: DragTarget<FloatingElement>(
            onWillAcceptWithDetails: (details) => !_locked,
            onAcceptWithDetails: (details) =>
                _acceptFormulaDrop(page.index, details),
            builder: (context, candidates, _) {
              Widget body = Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Positioned.fill(
                    child: _buildPageStack(
                      controller,
                      page,
                      pageCount,
                      content,
                      document,
                      highlighted: candidates.isNotEmpty,
                    ),
                  ),
                  for (final ref in pageAttachments)
                    ..._buildPageElement(controller, ref),
                  // Controls are siblings in the page-sized hit-test area and
                  // painted last so other attachments cannot cover them.
                  for (final ref in pageAttachments)
                    if (!_locked && _selectedAttachment?.elementId == ref.elementId)
                      _buildAttachmentToolbar(ref, _findAttachment(document, ref)!),
                ],
              );
              // معادلة جاهزة تنتظر موضعها: أي نقرة على الورقة تُقيمها في
              // الموضع المنقور (والإحداثيات محلية للورقة كلها بالهوامش).
              if (_stagedFormula != null && !_locked) {
                body = GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) => _placeStagedFormula(
                    details.localPosition,
                    pageIndex: page.index,
                  ),
                  child: body,
                );
              }
              return body;
            },
          ),
        ),
      ),
    );
  }

  /// يهيّئ محتوى الصفحة (الإطار + الكتل + تذييل آخر صفحة) داخل الهوامش؛
  /// والعناصر العائمة طبقة مستقلة فوقه بإحداثيات الصفحة.
  ///
  /// صندوق المحتوى كله يُشتق من هامش واحد (`marginMm`) هو نفسه حشوة الإطار،
  /// فيبتعد النص عن الإطار بقدره دائماً. ولا ترقيم للصفحات إطلاقاً.
  ///
  /// الطبقة نفسها **بحجم الورقة كاملة** وتُدخل الهوامش على أبنائها: اختبار
  /// الإصابة في Flutter لا يتجاوز حدود الأب، فلو كانت الطبقة بحجم مساحة
  /// الطباعة لصار أي عنصر يسحبه المستخدم إلى هامش الورقة غير قابل للمس. الآن
  /// كل نقطة في الورقة قابلة للإصابة (والقصّ على حدود الورقة في [Container]).
  Widget _buildPageStack(
    ExamWizardController controller,
    PaginatedPage page,
    int pageCount,
    Widget content,
    ExamDocument document, {
    required bool highlighted,
  }) {
    final settings = document.settings;
    final margin = ExamCanvasGeometry.marginFor(settings.marginMm);
    final isLastPage = page.index == pageCount - 1;
    // التذييل يُطبع في أسفل آخر صفحة فقط، ومساحته محجوزة من آخر كتلة.
    final footerReserve = isLastPage ? controller.footerReserve : 0.0;
    // صندوق صفحة كامل ⇒ كل العناصر العائمة قابلة للمس أينما وُضعت.
    Widget stack = Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        // الإطار خلف المحتوى: صورة PNG بحجم الورقة أو إطار متجه داخل الهامش.
        if (settings.pageBorder)
          Positioned.fill(
            child: IgnorePointer(child: _buildPageFrame(settings, margin)),
          ),
        // `bottom` يُترك مفتوحاً في الصفحة غير المتجاوزة: المحتوى الأطول من
        // الصفحة (قياس أولي أو كتلة طويلة) يُقصّ على حدود الورقة بلا خطأ
        // تجاوز، ويُصغَّر بتناسق حين تُعلَّم الصفحة متجاوزة.
        Positioned(
          top: margin,
          left: margin,
          right: margin,
          bottom: page.overflows ? margin + footerReserve : null,
          child: content,
        ),
        if (isLastPage)
          Positioned(
            left: margin,
            right: margin,
            bottom: margin,
            child: _buildFooterBlock(controller),
          ),
      ],
    );
    if (highlighted) {
      stack = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.accent, width: 1.6),
        ),
        child: stack,
      );
    }
    return stack;
  }

  /// إطار الصفحة: صورة PNG مختارة تغطي الورقة كاملة (وإن تعذّر فتحها يُرسم
  /// الإطار المتجه)، وإلا إطار متجه بسيط في منتصف المسافة بين الحافة والنص.
  Widget _buildPageFrame(PaperSettings settings, double margin) {
    final vector = Padding(
      padding: EdgeInsets.all(margin * 0.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.ink, width: 1.4),
        ),
      ),
    );
    if (!settings.hasFrameImage) {
      return vector;
    }
    return Image.file(
      File(settings.frameImagePath!),
      fit: BoxFit.fill,
      errorBuilder: (context, error, stackTrace) => vector,
    );
  }

  /// تذييل آخر صفحة (للقراءة فقط): يُقاس ارتفاعه فيُحجز في التقسيم الورقي.
  Widget _buildFooterBlock(ExamWizardController controller) {
    final document = controller.document;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _tapHeader,
      child: MeasureSize(
        key: const ValueKey<String>('measure-footer'),
        onChange: (size) =>
            controller.reportBlockHeight(PaperMetrics.footerBlockId, size.height),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _headerSelected
                  ? PaperStyles.primary.withOpacity(0.45)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: PaperFooterView(
            footer: controller.blueprint.footer,
            style: document.header.style,
            defaultFont: document.settings.defaultFont,
            fontScale: _fontScale,
            heightScale: _heightScale,
          ),
        ),
      ),
    );
  }

  RenderBox? _pageRenderBox(int pageIndex) {
    final renderObject = _pageCanvasKeys[pageIndex]?.currentContext?.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize ? renderObject : null;
  }

  Offset? _localPositionOnPage(int pageIndex, Offset globalPosition) {
    final box = _pageRenderBox(pageIndex);
    return box?.globalToLocal(globalPosition);
  }

  ({int pageIndex, Offset local})? _pageAtGlobalPosition(Offset globalPosition) {
    final pageIndexes = _pageCanvasKeys.keys.toList()..sort();
    for (final pageIndex in pageIndexes) {
      final box = _pageRenderBox(pageIndex);
      if (box == null) continue;
      final local = box.globalToLocal(globalPosition);
      if (Rect.fromLTWH(0, 0, box.size.width, box.size.height).contains(local)) {
        return (pageIndex: pageIndex, local: local);
      }
    }
    return null;
  }

  /// يستقبل بطاقة معادلة أُفلتت على صفحة A4 ويقيمها في الموضع الدقيق.
  void _acceptFormulaDrop(
    int pageIndex,
    DragTargetDetails<FloatingElement> details,
  ) {
    final local = _localPositionOnPage(pageIndex, details.offset);
    if (local == null) return;
    // [DragTargetDetails.offset] موضع المؤشر العام لحظة الإفلات، فينزل
    // العنصر مركزاً تحته تماماً حيث أراد المستخدم.
    final board = _boardPositionFromLocal(
      local,
      width: details.data.width,
      height: details.data.height,
    );
    _dropFormulaOnPage(details.data, board.dx, board.dy, pageIndex: pageIndex);
  }

  /// يبني عنصراً عائماً في موضعه **المطلق** على الورقة (بكسل اللوحة كما كتبه
  /// المستخدم) فوق كل الكتل، فتكون الحركة والإقامة حرّة تماماً.
  Iterable<Widget> _buildPageElement(
    ExamWizardController controller,
    _AttachmentRef ref,
  ) sync* {
    final element = _findAttachment(controller.document, ref);
    if (element == null) {
      yield const SizedBox.shrink();
      return;
    }
    // [_buildAttachment] يعيد عنصراً موضعه `PositionedDirectional` بإحداثيات
    // الورقة نفسها: `dy` من أعلى الورقة، و`dx` من حافة القراءة — فطبقة الصفحة
    // تحمل الإحداثي المطلق بلا لفّ إضافي (ولفّه بـ Positioned يفسد بيانات
    // الأب في Stack).
    yield KeyedSubtree(
      key: ValueKey<String>('page-element-${element.id}'),
      child: _buildAttachment(controller, ref, element),
    );
  }

  /// يُنشئ المعادلة المسحوبة من الشريط في موضع الإفلات على صفحة [pageIndex].
  bool _dropFormulaOnPage(
    FloatingElement element,
    double dx,
    double dy, {
    required int pageIndex,
  }) {
    final controller = _controller;
    if (controller == null) {
      return false;
    }
    final owner = _selectedOwnerQuestionId();
    final ownerRect = owner == null ? null : controller.questionRect(owner);
    final placed = element.copyWith(
      dx: ownerRect == null ? dx : math.max(0, dx - ExamCanvasGeometry.marginFor(controller.document.settings.marginMm)),
      dy: ownerRect == null ? dy : math.max(0, dy - ownerRect.top),
      pageIndex: ownerRect?.pageIndex ?? pageIndex,
    );
    final added = controller.addFloatingElement(
      placed,
      pageIndex: placed.pageIndex,
      ownerQuestionId: owner,
    );
    if (!added) {
      _showMessage('تعذر إدراج المعادلة في هذه الصفحة.');
      return false;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(placed.id);
    });
    _showMessage(
      owner == null
          ? 'أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.'
          : 'أُدرجت المعادلة داخل السؤال المحدد — حركتها محصورة فيه.',
    );
    return true;
  }

  // ------------------------------------------------------------------
  // الترويسة — قابلة للتحرير والتحديد والتنسيق
  // ------------------------------------------------------------------

  /// الترويسة بثلاثة أعمدة (للقراءة فقط على الورقة): النقر يحدّدها لتنسيقها
  /// من الشريط، وزر «تعديل» الظاهر عند تحديدها يفتح ورقة تعديل بيانات
  /// الترويسة والتذييل بتلميحات إرشادية لكل حقل.
  Widget _buildHeaderBlock(ExamWizardController controller) {
    final document = controller.document;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _tapHeader,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
            color: _headerSelected
                ? PaperStyles.primary.withOpacity(0.45)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: <Widget>[
            PaperHeaderView(
              header: controller.blueprint.header,
              style: document.header.style,
              defaultFont: document.settings.defaultFont,
              fontScale: _fontScale,
              heightScale: _heightScale,
            ),
            // أداة تحرير فقط (لا تُطبع ولا تغيّر ارتفاع الكتلة).
            if (_headerSelected)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: IconButton(
                  tooltip: 'تعديل الترويسة والتذييل',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _editHeaderAndFooter,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ورقة تعديل بيانات الترويسة والتذييل: النموذجان نفسهما في الخطوة 1،
  /// وكل تعديل يُطبَّق مباشرة على الورقة (وتتبعه إعادة التقسيم الورقي).
  Future<void> _editHeaderAndFooter() async {
    final controller = _controller!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'تعديل الترويسة والتذييل',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              HeaderForm(
                initial: controller.document.header,
                onChanged: (header) =>
                    controller.updateHeader(header, coalesceKey: 'header-form'),
              ),
              const SizedBox(height: 20),
              FooterForm(
                initial: controller.document.footer,
                onChanged: (footer) =>
                    controller.updateFooter(footer, coalesceKey: 'footer-form'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ) وفروعه
  // ------------------------------------------------------------------

  /// سطر عنوان (سؤال أو فرع) بلا طفح مهما كبر خط الورقة: تسمية الرقم والدرجة
  /// محدودتان بنسبة من عرض السطر فتتلفّفان داخل حدودهما، ويبقى لمنطوق السؤال
  /// وأزرار الإجراءات مكانه. الحد الأقصى لا يغيّر العرض العادي: لا أثر له إلا
  /// إذا تجاوز المحتوى عرض السطر فعلاً.
  Widget _titleRow({
    required Widget dragHandle,
    required Widget label,
    required Widget statement,
    required Widget marks,
    required List<Widget> actions,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            dragHandle,
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.34),
              child: label,
            ),
            const SizedBox(width: 4),
            Expanded(child: statement),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.26),
              child: marks,
            ),
            ...actions,
          ],
        );
      },
    );
  }

  Widget _buildQuestionBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    QuestionBlueprint data,
  ) {
    final document = controller.document;
    final question = data.model;
    final questionIndex = data.index;
    final selected = _isQuestionSelected(questionIndex);
    // الحقول الاختيارية (نص السؤال) تظهر للتحرير عند تحديد السؤال نفسه،
    // وتُحذف كلياً من الواجهة والطباعة عند فراغها.
    final directlySelected = _selectedQuestions.contains(question.id);
    final defaultFont = document.settings.defaultFont;
    final bodyStyle = question.style.copyWith(color: () => null);
    final titleStyle = PaperStyles.resolve(
      PaperStyles.question,
      question.style.copyWith(color: () => question.effectiveTitleColor),
      defaultFont: defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final textStyle = PaperStyles.resolve(
      PaperStyles.prompt,
      bodyStyle,
      defaultFont: defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final paragraphSpacing = question.style.paragraphSpacing;
    final blockSpacing = paragraphSpacing ?? 2;
    final itemSpacing = paragraphSpacing ?? 0;
    final owner = PointsOwner.question(questionIndex);
    final statementKey = _statementKey(question.id);
    final bodyKey = _bodyKey(question.id);

    Widget block = Column(
      key: ValueKey<String>('question-block-${question.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // عنوان قسم السؤال: نص قابل للتحرير مباشرة على الورقة.
        if (data.section != null)
          _paperField(
            fieldKey: _categoryKey(question.id),
            controller: _field(
              _categoryKey(question.id),
              question.category,
              (value) => controller.updateQuestionCategory(questionIndex, value),
            ),
            style: _scaled(PaperStyles.category),
            textAlign: _textAlignFor(_categoryKey(question.id), fallback: TextAlign.start),
            hint: 'عنوان القسم...',
          ),
        // سطر العنوان: الرقم ← المنطوق ← الدرجة «(٢٠ درجة)» في سطر واحد.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _tapQuestion(questionIndex),
          child: _titleRow(
            dragHandle: _locked
                ? Icon(Icons.drag_indicator, size: 18, color: Colors.grey.shade300)
                : LongPressDraggable<int>(
                    data: questionIndex,
                    feedback: Material(
                      elevation: 4,
                      color: Colors.white,
                      child: Container(
                        width: 320,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          data.title.line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _scaled(PaperStyles.question),
                        ),
                      ),
                    ),
                    childWhenDragging: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: Colors.grey.shade300,
                    ),
                    child: Semantics(
                      label: 'اضغط مطولاً واسحب لنقل السؤال كاملاً',
                      child: Icon(Icons.drag_indicator,
                          size: 18, color: Colors.grey.shade600),
                    ),
                  ),
            label: Tooltip(
              message: 'انقر لتعديل رقم السؤال',
              child: GestureDetector(
                onTap: () => _editQuestionLabel(questionIndex),
                child: Text(data.title.number, style: titleStyle),
              ),
            ),
            statement: _paperField(
              fieldKey: statementKey,
              controller: _field(
                statementKey,
                question.statement,
                (value) => controller.updateQuestionStatement(questionIndex, value),
              ),
              style: titleStyle,
              textAlign: _textAlignFor(
                statementKey,
                fallback: PaperStyles.toTextAlign(
                  question.titleAlign ?? question.style.align,
                ),
              ),
              hint: layout.isLtr
                  ? 'Question statement...'
                  : 'اكتب منطوق السؤال هنا...',
            ),
            marks: _marksTarget(
              marks: data.title.marks,
              showPlaceholder: document.settings.showQuestionMarks,
              style: titleStyle,
              onEdit: () => _editQuestionMarks(questionIndex),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'إضافة فرع',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => controller.addBranch(questionIndex),
              ),
              IconButton(
                tooltip: 'نسخ السؤال',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 16),
                onPressed: () => controller.duplicateQuestion(questionIndex),
              ),
              if (controller.questions.length > 1)
                IconButton(
                  tooltip: 'حذف السؤال',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: () => _confirmDeleteQuestion(questionIndex),
                ),
            ],
          ),
        ),
        // نص السؤال: يُحذف كلياً عند فراغه (يظهر للتحرير عند تحديد السؤال).
        if (data.body != null || directlySelected) ...<Widget>[
          if (blockSpacing > 0) SizedBox(height: blockSpacing),
          _paperField(
            fieldKey: bodyKey,
            controller: _field(
              bodyKey,
              question.body,
              (value) => controller.updateQuestionBody(questionIndex, value),
            ),
            style: textStyle,
            textAlign: _textAlignFor(
              bodyKey,
              fallback: PaperStyles.toTextAlign(
                question.bodyAlign ?? question.style.align,
              ),
            ),
            hint: layout.isLtr
                ? 'Question text (optional)...'
                : 'نص السؤال (اختياري) — يُحذف من الورقة إن تُرك فارغاً',
          ),
        ],
        // نقاط السؤال المباشرة (١-، ٢-، ٣-...) بأنواعها المختلطة وتسلسلها المتصل.
        for (var index = 0; index < data.points.length; index++) ...<Widget>[
          if ((index == 0 ? blockSpacing : itemSpacing) > 0)
            SizedBox(height: index == 0 ? blockSpacing : itemSpacing),
          _pointRow(
            controller,
            owner,
            data.points[index],
            textStyle,
            PaperStyles.toTextAlign(question.style.align),
          ),
        ],
        if (directlySelected) _addPointButton(controller, owner),
        // السؤال الجديد يبدأ بلا فروع؛ تُنشأ فقط بطلب صريح (زر +).
        if (question.branches.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 44, top: 2, bottom: 2),
            child: Text(
              layout.isLtr
                  ? 'No branches yet — tap + to add one.'
                  : 'لا فروع بعد — انقر + لإضافة فرع.',
              style: PaperStyles.hint(textStyle),
            ),
          ),
        for (final branch in data.branches) ...<Widget>[
          if (blockSpacing > 0) SizedBox(height: blockSpacing),
          _buildBranchBlock(controller, layout, branch),
        ],
        if (question.dividerAfter != null)
          _buildDividerWidget(
            key: 'q:${question.id}',
            divider: question.dividerAfter!,
            onDelete: () => controller.setQuestionDivider(questionIndex, null),
            onThicken: () => controller.setQuestionDivider(
              questionIndex,
              question.dividerAfter!.copyWith(
                thickness: question.dividerAfter!.thickness >= 3 ? 1.2 : 3,
              ),
            ),
            onCycleWidth: () => controller.setQuestionDivider(
              questionIndex,
              question.dividerAfter!.copyWith(
                widthFraction: _nextDividerWidth(question.dividerAfter!.widthFraction),
              ),
            ),
          ),
      ],
    );

    // Keep the render/widget ancestry stable when focus selects a question.
    // Inserting wrappers here used to dispose PaperField's FocusNode while
    // a tap was opening rich text or the keyboard was entering text.
    block = Container(
      padding: EdgeInsets.all(question.showFrame ? 4 : 0),
      decoration: BoxDecoration(
        border: Border.all(
          color: question.showFrame ? PaperStyles.ink : Colors.transparent,
          width: question.showFrame ? 1 : 0,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: block,
    );
    block = Container(
      padding: EdgeInsets.all(selected ? 1 : 0),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? PaperStyles.primary.withOpacity(0.45) : Colors.transparent,
          width: selected ? 1 : 0,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: block,
    );

    // حافظ على حجز المساحة للمرفقات القديمة فقط. العناصر المسجّلة على
    // مستوى المستند لا تغيّر ارتفاع السؤال عند سحبها.
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final minHeight = _legacyAttachmentMinHeight(question.attachments, globalIds);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, minWidth: double.infinity),
      child: block,
    );
  }

  /// درجة سطر العنوان «(٢٠ درجة)»: نقرة تفتح إدخال الرقم الخام فقط. وحين
  /// لا درجة تظهر أداة «+ درجة» (أداة تحرير لا تُطبع) إن كانت الدرجات مفعّلة.
  Widget _marksTarget({
    required String? marks,
    required bool showPlaceholder,
    required TextStyle style,
    required VoidCallback onEdit,
  }) {
    if (marks != null) {
      return Tooltip(
        message: 'انقر لتعديل الدرجة',
        child: GestureDetector(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text(marks, style: style),
          ),
        ),
      );
    }
    if (!showPlaceholder) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'إضافة درجة',
      child: GestureDetector(
        onTap: onEdit,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('+ درجة', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ),
      ),
    );
  }

  /// زر «إضافة نقطة» (أداة تحرير تظهر عند تحديد صاحب النقاط فقط).
  Widget _addPointButton(ExamWizardController controller, PointsOwner owner) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 36),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Tooltip(
          message: 'إضافة نقطة',
          child: TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: () => controller.addPoint(owner),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('إضافة نقطة', style: TextStyle(fontSize: 11)),
          ),
        ),
      ),
    );
  }

  double _legacyAttachmentMinHeight(
    Iterable<FloatingElement> attachments,
    Set<String> globalIds,
  ) {
    var minHeight = 0.0;
    for (final element in attachments) {
      if (globalIds.contains(element.id)) {
        continue;
      }
      final bottom = element.dy + element.height;
      if (bottom > minHeight) {
        minHeight = bottom;
      }
    }
    return minHeight;
  }

  Future<void> _confirmDeleteQuestion(int index) async {
    final controller = _controller!;
    final label = controller.document.displayQuestionLabel(controller.questions[index]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السؤال'),
        content: Text('هل تريد حذف $label بجميع فروعه ومرفقاته؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.removeQuestion(index);
      setState(_clearSelection);
    }
  }

  Widget _buildBranchBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchBlueprint data,
  ) {
    final branch = data.model;
    final ref = BranchRef(
      questionIndex: data.questionIndex,
      branchIndex: data.branchIndex,
    );
    final selected = _isBranchSelected(ref);

    // مقبض السحب وحده يبدأ السحب (حتى لا يتعارض مع تحديد النص في الحقول)؛
    // الهدف هو كتلة الفرع كاملة.
    final dragHandle = _locked
        ? Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade300)
        : LongPressDraggable<BranchRef>(
            data: ref,
            feedback: Material(
              elevation: 4,
              color: Colors.white,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(8),
                // معاينة السحب تُعرض نصاً مقروءاً: لا كود LaTeX حتى في
                // العنصر العائم أثناء السحب.
                child: Text(
                  '${data.title.number} ${_readableStatement(branch.content.statement)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _scaled(PaperStyles.body(layout)),
                ),
              ),
            ),
            childWhenDragging:
                Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade300),
            // لا Tooltip هنا: مُعرِّف الضغط المطوّل الخاص به يتنافس مع بدء السحب.
            child: Semantics(
              label: 'اضغط مطولاً واسحب لنقل الفرع أو تبديل محتواه مع فرع آخر',
              child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade600),
            ),
          );

    return DragTarget<BranchRef>(
      key: ValueKey<String>('branch-target-${branch.id}'),
      onWillAcceptWithDetails: (details) => !_locked && details.data != ref,
      onAcceptWithDetails: (details) {
        final from = details.data;
        if (from.questionIndex == ref.questionIndex) {
          // داخل السؤال نفسه: نقل وإعادة ترميز (المحتوى كما هو).
          controller.moveBranch(ref.questionIndex, from.branchIndex, ref.branchIndex);
        } else {
          // بين سؤالين: تبديل المحتوى والدرجة فقط (العناوين ثابتة).
          controller.swapBranchContent(from, ref);
        }
      },
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        Widget body = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _tapBranch(ref),
          child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding:
                const EdgeInsetsDirectional.only(start: 4, end: 4, top: 2, bottom: 2),
            decoration: BoxDecoration(
              color: highlighted ? const Color(0x1A2563EB) : null,
              border: Border.all(
                color: highlighted
                    ? PaperStyles.accent
                    : selected
                        ? PaperStyles.primary.withOpacity(0.45)
                        : Colors.transparent,
                width: highlighted ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _buildBranchBody(
              controller,
              layout,
              ref,
              data,
              dragHandle,
              isSelected: selected,
            ),
          ),
        );
        body = Container(
          margin: EdgeInsets.only(top: branch.showFrame ? 2 : 0),
          padding: EdgeInsets.all(branch.showFrame ? 3 : 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: branch.showFrame ? PaperStyles.ink : Colors.transparent,
              width: branch.showFrame ? 0.8 : 0,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: body,
        );
        return body;
      },
    );
  }

  /// الفرع بنفس بنية السؤال: الرقم ← المنطوق ← الدرجة (سطر واحد) ← النص (يُحذف
  /// كلياً عند فراغه) ← النقاط المرقّمة بأنواعها المختلطة.
  Widget _buildBranchBody(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    BranchBlueprint data,
    Widget dragHandle, {
    required bool isSelected,
  }) {
    final document = controller.document;
    final branch = data.model;
    final content = branch.content;
    final bodyStyle = PaperStyles.resolve(
      PaperStyles.body(layout),
      branch.style,
      defaultFont: document.settings.defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final paragraphSpacing = branch.style.paragraphSpacing;
    final firstItemSpacing = paragraphSpacing ?? 1;
    final itemSpacing = paragraphSpacing ?? 0;
    final statementKey = _branchStatementKey(branch.id);
    final bodyKey = _branchBodyKey(branch.id);
    final owner = PointsOwner.branch(ref);
    final branchAlign = PaperStyles.toTextAlign(branch.style.align);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _titleRow(
          dragHandle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: dragHandle,
          ),
          label: Tooltip(
            message: 'انقر لتعديل رقم الفرع',
            child: GestureDetector(
              onTap: () => _editBranchLabel(ref),
              child: Text(
                data.title.number,
                style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          statement: _paperField(
            fieldKey: statementKey,
            controller: _field(
              statementKey,
              content.statement,
              (value) => controller.updateBranchStatement(ref, value),
            ),
            style: bodyStyle,
            textAlign: _textAlignFor(statementKey, fallback: branchAlign),
            hint: layout.isLtr ? 'Branch statement...' : 'اكتب منطوق الفرع هنا...',
            mushafStyle: true,
          ),
          marks: _marksTarget(
            marks: data.title.marks,
            showPlaceholder: document.settings.showQuestionMarks,
            style: bodyStyle,
            onEdit: () => _editBranchMarks(ref),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'نسخ الفرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 14),
              onPressed: () => controller.duplicateBranch(ref),
            ),
            IconButton(
              tooltip: 'إدراج/تحرير معادلة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.functions, size: 14),
              onPressed: () => _editEquationInField(statementKey),
            ),
            // لا حد أدنى للفروع: يُحذف الأخير أيضاً ويبقى السؤال فارغاً.
            IconButton(
              tooltip: 'حذف الفرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 14),
              onPressed: () => controller.removeBranch(ref),
            ),
          ],
        ),
        // نص الفرع: يُحذف كلياً عند فراغه (يظهر للتحرير عند تحديد الفرع).
        if (data.body != null || isSelected)
          Padding(
            padding: EdgeInsetsDirectional.only(start: 26, top: firstItemSpacing),
            child: _paperField(
              fieldKey: bodyKey,
              controller: _field(
                bodyKey,
                content.body,
                (value) => controller.updateBranchBody(ref, value),
              ),
              style: bodyStyle,
              textAlign: _textAlignFor(bodyKey, fallback: branchAlign),
              hint: layout.isLtr
                  ? 'Branch text (optional)...'
                  : 'نص الفرع (اختياري) — يُحذف من الورقة إن تُرك فارغاً',
            ),
          ),
        for (var index = 0; index < data.points.length; index++) ...<Widget>[
          if ((index == 0 ? firstItemSpacing : itemSpacing) > 0)
            SizedBox(height: index == 0 ? firstItemSpacing : itemSpacing),
          _pointRow(controller, owner, data.points[index], bodyStyle, branchAlign),
        ],
        if (isSelected) _addPointButton(controller, owner),
        if (branch.dividerAfter != null)
          _buildDividerWidget(
            key: 'b:${branch.id}',
            divider: branch.dividerAfter!,
            onDelete: () => controller.setBranchDivider(ref, null),
            onThicken: () => controller.setBranchDivider(
              ref,
              branch.dividerAfter!.copyWith(
                thickness: branch.dividerAfter!.thickness >= 3 ? 1.2 : 3,
              ),
            ),
            onCycleWidth: () => controller.setBranchDivider(
              ref,
              branch.dividerAfter!.copyWith(
                widthFraction: _nextDividerWidth(branch.dividerAfter!.widthFraction),
              ),
            ),
          ),
      ],
    );

    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final legacyAttachments = branch.attachments
        .where((element) => !globalIds.contains(element.id))
        .toList(growable: false);
    if (legacyAttachments.isEmpty) {
      return column;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: _legacyAttachmentMinHeight(legacyAttachments, globalIds),
        minWidth: double.infinity,
      ),
      child: column,
    );
  }

  /// سطر نقطة واحدة (داخل سؤال أو فرع بالمسار نفسه): الرقم المتصل ← النص ←
  /// ما يُلحقه نوعها (قوسا «صح/خطأ» أو فراغ «إكمال الفراغ») ← الدرجة، وتحتها
  /// خيارات «اختيار من متعدد». أدوات النوع والحذف تظهر عند تفعيل النقطة فقط.
  Widget _pointRow(
    ExamWizardController controller,
    PointsOwner owner,
    PointBlueprint point,
    TextStyle bodyStyle,
    TextAlign ownerAlign,
  ) {
    final item = point.item;
    final fieldKey = _itemKey(item.id);
    final showActions = _activeItemFieldKey == fieldKey;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Tooltip(
                message: 'انقر لتعديل ترقيم النقطة',
                child: GestureDetector(
                  onTap: () => _editPointLabel(owner, item.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, left: 6),
                    child: point.label.isEmpty
                        ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                        : Text(
                            point.label,
                            style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: _paperField(
                  fieldKey: fieldKey,
                  controller: _field(
                    fieldKey,
                    item.text,
                    (value) => controller.updatePointText(owner, item.id, value),
                  ),
                  style: bodyStyle,
                  textAlign: _textAlignFor(fieldKey, fallback: ownerAlign),
                  hint: item.kind.textHint,
                ),
              ),
              if (point.trailer != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text(point.trailer!, style: bodyStyle),
                ),
              _marksTarget(
                marks: point.marks,
                showPlaceholder: controller.document.settings.showQuestionMarks,
                style: bodyStyle,
                onEdit: () => _editPointMarks(owner, item.id),
              ),
              if (showActions) ...<Widget>[
                PopupMenuButton<PointKind>(
                  tooltip: 'نوع النقطة',
                  onSelected: (kind) => controller.updatePointKind(owner, item.id, kind),
                  itemBuilder: (context) => <PopupMenuEntry<PointKind>>[
                    for (final kind in PointKind.values)
                      PopupMenuItem<PointKind>(
                        value: kind,
                        child: Text(kind.arabicLabel),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.swap_horiz, size: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف النقطة',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => controller.removePoint(owner, item.id),
                ),
              ],
            ],
          ),
          if (item.kind == PointKind.multipleChoice)
            _buildPointOptions(controller, owner, item, bodyStyle, ownerAlign),
        ],
      ),
    );
  }

  /// عرض حقل الخيار الواحد على اللوحة (بكسل منطقي) — قريب من توزيع
  /// الخيارات في الورقة المطبوعة مع إبقائها قابلة للتحرير في مكانها.
  static const double _optionFieldWidth = 190;

  /// خيارات نقطة «اختيار من متعدد»: كل خيار حقل كتابة مباشر بعرض ثابت، تحت
  /// نص النقطة، والخيارات الفارغة تبقى ظاهرة ليُكتب فيها (الطباعة تستثني
  /// الفارغ). زر «+ خيار» يظهر عند تفعيل النقطة أو أحد خياراتها.
  Widget _buildPointOptions(
    ExamWizardController controller,
    PointsOwner owner,
    BranchItem item,
    TextStyle bodyStyle,
    TextAlign ownerAlign,
  ) {
    final document = controller.document;
    final active = _activeItemFieldKey == _itemKey(item.id) ||
        (_activeFieldKey?.startsWith('option-${item.id}-') ?? false);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 20, top: 2),
      child: Wrap(
        spacing: 14,
        runSpacing: 2,
        children: <Widget>[
          for (var index = 0; index < item.options.length; index++)
            SizedBox(
              width: _optionFieldWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Tooltip(
                    message: 'انقر لتعديل تسمية الخيار',
                    child: GestureDetector(
                      onTap: () => _editOptionLabel(owner, item.id, index),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: document.displayOptionLabel(item.options[index], index).isEmpty
                            ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                            : Text(
                                document.displayOptionLabel(item.options[index], index),
                                style: bodyStyle,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _paperField(
                      fieldKey: _optionKey(item.id, index),
                      controller: _field(
                        _optionKey(item.id, index),
                        item.options[index].text,
                        (value) => controller.updatePointOptionText(
                          owner,
                          item.id,
                          index,
                          value,
                        ),
                      ),
                      style: bodyStyle,
                      textAlign: _textAlignFor(
                        _optionKey(item.id, index),
                        fallback: ownerAlign,
                      ),
                      hint: 'اكتب الخيار هنا...',
                    ),
                  ),
                  // لا حد أدنى للخيارات: يُحذف الأخير أيضاً.
                  InkWell(
                    onTap: () => controller.removePointOption(owner, item.id, index),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          if (active)
            InkWell(
              onTap: () => controller.addPointOption(owner, item.id),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add, size: 14, color: PaperStyles.accent),
                    Text(
                      'خيار',
                      style: TextStyle(fontSize: 11, color: PaperStyles.accent),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// عرض الفاصل التالي في دورة (كامل ← ثلثان ← ثلث ← كامل).
  static double _nextDividerWidth(double current) {
    if ((current - 1.0).abs() < 0.01) {
      return 0.66;
    }
    if ((current - 0.66).abs() < 0.05) {
      return 0.33;
    }
    return 1.0;
  }

  static String _dividerWidthLabel(double widthFraction) {
    if ((widthFraction - 1.0).abs() < 0.01) {
      return 'كامل';
    }
    if ((widthFraction - 0.66).abs() < 0.05) {
      return 'ثلثان';
    }
    if ((widthFraction - 0.33).abs() < 0.05) {
      return 'ثلث';
    }
    return 'العرض';
  }

  Widget _buildDividerWidget({
    required String key,
    required PaperDivider divider,
    required VoidCallback onDelete,
    required VoidCallback onThicken,
    required VoidCallback onCycleWidth,
  }) {
    final selected = _selectedDividerKey == key;
    return GestureDetector(
      key: ValueKey<String>('divider-$key'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _clearSelection();
        _selectedDividerKey = key;
      }),
      child: Container(
        padding: EdgeInsets.only(top: divider.spacingBefore, bottom: divider.spacingAfter),
        color: selected ? const Color(0x1A2563EB) : null,
        child: Column(
          children: <Widget>[
            Center(
              child: FractionallySizedBox(
                widthFactor: divider.widthFraction,
                child: Container(height: divider.thickness, color: PaperStyles.primary),
              ),
            ),
            if (selected)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: onThicken,
                    icon: const Icon(Icons.line_weight, size: 14),
                    label: const Text('السماكة', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton.icon(
                    onPressed: onCycleWidth,
                    icon: const Icon(Icons.swap_horiz, size: 14),
                    label: Text(
                      _dividerWidthLabel(divider.widthFraction),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      onDelete();
                      setState(() => _selectedDividerKey = null);
                    },
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('حذف', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// صندوق محتوى المرفق (حد التحديد + العرض) — يُبنى طازجًا كل استدعاء
  /// لاستخدامه في مواضع السحب المختلفة (child/feedback/childWhenDragging).
  Widget _buildAttachmentContent(
    ExamWizardController controller,
    FloatingElement element,
    bool selected,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: selected ? Border.all(color: PaperStyles.accent, width: 1.4) : null,
      ),
      child: FloatingElementView(
        element: element,
        defaultFont: controller.document.settings.defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      ),
    );
  }

  /// غلاف السحب لعنصر عائم (صورة/شكل/مربع نص).
  ///
  /// السحب **مباشر دائمًا** بلا تحديد مسبق ولا ضغط مطوّل: العنصر يُمسك من أي
  /// نقطة داخل مستطيله ويتبع الإصبع فورًا. سابقًا كان التحريك يتطلب ضغطًا
  /// مطوّلًا (أو تحديدًا مسبقًا) وهو ما جعل مربعات النص تبدو «ثابتة لا
  /// تتحرك». الورقة المقفلة ([_locked]) وحدها تمنع التحريك، وفيها يُعاد
  /// المحتوى وحده بلا ساحة إيماءات فتَمُرّ النقرات إلى [GestureDetector]
  /// الأب.
  ///
  /// المقابل المقصود: الإمساك المباشر يحجب تمرير الصفحة فوق مستطيل العنصر
  /// نفسه (ثمن مقبول لأن التحريك المباشر هو المطلوب)، وما عدا ذلك من الورقة
  /// يعمل كما كان.
  ///
  /// ملاحظة تقنية: `GestureDetector.onPanUpdate` لا يصلح هنا لأن حدّ
  /// الانزلاق المطلوب للفوز بساحة الإيماءات ضعف حدّ التمرير (`kPanSlop`
  /// = 2×`kTouchSlop`) فيسبق تمريرُ الصفحة العنصرَ إلى الفوز؛ لذلك يُعلن
  /// [EagerGestureRecognizer] الفوز فورًا وتُحسب الإزاحة من الفرق المطلق
  /// بين إحداثيات المؤشر العامة (بكسل الشاشة) مقسومةً على التكبير.
  Widget _buildAttachmentDraggable(
    ExamWizardController controller,
    _AttachmentRef ref,
    FloatingElement element,
    bool selected,
  ) {
    if (_locked) {
      return _buildAttachmentContent(controller, element, selected);
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (EagerGestureRecognizer instance) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) =>
            _beginAttachmentDrag(ref, element, event.pointer, event.position),
        onPointerMove: (event) =>
            _updateAttachmentDrag(event.pointer, event.position),
        onPointerUp: (event) {
          if (event.pointer == _dragPointer && !_dragMoved) {
            // لمسة بلا حركة = نقرة: تحدّد العنصر ثم تُسجَّل لكشف النقر
            // المزدوج (فتح محرّر مربع النص) لأن الفوز الفوري بساحة
            // الإيماءات يمنع وصول النقرة إلى [GestureDetector] الأب.
            _selectAttachment(ref);
            _noteAttachmentTap(ref, element, _lastPointerDownTime);
          }
          _endAttachmentDrag(event.pointer);
        },
        onPointerCancel: (event) => _endAttachmentDrag(event.pointer),
        child: _buildAttachmentContent(controller, element, selected),
      ),
    );
  }

  /// يبدأ سحباً فورياً للعنصر عند لمس المؤشر [pointer] ويحفظ نقطة الإمساك.
  void _beginAttachmentDrag(
    _AttachmentRef ref,
    FloatingElement element,
    int pointer,
    Offset position,
  ) {
    final controller = _controller;
    final fallbackPage = element.pageIndex;
    final ownerPage = controller != null && element.ownerQuestionId != null
        ? _elementGeometry(controller, element).pageIndex
        : controller != null &&
                !ref.isGlobal &&
                ref.questionIndex >= 0 &&
                ref.questionIndex < controller.questions.length
            ? controller.pagination.pageIndexOf(
                  controller.questions[ref.questionIndex].id,
                ) ??
                fallbackPage
            : fallbackPage;
    final pageCount = controller?.pagination.pageCount ?? 1;
    final pageIndex = ownerPage.clamp(0, math.max(0, pageCount - 1)).toInt();
    if (controller == null) {
      return;
    }
    final local = _localPositionOnPage(pageIndex, position);
    final geometry = _elementGeometry(controller, element);
    final physicalLeft = _layoutIsLtr
        ? geometry.dx
        : ExamCanvasGeometry.width - geometry.dx - element.width;

    _dragPointer = pointer;
    _dragRef = ref;
    _dragStartScreen = position;
    _dragLastScreen = position;
    _dragLastPaper = Offset(geometry.dx, geometry.dy);
    _dragPageIndex = pageIndex;
    _dragAnchorWithinElement = local == null
        ? Offset(element.width / 2, element.height / 2)
        : Offset(local.dx - physicalLeft, local.dy - geometry.dy);
    _dragMoved = false;
  }

  /// يتابع المؤشر [pointer] ويحوّل موضعه إلى صفحة A4 الحالية؛ وبذلك يمكن
  /// نقل العنصر إلى صفحة أخرى من دون إسناده إلى سؤال جديد.
  void _updateAttachmentDrag(int pointer, Offset position) {
    final start = _dragStartScreen;
    final lastScreen = _dragLastScreen;
    final lastPaper = _dragLastPaper;
    final anchor = _dragAnchorWithinElement;
    final ref = _dragRef;
    final controller = _controller;
    if (ref == null ||
        start == null ||
        lastScreen == null ||
        lastPaper == null ||
        anchor == null ||
        controller == null ||
        pointer != _dragPointer) {
      return;
    }
    // لا حركة قبل تجاوز حدّ الانزلاق: تبقى اللمسة العادية نقرة ولا يقفز العنصر.
    if (!_dragMoved && (position - start).distance <= kTouchSlop) {
      return;
    }
    _dragMoved = true;
    final element = _findAttachment(controller.document, ref);
    if (element == null) return;

    final hitPage = _pageAtGlobalPosition(position);
    final int pageIndex;
    final Offset target;
    if (hitPage != null) {
      pageIndex = hitPage.pageIndex;
      final physicalLeft = hitPage.local.dx - anchor.dx;
      target = Offset(
        _layoutIsLtr
            ? physicalLeft
            : ExamCanvasGeometry.width - physicalLeft - element.width,
        hitPage.local.dy - anchor.dy,
      );
    } else {
      // في الفراغ بين صفحتين أو خارج حافة الشاشة: استمر من آخر إحداثي
      // على الصفحة الحالية، ثم أعد الالتقاط عند دخول صفحة أخرى.
      pageIndex = _dragPageIndex ?? element.pageIndex;
      final step = (position - lastScreen) / _zoom;
      target = lastPaper + Offset(
        _layoutIsLtr ? step.dx : -step.dx,
        step.dy,
      );
    }
    _moveAttachmentTo(ref, target, pageIndex: pageIndex);
    final moved = _findAttachment(controller.document, ref);
    if (moved != null) {
      final geometry = _elementGeometry(controller, moved);
      _dragPageIndex = geometry.pageIndex;
      _dragLastPaper = Offset(geometry.dx, geometry.dy);
    }
    _dragLastScreen = position;
  }

  /// يُنهي السحب الفوري (رفع الإصبع أو إلغاء المؤشر).
  void _endAttachmentDrag(int pointer) {
    if (pointer != _dragPointer) {
      return;
    }
    _dragPointer = null;
    _dragRef = null;
    _dragStartScreen = null;
    _dragLastScreen = null;
    _dragLastPaper = null;
    _dragAnchorWithinElement = null;
    _dragPageIndex = null;
    _dragMoved = false;
  }

  /// يسجّل نقرة على مربع نص ويكشف النقر المزدوج (فتح محرّره).
  ///
  /// تُستدعى من مساري التحديد والسحب الفوري معًا، والمقارنة على ساعة أحداث
  /// المؤشر نفسها ([timeStamp] من الغلاف الخارجي) لا على ساعة النظام.
  void _noteAttachmentTap(
    _AttachmentRef ref,
    FloatingElement element,
    Duration? timeStamp,
  ) {
    // مربع النص يفتح محرّر نصه، والمعادلة تفتح محرّر المعادلات المرئي.
    if ((!element.isTextBox && !element.isFormula) || _locked || timeStamp == null) {
      _lastAttachmentTapId = null;
      _lastAttachmentTapTime = null;
      return;
    }
    final previous = _lastAttachmentTapTime;
    final isDoubleTap = _lastAttachmentTapId == ref.elementId &&
        previous != null &&
        (timeStamp - previous).abs() <= kDoubleTapTimeout;
    _lastAttachmentTapId = ref.elementId;
    _lastAttachmentTapTime = isDoubleTap ? null : timeStamp;
    if (isDoubleTap) {
      if (element.isFormula) {
        _editFormulaElement(ref);
      } else {
        _editTextBox(ref);
      }
    }
  }

  /// هل الورقة لاتينية الاتجاه؟ (`false` = عربية، فـ `dx` من اليمين).
  bool get _layoutIsLtr => _controller?.document.layout.isLtr ?? false;

  /// يحوّل موقعاً فيزيائياً داخل **الورقة** (من أعلى-يسارها) إلى إحداثيات
  /// [FloatingElement]: `dy` من أعلى الورقة، و`dx` من حافة القراءة (اليمين
  /// في الأوراق العربية)، والنقطة تصبح **مركز** العنصر.
  Offset _boardPositionFromLocal(
    Offset local, {
    required double width,
    required double height,
  }) {
    final dy = local.dy - height / 2;
    if (_layoutIsLtr) {
      return Offset(local.dx - width / 2, dy);
    }
    // عكس النقطة: مسافتها من الحافة اليمنى بدل اليسرى.
    final fromRight = ExamCanvasGeometry.width - local.dx;
    return Offset(fromRight + width / 2, dy);
  }

  /// يحدّد العنصر [ref] ويُظهر مقابضه (الحذف/التحرير).
  ///
  /// يُستدعى من مسار السحب المباشر عند انتهاء لمسة بلا حركة، لأن
  /// [EagerGestureRecognizer] يفوز بساحة الإيماءات فلا تصل النقرة إلى
  /// [GestureDetector] الأب؛ ويُستدعى كذلك من ذلك الأب في حال قفل الورقة
  /// (لا ساحة إيماءات حينها).
  void _selectAttachment(_AttachmentRef ref) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (ref.isGlobal) {
      controller.selectBranch(null);
    } else {
      controller.selectBranch(
        ref.branchIndex == null
            ? null
            : BranchRef(
                questionIndex: ref.questionIndex,
                branchIndex: ref.branchIndex!,
              ),
      );
      controller.selectQuestion(ref.questionIndex);
    }
    setState(() {
      _clearSelection();
      _selectedAttachment = ref;
    });
  }

  /// يضع العنصر [ref] في الموضع المطلوب على صفحة A4، مستقلاً عن الأسئلة.
  /// يسمح بدخول الهوامش وخروج جزء من العنصر خارج الحافة، مع إبقاء 24 بكسلاً
  /// منه داخل الصفحة كي يستطيع المستخدم إمساكه مجدداً.
  void _moveAttachmentTo(
    _AttachmentRef ref,
    Offset target, {
    required int pageIndex,
  }) {
    final controller = _controller;
    if (controller == null) return;
    final element = _findAttachment(controller.document, ref);
    if (element == null) return;
    const anchor = 24.0;
    final maxDx = ExamCanvasGeometry.width - anchor;
    final maxDy = ExamCanvasGeometry.height - anchor;
    final absolute = element.copyWith(
      pageIndex: pageIndex,
      dx: target.dx.clamp(anchor - element.width, maxDx).toDouble(),
      dy: target.dy.clamp(anchor - element.height, maxDy).toDouble(),
    );
    final owner = element.ownerQuestionId;
    if (owner == null) {
      _updateAttachmentElement(ref, absolute, preservePageIndex: true);
      return;
    }
    // عنصر مرتبط بسؤال: يُحوَّل الموضع المطلق إلى إحداثيات نسبةً للسؤال،
    // والمراقب (المتحكم) يحصره داخل حدوده — فلا يخرج منه بالسحب أبداً.
    final rect = controller.questionRect(owner);
    if (rect == null) {
      _updateAttachmentElement(ref, absolute, preservePageIndex: true);
      return;
    }
    final margin = ExamCanvasGeometry.marginFor(controller.document.settings.marginMm);
    _updateAttachmentElement(
      ref,
      element.copyWith(
        pageIndex: rect.pageIndex,
        dx: math.max(0, absolute.dx - margin),
        dy: math.max(0, absolute.dy - rect.top),
      ),
      preservePageIndex: true,
    );
  }

  Widget _elementHandle({
    required Key key,
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
    ValueChanged<DragUpdateDetails>? onPanUpdate,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanUpdate: onPanUpdate,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: CircleAvatar(
              radius: 10,
              backgroundColor: color,
              child: Icon(icon, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _scaleAttachment(
    _AttachmentRef ref,
    FloatingElement element,
    double factor,
  ) {
    final width = (element.width * factor).clamp(24.0, 600.0).toDouble();
    final height = element.isImage
        ? width * (element.height / element.width)
        : (element.height * factor).clamp(24.0, 600.0).toDouble();
    _updateAttachmentElement(ref, element.copyWith(width: width, height: height));
  }

  void _resizeAttachmentByDrag(
    _AttachmentRef ref,
    FloatingElement element,
    DragUpdateDetails details,
  ) {
    final current = _findAttachment(_controller!.document, ref) ?? element;
    final horizontalDelta = _layoutIsLtr ? details.delta.dx : -details.delta.dx;
    final width = (current.width + horizontalDelta / _zoom)
        .clamp(24.0, 600.0)
        .toDouble();
    final height = current.isImage
        ? width * (current.height / current.width)
        : (current.height + details.delta.dy / _zoom)
            .clamp(24.0, 600.0)
            .toDouble();
    _updateAttachmentElement(ref, current.copyWith(width: width, height: height));
  }

  Widget _buildAttachment(
    ExamWizardController controller,
    _AttachmentRef ref,
    FloatingElement element,
  ) {
    final selected = _selectedAttachment?.elementId == ref.elementId;
    // العنصر المرتبط بسؤال يُرسم نسبةً إلى سؤال المالك: إن سافر السؤال بين
    // الصفحات سافر معه العنصر، وإن تغيّر ارتفاع السؤال بقي داخله.
    final geometry = _elementGeometry(controller, element);
    return PositionedDirectional(
      start: geometry.dx,
      top: geometry.dy,
      width: element.width,
      height: element.height,
      // غلاف قياس وقت اللمس فقط (لا يستهلك الإيماءة): يحتاجه كشف النقر
      // المزدوج على مربع النص في المسارين (التحديد والسحب الفوري).
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (event) => _lastPointerDownTime = event.timeStamp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _selectAttachment(ref);
            _noteAttachmentTap(ref, element, _lastPointerDownTime);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                // صندوق إمساك شفاف: يضمن بدء السحب من أي نقطة داخل
                // المستطيل (بعض الأشكال لا تختبر الإصابة بذاتها)، ويقع في
                // مسار السحب المباشر الذي يحدّد العنصر عند النقر (لأن اللمس
                // يفوز بساحة الإيماءات فلا يصل إلى [GestureDetector]).
                child: _buildAttachmentDraggable(
                  controller,
                  ref,
                  element,
                  selected,
                ),
              ),
              if (selected && !_locked)
                Positioned(
                  left: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('delete-element-${element.id}'),
                    icon: Icons.close,
                    tooltip: 'حذف العنصر',
                    color: PaperStyles.danger,
                    onTap: () => _removeAttachmentElement(ref),
                  ),
                ),
              // ربط/فصل العنصر بالسؤال: المرتبط يبقى داخل سؤال المالك ويسافر
              // معه، والمفصول يبقى حراً في أي نقطة من الورقة.
              if (selected && !_locked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('owner-element-${element.id}'),
                    icon: element.isQuestionOwned
                        ? Icons.link_off
                        : Icons.link,
                    tooltip: element.isQuestionOwned
                        ? 'فصل العنصر عن السؤال'
                        : 'ربط العنصر بالسؤال المحدد',
                    color: PaperStyles.primary,
                    onTap: () => _toggleElementOwner(ref, element),
                  ),
                ),
              if (selected && !_locked && element.isFormula)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('edit-element-${element.id}'),
                    icon: Icons.functions,
                    tooltip: 'تحرير المعادلة',
                    color: PaperStyles.accent,
                    onTap: () => _editFormulaElement(ref),
                  ),
                ),
              if (selected && !_locked && element.isTextBox)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('edit-element-${element.id}'),
                    icon: Icons.edit,
                    tooltip: 'تحرير مربع النص',
                    color: PaperStyles.accent,
                    onTap: () => _editTextBox(ref),
                  ),
                ),
              if (selected && !_locked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('resize-element-${element.id}'),
                    icon: Icons.south_east,
                    tooltip: 'اسحب لتغيير الحجم',
                    color: PaperStyles.accent,
                    onTap: () => _scaleAttachment(ref, element, 1.1),
                    onPanUpdate: (details) =>
                        _resizeAttachmentByDrag(ref, element, details),
                  ),
                ),
              // مقبض التدوير يأتي **بعد** مقبض تغيير الحجم في الـStack:
              // الإيماءات تُختبر من آخر ابن إلى أوله، فمع العناصر الصغيرة
              // (60×60) يتقاطع صندوقا المقبضين (40×40 لكل منهما) ويبتلع
              // مقبضُ الحجم نقرةَ التدوير إن كان هو الأخير — فلا يدور العنصر
              // أبداً. جعله الأخير يضمن وصول النقرة إلى التدوير، ويبقى مقبض
              // الحجم فعالاً في وسطه (خارج تقاطع الصندوقين).
              if (selected &&
                  !_locked &&
                  !element.isTextBox &&
                  !element.isImage)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('rotate-element-${element.id}'),
                    icon: Icons.rotate_right,
                    tooltip: 'تدوير العنصر 45°',
                    color: PaperStyles.accent,
                    onTap: () => _updateAttachmentElement(
                      ref,
                      element.copyWith(
                        rotationDegrees: (element.rotationDegrees + 45) % 360,
                      ),
                    ),
                  ),
                ),

            ],
          ),
        ),
      ),
    );
  }

  /// شريط أدوات مصغّر فوق العنصر المحدد: تكبير/تصغير ومحاذاة دقيقة وأدواته.
  /// جميع الأزرار لها مساحة لمس كافية للأجهزة اللوحية والهواتف.
  Widget _buildAttachmentToolbar(_AttachmentRef ref, FloatingElement element) {
    const toolbarWidth = 460.0;
    const toolbarHeight = 40.0;
    final controller = _controller!;
    final pageCount = controller.pagination.pageCount;
    final elementPage = ref.isGlobal
        ? element.pageIndex
        : controller.pagination.pageIndexOf(
              controller.questions[ref.questionIndex].id,
            ) ??
            element.pageIndex;
    final pageIndex = elementPage.clamp(0, math.max(0, pageCount - 1)).toInt();
    // العنصر المرتبط بسؤال يتبع سؤاله: تُعرض أدوات الشريط عند موضعه الحقيقي
    // على الصفحة، ولا يُتاح «نقل إلى صفحة أخرى» (السؤال هو الذي ينتقل).
    final geometry = _elementGeometry(controller, element);
    final below = geometry.dy < 52;
    return PositionedDirectional(
      start: geometry.dx
          .clamp(0.0, ExamCanvasGeometry.width - toolbarWidth)
          .toDouble(),
      top: (below ? geometry.dy + element.height + 8 : geometry.dy - toolbarHeight)
          .clamp(0.0, ExamCanvasGeometry.height - toolbarHeight)
          .toDouble(),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (element.isImage)
              _attachTool(
                Icons.image_outlined,
                'استبدال الصورة',
                () => _replaceImage(ref, element),
              ),
            _attachTool(
              Icons.zoom_out,
              'تصغير العنصر',
              () => _scaleAttachment(ref, element, 0.9),
            ),
            _attachTool(
              Icons.zoom_in,
              'تكبير العنصر',
              () => _scaleAttachment(ref, element, 1.1),
            ),
            if (!element.isImage && !element.isTextBox) ...<Widget>[
              _attachTool(
                Icons.remove,
                'تقليل سماكة الحد',
                () => _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    strokeWidth:
                        (element.strokeWidth - 0.5).clamp(0.5, 12.0).toDouble(),
                  ),
                ),
              ),
              _attachTool(
                Icons.add,
                'زيادة سماكة الحد',
                () => _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    strokeWidth:
                        (element.strokeWidth + 0.5).clamp(0.5, 12.0).toDouble(),
                  ),
                ),
              ),
            ],
            _attachTool(
              Icons.format_align_right,
              'محاذاة لليمين',
              () => _alignAttachment(ref, element, 'right'),
            ),
            _attachTool(
              Icons.format_align_center,
              'توسيط العنصر',
              () => _alignAttachment(ref, element, 'center'),
            ),
            _attachTool(
              Icons.format_align_left,
              'محاذاة لليسار',
              () => _alignAttachment(ref, element, 'left'),
            ),
            _attachTool(
              Icons.vertical_align_top,
              'محاذاة للأعلى',
              () => _alignAttachmentVertically(ref, element, 'top'),
            ),
            _attachTool(
              Icons.vertical_align_center,
              'توسيط عمودياً',
              () => _alignAttachmentVertically(ref, element, 'center'),
            ),
            _attachTool(
              Icons.vertical_align_bottom,
              'محاذاة للأسفل',
              () => _alignAttachmentVertically(ref, element, 'bottom'),
            ),
            if (!element.isQuestionOwned && pageIndex > 0)
              _attachTool(
                Icons.keyboard_arrow_up,
                'نقل إلى الصفحة السابقة',
                () => _moveAttachmentToPage(ref, element, pageIndex - 1),
              ),
            if (!element.isQuestionOwned && pageIndex < pageCount - 1)
              _attachTool(
                Icons.keyboard_arrow_down,
                'نقل إلى الصفحة التالية',
                () => _moveAttachmentToPage(ref, element, pageIndex + 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachTool(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 36,
          height: 40,
          child: Icon(icon, size: 18, color: PaperStyles.accent),
        ),
      ),
    );
  }

  void _moveAttachmentToPage(
    _AttachmentRef ref,
    FloatingElement element,
    int pageIndex,
  ) {
    final controller = _controller!;
    final geometry = _elementGeometry(controller, element);
    _moveAttachmentTo(ref, Offset(geometry.dx, geometry.dy), pageIndex: pageIndex);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final targetContext = _pageCanvasKeys[pageIndex]?.currentContext;
      if (mounted && targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.08,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          ),
        );
      }
    });
  }

  /// يستبدل صورة العنصر [ref] بصورة جديدة (الموضع والمقاس كما هما).
  Future<void> _replaceImage(_AttachmentRef ref, FloatingElement element) async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage('تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.', isError: true),
    );
    if (!mounted) return;
    if (bytes == null) {
      return;
    }
    _updateAttachmentElement(
      ref,
      element.copyWith(bytes: Uint8List.fromList(bytes)),
    );
    _showMessage('تم استبدال الصورة.');
  }

  /// يحاذي العنصر أفقياً ([edge]: يمين/وسط/يسار) داخل هوامش الطباعة.
  /// الإحداثي يأخذ اتجاه الورقة بالحسبان لأن RTL يقيس `dx` من اليمين.
  void _alignAttachment(_AttachmentRef ref, FloatingElement element, String edge) {
    final margin = ExamCanvasGeometry.marginFor(
      _controller!.document.settings.marginMm,
    );
    final maxPhysicalLeft = ExamCanvasGeometry.width - margin - element.width;
    final isLtr = _controller!.document.layout.isLtr;
    final double dx;
    if (edge == 'center') {
      dx = (ExamCanvasGeometry.width - element.width) / 2;
    } else if (edge == 'right') {
      dx = isLtr ? maxPhysicalLeft : margin;
    } else {
      dx = isLtr ? margin : maxPhysicalLeft;
    }
    _updateAttachmentElement(ref, element.copyWith(dx: dx));
  }

  /// يحاذي العنصر رأسياً داخل صفحة A4 مع احترام الهامش.
  void _alignAttachmentVertically(
    _AttachmentRef ref,
    FloatingElement element,
    String edge,
  ) {
    final margin = ExamCanvasGeometry.marginFor(
      _controller!.document.settings.marginMm,
    );
    final dy = switch (edge) {
      'top' => margin,
      'center' => (ExamCanvasGeometry.height - element.height) / 2,
      _ => ExamCanvasGeometry.height - margin - element.height,
    };
    _updateAttachmentElement(ref, element.copyWith(dy: dy));
  }

  /// عرض منسّق لنص الفرع: الآيات القرآنية بالخط القرآني (Amiri) دائماً.
  ///
  /// وأما «أسلوب المصحف» — توسيط الآية القائمة بذاتها وتكبيرها — فيتبع
  /// تفضيل القالب ([SubjectLayoutTemplate.prefersQuranicFont]، أي قالب
  /// التربية الإسلامية)؛ وهو **نفس قرار محرك الـ PDF** حرفياً فلا تنحرف
  /// الشاشة عن الطباعة.
  Widget _buildRichPreview(
    SubjectLayoutTemplate layout,
    String text,
    TextStyle bodyStyle, {
    TextAlign textAlign = TextAlign.start,
  }) {
    final mushafVerse =
        layout.prefersQuranicFont && QuranText.isStandaloneVerse(text);
    return TexText(
      text,
      style: bodyStyle,
      mathTextStyle: bodyStyle,
      quranStyle: mushafVerse
          ? _scaled(PaperStyles.verse(layout))
          : PaperStyles.quranic(bodyStyle),
      textAlign: mushafVerse ? TextAlign.center : textAlign,
    );
  }

  /// حقل النص على الورقة: **الشكل النهائي فقط** — معادلات مرسومة وآيات
  /// بخطها، لا رموز LaTeX خام (`$...$`) على الورقة إطلاقاً.
  ///
  /// النص العادي يُحرَّر مباشرة في مكانه؛ وما إن يحتوي على صيغة/آية حتى
  /// يُعرض منسّقاً (نفس محرك الطباعة حرفياً) والنقر يفتح التحرير: محرر
  /// المعادلات المرئي للصيغ الخالصة، وإلا تحرير المصدر في مكانه.
  void _insertText(String text) {
    if (!_inserter.hasTarget) {
      _showMessage('انقر داخل حقل نصي على الورقة أولاً.');
      return;
    }
    _inserter.insert(text);
  }

  void _activateField(String key, TextEditingController field) {
    _inserter.controller = field;
    final controller = _controller!;
    final document = controller.document;
    // هل المفتاح لنقطة من [points] (نصها أو أحد خياراتها)؟
    bool belongsToPoints(List<BranchItem> points) => points.any(
          (point) => key == _itemKey(point.id) || key.startsWith('option-${point.id}-'),
        );
    setState(() {
      if (!_multiSelect) {
        _clearSelection();
      } else {
        _activeItemFieldKey = null;
      }
      _activeFieldKey = key;
      for (var q = 0; q < document.questions.length; q++) {
        final question = document.questions[q];
        final isQuestionPoint = belongsToPoints(question.items);
        if (key == _statementKey(question.id) ||
            key == _bodyKey(question.id) ||
            key == _categoryKey(question.id) ||
            isQuestionPoint) {
          _activeItemFieldKey =
              isQuestionPoint && key.startsWith('item-') ? key : null;
          _selectedQuestions.add(question.id);
          controller.selectBranch(null);
          controller.selectQuestion(q);
          return;
        }
        for (var b = 0; b < question.branches.length; b++) {
          final branch = question.branches[b];
          final isBranchPoint = belongsToPoints(branch.content.items);
          if (key == _branchStatementKey(branch.id) ||
              key == _branchBodyKey(branch.id) ||
              isBranchPoint) {
            _activeItemFieldKey =
                isBranchPoint && key.startsWith('item-') ? key : null;
            final ref = BranchRef(questionIndex: q, branchIndex: b);
            _selectedBranches.add(ref);
            controller.selectBranch(ref);
            return;
          }
        }
      }
    });
  }

  Widget _paperField({
    required String fieldKey,
    required TextEditingController controller,
    required TextStyle style,
    TextAlign textAlign = TextAlign.start,
    String? hint,
    bool mushafStyle = false,
  }) {
    final layout = _controller!.document.layout;
    return PaperField(
      key: ValueKey<String>(fieldKey),
      controller: controller,
      style: style,
      textAlign: textAlign,
      hint: hint,
      onActivate: () => _activateField(fieldKey, controller),
      onEditFormula: () => _editEquationInField(fieldKey),
      // نص الفرع وحده يتبع «أسلوب المصحف» (توسيط الآية القائمة بذاتها)
      // كما في محرك الـ PDF — وبقية الحقول تُعرض بمحاذاة الحقل نفسها.
      renderBuilder: (text) => mushafStyle
          ? _buildRichPreview(layout, text, style, textAlign: textAlign)
          : TexText(text, style: style, mathTextStyle: style, textAlign: textAlign),
    );
  }
}

/// نص العبارة مقروءاً للسحب والمعاينات الخفيفة: يُقسَّم النص بمقاطع
/// [TexContent.split] وتُعرض كل صيغة من نموذج المعادلات نفسه
/// ([EquationModel.readableText]) — فلا يظهر كود LaTeX على الشاشة أبداً.
String _readableStatement(String statement) {
  final buffer = StringBuffer();
  for (final segment in TexContent.split(statement)) {
    if (segment.isMath) {
      buffer.write(EquationModel.readableText(segment.text));
    } else {
      buffer.write(segment.text);
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
