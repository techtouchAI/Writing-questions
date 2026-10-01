import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/app_backup.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/backup_controller.dart';
import 'package:writing_questions_app/providers/exam_document_provider.dart';
import 'package:writing_questions_app/services/app_info_service.dart';
import 'package:writing_questions_app/services/backup_file_gateway.dart';
import 'package:writing_questions_app/services/backup_service.dart';
import 'package:writing_questions_app/services/storage_service.dart';
import 'package:writing_questions_app/views/settings_screen.dart';

/// تخزين في الذاكرة للاختبارات: يقطع الاعتماد على قناة المنصة نهائياً،
/// فتبقى شاشة الإعدادات معزولة وسريعة (طبقة التخزين نفسها مُختبَرة في
/// `test/services/storage_service_test.dart`).
class _MemoryStorage extends StorageService {
  List<ExamDocument> _documents = <ExamDocument>[];
  String? _lastOpenDocumentId;
  BackupMetadata? _lastBackup;

  @override
  Future<StorageLoadResult<ExamDocument>> loadExamDocuments() async {
    return StorageLoadResult<ExamDocument>(
      items: List<ExamDocument>.unmodifiable(_documents),
      hadStoredValue: true,
    );
  }

  @override
  Future<void> saveExamDocuments(List<ExamDocument> documents) async {
    _documents = List<ExamDocument>.of(documents);
  }

  @override
  Future<String?> loadLastOpenDocumentId() async => _lastOpenDocumentId;

  @override
  Future<void> saveLastOpenDocumentId(String? id) async {
    _lastOpenDocumentId = id;
  }

  @override
  Future<BackupMetadata?> loadLastBackupMetadata() async => _lastBackup;

  @override
  Future<void> saveLastBackupMetadata(BackupMetadata? metadata) async {
    _lastBackup = metadata;
  }
}

class _FakeGateway implements BackupFileGateway {
  PickedBackupFile? picked;
  BackupFileException? saveError;
  String? savedName;

  @override
  bool get isSupported => true;

  @override
  Future<PickedBackupFile?> pickBackupFile() async => picked;

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    if (saveError != null) {
      throw saveError!;
    }
    savedName = suggestedName;
    return 'content://saved/1';
  }
}

class _FakeAppInfo implements AppInfoService {
  @override
  Future<String> appVersion() async => '1.0.0+1';
}

ExamDocument _document({required String id, String name = 'ورقة الاختبار'}) {
  return ExamDocument(
    id: id,
    name: name,
    header: ExamHeaderModel.initial(subject: 'التربية الإسلامية'),
    questions: <QuestionModel>[
      QuestionModel(questionNumber: 1, statement: 'سؤال أول'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 6, 1),
  );
}

void main() {
  late ExamDocumentProvider provider;
  late _FakeGateway gateway;
  late BackupController controller;

  /// ينهي العملية غير المتزامنة وحركة النافذة/الشريحة بخطوات زمنية محددة.
  ///
  /// `pumpAndSettle` لا يصلح بعد بدء عملية يشغل فيها المتحكم مؤشر تقدم
  /// لانهائياً؛ فالخطوات المحددة تُكمل المهام الدقيقة (fakes) وحركات العناصر
  /// بلا انتظار غير محدود.
  Future<void> finishAction(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<BackupController>.value(
          value: controller,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    final storage = _MemoryStorage();
    provider = ExamDocumentProvider(storageService: storage);
    await provider.loadDocuments();
    gateway = _FakeGateway();
    controller = BackupController(
      documentsProvider: provider,
      fileGateway: gateway,
      appInfoService: _FakeAppInfo(),
      storageService: storage,
    );
  });

  testWidgets('offers backup and restore sections with app information', (tester) async {
    await pumpSettings(tester);

    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('النسخ الاحتياطي والاستعادة'), findsOneWidget);
    expect(find.text('إنشاء نسخة احتياطية'), findsOneWidget);
    expect(find.text('استعادة من ملف'), findsOneWidget);
    expect(find.text('لم تُنشأ نسخة احتياطية بعد على هذا الجهاز.'), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
  });

  testWidgets('saves a backup file and reports success with the last backup date',
      (tester) async {
    await provider.saveDocument(_document(id: 'a'));
    await pumpSettings(tester);

    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ في ملف على الجهاز'));
    await finishAction(tester);

    expect(gateway.savedName, endsWith('.json'));
    expect(find.text('تم حفظ النسخة الاحتياطية كاملة.'), findsOneWidget);
    expect(controller.lastBackup?.documentCount, 1);
  });

  testWidgets('shows a clear error when saving fails', (tester) async {
    gateway.saveError = const BackupFileException('تعذر حفظ ملف النسخة الاحتياطية على الجهاز.');
    await pumpSettings(tester);

    await tester.tap(find.text('إنشاء نسخة احتياطية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ في ملف على الجهاز'));
    await finishAction(tester);

    expect(find.text('تعذر حفظ ملف النسخة الاحتياطية على الجهاز.'), findsOneWidget);
  });

  testWidgets('reviews the backup file and restores it after confirmation', (tester) async {
    final backup = const BackupService().createBackup(
      documents: <ExamDocument>[_document(id: 'restored', name: 'ورقة مستعادة')],
      lastOpenDocumentId: 'restored',
    );
    gateway.picked = PickedBackupFile(
      name: 'نسخة_احتياطية.json',
      bytes: Uint8List.fromList(utf8.encode(backup.toJson())),
    );
    await pumpSettings(tester);

    await tester.tap(find.text('استعادة من ملف'));
    await tester.pumpAndSettle();

    // نافذة التأكيد تعرض الملف ومحتواه والوضعين قبل أي تعديل.
    expect(find.text('استعادة نسخة احتياطية'), findsOneWidget);
    expect(find.text('الملف: نسخة_احتياطية.json'), findsOneWidget);
    expect(find.textContaining('دمج مع المكتبة الحالية'), findsWidgets);
    expect(find.textContaining('استبدال المكتبة بالكامل'), findsWidgets);
    expect(provider.documents, isEmpty, reason: 'لا تعديل قبل التأكيد.');

    await tester.tap(find.widgetWithText(FilledButton, 'استعادة'));
    await finishAction(tester);

    expect(provider.documents.single.name, 'ورقة مستعادة');
    expect(find.textContaining('تمت الاستعادة'), findsOneWidget);
  });

  testWidgets('reports an unreadable file without touching the library', (tester) async {
    await provider.saveDocument(_document(id: 'keep'));
    gateway.picked = PickedBackupFile(
      name: 'ملف.txt',
      bytes: Uint8List.fromList(utf8.encode('ليست نسخة احتياطية')),
    );
    await pumpSettings(tester);

    await tester.tap(find.text('استعادة من ملف'));
    await tester.pumpAndSettle();

    expect(find.text('استعادة نسخة احتياطية'), findsNothing);
    expect(find.textContaining('ليس ملف نسخة احتياطية صالحاً'), findsOneWidget);
    expect(provider.documents.single.id, 'keep');
  });

  testWidgets('cancelling the picker keeps the library untouched', (tester) async {
    gateway.picked = null;
    await pumpSettings(tester);

    await tester.tap(find.text('استعادة من ملف'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(provider.documents, isEmpty);
    expect(controller.errorMessage, isNull);
  });
}
