import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam_document.dart';
import '../../providers/exam_wizard_controller.dart';
import '../widgets/ltr_numeric_field.dart';
import 'branch_editor_card.dart';

/// الخطوة 2 من المعالج: إعداد سؤال واحد بنصه وفروعه (أ، ب، ج...).
///
/// - العنوان ديناميكي: «إعداد السؤال الأول» ثم «الثاني»...
/// - حقل حر لنص السؤال/تعليماته («أجب عن فرعين فقط:»...) بلا صيغة مفروضة.
/// - يبدأ بفرع (أ) افتراضياً؛ [إضافة فرع جديد] يضيف (ب) ثم (ج) بنفس الأدوات.
/// - الدرجة تلقائية (مجموع الفروع) ما لم يثبّت المدرس درجة يدوية.
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
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _manualMarksController = TextEditingController();
  final FocusNode _promptFocus = FocusNode();
  int? _promptQuestionIndex;
  int? _marksQuestionIndex;

  @override
  void dispose() {
    _promptController.dispose();
    _manualMarksController.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  bool _validate(BuildContext context, ExamWizardController controller) {
    final question = controller.currentQuestion;
    if (!question.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب نص السؤال أو محتوى فرع واحد على الأقل قبل المتابعة.')),
      );
      return false;
    }
    if (question.marks <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدّد درجة فرع واحد على الأقل لهذا السؤال.')),
      );
      return false;
    }
    return true;
  }

  void _syncPromptField(ExamWizardController controller, int questionIndex) {
    if (_promptQuestionIndex != questionIndex) {
      _promptQuestionIndex = questionIndex;
      _promptController.text = controller.questions[questionIndex].prompt;
    } else if (!_promptFocus.hasFocus &&
        _promptController.text != controller.questions[questionIndex].prompt) {
      // مزامنة خارجية (تراجع/نقل) فقط — لا نسرق نص المستخدم أثناء الكتابة.
      _promptController.text = controller.questions[questionIndex].prompt;
    }
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _promptController,
              focusNode: _promptFocus,
              maxLines: null,
              minLines: 2,
              decoration: InputDecoration(
                labelText: layout.isLtr
                    ? 'Question text / instructions (optional)'
                    : 'نص السؤال / التعليمات (اختياري)',
                hintText: layout.isLtr
                    ? 'e.g. Answer two branches only:'
                    : 'مثال: أجب عن فرعين فقط:',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (value) => controller.updateQuestionPrompt(questionIndex, value),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: LtrNumericField(
                    controller: _manualMarksController,
                    hintText: 'درجة يدوية (فارغ = تلقائي)',
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
                      ? 'الدرجة محسوبة تلقائياً من الفروع'
                      : 'درجة يدوية ثابتة — امسح الحقل للعودة للتلقائي',
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
            if (sections.isNotEmpty) ...<Widget>[
              DropdownButtonFormField<String>(
                value: sections.contains(question.category) ? question.category : '',
                decoration: const InputDecoration(
                  labelText: 'القسم الوزاري (اختياري)',
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
            for (var index = 0; index < question.branches.length; index++)
              BranchEditorCard(
                key: ValueKey<String>('branch-editor-${question.branches[index].id}'),
                label: layout.branchLabel(index),
                branch: question.branches[index],
                onChanged: (branch) {
                  final ref = BranchRef(questionIndex: questionIndex, branchIndex: index);
                  controller.updateBranchContent(ref, branch.content);
                  controller.updateBranchMarks(ref, branch.marks);
                },
                onRemove: question.branches.length > 1
                    ? () => controller.removeBranch(
                          BranchRef(questionIndex: questionIndex, branchIndex: index),
                        )
                    : null,
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
                'درجة $questionLabel: ${layout.formatNumber(question.marks)} ${layout.marksUnit}'
                '  |  مجموع النموذج: ${layout.formatNumber(controller.document.totalMarks)} '
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
