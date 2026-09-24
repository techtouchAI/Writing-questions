import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../layout/pagination_engine.dart';
import '../../layout/paper_metrics.dart';
import '../../models/branch_model.dart';
import '../../models/exam_canvas_geometry.dart';
import '../../models/exam_document.dart';
import '../../models/exam_header_model.dart';
import '../../models/floating_element.dart';
import '../../models/question_model.dart';
import '../../models/question_type.dart';
import '../../models/subject_layout.dart';
import '../../models/tex_content.dart';
import '../../providers/exam_document_provider.dart';
import '../../providers/exam_wizard_controller.dart';
import '../../services/export_file_service.dart';
import '../../services/pdf_export_service.dart';
import '../widgets/floating_element_view.dart';
import '../widgets/formula_inserter.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/smart_exam_toolbar.dart';
import '../widgets/tex_text.dart';
import 'measure_size.dart';
import 'paper_styles.dart';

/// الخطوة 3: محرك المعاينة والمراجعة (WYSIWYG A4 Engine).
///
/// - **التقسيم الورقي الديناميكي**: كل كتلة (الترويسة/السؤال الكامل) تُقاس
///   عبر [MeasureSize] وتُبلّغ [ExamWizardController] الذي يعيد التوزيع عبر
///   `PaginationEngine` — السؤال لا يُفصل عن فروعه أبداً.
/// - **التحرير المباشر**: كل نص على الورقة حقل مسطّح قابل للكتابة.
/// - **السحب والإفلات المخصص**: سحب فرع وإفلاته على فرع آخر يبدّل
///   المحتوى والدرجة فقط؛ العناوين (السؤال الأول - أ) تبقى ثابتة.
/// - **الأدوات العائمة**: نفس أداة الرسم الحالية ([SmartExamToolbar]) تضيف
///   صوراً/أشكالاً تتراكب فوق مساحة الفرع المحدد وتُسحب وتُغيَّر أبعادها.
class ExamPreviewScreen extends StatefulWidget {
  const ExamPreviewScreen({super.key, required this.onBackToQuestions});

  final VoidCallback onBackToQuestions;

  @override
  State<ExamPreviewScreen> createState() => _ExamPreviewScreenState();
}

class _ExamPreviewScreenState extends State<ExamPreviewScreen> {
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{};
  final FormulaInserter _inserter = FormulaInserter();
  ExamWizardController? _controller;
  String? _selectedAttachmentId;
  bool _isBusy = false;

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
  static String _headerKey(HeaderSlot slot, int line) => 'header-${slot.name}-$line';
  static const String _instructionsKey = 'instructions';

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
      for (final branch in question.branches) {
        final textField = _fields[_branchTextKey(branch.id)];
        if (textField != null && textField.text != branch.content.text) {
          textField.text = branch.content.text;
        }
        final marksField = _fields[_branchMarksKey(branch.id)];
        if (marksField != null && _parseMarks(marksField.text) != branch.marks) {
          marksField.text = _formatMarksInput(branch.marks);
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

  void _addAttachment(FloatingElement element) {
    final added = _controller!.addAttachment(element);
    if (!added) {
      _showMessage('انقر على فرع داخل الورقة أولاً لتحديد موضع الإدراج.');
      return;
    }
    setState(() => _selectedAttachmentId = element.id);
  }

  void _addImage(List<int> bytes) {
    _addAttachment(
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

  void _addShape(FloatingShapeType shape) {
    _addAttachment(
      FloatingElement(
        type: FloatingElementType.shape,
        shape: shape,
        dx: 0,
        dy: 0,
        width: ExamCanvasGeometry.defaultElementSize,
        height: ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  void _addBranchToSelected() {
    final controller = _controller!;
    final target = controller.selectedBranch?.questionIndex ?? controller.questions.length - 1;
    controller.addBranch(target);
  }

  Future<void> _save() async {
    final provider = context.read<ExamDocumentProvider?>();
    if (provider == null) {
      _showMessage('الحفظ غير متاح في هذا السياق.', isError: true);
      return;
    }
    setState(() => _isBusy = true);
    try {
      await provider.saveDocument(_controller!.document);
      if (mounted) {
        _showMessage('تم حفظ النموذج الوزاري.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر حفظ النموذج. حاول مرة أخرى.', isError: true);
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            title: isTeacherVersion ? 'معاينة نموذج الإجابة' : 'معاينة النموذج الوزاري',
            fileName: '${controller.document.name}'
                '${isTeacherVersion ? '_نموذج_الإجابة' : '_النموذج_الوزاري'}.pdf',
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

  // ------------------------------------------------------------------
  // البناء
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final layout = controller.layout;
    final pagination = controller.pagination;

    return Scaffold(
      appBar: AppBar(
        title: Text('الخطوة 3: معاينة A4 (${pagination.pageCount} صفحة)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'العودة للأسئلة',
          onPressed: widget.onBackToQuestions,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'حفظ النموذج',
            onPressed: _isBusy ? null : _save,
          ),
          PopupMenuButton<bool>(
            tooltip: 'تصدير PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            enabled: !_isBusy,
            onSelected: (teacher) => _exportPdf(isTeacherVersion: teacher),
            itemBuilder: (_) => const <PopupMenuEntry<bool>>[
              PopupMenuItem<bool>(value: false, child: Text('PDF — ورقة الطالب')),
              PopupMenuItem<bool>(value: true, child: Text('PDF — نموذج الإجابة')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SmartExamToolbar(
            inserter: _inserter,
            onInsertText: _inserter.insert,
            onAddImage: _addImage,
            onAddShape: _addShape,
            onAddMainQuestion: controller.addQuestion,
            onAddBranch: _addBranchToSelected,
          ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: <Widget>[
                      for (final page in pagination.pages)
                        _buildPage(controller, layout, page, pagination.pageCount),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    PaginatedPage page,
    int pageCount,
  ) {
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
      blocks.add(
        MeasureSize(
          key: ValueKey<String>('measure-$blockId'),
          onChange: (size) => controller.reportBlockHeight(blockId, size.height),
          child: _buildQuestionBlock(controller, layout, question),
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
        margin: const EdgeInsets.only(bottom: 16),
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
                child: Center(
                  child: Text(
                    layout.isLtr
                        ? 'Page ${page.index + 1} of $pageCount'
                        : 'صفحة ${layout.formatNumber(page.index + 1)} من '
                            '${layout.formatNumber(pageCount)}',
                    style: PaperStyles.footer,
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
  // الترويسة الوزارية (3 أعمدة × 3 أسطر) — قابلة للتحرير
  // ------------------------------------------------------------------

  Widget _buildHeaderBlock(ExamWizardController controller, SubjectLayoutTemplate layout) {
    final header = controller.document.header;

    Widget column(HeaderSlot slot, {required bool center}) {
      final lines = header.column(slot).lines;
      return Expanded(
        flex: center ? 4 : 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < lines.length; index++)
              _paperField(
                controller: _field(
                  _headerKey(slot, index),
                  lines[index],
                  (value) => controller.updateHeaderLine(slot, index, value),
                ),
                style: center ? PaperStyles.headerCenter : PaperStyles.headerLine,
                textAlign: center ? TextAlign.center : TextAlign.start,
                hint: 'سطر ${index + 1}',
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: PaperStyles.primary, width: 1.4),
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
        const SizedBox(height: 4),
        Text(
          layout.isLtr
              ? 'Total: ${layout.formatNumber(controller.document.totalMarks)} ${layout.marksUnit}  |  '
                  'Questions: ${layout.formatNumber(controller.questions.length)}'
              : 'الدرجة الكلية: ${layout.formatNumber(controller.document.totalMarks)} '
                  '${layout.marksUnit}  |  عدد الأسئلة: '
                  '${layout.formatNumber(controller.questions.length)}',
          textAlign: TextAlign.center,
          style: PaperStyles.small,
        ),
        _paperField(
          controller: _field(_instructionsKey, header.instructions, controller.updateInstructions),
          style: PaperStyles.note,
          textAlign: TextAlign.center,
          hint: 'ملاحظة / تعليمات للطلاب...',
        ),
        const Divider(thickness: 1.5, color: PaperStyles.primary, height: 10),
      ],
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
    final questionIndex = controller.questions.indexOf(question);
    final category = question.category.trim();
    return Column(
      key: ValueKey<String>('question-block-${question.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (category.isNotEmpty) Text(category, style: PaperStyles.category),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${layout.questionLabel(question.questionNumber)}: '
                '[${layout.formatNumber(question.marks)} ${layout.marksUnit}]',
                style: PaperStyles.question,
              ),
            ),
            IconButton(
              tooltip: 'إضافة فرع',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => controller.addBranch(questionIndex),
            ),
            if (controller.questions.length > 1)
              IconButton(
                tooltip: 'حذف السؤال',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => controller.removeQuestion(questionIndex),
              ),
          ],
        ),
        for (var index = 0; index < question.branches.length; index++)
          _buildBranchBlock(
            controller,
            layout,
            BranchRef(questionIndex: questionIndex, branchIndex: index),
            question.branches[index],
          ),
      ],
    );
  }

  Widget _buildBranchBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    BranchModel branch,
  ) {
    final label = layout.branchLabel(ref.branchIndex);
    final selected = controller.selectedBranch == ref;

    // مقبض السحب وحده يبدأ السحب (حتى لا يتعارض مع تحديد النص في الحقول)؛
    // الهدف هو كتلة الفرع كاملة.
    final dragHandle = LongPressDraggable<BranchRef>(
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
      childWhenDragging: Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade300),
      // لا Tooltip هنا: مُعرِّف الضغط المطوّل الخاص به يتنافس مع بدء السحب.
      child: Semantics(
        label: 'اضغط مطولاً واسحب لتبديل المحتوى مع فرع آخر',
        child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade600),
      ),
    );

    return DragTarget<BranchRef>(
      key: ValueKey<String>('branch-target-${branch.id}'),
      onWillAcceptWithDetails: (details) => details.data != ref,
      onAcceptWithDetails: (details) => controller.swapBranchContent(details.data, ref),
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            controller.selectBranch(ref);
            setState(() => _selectedAttachmentId = null);
          },
          child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsetsDirectional.only(start: 4, end: 4, top: 2, bottom: 2),
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
    final content = branch.content;
    final bodyStyle = PaperStyles.body(layout);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(top: 2), child: dragHandle),
            SizedBox(
              width: 22,
              child: Text('$label)', style: bodyStyle.copyWith(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _paperField(
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
          ],
        ),
        if (TexContent.containsMath(content.text))
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 36),
            child: TexText(content.text, style: bodyStyle),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 36, top: 1),
          child: _buildTypeBody(layout, content),
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
          _buildAttachment(controller, ref, element),
      ],
    );
  }

  Widget _buildAttachment(
    ExamWizardController controller,
    BranchRef ref,
    FloatingElement element,
  ) {
    final selected = _selectedAttachmentId == element.id;
    return PositionedDirectional(
      start: element.dx,
      top: element.dy,
      width: element.width,
      height: element.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.selectBranch(ref);
          setState(() => _selectedAttachmentId = element.id);
        },
        onPanUpdate: (details) {
          final maxDx = PaperMetrics.contentWidthPx - element.width;
          controller.updateAttachment(
            ref,
            element.copyWith(
              dx: (element.dx + details.delta.dx).clamp(0.0, maxDx < 0 ? 0.0 : maxDx),
              dy: (element.dy + details.delta.dy).clamp(0.0, ExamCanvasGeometry.height),
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
                child: FloatingElementView(element: element),
              ),
            ),
            if (selected)
              Positioned(
                left: -12,
                top: -12,
                child: GestureDetector(
                  onTap: () {
                    controller.removeAttachment(ref, element.id);
                    setState(() => _selectedAttachmentId = null);
                  },
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: PaperStyles.danger,
                    child: Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                right: -6,
                bottom: -6,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    controller.updateAttachment(
                      ref,
                      element.copyWith(
                        width: (element.width + details.delta.dx).clamp(24.0, 600.0),
                        height: (element.height + details.delta.dy).clamp(24.0, 600.0),
                      ),
                    );
                  },
                  child: const Icon(Icons.south_east, size: 18, color: PaperStyles.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// جسم الفرع حسب نوعه (ورقة الطالب): خيارات / صح-خطأ / فراغ / أسطر مقالية.
  Widget _buildTypeBody(SubjectLayoutTemplate layout, BranchContent content) {
    switch (content.type) {
      case QuestionType.multipleChoice:
        final options = content.options
            .where((option) => option.text.trim().isNotEmpty)
            .toList(growable: false);
        return Wrap(
          spacing: 14,
          runSpacing: 2,
          children: <Widget>[
            for (var index = 0; index < options.length; index++)
              Text(
                '( ${layout.branchLabel(index)} ) ${options[index].text}',
                style: PaperStyles.option,
              ),
          ],
        );
      case QuestionType.trueFalse:
        return Text(
          layout.isLtr
              ? 'Answer: (     ) True      (     ) False'
              : 'الإجابة: (     ) صح      (     ) خطأ',
          style: PaperStyles.body(layout),
        );
      case QuestionType.fillInTheBlank:
        return Text(
          '${layout.isLtr ? 'Answer' : 'الإجابة'}: '
          '............................................................................',
          style: PaperStyles.body(layout),
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      case QuestionType.essay:
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

  /// حقل نصي مسطّح على الورقة (تحرير مباشر بلا حوارات).
  Widget _paperField({
    required TextEditingController controller,
    required TextStyle style,
    TextAlign textAlign = TextAlign.start,
    String? hint,
    bool registerInserter = false,
  }) {
    return TextField(
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
