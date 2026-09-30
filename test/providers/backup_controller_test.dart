import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/app_backup.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/backup_controller.dart';
import 'package:writing_questions_app/providers/exam_document_provider.dart';
import 'package:writing_questions_app/services/app_info_service.dart';
import 'package:writing_questions_app/services/backup_file_gateway.dart';
import 'package:writing_questions_app/services/backup_service.dart';
import 'package:writing_questions_app/services/storage_service.dart';

/// بوابة ملفات وهمية: تسجّل ما طُلب منها وتعيد ما حُدّد مسبقاً.
class _FakeGateway implements BackupFileGateway {
  _FakeGateway({
    this.pickResult,
    this.pickError,
    this.saveResult = 'content://saved/1',
    this.saveError,
    this.isSupported = true,
  });

  PickedBackupFile? pickResult;
  BackupFileException? pickError;
  String? saveResult;
  BackupFileException? saveError;

  @override
  final bool isSupported;

  String? savedName;
  Uint8List? savedBytes;
  int pickCalls = 0;

  @override
  Future<PickedBackupFile?> pickBackupFile() async {
    pickCalls++;
    if (pickError != null) {
      throw pickError!;
    }
    return pickResult;
  }

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    if (saveError != null) {
      throw saveError!;
    }
    savedName = suggestedName;
    savedBytes = bytes;
    return saveResult;
  }
}

class _FakeAppInfo implements AppInfoService {
  _FakeAppInfo([this.version = '1.0.0+1']);

  final String version;

  @override
  Future<String> appVersion() async => version;
}

ExamDocument _document({
  required String id,
  required DateTime updatedAt,
  String name = 'ورقة',
}) {
  return ExamDocument(
    id: id,
    name: name,
    header: ExamHeaderModel.ministerialDefault(subject: 'العلوم'),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        prompt: 'سؤال',
        branches: <BranchModel>[
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'فرع')),
        ],
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExamDocumentProvider provider;
  late StorageService storage;
  late _FakeGateway gateway;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = StorageService();
    provider = ExamDocumentProvider(storageService: storage);
    gateway = _FakeGateway();
    await provider.loadDocuments();
  });

  BackupController controllerWith({BackupFileGateway? fileGateway}) {
    return BackupController(
      documentsProvider: provider,
      fileGateway: fileGateway ?? gateway,
      appInfoService: _FakeAppInfo(),
      storageService: storage,
    );
  }

  group('createBackupFile', () {
    test('writes the full library and records the backup metadata', () async {
      await provider.saveDocument(_document(id: 'a', updatedAt: DateTime(2026, 5, 1)));
      await provider.saveLastOpenDocumentId('a');

      final controller = controllerWith();
      final saved = await controller.createBackupFile();

      expect(saved, isTrue);
      expect(gateway.savedName, endsWith('.json'));
      final payload = AppBackup.fromJson(utf8.decode(gateway.savedBytes!));
      expect(payload.documentCount, 1);
      expect(payload.documents.single.id, 'a');
      expect(payload.lastOpenDocumentId, 'a');
      expect(payload.appVersion, '1.0.0+1');
      expect(controller.lastBackup?.documentCount, 1);

      // البيانات الوصفية تُخزَّن فلا تنسى الشاشة آخر نسخة.
      expect((await storage.loadLastBackupMetadata())?.documentCount, 1);
    });

    test('does not record anything when the user cancels the save dialog', () async {
      gateway.saveResult = null;
      final controller = controllerWith();

      expect(await controller.createBackupFile(), isFalse);
      expect(controller.lastBackup, isNull);
      expect(await storage.loadLastBackupMetadata(), isNull);
      expect(controller.errorMessage, isNull);
    });

    test('reports a localized message when saving fails', () async {
      gateway.saveError = const BackupFileException('تعذر حفظ الملف على الجهاز.');
      final controller = controllerWith();

      expect(await controller.createBackupFile(), isFalse);
      expect(controller.errorMessage, 'تعذر حفظ الملف على الجهاز.');
      expect(controller.lastBackup, isNull);
    });
  });

  group('pickBackup and restore', () {
    test('parses the picked file and plans a merge preview', () async {
      await provider.saveDocument(_document(id: 'local', updatedAt: DateTime(2026, 6, 1)));
      final backup = BackupService().createBackup(
        documents: <ExamDocument>[
          _document(id: 'local', updatedAt: DateTime(2026, 7, 1), name: 'من النسخة'),
          _document(id: 'new', updatedAt: DateTime(2026, 7, 1)),
        ],
        lastOpenDocumentId: 'new',
      );
      gateway.pickResult = PickedBackupFile(
        name: 'نسخة.json',
        bytes: Uint8List.fromList(utf8.encode(backup.toJson())),
      );

      final controller = controllerWith();
      final preview = await controller.pickBackup();

      expect(preview, isNotNull);
      expect(preview!.sourceName, 'نسخة.json');
      expect(preview.backup.documentCount, 2);
      expect(preview.plan.added, 1);
      expect(preview.plan.updated, 1);
      // القراءة لا تعدّل شيئاً قبل التأكيد.
      expect(provider.documents, hasLength(1));
    });

    test('reports a clear error for a corrupt file', () async {
      gateway.pickResult = PickedBackupFile(
        name: 'ملف.txt',
        bytes: Uint8List.fromList(utf8.encode('هذا ليس JSON')),
      );

      final controller = controllerWith();
      expect(await controller.pickBackup(), isNull);
      expect(controller.errorMessage, contains('ليست ملف نسخة احتياطية صالحاً'));
      expect(provider.documents, isEmpty);
    });

    test('restores in merge mode without losing local documents', () async {
      await provider.saveDocument(_document(id: 'keep', updatedAt: DateTime(2026, 6, 1)));
      final backup = BackupService().createBackup(
        documents: <ExamDocument>[
          _document(id: 'added', updatedAt: DateTime(2026, 7, 1)),
        ],
      );

      final controller = controllerWith();
      final outcome = await controller.restore(
        backup: backup,
        mode: BackupRestoreMode.merge,
      );

      expect(outcome?.added, 1);
      expect(outcome?.total, 2);
      expect(provider.documents.map((document) => document.id), containsAll(<String>['keep', 'added']));
      // الحفظ ذري: المكتبة الجديدة صارت في التخزين.
      expect((await storage.loadExamDocuments()).items, hasLength(2));
    });

    test('replaces the library exactly and restores the session', () async {
      await provider.saveDocument(_document(id: 'old', updatedAt: DateTime(2026, 6, 1)));
      final backup = BackupService().createBackup(
        documents: <ExamDocument>[
          _document(id: 'only', updatedAt: DateTime(2026, 7, 1)),
        ],
        lastOpenDocumentId: 'only',
      );

      final controller = controllerWith();
      final outcome = await controller.restore(
        backup: backup,
        mode: BackupRestoreMode.replace,
      );

      expect(outcome?.total, 1);
      expect(provider.documents.single.id, 'only');
      expect(provider.lastOpenDocumentId, 'only');
      expect((await storage.loadLastOpenDocumentId()), 'only');
    });

    test('refuses to replace the library with an empty backup', () async {
      await provider.saveDocument(_document(id: 'old', updatedAt: DateTime(2026, 6, 1)));
      final controller = controllerWith();

      final outcome = await controller.restore(
        backup: BackupService().createBackup(documents: <ExamDocument>[]),
        mode: BackupRestoreMode.replace,
      );

      expect(outcome, isNull);
      expect(controller.errorMessage, isNotNull);
      expect(provider.documents, hasLength(1));
    });

    test('load() reads the app version and the last backup metadata', () async {
      await storage.saveLastBackupMetadata(
        BackupMetadata(createdAt: DateTime(2026, 9, 30, 10), documentCount: 3),
      );
      final controller = controllerWith();

      await controller.load();

      expect(controller.appVersion, '1.0.0+1');
      expect(controller.lastBackup?.documentCount, 3);
      expect(controller.isFileAccessSupported, isTrue);
    });
  });
}
