import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../layout/pagination_engine.dart';
import '../../layout/paper_metrics.dart';
import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/exam_canvas_geometry.dart';
import '../../models/exam_document.dart';
import '../../models/exam_header_model.dart';
import '../../models/floating_element.dart';
import '../../models/paper_divider.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/question_model.dart';
import '../../models/question_type.dart';
import '../../models/quran_text.dart';
import '../../models/subject_layout.dart';
import '../../models/tex_content.dart';
import '../../providers/exam_document_provider.dart';
import '../../providers/exam_wizard_controller.dart';
import '../../services/docx_document_export_service.dart';
import '../../services/export_file_service.dart';
import '../../services/math_image_renderer.dart';
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
import 'measure_size.dart';
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

  /// عرض «نموذج الإجابة» على الورقة: تُظهر الإجابات الصحيحة والنموذجية
  /// وتحرَّر في مكانها (نفس سلوك ملف الـ PDF في وضع المعلم).
  bool _showTeacherAnswers = false;

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

  static String _branchTextKey(String branchId) => 'branch-$branchId';
  static String _branchMarksKey(String branchId) => 'marks-$branchId';
  static String _optionKey(String branchId, int index) => 'option-$branchId-$index';
  static String _modelAnswerKey(String branchId) => 'answer-$branchId';
  static String _categoryKey(String questionId) => 'category-$questionId';
  static String _promptKey(String questionId) => 'prompt-$questionId';
  static String _itemKey(String itemId) => 'item-$itemId';
  static String _headerKey(HeaderSlot slot, int line) => 'header-${slot.name}-$line';
  static const String _instructionsKey = 'instructions';
  static const String _headerTitleKey = 'header-title';
  static const String _headerNotesKey = 'header-notes';

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
      for (final question in document.questions) {
        for (final item in question.items) {
          final field = _fields[_itemKey(item.id)];
          if (field != null && field.text != item.text) field.text = item.text;
        }
        final categoryField = _fields[_categoryKey(question.id)];
        if (categoryField != null && categoryField.text != question.category) {
          categoryField.text = question.category;
        }
        final promptField = _fields[_promptKey(question.id)];
        if (promptField != null && promptField.text != question.prompt) {
          promptField.text = question.prompt;
        }
        for (final branch in question.branches) {
          final textField = _fields[_branchTextKey(branch.id)];
          if (textField != null && textField.text != branch.content.text) {
            textField.text = branch.content.text;
          }
          final marksField = _fields[_branchMarksKey(branch.id)];
          if (marksField != null && _parseMarks(marksField.text) != branch.marks) {
            marksField.text = _formatMarksInput(branch.marks);
          }
          final answerField = _fields[_modelAnswerKey(branch.id)];
          if (answerField != null && answerField.text != branch.content.modelAnswer) {
            answerField.text = branch.content.modelAnswer;
          }
          for (var index = 0; index < branch.content.options.length; index++) {
            final optionField = _fields[_optionKey(branch.id, index)];
            if (optionField != null && optionField.text != branch.content.options[index].text) {
              optionField.text = branch.content.options[index].text;
            }
          }
          for (final item in branch.content.items) {
            final itemField = _fields[_itemKey(item.id)];
            if (itemField != null && itemField.text != item.text) {
              itemField.text = item.text;
            }
          }
        }
      }
      for (final slot in HeaderSlot.values) {
        final lines = document.header.column(slot).lines;
        for (var index = 0; index < lines.length; index++) {
          final field = _fields[_headerKey(slot, index)];
          if (field != null && field.text != lines[index]) {
            field.text = lines[index];
          }
        }
      }
      final titleField = _fields[_headerTitleKey];
      if (titleField != null && titleField.text != document.header.title) {
        titleField.text = document.header.title;
      }
      final notesField = _fields[_headerNotesKey];
      if (notesField != null && notesField.text != document.header.notes) {
        notesField.text = document.header.notes;
      }
      final instructions = _fields[_instructionsKey];
      if (instructions != null && instructions.text != document.header.instructions) {
        instructions.text = document.header.instructions;
      }
      _disposeStaleFields(document);
    } finally {
      _syncingFields = false;
    }
  }

  /// يتخلّص من تحكمات الحقول التي حُذف أصحابها (سؤال أو فرع) فلا تتراكم
  /// تحكمات بلا مالك. الحذف يتم **بعد اكتمال الإطار** كي لا يُحرَّر تحكم
  /// ما زال مربوطاً بحقل في الشجرة الحالية.
  void _disposeStaleFields(ExamDocument document) {
    final live = <String>{
      _instructionsKey,
      _headerTitleKey,
      _headerNotesKey,
      for (final slot in HeaderSlot.values)
        for (var line = 0; line < HeaderColumn.lineCount; line++) _headerKey(slot, line),
      for (final question in document.questions) ...<String>{
        _categoryKey(question.id),
        _promptKey(question.id),
        for (final item in question.items) _itemKey(item.id),
        for (final branch in question.branches) ...<String>{
          _branchTextKey(branch.id),
          _branchMarksKey(branch.id),
          _modelAnswerKey(branch.id),
          for (var index = 0; index < branch.content.options.length; index++)
            _optionKey(branch.id, index),
          for (final item in branch.content.items) _itemKey(item.id),
        },
      },
    };
    final stale = _fields.keys.where((key) => !live.contains(key)).toList(growable: false);
    if (stale.isEmpty) {
      return;
    }
    // يُزال القيد فوراً (فلا يُعاد استخدام تحكم فرع محذوف)، ويُحرَّر التحكم
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

  void _applyStyle(PaperTextStyle Function(PaperTextStyle current) update) {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    for (final ref in targets.branches) {
      controller.updateBranchStyle(ref, update(document.branchAt(ref).style));
      applied = true;
    }
    for (final index in targets.questions) {
      controller.updateQuestionStyle(index, update(document.questions[index].style));
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
  FloatingElement _withDefaultPosition(FloatingElement element) {
    final controller = _controller;
    if (controller == null) {
      return element;
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
    final added = _controller!.addFloatingElement(element, pageIndex: pageIndex);
    if (!added) {
      _showMessage('تعذر إدراج المعادلة. حاول اختيار موضع آخر على الورقة.');
      return;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(element.id);
    });
    _showMessage('أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.');
  }

  /// يضيف عنصراً حراً إلى صفحة السؤال النشط افتراضياً، من دون منحه مالكاً.
  void _addAttachmentToSelection(FloatingElement element) {
    element = _withDefaultPosition(element);
    final controller = _controller!;
    final added = controller.addFloatingElement(element, pageIndex: element.pageIndex);
    if (added) {
      setState(() => _selectedAttachment = _AttachmentRef.global(element.id));
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

  /// تثبيت تسمية يدوية للسؤال («أولاً»، «س1»...) — فارغ = تلقائي.
  Future<void> _editQuestionLabel(int questionIndex) async {
    final controller = _controller!;
    final document = controller.document;
    final question = document.questions[questionIndex];
    final saved = await _showTextInputDialog(
      title: 'تسمية السؤال',
      initialText: question.numberOverride ?? '',
      hintText: 'تلقائي: ${document.autoQuestionLabel(question)}',
      helperText: 'اتركه فارغاً للعودة للترقيم التلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateQuestionNumberOverride(questionIndex, saved);
  }

  /// تثبيت تسمية يدوية للفرع («أولاً»، «أ»...) — فارغ = تلقائي من الفهرس.
  Future<void> _editBranchLabel(BranchRef ref) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final branch = document.branchAt(ref);
    final saved = await _showTextInputDialog(
      title: 'تسمية الفرع',
      initialText: branch.labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoBranchLabel(ref.branchIndex)}',
      helperText: 'مثال: أولاً، ثانياً — فارغ = تلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateBranchLabelOverride(ref, saved);
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

  Future<void> _exportPdf({required bool isTeacherVersion}) async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    setState(() => _isBusy = true);
    try {
      final bytes = await PdfExportService.buildDocumentPdfBytes(
        document: controller.document,
        isTeacherVersion: isTeacherVersion,
        // نفس التوزيع المعروض على الشاشة تماماً.
        pageAssignments: controller.isFullyMeasured ? controller.pageAssignments : null,
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
            title: isTeacherVersion ? 'معاينة نموذج الإجابة' : 'معاينة ورقة الأسئلة',
            fileName: '${controller.document.name}'
                '${isTeacherVersion ? '_نموذج_الإجابة' : '_ورقة_الامتحان'}.pdf',
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

  Future<void> _exportWord({required bool isTeacherVersion}) async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    setState(() => _isBusy = true);
    try {
      final document = controller.document;
      final pageAssignments = controller.isFullyMeasured
          ? controller.pageAssignments
          : await PdfExportService.resolvePageAssignments(
              document: document,
              isTeacherVersion: isTeacherVersion,
            );
      if (!mounted) return;
      final file = await DocxDocumentExportService.exportDocumentToDocx(
        document: document,
        isTeacherVersion: isTeacherVersion,
        shapeRasterizer: ShapeImageRenderer.asRasterizer,
        // تستعمل الصفحات المقاسة على اللوحة، أو محرك PDF عند غيابها.
        pageAssignments: pageAssignments,
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
    final saved = await _showTextInputDialog(
      title: 'لون نص مخصص',
      initialText: _activeStyle().colorHex ?? '',
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
    _applyStyle((current) => current.copyWith(color: () => argb));
  }

  /// ترقيم النقطة: مخصص حرفي، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editItemLabel(BranchRef ref, int index) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final content = document.branchAt(ref).content;
    if (index < 0 || index >= content.items.length) {
      return;
    }
    final item = content.items[index];
    final saved = await _showTextInputDialog(
      title: 'ترقيم النقطة',
      initialText: item.labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoItemLabel(index)}',
      helperText: 'مثال: أ-، 1) — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updateBranchItemLabel(ref, index, saved);
  }

  /// تسمية الخيار: مخصصة حرفياً، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editOptionLabel(BranchRef ref, int index) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final content = document.branchAt(ref).content;
    if (index < 0 || index >= content.options.length) {
      return;
    }
    final option = content.options[index];
    final saved = await _showTextInputDialog(
      title: 'تسمية الخيار',
      initialText: option.labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoOptionLabel(index)}',
      helperText: 'مثال: ( أ )، A. — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updateBranchOptionLabel(ref, index, saved);
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مراجعة الورقة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _reviewRow('عدد الأسئلة', document.formatNumber(document.questions.length)),
              _reviewRow('عدد الفروع', document.formatNumber(document.totalBranches)),
              _reviewRow(
                'عدد الصفحات',
                document.formatNumber(controller.pagination.pageCount),
              ),
              _reviewRow(
                'الدرجة الكلية',
                '${document.formatNumber(document.totalMarks)} ${document.layout.marksUnit}',
              ),
              _reviewRow('النسخة', _showTeacherAnswers ? 'نموذج الإجابة' : 'ورقة الطالب'),
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
              _exportPdf(isTeacherVersion: _showTeacherAnswers);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('تصدير PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportWord(isTeacherVersion: _showTeacherAnswers);
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
    var settings = controller.document.settings;
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
                  min: 8,
                  max: 25,
                  divisions: 17,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(marginMm: value),
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
                  title: const Text('ترقيم الصفحات', style: TextStyle(fontSize: 13)),
                  value: settings.showPageNumbers,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(showPageNumbers: value),
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                controller.updateSettings(settings);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
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
            icon: Icon(
              _showTeacherAnswers ? Icons.visibility : Icons.visibility_off_outlined,
            ),
            tooltip: _showTeacherAnswers ? 'عرض ورقة الطالب' : 'عرض نموذج الإجابة',
            onPressed: _isBusy
                ? null
                : () => setState(() => _showTeacherAnswers = !_showTeacherAnswers),
          ),
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
            activeAlign: activeStyle.align,
            onAlignChanged: (align) => _applyStyle(
              (current) => current.copyWith(align: () => align),
            ),
            activeLineHeight: activeStyle.lineHeight,
            onLineHeightChanged: (value) {
              // القيمة المميزة NaN تعني «تباعد مخصص» من قائمة الشريط.
              if (value != null && value.isNaN) {
                _showCustomLineHeight();
                return;
              }
              _applyStyle((current) => current.copyWith(lineHeight: () => value));
            },
            activeQuestionSpacing: _activeQuestionSpacing(),
            onQuestionSpacingChanged: (spacing) {
              if (spacing.isNaN) {
                _showCustomQuestionSpacing();
                return;
              }
              _applyQuestionSpacing(spacing);
            },
            activeColor: activeStyle.color,
            onColorChanged: (value) {
              // القيمة المميزة -1 تعني «لون مخصص» (HEX) من قائمة الشريط.
              if (value != null && value == PreviewToolbar.customColorSentinel) {
                _showCustomColor();
                return;
              }
              _applyStyle((current) => current.copyWith(color: () => value));
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
            child: _buildHeaderBlock(controller, layout),
          ),
        );
        previousBlockId = blockId;
        continue;
      }
      final question = controller.document.questionById(blockId);
      if (question == null) {
        continue;
      }
      // بحث بالمعرف لا بالهوية: نسخ المستند تستبدل النسخ لا المعرفات.
      final questionIndex = controller.document.indexOfQuestion(question.id);
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
                child: _buildQuestionBlock(controller, layout, question),
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
    int resolvedPageIndex(FloatingElement element) => element.pageIndex
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
                      layout,
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

  /// يهيّئ محتوى الصفحة (الكتل + التذييل + الإطار) داخل الهوامش؛ والعناصر
  /// العائمة طبقة مستقلة فوقه بإحداثيات الصفحة.
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
    ExamDocument document,
    SubjectLayoutTemplate layout, {
    required bool highlighted,
  }) {
    final margin =
        ExamCanvasGeometry.marginFor(document.settings.marginMm);
    // صندوق صفحة كامل ⇒ كل العناصر العائمة قابلة للمس أينما وُضعت.
    Widget stack = Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        // `bottom` يُترك مفتوحاً في الصفحة غير المتجاوزة كما كان: المحتوى
        // الأطول من الصفحة (قياس أولي أو كتلة طويلة) يُقصّ على حدود الورقة
        // بلا خطأ تجاوز، ويُصغَّر بتناسق حين تُعلَّم الصفحة متجاوزة.
        Positioned(
          top: margin,
          left: margin,
          right: margin,
          bottom: page.overflows
              ? margin + PaperMetrics.footerHeightPx
              : null,
          child: content,
        ),
        Positioned(
          left: margin,
          right: margin,
          bottom: margin,
          height: PaperMetrics.footerHeightPx,
          child: document.settings.showPageNumbers
              ? Center(
                  child: Text(
                    layout.isLtr
                        ? 'Page ${page.index + 1} of $pageCount'
                        : 'صفحة ${document.formatNumber(page.index + 1)} من '
                            '${document.formatNumber(pageCount)}',
                    style: PaperStyles.footer,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (document.settings.pageBorder)
          Positioned(
            top: margin,
            left: margin,
            right: margin,
            bottom: margin,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: PaperStyles.primary, width: 1.4),
                ),
              ),
            ),
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
    final placed = element.copyWith(dx: dx, dy: dy, pageIndex: pageIndex);
    final added = controller.addFloatingElement(placed, pageIndex: pageIndex);
    if (!added) {
      _showMessage('تعذر إدراج المعادلة في هذه الصفحة.');
      return false;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(placed.id);
    });
    _showMessage('أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.');
    return true;
  }

  // ------------------------------------------------------------------
  // الترويسة — قابلة للتحرير والتحديد والتنسيق
  // ------------------------------------------------------------------

  Widget _buildHeaderBlock(ExamWizardController controller, SubjectLayoutTemplate layout) {
    final document = controller.document;
    final header = document.header;
    final defaultFont = document.settings.defaultFont;
    final lineStyle = PaperStyles.resolve(PaperStyles.headerLine, header.style,
        defaultFont: defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );
    final centerStyle = PaperStyles.resolve(PaperStyles.headerCenter, header.style,
        defaultFont: defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );
    final titleStyle = PaperStyles.resolve(PaperStyles.headerTitle, header.style,
        defaultFont: defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );

    Widget column(HeaderSlot slot, {required bool center}) {
      final lines = header.column(slot).lines;
      return Expanded(
        flex: center ? 4 : 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < lines.length; index++)
              _paperField(
                fieldKey: _headerKey(slot, index),
                controller: _field(
                  _headerKey(slot, index),
                  lines[index],
                  (value) => controller.updateHeaderLine(slot, index, value),
                ),
                style: center ? centerStyle : lineStyle,
                textAlign: center ? TextAlign.center : TextAlign.start,
                hint: 'سطر ${index + 1}',
              ),
          ],
        ),
      );
    }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header.title.trim().isNotEmpty || _headerSelected)
              _paperField(
                fieldKey: _headerTitleKey,
                controller: _field(
                  _headerTitleKey,
                  header.title,
                  controller.updateHeaderTitle,
                ),
                style: titleStyle,
                textAlign: PaperStyles.toTextAlign(header.style.align, TextAlign.center),
                hint: 'عنوان الامتحان...',
              ),
            Container(
              // Preserve focused header fields when optional title/notes
              // appear on selection before/after this group.
              key: const ValueKey<String>('header-columns'),
              decoration: BoxDecoration(
                border: document.settings.headerBorder
                    ? Border.all(color: PaperStyles.primary, width: 1.4)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  column(HeaderSlot.right, center: false),
                  const SizedBox(width: 8),
                  column(HeaderSlot.center, center: true),
                  const SizedBox(width: 8),
                  column(HeaderSlot.left, center: false),
                ],
              ),
            ),
            _paperField(
              fieldKey: _instructionsKey,
              controller:
                  _field(_instructionsKey, header.instructions, controller.updateInstructions),
              style: _scaled(PaperStyles.note),
              textAlign: TextAlign.center,
              hint: 'ملاحظة / تعليمات للطلاب...',
            ),
            if (header.notes.trim().isNotEmpty || _headerSelected)
              _paperField(
                fieldKey: _headerNotesKey,
                controller: _field(_headerNotesKey, header.notes, controller.updateHeaderNotes),
                style: _scaled(PaperStyles.note),
                textAlign: TextAlign.center,
                hint: 'ملاحظات إضافية (وقت/درجة/...)...',
              ),
            const Divider(thickness: 1.5, color: PaperStyles.primary, height: 10),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ) وفروعه
  // ------------------------------------------------------------------

  Widget _buildQuestionBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    QuestionModel question,
  ) {
    final document = controller.document;
    // بحث بالمعرف لا بالهوية: نسخ المستند تستبدل النسخ لا المعرفات.
    final questionIndex = document.indexOfQuestion(question.id);
    final category = question.category.trim();
    final selected = _isQuestionSelected(questionIndex);
    final defaultFont = document.settings.defaultFont;
    final titleStyle = PaperStyles.resolve(PaperStyles.question, question.style,
        defaultFont: defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );
    final promptStyle = PaperStyles.resolve(PaperStyles.prompt, question.style,
        defaultFont: defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );

    final label = document.displayQuestionLabel(question);
    final marksPart = document.settings.showQuestionMarks
        ? ': [${document.formatNumber(question.marks)} ${layout.marksUnit}]'
        : '';

    Widget block = Column(
      key: ValueKey<String>('question-block-${question.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // عنوان القسم الوزاري: نص قابل للتحرير مباشرة على الورقة مثل بقية النصوص.
        if (category.isNotEmpty)
          _paperField(
            fieldKey: _categoryKey(question.id),
            controller: _field(
              _categoryKey(question.id),
              category,
              (value) => controller.updateQuestionCategory(questionIndex, value),
            ),
            style: _scaled(PaperStyles.category),
            textAlign: PaperStyles.toTextAlign(question.style.align),
            hint: 'القسم الوزاري...',
          ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _tapQuestion(questionIndex),
          child: Row(
            children: <Widget>[
              if (!_locked)
                LongPressDraggable<int>(
                  data: questionIndex,
                  feedback: Material(
                    elevation: 4,
                    color: Colors.white,
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '$label$marksPart',
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
                )
              else
                Icon(Icons.drag_indicator, size: 18, color: Colors.grey.shade300),
              Expanded(
                child: Tooltip(
                  message: 'انقر لتعديل تسمية السؤال',
                  child: GestureDetector(
                    onTap: () => _editQuestionLabel(questionIndex),
                    child: Text(
                      '$label$marksPart',
                      style: titleStyle,
                      textAlign: PaperStyles.toTextAlign(question.style.align),
                    ),
                  ),
                ),
              ),
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
              IconButton(
                tooltip: 'تثبيت تسمية السؤال',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.label_outline, size: 16),
                onPressed: () => _editQuestionLabel(questionIndex),
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
        _paperField(
          fieldKey: _promptKey(question.id),
          controller: _field(
            _promptKey(question.id),
            question.prompt,
            (value) => controller.updateQuestionPrompt(questionIndex, value),
          ),
          style: promptStyle,
          textAlign: PaperStyles.toTextAlign(question.style.align),
          hint: layout.isLtr
              ? 'Question text / instructions...'
              : 'نص السؤال / التعليمات (أجب عن فرعين فقط: ...)...',
        ),
        // نقاط السؤال المباشرة (1، 2، 3...) — الترقيم تلقائي على الورقة،
        // والمدرس يكتب محتوى كل سطر (عبارات/فراغات/اختيارات) بنفسه.
        for (var index = 0; index < question.items.length; index++)
          _questionItemRow(controller, layout, question.id, index, promptStyle),
        // السؤال الجديد يبدأ بلا فروع؛ تُنشأ فقط بطلب صريح (زر +).
        if (question.branches.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 44, top: 2, bottom: 2),
            child: Text(
              layout.isLtr
                  ? 'No branches yet — tap + to add one.'
                  : 'لا فروع بعد — انقر + لإضافة فرع.',
              style: PaperStyles.hint(promptStyle),
            ),
          ),
        for (var index = 0; index < question.branches.length; index++)
          _buildBranchBlock(
            controller,
            layout,
            BranchRef(questionIndex: questionIndex, branchIndex: index),
            question.branches[index],
          ),
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
    // a tap was opening rich text or the keyboard was entering an answer.
    block = Container(
      padding: EdgeInsets.all(question.showFrame ? 4 : 0),
      decoration: BoxDecoration(
        border: Border.all(
          color: question.showFrame ? PaperStyles.primary : Colors.transparent,
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
    BranchRef ref,
    BranchModel branch,
  ) {
    final document = controller.document;
    final label = document.displayBranchLabel(ref.questionIndex, ref.branchIndex);
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
                child: Text(
                  '$label) ${branch.content.text}',
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
            child: _buildBranchBody(controller, layout, ref, branch, label, dragHandle),
          ),
        );
        body = Container(
          margin: EdgeInsets.only(top: branch.showFrame ? 2 : 0),
          padding: EdgeInsets.all(branch.showFrame ? 3 : 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: branch.showFrame ? PaperStyles.primary : Colors.transparent,
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

  Widget _buildBranchBody(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    BranchModel branch,
    String label,
    Widget dragHandle,
  ) {
    final document = controller.document;
    final content = branch.content;
    final bodyStyle = PaperStyles.resolve(
      PaperStyles.body(layout),
      branch.style,
      defaultFont: document.settings.defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(top: 2), child: dragHandle),
            SizedBox(
              width: 26,
              child: Tooltip(
                message: 'انقر لتعديل تسمية الفرع',
                child: GestureDetector(
                  onTap: () => _editBranchLabel(ref),
                  child: Text(
                    '$label)',
                    style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _paperField(
                fieldKey: _branchTextKey(branch.id),
                controller: _field(
                  _branchTextKey(branch.id),
                  content.text,
                  (value) => controller.updateBranchText(ref, value),
                ),
                style: bodyStyle,
                textAlign: PaperStyles.toTextAlign(branch.style.align),
                hint: layout.isLtr ? 'Branch text...' : 'نص الفرع...',

                mushafStyle: true,
              ),
            ),
            SizedBox(
              width: 44,
              child: LtrNumericField(
                key: ValueKey<String>(_branchMarksKey(branch.id)),
                controller: _field(
                  _branchMarksKey(branch.id),
                  _formatMarksInput(branch.marks),
                  (value) {
                    final marks = _parseMarks(value);
                    if (marks != null) {
                      controller.updateBranchMarks(ref, marks);
                    }
                  },
                ),
                collapsed: true,
                hintText: '0',
                textAlign: TextAlign.center,
                style: bodyStyle,
              ),
            ),
            Text(layout.marksUnit, style: _scaled(PaperStyles.small)),
            IconButton(
              tooltip: 'نسخ الفرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 14),
              onPressed: () => controller.duplicateBranch(ref),
            ),
            IconButton(
              tooltip: 'تثبيت تسمية الفرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.label_outline, size: 14),
              onPressed: () => _editBranchLabel(ref),
            ),
            IconButton(
              tooltip: 'إدراج/تحرير معادلة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.functions, size: 14),
              onPressed: () => _editEquationInField(_branchTextKey(branch.id)),
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
        for (var index = 0; index < content.items.length; index++)
          _branchItemRow(controller, layout, ref, index, bodyStyle),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 36, top: 1),
          child: Row(
            children: <Widget>[
              Expanded(child: _buildTypeBody(controller, ref, layout, branch)),
              IconButton(
                tooltip: 'إضافة نقطة',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 14),
                onPressed: () => controller.addBranchItem(ref),
              ),
            ],
          ),
        ),
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
      return text;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: _legacyAttachmentMinHeight(legacyAttachments, globalIds),
        minWidth: double.infinity,
      ),
      child: text,
    );
  }

  /// مفتاحا صح/خطأ المصغّران لإجابة النقطة (نموذج المعلم فقط).
  ///
  /// النقر على المحدد يمسح الإجابة (غير محددة).
  Widget _buildItemAnswerToggle(
    ExamWizardController controller,
    BranchRef ref,
    int index,
    BranchItem item,
  ) {
    Widget chip(String text, bool value) {
      final selected = item.isCorrect == value;
      return GestureDetector(
        onTap: () => controller.updateBranchItemAnswer(
          ref,
          index,
          selected ? null : value,
        ),
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? PaperStyles.answer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? PaperStyles.answer : Colors.grey.shade400,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[chip('صح', true), chip('خطأ', false)],
    );
  }

  /// سطر نقطة سؤال مباشرة — يربط المعرّفات الثابتة (سؤال/نقطة) فلا
  /// يختلط التحرير بعد إعادة الترتيب.
  Widget _questionItemRow(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    String questionId,
    int index,
    TextStyle bodyStyle,
  ) {
    final document = controller.document;
    final questionIndex = document.indexOfQuestion(questionId);
    final question = controller.questions[questionIndex];
    final item = question.items[index];
    final itemId = item.id;
    return _buildItemRow(
      layout: layout,
      item: item,
      index: index,
      count: question.items.length,
      bodyStyle: bodyStyle,
      fieldKey: _itemKey(itemId),
      label: document.displayItemLabel(item, index),
      onEditLabel: () => _editQuestionItemLabel(questionId, index),
      onTextChanged: (value) => _updateQuestionItemText(questionId, itemId, value),
      onMoveUp: index == 0
          ? null
          : () => controller.moveQuestionItem(questionIndex, index, index - 1),
      onMoveDown: index == question.items.length - 1
          ? null
          : () => controller.moveQuestionItem(questionIndex, index, index + 1),
      onDelete: () => controller.removeQuestionItem(questionIndex, index),
    );
  }

  /// سطر نقطة فرع — نفس مسار نقاط السؤال مع إجابة صح/خطأ في نموذج المعلم.
  Widget _branchItemRow(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    int index,
    TextStyle bodyStyle,
  ) {
    final document = controller.document;
    final content = document.branchAt(ref).content;
    final item = content.items[index];
    final itemId = item.id;
    return _buildItemRow(
      layout: layout,
      item: item,
      index: index,
      count: content.items.length,
      bodyStyle: bodyStyle,
      fieldKey: _itemKey(itemId),
      label: document.displayItemLabel(item, index),
      onEditLabel: () => _editItemLabel(ref, index),
      onTextChanged: (value) => _updateBranchItemText(ref, itemId, value),
      answerToggle: _showTeacherAnswers && content.type == QuestionType.trueFalse
          ? _buildItemAnswerToggle(controller, ref, index, item)
          : null,
      onMoveUp: index == 0
          ? null
          : () => controller.moveBranchItem(ref, index, index - 1),
      onMoveDown: index == content.items.length - 1
          ? null
          : () => controller.moveBranchItem(ref, index, index + 1),
      onDelete: () => controller.removeBranchItem(ref, index),
    );
  }

  /// سطر نقطة واحد (داخل سؤال أو فرع) — العرض النهائي للنص بلا رموز
  /// خامة، والتسمية والترتيب والحذف في مكانها.
  ///
  /// يُستخدم لنقاط السؤال المباشرة ونقاط الفروع بالمسار نفسه (نفس ما
  /// يُطبع في الـ PDF حرفياً)؛ وإجابة صح/خطأ ([answerToggle]) تظهر في
  /// نموذج المعلم لفروع صح/خطأ وحدها.
  Widget _buildItemRow({
    required SubjectLayoutTemplate layout,
    required BranchItem item,
    required int index,
    required int count,
    required TextStyle bodyStyle,
    required String fieldKey,
    required String label,
    required VoidCallback onEditLabel,
    required ValueChanged<String> onTextChanged,
    required VoidCallback onDelete,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
    Widget? answerToggle,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Tooltip(
            message: 'انقر لتعديل ترقيم النقطة',
            child: GestureDetector(
              onTap: onEditLabel,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, left: 6),
                child: label.isEmpty
                    ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                    : Text(
                        label,
                        style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
          // إجابة النقطة لصح/خطأ — تظهر وتُحرَّر في نموذج المعلم فقط.
          if (answerToggle != null) answerToggle,
          Expanded(
            child: _paperField(
              fieldKey: fieldKey,
              controller: _field(
                fieldKey,
                item.text,
                onTextChanged,
              ),
              style: bodyStyle,
              hint: layout.isLtr ? 'Item...' : 'نص النقطة...',
            ),
          ),
          IconButton(
            tooltip: 'نقل النقطة لأعلى',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_drop_up, size: 18),
            onPressed: onMoveUp,
          ),
          IconButton(
            tooltip: 'نقل النقطة لأسفل',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            onPressed: onMoveDown,
          ),
          IconButton(
            tooltip: 'حذف النقطة',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  /// ترقيم نقطة السؤال المباشرة: مخصص حرفي، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editQuestionItemLabel(String questionId, int index) async {
    final controller = _controller!;
    final questionIndex = controller.document.indexOfQuestion(questionId);
    if (questionIndex < 0) {
      return;
    }
    final question = controller.questions[questionIndex];
    if (index < 0 || index >= question.items.length) {
      return;
    }
    final item = question.items[index];
    final saved = await _showTextInputDialog(
      title: 'ترقيم النقطة',
      initialText: item.labelOverride ?? '',
      hintText: 'تلقائي: ${controller.document.autoItemLabel(index)}',
      helperText: 'مثال: أ-، 1) — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updateQuestionItemLabel(questionIndex, index, saved);
  }

  /// نص نقطة السؤال — يُحلّ موضع النقطة وقت الكتابة بمعرفها الثابت (لا
  /// فهرس مأسور وقت البناء)، فيبقى التعديل صحيحاً بعد النقل/الترتيب.
  void _updateQuestionItemText(String questionId, String itemId, String value) {
    final controller = _controller!;
    final questionIndex = controller.document.indexOfQuestion(questionId);
    if (questionIndex < 0) {
      return;
    }
    final items = controller.questions[questionIndex].items;
    final liveIndex = items.indexWhere((item) => item.id == itemId);
    if (liveIndex < 0) {
      return;
    }
    controller.updateQuestionItemText(questionIndex, liveIndex, value);
  }

  /// نص نقطة الفرع — يُحلّ فهرس النقطة وقت الكتابة (كما في نقاط السؤال).
  void _updateBranchItemText(BranchRef ref, String itemId, String value) {
    final controller = _controller!;
    if (!controller.document.containsRef(ref)) {
      return;
    }
    final items = controller.document.branchAt(ref).content.items;
    final liveIndex = items.indexWhere((item) => item.id == itemId);
    if (liveIndex < 0) {
      return;
    }
    controller.updateBranchItemText(ref, liveIndex, value);
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
    final ownerPage = controller != null &&
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
    final local = _localPositionOnPage(pageIndex, position);
    final physicalLeft = _layoutIsLtr
        ? element.dx
        : ExamCanvasGeometry.width - element.dx - element.width;

    _dragPointer = pointer;
    _dragRef = ref;
    _dragStartScreen = position;
    _dragLastScreen = position;
    _dragLastPaper = Offset(element.dx, element.dy);
    _dragPageIndex = pageIndex;
    _dragAnchorWithinElement = local == null
        ? Offset(element.width / 2, element.height / 2)
        : Offset(local.dx - physicalLeft, local.dy - element.dy);
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
      _dragPageIndex = moved.pageIndex;
      _dragLastPaper = Offset(moved.dx, moved.dy);
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
    _updateAttachmentElement(
      ref,
      element.copyWith(
        pageIndex: pageIndex,
        dx: target.dx.clamp(anchor - element.width, maxDx).toDouble(),
        dy: target.dy.clamp(anchor - element.height, maxDy).toDouble(),
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
    return PositionedDirectional(
      start: element.dx,
      top: element.dy,
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
    final below = element.dy < 52;
    return PositionedDirectional(
      start: element.dx
          .clamp(0.0, ExamCanvasGeometry.width - toolbarWidth)
          .toDouble(),
      top: (below ? element.dy + element.height + 8 : element.dy - toolbarHeight)
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
            if (pageIndex > 0)
              _attachTool(
                Icons.keyboard_arrow_up,
                'نقل إلى الصفحة السابقة',
                () => _moveAttachmentToPage(ref, element, pageIndex - 1),
              ),
            if (pageIndex < pageCount - 1)
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
    _moveAttachmentTo(ref, Offset(element.dx, element.dy), pageIndex: pageIndex);
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

  /// عرض حقل الخيار الواحد على اللوحة (بكسل منطقي) — قريب من توزيع
  /// الخيارات في الورقة المطبوعة مع إبقائها قابلة للتحرير في مكانها.
  static const double _optionFieldWidth = 190;

  /// جسم الفرع حسب نوعه: خيارات / صح-خطأ / فراغ / أسطر مقالية.
  ///
  /// كل نصوصه قابلة للتحرير في مكانها — بما فيها نصوص الخيارات في «اختيار
  /// من متعدد» — وتُعرض الإجابات النموذجية وتُحرَّر عند تشغيل «نموذج الإجابة».
  /// الفرع الحر ([BranchContent.plainText]) يعرض نصه ونقاطه فقط.
  Widget _buildTypeBody(
    ExamWizardController controller,
    BranchRef ref,
    SubjectLayoutTemplate layout,
    BranchModel branch,
  ) {
    final document = controller.document;
    final content = branch.content;
    final answerStyle = _scaled(PaperStyles.answerBody(layout));
    if (content.plainText && !_showTeacherAnswers) {
      return const SizedBox.shrink();
    }
    switch (content.type) {
      case QuestionType.multipleChoice:
        if (_showTeacherAnswers && content.plainText) {
          return const SizedBox.shrink();
        }
        // عرض الخيارات بنفس منطق الورقة المطبوعة (صفوف متعددة الخيارات)،
        // لكن كل خيار حقل كتابة مباشر بعرض ثابت — والخيارات الفارغة تبقى
        // ظاهرة ليُكتب فيها (محرك الطباعة يستثني الفارغ كما في الورقة).
        return Wrap(
          spacing: 14,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: <Widget>[
            for (var index = 0; index < content.options.length; index++)
              SizedBox(
                width: _optionFieldWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Tooltip(
                      message: 'انقر لتعديل تسمية الخيار',
                      child: GestureDetector(
                        onTap: () => _editOptionLabel(ref, index),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: document.displayOptionLabel(content.options[index], index).isEmpty
                              ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                              : Text(
                                  document.displayOptionLabel(content.options[index], index),
                                  style: _scaled(PaperStyles.option),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _paperField(
                            fieldKey: _optionKey(branch.id, index),
                            controller: _field(
                              _optionKey(branch.id, index),
                              content.options[index].text,
                              (value) => controller.updateBranchOptionText(ref, index, value),
                            ),
                            style: _showTeacherAnswers && content.options[index].isCorrect
                                ? answerStyle
                                : _scaled(PaperStyles.option),
                            hint: layout.isLtr ? 'Option...' : 'نص الخيار...',
                          ),
                        ],
                      ),
                    ),
                    if (_showTeacherAnswers && content.options[index].isCorrect)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: 2),
                        child: Text(
                          '•',
                          style: TextStyle(
                            color: PaperStyles.answer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    // لا حد أدنى للخيارات: يُحذف الأخير أيضاً.
                    InkWell(
                      onTap: () => controller.removeBranchOption(ref, index),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            InkWell(
              onTap: () => controller.addBranchOption(ref),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add, size: 14, color: PaperStyles.accent),
                    Text('خيار', style: TextStyle(fontSize: 11, color: PaperStyles.accent)),
                  ],
                ),
              ),
            ),
          ],
        );
      case QuestionType.trueFalse:
        // ورقة الطالب: الأسئلة فقط — الإجابة في دفتر الطالب، بلا مساحة
        // إجابة مولَّدة؛ والإجابة الصحيحة تظهر في نموذج المعلم وحده.
        if (_showTeacherAnswers) {
          final answer = content.trueFalseAnswer;
          return Text(
            layout.isLtr
                ? 'Answer: ${answer ? 'True' : 'False'} •'
                : 'الإجابة الصحيحة: ${answer ? 'صح' : 'خطأ'} •',
            style: answerStyle,
          );
        }
        return const SizedBox.shrink();
      case QuestionType.fillInTheBlank:
        if (_showTeacherAnswers) {
          return _buildModelAnswerField(controller, ref, layout, branch, answerStyle);
        }
        return const SizedBox.shrink();
      case QuestionType.definitions:
      case QuestionType.essay:
        if (_showTeacherAnswers) {
          return _buildModelAnswerField(controller, ref, layout, branch, answerStyle);
        }
        return const SizedBox.shrink();
    }
  }

  /// الإجابة النموذجية على الورقة في وضع «نموذج الإجابة» — نص قابل للتحرير
  /// في مكانه (فراغ/مقالي)، تماماً كما يُطبع في ملف الـ PDF.
  Widget _buildModelAnswerField(
    ExamWizardController controller,
    BranchRef ref,
    SubjectLayoutTemplate layout,
    BranchModel branch,
    TextStyle answerStyle,
  ) {
    final content = branch.content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          content.type == QuestionType.essay
              ? (layout.isLtr ? 'Model answer: ' : 'الإجابة النموذجية وعناصر التقييم: ')
              : (layout.isLtr ? 'Model answer: ' : 'الإجابة النموذجية: '),
          style: answerStyle,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _paperField(
                fieldKey: _modelAnswerKey(branch.id),
                controller: _field(
                  _modelAnswerKey(branch.id),
                  content.modelAnswer,
                  (value) => controller.updateBranchModelAnswer(ref, value),
                ),
                style: answerStyle,
                hint: layout.isLtr ? 'Model answer...' : 'اكتب الإجابة النموذجية...',
              ),
            ],
          ),
        ),
        Text(' •', style: answerStyle),
      ],
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
    setState(() {
      if (!_multiSelect) _clearSelection();
      if (key.startsWith('header-') || key == _instructionsKey) {
        _headerSelected = true;
        controller.selectBranch(null);
        controller.selectQuestion(null);
        return;
      }
      for (var q = 0; q < document.questions.length; q++) {
        final question = document.questions[q];
        if (key == _promptKey(question.id) || key == _categoryKey(question.id) ||
            question.items.any((item) => key == _itemKey(item.id))) {
          _selectedQuestions.add(question.id);
          controller.selectBranch(null);
          controller.selectQuestion(q);
          return;
        }
        for (var b = 0; b < question.branches.length; b++) {
          final branch = question.branches[b];
          if (key == _branchTextKey(branch.id) || key == _modelAnswerKey(branch.id) ||
              branch.content.items.any((item) => key == _itemKey(item.id)) ||
              List.generate(branch.content.options.length, (i) => _optionKey(branch.id, i)).contains(key)) {
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
