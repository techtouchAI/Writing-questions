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
/// من الورقة عند فراغه) ← النقاط المرقّمة بأنواعها المختلطة ← الفروع.
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final layout = controller.layout;
    final questionIndex = controller.currentQuestionIndex;
    final question = controller.currentQuestion;
    final colorScheme = Theme.of(context).colorScheme;
    final sections = layout.sections;
    final questionLabel = controller.document.displayQuestionLabel(question);
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
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'نسخ السؤال',
            onPressed: () => controller.duplicateQuestion(questionIndex),
          ),
          if (controller.questions.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'حذف هذا السؤال',
              onPressed: () => controller.removeQuestion(questionIndex),
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
            // نقاط السؤال المباشرة (١-، ٢-، ٣-...) بأنواعها المختلطة — تظهر
            // دائماً وهي محتوى السؤال كاملاً عند كتابة سؤال بلا فروع.
            PointsEditor(
              points: question.items,
              labelOf: (index, point) => controller.document.displayItemLabel(point, index),
              optionLabelOf: (index, option) =>
                  controller.document.displayOptionLabel(option, index),
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

  /// شريط تنقّل سريع بين الأسئلة المُعدّة.
  Widget _buildProgressStrip(BuildContext context, ExamWizardController controller) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final selected = index == controller.currentQuestionIndex;
          return ChoiceChip(
            label: Text(
              controller.document.displayQuestionLabel(controller.questions[index]),
            ),
            selected: selected,
            onSelected: (_) => controller.openQuestion(index),
          );
        },
      ),
    );
  }
}
