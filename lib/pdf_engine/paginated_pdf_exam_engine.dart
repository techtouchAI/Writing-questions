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
import '../models/question_option.dart';
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

  /// ارتفاع المحتوى الافتراضي (للهامش الافتراضي) بعد حسم التذييل.
  static double get pageContentHeight =>
      PdfPageFormat.a4.height -
      2 * pageMarginMillimeters * PdfPageFormat.mm -
      _footerHeight;

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
    // أسطر الترويسة الثلاثة×الآن تُرسم بالمحلل نفسه (معاينة وعنواناً
    // وصيغاً) — فالحاجة للخط القرآني تُحتسب منها أيضاً.
    for (final slot in HeaderSlot.values) {
      for (final line in document.header.column(slot).lines) {
        if (QuranText.containsQuran(line)) {
          return true;
        }
      }
    }
    for (final element in document.floatingElements) {
      if (QuranText.containsQuran(element.label)) {
        return true;
      }
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
    // الأنماط الأساسية مقاسة بمعاملَي الورقة العامّين (القيم الافتراضية
    // تعني 1.0 أي بلا تغيير) — والتنسيق المخصص لعنصر بعينه يبقى مطلقاً.
    final styles = ExamTextStyles.standard.scaled(
      fontScale: settings.fontScale,
      heightScale: settings.heightScale,
    );

    final pdf = pw.Document(
      title: document.name,
      creator: 'صانع ومحرر الأسئلة',
      subject: document.header.subject,
    );

    final pages = _resolvePages(
      document: document,
      pageAssignments: pageAssignments,
      measure: (widget) => _measure(widget, pdf, theme, direction, contentWidth),
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
            final blocks = <pw.Widget>[];
            final spacingAfter = <double>[];
            if (pageIndex == 0) {
              blocks.add(_buildHeader(document, layout, styles, loadedFonts));
              spacingAfter.add(_blockSpacing);
            }
            for (final id in questionIds) {
              final question = document.questionById(id)!;
              blocks.add(
                _buildQuestion(
                  document,
                  question,
                  layout,
                  styles,
                  loadedFonts,
                  isTeacherVersion,
                ),
              );
              spacingAfter.add(PaperMetrics.pt(question.spacingAfter));
            }
            final flowBlocks = <pw.Widget>[];
            for (var index = 0; index < blocks.length; index++) {
              if (index > 0) {
                flowBlocks.add(pw.SizedBox(height: spacingAfter[index - 1]));
              }
              flowBlocks.add(blocks[index]);
            }
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
                        width: contentWidth,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          mainAxisSize: pw.MainAxisSize.min,
                          children: flowBlocks,
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
                  left: margin,
                  top: margin,
                  right: margin,
                  bottom: margin,
                  child: content,
                ),
                // العناصر العائمة في الطبقة العليا بإحداثيات اللوحة نفسها:
                // موضعها اختيار المستخدم وقد يقع أعلى الورقة أو أسفلها، فترسم
                // مستقلةً عن كتل الأسئلة (بلا تكرار داخل الكتل).
                for (final element in _pageAttachments(
                  document,
                  questionIds,
                  pageIndex: pageIndex,
                  pageCount: pages.length,
                ))
                  pw.Positioned(
                    left: layout.isLtr ? element.dx * _canvasScale : null,
                    right: layout.isLtr ? null : element.dx * _canvasScale,
                    top: element.dy * _canvasScale,
                    child: FloatingElementsPdf.build(
                      element,
                      widthPt: element.width * _canvasScale,
                      heightPt: element.height * _canvasScale,
                      fonts: loadedFonts,
                      defaultFont: settings.defaultFont,
                      fontScale: settings.fontScale,
                      heightScale: settings.heightScale,
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

  /// Computes the same question-to-page assignments used by [generate] when
  /// no preview measurements are available. Word export uses this fallback so
  /// page-relative floating elements line up with the PDF export.
  Future<List<List<String>>> resolveQuestionPages({
    required ExamDocument document,
    bool isTeacherVersion = false,
    ExamFonts? fonts,
  }) async {
    final loadedFonts =
        fonts ?? await ExamFonts.load(loadQuranic: needsQuranicFont(document));
    final layout = document.layout;
    final settings = document.settings;
    final contentWidth = _contentWidthFor(document);
    final direction = layout.isLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final theme = pw.ThemeData.withFont(
      base: loadedFonts.fontFor(settings.defaultFont),
      bold: loadedFonts.fontFor(settings.defaultFont, bold: true),
    );
    final styles = ExamTextStyles.standard.scaled(
      fontScale: settings.fontScale,
      heightScale: settings.heightScale,
    );
    final pdf = pw.Document(
      title: document.name,
      creator: 'صانع ومحرر الأسئلة',
      subject: document.header.subject,
    );

    return _resolvePages(
      document: document,
      pageAssignments: null,
      measure: (widget) => _measure(widget, pdf, theme, direction, contentWidth),
      layout: layout,
      styles: styles,
      fonts: loadedFonts,
      isTeacherVersion: isTeacherVersion,
    );
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
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final printableQuestions = document.questions
        .where((question) => question.hasExportableContent(
              teacher: isTeacherVersion,
              ignoredAttachmentIds: globalElementIds,
            ))
        .toList(growable: false);
    if (pageAssignments != null &&
        _coversAllQuestions(pageAssignments, printableQuestions)) {
      return pageAssignments
          .map((page) => List<String>.unmodifiable(page))
          .toList(growable: false);
    }

    final headerHeight = measure(_buildHeader(document, layout, styles, fonts));
    final result = PaginationEngine.paginate(
      blocks: <PageBlock>[
        PageBlock(
          id: PaperMetrics.headerBlockId,
          height: headerHeight,
          spacingAfter: _blockSpacing,
        ),
        for (final question in printableQuestions)
          PageBlock(
            id: question.id,
            height: measure(_buildQuestion(
                document, question, layout, styles, fonts, isTeacherVersion)),
            spacingAfter: PaperMetrics.pt(question.spacingAfter),
          ),
      ],
      pageHeight: _pageContentHeightFor(document),
      spacing: _blockSpacing,
    );
    return <List<String>>[
      for (final page in result.pages)
        page.blockIds.where((id) => id != PaperMetrics.headerBlockId).toList(growable: false),
    ];
  }

  /// نسبة تحويل بكسل اللوحة إلى نقاط الـ PDF (نفس النسبة في كل المحرك).
  static double get _canvasScale => PaperMetrics.pointsPerPixel;

  /// العناصر العامة على الصفحة، مع العناصر القديمة التابعة لأسئلة الصفحة.
  /// تُتجاهل النسخ التوافقية الموجودة داخل السؤال/الفرع حتى لا تُطبع مرتين.
  static List<FloatingElement> _pageAttachments(
    ExamDocument document,
    List<String> questionIds, {
    required int pageIndex,
    required int pageCount,
  }) {
    final elements = <FloatingElement>[];
    final seenIds = <String>{};
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final lastPage = pageCount - 1;
    for (final element in document.floatingElements) {
      final assignedPage = element.pageIndex.clamp(0, lastPage).toInt();
      if (assignedPage == pageIndex && seenIds.add(element.id)) {
        elements.add(element);
      }
    }
    for (final id in questionIds) {
      final question = document.questionById(id);
      if (question == null) {
        continue;
      }
      for (final element in question.attachments) {
        if (!globalIds.contains(element.id) && seenIds.add(element.id)) {
          elements.add(element);
        }
      }
      for (final branch in question.branches) {
        for (final element in branch.attachments) {
          if (!globalIds.contains(element.id) && seenIds.add(element.id)) {
            elements.add(element);
          }
        }
      }
    }
    return elements;
  }

  static bool _coversAllQuestions(
    List<List<String>> pages,
    List<QuestionModel> printableQuestions,
  ) {
    final assigned = <String>{for (final page in pages) ...page};
    final expected = printableQuestions.map((question) => question.id).toSet();
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
    double contentWidth,
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
      styles.headerBody.copyWith(lineSpacing: 2 * settings.heightScale),
      header.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final centerStyle = PaperStyleResolver.apply(
      styles.headerBody.copyWith(
          fontWeight: pw.FontWeight.bold, lineSpacing: 2 * settings.heightScale),
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
      // الأسطر الفارغة تُحذف تماماً ولا تترك مسافة بيضاء.
      final lines =
          source.lines.where((line) => line.trim().isNotEmpty).toList(growable: false);
      return pw.Expanded(
        flex: align == pw.TextAlign.center ? 4 : 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: <pw.Widget>[
            // الصيغ داخل أسطر الترويسة تُرسم كمعادلات (SVG) كما في متن
            // الأسئلة — لا نص LaTeX خام على الورقة.
            for (final line in lines)
              _renderText(line, style, fonts.quranic,
                  align: align, maxLines: 2),
          ],
        ),
      );
    }

    final instructions = header.instructions.trim();
    final notes = header.notes.trim();
    final title = header.title.trim();
    final titleAlign =
        PaperStyleResolver.toPdfAlign(header.style.align) ?? pw.TextAlign.center;
    // محاذاة حددها المدرس لأي سطر ترويسة تُطبَّق على الأعمدة كلها (كما
    // تعرضها الشاشة)؛ والافتراضي العمودي يبقى كما كان عند غيابها.
    final headerAlign = PaperStyleResolver.toPdfAlign(header.style.align);
    final children = <pw.Widget>[
      if (title.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: _renderText(title, titleStyle, fonts.quranic, align: titleAlign),
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
            column(header.right, lineStyle, headerAlign ?? pw.TextAlign.start),
            pw.SizedBox(width: 6),
            column(header.center, centerStyle, headerAlign ?? pw.TextAlign.center),
            pw.SizedBox(width: 6),
            column(header.left, lineStyle, headerAlign ?? pw.TextAlign.start),
          ],
        ),
      ),
      if (instructions.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: _renderText(instructions, styles.note, fonts.quranic,
              align: pw.TextAlign.center),
        ),
      if (notes.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: _renderText(notes, styles.note, fonts.quranic,
              align: pw.TextAlign.center),
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
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final category = question.category.trim();
    final label = document.displayQuestionLabel(question);
    final marksPart = settings.showQuestionMarks
        ? ': [${document.formatNumber(question.marks)} ${layout.marksUnit}]'
        : '';
    final bodyOverride = question.style.copyWith(color: () => null);
    final titleOverride = question.style.copyWith(
      color: () => question.effectiveTitleColor,
    );
    final titleStyle = PaperStyleResolver.apply(
      styles.question,
      titleOverride,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final titleAlign =
        PaperStyleResolver.toPdfAlign(question.titleAlign ?? question.style.align) ?? pw.TextAlign.start;

    final prompt = question.prompt.trim();
    final promptStyle = PaperStyleResolver.apply(
      styles.body.copyWith(
          lineSpacing: layout.lineHeightFactor * 2 * settings.heightScale),
      bodyOverride,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final paragraphGap = PaperMetrics.pt(question.style.paragraphSpacing ?? 2);

    final children = <pw.Widget>[
      if (category.isNotEmpty)
        pw.Text(
          category,
          style: PaperStyleResolver.apply(styles.category, bodyOverride,
              fonts: fonts, defaultFont: settings.defaultFont),
          textAlign: titleAlign,
        ),
      pw.Text('$label$marksPart', style: titleStyle, textAlign: titleAlign),
      if (prompt.isNotEmpty)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: paragraphGap),
          child: _renderText(
            prompt,
            promptStyle,
            fonts.quranic,
            align: PaperStyleResolver.toPdfAlign(question.promptAlign ?? question.style.align),
          ),
        ),
      // نقاط السؤال المباشرة (1، 2، 3...) — ترقيم تلقائي كما في نقاط الفرع.
      if (question.items.any((item) =>
          item.showsInExport(teacher: isTeacherVersion, trueFalse: false)))
        pw.Padding(
          padding: pw.EdgeInsetsDirectional.only(start: 14, top: paragraphGap),
          child: _buildItems(
            document,
            question.items,
            layout,
            styles,
            fonts,
            isTeacherVersion,
            bodyOverride,
            trueFalse: false,
            trueFalseFormat: question.trueFalseFormat,
          ),
        ),
      for (var index = 0; index < question.branches.length; index++)
        if (question.branches[index].hasExportableContent(
          teacher: isTeacherVersion,
          ignoredAttachmentIds: globalElementIds,
        ))
          pw.Padding(
            padding: pw.EdgeInsetsDirectional.only(start: 10, top: paragraphGap),
            child: _buildBranch(
              document,
              question.branches[index],
              document.displayBranchLabel(
                document.indexOfQuestion(question.id),
                index,
              ),
              layout,
              styles,
              fonts,
              isTeacherVersion,
              globalElementIds,
            ),
          ),
      if (question.dividerAfter != null)
        _buildDivider(question.dividerAfter!, _contentWidthFor(document)),
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
    // حافظ على المساحة المحجوزة للمرفقات القديمة. المرايا المسجلة في
    // document.floatingElements لا تؤثر في ارتفاع كتلة السؤال.
    final legacyAttachments = question.attachments
        .where((element) => !globalElementIds.contains(element.id))
        .toList(growable: false);
    if (legacyAttachments.isEmpty) {
      return body;
    }
    return _withAttachments(
      body: body,
      attachments: legacyAttachments,
      contentWidth: _contentWidthFor(document),
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
    Set<String> globalElementIds,
  ) {
    final settings = document.settings;
    final content = branch.content;
    // الفرع الفارغ تماماً يُحذف من المطبوع كاملاً (مع فاصله) ولا يترك مسافة.
    if (!branch.hasExportableContent(
      teacher: isTeacherVersion,
      ignoredAttachmentIds: globalElementIds,
    )) {
      return pw.SizedBox();
    }
    final marksSuffix = branch.marks > 0
        ? ' (${document.formatNumber(branch.marks)} ${layout.marksUnit})'
        : '';
    final hasText = content.text.trim().isNotEmpty;
    // سطر التسمية: النص عند وجوده، وإلا التسمية الهيكلية وحدها بلا فراغ شارد.
    final labelLine =
        hasText ? '$label) ${content.text}$marksSuffix' : '$label)$marksSuffix';
    // المقاطع الموسومة بالآيات تُرسم بالخط القرآني في كل القوالب، وأما
    // «أسلوب المصحف» — توسيط الآية القائمة بذاتها وتكبيرها — فيتبع تفضيل
    // القالب ([SubjectLayoutTemplate.prefersQuranicFont] أي التربية
    // الإسلامية). وهو **نفس قرار لوحة المعاينة** حرفياً؛ والتوسيط والحجم لا
    // يتعلقان بتوفر الخط (الخط وحده يرتد إلى خط الورقة إن غاب الأصل).
    final standaloneVerse = hasText &&
        layout.prefersQuranicFont &&
        QuranText.isStandaloneVerse(content.text);
    final baseBody = standaloneVerse
        ? styles.body.copyWith(
            fontSize: 12 * settings.fontScale,
            lineSpacing:
                (layout.lineHeightFactor * 2 + 2) * settings.heightScale)
        : styles.body.copyWith(
            lineSpacing: layout.lineHeightFactor * 2 * settings.heightScale);
    final bodyStyle = PaperStyleResolver.apply(
      baseBody,
      branch.style,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final branchAlign = PaperStyleResolver.toPdfAlign(branch.style.align);
    // مطابقة اللوحة حرفياً: النص الحر يُخفي مساحة الإجابة عن الطالب،
    // وخيارات الاختيار تُخفى في نموذج المعلم للفرع الحر.
    final hasVisibleTypeBody =
        content.hasPrintableTypeBody(teacher: isTeacherVersion);
    final paragraphGap = PaperMetrics.pt(branch.style.paragraphSpacing ?? 1);

    final children = <pw.Widget>[
      _renderText(
        labelLine,
        bodyStyle,
        fonts.quranic,
        centerVerse: standaloneVerse,
        align: branchAlign,
      ),
      if (content.items.any((item) => item.showsInExport(
          teacher: isTeacherVersion,
          trueFalse: content.type == QuestionType.trueFalse)))
        pw.Padding(
          padding: pw.EdgeInsetsDirectional.only(start: 14, top: paragraphGap),
          child: _buildItems(
            document,
            content.items,
            layout,
            styles,
            fonts,
            isTeacherVersion,
            branch.style,
            trueFalse: content.type == QuestionType.trueFalse,
            trueFalseFormat: content.trueFalseFormat,
          ),
        ),
      if (hasVisibleTypeBody)
        pw.Padding(
          padding: pw.EdgeInsetsDirectional.only(start: 14, top: paragraphGap),
          child: _buildTypeBody(
            document,
            content,
            layout,
            styles,
            fonts,
            isTeacherVersion,
            branch.style,
          ),
        ),
      if (branch.dividerAfter != null)
        _buildDivider(branch.dividerAfter!, _contentWidthFor(document)),
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
    final legacyAttachments = branch.attachments
        .where((element) => !globalElementIds.contains(element.id))
        .toList(growable: false);
    if (legacyAttachments.isEmpty) {
      return body;
    }
    return _withAttachments(
      body: body,
      attachments: legacyAttachments,
      contentWidth: _contentWidthFor(document),
    );
  }

  /// نقاط مرقَّمة (داخل سؤال أو فرع) بترقيمها (تلقائي أو مخصص) — والفارغة
  /// تُحذف. نفس مسار العرض للنقطتين معاً (ما تراه اللوحة هو ما يُطبع).
  pw.Widget _buildItems(
    ExamDocument document,
    List<BranchItem> items,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
    PaperTextStyle? ownerStyle, {
    required bool trueFalse,
    String trueFalseFormat = 'words',
  }) {
    final settings = document.settings;
    final itemStyle = PaperStyleResolver.apply(
      styles.body.copyWith(
          lineSpacing: layout.lineHeightFactor * 2 * settings.heightScale),
      ownerStyle,
      fonts: fonts,
      defaultFont: settings.defaultFont,
    );
    final align = PaperStyleResolver.toPdfAlign(ownerStyle?.align);
    final paragraphGap = PaperMetrics.pt(ownerStyle?.paragraphSpacing ?? 0);
    final children = <pw.Widget>[];
    var visibleItemCount = 0;
    for (var index = 0; index < items.length; index++) {
      if (!items[index].showsInExport(teacher: isTeacherVersion, trueFalse: trueFalse)) {
        continue;
      }
      if (visibleItemCount > 0 && paragraphGap > 0) {
        children.add(pw.SizedBox(height: paragraphGap));
      }
      children.add(
        _buildItem(
          document,
          items[index],
          index,
          layout,
          itemStyle,
          fonts,
          isTeacherVersion,
          PaperStyleResolver.toPdfAlign(items[index].align) ?? align,
          trueFalse: trueFalse,
          trueFalseFormat: trueFalseFormat,
        ),
      );
      visibleItemCount++;
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  pw.Widget _buildItem(
    ExamDocument document,
    BranchItem item,
    int index,
    SubjectLayoutTemplate layout,
    pw.TextStyle style,
    ExamFonts fonts,
    bool isTeacherVersion,
    pw.TextAlign? align, {
    required bool trueFalse,
    String trueFalseFormat = 'words',
  }) {
    final marksSuffix = item.marks > 0
        ? ' (${document.formatNumber(item.marks)} ${layout.marksUnit})'
        : '';
    // إجابة النقطة لصح/خطأ — في نموذج المعلم فقط.
    var answerSuffix = '';
    if (isTeacherVersion && trueFalse && item.isCorrect != null) {
      if (trueFalseFormat == 'symbols') {
        answerSuffix = item.isCorrect! ? ' (✓)' : ' (✗)';
      } else {
        answerSuffix = layout.isLtr
            ? (item.isCorrect! ? ' (True)' : ' (False)')
            : (item.isCorrect! ? ' (صح)' : ' (خطأ)');
      }
    }
    final itemLabel = document.displayItemLabel(item, index);
    final chunks = <String>[
      if (itemLabel.isNotEmpty) itemLabel,
      if (item.text.trim().isNotEmpty) item.text,
    ];
    final line = '${chunks.join(' ')}$marksSuffix$answerSuffix';
    if (line.trim().isEmpty) {
      return pw.SizedBox();
    }
    return _renderText(
      line,
      style,
      fonts.quranic,
      align: align,
    );
  }

  pw.Widget _buildDivider(PaperDivider divider, double contentWidth) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        top: divider.spacingBefore,
        bottom: divider.spacingAfter,
      ),
      child: pw.Center(
        child: pw.SizedBox(
          width: contentWidth * divider.widthFraction,
          child: pw.Divider(
            thickness: divider.thickness,
            color: ExamTextStyles.primaryColor,
            height: divider.thickness + 2,
          ),
        ),
      ),
    );
  }

  /// يحافظ على سلوك الملفات القديمة التي كانت تحجز مساحة للمرفقات التابعة
  /// لسؤال/فرع؛ العناصر العامة الجديدة لا تمر عبر هذا المسار.
  pw.Widget _withAttachments({
    required pw.Widget body,
    required List<FloatingElement> attachments,
    required double contentWidth,
  }) {
    final scale = PaperMetrics.pointsPerPixel;
    final minHeight = attachments.fold<double>(
      0,
      (max, element) {
        final bottom = (element.dy + element.height) * scale;
        return bottom > max ? bottom : max;
      },
    );
    return pw.ConstrainedBox(
      constraints: pw.BoxConstraints(minHeight: minHeight, minWidth: contentWidth - 24),
      child: body,
    );
  }

  pw.Widget _buildTypeBody(
    ExamDocument document,
    BranchContent content,
    SubjectLayoutTemplate layout,
    ExamTextStyles styles,
    ExamFonts fonts,
    bool isTeacherVersion,
    PaperTextStyle? branchStyle,
  ) {
    final bodyStyle = PaperStyleResolver.apply(
      styles.body,
      branchStyle,
      fonts: fonts,
      defaultFont: document.settings.defaultFont,
    );
    final optionStyle = PaperStyleResolver.apply(
      styles.option,
      branchStyle,
      fonts: fonts,
      defaultFont: document.settings.defaultFont,
    );
    final branchColor = branchStyle?.color == null
        ? null
        : PdfColor.fromInt(branchStyle!.color!);
    final styledAnswer = bodyStyle.copyWith(
      color: branchColor ?? ExamTextStyles.successColor,
      fontWeight: pw.FontWeight.bold,
    );
    final styledOptionAnswer = optionStyle.copyWith(
      color: branchColor ?? ExamTextStyles.successColor,
      fontWeight: pw.FontWeight.bold,
    );
    final align = PaperStyleResolver.toPdfAlign(branchStyle?.align);
    // محاذاة الإجابة النموذجية/صح-خطأ: نظيرها في الموديل يعلو محاذاة الفرع.
    final answerAlign = PaperStyleResolver.toPdfAlign(content.modelAnswerAlign) ?? align;
    switch (content.type) {
      case QuestionType.multipleChoice:
        // الخيارات الفارغة تُحذف، لكن التسميات تبقى بفهارسها الأصلية
        // (مطابقة اللوحة) ولا يعاد ترقيم المخصص منها أبداً.
        return pw.Wrap(
          spacing: branchStyle?.paragraphSpacing == null
              ? 14
              : PaperMetrics.pt(branchStyle!.paragraphSpacing!),
          runSpacing: PaperMetrics.pt(branchStyle?.paragraphSpacing ?? 2),
          children: <pw.Widget>[
            for (var index = 0; index < content.options.length; index++)
              if (content.options[index].text.trim().isNotEmpty)
                _renderText(
                  _optionLine(
                    document,
                    content.options[index],
                    index,
                    isTeacherVersion && content.options[index].isCorrect,
                  ),
                  isTeacherVersion && content.options[index].isCorrect
                      ? styledOptionAnswer
                      : optionStyle,
                  fonts.quranic,
                  align: PaperStyleResolver.toPdfAlign(content.options[index].align) ??
                      align,
                ),
          ],
        );
      case QuestionType.trueFalse:
        // ورقة الطالب: الأسئلة فقط — الإجابة في دفتر الطالب، بلا مساحة
        // إجابة مولَّدة على الورقة.
        if (!isTeacherVersion || content.items.isNotEmpty) {
          return pw.SizedBox();
        }
        final answer = content.trueFalseAnswer;
        final answerStr = content.trueFalseFormat == 'symbols'
            ? (answer ? '✓' : '✗')
            : (layout.isLtr
                ? (answer ? 'True' : 'False')
                : (answer ? 'صح' : 'خطأ'));
        return pw.Text(
          layout.isLtr
              ? 'Answer: $answerStr •'
              : 'الإجابة الصحيحة: $answerStr •',
          style: styledAnswer,
          textAlign: answerAlign,
        );
      case QuestionType.fillInTheBlank:
        if (!isTeacherVersion) {
          return pw.SizedBox();
        }
        final fillModel = content.modelAnswer.trim();
        if (fillModel.isEmpty) {
          return pw.SizedBox();
        }
        return _renderText(
          '${layout.isLtr ? 'Model answer' : 'الإجابة النموذجية'}: $fillModel •',
          styledAnswer,
          fonts.quranic,
          align: answerAlign,
        );
      case QuestionType.definitions:
      case QuestionType.essay:
        if (isTeacherVersion) {
          final essayModel = content.modelAnswer.trim();
          if (essayModel.isEmpty) {
            return pw.SizedBox();
          }
          return _renderText(
            '${layout.isLtr ? 'Model answer' : 'الإجابة النموذجية وعناصر التقييم'}: '
            '$essayModel •',
            styledAnswer,
            fonts.quranic,
            align: answerAlign,
          );
        }
        return pw.SizedBox();
    }
  }

  /// سطر الخيار: تسميته (تلقائية بفهرسها الأصلي أو مخصصة) ثم نصه.
  String _optionLine(
    ExamDocument document,
    QuestionOption option,
    int index,
    bool markCorrect,
  ) {
    final label = document.displayOptionLabel(option, index);
    final prefix = label.isEmpty ? '' : '$label ';
    return '$prefix${option.text}${markCorrect ? ' •' : ''}';
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
  /// [centerVerse] يوسّط آية قائمة بذاتها كما في لوحة المعاينة، و[align]
  /// محاذاة الكتلة المختارة من شريط التنسيق.
  pw.Widget _renderText(
    String text,
    pw.TextStyle style,
    pw.Font? quranFont, {
    bool centerVerse = false,
    pw.TextAlign? align,
    int? maxLines,
  }) {
    final segments = TexContent.split(text);
    final hasMath = segments.any((segment) => segment.isMath);
    if (!hasMath) {
      return _plainText(text, style, quranFont,
          centerVerse: centerVerse, align: align, maxLines: maxLines);
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
          alignment: _wrapAlign(align),
          crossAxisAlignment: pw.WrapCrossAlignment.center,
          children: List<pw.Widget>.of(inline),
        ),
      );
      inline = <pw.Widget>[];
    }

    for (final segment in segments) {
      if (!segment.isMath) {
        if (segment.text.isNotEmpty) {
          inline.add(_plainText(segment.text, style, quranFont,
              align: align, maxLines: maxLines));
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
      crossAxisAlignment: _columnAlign(align),
      mainAxisSize: pw.MainAxisSize.min,
      children: rows,
    );
  }

  static pw.CrossAxisAlignment _columnAlign(pw.TextAlign? align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.CrossAxisAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
  }

  static pw.WrapAlignment _wrapAlign(pw.TextAlign? align) {
    switch (align) {
      case pw.TextAlign.center:
        return pw.WrapAlignment.center;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.WrapAlignment.end;
      default:
        return pw.WrapAlignment.start;
    }
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
    pw.TextAlign? align,
    int? maxLines,
  }) {
    if (quranFont == null || !QuranText.containsQuran(text)) {
      return pw.Text(
        text,
        style: style,
        textAlign: centerVerse ? pw.TextAlign.center : align,
        maxLines: maxLines,
      );
    }
    final spans = <pw.InlineSpan>[];
    for (final segment in QuranText.split(text)) {
      if (segment.text.isEmpty) {
        continue;
      }
      // تنبيه دقيق في حزمة pdf: `copyWith(font:)` يوجَّه إلى خانة الوزن
      // الفارغة فقط، وأي خط مضبوط مسبقاً (مثل Noto الصريح الذي يضعه
      // PaperStyleResolver) يبقى ويسقط الخط الممرَّر. لذلك تُتجاوَز هنا
      // الخانات الأربع صراحةً ليُلبَس الخط القرآني حتماً.
      spans.add(
        pw.TextSpan(
          text: segment.text,
          style: segment.isQuran
              ? style.copyWith(
                  fontNormal: quranFont,
                  fontBold: quranFont,
                  fontItalic: quranFont,
                  fontBoldItalic: quranFont,
                )
              : style,
        ),
      );
    }
    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: centerVerse ? pw.TextAlign.center : null,
      maxLines: maxLines,
    );
  }

}
