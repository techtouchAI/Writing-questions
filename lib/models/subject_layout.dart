import 'dart:ui' show TextDirection;

import 'label_alphabet.dart';
import 'subject_catalog.dart';

/// قوالب التنسيق الوزارية (وزارة التربية العراقية 2026/2027) حسب المادة.
///
/// القالب هو **مصدر الحقيقة الوحيد** لكل ما يختلف بين المواد في الورقة:
/// اتجاه الكتابة، صيغة ترقيم الأسئلة والفروع، نسق الأرقام، الأقسام
/// المعتمدة، ومساحات الإجابة — تستهلكه لوحة المعاينة ومحرك الـ PDF معاً
/// حتى تبقى الشاشة والطباعة متطابقتين.
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
  /// اللغتان العربية والتربية الإسلامية تعتمدان الأرقام المشرقية في النماذج
  /// الوزارية؛ الإنجليزية والمواد العلمية تعتمد الأرقام اللاتينية (لغة المنهج).
  bool get usesArabicIndicNumerals =>
      this == SubjectLayoutTemplate.islamic || this == SubjectLayoutTemplate.arabic;

  /// هل يُفضَّل الخط القرآني (إن توفّر في أصول التطبيق)؟
  bool get prefersQuranicFont => this == SubjectLayoutTemplate.islamic;

  /// وحدة الدرجة كما تُطبع بجانب الرقم.
  String get marksUnit => isLtr ? 'marks' : 'درجة';

  /// عدد أسطر الإجابة المتروكة للأسئلة المقالية (مساحة أوسع للمواد العلمية).
  int get essayAnswerLines => this == SubjectLayoutTemplate.scientific ? 6 : 4;

  /// معامل تباعد الأسطر (مساحة للمعادلات والموازنات في المواد العلمية).
  double get lineHeightFactor =>
      this == SubjectLayoutTemplate.scientific ? 1.8 : 1.45;

  /// الأقسام الوزارية المعتمدة للقالب (فارغة = بلا أقسام مسبقة).
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
