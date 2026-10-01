import 'package:uuid/uuid.dart';

import 'paper_text_style.dart';
import 'point_kind.dart';
import 'question_option.dart';

/// نقطة واحدة مرقّمة (١-، ٢-، ٣-...) داخل سؤال أو فرع.
///
/// لكل نقطة [kind] خاص بها (صح/خطأ، إكمال الفراغ، اختيار من متعدد، نص حر)،
/// وتختلط الأنواع في المجموعة نفسها بحرية: الترقيم تسلسل واحد متصل يُشتق من
/// الفهرس وقت العرض، والمدرس يخصّصه عبر [labelOverride] أو يخفيه (فراغ).
///
/// نقاط «اختيار من متعدد» تحمل [options] (٤ خيارات فارغة افتراضياً)؛ ولا
/// تُطبع الخيارات لأي نوع آخر. التطبيق لكتابة الأسئلة وحدها: لا حالة إجابة.
class BranchItem {
  BranchItem({
    String? id,
    this.text = '',
    this.kind = PointKind.plain,
    List<QuestionOption>? options,
    this.marks = 0.0,
    this.labelOverride,
    this.align,
  })  : id = id ?? const Uuid().v4(),
        options = List<QuestionOption>.unmodifiable(
          _normalizedOptions(kind, options),
        ) {
    if (!marks.isFinite || marks < 0) {
      throw ArgumentError.value(marks, 'marks', 'درجة النقطة يجب أن تكون رقماً موجباً.');
    }
  }

  /// عدد الخيارات الافتراضي لنقطة «اختيار من متعدد».
  static const int defaultOptionCount = 4;

  /// خيارات فارغة جديدة (نسخ مستقلة بمعرّفات جديدة).
  static List<QuestionOption> blankOptions([int count = defaultOptionCount]) =>
      <QuestionOption>[for (var i = 0; i < count; i++) QuestionOption(text: '')];

  static List<QuestionOption> _normalizedOptions(
    PointKind kind,
    List<QuestionOption>? source,
  ) {
    if (source == null || source.isEmpty) {
      return kind == PointKind.multipleChoice
          ? blankOptions()
          : const <QuestionOption>[];
    }
    return <QuestionOption>[for (final option in source) option.copyWith()];
  }

  final String id;

  /// نص النقطة (يدعم LaTeX داخل $...$): العبارة أو الجملة أو نص السؤال.
  final String text;

  /// نوع النقطة (يحدد طريقة طباعتها).
  final PointKind kind;

  /// خيارات «اختيار من متعدد» (لا تُطبع لغيره).
  final List<QuestionOption> options;

  /// درجة النقطة (0 = بلا درجة معلنة).
  final double marks;

  /// تسمية مخصصة: `null` = تلقائية من الفهرس، `''` = بلا تسمية.
  final String? labelOverride;

  /// محاذاة خاصة بهذه النقطة (null = وراثة من الفرع/السؤال).
  final PaperAlign? align;

  /// هل للنقطة خيارات تُطبع (اختيار من متعدد وفيه خيار مكتوب)؟
  bool get hasVisibleOptions =>
      kind == PointKind.multipleChoice &&
      options.any((option) => option.text.trim().isNotEmpty);

  bool get isEmpty =>
      text.trim().isEmpty &&
      options.every((option) => option.text.trim().isEmpty);

  /// محتوى النقطة الخاص (نص أو خيارات أو درجة) — دون التسمية.
  bool get hasOwnContent => !isEmpty || marks > 0;

  /// هل تظهر النقطة على الورقة (المعاينة/PDF/Word)؟
  /// تكفي درجة أو تسمية لإظهار النقطة حتى بلا نص.
  bool get showsInExport =>
      text.trim().isNotEmpty ||
      marks > 0 ||
      labelOverride != null ||
      hasVisibleOptions;

  BranchItem copyWith({
    String? text,
    PointKind? kind,
    List<QuestionOption>? options,
    double? marks,
    String? Function()? labelOverride,
    PaperAlign? Function()? align,
  }) {
    return BranchItem(
      id: id,
      text: text ?? this.text,
      kind: kind ?? this.kind,
      options: options ?? this.options,
      marks: marks ?? this.marks,
      labelOverride:
          labelOverride == null ? this.labelOverride : labelOverride(),
      align: align == null ? this.align : align(),
    );
  }

  /// نسخة بهوية جديدة (وهويات خيارات جديدة) بالمحتوى والتسمية نفسهما.
  BranchItem duplicated() {
    return BranchItem(
      text: text,
      kind: kind,
      options: <QuestionOption>[
        for (final option in options)
          QuestionOption(
            text: option.text,
            labelOverride: option.labelOverride,
            align: option.align,
          ),
      ],
      marks: marks,
      labelOverride: labelOverride,
      align: align,
    );
  }

  /// هل لهذه النقطة المحتوى نفسه تماماً (النص/النوع/الخيارات/الدرجة/التسمية)؟
  bool sameContentAs(BranchItem other) {
    if (id != other.id ||
        text != other.text ||
        kind != other.kind ||
        marks != other.marks ||
        labelOverride != other.labelOverride ||
        align != other.align ||
        options.length != other.options.length) {
      return false;
    }
    for (var index = 0; index < options.length; index++) {
      final a = options[index];
      final b = other.options[index];
      if (a.id != b.id ||
          a.text != b.text ||
          a.labelOverride != b.labelOverride ||
          a.align != b.align) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      if (kind != PointKind.plain) 'kind': kind.name,
      if (options.isNotEmpty &&
          (kind == PointKind.multipleChoice ||
              options.any((option) => option.text.trim().isNotEmpty)))
        'options': options.map((option) => option.toMap()).toList(growable: false),
      'marks': marks,
      if (labelOverride != null) 'labelOverride': labelOverride,
      if (align != null) 'align': align!.name,
    };
  }

  /// قراءة متسامحة قدر الإمكان: النص والدرجة التالفان يرتدان إلى فراغ/صفر،
  /// والخيار التالف يُتجاهل فرادى.
  factory BranchItem.fromMap(Map<String, dynamic> map) {
    final rawText = map['text'];
    final rawMarks = map['marks'];
    final marks = rawMarks is num
        ? rawMarks.toDouble()
        : double.tryParse(rawMarks?.toString() ?? '');
    final rawLabel = map['labelOverride'];
    final rawAlign = map['align'];
    final options = <QuestionOption>[];
    final rawOptions = map['options'];
    if (rawOptions is List) {
      for (final entry in rawOptions) {
        if (entry is! Map) {
          continue;
        }
        try {
          options.add(QuestionOption.fromMap(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // خيار واحد تالف لا يُسقط النقطة كاملة.
        }
      }
    }
    return BranchItem(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      text: rawText?.toString() ?? '',
      kind: PointKind.parse(map['kind']),
      options: options,
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
        // نقطة واحدة تالفة لا تُسقط المجموعة كاملة.
      }
    }
    return items;
  }
}
