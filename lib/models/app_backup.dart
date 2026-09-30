import 'dart:convert';

import 'exam_document.dart';

/// بيانات وصفية لآخر نسخة احتياطية أُنشئت على هذا الجهاز (لعرضها في الإعدادات).
class BackupMetadata {
  const BackupMetadata({required this.createdAt, required this.documentCount});

  final DateTime createdAt;
  final int documentCount;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'createdAt': createdAt.toIso8601String(),
        'documentCount': documentCount,
      };

  /// قراءة متسامحة: بيانات وصفية تالفة تُتجاهل (`null`) ولا تُسقط الإعدادات.
  static BackupMetadata? fromValue(Object? value) {
    if (value is! Map) {
      return null;
    }
    final rawCreatedAt = value['createdAt'];
    final createdAt =
        rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null;
    if (createdAt == null) {
      return null;
    }
    final rawCount = value['documentCount'];
    final count = rawCount is num ? rawCount.toInt() : int.tryParse('$rawCount');
    return BackupMetadata(
      createdAt: createdAt,
      documentCount: count == null || count < 0 ? 0 : count,
    );
  }
}

/// النسخة الاحتياطية الكاملة: مكتبة الأوراق + حالة الجلسة الإعدادية.
///
/// ملف واحد قابل للقراءة (JSON) يحوي **كل** الأوراق المحفوظة ببياناتها
/// الكاملة (الأسئلة/الفروع/النقاط/الإجابات/الصور/المعادلات/الترويسة/
/// الإعدادات)، مع ترويسة تعريفية تحمل رقم صيغة ورقم إصدار للتحقق قبل
/// الاستعادة — فلا تُقرأ نسخة أحدث من التطبيق بصمت ولا تُطبَّق بلا تحقق.
class AppBackup {
  const AppBackup({
    required this.createdAt,
    required this.documents,
    this.lastOpenDocumentId,
    this.appVersion = '',
    this.schemaVersion = currentSchemaVersion,
  });

  /// بصمة صيغة الملف: تُرفض أي بنية لا تحملها (ملف لا يخصّ التطبيق).
  static const String formatId = 'writing_questions.backup';

  /// رقم صيغة النسخة الاحتياطية الحالي؛ يزيد عند تغيير البنية تغييراً غير متوافق.
  static const int currentSchemaVersion = 1;

  final DateTime createdAt;
  final List<ExamDocument> documents;

  /// آخر ورقة مفتوحة وقت النسخ (تُستعاد مع المكتبة إن كانت موجودة فيها).
  final String? lastOpenDocumentId;

  /// إصدار التطبيق الذي أنشأ النسخة (تشخيصي).
  final String appVersion;

  final int schemaVersion;

  int get documentCount => documents.length;

  int get totalQuestions =>
      documents.fold<int>(0, (sum, document) => sum + document.questions.length);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'format': formatId,
      'schemaVersion': schemaVersion,
      'createdAt': createdAt.toIso8601String(),
      if (appVersion.trim().isNotEmpty) 'appVersion': appVersion.trim(),
      'documents':
          documents.map((document) => document.toMap()).toList(growable: false),
      'settings': <String, dynamic>{
        if (lastOpenDocumentId != null && lastOpenDocumentId!.isNotEmpty)
          'lastOpenDocumentId': lastOpenDocumentId,
      },
    };
  }

  /// نصّ الملف؛ [pretty] يُخرج JSON مُزاحاً مقروءاً (وهو الأنسب لملف يحفظه
  /// المدرس على جهازه ويستعيده لاحقاً).
  String toJson({bool pretty = true}) {
    final map = toMap();
    if (!pretty) {
      return jsonEncode(map);
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// يقرأ نسخة احتياطية **بشكل صارم** وبرسائل عربية واضحة، حتى يعرف المدرس
  /// سبب رفض الملف بدل فشل صامت. تُرفض: بنية ليست JSON، بصمة صيغة مختلفة،
  /// نسخة أحدث من التطبيق، أو مستند تالف (`ExamDocument.fromMap` صارم أيضاً).
  factory AppBackup.fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException(
        'الملف المختار ليس ملف نسخة احتياطية صالحاً (JSON غير سليم).',
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'الملف المختار ليس ملف نسخة احتياطية صالحاً (بنية غير متوقعة).',
      );
    }
    final map = Map<String, dynamic>.from(decoded);

    final format = map['format']?.toString().trim();
    if (format != formatId) {
      throw const FormatException(
        'الملف المختار لا يخص هذا التطبيق (بصمة النسخة الاحتياطية غير مطابقة).',
      );
    }

    final rawSchema = map['schemaVersion'];
    final schema = rawSchema is num ? rawSchema.toInt() : int.tryParse('$rawSchema');
    if (schema == null || schema < 1) {
      throw const FormatException(
        'الملف المختار لا يحمل رقم صيغة صالحاً للنسخة الاحتياطية.',
      );
    }
    if (schema > currentSchemaVersion) {
      throw FormatException(
        'النسخة الاحتياطية أُنشئت بإصدار أحدث من التطبيق '
        '(صيغة $schema مقابل $currentSchemaVersion). حدّث التطبيق ثم أعد المحاولة.',
      );
    }

    final rawCreatedAt = map['createdAt'];
    final createdAt =
        rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null;
    if (createdAt == null) {
      throw const FormatException(
        'الملف المختار لا يحمل تاريخ إنشاء صالحاً للنسخة الاحتياطية.',
      );
    }

    final rawDocuments = map['documents'];
    if (rawDocuments is! List) {
      throw const FormatException('النسخة الاحتياطية لا تحوي قائمة أوراق صالحة.');
    }
    final documents = <ExamDocument>[];
    final seenIds = <String>{};
    for (var index = 0; index < rawDocuments.length; index++) {
      final entry = rawDocuments[index];
      if (entry is! Map) {
        throw FormatException(
          'الورقة رقم ${index + 1} في النسخة الاحتياطية تالفة (بنية غير متوقعة).',
        );
      }
      try {
        final document = ExamDocument.fromMap(Map<String, dynamic>.from(entry));
        // الهوية مفتاح الدمج والاستبدال: لا تُقبل نسخة بهويات مكرّرة.
        if (seenIds.add(document.id)) {
          documents.add(document);
        }
      } on FormatException catch (error) {
        throw FormatException(
          'الورقة رقم ${index + 1} في النسخة الاحتياطية تالفة: ${error.message}',
        );
      }
    }

    final rawSettings = map['settings'];
    final settings =
        rawSettings is Map ? Map<String, dynamic>.from(rawSettings) : const <String, dynamic>{};
    final rawLastOpen = settings['lastOpenDocumentId']?.toString().trim();

    return AppBackup(
      createdAt: createdAt,
      documents: List<ExamDocument>.unmodifiable(documents),
      lastOpenDocumentId:
          rawLastOpen == null || rawLastOpen.isEmpty ? null : rawLastOpen,
      appVersion: map['appVersion']?.toString() ?? '',
      schemaVersion: schema,
    );
  }
}
