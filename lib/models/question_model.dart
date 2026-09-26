import 'package:uuid/uuid.dart';

import 'branch_model.dart';
import 'floating_element.dart';
import 'paper_divider.dart';
import 'paper_text_style.dart';

/// السؤال الكامل (QuestionModel): «السؤال الأول» بنصه وفروعه ومرفقاته.
///
/// - [questionNumber] هو الرقم الهيكلي (1، 2، 3...) ويُعاد ضبطه من الترتيب
///   داخل [ExamDocument] عند تفعيل الترقيم التلقائي.
/// - [prompt] نص السؤال الحر الذي يكتبه المدرس («أجب عن فرعين فقط:»...)
///   ويُحفظ حرفياً دون أي تفسير أو إعادة صياغة.
/// - الدرجة الكلية = مجموع درجات الفروع آلياً، ما لم يثبّت المدرس
///   [marksOverride] يدوياً.
/// - السؤال **وحدة لا تتجزأ**: ينتقل كاملاً بنصه وفروعه ونقاطه وصوره
///   وأشكاله ودرجاته وفواصله عند النقل، ولا يُقسَّم بين صفحتين.
class QuestionModel {
  QuestionModel({
    String? id,
    required this.questionNumber,
    List<BranchModel>? branches,
    this.category = '',
    this.prompt = '',
    this.marksOverride,
    this.numberOverride,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    this.showFrame = false,
    this.dividerAfter,
  })  : id = id ?? const Uuid().v4(),
        // السؤال الجديد يبدأ بلا فروع؛ تُنشأ فقط بطلب صريح من المدرس.
        branches = List<BranchModel>.unmodifiable(
          branches ?? const <BranchModel>[],
        ),
        attachments = List<FloatingElement>.unmodifiable(
          attachments ?? const <FloatingElement>[],
        ),
        style = style ?? PaperTextStyle.empty {
    if (questionNumber < 1) {
      throw ArgumentError.value(questionNumber, 'questionNumber', 'يبدأ الترقيم من 1.');
    }
    if (marksOverride != null && (!marksOverride!.isFinite || marksOverride! < 0)) {
      throw ArgumentError.value(marksOverride, 'marksOverride', 'الدرجة اليدوية غير صالحة.');
    }
  }

  final String id;
  final int questionNumber;

  /// فروع السؤال؛ فارغة افتراضياً وتُنشأ فقط بطلب صريح من المدرس.
  final List<BranchModel> branches;

  /// القسم الوزاري (القواعد/الأدب/أحكام التلاوة...) — فارغ = بلا قسم.
  final String category;

  /// نص السؤال/تعليماته كما كتبه المدرس («أجب عن فرعين فقط:»...).
  final String prompt;

  /// درجة يدوية ثابتة للسؤال (null = حساب تلقائي = مجموع الفروع).
  final double? marksOverride;

  /// ترقيم يدوي ثابت للسؤال (null = تلقائي من الترتيب).
  final String? numberOverride;

  /// صور وأشكال ومربعات نص على مستوى السؤال كاملاً.
  final List<FloatingElement> attachments;

  /// تنسيق خاص بالسؤال (يُطبق على العنوان والنص).
  final PaperTextStyle style;

  /// إطار حول السؤال كاملاً.
  final bool showFrame;

  /// فاصل بعد السؤال كاملاً.
  final PaperDivider? dividerAfter;

  /// الدرجة الفعلية: اليدوية إن ثُبّتت، وإلا مجموع درجات الفروع.
  double get marks => marksOverride ?? branches.fold<double>(0, (sum, branch) => sum + branch.marks);

  /// هل درجة السؤال محسوبة تلقائياً من الفروع؟
  bool get hasAutoMarks => marksOverride == null;

  /// هل يحمل السؤال أي محتوى مكتوب (نص/فروع/نقاط)؟
  bool get hasContent {
    if (prompt.trim().isNotEmpty) {
      return true;
    }
    return branches.any((branch) => !branch.content.isEmpty);
  }

  QuestionModel copyWith({
    int? questionNumber,
    List<BranchModel>? branches,
    String? category,
    String? prompt,
    double? Function()? marksOverride,
    String? Function()? numberOverride,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    bool? showFrame,
    PaperDivider? Function()? dividerAfter,
  }) {
    return QuestionModel(
      id: id,
      questionNumber: questionNumber ?? this.questionNumber,
      branches: branches ?? this.branches,
      category: category ?? this.category,
      prompt: prompt ?? this.prompt,
      marksOverride: marksOverride != null ? marksOverride() : this.marksOverride,
      numberOverride: numberOverride != null ? numberOverride() : this.numberOverride,
      attachments: attachments ?? this.attachments,
      style: style ?? this.style,
      showFrame: showFrame ?? this.showFrame,
      dividerAfter: dividerAfter != null ? dividerAfter() : this.dividerAfter,
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
  /// يحذف فرعاً؛ ويُسمح بسؤال بلا فروع (يُنشأ الفرع عند الطلب الصريح).
  QuestionModel withBranchRemoved(int index) {
    RangeError.checkValidIndex(index, branches, 'index');
    final updated = List<BranchModel>.of(branches)..removeAt(index);
    return copyWith(branches: updated);
  }

  /// ينقل فرعاً من [from] إلى [to] مع بقاء محتواه كما هو (يتغير موضعه فقط).
  QuestionModel withBranchMoved(int from, int to) {
    RangeError.checkValidIndex(from, branches, 'from');
    final updated = List<BranchModel>.of(branches);
    final branch = updated.removeAt(from);
    updated.insert(to.clamp(0, updated.length), branch);
    return copyWith(branches: updated);
  }

  /// ينسخ فرعاً كاملاً (محتوى/نقاط/صور/أشكال/درجات/تنسيق) بعد الأصل مباشرة.
  QuestionModel withBranchDuplicated(int index) {
    RangeError.checkValidIndex(index, branches, 'index');
    final updated = List<BranchModel>.of(branches);
    updated.insert(index + 1, branches[index].duplicated());
    return copyWith(branches: updated);
  }

  int indexOfBranch(String branchId) =>
      branches.indexWhere((branch) => branch.id == branchId);

  /// نسخة بهوية جديدة وهويات فروع/مرفقات جديدة (للنسخ/التكرار).
  QuestionModel duplicated({required int questionNumber}) {
    return QuestionModel(
      questionNumber: questionNumber,
      branches: branches.map((branch) => branch.duplicated()).toList(),
      category: category,
      prompt: prompt,
      marksOverride: marksOverride,
      attachments: attachments.map((element) => element.duplicated()).toList(),
      style: style,
      showFrame: showFrame,
      dividerAfter: dividerAfter,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'questionNumber': questionNumber,
      'category': category,
      'branches': branches.map((branch) => branch.toMap()).toList(growable: false),
      if (prompt.isNotEmpty) 'prompt': prompt,
      if (marksOverride != null) 'marksOverride': marksOverride,
      if (numberOverride != null && numberOverride!.trim().isNotEmpty)
        'numberOverride': numberOverride,
      if (attachments.isNotEmpty)
        'attachments':
            attachments.map((element) => element.toMap()).toList(growable: false),
      if (style.isNotEmpty) 'style': style.toMap(),
      if (showFrame) 'showFrame': true,
      if (dividerAfter != null) 'dividerAfter': dividerAfter!.toMap(),
    };
  }

  /// يقرأ سؤالاً **بشكل صارم** في الحقول الجوهرية؛ الحقول الجديدة متسامحة.
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
    final rawAttachments = map['attachments'];
    if (rawAttachments != null && rawAttachments is! List) {
      throw const FormatException('QuestionModel: المرفقات يجب أن تكون قائمة.');
    }
    final attachments = <FloatingElement>[];
    for (final entry in (rawAttachments as List?) ?? const <Object?>[]) {
      if (entry is! Map) {
        throw const FormatException('QuestionModel: عنصر المرفق يجب أن يكون خريطة.');
      }
      attachments.add(FloatingElement.fromMap(Map<String, dynamic>.from(entry)));
    }
    final rawOverride = map['marksOverride'];
    double? marksOverride;
    if (rawOverride != null) {
      final parsed = rawOverride is num
          ? rawOverride.toDouble()
          : double.tryParse(rawOverride.toString());
      if (parsed != null && parsed.isFinite && parsed >= 0) {
        marksOverride = parsed;
      }
    }
    final rawNumberOverride = map['numberOverride']?.toString().trim();
    return QuestionModel(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      questionNumber: number,
      category: map['category']?.toString() ?? '',
      branches: branches,
      prompt: map['prompt']?.toString() ?? '',
      marksOverride: marksOverride,
      numberOverride:
          rawNumberOverride == null || rawNumberOverride.isEmpty ? null : rawNumberOverride,
      attachments: attachments,
      style: PaperTextStyle.fromValue(map['style']),
      showFrame: map['showFrame'] == true,
      dividerAfter: PaperDivider.fromValue(map['dividerAfter']),
    );
  }
}
