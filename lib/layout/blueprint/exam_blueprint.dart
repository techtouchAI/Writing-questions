import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/exam_catalog.dart';
import '../../models/exam_document.dart';
import '../../models/point_kind.dart';
import '../../models/question_model.dart';
import '../../models/question_option.dart';

/// مخطط الورقة (Blueprint): **الطبقة الوحيدة** التي تقرر ما يُطبع وبأي نص.
///
/// يحوّل [ExamDocument] إلى كتل نصية مُحلَّلة بالكامل (الأرقام، الدرجات
/// «(٢٠ درجة)»، تسميات النقاط والخيارات، أسطر الترويسة والتذييل، قواعد الحذف
/// عند الفراغ). والمعاينة ومحرك PDF وملف Word تكتفي برسم هذه الكتل — فلا
/// يتكرر منطق الترقيم أو الحذف أو التنسيق النصي في أي منها، وتبقى الثلاثة
/// متطابقة بالبناء. منطق خالص (Dart) بلا أي اعتماد على Flutter أو pdf.
class ExamBlueprint {
  const ExamBlueprint({
    required this.header,
    required this.footer,
    required this.questions,
  });

  factory ExamBlueprint.from(ExamDocument document) =>
      _BlueprintBuilder(document).build();

  final HeaderBlueprint header;
  final FooterBlueprint footer;
  final List<QuestionBlueprint> questions;

  QuestionBlueprint? questionById(String id) {
    for (final question in questions) {
      if (question.model.id == id) {
        return question;
      }
    }
    return null;
  }
}

// ============================ الترويسة والتذييل ============================

/// الترويسة المحلَّلة: أسطر الأعمدة الثلاثة جاهزة للطباعة.
class HeaderBlueprint {
  const HeaderBlueprint({
    required this.showBismillah,
    required this.rightLines,
    required this.centerLines,
    required this.leftLines,
    required this.framed,
  });

  /// هل تُطبع البسملة أعلى عمود الوسط (بخط خطّي مستقل)؟
  final bool showBismillah;

  String get bismillah => ExamCatalog.bismillah;

  /// عمود اليمين (نص موسَّط): «ادارة» ← اسم المدرسة ← «للبنين».
  final List<String> rightLines;

  /// عمود الوسط (نص موسَّط): «اسئلة امتحان …» ← «للعام الدراسي …» ← الدور.
  /// البسملة منفصلة عنها لأن لها خطاً مختلفاً.
  final List<String> centerLines;

  /// عمود اليسار (نص محاذى لليمين): المادة ← الصف ← الوقت ← اسم الطالب.
  final List<String> leftLines;

  /// إطار حول جدول الترويسة (إعداد الورقة).
  final bool framed;
}

/// كتلة توقيع محلَّلة.
class SignatureBlueprint {
  const SignatureBlueprint({required this.title, required this.name});

  /// لقب الموقّع («مدرس المادة»...).
  final String title;

  /// اسم الموقّع (قد يكون فارغاً).
  final String name;

  /// السطر المطبوع تحت اللقب: الاسم، أو خط منقّط للتوقيع اليدوي عند فراغه.
  String get nameLine => name.isEmpty ? ExamCatalog.blankLine : name;
}

/// التذييل المحلَّل: العبارة الختامية في الوسط، والتوقيع الأساسي يساراً،
/// والثاني يميناً (فقط إن أضافه المدرس).
class FooterBlueprint {
  const FooterBlueprint({
    required this.closingPhrase,
    required this.primary,
    required this.secondary,
  });

  /// العبارة الختامية (`null` = مخفية).
  final String? closingPhrase;

  /// التوقيع الأساسي — يسار الورقة دائماً.
  final SignatureBlueprint primary;

  /// التوقيع الثاني — يمين الورقة، `null` ما لم يُضَف صراحةً.
  final SignatureBlueprint? secondary;
}

// ============================ السؤال والفرع والنقاط ============================

/// سطر العنوان: الرقم ← المنطوق ← الدرجة «(٢٠ درجة)».
class TitleLineBlueprint {
  const TitleLineBlueprint({
    required this.number,
    required this.statement,
    required this.marks,
  });

  /// الرقم المطبوع («السؤال الأول/» أو ما كتبه المدرس حرفياً، «أ)»...).
  final String number;

  /// المنطوق (قد يكون فارغاً).
  final String statement;

  /// الدرجة منسّقة «(٢٠ درجة)» — `null` إن كانت صفراً أو مخفية بالإعداد.
  final String? marks;

  bool get hasStatement => statement.isNotEmpty;

  /// السطر كاملاً نصاً واحداً (للتصدير النصي والاختبارات).
  String get line => <String>[
        number,
        if (statement.isNotEmpty) statement,
        if (marks != null) marks!,
      ].join(' ');
}

/// خيار «اختيار من متعدد» محلَّل (يحمل تسميته بفهرسه الأصلي).
class OptionBlueprint {
  const OptionBlueprint({
    required this.index,
    required this.option,
    required this.label,
  });

  final int index;
  final QuestionOption option;

  /// التسمية المطبوعة «( أ )» (تلقائية بالفهرس أو مخصصة؛ فارغة = بلا تسمية).
  final String label;

  String get text => option.text.trim();

  /// الخيار سطراً واحداً: التسمية ثم النص.
  String get line => label.isEmpty ? text : '$label $text';
}

/// نقطة مرقّمة محلَّلة.
class PointBlueprint {
  const PointBlueprint({
    required this.item,
    required this.index,
    required this.label,
    required this.text,
    required this.trailer,
    required this.marks,
    required this.options,
  });

  final BranchItem item;
  final int index;

  /// الرقم المطبوع «١-» (تسلسل متصل بالفهرس مهما اختلف النوع؛ فارغ = بلا رقم).
  final String label;

  /// نص النقطة كما كتبه المدرس (بعد قصّ الأطراف).
  final String text;

  /// ما يُلحق بالنص: قوسا إجابة «صح/خطأ» الفارغان، أو فراغ منقّط لجملة
  /// «إكمال الفراغ» بلا فراغ، وإلا `null`.
  final String? trailer;

  /// درجة النقطة «(٢ درجة)» أو `null`.
  final String? marks;

  /// الخيارات المكتوبة فقط (اختيار من متعدد).
  final List<OptionBlueprint> options;

  PointKind get kind => item.kind;

  /// هل تُطبع النقطة؟ (الفارغة تماماً بلا تسمية ولا درجة تُحذف).
  bool get isPrintable => item.showsInExport;

  /// سطر النقطة الرئيسي: الرقم ← النص ← القوسان ← الدرجة.
  String get line => <String>[
        if (label.isNotEmpty) label,
        if (text.isNotEmpty) text,
        if (trailer != null) trailer!,
        if (marks != null) marks!,
      ].join(' ');

  /// سطر خيارات «اختيار من متعدد» (فارغ إن لم يُكتب خيار).
  String get optionsLine =>
      options.map((option) => option.line).join('\u00A0\u00A0\u00A0\u00A0\u00A0');
}

/// فرع محلَّل: الرقم ← المنطوق ← الدرجة ← النص ← النقاط.
class BranchBlueprint {
  const BranchBlueprint({
    required this.model,
    required this.questionIndex,
    required this.branchIndex,
    required this.title,
    required this.body,
    required this.points,
  });

  final BranchModel model;
  final int questionIndex;
  final int branchIndex;
  final TitleLineBlueprint title;

  /// نص الفرع (`null` = فارغ فيُحذف كلياً).
  final String? body;
  final List<PointBlueprint> points;

  /// هل يُطبع الفرع؟ (الفارغ تماماً يُحذف مع فاصله).
  bool isPrintable({Set<String> ignoredAttachmentIds = const <String>{}}) =>
      model.hasExportableContentIn(ignoredAttachmentIds: ignoredAttachmentIds);
}

/// سؤال محلَّل: القسم ← سطر العنوان ← النص ← النقاط ← الفروع.
class QuestionBlueprint {
  const QuestionBlueprint({
    required this.model,
    required this.index,
    required this.section,
    required this.title,
    required this.body,
    required this.points,
    required this.branches,
  });

  final QuestionModel model;
  final int index;

  /// عنوان القسم (`null` = بلا قسم).
  final String? section;
  final TitleLineBlueprint title;

  /// نص السؤال (`null` = فارغ فيُحذف كلياً من الواجهة والطباعة).
  final String? body;
  final List<PointBlueprint> points;
  final List<BranchBlueprint> branches;

  /// هل يُطبع السؤال؟ (الفارغ يبقى مساحة تحرير فقط.)
  bool isPrintable({Set<String> ignoredAttachmentIds = const <String>{}}) =>
      model.hasExportableContent(ignoredAttachmentIds: ignoredAttachmentIds);
}

// ============================ الباني ============================

class _BlueprintBuilder {
  _BlueprintBuilder(this.document)
      : showMarks = document.settings.showQuestionMarks;

  final ExamDocument document;
  final bool showMarks;

  /// أي فراغ كتبه المدرس بنفسه في جملة «إكمال الفراغ» (شرطات سفلية أو نقاط).
  static final RegExp _blankMarker = RegExp(r'_{3,}|\.{4,}|\u2026');

  ExamBlueprint build() {
    return ExamBlueprint(
      header: _header(),
      footer: _footer(),
      questions: <QuestionBlueprint>[
        for (var index = 0; index < document.questions.length; index++)
          _question(index),
      ],
    );
  }

  // --------------------------- الترويسة ---------------------------

  String _value(String raw) => document.localizeDigits(raw.trim());

  HeaderBlueprint _header() {
    final header = document.header;
    final school = _value(header.schoolName);
    final examType = _value(header.examType);
    final year = _value(header.academicYear);
    final gender = header.schoolGender.label;
    final session = header.session.label;

    String labeled(String label, String value) =>
        value.isEmpty ? label : '$label $value';
    String field(String label, String value) =>
        '$label ${value.isEmpty ? ExamCatalog.blankLine : value}';

    return HeaderBlueprint(
      showBismillah: header.showBismillah,
      rightLines: <String>[
        ExamCatalog.administrationLabel,
        if (school.isNotEmpty) school,
        if (gender.isNotEmpty) gender,
      ],
      centerLines: <String>[
        labeled(ExamCatalog.examTitlePrefix, examType),
        labeled(ExamCatalog.academicYearPrefix, year),
        if (session.isNotEmpty) session,
      ],
      leftLines: <String>[
        field(ExamCatalog.subjectLabel, _value(header.subject)),
        field(ExamCatalog.gradeLabel, _value(header.grade)),
        field(ExamCatalog.timeLabel, _value(header.time)),
        '${ExamCatalog.studentNameLabel} ${ExamCatalog.blankLine}',
      ],
      framed: document.settings.headerBorder,
    );
  }

  // --------------------------- التذييل ---------------------------

  FooterBlueprint _footer() {
    final footer = document.footer;
    SignatureBlueprint signature(String title, String name) =>
        SignatureBlueprint(title: title, name: name.trim());
    final phrase = footer.closingPhrase.trim();
    final secondary = footer.secondary;
    return FooterBlueprint(
      closingPhrase: phrase.isEmpty ? null : phrase,
      primary: signature(footer.primary.title.label, footer.primary.name),
      secondary: secondary == null
          ? null
          : signature(secondary.title.label, secondary.name),
    );
  }

  // --------------------------- الأسئلة ---------------------------

  /// الدرجة بنسق «(٢٠ درجة)» — `null` عند الإخفاء بالإعداد أو الدرجة صفر.
  String? _marks(double marks) {
    if (!showMarks || marks <= 0) {
      return null;
    }
    return '(${document.formatNumber(marks)} ${document.layout.marksUnit})';
  }

  String? _nonBlank(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  QuestionBlueprint _question(int index) {
    final question = document.questions[index];
    final manual = question.numberOverride?.trim();
    // ما يكتبه المدرس يُطبع حرفياً («س١/»)؛ والتلقائي يلحقه الفاصل القياسي.
    final number = (manual != null && manual.isNotEmpty)
        ? manual
        : '${document.autoQuestionLabel(question)}'
            '${document.layout.questionSeparator}';
    final category = question.category.trim();
    return QuestionBlueprint(
      model: question,
      index: index,
      section: category.isEmpty ? null : category,
      title: TitleLineBlueprint(
        number: number,
        statement: question.statement.trim(),
        marks: _marks(question.marks),
      ),
      body: _nonBlank(question.body),
      points: _points(question.items),
      branches: <BranchBlueprint>[
        for (var branchIndex = 0;
            branchIndex < question.branches.length;
            branchIndex++)
          _branch(index, branchIndex),
      ],
    );
  }

  BranchBlueprint _branch(int questionIndex, int branchIndex) {
    final branch = document.questions[questionIndex].branches[branchIndex];
    final content = branch.content;
    final label = document.displayBranchLabel(questionIndex, branchIndex);
    return BranchBlueprint(
      model: branch,
      questionIndex: questionIndex,
      branchIndex: branchIndex,
      title: TitleLineBlueprint(
        number: '$label${document.layout.branchSeparator}',
        statement: content.statement.trim(),
        marks: _marks(branch.marks),
      ),
      body: _nonBlank(content.body),
      points: _points(content.items),
    );
  }

  // --------------------------- النقاط ---------------------------

  List<PointBlueprint> _points(List<BranchItem> items) {
    return <PointBlueprint>[
      for (var index = 0; index < items.length; index++)
        _point(items[index], index),
    ];
  }

  /// ما يُلحق بنص النقطة بحسب نوعها: قوسا إجابة «صح/خطأ»، وفراغ منقّط لجملة
  /// «إكمال الفراغ» التي لم يضع فيها المدرس فراغاً بنفسه.
  String? _trailer(BranchItem item, String text) {
    switch (item.kind) {
      case PointKind.trueFalse:
        return ExamCatalog.trueFalseSlot;
      case PointKind.fillBlank:
        return _blankMarker.hasMatch(text) ? null : ExamCatalog.fillBlank;
      case PointKind.plain:
      case PointKind.multipleChoice:
        return null;
    }
  }

  PointBlueprint _point(BranchItem item, int index) {
    final text = item.text.trim();
    return PointBlueprint(
      item: item,
      index: index,
      // الترقيم تسلسل واحد متصل بالفهرس بغض النظر عن نوع النقطة.
      label: document.displayItemLabel(item, index),
      text: text,
      trailer: text.isEmpty ? null : _trailer(item, text),
      marks: _marks(item.marks),
      options: <OptionBlueprint>[
        if (item.kind == PointKind.multipleChoice)
          for (var i = 0; i < item.options.length; i++)
            if (item.options[i].text.trim().isNotEmpty)
              OptionBlueprint(
                index: i,
                option: item.options[i],
                label: document.displayOptionLabel(item.options[i], i),
              ),
      ],
    );
  }
}
