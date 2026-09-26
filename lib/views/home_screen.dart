import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exam_document.dart';
import '../providers/exam_document_provider.dart';
import '../services/docx_document_export_service.dart';
import '../services/export_file_service.dart';
import '../services/pdf_export_service.dart';
import 'widgets/pdf_preview_screen.dart';
import 'wizard/exam_wizard_screen.dart';

/// الإجراءات المتاحة على ورقة محفوظة في المكتبة.
enum _DocumentAction { open, duplicate, rename, exportPdf, exportWord, delete }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// هوية الورقة الجاري تصديرها حالياً (لمنع التصدير المزدوج).
  String? _busyDocumentId;

  /// المعالج المتسلسل للنموذج الوزاري (ترويسة ← أسئلة ← معاينة A4).
  Future<void> _openExamWizard(BuildContext context, [ExamDocument? document]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExamWizardScreen(existingDocument: document),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
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

  /// إعادة تسمية ورقة في المكتبة.
  Future<void> _renameDocument(BuildContext context, ExamDocument document) async {
    final field = TextEditingController(text: document.name);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة تسمية الورقة'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم الورقة',
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
    if (saved == null || saved.trim().isEmpty || !context.mounted) {
      return;
    }
    try {
      await context.read<ExamDocumentProvider>().renameDocument(document.id, saved);
      _showMessage('تمت إعادة التسمية.');
    } catch (_) {
      _showMessage('تعذر إعادة التسمية. حاول مرة أخرى.', isError: true);
    }
  }

  /// نسخ ورقة كاملة (بهوية جديدة) لإعادة استخدامها.
  Future<void> _duplicateDocument(
    BuildContext context,
    ExamDocument document,
  ) async {
    try {
      final copy =
          await context.read<ExamDocumentProvider>().duplicateDocument(document.id);
      _showMessage('تم إنشاء نسخة: ${copy.name}.');
    } catch (_) {
      _showMessage('تعذر نسخ الورقة. حاول مرة أخرى.', isError: true);
    }
  }

  /// تصدير PDF مباشر من المكتبة (يُحدِّث طابع الورقة الزمني).
  Future<void> _exportPdf(BuildContext context, ExamDocument document) async {
    if (_busyDocumentId != null) {
      return;
    }
    setState(() => _busyDocumentId = document.id);
    try {
      final bytes = await PdfExportService.buildDocumentPdfBytes(
        document: document,
      );
      if (!context.mounted) {
        return;
      }
      await context.read<ExamDocumentProvider>().saveDocument(document.touched());
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            title: 'معاينة ورقة الأسئلة',
            fileName: '${document.name}_ورقة_الامتحان.pdf',
          ),
        ),
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('Home PDF export failed', error, stackTrace);
      _showMessage('تعذر إنشاء ملف الـ PDF. حاول مرة أخرى.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyDocumentId = null);
      }
    }
  }

  /// تصدير Word مباشر من المكتبة (يُحدِّث طابع الورقة الزمني).
  Future<void> _exportWord(BuildContext context, ExamDocument document) async {
    if (_busyDocumentId != null) {
      return;
    }
    setState(() => _busyDocumentId = document.id);
    try {
      final file = await DocxDocumentExportService.exportDocumentToDocx(
        document: document,
      );
      if (!context.mounted) {
        return;
      }
      await context.read<ExamDocumentProvider>().saveDocument(document.touched());
      if (!context.mounted) {
        return;
      }
      _showMessage('تم إنشاء ملف Word.');
      await DocxDocumentExportService.shareDocxFile(file);
    } catch (error, stackTrace) {
      ExportFileService.logError('Home Word export failed', error, stackTrace);
      _showMessage('تعذر إنشاء ملف الـ Word. حاول مرة أخرى.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyDocumentId = null);
      }
    }
  }

  Future<void> _onDocumentAction(
    BuildContext context,
    _DocumentAction action,
    ExamDocument document,
  ) async {
    switch (action) {
      case _DocumentAction.open:
        await _openExamWizard(context, document);
      case _DocumentAction.duplicate:
        await _duplicateDocument(context, document);
      case _DocumentAction.rename:
        await _renameDocument(context, document);
      case _DocumentAction.exportPdf:
        await _exportPdf(context, document);
      case _DocumentAction.exportWord:
        await _exportWord(context, document);
      case _DocumentAction.delete:
        await _confirmDeleteDocument(context, document);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExamWizard(context),
        icon: const Icon(Icons.add),
        label: const Text('إنشاء ورقة أسئلة جديدة'),
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
                  const SizedBox(height: 12),
                  if (documentProvider.lastOpenDocument != null)
                    _buildResumeBanner(
                      context,
                      documentProvider.lastOpenDocument!,
                    ),
                  const SizedBox(height: 12),
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

  /// لافتة «متابعة العمل»: تفتح آخر ورقة حُررت (ولو مسودة حُفظت تلقائياً).
  Widget _buildResumeBanner(BuildContext context, ExamDocument document) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.secondary.withOpacity(0.4)),
      ),
      child: ListTile(
        onTap: () async {
          await _openExamWizard(context, document);
        },
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondary,
          child: const Icon(Icons.history, color: Colors.white),
        ),
        title: const Text(
          'متابعة العمل',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'آخر ورقة: ${document.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
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
    final busy = _busyDocumentId == document.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: busy
            ? const SizedBox(
                width: 40,
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : const CircleAvatar(child: Icon(Icons.article_outlined)),
        title: Text(document.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${document.questions.length} سؤال • '
          '${document.totalBranches} فرع • '
          '${_formatMarks(document.totalMarks)} درجة • '
          '${document.header.subject}\n'
          'آخر تعديل: ${_formatDate(document.updatedAt)}',
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        isThreeLine: true,
        onTap: busy
            ? null
            : () async {
                await _openExamWizard(context, document);
              },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'تصدير PDF مباشر',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed:
                  busy ? null : () => _exportPdf(context, document),
            ),
            IconButton(
              tooltip: 'تصدير Word مباشر',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.description_outlined),
              onPressed:
                  busy ? null : () => _exportWord(context, document),
            ),
            PopupMenuButton<_DocumentAction>(
              enabled: !busy,
              tooltip: 'إجراءات الورقة',
              icon: const Icon(Icons.more_vert),
              onSelected: (_DocumentAction action) =>
                  _onDocumentAction(context, action, document),
          itemBuilder: (_) => const <PopupMenuEntry<_DocumentAction>>[
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.open,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined),
                title: Text('فتح / تعديل'),
              ),
            ),
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.duplicate,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.copy_outlined),
                title: Text('نسخ الورقة'),
              ),
            ),
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.rename,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('إعادة تسمية'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.exportPdf,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('تصدير PDF'),
              ),
            ),
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.exportWord,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.description_outlined),
                title: Text('تصدير Word'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem<_DocumentAction>(
              value: _DocumentAction.delete,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('حذف الورقة', style: TextStyle(color: Colors.red)),
              ),
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

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)}';
  }
}
