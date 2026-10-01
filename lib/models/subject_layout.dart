import 'dart:ui' show TextDirection;

import 'label_alphabet.dart';
import 'subject_catalog.dart';

/// قوالب تنسيق منطقة الأسئلة حسب المادة.
///
/// القالب هو **مصدر الحقيقة الوحيد** لكل ما يختلف بين المواد في منطقة
/// الأسئلة: اتجاه الكتابة، صيغة ترقيم الأسئلة والفروع، نسق الأرقام، الأقسام
/// المعتمدة، وتباعد الأسطر — تستهلكه لوحة المعاينة ومحرك الـ PDF وملف Word
/// معاً حتى تبقى الشاشة والطباعة متطابقتين. (الترويسة والتذييل عربيان دائماً.)
enum SubjectLayoutTemplate {
  /// التربية الإسلامية: أحكام التلاوة، الحفظ، الفهم والتفسير، التربية الإسلامية.
  islamic,

  /// اللغة العربية: القواعد، الأدب والنصوص، الإملاء، الإنشاء.
  arabic,

  /// اللغة الإنجليزية: اتجاه LTR كامل، ترقيم Q1/Q2 وفروع A/B/C.
  english,

  /// المواد العلمية (فيزياء، كيمياء، رياضيات، أحياء): مساحات مرنة للمعادلات.
  scientific,

  /// بقية المواد.
  generic;

  /// يختار القالب من اسم المادة كما كُتب في الترويسة.
  static SubjectLayoutTemplate fromSubject(String subject) {
    final normalized = subject.trim();
    if (SubjectCatalog.isIslamicSubject(normalized)) {
      return SubjectLayoutTemplate.islamic;
    }
    if (SubjectCatalog.isArabicSubject(normalized)) {
      return SubjectLayoutTemplate.arabic;
    }
    if (SubjectCatalog.isEnglishSubject(normalized) ||
        normalized.toLowerCase().contains('english')) {
      return SubjectLayoutTemplate.english;
    }
    if (_isScientificSubject(normalized)) {
      return SubjectLayoutTemplate.scientific;
    }
    return SubjectLayoutTemplate.generic;
  }

  static bool _isScientificSubject(String subject) {
    const markers = <String>[
      'فيزياء',
      'كيمياء',
      'رياضيات',
      'أحياء',
      'احياء',
      'علوم',
      'حاسوب',
    ];
    return markers.any(subject.contains);
  }

  /// يقرأ القالب من الاسم المخزَّن **بشكل صارم**.
  static SubjectLayoutTemplate parse(String? value) {
    final normalized = value?.trim() ?? '';
    for (final template in SubjectLayoutTemplate.values) {
      if (template.name == normalized) {
        return template;
      }
    }
    throw FormatException(
      'SubjectLayoutTemplate: قالب غير معروف (${value ?? 'مفقود'}).',
    );
  }

  String get arabicLabel {
    switch (this) {
      case SubjectLayoutTemplate.islamic:
        return 'قالب التربية الإسلامية';
      case SubjectLayoutTemplate.arabic:
        return 'قالب اللغة العربية';
      case SubjectLayoutTemplate.english:
        return 'English Layout';
      case SubjectLayoutTemplate.scientific:
        return 'قالب المواد العلمية';
      case SubjectLayoutTemplate.generic:
        return 'القالب العام';
    }
  }

  /// اتجاه العرض الكامل للورقة.
  TextDirection get textDirection =>
      this == SubjectLayoutTemplate.english ? TextDirection.ltr : TextDirection.rtl;

  bool get isLtr => textDirection == TextDirection.ltr;

  /// هل تُعرض الأرقام بالنسق العربي المشرقي (٠١٢٣)؟
  ///
  /// كل القوالب العربية (RTL) تعتمد الأرقام المشرقية افتراضياً — فتُطبع
  /// الدرجة «(٢٠ درجة)» والترقيم «١-» والعام «٢٠٢٦/٢٠٢٧» مهما كانت المادة —
  /// أما قالب الإنجليزية فيعتمد اللاتينية. وإعداد «نسق الأرقام» في الورقة
  /// يتقدم على هذا الافتراض.
  bool get usesArabicIndicNumerals => !isLtr;

  /// هل يُفضَّل الخط القرآني (إن توفّر في أصول التطبيق)؟
  bool get prefersQuranicFont => this == SubjectLayoutTemplate.islamic;

  /// وحدة الدرجة كما تُطبع بجانب الرقم.
  String get marksUnit => isLtr ? 'marks' : 'درجة';

  /// معامل تباعد الأسطر (مساحة للمعادلات والموازنات في المواد العلمية).
  double get lineHeightFactor =>
      this == SubjectLayoutTemplate.scientific ? 1.8 : 1.45;

  /// أقسام السؤال المقترحة للقالب (فارغة = بلا أقسام مسبقة).
  List<String> get sections {
    switch (this) {
      case SubjectLayoutTemplate.islamic:
        return const <String>[
          'أحكام التلاوة',
          'الحفظ',
          'الفهم والتفسير',
          'التربية الإسلامية',
        ];
      case SubjectLayoutTemplate.arabic:
        return const <String>['القواعد', 'الأدب والنصوص', 'الإملاء', 'الإنشاء'];
      case SubjectLayoutTemplate.english:
      case SubjectLayoutTemplate.scientific:
      case SubjectLayoutTemplate.generic:
        return const <String>[];
    }
  }

  /// الفاصل المطبوع بعد رقم السؤال المولَّد تلقائياً («السؤال الأول/»).
  /// الرقم الذي يكتبه المدرس يُطبع حرفياً دون إضافة فاصل.
  String get questionSeparator => isLtr ? '.' : '/';

  /// الفاصل المطبوع بعد تسمية الفرع («أ)»).
  String get branchSeparator => ')';

  /// تسمية السؤال الكاملة: «السؤال الأول» أو «Q1».
  String questionLabel(int number) {
    if (isLtr) {
      return 'Q$number';
    }
    return 'السؤال ${arabicOrdinal(number)}';
  }

  /// تسمية الفرع: «أ» أو «A».
  String branchLabel(int index) {
    if (isLtr) {
      if (index < 0) {
        return '1';
      }
      if (index < 26) {
        return String.fromCharCode('A'.codeUnitAt(0) + index);
      }
      return '${index + 1}';
    }
    return LabelAlphabet.at(index);
  }

  /// يُنسّق درجة أو عدداً وفق نسق أرقام القالب.
  String formatNumber(num value) {
    final text = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
    return usesArabicIndicNumerals ? toArabicIndic(text) : text;
  }

  /// يحوّل الأرقام العربية المشرقية داخل [text] إلى أرقام لاتينية.
  static String toLatinDigits(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0x660 && rune <= 0x669) {
        buffer.write(rune - 0x660);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// يحوّل الأرقام اللاتينية داخل [text] إلى أرقام عربية مشرقية.
  static String toArabicIndic(String text) {
    const digits = <String>['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.write(digits[rune - 0x30]);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// الترتيب العربي اللفظي (الأول، الثاني...) حتى العشرين، ثم رقمياً.
  static String arabicOrdinal(int number) {
    const ordinals = <String>[
      'الأول',
      'الثاني',
      'الثالث',
      'الرابع',
      'الخامس',
      'السادس',
      'السابع',
      'الثامن',
      'التاسع',
      'العاشر',
      'الحادي عشر',
      'الثاني عشر',
      'الثالث عشر',
      'الرابع عشر',
      'الخامس عشر',
      'السادس عشر',
      'السابع عشر',
      'الثامن عشر',
      'التاسع عشر',
      'العشرون',
    ];
    if (number >= 1 && number <= ordinals.length) {
      return ordinals[number - 1];
    }
    return 'رقم $number';
  }
}
