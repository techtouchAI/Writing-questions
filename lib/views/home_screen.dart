import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exam_document.dart';
import '../providers/exam_document_provider.dart';
import '../services/docx_document_export_service.dart';
import '../services/export_file_service.dart';
import '../services/pdf_export_service.dart';
import 'widgets/pdf_preview_screen.dart';
import 'wizard/exam_wizard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// المعالج المتسلسل للورقة الامتحانية (ترويسة ← أسئلة ← معاينة وتحرير A4).
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
        title: const Text('حذف ورقة الامتحان'),
        content: Text('هل تريد حذف الورقة "${document.name}"؟'),
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
            content: const Text('تعذر حذف الورقة. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _duplicateDocument(BuildContext context, ExamDocument document) async {
    try {
      final copy = await context.read<ExamDocumentProvider>().duplicateDocument(document.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم نسخ الورقة بنجاح: "${copy.name}"')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر نسخ الورقة. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _renameDocument(BuildContext context, ExamDocument document) async {
    final controller = TextEditingController(text: document.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير اسم الورقة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم الورقة الجديد',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      await context.read<ExamDocumentProvider>().renameDocument(document.id, newName);
    }
  }

  Future<void> _exportPdfFromHome(BuildContext context, ExamDocument document) async {
    try {
      final bytes = await PdfExportService.buildExamPdfBytes(document: document);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            fileName: '${document.name}_ورقة_الامتحان.pdf',
          ),
        ),
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('Home PDF export failed', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر إنشاء ملف الـ PDF. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _exportWordFromHome(BuildContext context, ExamDocument document) async {
    try {
      final file = await DocxDocumentExportService.exportDocumentToDocx(
        document: document,
        isTeacherVersion: false,
      );
      await DocxDocumentExportService.shareDocxFile(file);
    } catch (error, stackTrace) {
      ExportFileService.logError('Home Word export failed', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر إنشاء ملف الـ Word. حاول مرة أخرى.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documentProvider = context.watch<ExamDocumentProvider>();
    final isLoading = documentProvider.isLoading;
    final message =
        documentProvider.errorMessage ?? documentProvider.recoveryMessage;
    final hasError = documentProvider.errorMessage != null;

    final documents = documentProvider.documents;
    final lastDocument = documents.isNotEmpty ? documents.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('صانع ومحرر الأسئلة'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExamWizard(context),
        icon: const Icon(Icons.add),
        label: const Text('إنشاء ورقة جديدة'),
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
                    documentCount: documents.length,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'الإجراءات السريعة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildNewExamBanner(context),
                  if (lastDocument != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _buildResumeDraftBanner(context, lastDocument),
                  ],
                  const SizedBox(height: 24),
                  if (documents.isEmpty)
                    _buildEmptyDocumentsCard(context)
                  else ...<Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          'أوراقي الامتحانية',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${documents.length} ورقة',
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: documents.length,
                      itemBuilder: (context, index) => _buildDocumentTile(
                        context,
                        documents[index],
                      ),
                    ),
                  ],
                  const SizedBox(height: 80),
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
            'محرر أوراق الأسئلة والامتحانات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'صمم الترويسة والأسئلة بفروعها ونقاطها بحرية تامة، وحرر الورقة بصرياً كما ستطبع، ثم صدّرها كملف PDF أو Word جاهز للطباعة.',
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

  /// بطاقة إنشاء ورقة أسئلة جديدة.
  Widget _buildNewExamBanner(BuildContext context) {
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
          child: const Icon(Icons.post_add, color: Colors.white),
        ),
        title: const Text(
          'إنشاء ورقة أسئلة جديدة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: const Text(
          'ترويسة كاملة ← أسئلة بفروعها ونقاطها ← معاينة A4 ومحرر بصري ← تصدير PDF / Word',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
      ),
    );
  }

  /// بطاقة متابعة العمل على آخر ورقة مفتوحة أو قيد العمل.
  Widget _buildResumeDraftBanner(BuildContext context, ExamDocument document) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: () async {
          await _openExamWizard(context, document);
        },
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.history_edu, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(
          'متابعة العمل: ${document.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'آخر تعديل ${_formatDate(document.updatedAt)} • ${document.questions.length} أسئلة',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => _openExamWizard(context, document),
          child: const Text('متابعة'),
        ),
      ),
    );
  }

  Widget _buildEmptyDocumentsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.article_outlined, size: 44, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            'لم تنشئ أي ورقة امتحانية بعد.',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            'اضغط على "إنشاء ورقة أسئلة جديدة" لبدء كتابة أول ورقة امتحان.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(BuildContext context, ExamDocument document) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.description, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '📄 ${document.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '📅 ${_formatDate(document.updatedAt)}  •  ${document.questions.length} أسئلة  •  ${_formatMarks(document.totalMarks)} درجة  •  ${document.header.subject}',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'خيارات الورقة',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        await _openExamWizard(context, document);
                        break;
                      case 'duplicate':
                        await _duplicateDocument(context, document);
                        break;
                      case 'rename':
                        await _renameDocument(context, document);
                        break;
                      case 'delete':
                        await _confirmDeleteDocument(context, document);
                        break;
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('فتح وتعديل'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'duplicate',
                      child: ListTile(
                        leading: Icon(Icons.copy_outlined),
                        title: Text('نسخ الورقة'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('تغيير الاسم'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('حذف الورقة', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => _openExamWizard(context, document),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('تعديل / فتح'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportPdfFromHome(context, document),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('PDF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportWordFromHome(context, document),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Word'),
                ),
              ],
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

  String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}
