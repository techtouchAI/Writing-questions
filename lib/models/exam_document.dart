import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'branch_model.dart';
import 'exam.dart';
import 'exam_header.dart';
import 'exam_header_model.dart';
import 'main_question.dart';
import 'question_branch.dart';
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

/// نموذج الامتحان الوزاري الكامل (جذر شجرة المعالج المتسلسل).
///
/// - [header]: الترويسة الوزارية (3 أعمدة × 3 أسطر).
/// - [questions]: الأسئلة بترتيبها الهيكلي؛ [QuestionModel.questionNumber]
///   يُعاد ضبطه دائماً من الفهرس (1..n) عبر [normalized].
/// - قالب التنسيق يُشتق من مادة الترويسة ([layout]).
class ExamDocument {
  ExamDocument({
    String? id,
    required this.name,
    required this.header,
    List<QuestionModel>? questions,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        questions = List<QuestionModel>.unmodifiable(
          _renumber(questions ?? const <QuestionModel>[]),
        ),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final ExamHeaderModel header;
  final List<QuestionModel> questions;
  final DateTime createdAt;

  SubjectLayoutTemplate get layout => header.layoutTemplate;

  double get totalMarks =>
      questions.fold<double>(0, (sum, question) => sum + question.marks);

  /// نسخة بأرقام أسئلة متتالية 1..n (يُستدعى بعد كل حذف/إدراج).
  ExamDocument get normalized => copyWith(questions: questions);

  QuestionModel? questionById(String id) {
    for (final question in questions) {
      if (question.id == id) {
        return question;
      }
    }
    return null;
  }

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
  }) {
    return ExamDocument(
      id: id,
      name: name ?? this.name,
      header: header ?? this.header,
      questions: questions ?? this.questions,
      createdAt: createdAt,
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

  /// تحويل للنموذج القديم ([Exam]) لإعادة استخدام التصدير والتخزين الحاليين.
  ///
  /// كل فرع يتحوّل إلى [QuestionBranch]، ونوع السؤال الرئيسي يُؤخذ من الفرع
  /// الأول (النموذج القديم يحمل نوعاً واحداً لكل سؤال).
  Exam toLegacyExam() {
    final legacyQuestions = <MainQuestion>[
      for (final question in questions)
        MainQuestion(
          id: question.id,
          title: layout.questionLabel(question.questionNumber),
          type: question.branches.first.content.type,
          subject: header.subject,
          category: question.category,
          branches: <QuestionBranch>[
            for (final branch in question.branches)
              QuestionBranch(
                id: branch.id,
                text: branch.content.text,
                marks: branch.marks,
              ),
          ],
          options: question.branches.first.content.options,
          modelAnswer: question.branches.first.content.modelAnswer,
        ),
    ];
    return Exam(
      id: id,
      name: name,
      header: ExamHeader(
        institutionName: header.center.lines.first,
        title: header.center.lines[1],
        subject: header.subject,
        gradeStage: header.right.lines[2],
        duration: header.left.lines.first,
        generalInstructions: header.instructions,
      ),
      mainQuestions: legacyQuestions,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'header': header.toMap(),
      'questions': questions.map((question) => question.toMap()).toList(growable: false),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// يقرأ نموذجاً **بشكل صارم**؛ أي سؤال تالف يرمي [FormatException] ليُعزل
  /// السجل كاملاً بواسطة `StorageService`.
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
    return ExamDocument(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      name: rawName == null || rawName.isEmpty ? 'نموذج غير معنون' : rawName,
      header: ExamHeaderModel.fromMap(Map<String, dynamic>.from(rawHeader)),
      questions: questions,
      createdAt: rawCreated is String ? DateTime.tryParse(rawCreated) : null,
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

  static List<QuestionModel> _renumber(List<QuestionModel> source) {
    return <QuestionModel>[
      for (var index = 0; index < source.length; index++)
        source[index].questionNumber == index + 1
            ? source[index]
            : source[index].copyWith(questionNumber: index + 1),
    ];
  }
}
