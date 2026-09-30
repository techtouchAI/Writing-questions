import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// معلومات إصدار التطبيق المعروضة في الإعدادات والمكتوبة في ترويسة النسخة
/// الاحتياطية (تشخيصياً).
abstract interface class AppInfoService {
  /// يقرأ اسم إصدار التطبيق من النظام (فارغ إن تعذّر القراءة).
  Future<String> appVersion();
}

/// التنفيذ الفعلي عبر قناة النظام (نظيرها في `MainActivity.kt`).
class PlatformAppInfoService implements AppInfoService {
  PlatformAppInfoService({
    MethodChannel? channel,
    TargetPlatform? platform,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _platform = platform ?? defaultTargetPlatform;

  static const String channelName = 'writing_questions_app/app_info';

  final MethodChannel _channel;
  final TargetPlatform _platform;

  @override
  Future<String> appVersion() async {
    if (_platform != TargetPlatform.android) {
      return '';
    }
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }
}
