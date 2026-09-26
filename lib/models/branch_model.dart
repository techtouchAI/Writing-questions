import 'package:uuid/uuid.dart';

import 'branch_item.dart';
import 'floating_element.dart';
import 'paper_divider.dart';
import 'paper_text_style.dart';
import 'question_option.dart';
import 'question_type.dart';

/// المحتوى الفعلي لفرع السؤال (questionContent): نوع السؤال ونصه وخياراته.
///
/// كائن **غير قابل للتغيير** يُنقل ككتلة واحدة عند السحب والإفلات بين
/// الفروع — الهيكل (رقم السؤال، تسمية الفرع) يبقى ثابتاً والمحتوى يتبدّل.
///
/// كل فرع مستقل تماماً بنوعه: نص حر، تعداد، فراغات، صح/خطأ، اختيار من
/// متعدد — ولا يُفرض نوع واحد على السؤال كاملاً.
class BranchContent {
  BranchContent({
    required this.type,
    this.text = '',
    List<QuestionOption>? options,
    this.modelAnswer = '',
    List<BranchItem>? items,
    this.plainText = false,
  })  : options = List<QuestionOption>.unmodifiable(
          (options ?? const <QuestionOption>[]).map((option) => option.copyWith()),
        ),
        items = List<BranchItem>.unmodifiable(items ?? const <BranchItem>[]);

  /// محتوى مقالي فارغ (الافتراضي للفرع الجديد).
  factory BranchContent.empty([QuestionType type = QuestionType.essay]) {
    return BranchContent(type: type, options: _defaultOptionsFor(type));
  }

  final QuestionType type;

  /// نص الفرع (يدعم LaTeX داخل $...$ أو $$...$$).
  final String text;

  /// خيارات (اختيار من متعدد) أو (صح/خطأ).
  final List<QuestionOption> options;

  /// الإجابة النموذجية (فراغات/مقالي) لنموذج المعلم.
  final String modelAnswer;

  /// النقاط داخل الفرع (1، 2، 3...): عبارات، فراغات، تعداد — بلا حد.
  final List<BranchItem> items;

  /// نص حر خالص: يُعرض النص والنقاط فقط دون أي مساحة إجابة مولّدة.
  ///
  /// يبقى نوع الفرع محفوظاً (للإجابة النموذجية والتصدير) لكن العرض
  /// يقتصر على ما كتبه المدرس حرفياً.
  final bool plainText;

  /// الخيار الصحيح في صح/خطأ: `true` = صح.
  bool get trueFalseAnswer {
    final correct = options.where((option) => option.isCorrect).toList();
    return correct.isEmpty || correct.first.text.trim() != 'خطأ';
  }

  bool get isEmpty =>
      text.trim().isEmpty &&
      modelAnswer.trim().isEmpty &&
      items.every((item) => item.isEmpty) &&
      options.every((option) => option.text.trim().isEmpty);

  BranchContent copyWith({
    QuestionType? type,
    String? text,
    List<QuestionOption>? options,
    String? modelAnswer,
    List<BranchItem>? items,
    bool? plainText,
  }) {
    final nextType = type ?? this.type;
    return BranchContent(
      type: nextType,
      text: text ?? this.text,
      // تغيير النوع يعيد ضبط الخيارات على النموذج الافتراضي للنوع الجديد.
      options: options ??
          (type == null || type == this.type
              ? this.options
              : _defaultOptionsFor(nextType)),
      modelAnswer: modelAnswer ?? this.modelAnswer,
      items: items ?? this.items,
      plainText: plainText ?? this.plainText,
    );
  }

  /// نسخة مع استبدال النقطة في الموضع [index].
  BranchContent withItemAt(int index, BranchItem item) {
    RangeError.checkValidIndex(index, items, 'index');
    final updated = List<BranchItem>.of(items);
    updated[index] = item;
    return copyWith(items: updated);
  }

  /// نسخة مع إضافة نقطة جديدة (فارغة افتراضياً).
  BranchContent withItemAdded([BranchItem? item]) {
    return copyWith(items: <BranchItem>[...items, item ?? BranchItem()]);
  }

  /// نسخة مع توليد [count] نقطة فارغة (تُستخدم لضبط «عدد العناصر» دفعة واحدة).
  BranchContent withItemCount(int count) {
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

  /// نسخة مع حذف النقطة في الموضع [index].
  BranchContent withItemRemoved(int index) {
    RangeError.checkValidIndex(index, items, 'index');
    final updated = List<BranchItem>.of(items)..removeAt(index);
    return copyWith(items: updated);
  }

  /// نسخة مع تثبيت إجابة النقطة [index] لصح/خطأ (`null` = غير محددة).
  BranchContent withItemAnswer(int index, bool? answer) {
    RangeError.checkValidIndex(index, items, 'index');
    final updated = List<BranchItem>.of(items);
    updated[index] = updated[index].copyWith(isCorrect: () => answer);
    return copyWith(items: updated);
  }

  /// نسخة مع نقل النقطة من [from] إلى [to].
  BranchContent withItemMoved(int from, int to) {
    RangeError.checkValidIndex(from, items, 'from');
    final updated = List<BranchItem>.of(items);
    final item = updated.removeAt(from);
    final target = to.clamp(0, updated.length);
    updated.insert(target, item);
    return copyWith(items: updated);
  }

  /// يُثبّت إجابة صح/خطأ ([answer] = true تعني «صح»).
  BranchContent withTrueFalseAnswer(bool answer) {
    return copyWith(
      type: QuestionType.trueFalse,
      options: <QuestionOption>[
        QuestionOption(text: 'صح', isCorrect: answer),
        QuestionOption(text: 'خطأ', isCorrect: !answer),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'text': text,
      'options': options.map((option) => option.toMap()).toList(growable: false),
      'modelAnswer': modelAnswer,
      if (items.isNotEmpty)
        'items': items.map((item) => item.toMap()).toList(growable: false),
      if (plainText) 'plainText': true,
    };
  }

  /// يقرأ المحتوى **بشكل صارم** في الحقول الجوهرية؛ الحقول الجديدة
  /// (النقاط/النص الحر) متسامحة لتبقى الفروع القديمة صالحة.
  factory BranchContent.fromMap(Map<String, dynamic> map) {
    final rawType = map['type'];
    if (rawType is! String) {
      throw const FormatException('BranchContent: حقل النوع (type) مفقود أو ليس نصاً.');
    }
    final rawText = map['text'];
    if (rawText != null && rawText is! String && rawText is! num) {
      throw const FormatException('BranchContent: نص الفرع يجب أن يكون نصاً.');
    }
    final rawOptions = map['options'];
    if (rawOptions != null && rawOptions is! List) {
      throw const FormatException('BranchContent: الخيارات يجب أن تكون قائمة.');
    }
    final options = <QuestionOption>[];
    for (final entry in (rawOptions as List?) ?? const <Object?>[]) {
      if (entry is! Map) {
        throw const FormatException('BranchContent: عنصر الخيار يجب أن يكون خريطة.');
      }
      options.add(QuestionOption.fromMap(Map<String, dynamic>.from(entry)));
    }
    return BranchContent(
      type: QuestionType.parse(rawType),
      text: rawText?.toString() ?? '',
      options: options,
      modelAnswer: map['modelAnswer']?.toString() ?? '',
      items: BranchItem.listFromValue(map['items']),
      plainText: map['plainText'] == true,
    );
  }

  /// نسخة بهويات جديدة للنقاط (للنسخ/التكرار).
  BranchContent duplicated() {
    return BranchContent(
      type: type,
      text: text,
      options: options.map((option) => option.copyWith()).toList(growable: false),
      modelAnswer: modelAnswer,
      items: <BranchItem>[
        for (final item in items) BranchItem(text: item.text, marks: item.marks),
      ],
      plainText: plainText,
    );
  }

  static List<QuestionOption> _defaultOptionsFor(QuestionType type) {
    switch (type) {
      case QuestionType.multipleChoice:
        return <QuestionOption>[
          QuestionOption(text: '', isCorrect: true),
          QuestionOption(text: ''),
          QuestionOption(text: ''),
          QuestionOption(text: ''),
        ];
      case QuestionType.trueFalse:
        return <QuestionOption>[
          QuestionOption(text: 'صح', isCorrect: true),
          QuestionOption(text: 'خطأ'),
        ];
      case QuestionType.fillInTheBlank:
      case QuestionType.essay:
        return const <QuestionOption>[];
    }
  }
}

/// فرع السؤال (BranchModel): أ، ب، ج، د...
///
/// - تسمية الفرع **لا تُخزَّن** افتراضياً؛ تُشتق من فهرس الفرع داخل سؤاله
///   عبر قالب المادة (أ/ب/ج أو A/B/C) حتى لا تبقى فجوات عند الحذف أو
///   التبديل — ما لم يثبّت المدرس [labelOverride] يدوياً.
/// - [content] و[marks] هما ما يتبدّل عند السحب والإفلات؛ الهوية ([id])
///   والموضع يبقيان ثابتين.
/// - [attachments] صور وأشكال ومربعات نص مثبّتة فوق مساحة الفرع.
/// - [style] تنسيق خاص بالفرع، و[showFrame] إطار حوله، و[dividerAfter]
///   فاصل بعده — كلها اختيارية.
class BranchModel {
  BranchModel({
    String? id,
    BranchContent? content,
    this.marks = 0.0,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    this.showFrame = false,
    this.dividerAfter,
    this.labelOverride,
  })  : id = id ?? const Uuid().v4(),
        content = content ?? BranchContent.empty(),
        style = style ?? PaperTextStyle.empty,
        attachments = List<FloatingElement>.from(
          attachments ?? const <FloatingElement>[],
        ) {
    if (!marks.isFinite || marks < 0) {
      throw ArgumentError.value(marks, 'marks', 'درجة الفرع يجب أن تكون رقماً موجباً.');
    }
  }

  final String id;
  final BranchContent content;
  final double marks;
  final List<FloatingElement> attachments;
  final PaperTextStyle style;
  final bool showFrame;
  final PaperDivider? dividerAfter;

  /// تسمية يدوية ثابتة للفرع (null = تلقائي من الفهرس).
  final String? labelOverride;

  BranchModel copyWith({
    BranchContent? content,
    double? marks,
    List<FloatingElement>? attachments,
    PaperTextStyle? style,
    bool? showFrame,
    PaperDivider? Function()? dividerAfter,
    String? Function()? labelOverride,
  }) {
    return BranchModel(
      id: id,
      content: content ?? this.content,
      marks: marks ?? this.marks,
      attachments: attachments ?? this.attachments,
      style: style ?? this.style,
      showFrame: showFrame ?? this.showFrame,
      dividerAfter: dividerAfter != null ? dividerAfter() : this.dividerAfter,
      labelOverride: labelOverride != null ? labelOverride() : this.labelOverride,
    );
  }

  /// نسخة بهوية جديدة وهويات نقاط/مرفقات جديدة (للنسخ/التكرار).
  BranchModel duplicated() {
    return BranchModel(
      content: content.duplicated(),
      marks: marks,
      attachments: attachments.map((element) => element.duplicated()).toList(),
      style: style,
      showFrame: showFrame,
      dividerAfter: dividerAfter,
      labelOverride: labelOverride,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'content': content.toMap(),
      'marks': marks,
      'attachments':
          attachments.map((element) => element.toMap()).toList(growable: false),
      if (style.isNotEmpty) 'style': style.toMap(),
      if (showFrame) 'showFrame': true,
      if (dividerAfter != null) 'dividerAfter': dividerAfter!.toMap(),
      if (labelOverride != null && labelOverride!.trim().isNotEmpty)
        'labelOverride': labelOverride,
    };
  }

  /// يقرأ فرعاً **بشكل صارم** في الحقول الجوهرية؛ الحقول الجديدة متسامحة.
  factory BranchModel.fromMap(Map<String, dynamic> map) {
    final rawContent = map['content'];
    if (rawContent is! Map) {
      throw const FormatException('BranchModel: محتوى الفرع (content) مفقود.');
    }
    final rawMarks = map['marks'];
    final marks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    if (marks == null || !marks.isFinite || marks < 0) {
      throw FormatException('BranchModel: درجة الفرع غير صالحة (${rawMarks ?? 'مفقودة'}).');
    }
    final rawAttachments = map['attachments'];
    if (rawAttachments != null && rawAttachments is! List) {
      throw const FormatException('BranchModel: المرفقات يجب أن تكون قائمة.');
    }
    final attachments = <FloatingElement>[];
    for (final entry in (rawAttachments as List?) ?? const <Object?>[]) {
      if (entry is! Map) {
        throw const FormatException('BranchModel: عنصر المرفق يجب أن يكون خريطة.');
      }
      attachments.add(FloatingElement.fromMap(Map<String, dynamic>.from(entry)));
    }
    final rawLabel = map['labelOverride']?.toString().trim();
    return BranchModel(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      content: BranchContent.fromMap(Map<String, dynamic>.from(rawContent)),
      marks: marks,
      attachments: attachments,
      style: PaperTextStyle.fromValue(map['style']),
      showFrame: map['showFrame'] == true,
      dividerAfter: PaperDivider.fromValue(map['dividerAfter']),
      labelOverride: rawLabel == null || rawLabel.isEmpty ? null : rawLabel,
    );
  }
}
