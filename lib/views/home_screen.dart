import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exam.dart';
import '../models/exam_document.dart';
import '../providers/exam_document_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/question_provider.dart';
import 'exam_builder_screen.dart';
import 'question_bank_screen.dart';
import 'question_editor_screen.dart';
import 'widgets/export_dialog.dart';
import 'wizard/exam_wizard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openQuestionEditor(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const QuestionEditorScreen()),
    );
  }

  Future<void> _openQuestionBank(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const QuestionBankScreen()),
    );
  }

  Future<void> _openExamBuilder(BuildContext context, [Exam? exam]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExamBuilderScreen(existingExam: exam),
      ),
    );
  }

  /// المعالج المتسلسل للنموذج الوزاري (ترويسة ← أسئلة ← معاينة A4).
  Future<void> _openExamWizard(BuildContext context, [ExamDocument? document]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExamWizardScreen(existingDocument: document),
      ),
    );
  }

  Future<void> _confirmDeleteDocument(BuildContext context, ExamDocument document) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف النموذج الوزاري'),
        content: Text('هل تريد حذف النموذج "${document.name}"؟'),
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
    if (shouldDelete != true || !context.mounted) {
      return;
    }
    try {
      await context.read<ExamDocumentProvider>().deleteDocument(document.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر حذف النموذج. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showQuickExport(BuildContext context) async {
    final questions = context.read<QuestionProvider>().questions;
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أسئلة لتصديرها.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => ExportDialog(questions: questions),
    );
  }

  Future<void> _showExamExport(BuildContext context, Exam exam) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ExportDialog(exam: exam),
    );
  }

  Future<void> _confirmDeleteExam(BuildContext context, Exam exam) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الاختبار'),
        content: Text('هل تريد حذف اختبار "${exam.name}"؟'),
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

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    try {
      await context.read<ExamProvider>().deleteExam(exam.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الاختبار.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر حذف الاختبار. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questionProvider = context.watch<QuestionProvider>();
    final examProvider = context.watch<ExamProvider>();
    final documentProvider = context.watch<ExamDocumentProvider>();
    final isLoading = questionProvider.isLoading ||
        examProvider.isLoading ||
        documentProvider.isLoading;
    final message = questionProvider.errorMessage ??
        examProvider.errorMessage ??
        documentProvider.errorMessage ??
        questionProvider.recoveryMessage ??
        examProvider.recoveryMessage ??
        documentProvider.recoveryMessage;
    final hasError = questionProvider.errorMessage != null ||
        examProvider.errorMessage != null ||
        documentProvider.errorMessage != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('صانع ومحرر الأسئلة'),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (message != null) ...<Widget>[
                    MaterialBanner(
                      content: Text(message),
                      backgroundColor: hasError
                          ? theme.colorScheme.errorContainer
                          : theme.colorScheme.secondaryContainer,
                      actions: <Widget>[
                        TextButton(
                          onPressed: () {
                            questionProvider.clearMessages();
                            examProvider.clearMessages();
                            documentProvider.clearMessages();
                          },
                          child: const Text('إخفاء'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildDashboardCard(
                    context,
                    questionCount: questionProvider.questions.length,
                    examCount: examProvider.exams.length,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'الإجراءات السريعة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildWizardBanner(context),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: <Widget>[
                      _buildActionCard(
                        title: 'إضافة سؤال جديد',
                        subtitle: 'خيارات، صح/خطأ، مقالي',
                        icon: Icons.add_circle_outline,
                        color: Colors.blue.shade700,
                        onTap: () async {
                          await _openQuestionEditor(context);
                        },
                      ),
                      _buildActionCard(
                        title: 'بنك الأسئلة',
                        subtitle: 'استعراض وفلترة وتعديل',
                        icon: Icons.inventory_2_outlined,
                        color: Colors.indigo.shade700,
                        onTap: () async {
                          await _openQuestionBank(context);
                        },
                      ),
                      _buildActionCard(
                        title: 'بناء اختبار جديد',
                        subtitle: 'تخصيص الترويسة والأسئلة',
                        icon: Icons.post_add,
                        color: Colors.teal.shade700,
                        onTap: () async {
                          await _openExamBuilder(context);
                        },
                      ),
                      _buildActionCard(
                        title: 'تصدير سريع',
                        subtitle: 'تصدير Excel لبنك الأسئلة',
                        icon: Icons.file_download_outlined,
                        color: Colors.deepOrange.shade700,
                        onTap: () async {
                          await _showQuickExport(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (documentProvider.documents.isNotEmpty) ...<Widget>[
                    const Text(
                      'النماذج الوزارية المحفوظة',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: documentProvider.documents.length,
                      itemBuilder: (context, index) =>
                          _buildDocumentTile(context, documentProvider.documents[index]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'الاختبارات المحفوظة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _openExamBuilder(context);
                        },
                        child: const Text('اختبار جديد'),
                      ),
                    ],
                  ),
                  if (examProvider.exams.isEmpty)
                    _buildEmptyExamsCard()
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: examProvider.exams.length,
                      itemBuilder: (context, index) {
                        final exam = examProvider.exams[index];
                        return _buildExamTile(context, exam);
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required int questionCount,
    required int examCount,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'لوحة التحكم وإدارة الاختبارات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'أنشئ أسئلتك، صمم نماذج الاختبارات، وصدّرها كملفات PDF أو Excel.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              _buildStatBox('الأسئلة بالبنك', '$questionCount', Icons.quiz),
              const SizedBox(width: 12),
              _buildStatBox('الاختبارات الجاهزة', '$examCount', Icons.assignment),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة الدخول إلى المعالج المتسلسل للنموذج الوزاري.
  Widget _buildWizardBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () async {
          await _openExamWizard(context);
        },
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary,
          child: const Icon(Icons.auto_awesome_motion, color: Colors.white),
        ),
        title: const Text(
          'نموذج وزاري جديد (معالج متسلسل)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'ترويسة ← أسئلة بفروعها ← معاينة A4 متعددة الصفحات مع تحرير مباشر وسحب وإفلات',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
      ),
    );
  }

  Widget _buildDocumentTile(BuildContext context, ExamDocument document) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.article_outlined)),
        title: Text(document.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${document.questions.length} سؤال • ${_formatMarks(document.totalMarks)} درجة • '
          '${document.header.subject}',
        ),
        onTap: () async {
          await _openExamWizard(context, document);
        },
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'حذف النموذج',
          onPressed: () async {
            await _confirmDeleteDocument(context, document);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyExamsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.assignment_outlined, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'لم تقم بإنشاء اختبارات مخصصة بعد.',
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 4),
          Text(
            'انقر على "اختبار جديد" لتجميع أسئلة بنموذج موحد.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildExamTile(BuildContext context, Exam exam) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description)),
        title: Text(
          exam.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${exam.mainQuestions.length} سؤال • ${_formatMarks(exam.totalMarks)} درجة • ${exam.header.subject}',
        ),
        trailing: PopupMenuButton<_ExamAction>(
          tooltip: 'إجراءات الاختبار',
          onSelected: (action) async {
            switch (action) {
              case _ExamAction.edit:
                await _openExamBuilder(context, exam);
                break;
              case _ExamAction.export:
                await _showExamExport(context, exam);
                break;
              case _ExamAction.delete:
                await _confirmDeleteExam(context, exam);
                break;
            }
          },
          itemBuilder: (context) => const <PopupMenuEntry<_ExamAction>>[
            PopupMenuItem<_ExamAction>(
              value: _ExamAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('تعديل'),
              ),
            ),
            PopupMenuItem<_ExamAction>(
              value: _ExamAction.export,
              child: ListTile(
                leading: Icon(Icons.ios_share_outlined),
                title: Text('تصدير'),
              ),
            ),
            PopupMenuItem<_ExamAction>(
              value: _ExamAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('حذف', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String title, String count, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    count,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          await onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                radius: 18,
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}

enum _ExamAction { edit, export, delete }
