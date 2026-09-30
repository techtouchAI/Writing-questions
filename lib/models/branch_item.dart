import 'package:uuid/uuid.dart';

import 'paper_text_style.dart';

/// نقطة واحدة داخل فرع (1، 2، 3...): عبارة صح/خطأ، فراغ، تعداد...
///
/// عدد النقاط غير محدود، والمدرس يضيف/يحذف/يعيد ترتيبها بحرية.
/// الترقيم الافتراضي (1- أو ١-) يُشتق من الفهرس وقت العرض، والمدرس
/// يخصصه عبر [labelOverride] أو يحذفه (فراغ) دون إعادة ترقيم.
class BranchItem {
  BranchItem({
    String? id,
    this.text = '',
    this.marks = 0.0,
    this.labelOverride,
    this.align,
  }) : id = id ?? const Uuid().v4() {
    if (!marks.isFinite || marks < 0) {
      throw ArgumentError.value(marks, 'marks', 'درجة النقطة يجب أن تكون رقماً موجباً.');
    }
  }

  final String id;

  /// نص النقطة (يدعم LaTeX داخل $...$).
  final String text;

  /// درجة النقطة (0 = بلا درجة معلنة).
  final double marks;

  /// تسمية مخصصة: `null` = تلقائية من الفهرس، `''` = بلا تسمية.
  final String? labelOverride;

  /// محاذاة خاصة بهذه النقطة (null = وراثة من الفرع/السؤال).
  final PaperAlign? align;

  bool get isEmpty => text.trim().isEmpty;

  /// محتوى النقطة الخاص (نص أو درجة) — دون التسمية.
  bool get hasOwnContent => text.trim().isNotEmpty || marks > 0;

  /// هل تظهر النقطة على الورقة (المعاينة/PDF/Word)؟
  /// تكفي درجة أو تسمية لإظهار النقطة حتى بلا نص.
  bool get showsInExport =>
      text.trim().isNotEmpty || marks > 0 || labelOverride != null;

  BranchItem copyWith({
    String? text,
    double? marks,
    String? Function()? labelOverride,
    PaperAlign? Function()? align,
  }) {
    return BranchItem(
      id: id,
      text: text ?? this.text,
      marks: marks ?? this.marks,
      labelOverride:
          labelOverride == null ? this.labelOverride : labelOverride(),
      align: align == null ? this.align : align(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'marks': marks,
      if (labelOverride != null) 'labelOverride': labelOverride,
      if (align != null) 'align': align!.name,
    };
  }

  /// قراءة متسامحة قدر الإمكان: النص والدرجة التالفان يرتدان إلى فراغ/صفر.
  factory BranchItem.fromMap(Map<String, dynamic> map) {
    final rawText = map['text'];
    final rawMarks = map['marks'];
    final marks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    final rawLabel = map['labelOverride'];
    final rawAlign = map['align'];
    return BranchItem(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      marks: marks == null || !marks.isFinite || marks < 0 ? 0.0 : marks,
      labelOverride: rawLabel is String ? rawLabel : null,
      align: rawAlign != null ? PaperAlign.parse(rawAlign) : null,
    );
  }

  /// يقرأ قائمة نقاط من قيمة مخزنة؛ العناصر التالفة تُتجاهل فرادى.
  static List<BranchItem> listFromValue(Object? value) {
    if (value is! List) {
      return const <BranchItem>[];
    }
    final items = <BranchItem>[];
    for (final entry in value) {
      if (entry is! Map) {
        continue;
      }
      try {
        items.add(BranchItem.fromMap(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // نقطة واحدة تالفة لا تُسقط الفرع كاملاً.
      }
    }
    return items;
  }
}
