import 'package:flutter/material.dart';
import '../../models/main_question.dart';
import '../../models/question_option.dart';
import '../../models/question_type.dart';
import '../../models/difficulty.dart';

class QuestionCard extends StatelessWidget {
  final MainQuestion question;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;

  const QuestionCard({
    super.key,
    required this.question,
    this.onEdit,
    this.onDelete,
    this.isSelected = false,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color difficultyColor;
    switch (question.difficulty) {
      case Difficulty.easy:
        difficultyColor = Colors.green.shade700;
        break;
      case Difficulty.medium:
        difficultyColor = Colors.orange.shade800;
        break;
      case Difficulty.hard:
        difficultyColor = Colors.red.shade700;
        break;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onSelectChanged != null)
                  Checkbox(
                    value: isSelected,
                    onChanged: onSelectChanged,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildBadge(question.type.arabicLabel, theme.colorScheme.primaryContainer, theme.colorScheme.onPrimaryContainer),
                          _buildBadge(question.difficulty.arabicLabel, difficultyColor.withOpacity(0.15), difficultyColor),
                          _buildBadge('${question.marks} درجة', Colors.blueGrey.shade100, Colors.blueGrey.shade900),
                          if (question.subject.isNotEmpty)
                            _buildBadge(question.subject, Colors.teal.shade50, Colors.teal.shade800),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        question.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') onEdit?.call();
                      if (val == 'delete') onDelete?.call();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('تعديل'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('حذف'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (question.type == QuestionType.multipleChoice)
              ...question.options.map(
                (opt) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      Icon(
                        opt.isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: opt.isCorrect ? Colors.green.shade700 : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          opt.text,
                          style: TextStyle(
                            color: opt.isCorrect ? Colors.green.shade900 : Colors.black87,
                            fontWeight: opt.isCorrect ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (question.type == QuestionType.trueFalse)
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الإجابة الصحيحة: ${question.options.firstWhere((o) => o.isCorrect, orElse: () => QuestionOption(text: "غير محدد")).text}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                    ),
                  ),
                ],
              ),
            if (question.type == QuestionType.fillInTheBlank || question.type == QuestionType.essay)
              if (question.modelAnswer.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'الإجابة النموذجية: ${question.modelAnswer}',
                          style: TextStyle(fontSize: 13, color: Colors.brown.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
