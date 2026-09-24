import 'package:uuid/uuid.dart';

import 'branch_model.dart';

/// السؤال الكامل (QuestionModel): «السؤال الأول» بفروعه أ، ب، ج...
///
/// - [questionNumber] هو الرقم الهيكلي (1، 2، 3...) ويُعاد ضبطه من الترتيب
///   داخل [ExamDocument]؛ لا يتغيّر عند تبديل المحتوى بالسحب والإفلات.
/// - الدرجة الكلية = مجموع درجات الفروع آلياً.
/// - قاعدة التقسيم الورقي: السؤال **وحدة لا تتجزأ** — ينتقل كاملاً بفروعه
///   إلى الصفحة التالية إن لم يتسع في المساحة المتبقية.
class QuestionModel {
  QuestionModel({
    String? id,
    required this.questionNumber,
    List<BranchModel>? branches,
    this.category = '',
  })  : id = id ?? const Uuid().v4(),
        branches = List<BranchModel>.unmodifiable(
          branches == null || branches.isEmpty
              ? <BranchModel>[BranchModel()]
              : branches,
        ) {
    if (questionNumber < 1) {
      throw ArgumentError.value(questionNumber, 'questionNumber', 'يبدأ الترقيم من 1.');
    }
  }

  final String id;
  final int questionNumber;

  /// فروع السؤال؛ يوجد فرع واحد على الأقل دائماً (أ).
  final List<BranchModel> branches;

  /// القسم الوزاري (القواعد/الأدب/أحكام التلاوة...) — فارغ = بلا قسم.
  final String category;

  double get marks => branches.fold<double>(0, (sum, branch) => sum + branch.marks);

  QuestionModel copyWith({
    int? questionNumber,
    List<BranchModel>? branches,
    String? category,
  }) {
    return QuestionModel(
      id: id,
      questionNumber: questionNumber ?? this.questionNumber,
      branches: branches ?? this.branches,
      category: category ?? this.category,
    );
  }

  /// نسخة مع استبدال الفرع في الموضع [index].
  QuestionModel withBranchAt(int index, BranchModel branch) {
    RangeError.checkValidIndex(index, branches, 'index');
    final updated = List<BranchModel>.of(branches);
    updated[index] = branch;
    return copyWith(branches: updated);
  }

  QuestionModel withBranchAdded([BranchModel? branch]) {
    return copyWith(branches: <BranchModel>[...branches, branch ?? BranchModel()]);
  }

  /// يحذف فرعاً؛ يرفض حذف الفرع الأخير (يبقى «أ» دائماً).
  QuestionModel withBranchRemoved(int index) {
    RangeError.checkValidIndex(index, branches, 'index');
    if (branches.length == 1) {
      return this;
    }
    final updated = List<BranchModel>.of(branches)..removeAt(index);
    return copyWith(branches: updated);
  }

  int indexOfBranch(String branchId) =>
      branches.indexWhere((branch) => branch.id == branchId);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'questionNumber': questionNumber,
      'category': category,
      'branches': branches.map((branch) => branch.toMap()).toList(growable: false),
    };
  }

  /// يقرأ سؤالاً **بشكل صارم**.
  factory QuestionModel.fromMap(Map<String, dynamic> map) {
    final rawNumber = map['questionNumber'];
    final number = rawNumber is num ? rawNumber.toInt() : int.tryParse('$rawNumber');
    if (number == null || number < 1) {
      throw FormatException('QuestionModel: رقم السؤال غير صالح (${rawNumber ?? 'مفقود'}).');
    }
    final rawBranches = map['branches'];
    if (rawBranches is! List) {
      throw const FormatException('QuestionModel: حقل الفروع (branches) يجب أن يكون قائمة.');
    }
    final branches = <BranchModel>[];
    for (final entry in rawBranches) {
      if (entry is! Map) {
        throw const FormatException('QuestionModel: عنصر الفرع يجب أن يكون خريطة.');
      }
      branches.add(BranchModel.fromMap(Map<String, dynamic>.from(entry)));
    }
    return QuestionModel(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      questionNumber: number,
      category: map['category']?.toString() ?? '',
      branches: branches,
    );
  }
}
