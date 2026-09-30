import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/app_backup.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/backup_service.dart';

/// كتابة أسئلة فقط — **لا حالة إجابة لأي نوع سؤال**.
///
/// يحرس هذا الملف ثلاثة أمور صراحةً:
///  1. إنشاء كل نوع سؤال ثم فحص الـ JSON/النموذج الناتج: لا أي حقل إجابة.
///  2. النسخة الاحتياطية الجديدة: صفر حقول إجابة.
///  3. نسخة قديمة بحقول إجابة ← استعادة ← نموذج جديد بلا إجابات ← نسخة
///     احتياطية جديدة بلا إجابات.

/// كل مفتاح يدل على إجابة/تصحيح/نسخة معلم (بأي صياغة).
final RegExp _answerKeyPattern = RegExp(
  r'answer|correct|teacher|solution|truefalseformat|istrue',
  caseSensitive: false,
);

/// أسماء الحقول الممنوعة بالاسم الصريح (من متطلبات المشروع).
const List<String> _forbiddenFieldNames = <String>[
  'isCorrect',
  'modelAnswer',
  'trueFalseAnswer',
  'answer',
  'correctAnswer',
  'teacherAnswer',
  'isTeacherVersion',
];

/// مسارات كل مفتاح مشبوه داخل بنية JSON متداخلة (القيم لا تُفحص — المفاتيح فقط).
List<String> _answerKeyPaths(Object? node, [String path = r'$']) {
  final found = <String>[];
  if (node is Map) {
    node.forEach((key, value) {
      final keyText = key.toString();
      if (_answerKeyPattern.hasMatch(keyText)) {
        found.add('$path.$keyText');
      }
      found.addAll(_answerKeyPaths(value, '$path.$keyText'));
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      found.addAll(_answerKeyPaths(node[i], '$path[$i]'));
    }
  }
  return found;
}

/// نفس الفحص على نص JSON الخام: أي `"مفتاح":` مشبوه.
List<String> _answerKeysInRawJson(String json) {
  return RegExp(r'"([^"\\]*)"\s*:')
      .allMatches(json)
      .map((match) => match.group(1)!)
      .where(_answerKeyPattern.hasMatch)
      .toList();
}

const Set<String> _itemKeys = <String>{'id', 'text', 'marks', 'labelOverride', 'align'};
const Set<String> _optionKeys = <String>{'id', 'text', 'labelOverride', 'align'};

void _expectNoAnswerState(Map<String, dynamic> map, {required String reason}) {
  expect(_answerKeyPaths(map), isEmpty, reason: reason);
  for (final name in _forbiddenFieldNames) {
    expect(jsonEncode(map).contains('"$name"'), isFalse, reason: '$reason — "$name"');
  }
}

BranchContent _contentFor(QuestionType type) {
  return BranchContent(
    type: type,
    text: 'نص الفرع ${type.name}',
    options: type == QuestionType.multipleChoice
        ? <QuestionOption>[
            QuestionOption(text: 'الأول'),
            QuestionOption(text: 'الثاني'),
            QuestionOption(text: 'الثالث'),
          ]
        : null,
    items: <BranchItem>[
      BranchItem(text: 'عبارة ١', marks: 1),
      BranchItem(text: 'عبارة ٢', marks: 2, labelOverride: 'أ)'),
    ],
  );
}

/// ورقة فيها كل أنواع الأسئلة: نوع مباشر + فرع من النوع نفسه.
ExamDocument _documentWithEveryType() {
  return ExamDocument(
    id: 'doc-all-types',
    name: 'كل الأنواع',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
    questions: <QuestionModel>[
      for (final type in QuestionType.values)
        QuestionModel(
          questionNumber: QuestionType.values.indexOf(type) + 1,
          type: type,
          prompt: 'سؤال ${type.name}',
          items: <BranchItem>[BranchItem(text: 'نقطة مباشرة', marks: 1)],
          branches: <BranchModel>[
            BranchModel(content: _contentFor(type), marks: 3),
          ],
        ),
    ],
  );
}

/// يحاكي ملفاً قديماً: يحقن حقول الإجابات القديمة في كل مستوى من الـ JSON.
Map<String, dynamic> _injectLegacyAnswerFields(Map<String, dynamic> backupMap) {
  void pollute(Map<String, dynamic> target, List<String> names) {
    for (final name in names) {
      target[name] = name.startsWith('is') ? true : 'قيمة قديمة';
    }
  }

  void polluteItems(Object? items) {
    for (final item in (items as List?) ?? const <Object?>[]) {
      pollute(item as Map<String, dynamic>, <String>[
        'isCorrect',
        'answer',
        'trueFalseAnswer',
        'correctAnswer',
      ]);
    }
  }

  pollute(backupMap, <String>['isTeacherVersion', 'teacherVersion', 'answers']);
  for (final rawDocument in backupMap['documents'] as List) {
    final document = rawDocument as Map<String, dynamic>;
    pollute(document, <String>['isTeacherVersion', 'teacherVersion', 'modelAnswer']);
    for (final rawQuestion in document['questions'] as List) {
      final question = rawQuestion as Map<String, dynamic>;
      pollute(question, <String>[
        'answer',
        'modelAnswer',
        'trueFalseAnswer',
        'correctAnswer',
        'teacherAnswer',
        'isTeacherVersion',
        'teacherVersion',
        'trueFalseFormat',
      ]);
      polluteItems(question['items']);
      for (final rawBranch in question['branches'] as List) {
        final branch = rawBranch as Map<String, dynamic>;
        pollute(branch, <String>['answer', 'correctAnswer', 'trueFalseAnswer']);
        final content = branch['content'] as Map<String, dynamic>;
        pollute(content, <String>[
          'modelAnswer',
          'modelAnswerAlign',
          'trueFalseAnswer',
          'correctAnswer',
          'teacherAnswer',
          'answer',
          'trueFalseFormat',
        ]);
        polluteItems(content['items']);
        for (final rawOption in (content['options'] as List?) ?? const <Object?>[]) {
          pollute(rawOption as Map<String, dynamic>, <String>['isCorrect', 'correct', 'answer']);
        }
        if (content['type'] == QuestionType.trueFalse.name) {
          // الصيغة القديمة لصح/خطأ: خياران «صح/خطأ» أحدهما معلَّم كصحيح.
          content['options'] = <Map<String, dynamic>>[
            <String, dynamic>{'id': 'legacy-t', 'text': 'صح', 'isCorrect': true},
            <String, dynamic>{'id': 'legacy-f', 'text': 'خطأ', 'isCorrect': false},
          ];
        }
      }
    }
  }
  return backupMap;
}

void main() {
  group('J) كل نوع سؤال: JSON/النموذج الناتج بلا حالة إجابة', () {
    for (final type in QuestionType.values) {
      test('${type.name}: سؤال مباشر + فرع + نقاط (+ خيارات) بلا أي حقل إجابة', () {
        final question = QuestionModel(
          questionNumber: 1,
          type: type,
          prompt: 'سؤال ${type.name}',
          items: <BranchItem>[BranchItem(text: 'نقطة', marks: 1)],
          branches: <BranchModel>[BranchModel(content: _contentFor(type), marks: 2)],
        );
        final map = question.toMap();

        _expectNoAnswerState(map, reason: 'QuestionModel(${type.name})');
        expect(_answerKeysInRawJson(jsonEncode(map)), isEmpty);

        // القائمة البيضاء: النقطة نص/درجة/تسمية/محاذاة فقط.
        for (final item in question.items) {
          expect(item.toMap().keys.toSet().difference(_itemKeys), isEmpty);
        }
        final content = question.branches.single.content;
        for (final item in content.items) {
          expect(item.toMap().keys.toSet().difference(_itemKeys), isEmpty);
        }
        for (final option in content.options) {
          expect(option.toMap().keys.toSet().difference(_optionKeys), isEmpty);
        }
        // الخيارات للاختيار من متعدد وحده، ونصية فقط.
        expect(
          content.options.length,
          type == QuestionType.multipleChoice ? 3 : 0,
        );
      });

      test('${type.name}: إنشاؤه من المحرر (ExamWizardController) بلا حالة إجابة', () {
        final controller = ExamWizardController();
        controller.addBranch(0);
        const ref = BranchRef(questionIndex: 0, branchIndex: 0);
        controller.updateBranchType(ref, type);
        controller.updateBranchText(ref, 'نص');
        controller.addBranchItem(ref, BranchItem(text: 'عبارة'));
        controller.updateBranchItemText(ref, 0, 'عبارة معدّلة');
        if (type == QuestionType.multipleChoice) {
          controller.updateBranchOptionText(ref, 0, 'خيار');
        }

        _expectNoAnswerState(
          controller.document.toMap(),
          reason: 'ExamWizardController(${type.name})',
        );
      });
    }

    test('ورقة فيها كل الأنواع معاً: الـ JSON الكامل بلا حقل إجابة واحد', () {
      final document = _documentWithEveryType();
      expect(
        document.questions.map((question) => question.type).toSet(),
        QuestionType.values.toSet(),
      );
      _expectNoAnswerState(document.toMap(), reason: 'ExamDocument');
      expect(_answerKeysInRawJson(document.toJson()), isEmpty);
    });

    test('صح/خطأ: يخزّن نص العبارة وترتيبها ودرجتها فقط — لا صح/خطأ/بلا إجابة', () {
      final item = BranchItem(text: 'الأرض كروية', marks: 2);
      expect(item.toMap().keys.toSet().difference(_itemKeys), isEmpty);
      expect(item.toMap()['text'], 'الأرض كروية');
      expect(item.toMap()['marks'], 2.0);

      final content = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[BranchItem(text: 'أ'), BranchItem(text: 'ب')],
      );
      final map = content.toMap();
      expect(map.keys.toSet().difference(<String>{'type', 'text', 'options', 'items', 'plainText'}),
          isEmpty);
      expect(map['options'], isEmpty);
      expect((map['items'] as List).map((entry) => (entry as Map)['text']), <String>['أ', 'ب']);
    });

    test('اختيار من متعدد: الخيارات نصية فقط ولا خيار صحيح في النموذج', () {
      final content = BranchContent(
        type: QuestionType.multipleChoice,
        options: <QuestionOption>[QuestionOption(text: 'س'), QuestionOption(text: 'ص')],
      );
      final options = content.toMap()['options'] as List;
      expect(options, hasLength(2));
      for (final option in options) {
        expect((option as Map).keys.toSet().difference(_optionKeys), isEmpty);
      }
    });

    test('الشيفرة المصدرية (lib/) لا تحوي أي حقل/اسم إجابة', () {
      final pattern = RegExp(
        r'\b(isCorrect|modelAnswer|modelAnswerAlign|trueFalseAnswer|correctAnswer|'
        r'teacherAnswer|isTeacherVersion|teacherVersion|trueFalseFormat)\b',
      );
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('K) النسخة الاحتياطية الجديدة: صفر حقول إجابة', () {
    test('New Backup must contain zero answer fields', () {
      final backup = const BackupService().createBackup(
        documents: <ExamDocument>[_documentWithEveryType()],
        lastOpenDocumentId: 'doc-all-types',
        appVersion: '1.0.0',
        createdAt: DateTime(2026, 9, 30),
      );
      final json = backup.toJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(_answerKeyPaths(decoded), isEmpty);
      expect(_answerKeysInRawJson(json), isEmpty);
      for (final name in _forbiddenFieldNames) {
        expect(json.contains('"$name"'), isFalse, reason: name);
      }
      // ... والمحتوى الفعلي للأسئلة محفوظ كاملاً.
      expect(backup.totalQuestions, QuestionType.values.length);
      expect(json.contains('نص الفرع multipleChoice'), isTrue);
      expect(json.contains('عبارة ١'), isTrue);
    });

    test('النسخة المضغوطة (بلا تنسيق) بلا حقول إجابة أيضاً', () {
      final backup = AppBackup(
        createdAt: DateTime(2026, 9, 30),
        documents: <ExamDocument>[_documentWithEveryType()],
      );
      expect(_answerKeysInRawJson(backup.toJson(pretty: false)), isEmpty);
    });
  });

  group('L) نسخة قديمة بحقول إجابة ← استعادة ← نموذج جديد ← نسخة جديدة', () {
    test('Old Backup with answer fields → restore → no answer state → new Backup has none', () {
      const service = BackupService();
      final original = _documentWithEveryType();

      // 1) ملف قديم: نفس الورقة مع حقول الإجابات القديمة في كل مستوى.
      final oldBackupMap = _injectLegacyAnswerFields(
        jsonDecode(
          service
              .createBackup(
                documents: <ExamDocument>[original],
                lastOpenDocumentId: original.id,
                createdAt: DateTime(2026, 9, 30),
              )
              .toJson(),
        ) as Map<String, dynamic>,
      );
      final oldJson = jsonEncode(oldBackupMap);
      // تأكيد أن الملف القديم يحمل الإجابات فعلاً (وإلا لا قيمة للاختبار).
      expect(_answerKeyPaths(oldBackupMap), isNotEmpty);
      for (final name in _forbiddenFieldNames) {
        expect(oldJson.contains('"$name"'), isTrue, reason: 'الملف القديم يجب أن يحوي $name');
      }

      // 2) القراءة لا تنهار.
      final parsed = service.parseBackup(oldJson);
      expect(parsed.documents, hasLength(1));

      // 3) الاستعادة (الاستبدال ثم الدمج): النموذج الناتج بلا أي حالة إجابة.
      for (final mode in BackupRestoreMode.values) {
        final plan = service.planRestore(
          current: <ExamDocument>[],
          backup: parsed,
          mode: mode,
        );
        expect(plan.documents, hasLength(1));
        final restored = plan.documents.single;

        _expectNoAnswerState(restored.toMap(), reason: 'النموذج المستعاد ($mode)');
        // النموذج المستعاد مطابق حرفياً للنموذج النظيف الأصلي (كل ما عدا الإجابات محفوظ).
        expect(jsonEncode(restored.toMap()), jsonEncode(original.toMap()), reason: '$mode');
        // خيارات صح/خطأ القديمة (صح/خطأ) لا تنتقل إلى النموذج الجديد.
        for (final question in restored.questions) {
          for (final branch in question.branches) {
            if (branch.content.type != QuestionType.multipleChoice) {
              expect(branch.content.options, isEmpty);
            }
          }
        }

        // 4) نسخة احتياطية جديدة من النموذج المستعاد: صفر حقول إجابة.
        final newBackup = service.createBackup(
          documents: plan.documents,
          lastOpenDocumentId: plan.lastOpenDocumentId,
          createdAt: DateTime(2026, 10, 1),
        );
        final newJson = newBackup.toJson();
        expect(_answerKeyPaths(jsonDecode(newJson)), isEmpty, reason: '$mode');
        expect(_answerKeysInRawJson(newJson), isEmpty, reason: '$mode');
        for (final name in _forbiddenFieldNames) {
          expect(newJson.contains('"$name"'), isFalse, reason: '$mode — $name');
        }
      }
    });

    test('قراءة حقول الأسئلة القديمة فرادى تتجاهلها ولا تعيد كتابتها', () {
      final item = BranchItem.fromMap(<String, dynamic>{
        'id': 'i',
        'text': 'عبارة',
        'isCorrect': true,
        'answer': 'صح',
        'trueFalseAnswer': true,
      });
      expect(item.toMap().keys.toSet().difference(_itemKeys), isEmpty);

      final option = QuestionOption.fromMap(<String, dynamic>{
        'id': 'o',
        'text': 'خيار',
        'isCorrect': true,
        'correct': true,
      });
      expect(option.toMap().keys.toSet().difference(_optionKeys), isEmpty);

      final content = BranchContent.fromMap(<String, dynamic>{
        'type': 'trueFalse',
        'text': 'نص',
        'options': <Object?>[
          <String, dynamic>{'id': 'x', 'text': 'صح', 'isCorrect': true},
        ],
        'modelAnswer': 'قديم',
        'teacherAnswer': 'قديم',
        'correctAnswer': 'قديم',
        'isTeacherVersion': true,
      });
      expect(content.options, isEmpty);
      _expectNoAnswerState(content.toMap(), reason: 'BranchContent.fromMap(legacy)');

      final question = QuestionModel.fromMap(<String, dynamic>{
        'questionNumber': 1,
        'type': 'multipleChoice',
        'branches': <Object?>[],
        'answer': 'قديم',
        'teacherVersion': true,
        'isTeacherVersion': true,
      });
      _expectNoAnswerState(question.toMap(), reason: 'QuestionModel.fromMap(legacy)');
    });

    test('خيارات الاختيار من متعدد القديمة تبقى نصاً فقط بعد إسقاط علم الصحيح', () {
      final content = BranchContent.fromMap(<String, dynamic>{
        'type': 'multipleChoice',
        'text': 'اختر',
        'options': <Object?>[
          <String, dynamic>{'id': 'a', 'text': 'الأول', 'isCorrect': true},
          <String, dynamic>{'id': 'b', 'text': 'الثاني', 'isCorrect': false},
        ],
      });
      expect(content.options.map((option) => option.text), <String>['الأول', 'الثاني']);
      _expectNoAnswerState(content.toMap(), reason: 'MCQ legacy');
    });
  });
}
