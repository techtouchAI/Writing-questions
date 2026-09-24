import 'package:uuid/uuid.dart';

import 'floating_element.dart';
import 'question_option.dart';
import 'question_type.dart';

/// المحتوى الفعلي لفرع السؤال (questionContent): نوع السؤال ونصه وخياراته.
///
/// كائن **غير قابل للتغيير** يُنقل ككتلة واحدة عند السحب والإفلات بين
/// الفروع — الهيكل (رقم السؤال، تسمية الفرع) يبقى ثابتاً والمحتوى يتبدّل.
class BranchContent {
  BranchContent({
    required this.type,
    this.text = '',
    List<QuestionOption>? options,
    this.modelAnswer = '',
  }) : options = List<QuestionOption>.unmodifiable(
          (options ?? const <QuestionOption>[]).map((option) => option.copyWith()),
        );

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

  /// الخيار الصحيح في صح/خطأ: `true` = صح.
  bool get trueFalseAnswer {
    final correct = options.where((option) => option.isCorrect).toList();
    return correct.isEmpty || correct.first.text.trim() != 'خطأ';
  }

  bool get isEmpty =>
      text.trim().isEmpty &&
      modelAnswer.trim().isEmpty &&
      options.every((option) => option.text.trim().isEmpty);

  BranchContent copyWith({
    QuestionType? type,
    String? text,
    List<QuestionOption>? options,
    String? modelAnswer,
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
    );
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
    };
  }

  /// يقرأ المحتوى **بشكل صارم**؛ نوع مجهول أو خيارات تالفة ترمي [FormatException].
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

/// فرع السؤال (BranchModel): أ، ب، ج، د.
///
/// - [branchLabel] **لا يُخزَّن**؛ يُشتق من فهرس الفرع داخل سؤاله عبر قالب
///   المادة (أ/ب/ج أو A/B/C) حتى لا تبقى فجوات عند الحذف أو التبديل.
/// - [content] و[marks] هما ما يتبدّل عند السحب والإفلات؛ الهوية ([id])
///   والموضع يبقيان ثابتين.
/// - [attachments] صور وأشكال هندسية مثبّتة فوق مساحة الفرع بإحداثيات
///   نسبية إلى أعلى يسار كتلة الفرع (بكسل منطقي للوحة A4).
class BranchModel {
  BranchModel({
    String? id,
    BranchContent? content,
    this.marks = 0.0,
    List<FloatingElement>? attachments,
  })  : id = id ?? const Uuid().v4(),
        content = content ?? BranchContent.empty(),
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

  BranchModel copyWith({
    BranchContent? content,
    double? marks,
    List<FloatingElement>? attachments,
  }) {
    return BranchModel(
      id: id,
      content: content ?? this.content,
      marks: marks ?? this.marks,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'content': content.toMap(),
      'marks': marks,
      'attachments':
          attachments.map((element) => element.toMap()).toList(growable: false),
    };
  }

  /// يقرأ فرعاً **بشكل صارم**.
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
    return BranchModel(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      content: BranchContent.fromMap(Map<String, dynamic>.from(rawContent)),
      marks: marks,
      attachments: attachments,
    );
  }
}
