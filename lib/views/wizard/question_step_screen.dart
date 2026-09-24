import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam_document.dart';
import '../../providers/exam_wizard_controller.dart';
import 'branch_editor_card.dart';

/// الخطوة 2 من المعالج: إعداد سؤال واحد بفروعه (أ، ب، ج...).
///
/// - العنوان ديناميكي: «إعداد السؤال الأول» ثم «الثاني»...
/// - يبدأ بفرع (أ) افتراضياً؛ [إضافة فرع جديد] يضيف (ب) ثم (ج) بنفس الأدوات.
/// - [التالي] يحفظ السؤال ويفتح سؤالاً جديداً فارغاً، و[إنهاء وعرض النموذج]
///   ينتقل إلى محرك المعاينة A4.
class QuestionStepScreen extends StatelessWidget {
  const QuestionStepScreen({
    super.key,
    required this.onFinish,
    required this.onBack,
  });

  final VoidCallback onFinish;
  final VoidCallback onBack;

  bool _validate(BuildContext context, ExamWizardController controller) {
    final question = controller.currentQuestion;
    final hasContent = question.branches.any((branch) => !branch.content.isEmpty);
    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب محتوى فرع واحد على الأقل قبل المتابعة.')),
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final layout = controller.layout;
    final questionIndex = controller.currentQuestionIndex;
    final question = controller.currentQuestion;
    final colorScheme = Theme.of(context).colorScheme;
    final sections = layout.sections;
    final questionLabel = layout.questionLabel(question.questionNumber);

    return Scaffold(
      appBar: AppBar(
        title: Text(layout.isLtr ? 'Set up $questionLabel' : 'إعداد $questionLabel'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: questionIndex == 0 ? 'العودة للترويسة' : 'السؤال السابق',
          onPressed: questionIndex == 0 ? onBack : controller.goToPreviousQuestion,
        ),
        actions: <Widget>[
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
                      ? 'التالي: ${layout.questionLabel(question.questionNumber + 1)}'
                      : 'التالي: سؤال جديد',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (_validate(context, controller)) {
                    onFinish();
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
    final layout = controller.layout;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final selected = index == controller.currentQuestionIndex;
          return ChoiceChip(
            label: Text(layout.questionLabel(controller.questions[index].questionNumber)),
            selected: selected,
            onSelected: (_) => controller.openQuestion(index),
          );
        },
      ),
    );
  }
}
