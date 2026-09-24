import 'package:uuid/uuid.dart';

/// فرع من فروع السؤال الرئيسي (مثل: أ، ب، ج...) بدرجة مستقلة.
///
/// **لا يُخزَّن اسم التسمية (أ/ب/ج) في قاعدة البيانات إطلاقاً** — تُولَّد
/// التسميات ديناميكياً من فهرس الفرع داخل قائمة [`List<QuestionBranch>`]
/// وقت العرض في الواجهة وورقة الـ PDF عبر [LabelAlphabet.at]، حتى لا
/// تتبقّى فجوات (أ، ج) إذا حذف المستخدم فرعاً وسط القائمة.
///
/// البنية صارمة: أي تلف في البيانات يرفع [FormatException] صريحاً ليقوم
/// [StorageService] بعزل السجل التالف دون المساس بالسجلات السليمة.
class QuestionBranch {
  QuestionBranch({
    String? id,
    required this.text,
    this.marks = 0.0,
  }) : id = id ?? const Uuid().v4() {
    if (!marks.isFinite || marks < 0) {
      throw ArgumentError.value(marks, 'marks', 'درجة الفرع يجب أن تكون رقماً موجباً.');
    }
  }

  final String id;

  /// نص الفرع (نص LaTeX مدعوم داخل $$...$$ أو $...$ عند الحاجة).
  String text;

  /// درجة هذا الفرع؛ مجموع درجات الفروع = درجة السؤال الرئيسي الكلية.
  double marks;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'marks': marks,
    };
  }

  /// يقرأ فرعاً من مخزون JSON/Map **بشكل صارم**.
  ///
  /// يرمي [FormatException] إذا:
  /// - كانت البنية ليست خريطة (عبر مستدعٍ خارجي)،
  /// - كانت الدرجة نصاً غير رقمي أو سالباً أو غير منتهٍ.
  factory QuestionBranch.fromMap(Map<String, dynamic> map) {
    final rawMarks = map['marks'];
    final parsedMarks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    if (parsedMarks == null || !parsedMarks.isFinite || parsedMarks < 0) {
      throw FormatException(
        'QuestionBranch: درجة الفرع غير صالحة (${rawMarks ?? 'مفقودة'}).',
      );
    }

    final rawText = map['text'];
    if (rawText != null && rawText is! String && rawText is! num) {
      throw const FormatException('QuestionBranch: نص الفرع يجب أن يكون نصاً.');
    }

    return QuestionBranch(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      marks: parsedMarks,
    );
  }

  QuestionBranch copyWith({String? text, double? marks}) {
    return QuestionBranch(
      id: id,
      text: text ?? this.text,
      marks: marks ?? this.marks,
    );
  }
}
