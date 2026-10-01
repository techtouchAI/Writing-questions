import 'exam_catalog.dart';
import 'paper_text_style.dart';
import 'subject_layout.dart';

/// بيانات ترويسة ورقة الأسئلة (ثلاثة أعمدة).
///
/// الأعمدة نفسها لا تُخزَّن: كل ما هنا **مدخلات** يحوّلها `ExamBlueprint`
/// إلى أسطر الترويسة وفق المواصفة:
///
/// - **اليمين** (نص موسَّط): «ادارة» ثم [schoolName] ثم [schoolGender].
/// - **الوسط** (نص موسَّط): البسملة اختيارياً ([showBismillah])، ثم
///   «اسئلة امتحان [examType]»، ثم «للعام الدراسي [academicYear]»، ثم
///   [session] تحت العام مباشرةً.
/// - **اليسار** (نص محاذى لليمين): «المادة: [subject]»، «الصف: [grade]»،
///   «الوقت: [time]»، «اسم الطالب: ....................».
///
/// القيم تُحفظ كما كتبها المدرس (بلا قصّ) كي لا يُفسد القصّ مؤشر الكتابة؛
/// والتنظيف يتم عند بناء المخطط. [subject] اختياري، ويحدّد قالب التنسيق
/// ([layoutTemplate]) لمنطقة الأسئلة وحدها؛ أما الترويسة فعربية دائماً.
class ExamHeaderModel {
  ExamHeaderModel({
    this.schoolName = '',
    this.schoolGender = SchoolGender.boys,
    this.showBismillah = true,
    this.examType = '',
    this.academicYear = '',
    this.session = ExamSession.first,
    this.subject = '',
    this.grade = '',
    this.time = '',
    PaperTextStyle? style,
  }) : style = style ?? PaperTextStyle.empty;

  /// ترويسة ورقة جديدة: العام الدراسي الحالي ونوع الامتحان «نصف السنة».
  factory ExamHeaderModel.initial({
    String subject = 'اللغة العربية',
    String schoolName = '',
    String examType = 'نصف السنة',
    DateTime? now,
  }) {
    return ExamHeaderModel(
      subject: subject,
      schoolName: schoolName,
      examType: examType,
      academicYear: AcademicYear.current(now),
    );
  }

  /// اسم المدرسة (مدخل حر، السطر الثاني من عمود اليمين).
  final String schoolName;

  /// السطر الثالث من عمود اليمين («للبنين»/«للبنات»/بدون).
  final SchoolGender schoolGender;

  /// البسملة أعلى عمود الوسط.
  final bool showBismillah;

  /// نوع الامتحان بعد «اسئلة امتحان» (مثل «نصف السنة»).
  final String examType;

  /// العام الدراسي بعد «للعام الدراسي» (مثل «2026/2027»).
  final String academicYear;

  /// الدور الامتحاني تحت العام الدراسي مباشرةً.
  final ExamSession session;

  /// المادة (اختيارية: الفارغ يُطبع خطاً منقطاً).
  final String subject;

  /// الصف (اختياري: الفارغ يُطبع خطاً منقطاً).
  final String grade;

  /// الوقت (اختياري: الفارغ يُطبع خطاً منقطاً).
  final String time;

  /// تنسيق نصوص الترويسة (خط/حجم/عريض/مائل/تسطير/لون).
  final PaperTextStyle style;

  /// قالب تنسيق منطقة الأسئلة المشتق من المادة.
  SubjectLayoutTemplate get layoutTemplate =>
      SubjectLayoutTemplate.fromSubject(subject);

  ExamHeaderModel copyWith({
    String? schoolName,
    SchoolGender? schoolGender,
    bool? showBismillah,
    String? examType,
    String? academicYear,
    ExamSession? session,
    String? subject,
    String? grade,
    String? time,
    PaperTextStyle? style,
  }) {
    return ExamHeaderModel(
      schoolName: schoolName ?? this.schoolName,
      schoolGender: schoolGender ?? this.schoolGender,
      showBismillah: showBismillah ?? this.showBismillah,
      examType: examType ?? this.examType,
      academicYear: academicYear ?? this.academicYear,
      session: session ?? this.session,
      subject: subject ?? this.subject,
      grade: grade ?? this.grade,
      time: time ?? this.time,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'schoolName': schoolName,
      'schoolGender': schoolGender.name,
      'showBismillah': showBismillah,
      'examType': examType,
      'academicYear': academicYear,
      'session': session.name,
      'subject': subject,
      'grade': grade,
      'time': time,
      if (style.isNotEmpty) 'style': style.toMap(),
    };
  }

  /// يقرأ الترويسة: الحقول الناقصة تأخذ القيم الافتراضية، وغير الخريطة
  /// يرمي [FormatException] ليُعزل السجل التالف.
  factory ExamHeaderModel.fromMap(Map<String, dynamic> map) {
    String text(String key) => map[key]?.toString() ?? '';
    final rawBismillah = map['showBismillah'];
    return ExamHeaderModel(
      schoolName: text('schoolName'),
      schoolGender: SchoolGender.parse(map['schoolGender']),
      showBismillah: rawBismillah is bool ? rawBismillah : true,
      examType: text('examType'),
      academicYear: text('academicYear'),
      session: ExamSession.parse(map['session']),
      subject: text('subject').trim(),
      grade: text('grade'),
      time: text('time'),
      style: PaperTextStyle.fromValue(map['style']),
    );
  }
}
