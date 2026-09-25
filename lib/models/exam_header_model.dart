import 'paper_text_style.dart';
import 'subject_layout.dart';

/// عمود واحد من أعمدة الترويسة الوزارية (يمين/وسط/يسار) بثلاثة أسطر ثابتة.
///
/// عدد الأسطر مضبوط على [lineCount] دائماً (تُقصّ الزيادة وتُملأ النواقص
/// بنصوص فارغة) حتى تبقى شبكة الترويسة ثابتة في الشاشة والـ PDF.
class HeaderColumn {
  HeaderColumn(List<String> lines) : lines = _normalize(lines);

  const HeaderColumn.empty() : lines = const <String>['', '', ''];

  /// عدد أسطر كل عمود في النموذج الوزاري.
  static const int lineCount = 3;

  final List<String> lines;

  static List<String> _normalize(List<String> source) {
    final normalized = List<String>.generate(
      lineCount,
      // لا قصّ للمسافات هنا: النص يُحرَّر مباشرة على الورقة والقصّ أثناء
      // الكتابة يُفسد المؤشر؛ التنظيف يتم عند العرض فقط.
      (index) => index < source.length ? source[index] : '',
      growable: false,
    );
    return List<String>.unmodifiable(normalized);
  }

  /// يُرجع نسخة مع تبديل السطر [index].
  HeaderColumn withLine(int index, String value) {
    if (index < 0 || index >= lineCount) {
      throw RangeError.index(index, lines, 'index');
    }
    final updated = List<String>.of(lines);
    updated[index] = value;
    return HeaderColumn(updated);
  }

  bool get isEmpty => lines.every((line) => line.trim().isEmpty);

  List<String> toList() => List<String>.of(lines);

  /// يقرأ عموداً **بشكل صارم**: يجب أن يكون قائمة نصوص.
  factory HeaderColumn.fromValue(Object? value) {
    if (value == null) {
      return const HeaderColumn.empty();
    }
    if (value is! List) {
      throw const FormatException('HeaderColumn: عمود الترويسة يجب أن يكون قائمة.');
    }
    final lines = <String>[];
    for (final entry in value) {
      if (entry != null && entry is! String && entry is! num) {
        throw const FormatException('HeaderColumn: سطر الترويسة يجب أن يكون نصاً.');
      }
      lines.add(entry?.toString() ?? '');
    }
    return HeaderColumn(lines);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HeaderColumn || other.lines.length != lines.length) {
      return false;
    }
    for (var index = 0; index < lines.length; index++) {
      if (lines[index] != other.lines[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(lines);
}

/// مواضع أعمدة الترويسة الثلاثة.
enum HeaderSlot { right, center, left }

/// ترويسة النموذج الوزاري (ExamHeaderModel): ثلاثة أعمدة × ثلاثة أسطر.
///
/// - اليمين: مثلاً التاريخ، المادة، الصف.
/// - الوسط: وزارة التربية، اسم المدرسة، «امتحانات نصف السنة 2026/2027 — الدور».
/// - اليسار: الوقت، الاسم، الرقم الامتحاني.
///
/// حقل [subject] منفصل ومهيكل لأنه يحدّد قالب التنسيق ([layoutTemplate])
/// ولا يُترك لنصّ حر داخل الأعمدة.
class ExamHeaderModel {
  ExamHeaderModel({
    required this.subject,
    HeaderColumn? right,
    HeaderColumn? center,
    HeaderColumn? left,
    this.instructions = '',
    this.title = '',
    this.notes = '',
    PaperTextStyle? style,
    SubjectLayoutTemplate? layoutTemplate,
  })  : right = right ?? const HeaderColumn.empty(),
        center = center ?? const HeaderColumn.empty(),
        left = left ?? const HeaderColumn.empty(),
        style = style ?? PaperTextStyle.empty,
        layoutTemplate =
            layoutTemplate ?? SubjectLayoutTemplate.fromSubject(subject);

  /// ترويسة وزارية افتراضية جاهزة للعام الدراسي 2026/2027.
  factory ExamHeaderModel.ministerialDefault({
    String subject = 'اللغة العربية',
    String schoolName = 'اسم المدرسة',
    String gradeStage = 'الصف الثالث المتوسط',
    String academicYear = '2026 / 2027',
    String examRound = 'الدور الأول',
    String duration = 'ساعتان ونصف',
  }) {
    final template = SubjectLayoutTemplate.fromSubject(subject);
    if (template.isLtr) {
      return ExamHeaderModel(
        subject: subject,
        layoutTemplate: template,
        right: HeaderColumn(<String>['Ministry of Education', schoolName, gradeStage]),
        center: HeaderColumn(<String>[
          'Mid-Year Examinations $academicYear',
          'Subject: $subject',
          examRound,
        ]),
        left: HeaderColumn(<String>['Time: $duration', 'Name:', 'Exam No.:']),
        instructions: 'Answer all of the following questions.',
      );
    }
    return ExamHeaderModel(
      subject: subject,
      layoutTemplate: template,
      right: HeaderColumn(<String>['التاريخ:      /      /', 'المادة: $subject', gradeStage]),
      center: HeaderColumn(<String>[
        'وزارة التربية — $schoolName',
        'امتحانات نصف السنة للعام الدراسي $academicYear',
        examRound,
      ]),
      left: HeaderColumn(<String>['الوقت: $duration', 'الاسم:', 'الرقم الامتحاني:']),
      instructions: 'ملاحظة: أجب عن جميع الأسئلة الآتية.',
    );
  }

  final String subject;
  final HeaderColumn right;
  final HeaderColumn center;
  final HeaderColumn left;
  final String instructions;

  /// عنوان الامتحان أعلى الترويسة (اختياري).
  final String title;

  /// ملاحظات إضافية أسفل الترويسة (اختياري).
  final String notes;

  /// تنسيق نصوص الترويسة (خط/حجم/عريض/محاذاة).
  final PaperTextStyle style;

  final SubjectLayoutTemplate layoutTemplate;

  HeaderColumn column(HeaderSlot slot) {
    switch (slot) {
      case HeaderSlot.right:
        return right;
      case HeaderSlot.center:
        return center;
      case HeaderSlot.left:
        return left;
    }
  }

  /// نسخة مع تعديل سطر واحد في عمود محدد (للتحرير المباشر على الورقة).
  ExamHeaderModel withLine(HeaderSlot slot, int lineIndex, String value) {
    final updated = column(slot).withLine(lineIndex, value);
    switch (slot) {
      case HeaderSlot.right:
        return copyWith(right: updated);
      case HeaderSlot.center:
        return copyWith(center: updated);
      case HeaderSlot.left:
        return copyWith(left: updated);
    }
  }

  ExamHeaderModel copyWith({
    String? subject,
    HeaderColumn? right,
    HeaderColumn? center,
    HeaderColumn? left,
    String? instructions,
    String? title,
    String? notes,
    PaperTextStyle? style,
    SubjectLayoutTemplate? layoutTemplate,
  }) {
    final nextSubject = subject ?? this.subject;
    return ExamHeaderModel(
      subject: nextSubject,
      right: right ?? this.right,
      center: center ?? this.center,
      left: left ?? this.left,
      instructions: instructions ?? this.instructions,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      style: style ?? this.style,
      // تغيير المادة يعيد اختيار القالب آلياً ما لم يُحدَّد قالب صراحة.
      layoutTemplate: layoutTemplate ??
          (subject == null
              ? this.layoutTemplate
              : SubjectLayoutTemplate.fromSubject(nextSubject)),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'subject': subject,
      'right': right.toList(),
      'center': center.toList(),
      'left': left.toList(),
      'instructions': instructions,
      if (title.isNotEmpty) 'title': title,
      if (notes.isNotEmpty) 'notes': notes,
      if (style.isNotEmpty) 'style': style.toMap(),
      'layoutTemplate': layoutTemplate.name,
    };
  }

  /// يقرأ الترويسة **بشكل صارم**؛ أي عمود تالف يرمي [FormatException].
  factory ExamHeaderModel.fromMap(Map<String, dynamic> map) {
    final rawSubject = map['subject'];
    if (rawSubject is! String || rawSubject.trim().isEmpty) {
      throw const FormatException('ExamHeaderModel: حقل المادة (subject) مفقود.');
    }
    final rawTemplate = map['layoutTemplate'];
    if (rawTemplate != null && rawTemplate is! String) {
      throw const FormatException('ExamHeaderModel: قالب التنسيق يجب أن يكون نصاً.');
    }
    return ExamHeaderModel(
      subject: rawSubject.trim(),
      right: HeaderColumn.fromValue(map['right']),
      center: HeaderColumn.fromValue(map['center']),
      left: HeaderColumn.fromValue(map['left']),
      instructions: map['instructions']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      style: PaperTextStyle.fromValue(map['style']),
      layoutTemplate: rawTemplate == null
          ? null
          : SubjectLayoutTemplate.parse(rawTemplate as String),
    );
  }
}
