class ExamHeader {
  final String institutionName;
  final String title;
  final String subject;
  final String gradeStage;
  final String academicYear;
  final String duration;
  final String instructor;
  final String generalInstructions;

  ExamHeader({
    this.institutionName = 'وزارة التربية والتعليم',
    this.title = 'الاختبار النهائي للفصل الدراسي',
    this.subject = 'اللغة العربية',
    this.gradeStage = 'الصف الثالث الثانوي',
    String? academicYear,
    this.duration = 'ساعتان',
    this.instructor = '',
    this.generalInstructions = 'أجب عن جميع الأسئلة التالية بوضوح ودقة.',
  }) : academicYear = academicYear ?? _defaultAcademicYear();

  static String _defaultAcademicYear() {
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    return '$startYear - ${startYear + 1}';
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionName': institutionName,
      'title': title,
      'subject': subject,
      'gradeStage': gradeStage,
      'academicYear': academicYear,
      'duration': duration,
      'instructor': instructor,
      'generalInstructions': generalInstructions,
    };
  }

  factory ExamHeader.fromMap(Map<String, dynamic> map) {
    final defaults = ExamHeader();
    return ExamHeader(
      institutionName: _stringOrDefault(map['institutionName'], defaults.institutionName),
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
    );
  }

  ExamHeader copyWith({
    String? institutionName,
    String? title,
    String? subject,
    String? gradeStage,
    String? academicYear,
    String? duration,
    String? instructor,
    String? generalInstructions,
  }) {
    return ExamHeader(
      institutionName: institutionName ?? this.institutionName,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      gradeStage: gradeStage ?? this.gradeStage,
      academicYear: academicYear ?? this.academicYear,
      duration: duration ?? this.duration,
      instructor: instructor ?? this.instructor,
      generalInstructions: generalInstructions ?? this.generalInstructions,
    );
  }

  static String _stringOrDefault(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }
}
