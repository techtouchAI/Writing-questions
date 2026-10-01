import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/app_backup.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';

ExamDocument _document({String id = 'd1', String name = 'ورقة', int questions = 1}) {
  return ExamDocument(
    id: id,
    name: name,
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      for (var index = 1; index <= questions; index++)
        QuestionModel(questionNumber: index, statement: 'سؤال $index'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );
}

void main() {
  group('AppBackup model', () {
    test('round-trips the whole library, session and version', () {
      final backup = AppBackup(
        createdAt: DateTime(2026, 9, 30, 14, 30),
        documents: <ExamDocument>[_document(), _document(id: 'd2', name: 'ورقة ثانية', questions: 2)],
        lastOpenDocumentId: 'd2',
        appVersion: '1.0.0',
      );

      expect(backup.documentCount, 2);
      expect(backup.totalQuestions, 3);

      final restored = AppBackup.fromJson(backup.toJson());
      expect(restored.createdAt, DateTime(2026, 9, 30, 14, 30));
      expect(restored.documents.map((document) => document.id), <String>['d1', 'd2']);
      expect(restored.documents.first.name, 'ورقة');
      expect(restored.documents.last.questions, hasLength(2));
      expect(restored.lastOpenDocumentId, 'd2');
      expect(restored.appVersion, '1.0.0');
      expect(restored.schemaVersion, AppBackup.currentSchemaVersion);
    });

    test('pretty JSON stays parseable and readable', () {
      final backup = AppBackup(
        createdAt: DateTime(2026, 9, 30),
        documents: <ExamDocument>[_document()],
      );
      final pretty = backup.toJson();
      expect(pretty.contains('\n'), isTrue);
      expect(AppBackup.fromJson(pretty).documentCount, 1);
      expect(pretty.contains(AppBackup.formatId), isTrue);
    });

    test('rejects files that are not valid backups', () {
      expect(
        () => AppBackup.fromJson('{ليس JSON'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppBackup.fromJson('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppBackup.fromJson('{"format":"other.app","schemaVersion":1}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppBackup.fromJson(
          '{"format":"${AppBackup.formatId}","schemaVersion":1,"documents":[]}',
        ),
        throwsA(isA<FormatException>()),
        reason: 'تاريخ الإنشاء إلزامي لتمييز النسخة.',
      );
      expect(
        () => AppBackup.fromJson(
          '{"format":"${AppBackup.formatId}","createdAt":"2026-09-30T10:00:00.000",'
          '"documents":[{"name":"ورقة بلا ترويسة"}]}',
        ),
        throwsA(isA<FormatException>()),
        reason: 'ورقة تالفة (بلا ترويسة) ترفض النسخة كلها برسالة واضحة.',
      );
    });

    test('rejects a backup created by a newer app version', () {
      const source = '{"format":"${AppBackup.formatId}",'
          '"schemaVersion":${AppBackup.currentSchemaVersion + 1},'
          '"createdAt":"2026-09-30T10:00:00.000","documents":[]}';
      expect(
        () => AppBackup.fromJson(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('أحدث'),
          ),
        ),
      );
    });

    test('duplicate document ids collapse to the first occurrence', () {
      final backup = AppBackup(
        createdAt: DateTime(2026, 9, 30),
        documents: <ExamDocument>[_document(), _document(name: 'نسخة مكرّرة')],
      );
      final restored = AppBackup.fromJson(backup.toJson());
      expect(restored.documents, hasLength(1));
      expect(restored.documents.single.name, 'ورقة');
    });

    test('BackupMetadata reads leniently and ignores corrupt values', () {
      final metadata = BackupMetadata(
        createdAt: DateTime(2026, 9, 30, 12),
        documentCount: 4,
      );
      final restored = BackupMetadata.fromValue(metadata.toMap());
      expect(restored?.documentCount, 4);
      expect(restored?.createdAt, DateTime(2026, 9, 30, 12));

      expect(BackupMetadata.fromValue(null), isNull);
      expect(BackupMetadata.fromValue('نص'), isNull);
      expect(BackupMetadata.fromValue(<String, dynamic>{'createdAt': 'خطأ'}), isNull);
    });
  });
}
