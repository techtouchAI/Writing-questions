class ExamHeader {
  String institutionName;
  String title;
  String subject;
  String gradeStage;
  String academicYear;
  String duration;
  String instructor;
  String generalInstructions;

  ExamHeader({
    this.institutionName = 'وزارة التربية والتعليم',
    this.title = 'الاختبار النهائي للفصل الدراسي',
    this.subject = 'اللغة العربية',
    this.gradeStage = 'الصف الثالث الثانوي',
    this.academicYear = '2026 - 2027',
    this.duration = 'ساعتان',
    this.instructor = '',
    this.generalInstructions = 'أجب عن جميع الأسئلة التالية بوضوح ودقة.',
  });

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
    return ExamHeader(
      institutionName: map['institutionName'] ?? '',
      title: map['title'] ?? '',
      subject: map['subject'] ?? '',
      gradeStage: map['gradeStage'] ?? '',
      academicYear: map['academicYear'] ?? '',
      duration: map['duration'] ?? '',
      instructor: map['instructor'] ?? '',
      generalInstructions: map['generalInstructions'] ?? '',
    );
  }
}
