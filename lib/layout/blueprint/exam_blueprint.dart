import '../../models/branch_item.dart';
import '../../models/branch_model.dart';
import '../../models/exam_catalog.dart';
import '../../models/exam_document.dart';
import '../../models/point_kind.dart';
import '../../models/question_model.dart';
import '../../models/question_option.dart';
import '../document_direction.dart';
import '../semantic/inline_nodes.dart';

/// Business blueprint for the selected/ordered content of a paper.
///
/// It decides what is printable, in what order, and which domain records own
/// each semantic part. New content is kept as typed nodes; the legacy string
/// getters below are projections retained for existing exporters/tests/API
/// consumers while they are migrated through adapters.
class ExamBlueprint {
  const ExamBlueprint({
    required this.header,
    required this.footer,
    required this.questions,
    this.direction = DocumentDirection.auto,
  });

  factory ExamBlueprint.from(ExamDocument document) =>
      _BlueprintBuilder(document).build();

  final HeaderBlueprint header;
  final FooterBlueprint footer;
  final List<QuestionBlueprint> questions;
  final DocumentDirection direction;

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

enum HeaderFieldKind {
  administration,
  schoolName,
  schoolGender,
  examType,
  academicYear,
  session,
  subject,
  grade,
  time,
  studentName,
  bismillah,
  generic,
}

/// A single structured header line. Prefix labels, punctuation, and values
/// are retained as separate inline nodes in [content].
class HeaderLineBlueprint {
  const HeaderLineBlueprint({
    required this.field,
    required this.content,
    this.bold = false,
  });

  final HeaderFieldKind field;
  final InlineContent content;
  final bool bold;

  /// Legacy line projection, derived only for compatibility renderers.
  String get text => content.legacyText;
}

/// Parsed header: the old string-list getters remain for compatibility, while
/// the semantic line collections are the source for DocumentIR.
class HeaderBlueprint {
  const HeaderBlueprint({
    required this.showBismillah,
    List<String> rightLines = const <String>[],
    List<String> centerLines = const <String>[],
    List<String> leftLines = const <String>[],
    this.framed = false,
    List<HeaderLineBlueprint>? rightContentLines,
    List<HeaderLineBlueprint>? centerContentLines,
    List<HeaderLineBlueprint>? leftContentLines,
    this.bismillahSemanticContent,
  })  : _legacyRightLines = rightLines,
        _legacyCenterLines = centerLines,
        _legacyLeftLines = leftLines,
        _rightContentLines = rightContentLines,
        _centerContentLines = centerContentLines,
        _leftContentLines = leftContentLines;

  final bool showBismillah;
  final List<String> _legacyRightLines;
  final List<String> _legacyCenterLines;
  final List<String> _legacyLeftLines;
  final List<HeaderLineBlueprint>? _rightContentLines;
  final List<HeaderLineBlueprint>? _centerContentLines;
  final List<HeaderLineBlueprint>? _leftContentLines;
  final InlineContent? bismillahSemanticContent;
  final bool framed;

  String get bismillah => ExamCatalog.bismillah;

  InlineContent get bismillahContent =>
      bismillahSemanticContent ?? InlineContent.fromSource(bismillah);

  List<HeaderLineBlueprint> get rightSemanticLines =>
      _rightContentLines ?? _legacyLines(_legacyRightLines);
  List<HeaderLineBlueprint> get centerSemanticLines =>
      _centerContentLines ?? _legacyLines(_legacyCenterLines);
  List<HeaderLineBlueprint> get leftSemanticLines =>
      _leftContentLines ?? _legacyLines(_legacyLeftLines);

  /// Compatibility projections. Do not use these to construct DocumentIR.
  List<String> get rightLines =>
      _rightContentLines?.map((line) => line.text).toList(growable: false) ??
      _legacyRightLines;
  List<String> get centerLines =>
      _centerContentLines?.map((line) => line.text).toList(growable: false) ??
      _legacyCenterLines;
  List<String> get leftLines =>
      _leftContentLines?.map((line) => line.text).toList(growable: false) ??
      _legacyLeftLines;

  static List<HeaderLineBlueprint> _legacyLines(List<String> values) =>
      <HeaderLineBlueprint>[
        for (final value in values)
          HeaderLineBlueprint(
            field: HeaderFieldKind.generic,
            content: InlineContent.fromSource(value),
          ),
      ];
}

/// Signature title/name kept separately; `nameLine` remains a legacy
/// projection of the name or the dotted-signature placeholder.
class SignatureBlueprint {
  const SignatureBlueprint({
    required String title,
    required String name,
    this.semanticTitle,
    this.semanticName,
  })  : _legacyTitle = title,
        _legacyName = name;

  const SignatureBlueprint.semantic({
    required this.semanticTitle,
    required this.semanticName,
  })  : _legacyTitle = null,
        _legacyName = null;

  final String? _legacyTitle;
  final String? _legacyName;
  final LabelNode? semanticTitle;
  final InlineContent? semanticName;

  String get title => semanticTitle?.legacyText ?? _legacyTitle ?? '';
  String get name => semanticName?.legacyText ?? _legacyName ?? '';
  String get nameLine => name.isEmpty ? ExamCatalog.blankLine : name;

  InlineContent get titleContent => semanticTitle?.content ??
      InlineContent.fromSource(title, direction: DocumentDirection.rtl);
  InlineContent get nameLineContent => name.isEmpty
      ? InlineContent.literal(
          ExamCatalog.blankLine,
          direction: DocumentDirection.rtl,
        )
      : semanticName ?? InlineContent.fromSource(name, direction: DocumentDirection.rtl);
}

/// Footer content: phrase and signature fields are structured, with old text
/// getters derived for existing exporters.
class FooterBlueprint {
  const FooterBlueprint({
    String? closingPhrase,
    required this.primary,
    required this.secondary,
    this.semanticClosingPhrase,
  }) : _legacyClosingPhrase = closingPhrase;

  final String? _legacyClosingPhrase;
  final InlineContent? semanticClosingPhrase;
  final SignatureBlueprint primary;
  final SignatureBlueprint? secondary;

  String? get closingPhrase =>
      semanticClosingPhrase?.legacyText ?? _legacyClosingPhrase;
  InlineContent? get closingPhraseContent => semanticClosingPhrase ??
      (_legacyClosingPhrase == null
          ? null
          : InlineContent.fromSource(
              _legacyClosingPhrase!,
              direction: DocumentDirection.rtl,
            ));
}

// ============================ السؤال والفرع والنقاط ============================

/// A question/branch title with independently stored label/number, separator,
/// statement, and marks. `number`, `marks`, and `line` are legacy getters.
class TitleLineBlueprint {
  const TitleLineBlueprint({
    required String number,
    required String statement,
    required String? marks,
  })  : _legacyNumber = number,
        _legacyStatement = statement,
        _legacyMarks = marks,
        numberNode = null,
        separatorNode = null,
        statementContent = null,
        marksNode = null;

  const TitleLineBlueprint.semantic({
    required this.numberNode,
    required this.separatorNode,
    required this.statementContent,
    required this.marksNode,
  })  : _legacyNumber = null,
        _legacyStatement = null,
        _legacyMarks = null;

  final String? _legacyNumber;
  final String? _legacyStatement;
  final String? _legacyMarks;
  final InlineNode? numberNode;
  final SeparatorNode? separatorNode;
  final InlineContent? statementContent;
  final MarksNode? marksNode;

  InlineNode get semanticNumber => numberNode ??
      LabelNode.fromSource(
        _legacyNumber ?? '',
        role: LabelRole.question,
      );

  InlineContent get semanticStatement =>
      statementContent ?? InlineContent.fromSource(_legacyStatement ?? '');

  String get number => numberNode == null
      ? _legacyNumber ?? ''
      : '${numberNode!.legacyText}${separatorNode?.legacyText ?? ''}';
  String get statement => statementContent?.legacyText ?? _legacyStatement ?? '';
  String? get marks => marksNode?.legacyText ?? _legacyMarks;

  bool get hasStatement => statementContent?.isNotEmpty ?? statement.isNotEmpty;

  /// Legacy flat line for tests/public callers. Export adapters derive this
  /// view from the structured nodes rather than using it as semantic input.
  String get line => <String>[
        number,
        if (statement.isNotEmpty) statement,
        if (marks != null) marks!,
      ].join(' ');
}

class CategoryBlueprint {
  const CategoryBlueprint({required this.content});

  final InlineContent content;
  String get text => content.legacyText;
}

/// One option. Generated brackets/spaces, label, and option text have their
/// own node fields; [line] is a compatibility projection.
class OptionBlueprint {
  const OptionBlueprint({
    required this.index,
    required this.option,
    required String label,
  })  : _legacyLabel = label,
        labelNode = null,
        labelPrefix = const <SeparatorNode>[],
        labelSuffix = const <SeparatorNode>[],
        labelTextSeparator = null,
        content = null;

  const OptionBlueprint.semantic({
    required this.index,
    required this.option,
    required this.labelNode,
    this.labelPrefix = const <SeparatorNode>[],
    this.labelSuffix = const <SeparatorNode>[],
    this.labelTextSeparator = const SeparatorNode(
      ' ',
      role: SeparatorRole.optionLabel,
    ),
    required this.content,
  }) : _legacyLabel = null;

  final int index;
  final QuestionOption option;
  final String? _legacyLabel;
  final LabelNode? labelNode;
  final List<SeparatorNode> labelPrefix;
  final List<SeparatorNode> labelSuffix;
  final SeparatorNode? labelTextSeparator;
  final InlineContent? content;

  String get label => labelNode == null
      ? _legacyLabel ?? ''
      : <String>[
          ...labelPrefix.map((part) => part.legacyText),
          labelNode!.legacyText,
          ...labelSuffix.map((part) => part.legacyText),
        ].join();
  String get text => content?.legacyText ?? option.text.trim();
  bool get isPrintable => text.trim().isNotEmpty;

  InlineContent get semanticLabel => labelNode == null
      ? InlineContent.fromSource(label)
      : InlineContent(<InlineNode>[
          ...labelPrefix,
          labelNode!,
          ...labelSuffix,
        ]);
  InlineContent get semanticText => content ?? InlineContent.fromSource(text);

  /// Legacy option label + text projection.
  String get line => label.isEmpty
      ? text
      : '$label${labelTextSeparator?.legacyText ?? ' '}$text';
}

/// A numbered item. Its label and separator, content, trailer, marks, and
/// option collection stay distinct in the semantic blueprint.
class PointBlueprint {
  const PointBlueprint({
    required this.item,
    required this.index,
    required String label,
    required String text,
    required String? trailer,
    required String? marks,
    required this.options,
    List<OptionBlueprint>? allOptions,
  })  : _legacyLabel = label,
        _legacyText = text,
        _legacyTrailer = trailer,
        _legacyMarks = marks,
        labelNode = null,
        labelSeparator = null,
        content = null,
        trailerContent = null,
        marksNode = null,
        allOptions = allOptions;

  const PointBlueprint.semantic({
    required this.item,
    required this.index,
    required this.labelNode,
    required this.labelSeparator,
    required this.content,
    required this.trailerContent,
    required this.marksNode,
    required this.options,
    required this.allOptions,
  })  : _legacyLabel = null,
        _legacyText = null,
        _legacyTrailer = null,
        _legacyMarks = null;

  final BranchItem item;
  final int index;
  final String? _legacyLabel;
  final String? _legacyText;
  final String? _legacyTrailer;
  final String? _legacyMarks;
  final InlineNode? labelNode;
  final SeparatorNode? labelSeparator;
  final InlineContent? content;
  final InlineContent? trailerContent;
  final MarksNode? marksNode;
  final List<OptionBlueprint> options;
  final List<OptionBlueprint>? allOptions;

  String get label => labelNode == null
      ? _legacyLabel ?? ''
      : '${labelNode!.legacyText}${labelSeparator?.legacyText ?? ''}';
  String get text => content?.legacyText ?? _legacyText ?? '';
  String? get trailer => trailerContent?.legacyText ?? _legacyTrailer;
  String? get marks => marksNode?.legacyText ?? _legacyMarks;
  List<OptionBlueprint> get semanticOptions => allOptions ?? options;

  InlineContent get semanticLabel => labelNode == null
      ? InlineContent.fromSource(label, direction: DocumentDirection.inherit)
      : InlineContent(<InlineNode>[
          labelNode!,
          if (labelSeparator != null) labelSeparator!,
        ]);
  InlineContent get semanticText => content ??
      InlineContent.fromSource(text, direction: DocumentDirection.inherit);

  PointKind get kind => item.kind;

  /// هل تُطبع النقطة؟ (الفارغة تماماً بلا تسمية ولا درجة تُحذف).
  bool get isPrintable => item.showsInExport;

  /// Legacy flat point line.
  String get line => <String>[
        if (label.isNotEmpty) label,
        if (text.isNotEmpty) text,
        if (trailer != null) trailer!,
        if (marks != null) marks!,
      ].join(' ');

  /// Legacy option-row projection. The historical NBSP spacing lives only at
  /// this compatibility boundary; DocumentIR retains an OptionsBlock/list.
  String get optionsLine => options
      .map((option) => option.line)
      .join('\u00A0\u00A0\u00A0\u00A0\u00A0');
}

/// A branch remains a selected business structure; its visible label and
/// separator are held by [title.semanticNumber] / [title.separatorNode].
class BranchBlueprint {
  const BranchBlueprint({
    required this.model,
    required this.questionIndex,
    required this.branchIndex,
    required this.title,
    required this.body,
    required this.points,
    this.bodyContent,
  });

  final BranchModel model;
  final int questionIndex;
  final int branchIndex;
  final TitleLineBlueprint title;
  final String? body;
  final InlineContent? bodyContent;
  final List<PointBlueprint> points;

  /// هل يُطبع الفرع؟ (الفارغ تماماً يُحذف مع فاصله).
  bool isPrintable({Set<String> ignoredAttachmentIds = const <String>{}}) =>
      model.hasExportableContentIn(ignoredAttachmentIds: ignoredAttachmentIds);
}

/// A question and its selected business content. `section`/`body` are
/// compatibility text getters; DocumentIR consumes [category] and
/// [bodyContent].
class QuestionBlueprint {
  const QuestionBlueprint({
    required this.model,
    required this.index,
    required String? section,
    required this.title,
    required String? body,
    required this.points,
    required this.branches,
    this.category,
    this.bodyContent,
  })  : _legacySection = section,
        _legacyBody = body;

  const QuestionBlueprint.semantic({
    required this.model,
    required this.index,
    required this.category,
    required this.title,
    required this.bodyContent,
    required this.points,
    required this.branches,
  })  : _legacySection = null,
        _legacyBody = null;

  final QuestionModel model;
  final int index;
  final String? _legacySection;
  final String? _legacyBody;
  final CategoryBlueprint? category;
  final TitleLineBlueprint title;
  final InlineContent? bodyContent;
  final List<PointBlueprint> points;
  final List<BranchBlueprint> branches;

  String? get section => category?.text ?? _legacySection;
  String? get body => bodyContent?.legacyText ?? _legacyBody;
  InlineContent? get semanticBody => bodyContent ??
      (_legacyBody == null ? null : InlineContent.fromSource(_legacyBody!));

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

  /// Any blank marker entered by the teacher in a fill-in sentence.
  static final RegExp _blankMarker = RegExp(r'_{3,}|\.{4,}|\u2026');

  ExamBlueprint build() {
    return ExamBlueprint(
      header: _header(),
      footer: _footer(),
      questions: <QuestionBlueprint>[
        for (var index = 0; index < document.questions.length; index++)
          _question(index),
      ],
      direction: document.layout.isLtr
          ? DocumentDirection.ltr
          : DocumentDirection.rtl,
    );
  }

  // --------------------------- الترويسة ---------------------------

  String _value(String raw) => document.localizeDigits(raw.trim());

  HeaderLineBlueprint _headerLine(
    HeaderFieldKind field,
    InlineContent content, {
    bool bold = false,
  }) =>
      HeaderLineBlueprint(field: field, content: content, bold: bold);

  InlineContent _headerValueLine({
    required String label,
    required String value,
    required bool blankWhenEmpty,
  }) {
    final labelText = label.endsWith(':') ? label.substring(0, label.length - 1) : label;
    final valueText = value.isEmpty && blankWhenEmpty ? ExamCatalog.blankLine : value;
    return InlineContent(<InlineNode>[
      LabelNode.fromSource(
        labelText,
        role: LabelRole.headerField,
        direction: DocumentDirection.rtl,
      ),
      const SeparatorNode(':', role: SeparatorRole.punctuation, direction: DocumentDirection.rtl),
      const SeparatorNode(' ', role: SeparatorRole.labelValue, direction: DocumentDirection.rtl),
      ...InlineContent.fromSource(valueText, direction: DocumentDirection.auto).nodes,
    ]);
  }

  InlineContent _headerPrefixValue(String prefix, String value) =>
      InlineContent(<InlineNode>[
        LabelNode.fromSource(
          prefix,
          role: LabelRole.headerField,
          direction: DocumentDirection.rtl,
        ),
        if (value.isNotEmpty)
          const SeparatorNode(' ', role: SeparatorRole.labelValue, direction: DocumentDirection.rtl),
        if (value.isNotEmpty)
          ...InlineContent.fromSource(value, direction: DocumentDirection.auto).nodes,
      ]);

  HeaderBlueprint _header() {
    final header = document.header;
    final school = _value(header.schoolName);
    final examType = _value(header.examType);
    final year = _value(header.academicYear);
    final gender = header.schoolGender.label;
    final session = header.session.label;

    return HeaderBlueprint(
      showBismillah: header.showBismillah,
      rightContentLines: <HeaderLineBlueprint>[
        _headerLine(
          HeaderFieldKind.administration,
          InlineContent(<InlineNode>[
            LabelNode.fromSource(
              ExamCatalog.administrationLabel,
              role: LabelRole.headerField,
              direction: DocumentDirection.rtl,
            ),
          ]),
        ),
        if (school.isNotEmpty)
          _headerLine(
            HeaderFieldKind.schoolName,
            InlineContent.fromSource(school, direction: DocumentDirection.auto),
          ),
        if (gender.isNotEmpty)
          _headerLine(
            HeaderFieldKind.schoolGender,
            InlineContent.fromSource(gender, direction: DocumentDirection.rtl),
          ),
      ],
      centerContentLines: <HeaderLineBlueprint>[
        _headerLine(
          HeaderFieldKind.examType,
          _headerPrefixValue(ExamCatalog.examTitlePrefix, examType),
          bold: true,
        ),
        _headerLine(
          HeaderFieldKind.academicYear,
          _headerPrefixValue(ExamCatalog.academicYearPrefix, year),
          bold: true,
        ),
        if (session.isNotEmpty)
          _headerLine(
            HeaderFieldKind.session,
            InlineContent.fromSource(session, direction: DocumentDirection.rtl),
            bold: true,
          ),
      ],
      leftContentLines: <HeaderLineBlueprint>[
        _headerLine(
          HeaderFieldKind.subject,
          _headerValueLine(
            label: ExamCatalog.subjectLabel,
            value: _value(header.subject),
            blankWhenEmpty: true,
          ),
        ),
        _headerLine(
          HeaderFieldKind.grade,
          _headerValueLine(
            label: ExamCatalog.gradeLabel,
            value: _value(header.grade),
            blankWhenEmpty: true,
          ),
        ),
        _headerLine(
          HeaderFieldKind.time,
          _headerValueLine(
            label: ExamCatalog.timeLabel,
            value: _value(header.time),
            blankWhenEmpty: true,
          ),
        ),
        _headerLine(
          HeaderFieldKind.studentName,
          _headerValueLine(
            label: ExamCatalog.studentNameLabel,
            value: ExamCatalog.blankLine,
            blankWhenEmpty: false,
          ),
        ),
      ],
      bismillahSemanticContent: InlineContent.fromSource(
        ExamCatalog.bismillah,
        direction: DocumentDirection.rtl,
      ),
      framed: document.settings.headerBorder,
    );
  }

  // --------------------------- التذييل ---------------------------

  FooterBlueprint _footer() {
    final footer = document.footer;
    SignatureBlueprint signature(String title, String name) =>
        SignatureBlueprint.semantic(
          semanticTitle: LabelNode.fromSource(
            title,
            role: LabelRole.signature,
            direction: DocumentDirection.rtl,
          ),
          semanticName: InlineContent.fromSource(
            name.trim(),
            direction: DocumentDirection.auto,
          ),
        );
    final phrase = footer.closingPhrase.trim();
    final secondary = footer.secondary;
    return FooterBlueprint(
      semanticClosingPhrase: phrase.isEmpty
          ? null
          : InlineContent.fromSource(phrase, direction: DocumentDirection.rtl),
      primary: signature(footer.primary.title.label, footer.primary.name),
      secondary: secondary == null
          ? null
          : signature(secondary.title.label, secondary.name),
    );
  }

  // --------------------------- الأسئلة ---------------------------

  MarksNode? _marks(double marks) {
    if (!showMarks || marks <= 0) {
      return null;
    }
    return MarksNode(
      value: marks,
      number: NumberNode(
        value: marks,
        displayText: document.formatNumber(marks),
        role: NumberRole.marks,
        direction: DocumentDirection.auto,
      ),
      unit: LabelNode.fromSource(
        document.layout.marksUnit,
        role: LabelRole.generic,
        direction: DocumentDirection.rtl,
      ),
    );
  }

  InlineContent? _nonBlankContent(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : InlineContent.fromSource(trimmed);
  }

  QuestionBlueprint _question(int index) {
    final question = document.questions[index];
    final manual = question.numberOverride?.trim();
    final numberNode = manual != null && manual.isNotEmpty
        ? LabelNode.fromSource(
            manual,
            role: LabelRole.question,
            direction: DocumentDirection.auto,
          )
        : NumberNode(
            value: question.questionNumber,
            displayText: document.autoQuestionLabel(question),
            role: NumberRole.question,
            direction: document.layout.isLtr
                ? DocumentDirection.ltr
                : DocumentDirection.rtl,
          );
    final category = _nonBlankContent(question.category);
    return QuestionBlueprint.semantic(
      model: question,
      index: index,
      category: category == null ? null : CategoryBlueprint(content: category),
      title: TitleLineBlueprint.semantic(
        numberNode: numberNode,
        separatorNode: manual != null && manual.isNotEmpty
            ? null
            : SeparatorNode(
                document.layout.questionSeparator,
                role: SeparatorRole.question,
                direction: document.layout.isLtr
                    ? DocumentDirection.ltr
                    : DocumentDirection.rtl,
              ),
        statementContent: InlineContent.fromSource(question.statement.trim()),
        marksNode: _marks(question.marks),
      ),
      bodyContent: _nonBlankContent(question.body),
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
      title: TitleLineBlueprint.semantic(
        numberNode: LabelNode.fromSource(
          label,
          role: LabelRole.branch,
          direction: DocumentDirection.auto,
        ),
        separatorNode: SeparatorNode(
          document.layout.branchSeparator,
          role: SeparatorRole.branch,
          direction: document.layout.isLtr
              ? DocumentDirection.ltr
              : DocumentDirection.rtl,
        ),
        statementContent: InlineContent.fromSource(content.statement.trim()),
        marksNode: _marks(branch.marks),
      ),
      body: _nonBlankContent(content.body)?.legacyText,
      bodyContent: _nonBlankContent(content.body),
      points: _points(content.items),
    );
  }

  // --------------------------- النقاط ---------------------------

  List<PointBlueprint> _points(List<BranchItem> items) => <PointBlueprint>[
        for (var index = 0; index < items.length; index++)
          _point(items[index], index),
      ];

  /// Semantic trailer selected by point kind; no label or marks are appended
  /// to the point body here.
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

  OptionBlueprint _option(QuestionOption option, int index) {
    final custom = option.labelOverride;
    final labelNode = LabelNode.fromSource(
      custom ?? document.layout.branchLabel(index),
      role: LabelRole.option,
      direction: DocumentDirection.auto,
    );
    return OptionBlueprint.semantic(
      index: index,
      option: option,
      labelNode: labelNode,
      labelPrefix: custom == null
          ? const <SeparatorNode>[
              SeparatorNode('(', role: SeparatorRole.punctuation),
              SeparatorNode(' ', role: SeparatorRole.optionLabel),
            ]
          : const <SeparatorNode>[],
      labelSuffix: custom == null
          ? const <SeparatorNode>[
              SeparatorNode(' ', role: SeparatorRole.optionLabel),
              SeparatorNode(')', role: SeparatorRole.punctuation),
            ]
          : const <SeparatorNode>[],
      content: InlineContent.fromSource(option.text.trim()),
    );
  }

  PointBlueprint _point(BranchItem item, int index) {
    final text = item.text.trim();
    final manualLabel = item.labelOverride;
    final labelNode = manualLabel != null
        ? LabelNode.fromSource(
            manualLabel,
            role: LabelRole.item,
            direction: DocumentDirection.auto,
          )
        : NumberNode(
            value: index + 1,
            displayText: document.formatNumber(index + 1),
            role: NumberRole.item,
            direction: DocumentDirection.auto,
          );
    final allOptions = item.kind == PointKind.multipleChoice
        ? <OptionBlueprint>[
            for (var optionIndex = 0;
                optionIndex < item.options.length;
                optionIndex++)
              _option(item.options[optionIndex], optionIndex),
          ]
        : const <OptionBlueprint>[];
    return PointBlueprint.semantic(
      item: item,
      index: index,
      labelNode: labelNode,
      labelSeparator: manualLabel == null
          ? const SeparatorNode('-', role: SeparatorRole.item)
          : null,
      content: InlineContent.fromSource(text),
      trailerContent: text.isEmpty || _trailer(item, text) == null
          ? null
          : InlineContent.literal(_trailer(item, text)!),
      marksNode: _marks(item.marks),
      // The compatibility list contains only printable options; the semantic
      // list also keeps blank editor slots so Preview can render the same
      // model without independently regenerating their labels.
      options: allOptions.where((option) => option.isPrintable).toList(growable: false),
      allOptions: allOptions,
    );
  }
}
