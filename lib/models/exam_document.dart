import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'branch_model.dart';
import 'exam_header_model.dart';
import 'paper_settings.dart';
import 'question_model.dart';
import 'subject_layout.dart';

/// مرجع موضعي لفرع داخل النموذج: (فهرس السؤال، فهرس الفرع).
///
/// يُستخدم في السحب والإفلات: المرجع يشير إلى **الخانة الهيكلية** (السؤال
/// الأول - فرع أ) وليس إلى المحتوى، ولذلك يبقى صالحاً بعد التبديل.
class BranchRef {
  const BranchRef({required this.questionIndex, required this.branchIndex});

  final int questionIndex;
  final int branchIndex;

  @override
  bool operator ==(Object other) =>
      other is BranchRef &&
      other.questionIndex == questionIndex &&
      other.branchIndex == branchIndex;

  @override
  int get hashCode => Object.hash(questionIndex, branchIndex);

  @override
  String toString() => 'BranchRef(q=$questionIndex, b=$branchIndex)';
}

/// نموذج الامتحان الكامل (جذر شجرة منشئ ورقة الأسئلة).
///
/// - [header]: الترويسة (3 أعمدة × 3 أسطر + عنوان + ملاحظات + تنسيق).
/// - [questions]: الأسئلة بترتيبها؛ [QuestionModel.questionNumber] يُعاد
///   ضبطه من الفهرس (1..n) عبر [normalized] عند تفعيل الترقيم التلقائي.
/// - [settings]: إعدادات الورقة (ترقيم/أرقام/هوامش/خط افتراضي/إطارات).
/// - قالب التنسيق يُشتق من مادة الترويسة ([layout]).
///
/// المدرس حر تماماً: لا حد لعدد الأسئلة أو الفروع أو النقاط، ولا نوع
/// مفروض على أي مستوى — التطبيق أدوات تحرير فقط.
class ExamDocument {
  ExamDocument({
    String? id,
    required this.name,
    required this.header,
    List<QuestionModel>? questions,
    DateTime? createdAt,
    DateTime? updatedAt,
    PaperSettings? settings,
  })  : id = id ?? const Uuid().v4(),
        settings = settings ?? const PaperSettings(),
        questions = List<QuestionModel>.unmodifiable(
          _renumber(
            questions ?? const <QuestionModel>[],
            auto: settings?.autoNumberQuestions ?? true,
          ),
        ),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final ExamHeaderModel header;
  final List<QuestionModel> questions;
  final DateTime createdAt;

  /// آخر تعديل (يُحدَّث عند كل حفظ).
  final DateTime updatedAt;

  /// إعدادات الورقة (الترقيم/الأرقام/الهوامش/الخط/الإطارات).
  final PaperSettings settings;

  SubjectLayoutTemplate get layout => header.layoutTemplate;

  double get totalMarks =>
      questions.fold<double>(0, (sum, question) => sum + question.marks);

  /// عدد الفروع الكلي في الورقة (لشاشة المراجعة).
  int get totalBranches =>
      questions.fold<int>(0, (sum, question) => sum + question.branches.length);

  /// نسخة بأرقام أسئلة متتالية 1..n (يُستدعى بعد كل حذف/إدراج) — فقط عند
  /// تفعيل الترقيم التلقائي، وإلا تُحفظ الأرقام اليدوية كما هي.
  ExamDocument get normalized => copyWith(questions: questions);

  /// التسمية المعروضة للسؤال: اليدوية إن ثُبّتت، وإلا من قالب المادة.
  String displayQuestionLabel(QuestionModel question) {
    final manual = question.numberOverride?.trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }
    return layout.questionLabel(question.questionNumber);
  }

  /// التسمية المعروضة للفرع: اليدوية إن ثُبّتت، وإلا من الفهرس.
  String displayBranchLabel(int questionIndex, int branchIndex) {
    final branch = questions[questionIndex].branches[branchIndex];
    final manual = branch.labelOverride?.trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }
    return layout.branchLabel(branchIndex);
  }

  /// هل تُعرض الأرقام بالمشرقية؟ (إعداد الورقة يتقدم على قالب المادة).
  bool get usesArabicIndicNumerals {
    switch (settings.numerals) {
      case PaperNumerals.arabicIndic:
        return true;
      case PaperNumerals.latin:
        return false;
      case PaperNumerals.auto:
        return layout.usesArabicIndicNumerals;
    }
  }

  /// يُنسّق عدداً وفق نسق أرقام الورقة الفعلي.
  String formatNumber(num value) {
    final text = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
    return usesArabicIndicNumerals ? SubjectLayoutTemplate.toArabicIndic(text) : text;
  }

  QuestionModel? questionById(String id) {
    for (final question in questions) {
      if (question.id == id) {
        return question;
      }
    }
    return null;
  }

  int indexOfQuestion(String id) => questions.indexWhere((question) => question.id == id);

  BranchModel branchAt(BranchRef ref) =>
      questions[ref.questionIndex].branches[ref.branchIndex];

  bool containsRef(BranchRef ref) {
    if (ref.questionIndex < 0 || ref.questionIndex >= questions.length) {
      return false;
    }
    final branches = questions[ref.questionIndex].branches;
    return ref.branchIndex >= 0 && ref.branchIndex < branches.length;
  }

  ExamDocument copyWith({
    String? name,
    ExamHeaderModel? header,
    List<QuestionModel>? questions,
    DateTime? updatedAt,
    PaperSettings? settings,
  }) {
    return ExamDocument(
      id: id,
      name: name ?? this.name,
      header: header ?? this.header,
      questions: questions ?? this.questions,
      createdAt: createdAt,
      updatedAt: updatedAt,
      settings: settings ?? this.settings,
    );
  }

  /// نسخة مع استبدال السؤال في الموضع [index].
  ExamDocument withQuestionAt(int index, QuestionModel question) {
    RangeError.checkValidIndex(index, questions, 'index');
    final updated = List<QuestionModel>.of(questions);
    updated[index] = question;
    return copyWith(questions: updated);
  }

  ExamDocument withQuestionAdded([QuestionModel? question]) {
    return copyWith(
      questions: <QuestionModel>[
        ...questions,
        question ?? QuestionModel(questionNumber: questions.length + 1),
      ],
    );
  }

  ExamDocument withQuestionRemoved(int index) {
    RangeError.checkValidIndex(index, questions, 'index');
    final updated = List<QuestionModel>.of(questions)..removeAt(index);
    return copyWith(questions: updated);
  }

  /// ينقل سؤالاً كاملاً (وحدة لا تتجزأ: نص/فروع/نقاط/صور/أشكال/درجات/
  /// فواصل) من [from] إلى [to]، ثم يُعاد الترقيم حسب الإعداد.
  ExamDocument withQuestionMoved(int from, int to) {
    RangeError.checkValidIndex(from, questions, 'from');
    final updated = List<QuestionModel>.of(questions);
    final question = updated.removeAt(from);
    updated.insert(to.clamp(0, updated.length), question);
    return copyWith(questions: updated);
  }

  /// ينسخ سؤالاً كاملاً (كل المحتوى والتنسيق) بعد الأصل مباشرة.
  ExamDocument withQuestionDuplicated(int index) {
    RangeError.checkValidIndex(index, questions, 'index');
    final updated = List<QuestionModel>.of(questions);
    updated.insert(
      index + 1,
      questions[index].duplicated(questionNumber: questions[index].questionNumber),
    );
    return copyWith(questions: updated);
  }

  /// ينقل فرعاً داخل سؤاله من [from] إلى [to] (المحتوى كما هو، الموضع فقط).
  ExamDocument withBranchMoved(int questionIndex, int from, int to) {
    RangeError.checkValidIndex(questionIndex, questions, 'questionIndex');
    return withQuestionAt(
      questionIndex,
      questions[questionIndex].withBranchMoved(from, to),
    );
  }

  /// ينسخ فرعاً كاملاً بعد الأصل مباشرة داخل سؤاله.
  ExamDocument withBranchDuplicated(BranchRef ref) {
    if (!containsRef(ref)) {
      return this;
    }
    return withQuestionAt(
      ref.questionIndex,
      questions[ref.questionIndex].withBranchDuplicated(ref.branchIndex),
    );
  }

  /// نسخة مع استبدال الفرع عند [ref].
  ExamDocument withBranchAt(BranchRef ref, BranchModel branch) {
    return withQuestionAt(
      ref.questionIndex,
      questions[ref.questionIndex].withBranchAt(ref.branchIndex, branch),
    );
  }

  /// **القاعدة الذهبية للسحب والإفلات**: يبدّل [BranchModel.content]
  /// و[BranchModel.marks] فقط بين الخانتين [from] و[to].
  ///
  /// الهيكل الرقمي (السؤال الأول يبقى أولاً، الفرع أ يبقى أ) والمعرّفات
  /// والمرفقات المثبّتة على الخانة تبقى كما هي؛ المحتوى وحده ينتقل.
  ExamDocument swapBranchContent(BranchRef from, BranchRef to) {
    if (from == to || !containsRef(from) || !containsRef(to)) {
      return this;
    }
    final source = branchAt(from);
    final target = branchAt(to);
    final sourceUpdated = source.copyWith(
      content: target.content,
      marks: target.marks,
    );
    final targetUpdated = target.copyWith(
      content: source.content,
      marks: source.marks,
    );
    return withBranchAt(from, sourceUpdated).withBranchAt(to, targetUpdated);
  }

  /// نسخة باسم جديد (لإعادة التسمية في المكتبة).
  ExamDocument renamed(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    return copyWith(name: trimmed);
  }

  /// نسخة كاملة بهوية جديدة (لـ«نسخ الورقة» في المكتبة).
  ExamDocument duplicated({String? name}) {
    return ExamDocument(
      name: (name == null || name.trim().isEmpty) ? '${this.name} (نسخة)' : name.trim(),
      header: ExamHeaderModel(
        subject: header.subject,
        right: HeaderColumn(header.right.toList()),
        center: HeaderColumn(header.center.toList()),
        left: HeaderColumn(header.left.toList()),
        instructions: header.instructions,
        title: header.title,
        notes: header.notes,
        style: header.style,
      ),
      questions: <QuestionModel>[
        for (final question in questions)
          question.duplicated(questionNumber: question.questionNumber),
      ],
      settings: settings,
    );
  }

  /// نسخة محدّثة الطابع الزمني (تُستدعى عند الحفظ/التصدير).
  ExamDocument touched() => copyWith(updatedAt: DateTime.now());

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'header': header.toMap(),
      'questions': questions.map((question) => question.toMap()).toList(growable: false),
      'settings': settings.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// يقرأ نموذجاً **بشكل صارم**؛ أي سؤال تالف يرمي [FormatException] ليُعزل
  /// السجل كاملاً بواسطة `StorageService`. الحقول الجديدة (الإعدادات/
  /// الطابع الزمني) متسامحة لتبقى النماذج القديمة صالحة.
  factory ExamDocument.fromMap(Map<String, dynamic> map) {
    final rawHeader = map['header'];
    if (rawHeader is! Map) {
      throw const FormatException('ExamDocument: الترويسة (header) مفقودة.');
    }
    final rawQuestions = map['questions'];
    if (rawQuestions != null && rawQuestions is! List) {
      throw const FormatException('ExamDocument: حقل الأسئلة يجب أن يكون قائمة.');
    }
    final questions = <QuestionModel>[];
    for (final entry in (rawQuestions as List?) ?? const <Object?>[]) {
      if (entry is! Map) {
        throw const FormatException('ExamDocument: عنصر السؤال يجب أن يكون خريطة.');
      }
      questions.add(QuestionModel.fromMap(Map<String, dynamic>.from(entry)));
    }
    final rawName = map['name']?.toString().trim();
    final rawCreated = map['createdAt'];
    final rawUpdated = map['updatedAt'];
    return ExamDocument(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      name: rawName == null || rawName.isEmpty ? 'نموذج غير معنون' : rawName,
      header: ExamHeaderModel.fromMap(Map<String, dynamic>.from(rawHeader)),
      questions: questions,
      createdAt: rawCreated is String ? DateTime.tryParse(rawCreated) : null,
      updatedAt: rawUpdated is String ? DateTime.tryParse(rawUpdated) : null,
      settings: PaperSettings.fromValue(map['settings']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ExamDocument.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('ExamDocument JSON must contain an object.');
    }
    return ExamDocument.fromMap(Map<String, dynamic>.from(decoded));
  }

  /// يعيد ترقيم الأسئلة 1..n عند التفعيل، وإلا يحفظ الأرقام كما هي.
  static List<QuestionModel> _renumber(List<QuestionModel> source, {required bool auto}) {
    if (!auto) {
      return List<QuestionModel>.of(source);
    }
    return <QuestionModel>[
      for (var index = 0; index < source.length; index++)
        source[index].questionNumber == index + 1
            ? source[index]
            : source[index].copyWith(questionNumber: index + 1),
    ];
  }
}
