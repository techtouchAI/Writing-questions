import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_model.dart';
import '../models/exam_document.dart';
import '../models/exam_header_model.dart';
import '../models/question_model.dart';
import '../models/question_type.dart';
import '../models/quran_text.dart';
import '../models/subject_layout.dart';
import '../models/tex_content.dart';
import 'exam_fonts.dart';
import 'exam_strategy.dart' show ExamTextStyles;
import 'floating_elements_pdf.dart';
import 'latex/latex_svg_renderer.dart';

/// محرك PDF متعدد الصفحات للنموذج الوزاري (WYSIWYG A4).
///
/// الضمانات:
/// 1. **السؤال وحدة لا تتجزأ**: التقسيم الورقي يُحسب عبر [PaginationEngine]
///    (نفس محرك الشاشة) على ارتفاعات الكتل المقاسة فعلياً بمقاييس pdf؛
///    وعند تمرير [pageAssignments] من لوحة المعاينة يُطبع **نفس** التوزيع
///    المعروض على الشاشة تماماً.
/// 2. **لا تجاوز للورقة أبداً**: محتوى كل صفحة داخل [pw.FittedBox] بوضع
///    `scaleDown` كشبكة أمان ضد فروق قياس الخطوط بين الشاشة والطباعة.
/// 3. **قالب المادة** ([SubjectLayoutTemplate]) يقرّر الاتجاه (RTL/LTR)،
///    والترقيم (السؤال الأول / Q1)، والفروع (أ / A)، ونسق الأرقام.
class PaginatedPdfExamEngine {
  const PaginatedPdfExamEngine();

  static const double pageMarginMillimeters = 15;

  static double get _margin => pageMarginMillimeters * PdfPageFormat.mm;

  static double get contentWidth => PdfPageFormat.a4.width - 2 * _margin;

  static double get _footerHeight => PaperMetrics.pt(PaperMetrics.footerHeightPx);

  static double get _blockSpacing => PaperMetrics.pt(PaperMetrics.blockSpacingPx);

  /// الارتفاع المتاح للكتل في كل صفحة (نقاط).
  static double get pageContentHeight =>
      PdfPageFormat.a4.height - 2 * _margin - _footerHeight;

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
    final loadedFonts = fonts ?? await ExamFonts.load();
    final layout = document.layout;
    final direction = layout.isLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final theme = pw.ThemeData.withFont(
      base: loadedFonts.regular,
      bold: loadedFonts.bold,
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
              if (pageIndex == 0) _buildHeader(document, layout, styles),
              for (final id in questionIds)
                _buildQuestion(
                  document.questionById(id)!,
                  layout,
                  styles,
                  loadedFonts,
                  isTeacherVersion,
                ),
            ];
            return pw.Stack(
              children: <pw.Widget>[
                pw.Positioned(
                  left: _margin,
                  top: _margin,
                  right: _margin,
                  bottom: _margin,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: <pw.Widget>[
                      pw.Expanded(
                        child: pw.Align(
                          alignment: pw.Alignment.topCenter,
                          child: pw.FittedBox(
                            fit: pw.BoxFit.scaleDown,
                            alignment: pw.Alignment.topCenter,
                            child: pw.SizedBox(
                              width: contentWidth,
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
                      _buildFooter(pageIndex + 1, pages.length, layout, styles),
                    ],
                  ),
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

    final headerHeight = measure(_buildHeader(document, layout, styles));
    final result = PaginationEngine.paginate(
      blocks: <PageBlock>[
        PageBlock(id: PaperMetrics.headerBlockId, height: headerHeight),
        for (final question in document.questions)
          PageBlock(
            id: question.id,
            height: measure(_buildQuestion(question, layout, styles, fonts, isTeacherVersion)),
          ),
      ],
      pageHeight: pageContentHeight,
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
  static double _measure(
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
      pw.BoxConstraints(maxWidth: contentWidth),
      parentUsesSize: true,
    );
    return widget.box?.height ?? 0;
  }

  // ------------------------------------------------------------------
  // الترويسة الوزارية (3 أعمدة × 3 أسطر)
  // ------------------------------------------------------------------

  pw.Widget _buildHeader(
    ExamDocument document,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
  ) {
    final header = document.header;
    final lineStyle = styles.headerBody.copyWith(lineSpacing: 2);
    final centerStyle = styles.headerBody.copyWith(
      fontWeight: pw.FontWeight.bold,
      lineSpacing: 2,
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 1.2),
          ),
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
        pw.SizedBox(height: 3),
        pw.Text(
          layout.isLtr
              ? 'Total: ${layout.formatNumber(document.totalMarks)} ${layout.marksUnit}  |  '
                  'Questions: ${layout.formatNumber(document.questions.length)}'
              : 'الدرجة الكلية: ${layout.formatNumber(document.totalMarks)} ${layout.marksUnit}  |  '
                  'عدد الأسئلة: ${layout.formatNumber(document.questions.length)}',
          textAlign: pw.TextAlign.center,
          style: styles.small,
        ),
        if (instructions.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(instructions, textAlign: pw.TextAlign.center, style: styles.note),
          ),
        pw.Divider(thickness: 1.5, color: ExamTextStyles.primaryColor, height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ)
  // ------------------------------------------------------------------

  pw.Widget _buildQuestion(
    QuestionModel question,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
  ) {
    final category = question.category.trim();
    final title = '${layout.questionLabel(question.questionNumber)}: '
        '[${layout.formatNumber(question.marks)} ${layout.marksUnit}]';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        if (category.isNotEmpty) pw.Text(category, style: styles.category),
        pw.Text(title, style: styles.question),
        for (var index = 0; index < question.branches.length; index++)
          pw.Padding(
            padding: const pw.EdgeInsetsDirectional.only(start: 10, top: 2),
            child: _buildBranch(
              question.branches[index],
              layout.branchLabel(index),
              layout,
              styles,
              fonts,
              isTeacherVersion,
            ),
          ),
      ],
    );
  }

  pw.Widget _buildBranch(
    BranchModel branch,
    String label,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
  ) {
    final content = branch.content;
    final marksSuffix = branch.marks > 0
        ? ' (${layout.formatNumber(branch.marks)} ${layout.marksUnit})'
        : '';
    // الآية القائمة بذاتها تُوسَّط بخط قرآني أوضح — نفس قرار لوحة المعاينة
    // تماماً؛ والتوسيط والحجم لا يتعلقان بتوفر الخط القرآني (الخط وحده يرتد
    // إلى خط الورقة إن غاب) حتى تبقى الشاشة والطباعة متطابقتين.
    final standaloneVerse = QuranText.isStandaloneVerse(content.text);
    final bodyStyle = (standaloneVerse
            ? styles.body.copyWith(fontSize: 12, lineSpacing: layout.lineHeightFactor * 2 + 2)
            : styles.body.copyWith(lineSpacing: layout.lineHeightFactor * 2));

    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        _renderText(
          '$label) ${content.text}$marksSuffix',
          bodyStyle,
          fonts,
          centerVerse: standaloneVerse,
        ),
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 1),
          child: _buildTypeBody(content, layout, styles, fonts, isTeacherVersion),
        ),
      ],
    );

    if (branch.attachments.isEmpty) {
      return body;
    }
    // المرفقات (صور/أشكال) تتراكب فوق مساحة الفرع بنفس إحداثيات اللوحة.
    final scale = PaperMetrics.pointsPerPixel;
    final minHeight = branch.attachments.fold<double>(
      0,
      (max, element) {
        final bottom = (element.dy + element.height) * scale;
        return bottom > max ? bottom : max;
      },
    );
    return pw.Stack(
      overflow: pw.Overflow.visible,
      children: <pw.Widget>[
        pw.ConstrainedBox(
          constraints: pw.BoxConstraints(minHeight: minHeight, minWidth: contentWidth - 24),
          child: body,
        ),
        for (final element in branch.attachments)
          pw.Positioned(
            left: layout.isLtr ? element.dx * scale : null,
            right: layout.isLtr ? null : element.dx * scale,
            top: element.dy * scale,
            child: FloatingElementsPdf.build(
              element,
              widthPt: element.width * scale,
              heightPt: element.height * scale,
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTypeBody(
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
                fonts,
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
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
  ) {
    return pw.SizedBox(
      height: _footerHeight,
      child: pw.Center(
        child: pw.Text(
          layout.isLtr
              ? 'Page $pageNumber of $pageCount'
              : 'صفحة ${layout.formatNumber(pageNumber)} من ${layout.formatNumber(pageCount)}',
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
    ExamFonts fonts, {
    bool centerVerse = false,
  }) {
    final quranFont = fonts.quranic;
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
