import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_item.dart';
import '../models/branch_model.dart';
import '../models/exam_document.dart';
import '../models/exam_header_model.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_text_style.dart';
import '../models/question_model.dart';
import '../models/question_type.dart';
import '../models/quran_text.dart';
import '../models/subject_layout.dart';
import '../models/tex_content.dart';
import 'exam_fonts.dart';
import 'exam_strategy.dart' show ExamTextStyles;
import 'floating_elements_pdf.dart';
import 'latex/latex_svg_renderer.dart';
import 'paper_style_resolver.dart';

/// محرك PDF متعدد الصفحات لورقة الأسئلة (WYSIWYG A4).
///
/// الضمانات:
/// 1. **السؤال وحدة لا تتجزأ**: التقسيم الورقي يُحسب عبر [PaginationEngine]
///    (نفس محرك الشاشة) على ارتفاعات الكتل المقاسة فعلياً بمقاييس pdf؛
///    وعند تمرير [pageAssignments] من لوحة المعاينة يُطبع **نفس** التوزيع
///    المعروض على الشاشة تماماً.
/// 2. **لا تجاوز للورقة أبداً**: محتوى كل صفحة داخل [pw.FittedBox] بوضع
///    `scaleDown` كشبكة أمان ضد فروق قياس الخطوط بين الشاشة والطباعة.
/// 3. **قالب المادة** ([SubjectLayoutTemplate]) يقرّر الاتجاه (RTL/LTR)،
///    والترقيم (السؤال الأول / Q1)، والفروع (أ / A)، ونسق الأرقام —
///    ما لم تخصصه إعدادات الورقة أو المدرس لعنصر بعينه.
/// 4. **ما يُرى هو ما يُطبع**: نص السؤال، النقاط، الفواصل، الإطارات،
///    الصور، الأشكال، مربعات النص، والتنسيقات — كلها تُرسم هنا بنفس
///    قرارات لوحة المعاينة حرفياً.
class PaginatedPdfExamEngine {
  PaginatedPdfExamEngine();

  static const double pageMarginMillimeters = 15;

  /// عرض المحتوى الافتراضي (للهامش الافتراضي) — يُستخدم في القياسات
  /// الخارجية؛ العرض الفعلي لكل مستند يُحسب من هامشه عبر [_contentWidthFor].
  static double get contentWidth =>
      PdfPageFormat.a4.width - 2 * pageMarginMillimeters * PdfPageFormat.mm;

  static double get _footerHeight => PaperMetrics.pt(PaperMetrics.footerHeightPx);

  static double get _blockSpacing => PaperMetrics.pt(PaperMetrics.blockSpacingPx);

  static double _marginFor(ExamDocument document) =>
      document.settings.marginMm * PdfPageFormat.mm;

  static double _contentWidthFor(ExamDocument document) =>
      PdfPageFormat.a4.width - 2 * _marginFor(document);

  static double _pageContentHeightFor(ExamDocument document) =>
      PdfPageFormat.a4.height - 2 * _marginFor(document) - _footerHeight;

  /// هل تحمل الورقة نصاً موسوماً بآية قرآنية؟
  ///
  /// يُستهلك هذا القرار في تحميل الخط القرآني: الورقة التي لا تحمل وسماً
  /// قرآنياً لا يُحمَّل لها أصل الخط أصلاً — «إن توفّرت» تعني
  /// أيضاً ألا نكلّف الورقة ما لا تحتاجه، مع بقاء السلوك نفسه تماماً.
  static bool needsQuranicFont(ExamDocument document) {
    if (QuranText.containsQuran(document.header.title) ||
        QuranText.containsQuran(document.header.instructions) ||
        QuranText.containsQuran(document.header.notes)) {
      return true;
    }
    for (final question in document.questions) {
      if (QuranText.containsQuran(question.prompt)) {
        return true;
      }
      for (final element in question.attachments) {
        if (QuranText.containsQuran(element.label)) {
          return true;
        }
      }
      for (final branch in question.branches) {
        final content = branch.content;
        if (QuranText.containsQuran(content.text) ||
            QuranText.containsQuran(content.modelAnswer)) {
          return true;
        }
        for (final item in content.items) {
          if (QuranText.containsQuran(item.text)) {
            return true;
          }
        }
        for (final option in content.options) {
          if (QuranText.containsQuran(option.text)) {
            return true;
          }
        }
        for (final element in branch.attachments) {
          if (QuranText.containsQuran(element.label)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// يولّد ملف PDF متعدد الصفحات بحجم A4.
  ///
  /// [pageAssignments]: توزيع معرّفات الأسئلة على الصفحات كما حُسب على
  /// الشاشة؛ عند غيابه يُحسب التوزيع هنا بقياس عناصر pdf نفسها.
  Future<Uint8List> generate({
    required ExamDocument document,
    bool isTeacherVersion = false,
    List<List<String>>? pageAssignments,
    ExamFonts? fonts,
  }) async {
    final loadedFonts =
        fonts ?? await ExamFonts.load(loadQuranic: needsQuranicFont(document));
    final layout = document.layout;
    final settings = document.settings;
    final margin = _marginFor(document);
    final contentWidth = _contentWidthFor(document);
    final direction = layout.isLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final theme = pw.ThemeData.withFont(
      base: loadedFonts.fontFor(settings.defaultFont),
      bold: loadedFonts.fontFor(settings.defaultFont, bold: true),
    );
    final styles = ExamTextStyles.standard;

    final pdf = pw.Document(
      title: document.name,
      creator: 'صانع ومحرر الأسئلة',
      subject: document.header.subject,
    );

    final pages = _resolvePages(
      document: document,
      pageAssignments: pageAssignments,
      measure: (widget) => _measure(widget, pdf, theme, direction),
      layout: layout,
      styles: styles,
      fonts: loadedFonts,
      isTeacherVersion: isTeacherVersion,
    );

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final questionIds = pages[pageIndex];
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          textDirection: direction,
          theme: theme,
          build: (context) {
            final blocks = <pw.Widget>[
              if (pageIndex == 0) _buildHeader(document, layout, styles, loadedFonts),
              for (final id in questionIds)
                _buildQuestion(
                  document,
                  document.questionById(id)!,
                  layout,
                  styles,
                  loadedFonts,
                  isTeacherVersion,
                ),
            ];
            pw.Widget content = pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.topCenter,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.topCenter,
                      child: pw.SizedBox(
                        width: _contentWidth,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          mainAxisSize: pw.MainAxisSize.min,
                          children: _interleave(
                            blocks,
                            pw.SizedBox(height: _blockSpacing),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildFooter(pageIndex + 1, pages.length, document, layout, styles),
              ],
            );
            if (settings.pageBorder) {
              content = pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 1.4),
                ),
                padding: const pw.EdgeInsets.all(4),
                child: content,
              );
            }
            return pw.Stack(
              children: <pw.Widget>[
                pw.Positioned(
                  left: _marginValue,
                  top: _marginValue,
                  right: _marginValue,
                  bottom: _marginValue,
                  child: content,
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // ------------------------------------------------------------------
  // التقسيم الورقي
  // ------------------------------------------------------------------

  List<List<String>> _resolvePages({
    required ExamDocument document,
    required List<List<String>>? pageAssignments,
    required double Function(pw.Widget) measure,
    required SubjectLayoutTemplate layout,
    required ExamTextStyles styles,
    required ExamFonts fonts,
    required bool isTeacherVersion,
  }) {
    if (pageAssignments != null && _coversAllQuestions(pageAssignments, document)) {
      return pageAssignments
          .map((page) => List<String>.unmodifiable(page))
          .toList(growable: false);
    }

    final headerHeight = measure(_buildHeader(document, layout, styles, fonts));
    final result = PaginationEngine.paginate(
      blocks: <PageBlock>[
        PageBlock(id: PaperMetrics.headerBlockId, height: headerHeight),
        for (final question in document.questions)
          PageBlock(
            id: question.id,
            height: measure(_buildQuestion(
                document, question, layout, styles, fonts, isTeacherVersion)),
          ),
      ],
      pageHeight: _pageContentHeight,
      spacing: _blockSpacing,
    );
    return <List<String>>[
      for (final page in result.pages)
        page.blockIds.where((id) => id != PaperMetrics.headerBlockId).toList(growable: false),
    ];
  }

  static bool _coversAllQuestions(List<List<String>> pages, ExamDocument document) {
    final assigned = <String>{for (final page in pages) ...page};
    final expected = document.questions.map((question) => question.id).toSet();
    return pages.isNotEmpty &&
        assigned.length == expected.length &&
        assigned.containsAll(expected);
  }

  /// يقيس ارتفاع عنصر pdf خارج أي صفحة (سياق تخطيط مستقل بنفس السمة).
  double _measure(
    pw.Widget widget,
    pw.Document pdf,
    pw.ThemeData theme,
    pw.TextDirection direction,
  ) {
    final context = pw.Context(document: pdf.document).inheritFromAll(<pw.Inherited>[
      theme,
      pw.InheritedDirectionality(direction),
    ]);
    widget.layout(
      context,
      pw.BoxConstraints(maxWidth: _contentWidth),
      parentUsesSize: true,
    );
    return widget.box?.height ?? 0;
  }

  // ------------------------------------------------------------------
  // الترويسة (عنوان + 3 أعمدة × 3 أسطر + ملاحظات)
  // ------------------------------------------------------------------

  pw.Widget _buildHeader(
    ExamDocument document,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
  ) {
    final header = document.header;
    final settings = document.settings;
    final lineStyle = PaperStyleResolver.apply(
      styles.headerBody.copyWith(lineSpacing: 2),
      header.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final centerStyle = PaperStyleResolver.apply(
      styles.headerBody.copyWith(fontWeight: pw.FontWeight.bold, lineSpacing: 2),
      header.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final titleStyle = PaperStyleResolver.apply(
      styles.headerTitle,
      header.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );

    pw.Widget column(HeaderColumn source, pw.TextStyle style, pw.TextAlign align) {
      return pw.Expanded(
        flex: align == pw.TextAlign.center ? 4 : 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: <pw.Widget>[
            for (final line in source.lines)
              pw.Text(line.isEmpty ? ' ' : line, style: style, textAlign: align, maxLines: 2),
          ],
        ),
      );
    }

    final instructions = header.instructions.trim();
    final notes = header.notes.trim();
    final title = header.title.trim();
    final titleAlign =
        PaperStyleResolver.toPdfAlign(header.style.align) ?? pw.TextAlign.center;
    final children = <pw.Widget>[
      if (title.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(title, style: titleStyle, textAlign: titleAlign),
        ),
      pw.Container(
        decoration: settings.headerBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 1.2),
              )
            : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            // العمود الأول في اتجاه القراءة: اليمين في RTL.
            column(header.right, lineStyle, pw.TextAlign.start),
            pw.SizedBox(width: 6),
            column(header.center, centerStyle, pw.TextAlign.center),
            pw.SizedBox(width: 6),
            column(header.left, lineStyle, pw.TextAlign.start),
          ],
        ),
      ),
      if (settings.showTotalMarks || settings.showQuestionMarks)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
            layout.isLtr
                ? 'Total: ${document.formatNumber(document.totalMarks)} ${layout.marksUnit}  |  '
                    'Questions: ${document.formatNumber(document.questions.length)}'
                : 'الدرجة الكلية: ${document.formatNumber(document.totalMarks)} '
                    '${layout.marksUnit}  |  عدد الأسئلة: '
                    '${document.formatNumber(document.questions.length)}',
            textAlign: pw.TextAlign.center,
            style: styles.small,
          ),
        ),
      if (instructions.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(instructions, textAlign: pw.TextAlign.center, style: styles.note),
        ),
      if (notes.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(notes, textAlign: pw.TextAlign.center, style: styles.note),
        ),
      pw.Divider(thickness: 1.5, color: ExamTextStyles.primaryColor, height: 8),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ)
  // ------------------------------------------------------------------

  pw.Widget _buildQuestion(
    ExamDocument document,
    QuestionModel question,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
  ) {
    final settings = document.settings;
    final category = question.category.trim();
    final label = document.displayQuestionLabel(question);
    final marksPart = settings.showQuestionMarks
        ? ': [${document.formatNumber(question.marks)} ${layout.marksUnit}]'
        : '';
    final titleStyle = PaperStyleResolver.apply(
      styles.question,
      question.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final titleAlign =
        PaperStyleResolver.toPdfAlign(question.style.align) ?? pw.TextAlign.start;

    final prompt = question.prompt.trim();
    final promptStyle = PaperStyleResolver.apply(
      styles.body.copyWith(lineSpacing: layout.lineHeightFactor * 2),
      question.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );

    final children = <pw.Widget>[
      if (category.isNotEmpty)
        pw.Text(
          category,
          style: PaperStyleResolver.apply(styles.category, question.style,
              fonts: fonts, defaultFont: settings.defaultFont),
          textAlign: titleAlign,
        ),
      pw.Text('$label$marksPart', style: titleStyle, textAlign: titleAlign),
      if (prompt.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: _renderText(prompt, promptStyle, fonts.quranic),
        ),
      for (var index = 0; index < question.branches.length; index++)
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: 10, top: 2),
          child: _buildBranch(
            document,
            question.branches[index],
            document.displayBranchLabel(
                document.indexOfQuestion(question.id), index),
            layout,
            styles,
            fonts,
            isTeacherVersion,
          ),
        ),
      if (question.dividerAfter != null) _buildDivider(question.dividerAfter!),
    ];

    pw.Widget body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
    if (question.showFrame) {
      body = pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 1),
        ),
        padding: const pw.EdgeInsets.all(5),
        child: body,
      );
    }
    if (question.attachments.isEmpty) {
      return body;
    }
    return _withAttachments(
      body: body,
      attachments: question.attachments,
      layout: layout,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
  }

  pw.Widget _buildBranch(
    ExamDocument document,
    BranchModel branch,
    String label,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
  ) {
    final settings = document.settings;
    final content = branch.content;
    final marksSuffix = branch.marks > 0
        ? ' (${document.formatNumber(branch.marks)} ${layout.marksUnit})'
        : '';
    // المقاطع الموسومة بالآيات تُرسم بالخط القرآني في كل القوالب، وأما
    // «أسلوب المصحف» — توسيط الآية القائمة بذاتها وتكبيرها — فيتبع تفضيل
    // القالب ([SubjectLayoutTemplate.prefersQuranicFont] أي التربية
    // الإسلامية). وهو **نفس قرار لوحة المعاينة** حرفياً؛ والتوسيط والحجم لا
    // يتعلقان بتوفر الخط (الخط وحده يرتد إلى خط الورقة إن غاب الأصل).
    final standaloneVerse =
        layout.prefersQuranicFont && QuranText.isStandaloneVerse(content.text);
    final baseBody = standaloneVerse
        ? styles.body.copyWith(fontSize: 12, lineSpacing: layout.lineHeightFactor * 2 + 2)
        : styles.body.copyWith(lineSpacing: layout.lineHeightFactor * 2);
    final bodyStyle = PaperStyleResolver.apply(
      baseBody,
      branch.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );

    final children = <pw.Widget>[
      _renderText(
        '$label) ${content.text}$marksSuffix',
        bodyStyle,
        fonts.quranic,
        centerVerse: standaloneVerse,
      ),
      if (content.items.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 1),
          child: _buildItems(document, content, layout, styles, fonts),
        ),
      if (!(content.plainText && !isTeacherVersion))
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 1),
          child: _buildTypeBody(document, content, layout, styles, fonts, isTeacherVersion),
        ),
      if (isTeacherVersion && content.plainText) _buildPlainTeacherAnswer(document, content, layout, styles),
      if (branch.dividerAfter != null) _buildDivider(branch.dividerAfter!),
    ];

    pw.Widget body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
    if (branch.showFrame) {
      body = pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 0.8),
        ),
        padding: const pw.EdgeInsets.all(4),
        child: body,
      );
    }
    if (branch.attachments.isEmpty) {
      return body;
    }
    // المرفقات (صور/أشكال/مربعات نص) تتراكب فوق مساحة الفرع بنفس إحداثيات اللوحة.
    return _withAttachments(
      body: body,
      attachments: branch.attachments,
      layout: layout,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
  }

  /// النقاط داخل الفرع (1- 2- 3-...) بترقيم نسق الورقة.
  pw.Widget _buildItems(
    ExamDocument document,
    BranchContent content,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
  ) {
    final settings = document.settings;
    final itemStyle = PaperStyleResolver.apply(
      styles.body.copyWith(lineSpacing: layout.lineHeightFactor * 2),
      null,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        for (var index = 0; index < content.items.length; index++)
          _buildItem(document, content.items[index], index, layout, itemStyle, fonts),
      ],
    );
  }

  pw.Widget _buildItem(
    ExamDocument document,
    BranchItem item,
    int index,
    SubjectLayoutTemplate layout,
    pw.TextStyle style,
    ExamFonts fonts,
  ) {
    final marksSuffix = item.marks > 0
        ? ' (${document.formatNumber(item.marks)} ${layout.marksUnit})'
        : '';
    final text = item.text.trim().isEmpty ? '................................' : item.text;
    return _renderText(
      '${document.formatNumber(index + 1)}- $text$marksSuffix',
      style,
      fonts.quranic,
    );
  }

  /// الإجابة النموذجية للفرع الحر في نسخة المعلم.
  pw.Widget _buildPlainTeacherAnswer(
    ExamDocument document,
    BranchContent content,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
  ) {
    final model = content.modelAnswer.trim();
    if (model.isEmpty) {
      return pw.SizedBox();
    }
    return pw.Padding(
      padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 1),
      child: pw.Text(
        '${layout.isLtr ? 'Model answer' : 'الإجابة النموذجية'}: $model •',
        style: styles.body.copyWith(
          color: ExamTextStyles.successColor,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildDivider(PaperDivider divider) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        top: divider.spacingBefore,
        bottom: divider.spacingAfter,
      ),
      child: pw.Center(
        child: pw.SizedBox(
          width: _activeContentWidth * divider.widthFraction,
          child: pw.Divider(
            thickness: divider.thickness,
            color: ExamTextStyles.primaryColor,
            height: divider.thickness + 2,
          ),
        ),
      ),
    );
  }

  /// يركّب المرفقات فوق مساحة المالك (سؤال/فرع) بنفس إحداثيات اللوحة.
  pw.Widget _withAttachments({
    required pw.Widget body,
    required List<FloatingElement> attachments,
    required SubjectLayoutTemplate layout,
    required ExamFonts fonts,
    required dynamic defaultFont,
  }) {
    final scale = PaperMetrics.pointsPerPixel;
    final minHeight = attachments.fold<double>(
      0,
      (max, element) {
        final bottom = (element.dy + element.height) * scale;
        return bottom > max ? bottom : max;
      },
    );
    return pw.Stack(
      children: <pw.Widget>[
        pw.ConstrainedBox(
          constraints: pw.BoxConstraints(minHeight: minHeight, minWidth: _contentWidth - 24),
          child: body,
        ),
        for (final element in attachments)
          pw.Positioned(
            left: layout.isLtr ? element.dx * scale : null,
            right: layout.isLtr ? null : element.dx * scale,
            top: element.dy * scale,
            child: FloatingElementsPdf.build(
              element,
              widthPt: element.width * scale,
              heightPt: element.height * scale,
              fonts: fonts,
              defaultFont: defaultFont,
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTypeBody(
    ExamDocument document,
    BranchContent content,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
  ) {
    final answerStyle = styles.body.copyWith(
      color: ExamTextStyles.successColor,
      fontWeight: pw.FontWeight.bold,
    );
    switch (content.type) {
      case QuestionType.multipleChoice:
        final options = content.options
            .where((option) => option.text.trim().isNotEmpty)
            .toList(growable: false);
        return pw.Wrap(
          spacing: 14,
          runSpacing: 2,
          children: <pw.Widget>[
            for (var index = 0; index < options.length; index++)
              _renderText(
                '( ${layout.branchLabel(index)} ) ${options[index].text}'
                '${isTeacherVersion && options[index].isCorrect ? ' •' : ''}',
                isTeacherVersion && options[index].isCorrect ? answerStyle : styles.option,
                fonts.quranic,
              ),
          ],
        );
      case QuestionType.trueFalse:
        if (!isTeacherVersion) {
          return pw.Text(
            layout.isLtr
                ? 'Answer: (     ) True      (     ) False'
                : 'الإجابة: (     ) صح      (     ) خطأ',
            style: styles.body,
          );
        }
        final answer = content.trueFalseAnswer;
        return pw.Text(
          layout.isLtr
              ? 'Answer: ${answer ? 'True' : 'False'} •'
              : 'الإجابة الصحيحة: ${answer ? 'صح' : 'خطأ'} •',
          style: answerStyle,
        );
      case QuestionType.fillInTheBlank:
        if (!isTeacherVersion) {
          return pw.Text(
            '${layout.isLtr ? 'Answer' : 'الإجابة'}: '
            '............................................................................',
            style: styles.body,
          );
        }
        final model = content.modelAnswer.trim();
        return pw.Text(
          '${layout.isLtr ? 'Model answer' : 'الإجابة النموذجية'}: '
          '${model.isEmpty ? '—' : model} •',
          style: answerStyle,
        );
      case QuestionType.essay:
        if (isTeacherVersion) {
          final model = content.modelAnswer.trim();
          return pw.Text(
            '${layout.isLtr ? 'Model answer' : 'الإجابة النموذجية وعناصر التقييم'}: '
            '${model.isEmpty ? '—' : model} •',
            style: answerStyle,
          );
        }
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: List<pw.Widget>.generate(
            layout.essayAnswerLines,
            (_) => pw.Text(
              '................................................................................................',
              style: styles.small,
            ),
          ),
        );
    }
  }

  pw.Widget _buildFooter(
    int pageNumber,
    int pageCount,
    ExamDocument document,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
  ) {
    if (!document.settings.showPageNumbers) {
      return pw.SizedBox(height: _footerHeight);
    }
    return pw.SizedBox(
      height: _footerHeight,
      child: pw.Center(
        child: pw.Text(
          layout.isLtr
              ? 'Page $pageNumber of $pageCount'
              : 'صفحة ${document.formatNumber(pageNumber)} من ${document.formatNumber(pageCount)}',
          style: styles.footer,
        ),
      ),
    );
  }

  /// نص الورقة: مقاطع LaTeX ($...$) تُرسم SVG متجهة، وآيات القرآن الموسومة
  /// بـ `﴿ ... ﴾` تُرسم بالخط القرآني (Amiri) إن توفّر، والباقي نص عادي.
  ///
  /// [centerVerse] يوسّط آية قائمة بذاتها كما في لوحة المعاينة.
  pw.Widget _renderText(
    String text,
    pw.TextStyle style,
    pw.Font? quranFont, {
    bool centerVerse = false,
  }) {
    final segments = TexContent.split(text);
    final hasMath = segments.any((segment) => segment.isMath);
    if (!hasMath) {
      return _plainText(text, style, quranFont, centerVerse: centerVerse);
    }
    final fontSize = style.fontSize ?? 10.5;
    final rows = <pw.Widget>[];
    var inline = <pw.Widget>[];

    void flushInline() {
      if (inline.isEmpty) {
        return;
      }
      rows.add(
        pw.Wrap(
          spacing: 1,
          runSpacing: 2,
          crossAxisAlignment: pw.WrapCrossAlignment.center,
          children: List<pw.Widget>.of(inline),
        ),
      );
      inline = <pw.Widget>[];
    }

    for (final segment in segments) {
      if (!segment.isMath) {
        if (segment.text.isNotEmpty) {
          inline.add(_plainText(segment.text, style, quranFont));
        }
        continue;
      }
      final latex = LatexSvgRenderer.tryToSvg(segment.text, fontSize: fontSize);
      if (latex == null) {
        inline.add(pw.Text('\$${segment.text}\$', style: style));
        continue;
      }
      final image = pw.SvgImage(svg: latex.svg, width: latex.width, height: latex.height);
      if (segment.isBlock) {
        flushInline();
        rows.add(pw.Center(child: image));
      } else {
        inline.add(image);
      }
    }
    flushInline();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: rows,
    );
  }

  /// نص عادي — وإذا حمل آيات موسومة رُسمت مقاطعها بالخط القرآني [quranFont]
  /// في نفس السطر ([pw.RichText] بامتدادات متعددة الخطوط).
  ///
  /// غياب الخط القرآني أو غياب الوسم يعيد النص كما هو بخط الورقة الأساسي.
  static pw.Widget _plainText(
    String text,
    pw.TextStyle style,
    pw.Font? quranFont, {
    bool centerVerse = false,
  }) {
    if (quranFont == null || !QuranText.containsQuran(text)) {
      return pw.Text(
        text,
        style: style,
        textAlign: centerVerse ? pw.TextAlign.center : null,
      );
    }
    final spans = <pw.InlineSpan>[];
    for (final segment in QuranText.split(text)) {
      if (segment.text.isEmpty) {
        continue;
      }
      spans.add(
        pw.TextSpan(
          text: segment.text,
          style: segment.isQuran ? style.copyWith(font: quranFont) : style,
        ),
      );
    }
    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: centerVerse ? pw.TextAlign.center : null,
    );
  }

  static List<pw.Widget> _interleave(List<pw.Widget> blocks, pw.Widget separator) {
    final result = <pw.Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      if (index > 0) {
        result.add(separator);
      }
      result.add(blocks[index]);
    }
    return result;
  }
}
