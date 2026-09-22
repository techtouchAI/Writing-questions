import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/excel_export_service.dart';
import '../../services/export_file_service.dart';
import '../../services/pdf_export_service.dart';
import 'pdf_preview_screen.dart';

/// مركز التصدير: الاختبارات الرسمية تُصدَّر PDF حصراً (معاينة قبل الطباعة)،
/// وبنك الأسئلة يحتفظ بتصدير Excel للبيانات.
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

  List<Question>? get _questions =>
      widget.exam != null ? widget.exam!.questions : widget.questions;
  String get _exportTitle => widget.exam?.name ?? 'بنك_الأسئلة';

  Future<void> _previewExamPdf({required bool isTeacherVersion}) async {
    final exam = widget.exam;
    if (exam == null) {
      _showError('يتطلب التصدير إنشاء اختبار أو فتح اختبار محفوظ أولاً.');
      return;
    }
    if (_isExporting) {
      return;
    }
    if (exam.questions.isEmpty) {
      _showError('لا توجد أسئلة في الاختبار لتصديرها.');
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري بناء ورقة الـ PDF بصفحة A4 واحدة...';
    });

    try {
      final Uint8List bytes = await PdfExportService.buildExamPdfBytes(
        exam: exam,
        isTeacherVersion: isTeacherVersion,
      );

      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            title: isTeacherVersion ? 'معاينة نموذج الإجابة' : 'معاينة ورقة الطالب',
            fileName: isTeacherVersion
                ? '${exam.name}_نموذج_الإجابة.pdf'
                : '${exam.name}_ورقة_الامتحان.pdf',
          ),
        ),
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('PDF export failed', error, stackTrace);
      if (mounted) {
        _showError('تعذر إنشاء معاينة الـ PDF. حاول مرة أخرى.');
      }
    } finally {
      // عند العودة من المعاينة يبقى مركز التصدير مفتوحاً لاختيار نسخة أخرى.
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_isExporting) {
      return;
    }
    final questions = _questions;
    if (questions == null || questions.isEmpty) {
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
        questions: questions,
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
    } on ExportException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } catch (error, stackTrace) {
      ExportFileService.logError('Excel export failed', error, stackTrace);
      if (mounted) {
        _showError('تعذر إنشاء أو مشاركة ملف Excel. حاول مرة أخرى.');
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
    final isExam = widget.exam != null;

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
                    Text(
                      isExam
                          ? 'اختر نسخة ورقة الاختبار؛ تُفتح معاينة PDF مباشرة قبل الطباعة أو المشاركة.'
                          : 'اختر صيغة الملف لتصدير بنك الأسئلة ومشاركته:',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (isExam) ...<Widget>[
                      _buildOptionTile(
                        icon: Icons.picture_as_pdf,
                        iconColor: Colors.blue.shade700,
                        title: 'PDF — ورقة الطالب',
                        subtitle: 'معاينة A4 بصفحة واحدة ثم طباعتها أو مشاركتها.',
                        onTap: () => _previewExamPdf(isTeacherVersion: false),
                      ),
                      const Divider(),
                      _buildOptionTile(
                        icon: Icons.fact_check_outlined,
                        iconColor: Colors.green.shade700,
                        title: 'PDF — نموذج الإجابة للمعلم',
                        subtitle: 'نسخة مع الحلول وتوزيع الدرجات للمراجعة.',
                        onTap: () => _previewExamPdf(isTeacherVersion: true),
                      ),
                      const Divider(height: 20),
                      Text(
                        'تُجمَّد تصديرات Word وExcel للامتحانات الرسمية '
                        'حفاظاً على التنسيق الوزاري الثابت — الناتج PDF فقط.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ] else
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
