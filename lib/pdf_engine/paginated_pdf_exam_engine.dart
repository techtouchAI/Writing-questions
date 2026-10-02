import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/blueprint/exam_blueprint.dart';
import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_item.dart';
import '../models/exam_canvas_geometry.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import '../models/question_model.dart';
import '../models/quran_text.dart';
import 'exam_fonts.dart';
import 'pdf_math_rasters.dart';
import 'exam_strategy.dart' show ExamTextStyles;
import 'floating_elements_pdf.dart';
import 'pdf_paper_builder.dart';

/// محرك PDF متعدد الصفحات لورقة الأسئلة (WYSIWYG A4).
///
/// المحرك **منسّق** فقط: يحسب التقسيم الورقي ويركّب الصفحات؛ أما بناء
/// العناصر (الترويسة/السؤال/النقاط/التذييل/الإطار) فمسؤولية
/// [PdfPaperBuilder] من مخطط الورقة المشترك [ExamBlueprint].
///
/// الضمانات:
/// 1. **السؤال وحدة لا تتجزأ**: التقسيم الورقي يُحسب عبر [PaginationEngine]
///    (نفس محرك الشاشة) على ارتفاعات الكتل المقاسة فعلياً بمقاييس pdf؛
///    وعند تمرير [pageAssignments] من لوحة المعاينة يُطبع **نفس** التوزيع
///    المعروض على الشاشة تماماً.
/// 2. **التذييل في آخر صفحة فقط** وملتصق بأسفل صندوق المحتوى، ومساحته
///    محجوزة في التقسيم فلا يتداخل مع أي سؤال. لا ترقيم للصفحات إطلاقاً.
/// 3. **لا تجاوز للورقة أبداً**: محتوى كل صفحة داخل [pw.FittedBox] بوضع
///    `scaleDown` كشبكة أمان ضد فروق قياس الخطوط بين الشاشة والطباعة.
/// 4. **صندوق المحتوى** يُشتق من هامش الورقة وحده (`marginMm`)، وهو نفسه
///    حشوة الإطار (صورة PNG شفافة أو إطار متجه) فلا يتداخل النص معه.
/// 5. **قالب المادة** يقرّر اتجاه منطقة الأسئلة وترقيمها ونسق أرقامها.
class PaginatedPdfExamEngine {
  PaginatedPdfExamEngine();

  static const double pageMarginMillimeters = 15;

  /// عرض المحتوى الافتراضي (للهامش الافتراضي) — يُستخدم في القياسات
  /// الخارجية؛ العرض الفعلي لكل مستند يُحسب من هامشه عبر [_contentWidthFor].
  static double get contentWidth =>
      PdfPageFormat.a4.width - 2 * pageMarginMillimeters * PdfPageFormat.mm;

  /// إزاحة بداية كتلة الفرع عن صندوق المحتوى (بنقاط PDF).
  static const double branchIndent = PdfPaperBuilder.branchIndent;

  /// ارتفاع المحتوى الافتراضي (للهامش الافتراضي).
  static double get pageContentHeight =>
      PdfPageFormat.a4.height - 2 * pageMarginMillimeters * PdfPageFormat.mm;

  static double get _blockSpacing => PaperMetrics.pt(PaperMetrics.blockSpacingPx);

  static double _marginFor(ExamDocument document) =>
      document.settings.marginMm * PdfPageFormat.mm;

  static double _contentWidthFor(ExamDocument document) =>
      PdfPageFormat.a4.width - 2 * _marginFor(document);

  static double _pageContentHeightFor(ExamDocument document) =>
      PdfPageFormat.a4.height - 2 * _marginFor(document);

  /// هل تحتاج الورقة الخط القرآني (Amiri)؟ نعم عند تفعيل البسملة أو وجود
  /// نص موسوم بآية قرآنية — وإلا لا يُحمَّل أصل الخط أصلاً.
  static bool needsQuranicFont(ExamDocument document) {
    if (document.header.showBismillah) {
      return true;
    }
    for (final element in document.floatingElements) {
      if (QuranText.containsQuran(element.label)) {
        return true;
      }
    }
    for (final question in document.questions) {
      if (QuranText.containsQuran(question.statement) ||
          QuranText.containsQuran(question.body) ||
          _pointsContainQuran(question.items)) {
        return true;
      }
      for (final element in question.attachments) {
        if (QuranText.containsQuran(element.label)) {
          return true;
        }
      }
      for (final branch in question.branches) {
        final content = branch.content;
        if (QuranText.containsQuran(content.statement) ||
            QuranText.containsQuran(content.body) ||
            _pointsContainQuran(content.items)) {
          return true;
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

  static bool _pointsContainQuran(List<BranchItem> items) {
    for (final item in items) {
      if (QuranText.containsQuran(item.text)) {
        return true;
      }
      for (final option in item.options) {
        if (QuranText.containsQuran(option.text)) {
          return true;
        }
      }
    }
    return false;
  }

  /// يولّد ملف PDF متعدد الصفحات بحجم A4.
  ///
  /// [pageAssignments]: توزيع معرّفات الأسئلة على الصفحات كما حُسب على
  /// الشاشة؛ عند غيابه يُحسب التوزيع هنا بقياس عناصر pdf نفسها.
  /// [frameImage]: بايتات صورة PNG الإطار (تُقرأ من مسارها في طبقة
  /// الخدمات)؛ غيابها يرسم الإطار المتجه عند تفعيل «إطار حول الصفحة».
  Future<Uint8List> generate({
    required ExamDocument document,
    List<List<String>>? pageAssignments,
    ExamFonts? fonts,
    Uint8List? frameImage,
  }) async {
    final loadedFonts =
        fonts ?? await ExamFonts.load(loadQuranic: needsQuranicFont(document));
    // مرحلتان: جولة تبني الورقة كاملةً وتسجّل كل معادلة يحتاجها الرسم — متن
    // وفروع ومربعات نص وبطاقات معادلة حرّة — ثم تُلتقط كلها دفعة واحدة بمحرك
    // المعاينة، ثم تُبنى الورقة ثانيةً والمخزون خلف كل طلب. والسبب أن بناء
    // `pdf` متزامن واللقطة تحتاج إطار رسم في شجرة الودجت. ورقة بلا معادلات
    // تُستعمل منها الجولة الأولى كما هي (لا إعادة بناء بلا طائل).
    final collected = PdfMathRasters.collecting();
    final probe = await _generateOnce(
      document: document,
      pageAssignments: pageAssignments,
      fonts: loadedFonts,
      frameImage: frameImage,
      mathRasters: collected,
    );
    if (collected.isEmpty) {
      return probe;
    }
    return _generateOnce(
      document: document,
      pageAssignments: pageAssignments,
      fonts: loadedFonts,
      frameImage: frameImage,
      mathRasters: await collected.resolve(),
    );
  }

  /// بناء ملف واحد فعلي: [mathRasters] هو مخزون لقطات المعادلات (أو جولة جمع
  /// في `_generateOnce` الأولى)، ونتاجه بايتات PDF كاملة.
  Future<Uint8List> _generateOnce({
    required ExamDocument document,
    required List<List<String>>? pageAssignments,
    required ExamFonts fonts,
    required Uint8List? frameImage,
    required PdfMathRasters mathRasters,
  }) async {
    final loadedFonts = fonts;
    final layout = document.layout;
    final settings = document.settings;
    final margin = _marginFor(document);
    final contentWidth = _contentWidthFor(document);
    final direction = layout.isLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final theme = _themeFor(document, loadedFonts);
    // الأنماط الأساسية مقاسة بمعاملَي الورقة العامّين (القيم الافتراضية
    // تعني 1.0 أي بلا تغيير) — والتنسيق المخصص لعنصر بعينه يبقى مطلقاً.
    final styles = ExamTextStyles.standard.scaled(
      fontScale: settings.fontScale,
      heightScale: settings.heightScale,
    );
    final blueprint = ExamBlueprint.from(document);
    final builder = PdfPaperBuilder(
      document: document,
      blueprint: blueprint,
      fonts: loadedFonts,
      styles: styles,
      mathRasters: mathRasters,
    );

    final pdf = _newDocument(document);
    double measure(pw.Widget widget) =>
        _measure(widget, pdf, theme, direction, contentWidth);

    final pages = _resolvePages(
      document: document,
      blueprint: blueprint,
      builder: builder,
      pageAssignments: pageAssignments,
      measure: measure,
    );

    // أعلى كل سؤال داخل صفحته (نقاط PDF) — مرجع العناصر المرتبطة بالسؤال،
    // فالسؤال قد يتصدّر الصفحة أو يتأخر بعد غيره أو ينتقل بين الصفحات.
    final headerHeight = measure(builder.header());
    final questionTopsByPage = <int, Map<String, double>>{};
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final tops = <String, double>{};
      var top = margin;
      if (pageIndex == 0) {
        top += headerHeight + _blockSpacing;
      }
      for (final id in pages[pageIndex]) {
        tops[id] = top;
        final question = blueprint.questionById(id);
        if (question == null) {
          continue;
        }
        top += measure(builder.question(question)) +
            PaperMetrics.pt(question.model.spacingAfter);
      }
      questionTopsByPage[pageIndex] = tops;
    }

    final frameLayer = builder.frame(imageBytes: frameImage);
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final questionIds = pages[pageIndex];
      final isLastPage = pageIndex == pages.length - 1;
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
              blocks.add(builder.header());
              spacingAfter.add(_blockSpacing);
            }
            for (final id in questionIds) {
              final question = blueprint.questionById(id)!;
              blocks.add(builder.question(question));
              spacingAfter.add(PaperMetrics.pt(question.model.spacingAfter));
            }
            final flowBlocks = <pw.Widget>[];
            for (var index = 0; index < blocks.length; index++) {
              if (index > 0) {
                flowBlocks.add(pw.SizedBox(height: spacingAfter[index - 1]));
              }
              flowBlocks.add(blocks[index]);
            }
            final content = pw.Column(
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
                // التذييل في أسفل آخر صفحة فقط (وملتصق بأسفل صندوق المحتوى).
                if (isLastPage) ...<pw.Widget>[
                  pw.SizedBox(height: _blockSpacing),
                  builder.footer(),
                ],
              ],
            );
            return pw.Stack(
              children: <pw.Widget>[
                if (frameLayer != null) frameLayer,
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
                for (final placement in _pageAttachmentPlacements(
                  document,
                  questionIds,
                  pageIndex: pageIndex,
                  pageCount: pages.length,
                  questionTops: questionTopsByPage[pageIndex] ?? const <String, double>{},
                ))
                  pw.Positioned(
                    left: layout.isLtr ? placement.edge : null,
                    right: layout.isLtr ? null : placement.edge,
                    top: placement.top,
                    child: FloatingElementsPdf.build(
                      placement.element,
                      widthPt: placement.element.width * _canvasScale,
                      heightPt: placement.element.height * _canvasScale,
                      fonts: loadedFonts,
                      defaultFont: settings.defaultFont,
                      fontScale: settings.fontScale,
                      heightScale: settings.heightScale,
                      mathRasters: mathRasters,
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
    ExamFonts? fonts,
  }) async {
    final loadedFonts =
        fonts ?? await ExamFonts.load(loadQuranic: needsQuranicFont(document));
    final settings = document.settings;
    final contentWidth = _contentWidthFor(document);
    final direction =
        document.layout.isLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final theme = _themeFor(document, loadedFonts);
    final styles = ExamTextStyles.standard.scaled(
      fontScale: settings.fontScale,
      heightScale: settings.heightScale,
    );
    final blueprint = ExamBlueprint.from(document);
    final pdf = _newDocument(document);

    List<List<String>> assign(PdfPaperBuilder paperBuilder) => _resolvePages(
          document: document,
          blueprint: blueprint,
          builder: paperBuilder,
          pageAssignments: null,
          measure: (widget) =>
              _measure(widget, pdf, theme, direction, contentWidth),
        );

    // ارتفاع المعادلة يحدّد التقسيم، فقياسٌ بلا لقطات يعطي تقسيماً غير
    // التقسيم المطبوع: جولة جمع ثم قياس بالمخزون نفسه (كـ generate).
    final collected = PdfMathRasters.collecting();
    final probe = assign(
      PdfPaperBuilder(
        document: document,
        blueprint: blueprint,
        fonts: loadedFonts,
        styles: styles,
        mathRasters: collected,
      ),
    );
    if (collected.isEmpty) {
      return probe;
    }
    return assign(
      PdfPaperBuilder(
        document: document,
        blueprint: blueprint,
        fonts: loadedFonts,
        styles: styles,
        mathRasters: await collected.resolve(),
      ),
    );
  }

  /// مستند PDF ببيانات وصفية كاملة: الملف يحمل هويته (اسم الورقة، المادة،
  /// المنتج) فيخصّص للطباعة والأرشفة بلا فقدان معلومات.
  static pw.Document _newDocument(ExamDocument document) => pw.Document(
        title: document.name,
        creator: 'صانع ومحرر الأسئلة',
        producer: 'صانع ومحرر الأسئلة — محرك PDF',
        author: document.header.schoolName.isEmpty
            ? null
            : document.header.schoolName,
        subject: document.header.subject,
        keywords: 'ورقة أسئلة, امتحان, ${document.header.subject}',
      );

  pw.ThemeData _themeFor(ExamDocument document, ExamFonts fonts) {
    final font = document.settings.defaultFont;
    return pw.ThemeData.withFont(
      base: fonts.fontFor(font),
      bold: fonts.fontFor(font, bold: true),
    );
  }

  // ------------------------------------------------------------------
  // التقسيم الورقي
  // ------------------------------------------------------------------

  List<List<String>> _resolvePages({
    required ExamDocument document,
    required ExamBlueprint blueprint,
    required PdfPaperBuilder builder,
    required List<List<String>>? pageAssignments,
    required double Function(pw.Widget) measure,
  }) {
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final printableQuestions = blueprint.questions
        .where((question) => question.isPrintable(
              ignoredAttachmentIds: globalElementIds,
            ))
        .map((question) => question.model)
        .toList(growable: false);
    if (pageAssignments != null &&
        _coversAllQuestions(pageAssignments, printableQuestions)) {
      return pageAssignments
          .map((page) => List<String>.unmodifiable(page))
          .toList(growable: false);
    }

    final result = PaginationEngine.paginate(
      blocks: <PageBlock>[
        PageBlock(
          id: PaperMetrics.headerBlockId,
          height: measure(builder.header()),
          spacingAfter: _blockSpacing,
        ),
        for (final question in printableQuestions)
          PageBlock(
            id: question.id,
            height: measure(builder.question(blueprint.questionById(question.id)!)),
            spacingAfter: PaperMetrics.pt(question.spacingAfter),
          ),
      ],
      pageHeight: _pageContentHeightFor(document),
      spacing: _blockSpacing,
      // مساحة التذييل (يُطبع أسفل آخر صفحة) محجوزة من آخر كتلة.
      lastPageReserve: measure(builder.footer()) + _blockSpacing,
    );
    return <List<String>>[
      for (final page in result.pages)
        page.blockIds.where((id) => id != PaperMetrics.headerBlockId).toList(growable: false),
    ];
  }

  /// نسبة تحويل بكسل اللوحة إلى نقاط الـ PDF (نفس النسبة في كل المحرك).
  static double get _canvasScale => PaperMetrics.pointsPerPixel;

  /// موضع عنصر عائم جاهز للرسم في الـ PDF: عناصر الصفحة بإحداثياتها المطلقة،
  /// والعناصر المرتبطة بسؤال بإحداثيات نسبية لأعلى سؤالها (فتُرسم داخله
  /// وتنتقل معه بين الصفحات).
  ///
  /// [`edge`] = المسافة من حافة القراءة (يمين الورقة في RTL ويسارها في LTR)،
  /// والمستدعي يضعها في `right` أو `left` بحسب اتجاه الورقة — فلا يُحدَّد
  /// الاتجاهان معاً فيتمدّد العنصر بعرض الورقة.
  static List<({FloatingElement element, double edge, double top})>
      _pageAttachmentPlacements(
    ExamDocument document,
    List<String> questionIds, {
    required int pageIndex,
    required int pageCount,
    required Map<String, double> questionTops,
  }) {
    final marginPt = _marginForDocument(document);
    final placements =
        <({FloatingElement element, double edge, double top})>[];
    for (final element in _pageAttachments(
      document,
      questionIds,
      pageIndex: pageIndex,
      pageCount: pageCount,
      questionTops: questionTops,
    )) {
      final owner = element.ownerQuestionId;
      final ownerTop = owner == null ? null : questionTops[owner];
      // عنصر حر: إحداثياته مطلقة على الورقة (من حافتها). عنصر مرتبط بسؤال:
      // إحداثياته من حافة محتوى سؤاله، وأعلى سؤال المالك مرجعه الرأسي.
      final topPt = ownerTop == null
          ? element.dy * _canvasScale
          : ownerTop + element.dy * _canvasScale;
      final edge = ownerTop == null
          ? element.dx * _canvasScale
          : marginPt + element.dx * _canvasScale;
      placements.add((
        element: element,
        edge: edge,
        top: topPt,
      ));
    }
    return placements;
  }

  /// هامش الورقة بالنقاط لورقة [document] (نفس هامش محرك الطباعة).
  static double _marginForDocument(ExamDocument document) =>
      PaperMetrics.pt(ExamCanvasGeometry.marginFor(document.settings.marginMm));

  /// عناصر الصفحة: الحرة بإحداثياتها على الورقة، والمرتبطة بسؤال **لصفحة
  /// مالكها وحدها** (فلا تُرسم مرتين ولا تفوت صفحة سؤالها).
  static List<FloatingElement> _pageAttachments(
    ExamDocument document,
    List<String> questionIds, {
    required int pageIndex,
    required int pageCount,
    required Map<String, double> questionTops,
  }) {
    final elements = <FloatingElement>[];
    final seenIds = <String>{};
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final lastPage = pageCount - 1;
    for (final element in document.floatingElements) {
      final owner = element.ownerQuestionId;
      if (owner != null) {
        // عنصر مرتبط بسؤال: يُرسم في صفحة سؤاله نفسها.
        if (questionTops.containsKey(owner) && seenIds.add(element.id)) {
          elements.add(element);
        }
        continue;
      }
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

}
