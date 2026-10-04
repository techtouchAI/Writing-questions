import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'branch_item.dart';
import 'branch_model.dart';
import 'exam_footer_model.dart';
import 'exam_header_model.dart';
import 'floating_element.dart';
import 'paper_settings.dart';
import 'question_model.dart';
import 'question_option.dart';
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

/// عنوان مجموعة نقاط: نقاط سؤال مباشرة (بلا فروع) أو نقاط فرع.
///
/// المجموعتان بنية واحدة ([BranchItem])، فيُحرَّران بالمسار الواحد نفسه في
/// المتحكم والواجهة بدل تكرار كل عملية مرتين.
class PointsOwner {
  const PointsOwner._(this.questionIndex, this.branchIndex);

  /// نقاط السؤال المباشرة للسؤال [questionIndex].
  const PointsOwner.question(int questionIndex) : this._(questionIndex, null);

  /// نقاط الفرع [ref].
  factory PointsOwner.branch(BranchRef ref) =>
      PointsOwner._(ref.questionIndex, ref.branchIndex);

  final int questionIndex;

  /// فهرس الفرع (`null` = نقاط السؤال المباشرة).
  final int? branchIndex;

  bool get isBranch => branchIndex != null;

  @override
  bool operator ==(Object other) =>
      other is PointsOwner &&
      other.questionIndex == questionIndex &&
      other.branchIndex == branchIndex;

  @override
  int get hashCode => Object.hash(questionIndex, branchIndex);

  @override
  String toString() => 'PointsOwner(q=$questionIndex, b=$branchIndex)';
}

/// نموذج الامتحان الكامل (جذر شجرة منشئ ورقة الأسئلة).
///
/// - [header]: بيانات الترويسة ذات الأعمدة الثلاثة (مدخلات منظّمة).
/// - [questions]: الأسئلة بترتيبها؛ [QuestionModel.questionNumber] يُعاد
///   ضبطه من الفهرس (1..n) عبر [normalized] عند تفعيل الترقيم التلقائي.
/// - [footer]: التذييل (عبارة ختامية + توقيع أو توقيعان) في آخر صفحة.
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
    ExamFooterModel? footer,
    List<QuestionModel>? questions,
    List<FloatingElement>? floatingElements,
    DateTime? createdAt,
    DateTime? updatedAt,
    PaperSettings? settings,
  })  : id = id ?? const Uuid().v4(),
        footer = footer ?? const ExamFooterModel(),
        settings = settings ?? const PaperSettings(),
        questions = List<QuestionModel>.unmodifiable(
          _renumber(
            questions ?? const <QuestionModel>[],
            auto: settings?.autoNumberQuestions ?? true,
          ),
        ),
        floatingElements = List<FloatingElement>.unmodifiable(
          floatingElements ?? const <FloatingElement>[],
        ),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final ExamHeaderModel header;

  /// تذييل الورقة (يُطبع في أسفل آخر صفحة فقط).
  final ExamFooterModel footer;
  final List<QuestionModel> questions;

  /// عناصر حرة على مستوى المستند (لا يملكها سؤال أو فرع).
  ///
  /// تبقى بعض المرفقات القديمة في قوائم السؤال/الفرع للتوافق مع الملفات
  /// المحفوظة سابقاً؛ العناصر الجديدة تُسجّل هنا ويُستخدم [pageIndex] لتحديد
  /// صفحتها، لذلك لا يؤثر تحريكها على ارتفاع السؤال أو تقسيم الصفحات.
  final List<FloatingElement> floatingElements;

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

  /// التسمية المعروضة للسؤال: ما كتبه المدرس إن وُجد، وإلا من نمط التسمية
  /// العام (رسمي «السؤال الأول» أو مختصر «س1») — بنسق أرقام الورقة.
  String displayQuestionLabel(QuestionModel question) {
    final manual = question.numberOverride?.trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }
    return autoQuestionLabel(question);
  }

  /// التسمية التلقائية للسؤال (دون اليدوية) — تُستخدم تلميحاً في محرر التسمية.
  String autoQuestionLabel(QuestionModel question) {
    if (settings.questionLabelStyle == QuestionLabelStyle.compact) {
      if (layout.isLtr) {
        return 'Q${question.questionNumber}';
      }
      return 'س${formatNumber(question.questionNumber)}';
    }
    return layout.questionLabel(question.questionNumber);
  }

  /// التسمية التلقائية للفرع من فهرسه (دون اليدوية).
  String autoBranchLabel(int branchIndex) => layout.branchLabel(branchIndex);

  /// التسمية المعروضة للفرع: اليدوية إن ثُبّتت، وإلا من الفهرس.
  String displayBranchLabel(int questionIndex, int branchIndex) {
    final branch = questions[questionIndex].branches[branchIndex];
    final manual = branch.labelOverride?.trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }
    return layout.branchLabel(branchIndex);
  }

  /// الترقيم التلقائي للنقطة من فهرسها (1-، 2-...) بنسق أرقام الورقة.
  String autoItemLabel(int itemIndex) => '${formatNumber(itemIndex + 1)}-';

  /// الترقيم المعروض للنقطة: المخصص حرفياً إن ثُبّت (ولو فارغاً)،
  /// وإلا التلقائي من الفهرس. لا يعاد ترقيم المخصص أبداً.
  String displayItemLabel(BranchItem item, int itemIndex) =>
      item.labelOverride ?? autoItemLabel(itemIndex);

  /// التسمية التلقائية للخيار من فهرسه (( أ )، ( ب )...).
  String autoOptionLabel(int optionIndex) => '( ${layout.branchLabel(optionIndex)} )';

  /// التسمية المعروضة للخيار: المخصصة حرفياً إن ثُبّتت (ولو فارغة)،
  /// وإلا التلقائية من الفهرس. لا يعاد ترقيم المخصصة أبداً.
  String displayOptionLabel(QuestionOption option, int optionIndex) =>
      option.labelOverride ?? autoOptionLabel(optionIndex);

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
    return localizeDigits(text);
  }

  /// يحوّل كل الأرقام داخل [text] (لاتينية أو مشرقية) إلى نسق أرقام الورقة.
  ///
  /// تُطبَّق على قيم الترويسة والتذييل فيطبع العام «٢٠٢٦/٢٠٢٧» أو «2026/2027»
  /// بحسب إعداد «نسق الأرقام» أياً كانت طريقة كتابة المدرس له.
  String localizeDigits(String text) {
    return usesArabicIndicNumerals
        ? SubjectLayoutTemplate.toArabicIndic(SubjectLayoutTemplate.toLatinDigits(text))
        : SubjectLayoutTemplate.toLatinDigits(text);
  }

  QuestionModel? questionById(String id) {
    for (final question in questions) {
      if (question.id == id) {
        return question;
      }
    }
    return null;
  }

  FloatingElement? floatingElementById(String id) {
    for (final element in floatingElements) {
      if (element.id == id) {
        return element;
      }
    }
    // Older documents store owned floats on their question/branch instead of
    // in the document-level collection. Renderers still resolve by the stable
    // float ID, so include those legacy locations as source data too.
    for (final question in questions) {
      for (final element in question.attachments) {
        if (element.id == id) return element;
      }
      for (final branch in question.branches) {
        for (final element in branch.attachments) {
          if (element.id == id) return element;
        }
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

  /// هل عنوان المجموعة [owner] موجود في النموذج الحالي؟
  bool containsOwner(PointsOwner owner) {
    if (owner.questionIndex < 0 || owner.questionIndex >= questions.length) {
      return false;
    }
    final branchIndex = owner.branchIndex;
    if (branchIndex == null) {
      return true;
    }
    return branchIndex >= 0 &&
        branchIndex < questions[owner.questionIndex].branches.length;
  }

  /// نقاط المجموعة [owner] (يجب أن يكون موجوداً: انظر [containsOwner]).
  List<BranchItem> pointsOf(PointsOwner owner) {
    final question = questions[owner.questionIndex];
    final branchIndex = owner.branchIndex;
    return branchIndex == null
        ? question.items
        : question.branches[branchIndex].content.items;
  }

  /// نسخة باستبدال نقاط المجموعة [owner] بـ[points].
  ExamDocument withPoints(PointsOwner owner, List<BranchItem> points) {
    final question = questions[owner.questionIndex];
    final branchIndex = owner.branchIndex;
    if (branchIndex == null) {
      return withQuestionAt(owner.questionIndex, question.copyWith(items: points));
    }
    final branch = question.branches[branchIndex];
    return withQuestionAt(
      owner.questionIndex,
      question.withBranchAt(
        branchIndex,
        branch.copyWith(content: branch.content.copyWith(items: points)),
      ),
    );
  }

  ExamDocument copyWith({
    String? name,
    ExamHeaderModel? header,
    ExamFooterModel? footer,
    List<QuestionModel>? questions,
    List<FloatingElement>? floatingElements,
    DateTime? updatedAt,
    PaperSettings? settings,
  }) {
    return ExamDocument(
      id: id,
      name: name ?? this.name,
      header: header ?? this.header,
      footer: footer ?? this.footer,
      questions: questions ?? this.questions,
      floatingElements: floatingElements ?? this.floatingElements,
      createdAt: createdAt,
      // يُحفظ الطابع الزمني ما لم يُمرَّر وقت جديد صراحةً — وإلا خفّ كل
      // copyWith/normalized على updatedAt وانتقصت مطابقة التراجع الحرفي.
      updatedAt: updatedAt ?? this.updatedAt,
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
    final source = questions[index];
    final duplicate = source.duplicated(questionNumber: source.questionNumber);
    final duplicateBranches = <BranchModel>[];
    for (var branchIndex = 0; branchIndex < source.branches.length; branchIndex++) {
      final originalBranch = source.branches[branchIndex];
      final copiedBranch = duplicate.branches[branchIndex];
      duplicateBranches.add(
        copiedBranch.copyWith(
          attachments: _duplicatedLegacyAttachments(
            originalBranch.attachments,
            copiedBranch.attachments,
          ),
        ),
      );
    }
    final questionCopy = duplicate.copyWith(
      attachments: _duplicatedLegacyAttachments(source.attachments, duplicate.attachments),
      branches: duplicateBranches,
    );
    final updated = List<QuestionModel>.of(questions)..insert(index + 1, questionCopy);
    return copyWith(questions: updated);
  }

  /// Document-level elements are shared by the document; compatibility mirrors
  /// must not become new legacy attachments when a question/branch is duplicated.
  List<FloatingElement> _duplicatedLegacyAttachments(
    List<FloatingElement> original,
    List<FloatingElement> copies,
  ) {
    final globalIds = floatingElements.map((element) => element.id).toSet();
    return <FloatingElement>[
      for (var index = 0; index < original.length; index++)
        if (!globalIds.contains(original[index].id)) copies[index],
    ];
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
    final question = questions[ref.questionIndex];
    final sourceBranch = question.branches[ref.branchIndex];
    final duplicatedQuestion = question.withBranchDuplicated(ref.branchIndex);
    final copyIndex = ref.branchIndex + 1;
    final copiedBranch = duplicatedQuestion.branches[copyIndex];
    return withQuestionAt(
      ref.questionIndex,
      duplicatedQuestion.withBranchAt(
        copyIndex,
        copiedBranch.copyWith(
          attachments: _duplicatedLegacyAttachments(
            sourceBranch.attachments,
            copiedBranch.attachments,
          ),
        ),
      ),
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
    final floatingCopies = <String, FloatingElement>{
      for (final element in floatingElements) element.id: element.duplicated(),
    };
    final duplicateQuestions = <QuestionModel>[];
    for (final question in questions) {
      final duplicate = question.duplicated(questionNumber: question.questionNumber);
      final questionAttachments = List<FloatingElement>.of(duplicate.attachments);
      for (var index = 0; index < question.attachments.length; index++) {
        final floatingCopy = floatingCopies[question.attachments[index].id];
        if (floatingCopy != null) {
          questionAttachments[index] = floatingCopy;
        }
      }
      final branches = List<BranchModel>.of(duplicate.branches);
      for (var branchIndex = 0; branchIndex < question.branches.length; branchIndex++) {
        final originalBranch = question.branches[branchIndex];
        final duplicateBranch = branches[branchIndex];
        final branchAttachments = List<FloatingElement>.of(duplicateBranch.attachments);
        for (var index = 0; index < originalBranch.attachments.length; index++) {
          final floatingCopy = floatingCopies[originalBranch.attachments[index].id];
          if (floatingCopy != null) {
            branchAttachments[index] = floatingCopy;
          }
        }
        branches[branchIndex] =
            duplicateBranch.copyWith(attachments: branchAttachments);
      }
      duplicateQuestions.add(
        duplicate.copyWith(attachments: questionAttachments, branches: branches),
      );
    }
    return ExamDocument(
      name: (name == null || name.trim().isEmpty) ? '${this.name} (نسخة)' : name.trim(),
      // الترويسة والتذييل كائنان غير قابلين للتغيير فيُشارَكان بلا نسخ.
      header: header,
      footer: footer,
      questions: duplicateQuestions,
      floatingElements: floatingCopies.values.toList(growable: false),
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
      'footer': footer.toMap(),
      'questions': questions.map((question) => question.toMap()).toList(growable: false),
      if (floatingElements.isNotEmpty)
        'floatingElements':
            floatingElements.map((element) => element.toMap()).toList(growable: false),
      'settings': settings.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// يقرأ نموذجاً **بشكل صارم** في بنيته؛ أي سؤال تالف يرمي [FormatException]
  /// ليُعزل السجل كاملاً بواسطة `StorageService`. الحقول الاختيارية (التذييل/
  /// الإعدادات/الطابع الزمني) متسامحة وتأخذ قيمها الافتراضية عند غيابها.
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
    final rawFloatingElements = map['floatingElements'];
    if (rawFloatingElements != null && rawFloatingElements is! List) {
      throw const FormatException('ExamDocument: العناصر الحرة يجب أن تكون قائمة.');
    }
    final floatingElements = <FloatingElement>[];
    final floatingElementIds = <String>{};
    for (final entry in (rawFloatingElements as List?) ?? const <Object?>[]) {
      if (entry is! Map) {
        throw const FormatException('ExamDocument: عنصر حر يجب أن يكون خريطة.');
      }
      final element = FloatingElement.fromMap(Map<String, dynamic>.from(entry));
      if (floatingElementIds.add(element.id)) {
        floatingElements.add(element);
      }
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
      footer: ExamFooterModel.fromValue(map['footer']),
      questions: questions,
      floatingElements: floatingElements,
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
