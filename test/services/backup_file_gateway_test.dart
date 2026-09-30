import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/services/app_info_service.dart';
import 'package:writing_questions_app/services/backup_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformBackupFileGateway.channelName);
  const appInfoChannel = MethodChannel(PlatformAppInfoService.channelName);

  final calls = <MethodCall>[];

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appInfoChannel, null);
  });

  group('PlatformBackupFileGateway', () {
    test('reads the picked file name and bytes and decodes Arabic text', () async {
      final bytes = Uint8List.fromList(utf8.encode('{"format":"x"}'));
      mockChannel((_) async => <String, Object>{'name': 'نسخة.json', 'bytes': bytes});

      final gateway = PlatformBackupFileGateway(platform: TargetPlatform.android);
      final picked = await gateway.pickBackupFile();

      expect(picked?.name, 'نسخة.json');
      expect(picked?.text, '{"format":"x"}');
      expect(calls.single.method, 'pickBackupFile');
    });

    test('returns null when the user cancels the picker', () async {
      mockChannel((_) async => null);

      final gateway = PlatformBackupFileGateway(platform: TargetPlatform.android);
      expect(await gateway.pickBackupFile(), isNull);
    });

    test('maps platform failures to a user-facing Arabic message', () async {
      mockChannel((_) async => throw PlatformException(
            code: 'read_failed',
            message: 'تعذر قراءة الملف المحدد.',
          ));

      final gateway = PlatformBackupFileGateway(platform: TargetPlatform.android);
      await expectLater(
        gateway.pickBackupFile(),
        throwsA(
          isA<BackupFileException>().having(
            (error) => error.message,
            'message',
            'تعذر قراءة الملف المحدد.',
          ),
        ),
      );
    });

    test('sends the suggested name and bytes when saving', () async {
      mockChannel((_) async => 'content://saved/1');

      final gateway = PlatformBackupFileGateway(platform: TargetPlatform.android);
      final bytes = Uint8List.fromList(utf8.encode('{"a":1}'));
      final saved = await gateway.saveBackupFile(
        suggestedName: 'نسخة_احتياطية.json',
        bytes: bytes,
      );

      expect(saved, 'content://saved/1');
      final call = calls.single;
      expect(call.method, 'saveBackupFile');
      expect(call.arguments['suggestedName'], 'نسخة_احتياطية.json');
      expect(call.arguments['bytes'], bytes);
    });

    test('reports unsupported platforms instead of failing silently', () async {
      final gateway = PlatformBackupFileGateway(platform: TargetPlatform.linux);
      expect(gateway.isSupported, isFalse);
      await expectLater(
        gateway.pickBackupFile(),
        throwsA(isA<BackupFileException>()),
      );
    });
  });

  group('PlatformAppInfoService', () {
    test('reads the app version from the platform', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appInfoChannel, (call) async {
        expect(call.method, 'appVersion');
        return '1.0.0';
      });

      final service = PlatformAppInfoService(platform: TargetPlatform.android);
      expect(await service.appVersion(), '1.0.0');
    });

    test('returns an empty version when the platform fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appInfoChannel, (_) async {
        throw PlatformException(code: 'error');
      });

      final service = PlatformAppInfoService(platform: TargetPlatform.android);
      expect(await service.appVersion(), isEmpty);
      expect(
        await PlatformAppInfoService(platform: TargetPlatform.linux).appVersion(),
        isEmpty,
      );
    });
  });
}
