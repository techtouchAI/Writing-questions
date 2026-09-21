import 'package:flutter/material.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/docx_export_service.dart';
import '../../services/excel_export_service.dart';

class ExportDialog extends StatefulWidget {
  final Exam? exam;
  final List<Question>? questions;

  const ExportDialog({
    super.key,
    this.exam,
    this.questions,
  }) : assert(exam != null || questions != null);

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isExporting = false;
  String _statusMessage = '';

  Future<void> _exportToExcel() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري توليد ملف Excel (.xlsx)...';
    });

    try {
      final list = widget.exam != null ? widget.exam!.questions : widget.questions!;
      final title = widget.exam?.name ?? 'بنك_الأسئلة';
      final file = await ExcelExportService.exportQuestionsToExcel(
        questions: list,
        sheetName: title,
        fileName: '${title.replaceAll(' ', '_')}.xlsx',
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء ملف Excel بنجاح! جاري فتح خيارات المشاركة...')),
        );
      }
      await ExcelExportService.shareExcelFile(file, subject: title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التصدير: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportToDocx({required bool isTeacherVersion}) async {
    if (widget.exam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لتصدير ملف Word كامل، يُرجى إنشاء أو تحديد اختبار أولاً')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري بناء وتنسيق ملف Word (.docx)...';
    });

    try {
      final file = await DocxExportService.exportExamToDocx(
        exam: widget.exam!,
        isTeacherVersion: isTeacherVersion,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isTeacherVersion
                ? 'تم إنشاء نموذج إجابة المعلم بصيغة Word بنجاح!'
                : 'تم إنشاء ورقة امتحان الطالب بصيغة Word بنجاح!'),
          ),
        );
      }
      await DocxExportService.shareDocxFile(file, subject: widget.exam!.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التصدير: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
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
                  onTap: () => _exportToDocx(isTeacherVersion: false),
                ),
                const Divider(),
                _buildOptionTile(
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green.shade700,
                  title: 'تصدير Word - نموذج الإجابة (.docx)',
                  subtitle: 'نسخة للمعلم تتضمن الحلول الصحيحة وتوزيع الدرجات',
                  onTap: () => _exportToDocx(isTeacherVersion: true),
                ),
                const Divider(),
                _buildOptionTile(
                  icon: Icons.table_chart,
                  iconColor: Colors.teal.shade700,
                  title: 'تصدير Excel جدول بيانات (.xlsx)',
                  subtitle: 'جدول بجميع الأسئلة والخيارات والحلول لمنصات التعليم',
                  onTap: _exportToExcel,
                ),
              ],
            ),
      actions: [
        if (!_isExporting)
          TextButton(
            onPressed: () => Navigator.pop(context),
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
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
