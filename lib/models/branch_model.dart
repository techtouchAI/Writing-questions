import 'package:uuid/uuid.dart';

import 'branch_item.dart';
import 'floating_element.dart';
import 'paper_divider.dart';
import 'paper_text_style.dart';

/// المحتوى الفعلي لفرع السؤال: منطوق الفرع ونصه ونقاطه.
///
/// كائن **غير قابل للتغيير** يُنقل ككتلة واحدة عند السحب والإفلات بين
/// الفروع — الهيكل (رقم السؤال، تسمية الفرع) يبقى ثابتاً والمحتوى يتبدّل.
///
/// بنية الفرع مطابقة لبنية السؤال: الرقم ← [statement] (المنطوق) ← الدرجة ←
/// [body] (النص، يُحذف كلياً عند فراغه) ← [items] (النقاط المرقّمة بأنواعها).
class BranchContent {
  BranchContent({
    this.statement = '',
    this.body = '',
    List<BranchItem>? items,
  }) : items = List<BranchItem>.unmodifiable(items ?? const <BranchItem>[]);

  /// محتوى فارغ (الافتراضي للفرع الجديد).
  factory BranchContent.empty() => BranchContent();

  /// منطوق الفرع: يُطبع في سطر العنوان بعد الرقم وقبل الدرجة (يدعم LaTeX).
  final String statement;

  /// نص الفرع: يُطبع تحت سطر العنوان، ويُحذف من الواجهة والطباعة عند فراغه.
  final String body;

  /// النقاط المرقّمة داخل الفرع (١-، ٢-، ٣-...) بأنواعها المختلطة — بلا حد.
  final List<BranchItem> items;

  bool get hasStatement => statement.trim().isNotEmpty;
  bool get hasBody => body.trim().isNotEmpty;

  /// هل يحمل الفرع محتوى يستحق الظهور في المخرجات (PDF/Word/طباعة)؟
  /// الفرع الفارغ تماماً يُحذف من المطبوع كاملاً ولا يترك أي مسافة.
  bool get hasExportableContent =>
      hasStatement || hasBody || items.any((item) => item.showsInExport);

  bool get isEmpty =>
      !hasStatement && !hasBody && items.every((item) => item.isEmpty);

  BranchContent copyWith({
    String? statement,
    String? body,
    List<BranchItem>? items,
  }) {
    return BranchContent(
      statement: statement ?? this.statement,
      body: body ?? this.body,
      items: items ?? this.items,
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

  /// نسخة مع نقل النقطة من [from] إلى [to].
  BranchContent withItemMoved(int from, int to) {
    RangeError.checkValidIndex(from, items, 'from');
    final updated = List<BranchItem>.of(items);
    final item = updated.removeAt(from);
    final target = to.clamp(0, updated.length);
    updated.insert(target, item);
    return copyWith(items: updated);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'statement': statement,
      if (hasBody) 'body': body,
      if (items.isNotEmpty)
        'items': items.map((item) => item.toMap()).toList(growable: false),
    };
  }

  /// يقرأ المحتوى؛ الحقول الناقصة تأخذ الفراغ، وغير الخريطة يُرفض من المستدعي.
  factory BranchContent.fromMap(Map<String, dynamic> map) {
    final rawStatement = map['statement'];
    final rawBody = map['body'];
    for (final raw in <Object?>[rawStatement, rawBody]) {
      if (raw != null && raw is! String && raw is! num) {
        throw const FormatException('BranchContent: النص يجب أن يكون نصاً.');
      }
    }
    return BranchContent(
      statement: rawStatement?.toString() ?? '',
      body: rawBody?.toString() ?? '',
      items: BranchItem.listFromValue(map['items']),
    );
  }

  /// نسخة بهويات جديدة للنقاط (للنسخ/التكرار) — كاملة التسميات اليدوية
  /// (نفس محتوى النقطة الأصلية حرفياً).
  BranchContent duplicated() {
    return BranchContent(
      statement: statement,
      body: body,
      items: items.map((item) => item.duplicated()).toList(growable: false),
    );
  }
}

/// فرع السؤال (BranchModel): أ، ب، ج، د...
///
/// - تسمية الفرع **لا تُخزَّن** افتراضياً؛ تُشتق من فهرس الفرع داخل سؤاله
///   عبر قالب المادة (أ/ب/ج أو A/B/C) حتى لا تبقى فجوات عند الحذف أو
///   التبديل — ما لم يثبّت المدرس [labelOverride] يدوياً.
/// - [content] و[marks] هما ما يتبدّل عند السحب والإفلات؛ الهوية ([id])
///   والموضع يبقيان ثابتين.
/// - [marks] رقم خام يكتبه المدرس؛ يُطبع «(٥ درجة)» تلقائياً في سطر العنوان.
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

  /// هل ينتج الفرع أو مرفقاته/فاصله محتوى مرئياً عند التصدير؟
  bool hasExportableContentIn({
    Set<String> ignoredAttachmentIds = const <String>{},
  }) =>
      content.hasExportableContent ||
      attachments.any((element) => !ignoredAttachmentIds.contains(element.id)) ||
      dividerAfter != null;

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
