/// الكتالوجات الثابتة لورقة الأسئلة: النصوص الحرفية للترويسة والتذييل، وقوائم
/// الاختيار (العبارات الختامية، ألقاب التوقيع، الأدوار الامتحانية...).
///
/// هذا الملف **مصدر الحقيقة الوحيد** لهذه النصوص: تستهلكها الواجهة والمعاينة
/// ومحرك PDF وملف Word عبر `ExamBlueprint` فلا يتكرر حرف منها في أي مكان آخر،
/// وتبقى مطابقة حرفياً لمواصفة الورقة.
abstract final class ExamCatalog {
  /// البسملة (تُعرض بخط خطّي أنيق أعلى عمود الوسط عند تفعيلها).
  static const String bismillah = 'بسم الله الرحمن الرحيم';

  /// السطر الأول من عمود اليمين (ثابت حرفياً) يليه اسم المدرسة ثم «للبنين».
  static const String administrationLabel = 'ادارة';

  /// بادئة سطر نوع الامتحان في عمود الوسط: «اسئلة امتحان [نوع الامتحان]».
  static const String examTitlePrefix = 'اسئلة امتحان';

  /// بادئة سطر العام الدراسي: «للعام الدراسي [٢٠٢٦/٢٠٢٧]».
  static const String academicYearPrefix = 'للعام الدراسي';

  static const String subjectLabel = 'المادة:';
  static const String gradeLabel = 'الصف:';
  static const String timeLabel = 'الوقت:';
  static const String studentNameLabel = 'اسم الطالب:';

  /// خط منقّط يُطبع بدل أي قيمة فارغة (المادة/الصف/الوقت/اسم الطالب).
  static const String blankLine = '....................';

  /// فراغ إكمال الجملة المنقّط (يُلحق بجملة «إكمال الفراغ» التي لا فراغ فيها).
  static const String fillBlank = '............';

  /// قوسا إجابة «صح/خطأ» الفارغان (مسافات غير قابلة للكسر داخل القوسين).
  static const String trueFalseSlot =
      '(\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0)';

  /// اقتراحات سريعة لحقل نوع الامتحان (والإدخال الحر متاح دائماً).
  static const List<String> examTypeSuggestions = <String>[
    'نصف السنة',
    'نهاية السنة',
    'الشهر الأول',
    'الشهر الثاني',
    'الشهر الثالث',
    'الكورس الأول',
    'الكورس الثاني',
  ];

  /// اقتراحات سريعة لحقل الوقت (والإدخال الحر متاح دائماً).
  static const List<String> timeSuggestions = <String>[
    'نصف ساعة',
    'ساعة واحدة',
    'ساعة ونصف',
    'ساعتان',
    'ساعتان ونصف',
    'ثلاث ساعات',
  ];

  /// العبارات الختامية العشر المعتمدة (قائمة منسدلة، ويمكن إخفاء العبارة).
  static const List<String> closingPhrases = <String>[
    'انتهت الأسئلة',
    'تمنياتنا لكم بالنجاح والتوفيق',
    'مع تمنياتنا لجميع الطلبة بالنجاح',
    'مع تمنياتي لكم بالنجاح والتفوق',
    'وفقكم الله ونجحكم',
    'بالتوفيق والنجاح للجميع',
    'مع أطيب التمنيات بالنجاح والتفوق',
    'وفقكم الله لما يحب ويرضى',
    'انتهت الأسئلة مع تمنياتنا بالنجاح',
    'والله ولي التوفيق',
  ];

  /// العبارة الختامية الافتراضية لورقة جديدة.
  static const String defaultClosingPhrase = 'تمنياتنا لكم بالنجاح والتوفيق';
}

/// جنس المدرسة: السطر الثالث من عمود اليمين («للبنين» افتراضياً).
enum SchoolGender {
  boys,
  girls,
  none;

  /// النص المطبوع (فارغ = السطر مخفي).
  String get label {
    switch (this) {
      case SchoolGender.boys:
        return 'للبنين';
      case SchoolGender.girls:
        return 'للبنات';
      case SchoolGender.none:
        return '';
    }
  }

  /// التسمية المعروضة في القائمة المنسدلة.
  String get menuLabel => this == SchoolGender.none ? 'بدون' : label;

  static SchoolGender parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final gender in SchoolGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return SchoolGender.boys;
  }
}

/// الدور الامتحاني: يُطبع مباشرةً تحت العام الدراسي في عمود الوسط.
enum ExamSession {
  none,
  first,
  second,
  third;

  /// النص المطبوع (فارغ = السطر مخفي).
  String get label {
    switch (this) {
      case ExamSession.none:
        return '';
      case ExamSession.first:
        return 'الدور الأول';
      case ExamSession.second:
        return 'الدور الثاني';
      case ExamSession.third:
        return 'الدور الثالث';
    }
  }

  /// التسمية المعروضة في القائمة المنسدلة.
  String get menuLabel => this == ExamSession.none ? 'بدون دور' : label;

  static ExamSession parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final session in ExamSession.values) {
      if (session.name == normalized) {
        return session;
      }
    }
    return ExamSession.first;
  }
}

/// لقب كتلة التوقيع في التذييل (قائمة منسدلة من أربعة ألقاب).
enum SignatureTitle {
  lecturer,
  educator,
  lecturerFemale,
  educatorFemale;

  String get label {
    switch (this) {
      case SignatureTitle.lecturer:
        return 'مدرس المادة';
      case SignatureTitle.educator:
        return 'معلم المادة';
      case SignatureTitle.lecturerFemale:
        return 'مدرسة المادة';
      case SignatureTitle.educatorFemale:
        return 'معلمة المادة';
    }
  }

  static SignatureTitle parse(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final title in SignatureTitle.values) {
      if (title.name == normalized) {
        return title;
      }
    }
    return SignatureTitle.lecturer;
  }
}

/// العام الدراسي: يبدأ في أيلول ويمتد لأيلول التالي («2026/2027»).
///
/// الأرقام تُخزَّن لاتينية قياسية، ويحوّلها المخطط (Blueprint) إلى نسق أرقام
/// الورقة المختار (مشرقية ٢٠٢٦/٢٠٢٧ افتراضياً للعربية).
abstract final class AcademicYear {
  static const int _firstMonthOfYear = 9;

  static int _startYear(DateTime date) =>
      date.month >= _firstMonthOfYear ? date.year : date.year - 1;

  /// العام الدراسي الذي يضم [now] (الآن افتراضياً).
  static String current([DateTime? now]) {
    final start = _startYear(now ?? DateTime.now());
    return '$start/${start + 1}';
  }

  /// اقتراحات القائمة: العام السابق والحالي والتالي.
  static List<String> suggestions([DateTime? now]) {
    final start = _startYear(now ?? DateTime.now());
    return <String>[
      '${start - 1}/$start',
      '$start/${start + 1}',
      '${start + 1}/${start + 2}',
    ];
  }
}
