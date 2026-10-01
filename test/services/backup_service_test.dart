import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/backup_service.dart';

ExamDocument _document({
  required String id,
  required DateTime updatedAt,
  String name = 'ورقة',
  int questions = 1,
}) {
  return ExamDocument(
    id: id,
    name: name,
    header: ExamHeaderModel.initial(subject: 'الرياضيات'),
    questions: <QuestionModel>[
      for (var index = 1; index <= questions; index++)
        QuestionModel(questionNumber: index, statement: 'سؤال $index'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
  );
}

void main() {
  const service = BackupService();

  group('BackupService.createBackup', () {
    test('keeps the session only when its document is in the backup', () {
      final documents = <ExamDocument>[
        _document(id: 'a', updatedAt: DateTime(2026, 5, 1)),
      ];

      final withSession = service.createBackup(
        documents: documents,
        lastOpenDocumentId: 'a',
        appVersion: '1.0.0+1',
        createdAt: DateTime(2026, 9, 30, 8),
      );
      expect(withSession.lastOpenDocumentId, 'a');
      expect(withSession.appVersion, '1.0.0+1');
      expect(withSession.createdAt, DateTime(2026, 9, 30, 8));

      final staleSession = service.createBackup(
        documents: documents,
        lastOpenDocumentId: 'محذوف',
      );
      expect(staleSession.lastOpenDocumentId, isNull);
    });

    test('suggests a timestamped Arabic file name', () {
      final backup = service.createBackup(
        documents: <ExamDocument>[],
        createdAt: DateTime(2026, 9, 30, 14, 5),
      );
      expect(service.suggestedFileStem(backup), 'نسخة_احتياطية_2026-09-30_1405');
      expect(service.suggestedFileName(backup), 'نسخة_احتياطية_2026-09-30_1405.json');
    });
  });

  group('BackupService.planRestore', () {
    final local = <ExamDocument>[
      _document(id: 'same', updatedAt: DateTime(2026, 6, 1), name: 'نسختي'),
      _document(id: 'local-only', updatedAt: DateTime(2026, 6, 1)),
    ];

    test('merge adds new documents, updates older ones and keeps newer ones', () {
      final backup = service.createBackup(
        documents: <ExamDocument>[
          _document(id: 'same', updatedAt: DateTime(2026, 7, 1), name: 'من النسخة'),
          _document(id: 'backup-only', updatedAt: DateTime(2026, 7, 1)),
        ],
        lastOpenDocumentId: 'backup-only',
      );

      final plan = service.planRestore(
        current: local,
        backup: backup,
        mode: BackupRestoreMode.merge,
        currentLastOpenDocumentId: 'same',
      );

      expect(plan.added, 1);
      expect(plan.updated, 1);
      expect(plan.kept, 0);
      expect(plan.total, 3);
      expect(
        plan.documents.firstWhere((document) => document.id == 'same').name,
        'من النسخة',
      );
      // الجلسة الحالية باقية لأن ورقتها ما زالت في المكتبة.
      expect(plan.lastOpenDocumentId, 'same');
      expect(plan.changesNothing, isFalse);
    });

    test('merge keeps a locally newer document untouched', () {
      final backup = service.createBackup(
        documents: <ExamDocument>[
          _document(id: 'same', updatedAt: DateTime(2026, 1, 1), name: 'قديمة'),
        ],
      );

      final plan = service.planRestore(
        current: local,
        backup: backup,
        mode: BackupRestoreMode.merge,
        currentLastOpenDocumentId: 'local-only',
      );

      expect(plan.added, 0);
      expect(plan.updated, 0);
      expect(plan.kept, 1);
      expect(plan.total, 2);
      expect(
        plan.documents.firstWhere((document) => document.id == 'same').name,
        'نسختي',
      );
      expect(plan.changesNothing, isTrue);
      // جلسة النسخة لا تحل مكان جلسة حقيقية قائمة.
      expect(plan.lastOpenDocumentId, 'local-only');
    });

    test('merge falls back to the backup session when the local one is gone', () {
      final backup = service.createBackup(
        documents: <ExamDocument>[
          _document(id: 'restored', updatedAt: DateTime(2026, 7, 1)),
        ],
        lastOpenDocumentId: 'restored',
      );

      final plan = service.planRestore(
        current: local,
        backup: backup,
        mode: BackupRestoreMode.merge,
        currentLastOpenDocumentId: 'ورقة-محذوفة',
      );

      expect(plan.lastOpenDocumentId, 'restored');
    });

    test('replace mirrors the backup exactly', () {
      final backup = service.createBackup(
        documents: <ExamDocument>[
          _document(id: 'x', updatedAt: DateTime(2026, 7, 1)),
          _document(id: 'y', updatedAt: DateTime(2026, 7, 1)),
        ],
        lastOpenDocumentId: 'y',
      );

      final plan = service.planRestore(
        current: local,
        backup: backup,
        mode: BackupRestoreMode.replace,
        currentLastOpenDocumentId: 'same',
      );

      expect(plan.documents.map((document) => document.id), <String>['x', 'y']);
      expect(plan.added, 2);
      expect(plan.kept, 0);
      expect(plan.lastOpenDocumentId, 'y');
    });

    test('modes document their own effect in Arabic', () {
      for (final mode in BackupRestoreMode.values) {
        expect(mode.arabicLabel.trim(), isNotEmpty);
        expect(mode.arabicDescription.trim(), isNotEmpty);
      }
    });
  });

  test('parseBackup surfaces the strict format errors', () {
    expect(
      () => service.parseBackup('{"format":"nope"}'),
      throwsA(isA<FormatException>()),
    );
    final valid = service.createBackup(documents: <ExamDocument>[]);
    expect(service.parseBackup(valid.toJson()).documentCount, 0);
  });
}
