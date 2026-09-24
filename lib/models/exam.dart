import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'exam_header.dart';
import 'floating_element.dart';
import 'main_question.dart';

/// نموذج الاختبار (ExamModel) — جذر الشجرة الهرمية للورقة.
///
/// البنية الصارمة:
/// - [Exam] ← قائمة `List<MainQuestion>` ([mainQuestions]: س1، س2...).
/// - [MainQuestion] ← قائمة `List<QuestionBranch>` (أ، ب، ج...) ودرجته
///   الكلية مجموع درجات فروعه آلياً.
/// - [floatingElements] عناصر حرة (صور/أشكال) فوق لوحة الورقة بإحداثيات
///   مطلقة تنتقل 1:1 إلى `pw.Positioned` في محرك الـ PDF.
///
/// **الترتيب يدوي 100%**: لا خلط (`shuffle`) آلي إطلاقاً — ترتيب
/// [mainQuestions] هو ترتيب ورقة الامتحان كما يظهر في اللوحة التفاعلية.
class Exam {
  Exam({
    String? id,
    required this.name,
    ExamHeader? header,
    List<MainQuestion>? mainQuestions,
    List<FloatingElement>? floatingElements,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        header = header ?? ExamHeader(),
        mainQuestions = List<MainQuestion>.from(mainQuestions ?? const []),
        floatingElements = List<FloatingElement>.from(floatingElements ?? const []),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final ExamHeader header;

  /// أسئلة الاختبار الرئيسية بترتيبها اليدوي (س1، س2...).
  final List<MainQuestion> mainQuestions;

  /// العناصر الحرة (صور/أشكال) فوق لوحة الورقة.
  final List<FloatingElement> floatingElements;
  final DateTime createdAt;

  /// الدرجة الكلية = مجموع درجات الأسئلة الرئيسية = مجموع درجات كل الفروع.
  double get totalMarks {
    return mainQuestions.fold<double>(
      0,
      (sum, question) => sum + question.marks,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'header': header.toMap(),
      'mainQuestions':
          mainQuestions.map((question) => question.toMap()).toList(growable: false),
      'floatingElements': floatingElements
          .map((element) => element.toMap())
          .toList(growable: false),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// يقرأ اختباراً من مخزون JSON/Map **بشكل صارم**.
  ///
  /// أي سؤال تالف أو عنصر عائم تالف يرمي [FormatException] ليُعزل السجل
  /// كاملاً بواسطة [StorageService] دون المساس بالاختبارات السليمة.
  ///
  /// التوافق الخلفي: يُقرأ مفتاح `mainQuestions` الجديد، وإلا مفتاح
  /// `questions` القديم (السجلات المكتوبة بالإصدارات السابقة).
  factory Exam.fromMap(Map<String, dynamic> map) {
    final rawQuestions = map['mainQuestions'] ?? map['questions'];
    return Exam(
      id: _nonEmptyString(map['id']),
      name: _nonEmptyString(map['name']) ?? 'اختبار غير معنون',
      header: _headerFromValue(map['header']),
      mainQuestions: _questionsFromValue(rawQuestions),
      floatingElements: _floatingElementsFromValue(map['floatingElements']),
      createdAt: _dateFromValue(map['createdAt']) ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Exam.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Exam JSON must contain an object.');
    }
    return Exam.fromMap(Map<String, dynamic>.from(decoded));
  }

  Exam copyWith({
    String? name,
    ExamHeader? header,
    List<MainQuestion>? mainQuestions,
    List<FloatingElement>? floatingElements,
  }) {
    return Exam(
      id: id,
      name: name ?? this.name,
      header: header ?? this.header,
      mainQuestions: mainQuestions ?? this.mainQuestions,
      floatingElements: floatingElements ?? this.floatingElements,
      createdAt: createdAt,
    );
  }

  static ExamHeader _headerFromValue(Object? value) {
    return value is Map
        ? ExamHeader.fromMap(Map<String, dynamic>.from(value))
        : ExamHeader();
  }

  static List<MainQuestion> _questionsFromValue(Object? value) {
    if (value == null) {
      return <MainQuestion>[];
    }
    if (value is! List) {
      throw const FormatException('Exam: حقل الأسئلة (mainQuestions) يجب أن يكون قائمة.');
    }

    final questions = <MainQuestion>[];
    for (final entry in value) {
      if (entry is! Map) {
        throw const FormatException(
          'Exam: تركيب أسئلة تالف — عنصر السؤال يجب أن يكون خريطة.',
        );
      }
      questions.add(MainQuestion.fromMap(Map<String, dynamic>.from(entry)));
    }
    return questions;
  }

  static List<FloatingElement> _floatingElementsFromValue(Object? value) {
    if (value == null) {
      return <FloatingElement>[];
    }
    if (value is! List) {
      throw const FormatException('Exam: حقل العناصر العائمة يجب أن يكون قائمة.');
    }

    final elements = <FloatingElement>[];
    for (final entry in value) {
      if (entry is! Map) {
        throw const FormatException(
          'Exam: تركيب عناصر عائمة تالف — العنصر يجب أن يكون خريطة.',
        );
      }
      elements.add(FloatingElement.fromMap(Map<String, dynamic>.from(entry)));
    }
    return elements;
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
