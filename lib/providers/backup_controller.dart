import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_backup.dart';
import '../services/app_info_service.dart';
import '../services/backup_file_gateway.dart';
import '../services/backup_service.dart';
import '../services/export_file_service.dart';
import '../services/storage_service.dart';
import 'exam_document_provider.dart';

/// نسخة احتياطية مقروءة من ملف، جاهزة للعرض في نافذة التأكيد قبل التطبيق.
class BackupPreview {
  const BackupPreview({required this.backup, required this.sourceName});

  final AppBackup backup;

  /// اسم الملف المختار (فارغ إن لم يوفّره النظام).
  final String sourceName;
}

/// حصيلة الاستعادة بعد تطبيقها فعلياً على المكتبة.
class BackupRestoreOutcome {
  const BackupRestoreOutcome({
    required this.added,
    required this.updated,
    required this.kept,
    required this.total,
  });

  final int added;
  final int updated;
  final int kept;
  final int total;
}

/// متحكم النسخ الاحتياطي والاستعادة: يربط المنطق الخالص ([BackupService])
/// بنقل الملفات ([BackupFileGateway]) وتحديث المكتبة
/// ([ExamDocumentProvider]).
///
/// - **مصدر الحقيقة** للمكتبة يبقى [ExamDocumentProvider]، والاستعادة تمرّ
///   من [ExamDocumentProvider.replaceDocuments] بحفظ ذري وتراجع كامل.
/// - لا ترمي هذه العمليات إلى الواجهة: كل فشل يُسجَّل في [errorMessage]
///   ورسالة النجاح في [statusMessage]، وتُعيد الدوال `false`/`null` بدل
///   استثناء — فتبقى شاشة الإعدادات بسيطة وآمنة.
class BackupController extends ChangeNotifier {
  BackupController({
    required ExamDocumentProvider documentsProvider,
    BackupService service = const BackupService(),
    BackupFileGateway? fileGateway,
    AppInfoService? appInfoService,
    StorageService? storageService,
  })  : _documentsProvider = documentsProvider,
        _service = service,
        _fileGateway = fileGateway ?? PlatformBackupFileGateway(),
        _appInfoService = appInfoService ?? PlatformAppInfoService(),
        _storageService = storageService ?? StorageService();

  final ExamDocumentProvider _documentsProvider;
  final BackupService _service;
  final BackupFileGateway _fileGateway;
  final AppInfoService _appInfoService;
  final StorageService _storageService;

  bool _isBusy = false;
  BackupMetadata? _lastBackup;
  String? _statusMessage;
  String? _errorMessage;
  String _appVersion = '';

  /// هل يجري إنشاء/قراءة/استعادة نسخة الآن؟ (تُعطَّل الأزرار أثناءها)
  bool get isBusy => _isBusy;

  /// آخر نسخة احتياطية أُنشئت من هذا الجهاز (`null` = لا توجد).
  BackupMetadata? get lastBackup => _lastBackup;

  /// رسالة نجاح مصاغة للعرض (تُمسح بـ[clearMessages]).
  String? get statusMessage => _statusMessage;

  /// رسالة فشل مصاغة للعرض (تُمسح بـ[clearMessages]).
  String? get errorMessage => _errorMessage;

  /// إصدار التطبيق المعروض (فارغ إن تعذّرت قراءته).
  String get appVersion => _appVersion;

  /// هل يستطيع النظام اختيار/حفظ الملفات؟ (Android عبر SAF)
  bool get isFileAccessSupported => _fileGateway.isSupported;

  /// عدد أوراق المكتبة الحالية (يُعرض في «معلومات»).
  int get documentCount => _documentsProvider.documents.length;

  /// يقرأ إصدار التطبيق وبيانات آخر نسخة عند فتح شاشة الإعدادات.
  ///
  /// صامت بالكامل: تعذّر القراءة لا يمنع عرض الشاشة ولا يظهر كخطأ.
  Future<void> load() async {
    try {
      _appVersion = await _appInfoService.appVersion();
    } catch (_) {
      _appVersion = '';
    }
    try {
      _lastBackup = await _storageService.loadLastBackupMetadata();
    } catch (_) {
      _lastBackup = null;
    }
    notifyListeners();
  }

  /// ينشئ نسخة احتياطية كاملة ويحفظها في ملف يختاره المدرس.
  ///
  /// `true` = حُفظت، `false` = أُلغيت العملية أو فشلت (انظر [errorMessage]).
  Future<bool> createBackupFile() async {
    _errorMessage = null;
    final backup = await _createBackup();
    if (backup == null) {
      return false;
    }
    _setBusy(true);
    try {
      final saved = await _fileGateway.saveBackupFile(
        suggestedName: _service.suggestedFileName(backup),
        bytes: _backupBytes(backup),
      );
      if (saved == null) {
        // أُلغيت العملية: لا تُسجَّل نسخة ولا يُعلن نجاح.
        return false;
      }
      await _rememberBackup(backup);
      return true;
    } on BackupFileException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'تعذر حفظ ملف النسخة الاحتياطية على الجهاز.';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// ينشئ نسخة احتياطية ويفتح نافذة المشاركة (Drive/واتساب/بريد...).
  Future<bool> shareBackup() async {
    _errorMessage = null;
    final backup = await _createBackup();
    if (backup == null) {
      return false;
    }
    _setBusy(true);
    try {
      // ملف مؤقت في مجلد الكاش (لا يتراكم في مجلد مستندات التطبيق).
      final file = await ExportFileService.writeExportFile(
        baseName: _service.suggestedFileStem(backup),
        extension: 'json',
        bytes: _backupBytes(backup),
        destination: await getTemporaryDirectory(),
      );
      await _rememberBackup(backup);
      await ExportFileService.shareExportFile(
        file,
        mimeType: 'application/json',
        subject: 'نسخة احتياطية — ${backup.documentCount} ورقة',
      );
      return true;
    } on BackupFileException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'تعذرت مشاركة النسخة الاحتياطية.';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// يفتح منتقي الملفات ويقرأ النسخة الاحتياطية ويعيد معاينتها (بلا أي
  /// تعديل على المكتبة). `null` = أُلغيت العملية أو فشل القراءة.
  Future<BackupPreview?> pickBackup() async {
    _errorMessage = null;
    _setBusy(true);
    try {
      final picked = await _fileGateway.pickBackupFile();
      if (picked == null) {
        return null;
      }
      final backup = _service.parseBackup(picked.text);
      if (backup.documents.isEmpty && _documentsProvider.documents.isNotEmpty) {
        _errorMessage = 'النسخة الاحتياطية المختارة لا تحوي أي ورقة.';
        return null;
      }
      return BackupPreview(backup: backup, sourceName: picked.name);
    } on BackupFileException catch (error) {
      _errorMessage = error.message;
      return null;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return null;
    } catch (_) {
      _errorMessage = 'تعذرت قراءة الملف المختار.';
      return null;
    } finally {
      _setBusy(false);
    }
  }

  /// يحسب خطة الاستعادة بالوضع المختار (تُعرض في نافذة التأكيد).
  BackupRestorePlan planRestore({
    required AppBackup backup,
    required BackupRestoreMode mode,
  }) {
    return _service.planRestore(
      current: _documentsProvider.documents,
      backup: backup,
      mode: mode,
      currentLastOpenDocumentId: _documentsProvider.lastOpenDocumentId,
    );
  }

  /// يطبّق الاستعادة فعلياً (حفظ ذري واحد) ويعيد الحصيلة، أو `null` عند الفشل
  /// — والمكتبة تعود لحالتها السابقة في تلك الحالة (تراجع كامل).
  Future<BackupRestoreOutcome?> restore({
    required AppBackup backup,
    required BackupRestoreMode mode,
  }) async {
    _errorMessage = null;
    final plan = planRestore(backup: backup, mode: mode);
    if (mode == BackupRestoreMode.replace && plan.documents.isEmpty) {
      _errorMessage = 'لا يمكن استبدال المكتبة بنسخة احتياطية فارغة.';
      return null;
    }
    _setBusy(true);
    try {
      await _documentsProvider.replaceDocuments(
        plan.documents,
        lastOpenDocumentId: plan.lastOpenDocumentId,
      );
    } catch (_) {
      _errorMessage = 'تعذر حفظ البيانات المستعادة. حاول مرة أخرى.';
      return null;
    } finally {
      _setBusy(false);
    }
    return BackupRestoreOutcome(
      added: plan.added,
      updated: plan.updated,
      kept: plan.kept,
      total: plan.total,
    );
  }

  /// يُعلن رسالة نجاح (تعرضها الشاشة ثم تمسحها بـ[clearMessages]).
  void reportSuccess(String message) {
    _statusMessage = message;
    _errorMessage = null;
    notifyListeners();
  }

  void clearMessages() {
    if (_statusMessage == null && _errorMessage == null) {
      return;
    }
    _statusMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// يبني النسخة كاملة (بالبيانات الحالية والمكتبة وإصدار التطبيق).
  Future<AppBackup?> _createBackup() async {
    _setBusy(true);
    try {
      if (_appVersion.isEmpty) {
        try {
          _appVersion = await _appInfoService.appVersion();
        } catch (_) {
          _appVersion = '';
        }
      }
      return _service.createBackup(
        documents: _documentsProvider.documents,
        lastOpenDocumentId: _documentsProvider.lastOpenDocumentId,
        appVersion: _appVersion,
      );
    } catch (_) {
      _errorMessage = 'تعذر تجهيز بيانات النسخة الاحتياطية.';
      return null;
    } finally {
      _setBusy(false);
    }
  }

  static Uint8List _backupBytes(AppBackup backup) =>
      Uint8List.fromList(utf8.encode(backup.toJson()));

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }

  Future<void> _rememberBackup(AppBackup backup) async {
    final metadata = BackupMetadata(
      createdAt: backup.createdAt,
      documentCount: backup.documentCount,
    );
    _lastBackup = metadata;
    notifyListeners();
    try {
      await _storageService.saveLastBackupMetadata(metadata);
    } catch (_) {
      // تجاهل صامت — البيانات الوصفية عرض تحسيني لا يُفقد النسخة نفسها.
    }
  }
}
