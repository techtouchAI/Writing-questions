import '../models/app_backup.dart';
import '../models/exam_document.dart';

/// سياسة الاستعادة: تُدمج النسخة مع المكتبة الحالية أو تستبدلها تماماً.
enum BackupRestoreMode {
  /// دمج: تُضاف الأوراق الجديدة، وتُحدَّث الأوراق نفسها إن كانت نسخة الملف
  /// أحدث تعديلاً، ويبقى ما لا وجود له في الملف كما هو.
  merge,

  /// استبدال: تصير المكتبة **مطابقة** لما في النسخة الاحتياطية حرفياً.
  replace;

  String get arabicLabel => switch (this) {
        BackupRestoreMode.merge => 'دمج مع المكتبة الحالية',
        BackupRestoreMode.replace => 'استبدال المكتبة بالكامل',
      };

  String get arabicDescription => switch (this) {
        BackupRestoreMode.merge =>
          'تُضاف الأوراق غير الموجودة، وتُحدَّث الأوراق نفسها إن كانت في النسخة أحدث تعديلاً.',
        BackupRestoreMode.replace =>
          'تُحذف أوراق المكتبة الحالية وتُستبدل بأوراق النسخة الاحتياطية حرفياً.',
      };
}

/// خطة الاستعادة المحسوبة قبل التطبيق: تُعرض للمدرس في نافذة التأكيد ثم
/// تُطبَّق كما هي (نفس الحساب، بلا مفاجآت بعد التأكيد).
class BackupRestorePlan {
  const BackupRestorePlan({
    required this.documents,
    required this.added,
    required this.updated,
    required this.kept,
    this.lastOpenDocumentId,
  });

  /// المكتبة الناتجة بعد التطبيق.
  final List<ExamDocument> documents;

  /// أوراق جديدة ستُضاف.
  final int added;

  /// أوراق موجودة سيُحدَّث محتواها من النسخة (نسختها أحدث).
  final int updated;

  /// أوراق موجودة ستبقى كما هي (نسختها المحلية أحدث أو مساوية).
  final int kept;

  /// آخر ورقة مفتوحة بعد الاستعادة (تُضبط إن كانت موجودة في المكتبة الناتجة).
  final String? lastOpenDocumentId;

  int get total => documents.length;

  bool get changesNothing => added == 0 && updated == 0;
}

/// منطق النسخ الاحتياطي والاستعادة **الخالص** (بلا واجهة ولا ملفات):
/// إنشاء النسخة، وقراءتها بصرامة، وحساب خطة الاستعادة.
///
/// فصل المنطق عن النقل (ملفات/مشاركة) يجعل السلوك قابلاً للاختبار كاملاً
/// دون جهاز، ويُبقي كتابة الملف وقراءته في [BackupController] وحده.
class BackupService {
  const BackupService();

  /// يبني نسخة احتياطية كاملة من [documents] مع حالة الجلسة.
  AppBackup createBackup({
    required List<ExamDocument> documents,
    String? lastOpenDocumentId,
    String appVersion = '',
    DateTime? createdAt,
  }) {
    final ids = documents.map((document) => document.id).toSet();
    final lastOpen = lastOpenDocumentId != null && ids.contains(lastOpenDocumentId)
        ? lastOpenDocumentId
        : null;
    return AppBackup(
      createdAt: createdAt ?? DateTime.now(),
      documents: List<ExamDocument>.unmodifiable(documents),
      lastOpenDocumentId: lastOpen,
      appVersion: appVersion,
    );
  }

  /// يقرأ نسخة احتياطية من نصّ ملف؛ يرمي [FormatException] برسالة عربية
  /// واضحة عند أي تلف (انظر `AppBackup.fromJson`).
  AppBackup parseBackup(String source) => AppBackup.fromJson(source);

  /// يحسب خطة الاستعادة **دون أي تعديل**: المقارنة بالهوية، والبتّ عند
  /// الاختلاف بختم آخر تعديل ([ExamDocument.updatedAt]) — فلا تُفقد أوراق
  /// المكتبة ولا يُدهس عمل أحدث منها بنسخة قديمة.
  BackupRestorePlan planRestore({
    required List<ExamDocument> current,
    required AppBackup backup,
    required BackupRestoreMode mode,
    String? currentLastOpenDocumentId,
  }) {
    if (mode == BackupRestoreMode.replace) {
      return BackupRestorePlan(
        documents: List<ExamDocument>.unmodifiable(backup.documents),
        added: backup.documents.length,
        updated: 0,
        kept: 0,
        lastOpenDocumentId: _resolvedLastOpenId(
          backup.lastOpenDocumentId,
          backup.documents,
        ),
      );
    }

    final byId = <String, ExamDocument>{
      for (final document in current) document.id: document,
    };
    var added = 0;
    var updated = 0;
    var kept = 0;

    for (final incoming in backup.documents) {
      final existing = byId[incoming.id];
      if (existing == null) {
        byId[incoming.id] = incoming;
        added++;
        continue;
      }
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        byId[incoming.id] = incoming;
        updated++;
      } else {
        kept++;
      }
    }

    return BackupRestorePlan(
      documents: List<ExamDocument>.unmodifiable(byId.values),
      added: added,
      updated: updated,
      kept: kept,
      // في الدمج: تبقى الجلسة الحالية إن كانت ورقتها ما زالت موجودة،
      // وإلا تُستعاد جلسة النسخة الاحتياطية.
      lastOpenDocumentId: _resolvedLastOpenId(
            currentLastOpenDocumentId,
            byId.values,
          ) ??
          _resolvedLastOpenId(backup.lastOpenDocumentId, byId.values),
    );
  }

  /// جذر اسم الملف المقترح للنسخة (يحمل تاريخاً زمنياً فلا يطمس سابقتها).
  String suggestedFileStem(AppBackup backup) {
    final at = backup.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${at.year}-${two(at.month)}-${two(at.day)}'
        '_${two(at.hour)}${two(at.minute)}';
    return 'نسخة_احتياطية_$stamp';
  }

  /// اسم ملف النسخة الاحتياطية الكامل (بامتداد JSON).
  String suggestedFileName(AppBackup backup) =>
      '${suggestedFileStem(backup)}.json';

  static String? _resolvedLastOpenId(
    String? candidate,
    Iterable<ExamDocument> documents,
  ) {
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    for (final document in documents) {
      if (document.id == candidate) {
        return candidate;
      }
    }
    return null;
  }
}
