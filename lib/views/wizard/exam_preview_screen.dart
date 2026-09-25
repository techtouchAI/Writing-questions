import 'dart:typed_data';

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
import '../../services/pdf_export_service.dart';
import '../../services/shape_image_renderer.dart';
import '../widgets/floating_element_view.dart';
import '../widgets/formula_inserter.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/smart_exam_toolbar.dart';
import '../widgets/tex_text.dart';
import 'measure_size.dart';
import 'paper_styles.dart';
import 'preview_toolbar.dart';

/// مرجع مرفق محدد (سؤال/فرع + هوية العنصر).
class _AttachmentRef {
  const _AttachmentRef({
    required this.questionIndex,
    this.branchIndex,
    required this.elementId,
  });

  final int questionIndex;
  final int? branchIndex;
  final String elementId;

  bool get isQuestionLevel => branchIndex == null;
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
/// - **المرفقات**: صور/أشكال/مربعات نص على مستوى السؤال أو الفرع: تحريك،
///   تغيير حجم (الصور بنسبة ثابتة)، تدوير، إطار، حذف.
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
  ExamWizardController? _controller;
  _AttachmentRef? _selectedAttachment;
  String? _selectedDividerKey;
  bool _isBusy = false;

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

  TextEditingController _field(String key, String initial, ValueChanged<String> onEdit) {
    return _fields.putIfAbsent(key, () {
      final field = TextEditingController(text: initial);
      field.addListener(() => onEdit(field.text));
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
    final document = controller.document;
    for (final question in document.questions) {
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
    _disposeStaleFields(document);
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
    final id = _controller!.questions[index].id;
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
    return '';
  }

  FloatingElement? _findAttachment(ExamDocument document, _AttachmentRef ref) {
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
    return (
      branches: const [],
      questions: [controller.currentQuestionIndex],
      header: false,
      boxes: const []
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// يضيف صورة/شكلاً لمساحة الفرع المحدد (مسار شريط الصيغ — يتطلب فرعاً).
  void _addAttachmentToBranch(FloatingElement element) {
    final added = _controller!.addAttachment(element);
    if (!added) {
      _showMessage('انقر على فرع داخل الورقة أولاً لتحديد موضع الإدراج.');
      return;
    }
    final ref = _controller!.selectedBranch!;
    setState(() => _selectedAttachment = _AttachmentRef(
      questionIndex: ref.questionIndex,
      branchIndex: ref.branchIndex,
      elementId: element.id,
    ));
  }

  /// يضيف عنصراً للتحديد الحالي (فرع، وإلا سؤال، وإلا رفض مع إرشاد).
  void _addAttachmentToSelection(FloatingElement element) {
    final controller = _controller!;
    BranchRef? branchTarget;
    final branches = _selectedBranches.where(controller.document.containsRef).toList();
    if (branches.length == 1) {
      branchTarget = branches.single;
    } else {
      branchTarget = controller.selectedBranch;
    }
    if (branchTarget != null) {
      if (controller.addAttachment(element, ref: branchTarget)) {
        setState(() => _selectedAttachment = _AttachmentRef(
          questionIndex: branchTarget!.questionIndex,
          branchIndex: branchTarget.branchIndex,
          elementId: element.id,
        ));
        return;
      }
    }
    var questionTarget = controller.selectedQuestionIndex;
    if (questionTarget == null && _selectedQuestions.length == 1) {
      questionTarget = controller.document.indexOfQuestion(_selectedQuestions.single);
      if (questionTarget == -1) {
        questionTarget = null;
      }
    }
    if (questionTarget != null) {
      if (controller.addQuestionAttachment(element, questionIndex: questionTarget)) {
        setState(() => _selectedAttachment = _AttachmentRef(
          questionIndex: questionTarget!,
          elementId: element.id,
        ));
        return;
      }
    }
    _showMessage('انقر على سؤال أو فرع داخل الورقة أولاً لتحديد موضع الإدراج.');
  }

  void _addImage(List<int> bytes) {
    _addAttachmentToBranch(
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
    final bytes = await pickImageBytes();
    if (bytes != null) {
      _addImageToSelection(bytes);
    }
  }

  void _addShape(FloatingShapeType shape) {
    _addAttachmentToBranch(
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
    _addAttachmentToSelection(
      FloatingElement(
        type: FloatingElementType.shape,
        shape: FloatingShapeType.textBox,
        dx: 0,
        dy: 0,
        width: 180,
        height: 90,
      ),
    );
    // فتح محرر النص فوراً لكتابة محتوى المربع الجديد.
    final ref = _selectedAttachment;
    if (ref != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _editTextBox(ref);
        }
      });
    }
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
    questionTarget ??= document.questions.length - 1;
    controller.setQuestionDivider(questionTarget, const PaperDivider());
    _showMessage('تمت إضافة فاصل بعد السؤال.');
  }

  void _updateAttachmentElement(_AttachmentRef ref, FloatingElement element) {
    final controller = _controller!;
    if (ref.branchIndex == null) {
      controller.updateQuestionAttachment(ref.questionIndex, element);
    } else {
      controller.updateAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        element,
      );
    }
  }

  void _removeAttachmentElement(_AttachmentRef ref) {
    final controller = _controller!;
    if (ref.branchIndex == null) {
      controller.removeQuestionAttachment(ref.questionIndex, ref.elementId);
    } else {
      controller.removeAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        ref.elementId,
      );
    }
    setState(() => _selectedAttachment = null);
  }

  Future<void> _editTextBox(_AttachmentRef ref) async {
    final document = _controller!.document;
    final element = _findAttachment(document, ref);
    if (element == null) {
      return;
    }
    final field = TextEditingController(text: element.label);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مربع نص'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب النص هنا... (ملاحظة، تمنيات...)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    field.dispose();
    if (saved == null) {
      return;
    }
    _updateAttachmentElement(ref, element.copyWith(label: saved));
  }

  void _addBranchToSelected() {
    final controller = _controller!;
    final target = controller.selectedBranch?.questionIndex ?? controller.questions.length - 1;
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
      final file = await DocxDocumentExportService.exportDocumentToDocx(
        document: controller.document,
        isTeacherVersion: isTeacherVersion,
        shapeRasterizer: ShapeImageRenderer.asRasterizer,
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
              _reviewRow('حجم الورق', 'A4'),
              _reviewRow('الخط الافتراضي', document.settings.defaultFont.arabicLabel),
              _reviewRow(
                'الهوامش',
                '${document.settings.marginMm.toStringAsFixed(0)} مم',
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
              _exportPdf(isTeacherVersion: false);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('تصدير PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportWord(isTeacherVersion: false);
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
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
                SwitchListTile(
                  dense: true,
                  title: const Text('إظهار الدرجة الكلية', style: TextStyle(fontSize: 13)),
                  value: settings.showTotalMarks,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(showTotalMarks: value),
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

  void _centerPaper() {
    _fitToScreen();
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
            onFontSizeChanged: (size) => _applyStyle(
              (current) => current.copyWith(fontSize: () => size),
            ),
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
              onInsertText: _inserter.insert,
              onAddImage: _addImage,
              onAddShape: _addShape,
              onAddQuestion: controller.addQuestion,
              onAddBranch: _addBranchToSelected,
              onAddTextBox: () => _addAttachmentToBranch(
                FloatingElement(
                  type: FloatingElementType.shape,
                  shape: FloatingShapeType.textBox,
                  dx: 0,
                  dy: 0,
                  width: 180,
                  height: 90,
                ),
              ),
              onAddDivider: () {
                final ref = controller.selectedBranch;
                if (ref == null) {
                  _showMessage('انقر على فرع داخل الورقة أولاً لتحديد موضع الفاصل.');
                  return;
                }
                controller.setBranchDivider(ref, const PaperDivider());
              },
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
                  controller: _vScroll,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SingleChildScrollView(
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
    for (final blockId in page.blockIds) {
      if (blocks.isNotEmpty) {
        blocks.add(const SizedBox(height: PaperMetrics.blockSpacingPx));
      }
      if (blockId == PaperMetrics.headerBlockId) {
        blocks.add(
          MeasureSize(
            key: const ValueKey<String>('measure-header'),
            onChange: (size) => controller.reportBlockHeight(blockId, size.height),
            child: _buildHeaderBlock(controller, layout),
          ),
        );
        continue;
      }
      final question = controller.document.questionById(blockId);
      if (question == null) {
        continue;
      }
      final questionIndex = controller.questions.indexOf(question);
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
        child: SizedBox(width: PaperMetrics.contentWidthPx, child: content),
      );
    }

    return Directionality(
      textDirection: layout.textDirection,
      child: Container(
        key: ValueKey<String>('a4-page-${page.index}'),
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
        child: Padding(
          padding: const EdgeInsets.all(ExamCanvasGeometry.margin),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: page.overflows ? PaperMetrics.footerHeightPx : null,
                child: content,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
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
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: PaperStyles.primary, width: 1.4),
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

  // ------------------------------------------------------------------
  // الترويسة — قابلة للتحرير والتحديد والتنسيق
  // ------------------------------------------------------------------

  Widget _buildHeaderBlock(ExamWizardController controller, SubjectLayoutTemplate layout) {
    final document = controller.document;
    final header = document.header;
    final defaultFont = document.settings.defaultFont;
    final lineStyle = PaperStyles.resolve(PaperStyles.headerLine, header.style,
        defaultFont: defaultFont);
    final centerStyle = PaperStyles.resolve(PaperStyles.headerCenter, header.style,
        defaultFont: defaultFont);
    final titleStyle = PaperStyles.resolve(PaperStyles.headerTitle, header.style,
        defaultFont: defaultFont);

    Widget column(HeaderSlot slot, {required bool center}) {
      final lines = header.column(slot).lines;
      return Expanded(
        flex: center ? 4 : 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < lines.length; index++)
              _paperField(
                key: ValueKey<String>(_headerKey(slot, index)),
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
                key: const ValueKey<String>(_headerTitleKey),
                controller: _field(
                  _headerTitleKey,
                  header.title,
                  controller.updateHeaderTitle,
                ),
                style: titleStyle,
                textAlign: PaperStyles.toTextAlign(header.style.align, TextAlign.center),
                hint: 'عنوان الامتحان...',
                registerInserter: true,
              ),
            Container(
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
            if (document.settings.showTotalMarks) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                layout.isLtr
                    ? 'Total: ${document.formatNumber(document.totalMarks)} ${layout.marksUnit}  |  '
                        'Questions: ${document.formatNumber(document.questions.length)}'
                    : 'الدرجة الكلية: ${document.formatNumber(document.totalMarks)} '
                        '${layout.marksUnit}  |  عدد الأسئلة: '
                        '${document.formatNumber(document.questions.length)}',
                textAlign: TextAlign.center,
                style: PaperStyles.small,
              ),
            ],
            _paperField(
              key: const ValueKey<String>(_instructionsKey),
              controller:
                  _field(_instructionsKey, header.instructions, controller.updateInstructions),
              style: PaperStyles.note,
              textAlign: TextAlign.center,
              hint: 'ملاحظة / تعليمات للطلاب...',
            ),
            if (header.notes.trim().isNotEmpty || _headerSelected)
              _paperField(
                key: const ValueKey<String>(_headerNotesKey),
                controller: _field(_headerNotesKey, header.notes, controller.updateHeaderNotes),
                style: PaperStyles.note,
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
    final questionIndex = controller.questions.indexOf(question);
    final category = question.category.trim();
    final selected = _isQuestionSelected(questionIndex);
    final defaultFont = document.settings.defaultFont;
    final titleStyle = PaperStyles.resolve(PaperStyles.question, question.style,
        defaultFont: defaultFont);
    final promptStyle = PaperStyles.resolve(PaperStyles.prompt, question.style,
        defaultFont: defaultFont);

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
            key: ValueKey<String>(_categoryKey(question.id)),
            controller: _field(
              _categoryKey(question.id),
              category,
              (value) => controller.updateQuestionCategory(questionIndex, value),
            ),
            style: PaperStyles.category,
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
                        style: PaperStyles.question,
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
                child: InkWell(
                  onTap: () => _tapQuestion(questionIndex),
                  onDoubleTap: !_locked ? () => _editQuestionLabel(questionIndex) : null,
                  child: Text(
                    '$label$marksPart',
                    style: titleStyle,
                    textAlign: PaperStyles.toTextAlign(question.style.align),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تخصيص ترقيم السؤال',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, size: 16),
                onPressed: !_locked ? () => _editQuestionLabel(questionIndex) : null,
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
          key: ValueKey<String>(_promptKey(question.id)),
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
          registerInserter: true,
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
          ),
      ],
    );

    if (question.showFrame) {
      block = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.primary, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: block,
      );
    }
    if (selected) {
      block = Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.primary.withOpacity(0.45)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: block,
      );
    }

    if (question.attachments.isEmpty) {
      return block;
    }
    // مرفقات مستوى السؤال تتراكب فوق مساحته؛ الكتلة تتمدد لتضمّها.
    var minHeight = 0.0;
    for (final element in question.attachments) {
      final bottom = element.dy + element.height;
      if (bottom > minHeight) {
        minHeight = bottom;
      }
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight, minWidth: double.infinity),
          child: block,
        ),
        for (final element in question.attachments)
          _buildAttachment(
            controller,
            _AttachmentRef(questionIndex: questionIndex, elementId: element.id),
            element,
          ),
      ],
    );
  }

  Future<void> _editQuestionLabel(int index) async {
    final controller = _controller!;
    final question = controller.questions[index];
    final textController = TextEditingController(text: question.numberOverride ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تخصيص ترقيم/تسمية السؤال'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'تسمية السؤال (اتركه فارغاً للترقيم التلقائي)',
            hintText: 'مثال: س1/ أو أولاً: أو المسألة 1',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(textController.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (updated != null) {
      final val = updated.trim();
      controller.updateQuestionNumberOverride(index, val.isEmpty ? null : val);
    }
  }

  Future<void> _editBranchLabel(BranchRef ref) async {
    final controller = _controller!;
    final branch = controller.document.branchAt(ref);
    final textController = TextEditingController(text: branch.labelOverride ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تخصيص تسمية الفرع'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'تسمية الفرع (اتركه فارغاً للترميز التلقائي)',
            hintText: 'مثال: أولاً: أو ثانياً: أو 1-',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(textController.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (updated != null) {
      final val = updated.trim();
      controller.updateBranchLabelOverride(ref, val.isEmpty ? null : val);
    }
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
                  style: PaperStyles.body(layout),
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
        if (branch.showFrame) {
          body = Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              border: Border.all(color: PaperStyles.primary, width: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: body,
          );
        }
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
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(top: 2), child: dragHandle),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: InkWell(
                onTap: !_locked ? () => _editBranchLabel(ref) : null,
                borderRadius: BorderRadius.circular(4),
                child: Text('$label)', style: bodyStyle.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: _paperField(
                key: ValueKey<String>(_branchTextKey(branch.id)),
                controller: _field(
                  _branchTextKey(branch.id),
                  content.text,
                  (value) => controller.updateBranchText(ref, value),
                ),
                style: bodyStyle,
                hint: layout.isLtr ? 'Branch text...' : 'نص الفرع...',
                registerInserter: true,
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
            Text(layout.marksUnit, style: PaperStyles.small),
            IconButton(
              tooltip: 'نسخ الفرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 14),
              onPressed: () => controller.duplicateBranch(ref),
            ),
            if (document.questions[ref.questionIndex].branches.length > 1)
              IconButton(
                tooltip: 'حذف الفرع',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 14),
                onPressed: () => controller.removeBranch(ref),
              ),
          ],
        ),
        // عرض منسّق للنص العلمي (LaTeX) وللآيات القرآنية (خط قرآني) تحت
        // الحقل، مع إبقاء الحقل نفسه للكتابة: ما يُرى هو ما يُطبع.
        if (TexContent.containsMath(content.text) || QuranText.containsQuran(content.text))
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 36),
            child: _buildRichPreview(layout, content.text, bodyStyle),
          ),
        for (var index = 0; index < content.items.length; index++)
          _buildItemRow(controller, layout, ref, content.items[index], index, bodyStyle),
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
          ),
      ],
    );

    if (branch.attachments.isEmpty) {
      return text;
    }

    // المرفقات تتراكب فوق مساحة الفرع؛ الكتلة تتمدد لتضمّها حتى لا تُقصّ.
    var minHeight = 0.0;
    for (final element in branch.attachments) {
      final bottom = element.dy + element.height;
      if (bottom > minHeight) {
        minHeight = bottom;
      }
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight, minWidth: double.infinity),
          child: text,
        ),
        for (final element in branch.attachments)
          _buildAttachment(
            controller,
            _AttachmentRef(
              questionIndex: ref.questionIndex,
              branchIndex: ref.branchIndex,
              elementId: element.id,
            ),
            element,
          ),
      ],
    );
  }

  Widget _buildItemRow(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    BranchItem item,
    int index,
    TextStyle bodyStyle,
  ) {
    final document = controller.document;
    final count = controller.document.branchAt(ref).content.items.length;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 30,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${document.formatNumber(index + 1)}-', style: bodyStyle),
            ),
          ),
          Expanded(
            child: _paperField(
              key: ValueKey<String>(_itemKey(item.id)),
              controller: _field(
                _itemKey(item.id),
                item.text,
                (value) => controller.updateBranchItemText(ref, index, value),
              ),
              style: bodyStyle,
              hint: layout.isLtr ? 'Item...' : 'نص النقطة...',
              registerInserter: true,
            ),
          ),
          IconButton(
            tooltip: 'نقل النقطة لأعلى',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_drop_up, size: 18),
            onPressed: index == 0 ? null : () => controller.moveBranchItem(ref, index, index - 1),
          ),
          IconButton(
            tooltip: 'نقل النقطة لأسفل',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            onPressed: index == count - 1
                ? null
                : () => controller.moveBranchItem(ref, index, index + 1),
          ),
          IconButton(
            tooltip: 'حذف النقطة',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            onPressed: () => controller.removeBranchItem(ref, index),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerWidget({
    required String key,
    required PaperDivider divider,
    required VoidCallback onDelete,
    required VoidCallback onThicken,
  }) {
    final selected = _selectedDividerKey == key;
    return GestureDetector(
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

  Widget _buildAttachment(
    ExamWizardController controller,
    _AttachmentRef ref,
    FloatingElement element,
  ) {
    final selected = _selectedAttachment != null &&
        _selectedAttachment!.questionIndex == ref.questionIndex &&
        _selectedAttachment!.branchIndex == ref.branchIndex &&
        _selectedAttachment!.elementId == ref.elementId;
    return PositionedDirectional(
      start: element.dx,
      top: element.dy,
      width: element.width,
      height: element.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.selectBranch(
            ref.branchIndex == null
                ? null
                : BranchRef(
                    questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
          );
          controller.selectQuestion(ref.questionIndex);
          setState(() {
            _clearSelection();
            _selectedAttachment = ref;
          });
        },
        onDoubleTap: element.isTextBox && !_locked ? () => _editTextBox(ref) : null,
        onPanUpdate: _locked
            ? null
            : (details) {
                final maxDx = PaperMetrics.contentWidthPx - element.width;
                _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    dx: (element.dx + details.delta.dx)
                        .clamp(0.0, maxDx < 0 ? 0.0 : maxDx),
                    dy: (element.dy + details.delta.dy)
                        .clamp(0.0, ExamCanvasGeometry.height),
                  ),
                );
              },
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: selected ? Border.all(color: PaperStyles.accent, width: 1.4) : null,
                ),
                child: FloatingElementView(
                  element: element,
                  defaultFont: controller.document.settings.defaultFont,
                ),
              ),
            ),
            if (selected && !_locked)
              Positioned(
                left: -12,
                top: -12,
                child: GestureDetector(
                  onTap: () => _removeAttachmentElement(ref),
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: PaperStyles.danger,
                    child: Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            if (selected && !_locked && element.isTextBox)
              Positioned(
                right: -12,
                top: -12,
                child: GestureDetector(
                  onTap: () => _editTextBox(ref),
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: PaperStyles.accent,
                    child: Icon(Icons.edit, size: 12, color: Colors.white),
                  ),
                ),
              ),
            if (selected && !_locked && !element.isTextBox && !element.isImage)
              Positioned(
                left: -12,
                bottom: -12,
                child: GestureDetector(
                  onTap: () => _updateAttachmentElement(
                    ref,
                    element.copyWith(
                      rotationDegrees: (element.rotationDegrees + 45) % 360,
                    ),
                  ),
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: PaperStyles.accent,
                    child: Icon(Icons.rotate_right, size: 12, color: Colors.white),
                  ),
                ),
              ),
            if (selected && !_locked)
              Positioned(
                right: -6,
                bottom: -6,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    if (element.isImage) {
                      // الصور تحافظ على نسبة أبعادها عند تغيير الحجم.
                      final ratio = element.height / element.width;
                      final width =
                          (element.width + details.delta.dx).clamp(24.0, 600.0);
                      _updateAttachmentElement(
                        ref,
                        element.copyWith(width: width, height: width * ratio),
                      );
                    } else {
                      _updateAttachmentElement(
                        ref,
                        element.copyWith(
                          width: (element.width + details.delta.dx).clamp(24.0, 600.0),
                          height:
                              (element.height + details.delta.dy).clamp(24.0, 600.0),
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.south_east, size: 18, color: PaperStyles.accent),
                ),
              ),
          ],
        ),
      ),
    );
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
    TextStyle bodyStyle,
  ) {
    final mushafVerse =
        layout.prefersQuranicFont && QuranText.isStandaloneVerse(text);
    return TexText(
      text,
      style: bodyStyle,
      mathTextStyle: bodyStyle,
      quranStyle: mushafVerse
          ? PaperStyles.verse(layout)
          : PaperStyles.quranic(bodyStyle),
      textAlign: mushafVerse ? TextAlign.center : TextAlign.start,
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
    final content = branch.content;
    final answerStyle = PaperStyles.answerBody(layout);
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
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        '( ${layout.branchLabel(index)} )',
                        style: PaperStyles.option,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _paperField(
                        key: ValueKey<String>(_optionKey(branch.id, index)),
                        controller: _field(
                          _optionKey(branch.id, index),
                          content.options[index].text,
                          (value) => controller.updateBranchOptionText(ref, index, value),
                        ),
                        style: _showTeacherAnswers && content.options[index].isCorrect
                            ? answerStyle
                            : PaperStyles.option,
                        hint: layout.isLtr ? 'Option...' : 'نص الخيار...',
                        registerInserter: true,
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
                    if (content.options.length > 1)
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
        if (_showTeacherAnswers) {
          final answer = content.trueFalseAnswer;
          return Text(
            layout.isLtr
                ? 'Answer: ${answer ? 'True' : 'False'} •'
                : 'الإجابة الصحيحة: ${answer ? 'صح' : 'خطأ'} •',
            style: answerStyle,
          );
        }
        if (content.plainText) {
          return const SizedBox.shrink();
        }
        return Text(
          layout.isLtr
              ? 'Answer: (     ) True      (     ) False'
              : 'الإجابة: (     ) صح      (     ) خطأ',
          style: PaperStyles.body(layout),
        );
      case QuestionType.fillInTheBlank:
        if (_showTeacherAnswers) {
          return _buildModelAnswerField(controller, ref, layout, branch, answerStyle);
        }
        if (content.plainText) {
          return const SizedBox.shrink();
        }
        return Text(
          '${layout.isLtr ? 'Answer' : 'الإجابة'}: '
          '............................................................................',
          style: PaperStyles.body(layout),
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      case QuestionType.essay:
        if (_showTeacherAnswers) {
          return _buildModelAnswerField(controller, ref, layout, branch, answerStyle);
        }
        if (content.plainText) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List<Widget>.generate(
            layout.essayAnswerLines,
            (_) => Text(
              '................................................................................................',
              style: PaperStyles.small,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        );
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
          child: _paperField(
            key: ValueKey<String>(_modelAnswerKey(branch.id)),
            controller: _field(
              _modelAnswerKey(branch.id),
              content.modelAnswer,
              (value) => controller.updateBranchModelAnswer(ref, value),
            ),
            style: answerStyle,
            hint: layout.isLtr ? 'Model answer...' : 'اكتب الإجابة النموذجية...',
            registerInserter: true,
          ),
        ),
        Text(' •', style: answerStyle),
      ],
    );
  }

  /// حقل نصي مسطّح على الورقة (تحرير مباشر بلا حوارات).
  Widget _paperField({
    required TextEditingController controller,
    required TextStyle style,
    Key? key,
    TextAlign textAlign = TextAlign.start,
    String? hint,
    bool registerInserter = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      maxLines: null,
      textAlign: textAlign,
      style: style,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: PaperStyles.hint(style),
      ),
      onTap: registerInserter ? () => _inserter.controller = controller : null,
    );
  }
}
