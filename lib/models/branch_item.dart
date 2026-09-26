import 'package:uuid/uuid.dart';

/// نقطة واحدة داخل فرع (1، 2، 3...): عبارة صح/خطأ، فراغ، تعداد...
///
/// عدد النقاط غير محدود، والمدرس يضيف/يحذف/يعيد ترتيبها بحرية.
/// الترقيم (1- أو ١-) يُشتق من الفهرس وقت العرض ولا يُخزَّن.
class BranchItem {
  BranchItem({
    String? id,
    this.text = '',
    this.marks = 0.0,
    this.isCorrect,
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

  /// إجابة النقطة لفروع صح/خطأ (`true` = صح، `false` = خطأ، `null` =
  /// غير محددة) — تظهر في نموذج المعلم فقط.
  final bool? isCorrect;

  bool get isEmpty => text.trim().isEmpty;

  BranchItem copyWith({String? text, double? marks, bool? Function()? isCorrect}) {
    return BranchItem(
      id: id,
      text: text ?? this.text,
      marks: marks ?? this.marks,
      isCorrect: isCorrect == null ? this.isCorrect : isCorrect(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'marks': marks,
      if (isCorrect != null) 'isCorrect': isCorrect,
    };
  }

  /// قراءة متسامحة قدر الإمكان: النص والدرجة التالفان يرتدان إلى فراغ/صفر.
  factory BranchItem.fromMap(Map<String, dynamic> map) {
    final rawText = map['text'];
    final rawMarks = map['marks'];
    final marks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    return BranchItem(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      marks: marks == null || !marks.isFinite || marks < 0 ? 0.0 : marks,
      isCorrect: map['isCorrect'] is bool ? map['isCorrect'] as bool : null,
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
