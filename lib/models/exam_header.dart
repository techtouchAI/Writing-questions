import 'exam_duration_rules.dart';

/// ترويسة ورقة الاختبار — تمثّل «بيانات الامتحان» الصارمة (ExamMeta)
/// في هندسة محرك الأسئلة: لا يُترك أي حقل وزاري لنص حر غير مُهيكل.
class ExamHeader {
  final String institutionName;
  final String directorate;
  final String section;
  final String examType;
  final String title;
  final String subject;
  final String gradeStage;
  final String academicYear;
  final String duration;
  final String instructor;
  final String generalInstructions;
  final DateTime? examDate;

  ExamHeader({
    this.institutionName = 'وزارة التربية والتعليم',
    this.directorate = '',
    this.section = '',
    this.examType = '',
    this.title = 'الاختبار النهائي للفصل الدراسي',
    this.subject = 'اللغة العربية',
    this.gradeStage = 'الصف الثالث الثانوي',
    String? academicYear,
    this.duration = 'ساعتان',
    this.instructor = '',
    this.generalInstructions = 'أجب عن جميع الأسئلة التالية بوضوح ودقة.',
    this.examDate,
  }) : academicYear = academicYear ?? _defaultAcademicYear();

  /// الزمن المعروض: المدخل اليدوي أولاً، وإلا يُحسب آلياً حسب قواعد الوزارة.
  String get computedDuration {
    final manual = duration.trim();
    if (manual.isNotEmpty) {
      return manual;
    }
    return ExamDurationRules.calculate(grade: gradeStage, subject: subject);
  }

  static String _defaultAcademicYear() {
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    return '$startYear - ${startYear + 1}';
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionName': institutionName,
      'directorate': directorate,
      'section': section,
      'examType': examType,
      'title': title,
      'subject': subject,
      'gradeStage': gradeStage,
      'academicYear': academicYear,
      'duration': duration,
      'instructor': instructor,
      'generalInstructions': generalInstructions,
      'examDate': examDate?.toIso8601String(),
    };
  }

  factory ExamHeader.fromMap(Map<String, dynamic> map) {
    final defaults = ExamHeader();
    return ExamHeader(
      institutionName: _stringOrDefault(map['institutionName'], defaults.institutionName),
      directorate: _stringOrDefault(map['directorate'], ''),
      section: _stringOrDefault(map['section'], ''),
      examType: _stringOrDefault(map['examType'], ''),
      title: _stringOrDefault(map['title'], defaults.title),
      subject: _stringOrDefault(map['subject'], defaults.subject),
      gradeStage: _stringOrDefault(map['gradeStage'], defaults.gradeStage),
      academicYear: _stringOrDefault(map['academicYear'], defaults.academicYear),
      duration: _stringOrDefault(map['duration'], defaults.duration),
      instructor: _stringOrDefault(map['instructor'], defaults.instructor),
      generalInstructions: _stringOrDefault(
        map['generalInstructions'],
        defaults.generalInstructions,
      ),
      examDate: _dateFromValue(map['examDate']),
    );
  }

  ExamHeader copyWith({
    String? institutionName,
    String? directorate,
    String? section,
    String? examType,
    String? title,
    String? subject,
    String? gradeStage,
    String? academicYear,
    String? duration,
    String? instructor,
    String? generalInstructions,
    DateTime? examDate,
  }) {
    return ExamHeader(
      institutionName: institutionName ?? this.institutionName,
      directorate: directorate ?? this.directorate,
      section: section ?? this.section,
      examType: examType ?? this.examType,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      gradeStage: gradeStage ?? this.gradeStage,
      academicYear: academicYear ?? this.academicYear,
      duration: duration ?? this.duration,
      instructor: instructor ?? this.instructor,
      generalInstructions: generalInstructions ?? this.generalInstructions,
      examDate: examDate ?? this.examDate,
    );
  }

  static String _stringOrDefault(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static DateTime? _dateFromValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}
