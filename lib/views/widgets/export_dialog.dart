import 'package:flutter/material.dart';

import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/docx_export_service.dart';
import '../../services/excel_export_service.dart';

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, this.exam, this.questions})
      : assert(exam != null || questions != null);

  final Exam? exam;
  final List<Question>? questions;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isExporting = false;
  String _statusMessage = '';

  List<Question> get _questions => widget.exam?.questions ?? widget.questions!;
  String get _exportTitle => widget.exam?.name ?? 'بنك_الأسئلة';

  Future<void> _exportToExcel() async {
    if (_isExporting) {
      return;
    }
    if (_questions.isEmpty) {
      _showError('لا توجد أسئلة لتصديرها.');
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري توليد ملف Excel (.xlsx)...';
    });
    final messenger = ScaffoldMessenger.of(context);
    var completed = false;

    try {
      final file = await ExcelExportService.exportQuestionsToExcel(
        questions: _questions,
        sheetName: _exportTitle,
        fileName: _exportTitle,
      );
      await ExcelExportService.shareExcelFile(file, subject: _exportTitle);

      if (!mounted) {
        return;
      }
      completed = true;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء ملف Excel وفتح خيارات المشاركة.')),
      );
    } catch (_) {
      if (mounted) {
        _showError('تعذر إنشاء أو مشاركة ملف Excel. حاول مرة أخرى.');
      }
    } finally {
      if (mounted && !completed) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportToDocx({required bool isTeacherVersion}) async {
    final exam = widget.exam;
    if (exam == null) {
      _showError('يتطلب تصدير Word إنشاء اختبار أو فتح اختبار محفوظ أولاً.');
      return;
    }
    if (_isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري بناء وتنسيق ملف Word (.docx)...';
    });
    final messenger = ScaffoldMessenger.of(context);
    var completed = false;

    try {
      final file = await DocxExportService.exportExamToDocx(
        exam: exam,
        isTeacherVersion: isTeacherVersion,
      );
      await DocxExportService.shareDocxFile(file, subject: exam.name);

      if (!mounted) {
        return;
      }
      completed = true;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isTeacherVersion
                ? 'تم إنشاء نموذج الإجابة بصيغة Word وفتح خيارات المشاركة.'
                : 'تم إنشاء ورقة الطالب بصيغة Word وفتح خيارات المشاركة.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        _showError('تعذر إنشاء أو مشاركة ملف Word. حاول مرة أخرى.');
      }
    } finally {
      if (mounted && !completed) {
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isExporting,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.output_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('مركز التصدير')),
          ],
        ),
        content: _isExporting
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage, textAlign: TextAlign.center),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'اختر صيغة الملف والنوع المطلوب للتصدير والمشاركة:',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _buildOptionTile(
                      icon: Icons.description,
                      iconColor: Colors.blue.shade700,
                      title: 'Word — ورقة الطالب (.docx)',
                      subtitle: 'ورقة اختبار منسقة للطباعة بدون إجابات.',
                      onTap: () => _exportToDocx(isTeacherVersion: false),
                    ),
                    const Divider(),
                    _buildOptionTile(
                      icon: Icons.check_circle_outline,
                      iconColor: Colors.green.shade700,
                      title: 'Word — نموذج الإجابة (.docx)',
                      subtitle: 'نسخة للمعلم تتضمن الحلول وتوزيع الدرجات.',
                      onTap: () => _exportToDocx(isTeacherVersion: true),
                    ),
                    const Divider(),
                    _buildOptionTile(
                      icon: Icons.table_chart,
                      iconColor: Colors.teal.shade700,
                      title: 'Excel — جدول بيانات (.xlsx)',
                      subtitle: 'جدول بالأسئلة والخيارات والحلول لمنصات التعليم.',
                      onTap: _exportToExcel,
                    ),
                  ],
                ),
              ),
        actions: <Widget>[
          if (!_isExporting)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: iconColor.withOpacity(0.12),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () async {
        await onTap();
      },
    );
  }
}
