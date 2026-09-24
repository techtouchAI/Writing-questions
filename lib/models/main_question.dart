import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'difficulty.dart';
import 'question_branch.dart';
import 'question_option.dart';
import 'question_type.dart';

export 'question_branch.dart';
export 'question_option.dart';

/// السؤال الرئيسي في ورقة الاختبار (س1، س2...) — عقدة الشجرة الهرمية.
///
/// البنية الهرمية الصارمة في هندسة محرك الأسئلة:
/// - [Exam] ← قائمة `List<MainQuestion>` (الأسئلة الرئيسية: س1، س2...).
/// - [MainQuestion] ← قائمة `List<QuestionBranch>` (الفروع: أ، ب، ج...).
///
/// قواعد صارمة لا تُكسر:
/// 1. **درجة السؤال الكلية = مجموع درجات فروعه آلياً** (انظر [marks])؛
///    لا يوجد حقل درجة مستقل قابل للتلاعب أو يُخالف مجموع الفروع.
/// 2. **تسميات الفروع (أ، ب، ج...) تُولَّد ديناميكياً من الفهرس** وقت
///    العرض والطباعة ولا تُخزَّن إطلاقاً — حتى لا تتبقّى فجوات في الترقيم
///    عند حذف فرع وسط القائمة.
/// 3. **القراءة صارمة**: أي نوع مجهول أو تركيب فروع تالف يرمي
///    [FormatException] صريحاً بدل الأسئلة الوهمية الافتراضية، ليقوم
///    [StorageService] بعزل السجل التالف دون المساس بالسجلات السليمة.
class MainQuestion {
  MainQuestion({
    String? id,
    required this.title,
    required this.type,
    this.difficulty = Difficulty.medium,
    this.subject = 'عام',
    this.topic = '',
    this.category = '',
    List<QuestionBranch>? branches,
    List<QuestionOption>? options,
    this.modelAnswer = '',
    this.explanation = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        branches = _copyBranches(branches ?? const <QuestionBranch>[]),
        options = _copyOptions(options ?? const <QuestionOption>[]),
        createdAt = createdAt ?? DateTime.now();

  final String id;

  /// عنوان/مقدمة السؤال الرئيسي (نص LaTeX مدعوم داخل $...$ أو $$...$$).
  String title;

  QuestionType type;
  Difficulty difficulty;
  String subject;
  String topic;

  /// قسم السؤال داخل المادة (القواعد/الأدب/إنشاء... مثلاً) لتقسيم ورقة الامتحان.
  String category;

  /// فروع السؤال (أ، ب، ج...)؛ التسميات تُولَّد من فهرس كل فرع في هذه
  /// القائمة وقت العرض فقط.
  List<QuestionBranch> branches;

  List<QuestionOption> options;
  String modelAnswer;
  String explanation;
  final DateTime createdAt;

  /// الدرجة الكلية للسؤال = **مجموع درجات فروعه آلياً** (roll-up).
  ///
  /// الأسئلة البسيطة بدون فروع نصية تُمثَّل بفرع واحد (نصه فارغ) تحمل
  /// الدرجة، فيبقى القانون `marks == sum(branch.marks)` صحيحاً دائماً.
  double get marks => branches.fold<double>(0, (sum, branch) => sum + branch.marks);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'type': type.name,
      'difficulty': difficulty.name,
      'subject': subject,
      'topic': topic,
      'category': category,
      'branches':
          branches.map((branch) => branch.toMap()).toList(growable: false),
      'options': options.map((option) => option.toMap()).toList(growable: false),
      'modelAnswer': modelAnswer,
      'explanation': explanation,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// يقرأ سؤالاً رئيسياً من مخزون JSON/Map **بشكل صارم**.
  ///
  /// يرمي [FormatException] عند:
  /// - نوع مجهول أو مفقود (`type`)، أو مستوى صعوبة مجهول،
  /// - `branches` ليست قائمة، أو تحتوي عنصراً ليس خريطة، أو فرعاً بدرجة تالفة،
  /// - `options` ليست قائمة من الخرائط،
  /// - درجة قديمة (`marks`) غير صالحة عند غياب الفروع.
  ///
  /// التوافق الخلفي: السجلات القديمة بلا `branches` لكن بـ`marks` تُرحَّل
  /// إلى فرع واحد يحمل الدرجة (نص فارغ) حتى لا تضيع الدرجات المخزنة.
  factory MainQuestion.fromMap(Map<String, dynamic> map) {
    final rawType = map['type'];
    if (rawType is! String) {
      throw const FormatException('MainQuestion: حقل النوع (type) مفقود أو ليس نصاً.');
    }
    final type = QuestionType.parse(rawType);

    final rawDifficulty = map['difficulty'];
    if (rawDifficulty != null && rawDifficulty is! String) {
      throw const FormatException('MainQuestion: حقل الصعوبة (difficulty) يجب أن يكون نصاً.');
    }
    final difficulty =
        rawDifficulty == null ? Difficulty.medium : Difficulty.parse(rawDifficulty as String);

    final branches = _branchesFromValue(map['branches'], legacyMarks: map['marks']);
    final options = _optionsFromValue(map['options']);

    final rawTitle = map['title'];
    if (rawTitle != null && rawTitle is! String && rawTitle is! num) {
      throw const FormatException('MainQuestion: عنوان السؤال يجب أن يكون نصاً.');
    }

    return MainQuestion(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      title: rawTitle?.toString() ?? '',
      type: type,
      difficulty: difficulty,
      subject: _nonEmptyString(map['subject']) ?? 'عام',
      topic: map['topic']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      branches: branches,
      options: options,
      modelAnswer: map['modelAnswer']?.toString() ?? '',
      explanation: map['explanation']?.toString() ?? '',
      createdAt: _dateFromValue(map['createdAt']) ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory MainQuestion.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('MainQuestion JSON must contain an object.');
    }
    return MainQuestion.fromMap(Map<String, dynamic>.from(decoded));
  }

  MainQuestion copyWith({
    String? title,
    QuestionType? type,
    Difficulty? difficulty,
    String? subject,
    String? topic,
    String? category,
    List<QuestionBranch>? branches,
    List<QuestionOption>? options,
    String? modelAnswer,
    String? explanation,
  }) {
    return MainQuestion(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      category: category ?? this.category,
      branches: branches ?? this.branches,
      options: options ?? this.options,
      modelAnswer: modelAnswer ?? this.modelAnswer,
      explanation: explanation ?? this.explanation,
      createdAt: createdAt,
    );
  }

  /// يقرأ قائمة الفروع **بشكل صارم**؛ [legacyMarks] يُستخدم فقط عند غياب
  /// مفتاح `branches` كلياً (ترحيل سجلات قديمة) ولا يُطغى أبداً على الفروع.
  static List<QuestionBranch> _branchesFromValue(
    Object? value, {
    Object? legacyMarks,
  }) {
    if (value == null) {
      // ترحيل آمن لسجلات الإصدارات القديمة: درجة بلا فروع ← فرع واحد يحملها.
      if (legacyMarks == null) {
        return <QuestionBranch>[];
      }
      final parsed = legacyMarks is num
          ? legacyMarks.toDouble()
          : double.tryParse(legacyMarks.toString());
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('MainQuestion: درجة قديمة غير صالحة ($legacyMarks).');
      }
      return <QuestionBranch>[
        QuestionBranch(text: '', marks: parsed),
      ];
    }

    if (value is! List) {
      throw const FormatException('MainQuestion: حقل الفروع (branches) يجب أن يكون قائمة.');
    }

    final branches = <QuestionBranch>[];
    for (final entry in value) {
      if (entry is! Map) {
        throw const FormatException(
          'MainQuestion: تركيب فروع تالف — عنصر الفرع يجب أن يكون خريطة.',
        );
      }
      branches.add(QuestionBranch.fromMap(Map<String, dynamic>.from(entry)));
    }
    return branches;
  }

  static List<QuestionOption> _optionsFromValue(Object? value) {
    if (value == null) {
      return <QuestionOption>[];
    }
    if (value is! List) {
      throw const FormatException('MainQuestion: حقل الخيارات (options) يجب أن يكون قائمة.');
    }

    final options = <QuestionOption>[];
    for (final entry in value) {
      if (entry is! Map) {
        throw const FormatException(
          'MainQuestion: تركيب خيارات تالف — عنصر الخيار يجب أن يكون خريطة.',
        );
      }
      options.add(QuestionOption.fromMap(Map<String, dynamic>.from(entry)));
    }
    return options;
  }

  static List<QuestionOption> _copyOptions(List<QuestionOption> source) {
    return source.map((option) => option.copyWith()).toList(growable: true);
  }

  static List<QuestionBranch> _copyBranches(List<QuestionBranch> source) {
    return source.map((branch) => branch.copyWith()).toList(growable: true);
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
