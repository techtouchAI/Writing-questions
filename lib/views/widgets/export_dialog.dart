import 'package:flutter/material.dart';

import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/docx_export_service.dart';
import '../../services/excel_export_service.dart';
import '../../services/export_file_service.dart';

/// Dialog offering every export flavor for either a whole exam or an
/// arbitrary list of questions.
class ExportDialog extends StatefulWidget {
  const ExportDialog({
    super.key,
    this.exam,
    this.questions,
  }) : assert(exam != null || questions != null);

  final Exam? exam;
  final List<Question>? questions;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isExporting = false;
  String _statusMessage = '';

  /// Runs an export task with progress state, error handling and async-gap
  /// safety in one place.
  ///
  /// [task] returns the success message to show before closing the dialog,
  /// or null to keep the dialog open (e.g. after a validation notice).
  Future<void> _runExport({
    required String statusMessage,
    required Future<String?> Function() task,
  }) async {
    setState(() {
      _isExporting = true;
      _statusMessage = statusMessage;
    });
    try {
      final successMessage = await task();
      if (!mounted) return;
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
        Navigator.of(context).pop();
      }
    } on ExportException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (error, stackTrace) {
      ExportFileService.logError('Export failed', error, stackTrace);
      if (mounted) {
        _showError('تعذّر إكمال التصدير. تحقق من مساحة التخزين وحاول مجدداً.');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<String?> _exportToDocx({required bool isTeacherVersion}) async {
    final exam = widget.exam;
    if (exam == null) {
      _showError('لتصدير ملف Word كامل، يُرجى إنشاء أو تحديد اختبار أولاً');
      return null;
    }
    final file = await DocxExportService.exportExamToDocx(
      exam: exam,
      isTeacherVersion: isTeacherVersion,
    );
    await DocxExportService.shareDocxFile(file, subject: exam.name);
    return isTeacherVersion
        ? 'تم إنشاء نموذج إجابة المعلم بصيغة Word بنجاح!'
        : 'تم إنشاء ورقة امتحان الطالب بصيغة Word بنجاح!';
  }

  Future<String?> _exportToExcel() async {
    final questions =
        widget.exam?.questions ?? widget.questions ?? const <Question>[];
    final title = widget.exam?.name ?? 'بنك الأسئلة';
    final file = await ExcelExportService.exportQuestionsToExcel(
      questions: questions,
      sheetName: title,
      fileBaseName: title,
    );
    await ExcelExportService.shareExcelFile(file, subject: title);
    return 'تم إنشاء ملف Excel بنجاح! جاري فتح خيارات المشاركة...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.output_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('مركز تصدير الاختبار والأسئلة'),
        ],
      ),
      content: _isExporting
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_statusMessage),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'اختر صيغة الملف والنوع المطلوب للتصدير والمشاركة:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _buildOptionTile(
                  icon: Icons.description,
                  iconColor: Colors.blue.shade700,
                  title: 'تصدير Word - ورقة الطالب (.docx)',
                  subtitle: 'ورقة اختبار رسمية منسقة للطباعة بدون إجابات',
                  onTap: () => _runExport(
                    statusMessage: 'جاري بناء وتنسيق ملف Word (.docx)...',
                    task: () => _exportToDocx(isTeacherVersion: false),
                  ),
                ),
                const Divider(),
                _buildOptionTile(
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green.shade700,
                  title: 'تصدير Word - نموذج الإجابة (.docx)',
                  subtitle: 'نسخة للمعلم تتضمن الحلول الصحيحة وتوزيع الدرجات',
                  onTap: () => _runExport(
                    statusMessage: 'جاري بناء وتنسيق ملف Word (.docx)...',
                    task: () => _exportToDocx(isTeacherVersion: true),
                  ),
                ),
                const Divider(),
                _buildOptionTile(
                  icon: Icons.table_chart,
                  iconColor: Colors.teal.shade700,
                  title: 'تصدير Excel جدول بيانات (.xlsx)',
                  subtitle: 'جدول بجميع الأسئلة والخيارات والحلول لمنصات التعليم',
                  onTap: () => _runExport(
                    statusMessage: 'جاري توليد ملف Excel (.xlsx)...',
                    task: _exportToExcel,
                  ),
                ),
              ],
            ),
      actions: [
        if (!_isExporting)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withOpacity(0.12),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
