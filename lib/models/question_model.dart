import 'package:uuid/uuid.dart';

import 'branch_item.dart';
import 'branch_model.dart';
import 'floating_element.dart';
import 'paper_divider.dart';
import 'paper_text_style.dart';

/// السؤال الكامل (QuestionModel): «السؤال الأول» بمنطوقه ونصه ونقاطه وفروعه.
///
/// بنية السؤال على الورقة (وهي نفسها بنية الفرع):
/// الرقم ← [statement] (المنطوق) ← الدرجة «(٢٠ درجة)» في سطر العنوان نفسه،
/// ثم [body] (نص السؤال، يُحذف كلياً عند فراغه)، ثم [items] (النقاط المرقّمة
/// بأنواعها المختلطة)، ثم [branches] (أ، ب، ج...).
///
/// - [questionNumber] هو الرقم الهيكلي (1، 2، 3...) ويُعاد ضبطه من الترتيب
///   داخل `ExamDocument` عند تفعيل الترقيم التلقائي.
/// - [numberOverride]: ما يكتبه المدرس حرفياً في موضع الرقم («س١/»،
///   «السؤال الاول/»)؛ الفارغ = رقم تلقائي من نمط التسمية العام.
/// - [marksOverride]: الدرجة كرقم خام يكتبه المدرس («20») فيطبعها النظام
///   «(٢٠ درجة)»؛ غيابها يعني مجموع درجات الفروع والنقاط تلقائياً.
/// - السؤال **وحدة لا تتجزأ**: ينتقل كاملاً بمنطوقه ونصه ونقاطه وفروعه وصوره
///   وأشكاله ودرجاته وفواصله عند النقل، ولا يُقسَّم بين صفحتين.
class QuestionModel {
  QuestionModel({
    String? id,
    required this.questionNumber,
    List<BranchModel>? branches,
    this.category = '',
    this.statement = '',
    this.body = '',
    this.marksOverride,
    this.numberOverride,
    this.spacingAfter = 10,
    List<BranchItem>? items,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    this.titleColor,
    this.showFrame = false,
    this.dividerAfter,
    this.titleAlign,
    this.bodyAlign,
    this.categoryAlign,
  })  : id = id ?? const Uuid().v4(),
        // السؤال الجديد يبدأ بلا فروع؛ تُنشأ فقط بطلب صريح من المدرس.
        branches = List<BranchModel>.unmodifiable(
          branches ?? const <BranchModel>[],
        ),
        // نقاط السؤال المباشرة: قائمة غير قابلة للتغيير بنفس حجج الفروع.
        items = List<BranchItem>.unmodifiable(
          items ?? const <BranchItem>[],
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

  /// نقاط السؤال المباشرة (١-، ٢-، ٣-...) بأنواعها المختلطة — نفس بنية
  /// نقاط الفرع ([BranchItem]) والترقيم يُشتق من الفهرس وقت العرض.
  final List<BranchItem> items;

  /// قسم السؤال (القواعد/الأدب/أحكام التلاوة...) — فارغ = بلا قسم.
  final String category;

  /// منطوق السؤال: يُطبع في سطر العنوان بعد الرقم وقبل الدرجة (يدعم LaTeX).
  final String statement;

  /// نص السؤال: يُطبع تحت سطر العنوان ويُحذف كلياً عند فراغه.
  final String body;

  /// الدرجة التي كتبها المدرس كرقم خام (null = مجموع الفروع والنقاط).
  final double? marksOverride;

  /// ما كتبه المدرس في موضع رقم السؤال حرفياً (null = ترقيم تلقائي).
  final String? numberOverride;

  /// المسافة بعد السؤال بالبكسل، قابلة للتخصيص لكل سؤال.
  final double spacingAfter;

  /// صور وأشكال ومربعات نص على مستوى السؤال كاملاً.
  final List<FloatingElement> attachments;

  /// تنسيق السؤال المشترك بين العنوان والمتن.
  /// يبقى [PaperTextStyle.color] مقروءاً ويُعامل كلون عنوان فقط.
  final PaperTextStyle style;

  /// لون عنوان السؤال فقط (ARGB). `null` = لون القالب.
  final int? titleColor;

  /// اللون المعروض للعنوان.
  int? get effectiveTitleColor => titleColor ?? style.color;

  /// إطار حول السؤال كاملاً.
  final bool showFrame;

  /// محاذاة خاصة لسطر عنوان السؤال (null = وراثة من نمط السؤال).
  final PaperAlign? titleAlign;

  /// محاذاة خاصة لنص السؤال (null = وراثة من نمط السؤال).
  final PaperAlign? bodyAlign;

  /// محاذاة خاصة لسطر القسم (`category`) — مثل [titleAlign] و[bodyAlign]
  /// تُحفظ في النموذج فتصل إلى المعاينة وPDF وWord معاً.
  final PaperAlign? categoryAlign;

  /// فاصل بعد السؤال كاملاً.
  final PaperDivider? dividerAfter;

  bool get hasStatement => statement.trim().isNotEmpty;
  bool get hasBody => body.trim().isNotEmpty;

  /// الدرجة الفعلية: اليدوية إن ثُبّتت، وإلا مجموع درجات الفروع والنقاط.
  double get marks =>
      marksOverride ??
      branches.fold<double>(0, (sum, branch) => sum + branch.marks) +
          items.fold<double>(0, (sum, item) => sum + item.marks);

  /// هل درجة السؤال محسوبة تلقائياً من الفروع والنقاط؟
  bool get hasAutoMarks => marksOverride == null;

  /// هل يحمل السؤال أي محتوى مكتوب (منطوق/نص/نقاط/فروع)؟
  bool get hasContent {
    if (hasStatement || hasBody) {
      return true;
    }
    if (items.any((item) => !item.isEmpty)) {
      return true;
    }
    return branches.any((branch) => !branch.content.isEmpty);
  }

  /// هل يستحق السؤال الظهور في النسخة المصدّرة؟
  ///
  /// الأسئلة الفارغة التي تبقى كمساحة تحرير في المنشئ لا تُطبع ولا تحجز
  /// مكاناً في ترقيم الصفحات. مرفقات السؤال والفروع والفواصل محتوى مقصود.
  bool hasExportableContent({
    Set<String> ignoredAttachmentIds = const <String>{},
  }) {
    if (hasStatement ||
        hasBody ||
        items.any((item) => item.showsInExport) ||
        attachments.any((element) => !ignoredAttachmentIds.contains(element.id)) ||
        dividerAfter != null) {
      return true;
    }
    return branches.any(
      (branch) => branch.hasExportableContentIn(
        ignoredAttachmentIds: ignoredAttachmentIds,
      ),
    );
  }

  QuestionModel copyWith({
    int? questionNumber,
    List<BranchModel>? branches,
    String? category,
    String? statement,
    String? body,
    double? Function()? marksOverride,
    String? Function()? numberOverride,
    double? spacingAfter,
    List<BranchItem>? items,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    int? Function()? titleColor,
    bool? showFrame,
    PaperDivider? Function()? dividerAfter,
    PaperAlign? Function()? titleAlign,
    PaperAlign? Function()? bodyAlign,
    PaperAlign? Function()? categoryAlign,
  }) {
    return QuestionModel(
      id: id,
      questionNumber: questionNumber ?? this.questionNumber,
      branches: branches ?? this.branches,
      category: category ?? this.category,
      statement: statement ?? this.statement,
      body: body ?? this.body,
      marksOverride: marksOverride != null ? marksOverride() : this.marksOverride,
      numberOverride: numberOverride != null ? numberOverride() : this.numberOverride,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      items: items ?? this.items,
      attachments: attachments ?? this.attachments,
      style: style ?? this.style,
      titleColor: titleColor != null ? titleColor() : this.titleColor,
      showFrame: showFrame ?? this.showFrame,
      dividerAfter: dividerAfter != null ? dividerAfter() : this.dividerAfter,
      titleAlign: titleAlign != null ? titleAlign() : this.titleAlign,
      bodyAlign: bodyAlign != null ? bodyAlign() : this.bodyAlign,
      categoryAlign: categoryAlign != null ? categoryAlign() : this.categoryAlign,
    );
  }

  // ============================ نقاط السؤال المباشرة ============================

  /// نسخة مع إضافة نقطة جديدة (فارغة افتراضياً).
  QuestionModel withItemAdded([BranchItem? item]) {
    return copyWith(items: <BranchItem>[...items, item ?? BranchItem()]);
  }

  /// نسخة مع توليد [count] نقطة فارغة (تُستخدم لضبط «عدد العناصر» دفعة واحدة).
  QuestionModel withItemCount(int count) {
    final safe = count.clamp(0, 200);
    if (items.length == safe) {
      return this;
    }
    if (items.length > safe) {
      return copyWith(items: items.sublist(0, safe));
    }
    return copyWith(
      items: <BranchItem>[
        ...items,
        for (var i = items.length; i < safe; i++) BranchItem(),
      ],
    );
  }

  /// نسخة مع استبدال النقطة في الموضع [index].
  QuestionModel withItemAt(int index, BranchItem item) {
    RangeError.checkValidIndex(index, items, 'index');
    final updated = List<BranchItem>.of(items);
    updated[index] = item;
    return copyWith(items: updated);
  }

  /// نسخة مع حذف النقطة في الموضع [index].
  QuestionModel withItemRemoved(int index) {
    RangeError.checkValidIndex(index, items, 'index');
    final updated = List<BranchItem>.of(items)..removeAt(index);
    return copyWith(items: updated);
  }

  /// نسخة مع نقل النقطة من [from] إلى [to].
  QuestionModel withItemMoved(int from, int to) {
    RangeError.checkValidIndex(from, items, 'from');
    final updated = List<BranchItem>.of(items);
    final item = updated.removeAt(from);
    final target = to.clamp(0, updated.length);
    updated.insert(target, item);
    return copyWith(items: updated);
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

  /// نسخة بهوية جديدة وهويات فروع/نقاط/مرفقات جديدة (للنسخ/التكرار).
  ///
  /// نقاط السؤال تُنسخ **كاملة** (نص/نوع/خيارات/درجة/تسمية/محاذاة) كما هي؛
  /// وأما [numberOverride] فلا يُنقل عمداً — الرقم اليدوي خاص بالأصل،
  /// والنسخة سؤال جديد بترقيمها التلقائي.
  QuestionModel duplicated({required int questionNumber}) {
    return QuestionModel(
      questionNumber: questionNumber,
      branches: branches.map((branch) => branch.duplicated()).toList(),
      category: category,
      statement: statement,
      body: body,
      marksOverride: marksOverride,
      spacingAfter: spacingAfter,
      items: items.map((item) => item.duplicated()).toList(),
      attachments: attachments.map((element) => element.duplicated()).toList(),
      style: style,
      titleColor: titleColor,
      showFrame: showFrame,
      dividerAfter: dividerAfter,
      titleAlign: titleAlign,
      bodyAlign: bodyAlign,
      categoryAlign: categoryAlign,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'questionNumber': questionNumber,
      'category': category,
      'branches': branches.map((branch) => branch.toMap()).toList(growable: false),
      if (statement.isNotEmpty) 'statement': statement,
      if (body.isNotEmpty) 'body': body,
      if (marksOverride != null) 'marksOverride': marksOverride,
      if (numberOverride != null && numberOverride!.trim().isNotEmpty)
        'numberOverride': numberOverride,
      if (spacingAfter != 10) 'spacingAfter': spacingAfter,
      if (items.isNotEmpty)
        'items': items.map((item) => item.toMap()).toList(growable: false),
      if (attachments.isNotEmpty)
        'attachments':
            attachments.map((element) => element.toMap()).toList(growable: false),
      if (style.isNotEmpty) 'style': style.toMap(),
      if (titleColor != null) 'titleColor': titleColor,
      if (showFrame) 'showFrame': true,
      if (dividerAfter != null) 'dividerAfter': dividerAfter!.toMap(),
      if (titleAlign != null) 'titleAlign': titleAlign!.name,
      if (bodyAlign != null) 'bodyAlign': bodyAlign!.name,
      if (categoryAlign != null) 'categoryAlign': categoryAlign!.name,
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
    final rawTitleAlign = map['titleAlign'];
    final rawBodyAlign = map['bodyAlign'];
    final rawCategoryAlign = map['categoryAlign'];
    return QuestionModel(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      questionNumber: number,
      category: map['category']?.toString() ?? '',
      branches: branches,
      statement: map['statement']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      marksOverride: marksOverride,
      numberOverride:
          rawNumberOverride == null || rawNumberOverride.isEmpty ? null : rawNumberOverride,
      spacingAfter: (map['spacingAfter'] is num &&
              (map['spacingAfter'] as num).isFinite &&
              (map['spacingAfter'] as num) >= 0)
          ? (map['spacingAfter'] as num).toDouble().clamp(0, 200).toDouble()
          : 10,
      items: BranchItem.listFromValue(map['items']),
      attachments: attachments,
      style: PaperTextStyle.fromValue(map['style']),
      titleColor: PaperTextStyle.parseColor(map['titleColor']),
      showFrame: map['showFrame'] == true,
      dividerAfter: PaperDivider.fromValue(map['dividerAfter']),
      titleAlign: rawTitleAlign != null ? PaperAlign.parse(rawTitleAlign) : null,
      bodyAlign: rawBodyAlign != null ? PaperAlign.parse(rawBodyAlign) : null,
      categoryAlign:
          rawCategoryAlign != null ? PaperAlign.parse(rawCategoryAlign) : null,
    );
  }
}
