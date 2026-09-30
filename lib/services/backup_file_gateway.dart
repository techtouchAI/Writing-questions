import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ملف اختاره المدرس من جهازه (نسخة احتياطية) باسمه وبايتاته الخام.
class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  /// نص الملف بترميز UTF-8 (ملفات النسخ الاحتياطية JSON نصية)؛ البايتات
  /// التالفة تُستبدل بدل إسقاط القراءة كاملة.
  String get text => const Utf8Codec(allowMalformed: true).decode(bytes);
}

/// فشل عمليات ملفات النسخة الاحتياطية برسالة عربية جاهزة للعرض.
class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// واجهة اختيار/حفظ ملف النسخة الاحتياطية على النظام.
///
/// الواجهة تجريدية لتُستبدل في الاختبارات بلا قناة نظام، فيبقى منطق النسخ
/// والاستعادة قابلاً للتحقق كاملاً على أي بيئة.
abstract interface class BackupFileGateway {
  /// هل يتيح النظام اختيار/حفظ الملفات (Android عبر SAF)؟
  bool get isSupported;

  /// يفتح منتقي الملفات ويعيد الملف المختار، أو `null` إذا أُلغيت العملية.
  Future<PickedBackupFile?> pickBackupFile();

  /// يفتح نافذة حفظ ملف باسم مقترح ويعيد معرّف/مسار الملف المحفوظ، أو
  /// `null` إذا أُلغيت العملية.
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  });
}

/// التنفيذ الفعلي عبر قناة النظام (Storage Access Framework على Android).
class PlatformBackupFileGateway implements BackupFileGateway {
  PlatformBackupFileGateway({
    MethodChannel? channel,
    TargetPlatform? platform,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _platform = platform ?? defaultTargetPlatform;

  /// اسم القناة بين Dart و Android (نظيره في `MainActivity.kt`).
  static const String channelName = 'writing_questions_app/backup_files';

  final MethodChannel _channel;
  final TargetPlatform _platform;

  @override
  bool get isSupported => _platform == TargetPlatform.android;

  @override
  Future<PickedBackupFile?> pickBackupFile() async {
    if (!isSupported) {
      throw const BackupFileException(
        'اختيار ملفات النسخ الاحتياطية متاح على أجهزة Android فقط.',
      );
    }
    Object? response;
    try {
      response = await _channel.invokeMethod<Object>('pickBackupFile');
    } on PlatformException catch (error) {
      throw BackupFileException(
        error.message ?? 'تعذر قراءة ملف النسخة الاحتياطية من الجهاز.',
      );
    } on MissingPluginException {
      throw const BackupFileException(
        'تعذر الوصول إلى ملفات الجهاز في هذا الإصدار من التطبيق.',
      );
    }
    // `null` = أُلغيت العملية (رجوع بلا اختيار).
    if (response is! Map) {
      return null;
    }
    final map = Map<Object?, Object?>.from(response);
    final bytes = map['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return null;
    }
    return PickedBackupFile(
      name: map['name']?.toString() ?? '',
      bytes: bytes,
    );
  }

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    if (!isSupported) {
      throw const BackupFileException(
        'حفظ ملفات النسخ الاحتياطية متاح على أجهزة Android فقط.',
      );
    }
    try {
      return await _channel.invokeMethod<String>('saveBackupFile', <String, Object>{
        'suggestedName': suggestedName,
        'bytes': bytes,
      });
    } on PlatformException catch (error) {
      throw BackupFileException(
        error.message ?? 'تعذر حفظ ملف النسخة الاحتياطية على الجهاز.',
      );
    } on MissingPluginException {
      throw const BackupFileException(
        'تعذر الوصول إلى ملفات الجهاز في هذا الإصدار من التطبيق.',
      );
    }
  }
}
