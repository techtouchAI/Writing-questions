import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam_document.dart';
import '../../models/question_model.dart';
import '../../providers/exam_wizard_controller.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/points_editor.dart';
import '../widgets/rich_content_field.dart';
import 'branch_editor_card.dart';

/// الخطوة 2 من المعالج: إعداد سؤال واحد بمنطوقه ونقاطه وفروعه (أ، ب، ج...).
///
/// الحقول بترتيب الطباعة نفسه:
/// الرقم ← المنطوق ← الدرجة (رقم خام يطبعه النظام «(٢٠ درجة)») ← النص (يُحذف
/// من الورقة عند فراغه) ← النقاط المرقّمة ذات النص الحر ← الفروع.
///
/// - العنوان ديناميكي: «إعداد السؤال الأول» ثم «الثاني»...
/// - الدرجة تلقائية (مجموع الفروع والنقاط) ما لم يكتب المدرس رقماً.
/// - [التالي] يحفظ السؤال ويفتح سؤالاً جديداً فارغاً، و[إنهاء وعرض النموذج]
///   ينتقل إلى محرك المعاينة A4.
class QuestionStepScreen extends StatefulWidget {
  const QuestionStepScreen({
    super.key,
    required this.onFinish,
    required this.onBack,
  });

  final VoidCallback onFinish;
  final VoidCallback onBack;

  @override
  State<QuestionStepScreen> createState() => _QuestionStepScreenState();
}

class _QuestionStepScreenState extends State<QuestionStepScreen> {
  final TextEditingController _manualMarksController = TextEditingController();
  int? _marksQuestionIndex;

  /// التحديد المتعدد في قائمة الأسئلة: ضغط مطوّل على سؤال يدخل «وضع
  /// التحديد» ويحدد السؤال المضغوط، وبعدها كل ضغطة تقلب تحديد سؤالها.
  /// حالة عرض مؤقتة فقط — لا تغيّر الأسئلة ولا محتواها ولا ترتيبها.
  bool _selectionMode = false;
  final Set<String> _selectedQuestionIds = <String>{};

  void _enterSelectionModeWith(String questionId) {
    setState(() {
      _selectionMode = true;
      _selectedQuestionIds.add(questionId);
    });
  }

  void _toggleQuestionSelection(String questionId) {
    setState(() {
      if (!_selectedQuestionIds.remove(questionId)) {
        _selectedQuestionIds.add(questionId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedQuestionIds.clear();
    });
  }

  /// التحديد الفعّال داخل نطاق هذه الشاشة: تقاطع المعرّفات المخزَّنة مع
  /// أسئلة المستند الحالية.
  ///
  /// المصدر الوحيد لحالة التحديد في العدّاد وحالة الأزرار وأهداف النسخ/
  /// الحذف: معرّف سؤال حُذف (بحذف خارجي أو تراجع) لا يبقى محسوباً، فلا
  /// يعرض العدّاد رقماً لا مقابل له في الشريط، ولا يصل هدف إلى سؤال غير
  /// موجود.
  Set<String> _selectedIdsInScope(List<QuestionModel> questions) {
    if (!_selectionMode) {
      return const <String>{};
    }
    final liveIds = questions.map((question) => question.id).toSet();
    return _selectedQuestionIds.where(liveIds.contains).toSet();
  }

  /// «تحديد الكل» ↔ «إلغاء تحديد الكل»: إن كانت كل الأسئلة محددة تُفرَّغ،
  /// وإلا تُحدد كلها — مع الدخول في وضع التحديد في الحالتين.
  ///
  /// النطاق = أسئلة هذه الشاشة وحدها (رقائق الشريط نفسها)؛ الفروع والنقاط
  /// ليست قابلة للتحديد هنا فلا تدخل العدّاد ولا التحديد.
  void _toggleSelectAll(List<QuestionModel> questions) {
    if (questions.isEmpty) {
      _showMessage('لا توجد أسئلة في هذه الشاشة لتحديدها.');
      return;
    }
    final ids = questions.map((question) => question.id).toSet();
    final allSelected =
        ids.isNotEmpty && _selectedIdsInScope(questions).containsAll(ids);
    setState(() {
      _selectionMode = true;
      if (allSelected) {
        _selectedQuestionIds.clear();
      } else {
        _selectedQuestionIds
          ..removeWhere((id) => !ids.contains(id))
          ..addAll(ids);
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// أهداف زرَّي «نسخ»/«حذف»: الأسئلة **المحددة فعلاً** داخل وضع التحديد،
  /// وإلا السؤال المفتوح (سلوك الشريط السابق للتحديد المتعدد كما هو).
  ///
  /// وضع تحديد بلا عنصر محدد = بلا هدف: لا يُنسخ شيء ولا يُحذف شيء، حتى
  /// لا تُطاح أسئلة لم يقصدها المستخدم (منع الحذف غير المقصود عند غياب
  /// التحديد).
  List<int> _actionTargets(ExamWizardController controller) {
    if (!_selectionMode) {
      return <int>[controller.currentQuestionIndex];
    }
    final questions = controller.questions;
    final selectedIds = _selectedIdsInScope(questions);
    return <int>[
      for (var index = 0; index < questions.length; index++)
        if (selectedIds.contains(questions[index].id)) index,
    ];
  }

  /// «نسخ»: ينسخ السؤال المحدد (أو الأسئلة المحددة) نسخاً حقيقياً داخل
  /// المستند — كل نسخة بعد أصلها بمحتواها وإعداداتها — بآليّة التكرار
  /// المعتمدة في المتحكم، لا نسخ نص للحافظة.
  void _copyAction(ExamWizardController controller) {
    final targets = _actionTargets(controller);
    if (targets.isEmpty) {
      _showMessage('لم تحدد أي سؤال — حدّد سؤالاً أو أكثر لنسخه.');
      return;
    }
    controller.duplicateQuestions(targets);
    final document = controller.document;
    _showMessage(
      targets.length == 1
          ? 'نُسخ السؤال بعد الأصل مباشرة.'
          : 'نُسخت ${document.formatNumber(targets.length)} من الأسئلة بعد أصولها.',
    );
  }

  /// «حذف»: يحذف العناصر المحددة فقط. خارج وضع التحديد يبقى السؤال المفتوح
  /// هو الهدف (سلوك الزر السابق كما هو)، وفي وضع التحديد لا يُحذف شيء بلا
  /// تحديد. يبقى سؤال واحد على الأقل في المستند.
  void _deleteAction(ExamWizardController controller) {
    final targets = _actionTargets(controller);
    if (targets.isEmpty) {
      _showMessage('لم تحدد أي سؤال — الحذف يُطبَّق على المحدد فقط.');
      return;
    }
    if (!_selectionMode) {
      controller.removeQuestion(targets.single);
      return;
    }
    final removed = controller.removeQuestions(targets);
    _exitSelectionMode();
    if (removed > 0) {
      _showMessage(
        'حُذف ${controller.document.formatNumber(removed)} من الأسئلة المحددة.',
      );
    }
  }

  @override
  void dispose() {
    _manualMarksController.dispose();
    super.dispose();
  }

  bool _validate(BuildContext context, ExamWizardController controller) {
    final question = controller.currentQuestion;
    // الشرط الوحيد: محتوى مكتوب (منطوق أو نقطة أو فرع) حتى لا تُنشأ صفحات فارغة.
    // الدرجة اختيارية تماماً — المدرس حر في تثبيتها الآن أو لاحقاً من المعاينة.
    if (!question.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اكتب منطوق السؤال أو نقطة واحدة أو محتوى فرع على الأقل قبل المتابعة.')),
      );
      return false;
    }
    return true;
  }

  void _syncPromptField(ExamWizardController controller, int questionIndex) {
    if (_marksQuestionIndex != questionIndex) {
      _marksQuestionIndex = questionIndex;
      _manualMarksController.text =
          _formatManualMarks(controller.questions[questionIndex].marksOverride);
    }
  }

  static String _formatManualMarks(double? marks) {
    if (marks == null) {
      return '';
    }
    return marks == marks.truncateToDouble() ? marks.toInt().toString() : marks.toString();
  }

  /// تلميح درجة النقطة: يري المدرس نص الطباعة النهائي «(٢ درجة)» قبل كتابته.
  static String _pointMarksHelper(ExamDocument document, double marks) {
    if (marks <= 0) {
      return 'اكتب رقماً أكبر من صفر لتُطبع الدرجة بجانب النقطة.';
    }
    return 'تُطبع بصيغة (${document.formatNumber(marks)} ${document.layout.marksUnit}) '
        'عند تفعيل «إظهار درجات الأسئلة».';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final layout = controller.layout;
    final questionIndex = controller.currentQuestionIndex;
    final question = controller.currentQuestion;
    final colorScheme = Theme.of(context).colorScheme;
    final sections = layout.sections;
    final questionLabel = controller.document.displayQuestionLabel(question);
    // حالة الأزرار تتبع التحديد: داخل وضع التحديد يعمل «نسخ»/«حذف» على
    // المحدد وحده فيُعطَّلان بلا تحديد، وخارج الوضع يعملان على السؤال
    // المفتوح (سلوكهما السابق كما هو).
    final hasActionTarget = !_selectionMode ||
        _selectedIdsInScope(controller.questions).isNotEmpty;
    final copyEnabled = hasActionTarget;
    final deleteEnabled = hasActionTarget && controller.questions.length > 1;
    _syncPromptField(controller, questionIndex);

    return Scaffold(
      appBar: AppBar(
        title: Text(layout.isLtr ? 'Set up $questionLabel' : 'إعداد $questionLabel'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: questionIndex == 0 ? 'العودة للترويسة' : 'السؤال السابق',
          onPressed: questionIndex == 0 ? widget.onBack : controller.goToPreviousQuestion,
        ),
        actions: <Widget>[
          if (questionIndex > 0)
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'نقل السؤال لأعلى',
              onPressed: () => controller.moveQuestion(questionIndex, questionIndex - 1),
            ),
          if (questionIndex < controller.questions.length - 1)
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              tooltip: 'نقل السؤال لأسفل',
              onPressed: () => controller.moveQuestion(questionIndex, questionIndex + 1),
            ),
          IconButton(
            key: const ValueKey<String>('question-copy-action'),
            icon: const Icon(Icons.copy_outlined),
            tooltip:
                _selectionMode ? 'نسخ الأسئلة المحددة' : 'نسخ السؤال',
            // معطَّل في وضع التحديد ما لم يكن هناك عنصر محدد فعلاً: زر
            // «نسخ» ينسخ المحدد (حالة الأزرار تتبع التحديد).
            onPressed:
                copyEnabled ? () => _copyAction(controller) : null,
          ),
          if (controller.questions.length > 1)
            IconButton(
              key: const ValueKey<String>('question-delete-action'),
              icon: const Icon(Icons.delete_outline),
              tooltip:
                  _selectionMode ? 'حذف الأسئلة المحددة' : 'حذف هذا السؤال',
              onPressed:
                  deleteEnabled ? () => _deleteAction(controller) : null,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildProgressStrip(context, controller),
            if (<String>{'الرياضيات', 'الفيزياء', 'الكيمياء'}.contains(controller.document.header.subject))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'اكتب النص في محرره، وأضف المعادلات من محرر النص والمعادلات: '
                  'النص والمعادلات يظهران دائماً بشكلهما النهائي بلا أي أكواد.',
                  textDirection: TextDirection.rtl,
                ),
              ),
            _buildQuestionNumberField(controller, questionIndex, question),
            const SizedBox(height: 12),
            // منطوق السؤال: عرض نهائي + تحرير في محرر المحتوى المختلط (نص
            // ومعادلات مرئية) — فلا يظهر كود LaTeX في أي مرحلة.
            RichContentField(
              label: layout.isLtr ? 'Question statement' : 'منطوق السؤال',
              hint: layout.isLtr
                  ? 'e.g. Choose the correct answer'
                  : 'اكتب منطوق السؤال هنا (مثال: اختر الإجابة الصحيحة لما يأتي)',
              title: 'تحرير منطوق السؤال',
              value: question.statement,
              minHeight: 56,
              onChanged: (value) =>
                  controller.updateQuestionStatement(questionIndex, value),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: LtrNumericField(
                    controller: _manualMarksController,
                    decoration: const InputDecoration(
                      labelText: 'درجة السؤال',
                      hintText: 'اكتب الرقم فقط، مثال: 20 (فارغ = تلقائي)',
                      suffixText: 'درجة',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final normalized = value.trim();
                      if (normalized.isEmpty) {
                        controller.updateQuestionMarksOverride(questionIndex, null);
                        return;
                      }
                      final marks = double.tryParse(
                        normalized.replaceAll('،', '.').replaceAll(',', '.'),
                      );
                      if (marks != null && marks.isFinite && marks >= 0) {
                        controller.updateQuestionMarksOverride(questionIndex, marks);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: question.hasAutoMarks
                      ? 'الدرجة محسوبة تلقائياً من الفروع والنقاط'
                      : 'درجة ثابتة كتبتها بنفسك — امسح الحقل للعودة للتلقائي',
                  child: Chip(
                    label: Text(
                      question.hasAutoMarks ? 'تلقائي' : 'يدوي',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichContentField(
              label: layout.isLtr
                  ? 'Question text (optional)'
                  : 'نص السؤال (اختياري)',
              hint: 'يُحذف من الورقة تلقائياً إذا تُرك فارغاً',
              title: 'تحرير نص السؤال',
              value: question.body,
              minHeight: 56,
              onChanged: (value) =>
                  controller.updateQuestionBody(questionIndex, value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: question.spacingAfter.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المسافة بعد السؤال (بكسل)',
                hintText: 'مثال: 10',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final spacing = double.tryParse(value.replaceAll(',', '.'));
                if (spacing != null) controller.updateQuestionSpacing(questionIndex, spacing);
              },
            ),
            const SizedBox(height: 12),
            if (sections.isNotEmpty) ...<Widget>[
              DropdownButtonFormField<String>(
                value: sections.contains(question.category) ? question.category : '',
                decoration: const InputDecoration(
                  labelText: 'القسم (اختياري)',
                  hintText: 'اختر «بدون قسم» لعدم طباعة عنوان قسم قبل السؤال',
                  helperText: 'يُطبع عنوان القسم قبل السؤال في الورقة.',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(value: '', child: Text('بدون قسم')),
                  ...sections.map(
                    (section) => DropdownMenuItem<String>(
                      value: section,
                      child: Text(section, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    controller.updateQuestionCategory(questionIndex, value ?? ''),
              ),
              const SizedBox(height: 12),
            ],
            // نقاط السؤال المباشرة (١-، ٢-، ٣-...) — نص حر فقط، وتظهر
            // دائماً وهي محتوى السؤال كاملاً عند كتابة سؤال بلا فروع.
            PointsEditor(
              points: question.items,
              labelOf: (index, point) => controller.document.displayItemLabel(point, index),
              optionLabelOf: (index, option) =>
                  controller.document.displayOptionLabel(option, index),
              marksHelperOf: (marks) => _pointMarksHelper(controller.document, marks),
              onChanged: (points) =>
                  controller.setPoints(PointsOwner.question(questionIndex), points),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < question.branches.length; index++)
              BranchEditorCard(
                key: ValueKey<String>('branch-editor-${question.branches[index].id}'),
                label: controller.document.displayBranchLabel(questionIndex, index),
                autoLabel: layout.branchLabel(index),
                branch: question.branches[index],
                pointLabelOf: (pointIndex, point) =>
                    controller.document.displayItemLabel(point, pointIndex),
                optionLabelOf: (optionIndex, option) =>
                    controller.document.displayOptionLabel(option, optionIndex),
                pointMarksHelperOf: (marks) =>
                    _pointMarksHelper(controller.document, marks),
                onChanged: (branch) {
                  final ref = BranchRef(questionIndex: questionIndex, branchIndex: index);
                  controller.updateBranchContent(ref, branch.content);
                  controller.updateBranchMarks(ref, branch.marks);
                  controller.updateBranchLabelOverride(ref, branch.labelOverride);
                },
                // لا حد أدنى للفروع: يُحذف الأخير أيضاً.
                onRemove: () => controller.removeBranch(
                  BranchRef(questionIndex: questionIndex, branchIndex: index),
                ),
              ),
            // السؤال الجديد بلا فروع؛ التلميح يوجّه لأول إنشاء صريح.
            if (question.branches.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  layout.isLtr
                      ? 'No branches yet — add points above, or create the first branch below.'
                      : 'لا فروع بعد — اكتب نقاط السؤال أعلاه، أو أنشئ الفرع الأول بالزر أدناه.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => controller.addBranch(questionIndex),
              icon: const Icon(Icons.add),
              label: Text(
                'إضافة فرع جديد (${layout.branchLabel(question.branches.length)})',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'درجة $questionLabel: ${controller.document.formatNumber(question.marks)} ${layout.marksUnit}'
                '  |  مجموع النموذج: ${controller.document.formatNumber(controller.document.totalMarks)} '
                '${layout.marksUnit}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  if (_validate(context, controller)) {
                    controller.goToNextQuestion();
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(
                  questionIndex < controller.questions.length - 1
                      ? 'التالي: ${controller.document.displayQuestionLabel(controller.questions[questionIndex + 1])}'
                      : 'التالي: سؤال جديد',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (_validate(context, controller)) {
                    widget.onFinish();
                  }
                },
                icon: const Icon(Icons.preview),
                label: const Text('إنهاء وعرض النموذج'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// رقم السؤال: ما يكتبه المدرس يُطبع حرفياً («س١/»، «السؤال الاول/»)،
  /// والفارغ يعني ترقيماً تلقائياً من نمط التسمية العام.
  Widget _buildQuestionNumberField(
    ExamWizardController controller,
    int questionIndex,
    QuestionModel question,
  ) {
    final document = controller.document;
    return TextFormField(
      key: ValueKey<String>('question-label-${question.id}'),
      initialValue: question.numberOverride ?? '',
      decoration: InputDecoration(
        labelText: 'رقم السؤال (فارغ = تلقائي)',
        hintText: 'مثال: س١/ أو السؤال الاول/ — تلقائي: '
            '${document.autoQuestionLabel(question)}${document.layout.questionSeparator}',
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) =>
          controller.updateQuestionNumberOverride(questionIndex, value),
    );
  }

  /// شريط التنقّل بين الأسئلة المُعدّة — وهو قائمة الأسئلة نفسها: ضغطة
  /// تفتح السؤال، وضغطة مطوّلة تدخل وضع التحديد المتعدد، وزر «تحديد الكل»
  /// يحدد الأسئلة جميعها (ويتحول «إلغاء تحديد الكل» عندما تكون محددة).
  Widget _buildProgressStrip(BuildContext context, ExamWizardController controller) {
    final document = controller.document;
    final questions = controller.questions;
    final selectedIds = _selectedIdsInScope(questions);
    final selectedCount = selectedIds.length;
    final allSelected = questions.isNotEmpty && selectedCount == questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_selectionMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'المحدد ${document.formatNumber(selectedCount)} '
                      'من ${document.formatNumber(questions.length)}',
                      key: const ValueKey<String>('question-selection-count'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('exit-selection-mode'),
                  onPressed: _exitSelectionMode,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('إنهاء التحديد'),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 40,
          // تمرير أفقي غير كسول (Row داخل SingleChildScrollView لا ListView):
          // تُبنى كل الرقائق دائماً في شجرة الودجت مهما طال النطاق، فتبقى
          // قابلة للوصول في الاختبارات ومساعدات الوصول، مع التمرير الأفقي
          // والتصميم كما هما تماماً.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ActionChip(
                  key: const ValueKey<String>('select-all-questions'),
                  avatar: Icon(
                    allSelected ? Icons.deselect : Icons.select_all,
                    size: 18,
                  ),
                  label: Text(allSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل'),
                  onPressed: () => _toggleSelectAll(questions),
                ),
                for (var index = 0; index < questions.length; index++) ...<Widget>[
                  const SizedBox(width: 6),
                  _buildQuestionChip(controller, index, selectedIds),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// رقاقة سؤال واحد: الضغطة العادية تفتحه للتحرير كما كانت دائماً (أو
  /// تقلب تحديده داخل وضع التحديد)، والضغط المطوّل يدخل وضع التحديد
  /// المتعدد ويحدد هذا السؤال — بلا أي أثر على بقية الأسئلة.
  Widget _buildQuestionChip(
    ExamWizardController controller,
    int index,
    Set<String> selectedIds,
  ) {
    final question = controller.questions[index];
    final selectedInMode =
        _selectionMode && selectedIds.contains(question.id);
    return GestureDetector(
      onLongPress: () {
        if (_selectionMode) {
          _toggleQuestionSelection(question.id);
        } else {
          _enterSelectionModeWith(question.id);
        }
      },
      child: ChoiceChip(
        key: ValueKey<String>('question-chip-${question.id}'),
        label: Text(controller.document.displayQuestionLabel(question)),
        selected: _selectionMode
            ? selectedInMode
            : index == controller.currentQuestionIndex,
        onSelected: (_) {
          if (_selectionMode) {
            _toggleQuestionSelection(question.id);
          } else {
            controller.openQuestion(index);
          }
        },
      ),
    );
  }
}
