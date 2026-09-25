import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exam_document.dart';
import '../providers/exam_document_provider.dart';
import 'wizard/exam_wizard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documentProvider = context.watch<ExamDocumentProvider>();
    final isLoading = documentProvider.isLoading;
    final message =
        documentProvider.errorMessage ?? documentProvider.recoveryMessage;
    final hasError = documentProvider.errorMessage != null;

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
                          onPressed: documentProvider.clearMessages,
                          child: const Text('إخفاء'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildDashboardCard(
                    context,
                    documentCount: documentProvider.documents.length,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'الإجراءات السريعة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildWizardBanner(context),
                  const SizedBox(height: 24),
                  if (documentProvider.documents.isEmpty)
                    _buildEmptyDocumentsCard(context)
                  else ...<Widget>[
                    const Text(
                      'النماذج الوزارية المحفوظة',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: documentProvider.documents.length,
                      itemBuilder: (context, index) => _buildDocumentTile(
                        context,
                        documentProvider.documents[index],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required int documentCount,
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
            'محرر أوراق الأسئلة الوزارية',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'صمم الترويسة والأسئلة بفروعها، وحرر الورقة مباشرة على معاينة A4، ثم صدّرها PDF أو Word.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              _buildStatBox('النماذج المحفوظة', '$documentCount', Icons.article),
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

  Widget _buildEmptyDocumentsCard(BuildContext context) {
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
          Icon(Icons.article_outlined, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'لم تنشئ أي نموذج وزاري بعد.',
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 4),
          Text(
            'انقر على "نموذج وزاري جديد" لبدء تصميم ورقتك.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
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

  String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}
