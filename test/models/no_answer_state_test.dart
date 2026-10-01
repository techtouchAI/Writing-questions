import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/app_backup.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
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

const Set<String> _itemKeys = <String>{
  'id',
  'text',
  'kind',
  'options',
  'marks',
  'labelOverride',
  'align',
};
const Set<String> _optionKeys = <String>{'id', 'text', 'labelOverride', 'align'};

void _expectNoAnswerState(Map<String, dynamic> map, {required String reason}) {
  expect(_answerKeyPaths(map), isEmpty, reason: reason);
  for (final name in _forbiddenFieldNames) {
    expect(jsonEncode(map).contains('"$name"'), isFalse, reason: '$reason — "$name"');
  }
}

/// نقطة من النوع [kind] (الاختيار من متعدد بثلاثة خيارات نصية).
BranchItem _pointOf(PointKind kind) {
  return BranchItem(
    kind: kind,
    text: 'نقطة ${kind.name}',
    marks: 1,
    labelOverride: kind == PointKind.plain ? 'أ)' : null,
    options: kind == PointKind.multipleChoice
        ? <QuestionOption>[
            QuestionOption(text: 'الأول'),
            QuestionOption(text: 'الثاني'),
            QuestionOption(text: 'الثالث'),
          ]
        : null,
  );
}

/// ورقة فيها كل أنواع النقاط معاً في المجموعة نفسها (سؤال + فرع).
ExamDocument _documentWithEveryKind() {
  return ExamDocument(
    id: 'doc-all-kinds',
    name: 'كل الأنواع',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية', now: DateTime(2026, 10, 1)),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        statement: 'سؤال مختلط',
        items: <BranchItem>[for (final kind in PointKind.values) _pointOf(kind)],
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              statement: 'فرع مختلط',
              items: <BranchItem>[for (final kind in PointKind.values) _pointOf(kind)],
            ),
            marks: 3,
          ),
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
      final map = item as Map<String, dynamic>;
      pollute(map, <String>[
        'isCorrect',
        'answer',
        'trueFalseAnswer',
        'correctAnswer',
      ]);
      for (final rawOption in (map['options'] as List?) ?? const <Object?>[]) {
        pollute(rawOption as Map<String, dynamic>, <String>['isCorrect', 'correct', 'answer']);
      }
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
      }
    }
  }
  return backupMap;
}

void main() {
  group('J) كل نوع نقطة: JSON/النموذج الناتج بلا حالة إجابة', () {
    for (final kind in PointKind.values) {
      test('${kind.name}: سؤال مباشر + فرع + نقاط (+ خيارات) بلا أي حقل إجابة', () {
        final question = QuestionModel(
          questionNumber: 1,
          statement: 'سؤال ${kind.name}',
          items: <BranchItem>[_pointOf(kind)],
          branches: <BranchModel>[
            BranchModel(content: BranchContent(items: <BranchItem>[_pointOf(kind)]), marks: 2),
          ],
        );
        final map = question.toMap();

        _expectNoAnswerState(map, reason: 'QuestionModel(${kind.name})');
        expect(_answerKeysInRawJson(jsonEncode(map)), isEmpty);

        // القائمة البيضاء: النقطة نوع/نص/خيارات/درجة/تسمية/محاذاة فقط.
        final points = <BranchItem>[
          ...question.items,
          ...question.branches.single.content.items,
        ];
        for (final point in points) {
          expect(point.toMap().keys.toSet().difference(_itemKeys), isEmpty);
          for (final option in point.options) {
            expect(option.toMap().keys.toSet().difference(_optionKeys), isEmpty);
          }
          // الخيارات للاختيار من متعدد وحده، ونصية فقط.
          expect(
            point.options.length,
            kind == PointKind.multipleChoice ? 3 : 0,
          );
        }
      });

      test('${kind.name}: إنشاؤه من المحرر (ExamWizardController) بلا حالة إجابة', () {
        final controller = ExamWizardController();
        controller.addBranch(0);
        const ref = BranchRef(questionIndex: 0, branchIndex: 0);
        final owner = PointsOwner.branch(ref);
        controller.updateBranchStatement(ref, 'منطوق');
        final point = BranchItem(text: 'عبارة');
        controller.addPoint(owner, point);
        controller.updatePointKind(owner, point.id, kind);
        controller.updatePointText(owner, point.id, 'عبارة معدّلة');
        if (kind == PointKind.multipleChoice) {
          controller.updatePointOptionText(owner, point.id, 0, 'خيار');
        }

        _expectNoAnswerState(
          controller.document.toMap(),
          reason: 'ExamWizardController(${kind.name})',
        );
      });
    }

    test('ورقة فيها كل الأنواع معاً: الـ JSON الكامل بلا حقل إجابة واحد', () {
      final document = _documentWithEveryKind();
      expect(
        document.questions.single.items.map((point) => point.kind).toSet(),
        PointKind.values.toSet(),
      );
      _expectNoAnswerState(document.toMap(), reason: 'ExamDocument');
      expect(_answerKeysInRawJson(document.toJson()), isEmpty);
    });

    test('صح/خطأ: يخزّن نص العبارة ونوعها وترتيبها ودرجتها فقط — لا صح/خطأ/بلا إجابة', () {
      final item = BranchItem(kind: PointKind.trueFalse, text: 'الأرض كروية', marks: 2);
      expect(item.toMap().keys.toSet().difference(_itemKeys), isEmpty);
      expect(item.toMap()['text'], 'الأرض كروية');
      expect(item.toMap()['marks'], 2.0);
      expect(item.toMap()['kind'], 'trueFalse');
      expect(item.toMap().containsKey('options'), isFalse);

      final content = BranchContent(
        items: <BranchItem>[
          BranchItem(kind: PointKind.trueFalse, text: 'أ'),
          BranchItem(kind: PointKind.trueFalse, text: 'ب'),
        ],
      );
      final map = content.toMap();
      expect(map.keys.toSet().difference(<String>{'statement', 'body', 'items'}), isEmpty);
      expect((map['items'] as List).map((entry) => (entry as Map)['text']), <String>['أ', 'ب']);
    });

    test('اختيار من متعدد: الخيارات نصية فقط ولا خيار صحيح في النموذج', () {
      final item = BranchItem(
        kind: PointKind.multipleChoice,
        options: <QuestionOption>[QuestionOption(text: 'س'), QuestionOption(text: 'ص')],
      );
      final options = item.toMap()['options'] as List;
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
        documents: <ExamDocument>[_documentWithEveryKind()],
        lastOpenDocumentId: 'doc-all-kinds',
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
      expect(backup.totalQuestions, 1);
      expect(json.contains('نقطة multipleChoice'), isTrue);
      expect(json.contains('فرع مختلط'), isTrue);
    });

    test('النسخة المضغوطة (بلا تنسيق) بلا حقول إجابة أيضاً', () {
      final backup = AppBackup(
        createdAt: DateTime(2026, 9, 30),
        documents: <ExamDocument>[_documentWithEveryKind()],
      );
      expect(_answerKeysInRawJson(backup.toJson(pretty: false)), isEmpty);
    });
  });

  group('L) نسخة قديمة بحقول إجابة ← استعادة ← نموذج جديد ← نسخة جديدة', () {
    test('Old Backup with answer fields → restore → no answer state → new Backup has none', () {
      const service = BackupService();
      final original = _documentWithEveryKind();

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
        // الخيارات لا تبقى إلا في نقاط «اختيار من متعدد».
        for (final question in restored.questions) {
          for (final point in <BranchItem>[
            ...question.items,
            for (final branch in question.branches) ...branch.content.items,
          ]) {
            if (point.kind != PointKind.multipleChoice) {
              expect(point.options, isEmpty);
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
        'statement': 'نص',
        'items': <Object?>[
          <String, dynamic>{
            'text': 'سؤال',
            'kind': 'multipleChoice',
            'options': <Object?>[
              <String, dynamic>{'id': 'x', 'text': 'خيار', 'isCorrect': true},
            ],
          },
        ],
        'modelAnswer': 'قديم',
        'teacherAnswer': 'قديم',
        'correctAnswer': 'قديم',
        'isTeacherVersion': true,
      });
      expect(content.items.single.options.map((option) => option.text), <String>['خيار']);
      _expectNoAnswerState(content.toMap(), reason: 'BranchContent.fromMap(legacy)');

      final question = QuestionModel.fromMap(<String, dynamic>{
        'questionNumber': 1,
        'branches': <Object?>[],
        'answer': 'قديم',
        'teacherVersion': true,
        'isTeacherVersion': true,
      });
      _expectNoAnswerState(question.toMap(), reason: 'QuestionModel.fromMap(legacy)');
    });
  });
}
