import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/backup_controller.dart';
import '../services/backup_service.dart';

/// شاشة الإعدادات: النسخ الاحتياطي والاستعادة، ومعلومات التطبيق.
///
/// النسخة الاحتياطية ملف واحد يحوي كل الأوراق المحفوظة (بأسئلتها وفروعها
/// ونقاطها وإجاباتها وصورها ومعادلاتها وترويستها وإعداداتها) مع حالة الجلسة،
/// ويُقرأ الملف عند الاستعادة بتحقق صارم ثم يُعرض ملخّصه (**كم ورقة ستُضاف
/// وكم ستُحدَّث**) قبل أي تعديل — فالمدرس يرى الأثر قبل التأكيد.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // قراءة إصدار التطبيق وبيانات آخر نسخة بعد بناء الشاشة (لا أثناءها).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BackupController>().load();
      }
    });
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

  /// يعرض أي رسالة سجّلها المتحكم بعد عملية (نجاح/فشل) ثم يمسحها.
  void _flushControllerMessages() {
    final controller = context.read<BackupController>();
    final error = controller.errorMessage;
    if (error != null) {
      controller.clearMessages();
      _showMessage(error, isError: true);
      return;
    }
    final status = controller.statusMessage;
    if (status != null) {
      controller.clearMessages();
      _showMessage(status);
    }
  }

  // ============================ النسخ الاحتياطي ============================

  /// إنشاء نسخة: يختار المدرس بين الحفظ في ملف أو المشاركة.
  Future<void> _createBackup() async {
    final choice = await showModalBottomSheet<_BackupDestination>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'أين تريد حفظ النسخة الاحتياطية؟',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('حفظ في ملف على الجهاز'),
              subtitle: const Text('تختار المجلد والاسم من ملفات الجهاز'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_BackupDestination.file),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('مشاركة النسخة'),
              subtitle: const Text('إلى Drive أو واتساب أو البريد...'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_BackupDestination.share),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }

    final controller = context.read<BackupController>();
    final saved = switch (choice) {
      _BackupDestination.file => await controller.createBackupFile(),
      _BackupDestination.share => await controller.shareBackup(),
    };
    if (!mounted) {
      return;
    }
    if (saved) {
      controller.reportSuccess(
        choice == _BackupDestination.file
            ? 'تم حفظ النسخة الاحتياطية كاملة.'
            : 'تم تجهيز النسخة الاحتياطية للمشاركة.',
      );
    }
    _flushControllerMessages();
  }

  /// استعادة: يقرأ الملف ويعرض ملخّصه وخطة الدمج قبل أي تعديل.
  Future<void> _restoreFromFile() async {
    final controller = context.read<BackupController>();
    final preview = await controller.pickBackup();
    if (!mounted) {
      return;
    }
    if (preview == null) {
      _flushControllerMessages();
      return;
    }

    final request = await _showRestoreDialog(preview);
    if (request == null || !mounted) {
      return;
    }

    final outcome = await controller.restore(
      backup: preview.backup,
      mode: request,
    );
    if (!mounted) {
      return;
    }
    if (outcome == null) {
      _flushControllerMessages();
      return;
    }
    controller.reportSuccess(
      'تمت الاستعادة: أُضيفت ${outcome.added} ورقة، '
      'وحُدّثت ${outcome.updated}، وبقيت ${outcome.kept}، '
      'فصار في المكتبة ${outcome.total} ورقة.',
    );
    _flushControllerMessages();
  }

  /// نافذة تأكيد تعرض محتوى الملف وأثره على المكتبة قبل التطبيق.
  Future<BackupRestoreMode?> _showRestoreDialog(BackupPreview preview) {
    final controller = context.read<BackupController>();
    var mode = BackupRestoreMode.merge;

    return showDialog<BackupRestoreMode>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final plan = controller.planRestore(backup: preview.backup, mode: mode);
          return AlertDialog(
            title: const Text('استعادة نسخة احتياطية'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (preview.sourceName.isNotEmpty)
                    Text(
                      'الملف: ${preview.sourceName}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'أُنشئت في: ${_formatDateTime(preview.backup.createdAt)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    'تحوي: ${preview.backup.documentCount} ورقة، '
                    'و${preview.backup.totalQuestions} سؤالاً.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (preview.backup.appVersion.isNotEmpty)
                    Text(
                      'أنشأها إصدار التطبيق: ${preview.backup.appVersion}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  const Divider(height: 20),
                  for (final option in BackupRestoreMode.values)
                    RadioListTile<BackupRestoreMode>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: option,
                      groupValue: mode,
                      onChanged: (value) =>
                          setDialogState(() => mode = value ?? mode),
                      title: Text(
                        option.arabicLabel,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        option.arabicDescription,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'الأثر على المكتبة: تُضاف ${plan.added} ورقة، '
                    'وتُحدَّث ${plan.updated}'
                    '${mode == BackupRestoreMode.replace ? ' (استبدال كامل)' : '، وتبقى ${plan.kept}'}'
                    '، فتصير المكتبة ${plan.total} ورقة.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  if (plan.changesNothing && mode == BackupRestoreMode.merge)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'لا جديد في هذه النسخة: كل أوراقها موجودة ومحدَّثة في مكتبتك.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(mode),
                child: const Text('استعادة'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================ البناء ============================

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackupController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        bottom: controller.isBusy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _sectionTitle('النسخ الاحتياطي والاستعادة'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.backup_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'نسخة كاملة من مكتبة الأوراق',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ملف واحد يحوي كل الأوراق المحفوظة: الأسئلة والفروع والنقاط '
                    'والإجابات والصور والمعادلات والترويسة وإعدادات الورقة، مع '
                    'حالة الجلسة. يمكنك حفظه على الجهاز أو مشاركته، ثم استعادته '
                    'على أي جهاز يشغّل التطبيق.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _lastBackupRow(controller),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: controller.isBusy ? null : _createBackup,
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('إنشاء نسخة احتياطية'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy ? null : _restoreFromFile,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('استعادة من ملف'),
                      ),
                    ],
                  ),
                  if (!controller.isFileAccessSupported)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'اختيار وحفظ الملفات متاح على أجهزة Android.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('معلومات'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('إصدار التطبيق', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    controller.appVersion.isEmpty ? '—' : controller.appVersion,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('أوراق المكتبة', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${controller.documentCount} ورقة محفوظة',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('الخصوصية', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    'تبقى الأوراق والنسخ الاحتياطية على جهازك؛ لا يرسل التطبيق '
                    'أي بيانات إلى خادم، ولا تُشارك النسخة إلا عندما تختار ذلك.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _lastBackupRow(BackupController controller) {
    final last = controller.lastBackup;
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            last == null ? Icons.history_toggle_off : Icons.history,
            size: 18,
            color: color.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              last == null
                  ? 'لم تُنشأ نسخة احتياطية بعد على هذا الجهاز.'
                  : 'آخر نسخة: ${_formatDateTime(last.createdAt)} — '
                      '${last.documentCount} ورقة.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// أين تُحفظ النسخة الاحتياطية.
enum _BackupDestination { file, share }

/// صيغة تاريخ/وقت موحّدة لشاشة الإعدادات (بلا اعتماد على حزم إضافية).
String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}
