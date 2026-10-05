import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../docx/omml_from_equation.dart';
import '../layout/adapters/legacy_docx_adapter.dart';
import '../layout/blueprint/exam_blueprint.dart';
import '../layout/canonical/canonical_layout_service.dart';
import '../layout/canonical/flutter_text_metrics.dart';
import '../layout/canonical/layout_document.dart';
import '../layout/canonical/layout_units.dart';
import '../layout/document_ir.dart';
import '../layout/document_direction.dart';
import '../layout/pagination_engine.dart';
import '../layout/semantic/inline_nodes.dart';
import '../layout/paper_metrics.dart';
import '../layout/visual/visual_metrics.dart';
import '../layout/visual/visual_content.dart';
import '../layout/visual/visual_style.dart';
import '../layout/visual/visual_typography.dart';
import '../models/exam_canvas_geometry.dart';
import '../models/exam_document.dart';
import '../models/equation_model.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_font.dart';
import '../models/paper_text_style.dart';
import 'export_file_service.dart';
import 'math_snapshot_renderer.dart' show MathRaster;
import 'page_frame_store.dart';

/// مخصّص تحويل شكل متجه إلى صورة نقطية (لأن Word لا يقبل SVG الداخلي
/// بنفس البساطة؛ يُمرَّر من الواجهة حيث يتوفر مسجّل الرسم).
///
/// يعيد بايتات PNG/JPG أو `null` عند التعذّر (يُكتب عنصر نصي بديل).
typedef ShapeRasterizer = Future<Uint8List?> Function(
  FloatingElement element,
  double widthPx,
  double heightPx,
);

/// جريان نصّي واحد داخل فقرة Word: نصّه وتنسيقه الخاص.
///
/// الفرق الجوهري عن تمرير نص واحد: أجزاء العنصر (رقم السؤال ← منطوقه ←
/// درجته، أو تسمية النقطة ← نصها ← قوساها ← درجتها، أو تسمية الخيار ←
/// نصه) تُكتب **جريانات مستقلة**، فيستطيع Word أن يعطي كلاً منها تنسيقه
/// (التسمية غامقة مثلاً) — وهو ما لا يمكن أن يحدث حين تُدمج الأجزاء في
/// نص واحد. هذا هو مقابِل «العناصر المتعددة» في المعاينة وPDF.
class DocxRunSpec {
  const DocxRunSpec(
    this.text, {
    this.bold,
    this.italic,
    this.underline,
    this.size,
    this.color,
    this.font,
    this.rtl,
    this.visualRun,
  });

  final String text;

  /// `null` = يتبع تنسيق الفقرة (الغامق/الميل/التسطير/الحجم/اللون/الخط).
  final bool? bold;
  final bool? italic;
  final bool? underline;

  /// الحجم بأنصاف النقاط (`w:sz`)؛ `null` = حجم الفقرة.
  final int? size;

  /// لون hex بلا `#`؛ `null` = لون الفقرة.
  final String? color;

  final String? font;

  /// Explicit semantic direction. `null` means infer from strong script.
  final bool? rtl;

  /// Existing semantic visual run, when projected directly from DocumentIR.
  final VisualRun? visualRun;
}

/// مخصّص تحويل صيغة LaTeX إلى صورة نقطية (يُمرَّر من الواجهة حيث يتوفر
/// مسجّل الرسم؛ انظر `MathImageRenderer`).
///
/// يعيد [MathRaster] أو `null` عند التعذّر (فيكتب المصدر نص الصيغة كما هو).
typedef MathRasterizer = Future<MathRaster?> Function(
  String latex,
  double fontSizePt,
);

/// Optional observer for meaningful stages in an editable DOCX build.
typedef DocxBuildProgress = void Function(String stage);

/// صورة مضمّنة في حزمة docx (أصلية أو مرسومة من شكل/معادلة).
class _EmbeddedImage {
  _EmbeddedImage({
    required this.data,
    required this.extension,
    required this.contentType,
    required this.relationId,
    required this.widthEmu,
    required this.heightEmu,
  });

  final Uint8List data;
  final String extension;
  final String contentType;
  final String relationId;
  final int widthEmu;
  final int heightEmu;
}

/// تصدير ورقة الأسئلة ([ExamDocument]) إلى ملف Word قابل للتحرير.
///
/// يعرض نفس مخطط الورقة ([ExamBlueprint]) الذي تعرضه المعاينة وPDF:
/// ترويسة الأعمدة الثلاثة، الأسئلة (رقم ← منطوق ← درجة ← نص ← نقاط ← فروع)،
/// وتذييل (عبارة ختامية + توقيع/توقيعان) مثبّت أسفل آخر صفحة، وإطار الصفحة
/// (صورة PNG خلف النص أو حدود متجهة) — بلا ترقيم صفحات إطلاقاً.
/// والأشكال تُرسم صوراً عبر [ShapeRasterizer]، وصيغ LaTeX (`$...$` و`$$...$$`)
/// تُصدَّر **معادلات Word أصلية قابلة للتحرير** (OMML — [OmmlFromEquation])
/// من `EquationModel` نفسه، فلا تظهر أكواداً خامة ولا تُفلطح صوراً؛ ولا
/// تُرسم عبر [MathRasterizer] إلا صيغةٌ تعذّر تمثيلها بُنيةً، فتُرسَم
/// بمحرك المعاينة نفسه (`MathImageRenderer`) حفظاً لشكلها.
class DocxDocumentExportService {
  const DocxDocumentExportService._();

  /// أقصى عرض لصورة داخل النص بالنقاط (يقارب عرض محتوى A4).
  static const double _maxImageWidthPt = 430;

  static Future<File> exportDocumentToDocx({
    required ExamDocument document,
    String? fileName,
    Directory? outputDirectory,
    ShapeRasterizer? shapeRasterizer,
    MathRasterizer? mathRasterizer,
    /// Legacy compatibility parameter; editable Word pagination ignores it.
    List<List<String>>? pageAssignments,
    PaginationInput? legacyPaginationInput,
    Uint8List? frameImage,
    DocxBuildProgress? onProgress,
  }) async {
    final bytes = await buildDocumentDocxBytes(
      document: document,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      pageAssignments: pageAssignments,
      legacyPaginationInput: legacyPaginationInput,
      frameImage: frameImage,
      onProgress: onProgress,
    );
    return ExportFileService.writeExportFile(
      baseName: fileName ?? '${document.name}_ورقة_الامتحان',
      extension: 'docx',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  static Future<Uint8List> buildDocumentDocxBytes({
    required ExamDocument document,
    ShapeRasterizer? shapeRasterizer,
    MathRasterizer? mathRasterizer,
    /// Legacy API parameter retained for callers; it is ignored. The editable
    /// document always obtains page ownership from PaginationEngine.
    List<List<String>>? pageAssignments,
    PaginationInput? legacyPaginationInput,
    Uint8List? frameImage,
    DocxBuildProgress? onProgress,
  }) async {
    // صورة الإطار تُقرأ من مسارها عند عدم تمريرها (التصدير من المعاينة).
    final frame = document.settings.pageBorder
        ? (frameImage ?? await PageFrameStore.read(document.settings.frameImagePath))
        : null;
    final builder = _DocxBuilder(
      document: document,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      legacyPaginationInput: legacyPaginationInput,
      frameImage: frame,
      onProgress: onProgress,
    );
    onProgress?.call('builder created');
    await builder.build();
    onProgress?.call('builder completed');
    final archive = Archive();
    _addTextFile(archive, '[Content_Types].xml', builder.contentTypesXml);
    _addTextFile(archive, '_rels/.rels', _globalRelationshipsXml);
    _addTextFile(archive, 'word/_rels/document.xml.rels', builder.documentRelationshipsXml);
    _addTextFile(archive, 'word/styles.xml', _stylesXml(document));
    _addTextFile(archive, 'word/document.xml', builder.documentXml);
    if (builder.headerXml != null) {
      // طبقة الإطار: صورة PNG مثبّتة خلف النص في ترويسة الصفحة فتتكرر
      // على كل صفحة.
      _addTextFile(archive, 'word/header1.xml', builder.headerXml!);
      _addTextFile(archive, 'word/_rels/header1.xml.rels', builder.headerRelationshipsXml!);
      archive.addFile(
        ArchiveFile(
          'word/media/frame.png',
          builder.frameImage!.length,
          builder.frameImage!,
        ),
      );
    }
    for (var i = 0; i < builder.images.length; i++) {
      final image = builder.images[i];
      archive.addFile(
        ArchiveFile(
          'word/media/image${i + 1}.${image.extension}',
          image.data.length,
          image.data,
        ),
      );
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('فشل ضغط ملف Word.');
    }
    return Uint8List.fromList(zipBytes);
  }

  /// Resolve the editable Word pagination plan without consulting canonical
  /// PDF page assignments. The returned measured blocks are owned by this
  /// DOCX/legacy adapter path and consumed by PaginationEngine.
  static Future<PaginationInput> resolveEditablePaginationInput({
    required ExamDocument document,
    DocumentIR? sourceIr,
    LayoutDocument? measurementLayout,
  }) async {
    final builder = _DocxBuilder(
      document: document,
      sourceIr: sourceIr,
      measurementLayout: measurementLayout,
      shapeRasterizer: null,
      mathRasterizer: null,
      legacyPaginationInput: null,
      frameImage: null,
    );
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final expectedIds = builder.blueprint.questions
        .where((question) => question.isPrintable(
              ignoredAttachmentIds: globalElementIds,
            ))
        .map((question) => question.model.id)
        .toSet();
    return builder._paginationInputFor(expectedIds);
  }

  static Future<void> shareDocxFile(File file, {String? subject}) {
    return ExportFileService.shareExportFile(
      file,
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      subject: subject ?? 'تصدير ورقة الأسئلة بصيغة Word',
    );
  }

  static void _addTextFile(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static const String _globalRelationshipsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static String _stylesXml(ExamDocument document) {
    final font = _fontName(document.settings.defaultFont);
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>
        <w:sz w:val="22"/>
        <!-- مقاس النص العربي (Complex Script): بدونه يتجاهل Word حجم المجموعة
             نفسه ويستعمل مقاس المحرك الافتراضي، فلا يتغير حجم الخط العربي
             في الملف مهما ضبطه المدرس في المعاينة. -->
        <w:szCs w:val="22"/>
        <w:lang w:val="ar-SA" w:bidi="ar-SA"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        ${document.layout.isLtr ? '' : '<w:bidi/>'}
        <w:jc w:val="${document.layout.isLtr ? 'left' : 'right'}"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
</w:styles>''';
  }

  /// لون Word: ست خانات سداسية بلا قناة ألفا.
  static String _hexColor(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static String _fontName(PaperFont font) {
    switch (font) {
      case PaperFont.naskh:
        return 'Noto Naskh Arabic';
      case PaperFont.amiri:
        return 'Amiri';
      case PaperFont.tajawal:
        return 'Tajawal';
      case PaperFont.rakkas:
        return 'Rakkas';
    }
  }
}

/// خصائص جريان Word **كقيم** لا كنص XML: تُبنى مرّة من الفقرة، ثم يُدمج
/// فيها تنسيق المقطع المعلن في العقد ([VisualRunStyle])، ثم تُولَّد مرّة
/// واحدة. فلا جراحة نصية على XML ولا خاصية تُكتب مرتين بقيمتين متضادتين.
class _RunProperties {
  const _RunProperties({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.highlight = false,
    this.color,
    required this.size,
    required this.font,
    required this.rtl,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool highlight;
  final String? color;

  /// الحجم بأنصاف النقاط كما يكتبه Word.
  final int size;

  /// اسم عائلة الخط كما يعرفه Word.
  final String font;

  final bool rtl;

  _RunProperties withRtl(bool value) => _RunProperties(
        bold: bold,
        italic: italic,
        underline: underline,
        highlight: highlight,
        color: color,
        size: size,
        font: font,
        rtl: value,
      );

  /// يدمج تنسيق مقطع من العقد فوق خصائص الفقرة: المعلَن يستبدل الموروث،
  /// و`null` يعني «اتبع الفقرة».
  _RunProperties merge(VisualRunStyle? style) {
    if (style == null || style.isEmpty) {
      return this;
    }
    final fontSizePt = style.fontSizePt;
    return _RunProperties(
      bold: style.bold ?? bold,
      italic: style.italic ?? italic,
      underline: style.underline ?? underline,
      highlight: highlight,
      color: style.colorArgb == null
          ? color
          : DocxDocumentExportService._hexColor(style.colorArgb!),
      size: fontSizePt == null ? size : (fontSizePt * 2).round(),
      font: style.font == null
          ? font
          : DocxDocumentExportService._fontName(style.font!),
      rtl: rtl,
    );
  }

  String toXml() => _DocxBuilder._runPropertiesXml(
        bold: bold,
        italic: italic,
        underline: underline,
        highlight: highlight,
        color: color,
        size: size,
        font: font,
        rtl: rtl,
      );
}

/// بانِي مستند Word الداخلي (يجمع الصور أثناء بناء XML).
class _DocxBuilder {
  factory _DocxBuilder({
    required ExamDocument document,
    DocumentIR? sourceIr,
    LayoutDocument? measurementLayout,
    required ShapeRasterizer? shapeRasterizer,
    required MathRasterizer? mathRasterizer,
    required PaginationInput? legacyPaginationInput,
    required Uint8List? frameImage,
    DocxBuildProgress? onProgress,
  }) {
    if (measurementLayout != null && sourceIr == null) {
      throw ArgumentError.value(
        measurementLayout,
        'measurementLayout',
        'A measured layout must be paired with its DocumentIR source.',
      );
    }
    final documentIr = sourceIr ??
        DocumentIR.fromBlueprint(
          blueprint: ExamBlueprint.from(document),
          document: document,
        );
    if (measurementLayout != null &&
        !identical(measurementLayout.source, documentIr)) {
      throw ArgumentError.value(
        measurementLayout,
        'measurementLayout',
        'The measured layout must belong to the supplied DocumentIR instance.',
      );
    }
    return _DocxBuilder._(
      document: document,
      documentIr: documentIr,
      measurementLayout: measurementLayout,
      blueprint: LegacyDocxAdapter.adapt(
        documentIr: documentIr,
        sourceDocument: document,
      ),
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      legacyPaginationInput: legacyPaginationInput,
      frameImage: frameImage,
      onProgress: onProgress,
    );
  }

  _DocxBuilder._({
    required this.document,
    required this.documentIr,
    required this.measurementLayout,
    required this.blueprint,
    required this.shapeRasterizer,
    required this.mathRasterizer,
    required this.legacyPaginationInput,
    required this.frameImage,
    required this.onProgress,
  });

  final ExamDocument document;
  final DocumentIR documentIr;
  final LayoutDocument? measurementLayout;
  final ExamBlueprint blueprint;
  final ShapeRasterizer? shapeRasterizer;
  final MathRasterizer? mathRasterizer;
  final PaginationInput? legacyPaginationInput;
  final DocxBuildProgress? onProgress;

  /// صورة PNG الإطار (`null` = إطار متجه عند تفعيل «إطار حول الصفحة»).
  final Uint8List? frameImage;

  final List<_EmbeddedImage> images = <_EmbeddedImage>[];
  int _drawingId = 1;

  FloatingElement _legacyFloatingElement(FloatingElement source) =>
      LegacyDocxAdapter.adaptFloatingElement(
        documentIr: documentIr,
        sourceElement: source,
      );

  void _reportProgress(String stage) => onProgress?.call(stage);

  /// صيغ LaTeX المكتشفة في النصوص عند كتابة الفقرات، بترتيب ظهورها — تُرسم
  /// وتُستبدل علاماتها بعد اكتمال النص (انظر [_resolveMath]).
  final List<_MathPlaceholder> _mathQueue = <_MathPlaceholder>[];

  late final String documentXml;
  late final String contentTypesXml;
  late final String documentRelationshipsXml;

  /// ترويسة الصفحة الحاملة لصورة الإطار (`null` = لا صورة إطار).
  String? headerXml;
  String? headerRelationshipsXml;

  static const String _headerRelationId = 'rIdFrameHeader';
  static const String _frameImageRelationId = 'rIdFrameImage';

  /// ارتفاع/عرض A4 بالتويبس (الإطار يغطي الصفحة كاملة).
  static const int _pageWidthTwips = 11906;
  static const int _pageHeightTwips = 16838;

  Future<void> build() async {
    _reportProgress('fonts:started');
    await FlutterTextMetrics.ensureFontsLoaded();
    _reportProgress('fonts:completed');
    final body = StringBuffer();
    body.write(_buildHeaderTable());
    final headerSpacingAfter = (PaperMetrics.pt(PaperMetrics.blockSpacingPx) * 20).round();
    body.write('<w:p><w:pPr><w:spacing w:after="$headerSpacingAfter"/></w:pPr></w:p>');
    final questionPages = await _resolvedQuestionPages();
    _reportProgress('pagination:completed pages=${questionPages.length}');
    for (var pageIndex = 0; pageIndex < questionPages.length; pageIndex++) {
      if (pageIndex > 0) {
        _writePageBreak(body);
      }
      _reportProgress('page $pageIndex floating-elements:started');
      await _buildFloatingElementsForPage(
        body,
        pageIndex,
        pageCount: questionPages.length,
      );
      _reportProgress('page $pageIndex floating-elements:completed');
      final pageQuestions = questionPages[pageIndex];
      for (var index = 0; index < pageQuestions.length; index++) {
        final question = pageQuestions[index];
        _reportProgress('question ${question.model.id}:started');
        await _buildQuestion(body, question);
        _reportProgress('question ${question.model.id}:completed');
        if (index < pageQuestions.length - 1) {
          _writeQuestionSpacing(body, question.model.spacingAfter);
        }
      }
    }
    // التذييل بعد آخر سؤال مباشرةً، مثبّتاً أسفل آخر صفحة.
    _reportProgress('footer:started');
    _buildFooterTable(body);
    _reportProgress('footer:completed');

    // بعد اكتمال كل النصوص: تُرسم صيغ LaTeX ($...$ و$$...$$) وتُستبدل
    // علاماتها برسوم مضمّنة — قبل بناء قوائم الصور في الحزمة.
    _reportProgress('math-resolution:started count=${_mathQueue.length}');
    final resolvedBody = await _resolveMath(body.toString());
    _reportProgress('math-resolution:completed images=${images.length}');

    final marginTwips = (document.settings.marginMm / 25.4 * 1440).round();
    if (document.settings.pageBorder && frameImage != null && frameImage!.isNotEmpty) {
      headerXml = _buildFrameHeader();
      headerRelationshipsXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="$_frameImageRelationId" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/frame.png"/>'
          '</Relationships>';
    }
    final vectorBorder = document.settings.pageBorder && headerXml == null;
    // حدود متجهة تتبع الهامش: تُرسم في منتصف المسافة بين حافة الورقة والنص.
    final borderSpace = (document.settings.marginMm * 0.5 * 72 / 25.4).round().clamp(1, 31);
    String side(String name) =>
        '<w:$name w:val="single" w:sz="12" w:space="$borderSpace" w:color="000000"/>';
    documentXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        '${OmmlFromEquation.mathNamespaceDeclaration} '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>'
        '$resolvedBody'
        '<w:sectPr>'
        '${headerXml == null ? '' : '<w:headerReference r:id="$_headerRelationId" w:type="default"/>'}'
        '<w:pgSz w:w="$_pageWidthTwips" w:h="$_pageHeightTwips"/>'
        '<w:pgMar w:top="$marginTwips" w:right="$marginTwips" w:bottom="$marginTwips" '
        'w:left="$marginTwips" w:header="0" w:footer="0" w:gutter="0"/>'
        '${vectorBorder ? '<w:pgBorders w:offsetFrom="page">${side('top')}${side('left')}${side('bottom')}${side('right')}</w:pgBorders>' : ''}'
        '${document.layout.isLtr ? '' : '<w:bidi/>'}'
        '</w:sectPr>'
        '</w:body>'
        '</w:document>';

    final overrides = StringBuffer(
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>''',
    );
    for (var i = 0; i < images.length; i++) {
      overrides.write(
        '\n  <Override PartName="/word/media/image${i + 1}.${images[i].extension}" ContentType="${images[i].contentType}"/>',
      );
    }
    if (headerXml != null) {
      overrides.write(
        '\n  <Override PartName="/word/media/frame.png" ContentType="image/png"/>'
        '\n  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>',
      );
    }
    overrides.write('''
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''');
    contentTypesXml = overrides.toString();

    final rels = StringBuffer(
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>''',
    );
    for (var i = 0; i < images.length; i++) {
      rels.write(
        '\n  <Relationship Id="${images[i].relationId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image${i + 1}.${images[i].extension}"/>',
      );
    }
    if (headerXml != null) {
      rels.write(
        '\n  <Relationship Id="$_headerRelationId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>',
      );
    }
    rels.write('\n</Relationships>');
    documentRelationshipsXml = rels.toString();
  }

  /// ترويسة الصفحة الحاملة لصورة الإطار: صورة PNG بحجم A4 مثبّتة على الصفحة
  /// (0،0) **خلف النص**، فتتكرر خلف كل صفحة ولا تزاحم الأسئلة.
  String _buildFrameHeader() {
    const emuWidth = 7560310;
    const emuHeight = 10692130;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        '${OmmlFromEquation.mathNamespaceDeclaration} '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr>'
        '<w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" '
        'simplePos="0" relativeHeight="0" behindDoc="1" locked="1" '
        'layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionV>'
        '<wp:extent cx="$emuWidth" cy="$emuHeight"/><wp:wrapNone/>'
        '<wp:docPr id="9000" name="Page frame"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="0"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="9000" name="Page frame"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$_frameImageRelationId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$emuWidth" cy="$emuHeight"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>'
        '</w:hdr>';
  }

  Future<List<List<QuestionBlueprint>>> _resolvedQuestionPages() async {
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final printableQuestions = blueprint.questions
        .where((question) => question.isPrintable(
              ignoredAttachmentIds: globalElementIds,
            ))
        .toList(growable: false);
    final questionsById = <String, QuestionBlueprint>{
      for (final question in printableQuestions) question.model.id: question,
    };
    final expectedIds = questionsById.keys.toSet();

    // Editable Word page ownership is always recomputed by PaginationEngine;
    // PDF page assignments never enter this editable export path.
    final paginationInput = await _paginationInputFor(expectedIds);
    final pageIds = _questionPageIds(paginationInput.paginate(), expectedIds);

    return pageIds
        .map((page) => page.map((id) => questionsById[id]!).toList(growable: false))
        .toList(growable: false);
  }

  Future<PaginationInput> _paginationInputFor(Set<String> expectedIds) async {
    final supplied = legacyPaginationInput;
    if (supplied != null) {
      final sourceQuestionIds =
          blueprint.questions.map((question) => question.model.id).toSet();
      final allowedIds = <String>{
        ...sourceQuestionIds,
        PaperMetrics.headerBlockId,
      };
      final hasUnknownBlock =
          supplied.blocks.any((block) => !allowedIds.contains(block.id));
      final filtered = supplied.retainBlockIds(<String>{
        ...expectedIds,
        PaperMetrics.headerBlockId,
      });
      final expectedBlockIds = <String>[
        PaperMetrics.headerBlockId,
        for (final question in blueprint.questions)
          if (expectedIds.contains(question.model.id)) question.model.id,
      ];
      final actualBlockIds =
          filtered.blocks.map((block) => block.id).toList(growable: false);
      if (!hasUnknownBlock &&
          _sameIds(actualBlockIds, expectedBlockIds) &&
          _hasValidPaginationGeometry(filtered)) {
        return filtered;
      }
    }
    return _fallbackPaginationInput(expectedIds);
  }

  bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _hasValidPaginationGeometry(PaginationInput input) {
    if (!input.pageHeight.isFinite ||
        input.pageHeight <= 0 ||
        (input.firstPageHeight != null &&
            (!input.firstPageHeight!.isFinite || input.firstPageHeight! <= 0)) ||
        !input.spacing.isFinite ||
        input.spacing < 0 ||
        !input.lastPageReserve.isFinite ||
        input.lastPageReserve < 0 ||
        !input.footerMeasured) {
      return false;
    }
    return input.blocks.every(
      (block) =>
          block.id.isNotEmpty &&
          block.height.isFinite &&
          block.height >= 0 &&
          block.spacingAfter.isFinite &&
          block.spacingAfter >= 0,
    );
  }

  /// Direct/service DOCX callers may not have the editor's measured widget
  /// heights. Measure the shared semantic question blocks from the canonical
  /// source geometry (or resolve it once on A4), summing any page fragments by
  /// question ID. Fresh PageBlocks are then handed to PaginationEngine, which
  /// decides editable Word page ownership independently of PDF page indices.
  Future<PaginationInput> _fallbackPaginationInput(
    Set<String> expectedIds,
  ) async {
    var layout = measurementLayout ??
        await CanonicalLayoutService.resolve(
          document: document,
          sourceIr: documentIr,
        );
    if (!identical(layout.source, documentIr)) {
      throw const ExportException(
        'تعذر تخطيط ملف Word: هندسة القياس لا تخص DocumentIR الحالي.',
      );
    }
    bool hasSplitQuestion(LayoutDocument measured) => measured.pages
        .expand((page) => page.blocks)
        .any((block) =>
            block.kind == LayoutBlockKind.question && block.split.isSplit);

    if (hasSplitQuestion(layout)) {
      // A4 geometry can fragment an oversized question across pages. Re-measure
      // on one dynamically tall page so the gaps at canonical page boundaries
      // remain part of its full DOCX block height. This canvas is only a metric
      // pass; PaginationEngine still calculates the editable page assignments.
      layout = await CanonicalLayoutService.resolve(
        document: document,
        sourceIr: documentIr,
        pageSize: LayoutSize(
          width: layout.pageSize.width,
          height: layout.pageSize.height * (layout.pageCount + 2),
        ),
      );
      if (!identical(layout.source, documentIr) || hasSplitQuestion(layout)) {
        throw const ExportException(
          'تعذر قياس كتل Word كاملة من DocumentIR قبل إعادة تقسيم PaginationEngine.',
        );
      }
    }
    final questionHeights = <String, double>{};
    for (final page in layout.pages) {
      for (final block in page.blocks) {
        if (block.kind != LayoutBlockKind.question ||
            !expectedIds.contains(block.semanticNodeId)) {
          continue;
        }
        questionHeights.update(
          block.semanticNodeId,
          (height) => height + LayoutUnits.ptToPx(block.rect.height),
          ifAbsent: () => LayoutUnits.ptToPx(block.rect.height),
        );
      }
    }

    final unmeasuredIds = expectedIds
        .where((id) => !questionHeights.containsKey(id))
        .toList(growable: false);
    if (unmeasuredIds.isNotEmpty) {
      throw ExportException(
        'تعذر قياس كتل الأسئلة قبل تخطيط ملف Word: ${unmeasuredIds.join(', ')}',
      );
    }

    final headerHeight = layout.headerBlock?.rect.height ?? 0.0;
    final footerHeight = layout.footerBlock?.rect.height ?? 0.0;
    return PaginationInput(
      blocks: <PageBlock>[
        PageBlock(
          id: PaperMetrics.headerBlockId,
          height: LayoutUnits.ptToPx(headerHeight),
        ),
        for (final question in blueprint.questions)
          if (expectedIds.contains(question.model.id))
            PageBlock(
              id: question.model.id,
              height: questionHeights[question.model.id] ?? 0,
              spacingAfter: question.model.spacingAfter,
            ),
      ],
      pageHeight: PaperMetrics.pageContentHeightFor(document.settings.marginMm),
      spacing: PaperMetrics.blockSpacingPx,
      lastPageReserve: footerHeight <= 0
          ? 0
          : LayoutUnits.ptToPx(footerHeight) + PaperMetrics.blockSpacingPx,
      footerMeasured: true,
    );
  }

  List<List<String>> _questionPageIds(
    PaginationResult result,
    Set<String> expectedIds,
  ) {
    final pages = <List<String>>[
      for (final page in result.pages)
        page.blockIds
            .where(expectedIds.contains)
            .toList(growable: false),
    ].where((page) => page.isNotEmpty).toList(growable: false);
    return pages.isEmpty ? <List<String>>[<String>[]] : pages;
  }

  void _writePageBreak(StringBuffer body) {
    body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }

  void _writeQuestionSpacing(StringBuffer body, double spacingPx) {
    final spacing = spacingPx.clamp(0.0, 200.0).toDouble();
    final afterTwips = (PaperMetrics.pt(spacing) * 20).round();
    if (afterTwips <= 0) return;
    body.write(
      '<w:p><w:pPr><w:spacing w:before="0" w:after="$afterTwips" '
      'w:line="1" w:lineRule="exact"/></w:pPr></w:p>',
    );
  }

  Future<void> _buildFloatingElementsForPage(
    StringBuffer body,
    int pageIndex, {
    required int pageCount,
  }) async {
    if (pageCount <= 0) {
      return;
    }
    final seenIds = <String>{};
    final formulas = <FloatingElement>[];
    for (final element in document.floatingElements) {
      // العناصر المرتبطة بسؤال تُصدَّر مع فقرات سؤالها لا في طبقة الصفحة،
      // فتبقى معه عند تحريكه في Word أيضاً.
      if (element.isQuestionOwned) {
        continue;
      }
      final assignedPage = element.pageIndex.clamp(0, pageCount - 1).toInt();
      if (assignedPage != pageIndex || !seenIds.add(element.id)) {
        continue;
      }
      if (element.isFormula) {
        // المعادلة لا تُعوَّم أبداً: فقرة في تدفق النص بترتيبها البصري،
        // فلا تداخل ولا تجاوز ولا ترتيب متغير داخل Word.
        formulas.add(element);
        continue;
      }
      await _buildFloatingElement(
        body,
        _legacyFloatingElement(element),
        pageAnchored: true,
      );
    }
    for (final element in _formulaFlowOrder(formulas)) {
      await _buildFormulaElement(body, _legacyFloatingElement(element));
    }
  }

  /// ترتيب المعادلات كما يراها المدرس على اللوحة: من الأعلى إلى الأسفل ثم
  /// من اليمين إلى اليسار — ترتيب ثابت داخل الملف لا يعتمد على ترتيب
  /// الإضافة، فتخرج الصيغ ١ ثم ٢ ثم ٣ تحت سؤالها كما في المعاينة.
  static List<FloatingElement> _formulaFlowOrder(
    Iterable<FloatingElement> elements,
  ) {
    return elements.toList()..sort((a, b) {
        final byRow = a.dy.compareTo(b.dy);
        return byRow != 0 ? byRow : a.dx.compareTo(b.dx);
      });
  }

  /// يُصدّر العناصر المرتبطة بالسؤال [questionId] داخل فقرات السؤال نفسه —
  /// فيبقى كل عنصر مع سؤاله. المعادلات تُكتب **فقرات في التدفق** أسفل
  /// السؤال بترتيبها البصري (لا تعويم ولا تداخل)، وبقية العناصر تحافظ على
  /// مراسيها النسبية للفقرة.
  Future<void> _buildOwnedElements(StringBuffer body, String questionId) async {
    final formulas = <FloatingElement>[];
    for (final element in document.floatingElements) {
      if (element.ownerQuestionId != questionId) {
        continue;
      }
      if (element.isFormula) {
        formulas.add(element);
        continue;
      }
      await _buildFloatingElement(
        body,
        _legacyFloatingElement(element),
        pageAnchored: false,
      );
    }
    for (final element in _formulaFlowOrder(formulas)) {
      await _buildFormulaElement(body, _legacyFloatingElement(element));
    }
  }

  /// يصدّر عنصراً عائماً واحداً: مربع نص / صورة / شكل.
  ///
  /// المعادلة لا تُعوَّم أبداً: حتى لو وصلت إلى هنا تُصدَّر فقرةً في تدفق
  /// النص عبر [_buildFormulaElement] (فلا تداخل ولا خروج عن الترتيب).
  ///
  /// [pageAnchored]: مرساة بترتيب الصفحة (عنصر حر) أو نسبةً لفقرة السؤال
  /// (عنصر مرتبط بسؤال).
  Future<void> _buildFloatingElement(
    StringBuffer body,
    FloatingElement element, {
    required bool pageAnchored,
  }) async {
    if (element.isTextBox) {
      _buildTextBox(
        body,
        element,
        floatingOnPage: true,
        pageAnchored: pageAnchored,
      );
      return;
    }
    if (element.isFormula) {
      await _buildFormulaElement(body, element);
      return;
    }
    if (element.isImage) {
      final bytes = element.bytes;
      if (bytes == null || bytes.isEmpty) {
        return;
      }
      _writeAnchoredImageParagraph(
        body,
        Uint8List.fromList(bytes),
        PaperMetrics.pt(element.width),
        PaperMetrics.pt(element.height),
        dx: element.dx,
        dy: element.dy,
        rotationDegrees: element.rotationDegrees,
        pageAnchored: pageAnchored,
      );
      return;
    }

    Uint8List? raster;
    if (shapeRasterizer != null) {
      try {
        raster = await shapeRasterizer!(element, element.width, element.height);
      } catch (_) {
        raster = null;
      }
    }
    if (raster != null && raster.isNotEmpty) {
      _writeAnchoredImageParagraph(
        body,
        raster,
        PaperMetrics.pt(element.width),
        PaperMetrics.pt(element.height),
        dx: element.dx,
        dy: element.dy,
        rotationDegrees: element.rotationDegrees,
        pageAnchored: pageAnchored,
      );
      return;
    }
    _buildTextBox(
      body,
      element,
      floatingOnPage: true,
      pageAnchored: pageAnchored,
      textOverride: '[شكل: ${element.shape?.arabicLabel ?? 'شكل'}]',
    );
  }

  void _writeAnchoredImageParagraph(
    StringBuffer body,
    Uint8List bytes,
    double widthPt,
    double heightPt, {
    required double dx,
    required double dy,
    required double rotationDegrees,
    bool pageAnchored = true,
  }) {
    if (bytes.isEmpty || widthPt <= 0 || heightPt <= 0) {
      return;
    }
    body.write(
      '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}<w:spacing w:before="0" w:after="0" '
      'w:line="1" w:lineRule="exact"/></w:pPr>'
      '<w:r>${_positionedDrawingXml(bytes, widthPt, heightPt, dx: dx, dy: dy, rotationDegrees: rotationDegrees, pageAnchored: pageAnchored)}</w:r></w:p>',
    );
  }

  String _positionedDrawingXml(
    Uint8List bytes,
    double widthPt,
    double heightPt, {
    required double dx,
    required double dy,
    required double rotationDegrees,
    bool pageAnchored = true,
  }) {
    var width = widthPt;
    var height = heightPt;
    if (width > DocxDocumentExportService._maxImageWidthPt) {
      final scale = DocxDocumentExportService._maxImageWidthPt / width;
      width *= scale;
      height *= scale;
    }
    final widthEmu = (width / 72 * 914400).round();
    final heightEmu = (height / 72 * 914400).round();
    final widthPx = PaperMetrics.px(width);
    // في RTL يقاس `dx` من حافة القراءة (اليمين): إما حافة الصفحة (عنصر حر)
    // أو حافة عمود نص السؤال (عنصر مرتبط بسؤال).
    final referenceWidth = pageAnchored
        ? ExamCanvasGeometry.width
        : ExamCanvasGeometry.contentWidthFor(document.settings.marginMm);
    final physicalLeftPx = document.layout.isLtr
        ? dx
        : referenceWidth - dx - widthPx;
    final xEmu = (PaperMetrics.pt(physicalLeftPx) * 12700).round();
    final yEmu = (PaperMetrics.pt(dy) * 12700).round();
    final rotation = (rotationDegrees * 60000).round();
    final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final relationId = 'rIdImg${images.length + 2}';
    images.add(
      _EmbeddedImage(
        data: bytes,
        extension: isJpeg ? 'jpeg' : 'png',
        contentType: isJpeg ? 'image/jpeg' : 'image/png',
        relationId: relationId,
        widthEmu: widthEmu,
        heightEmu: heightEmu,
      ),
    );
    final id = _drawingId++;
    // عنصر السؤال يُثبَّت نسبةً إلى فقرته (column/paragraph) فيبقى مع سؤاله،
    // والعنصر الحر يُثبَّت على الصفحة كما كان.
    final horizontalFrom = pageAnchored ? 'page' : 'column';
    final verticalFrom = pageAnchored ? 'page' : 'paragraph';
    return '<w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" '
        'simplePos="0" relativeHeight="$id" behindDoc="0" locked="0" '
        'layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="$horizontalFrom"><wp:posOffset>$xEmu</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="$verticalFrom"><wp:posOffset>$yEmu</wp:posOffset></wp:positionV>'
        '<wp:extent cx="$widthEmu" cy="$heightEmu"/><wp:wrapNone/>'
        '<wp:docPr id="$id" name="Floating element $id"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Floating element $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relationId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm rot="$rotation"><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing>';
  }

  // ------------------------------- الترويسة -------------------------------

  /// جدول الترويسة: ثلاثة أعمدة (يمين موسَّط | وسط موسَّط | يسار محاذى لليمين).
  /// الجدول `bidiVisual` فالخلية الأولى عند اليمين.
  String _buildHeaderTable() {
    final data = blueprint.header;
    final borders = data.framed
        ? '<w:tblBorders>'
            '<w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
            '<w:left w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
            '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
            '<w:right w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
            '</w:tblBorders>'
        : '';
    final right = StringBuffer();
    for (final line in data.rightLines) {
      right.write(_headerParagraph(line, alignment: 'center'));
    }
    final center = StringBuffer();
    if (data.showBismillah) {
      // البسملة بخط خطّي أنيق (Amiri) — يبقى لها خطها مهما كان خط الورقة.
      center.write(
        _headerParagraph(
          data.bismillah,
          alignment: 'center',
          // الدور `bismillah` في العقد يحمل خط Amiri وحجم 17pt وارتفاع
          // السطر 1.5× معامل الورقة، ولا يرث تنسيق الترويسة — لكنه يحفظ
          // لون الترويسة (المعاينة والـ PDF نفسهما).
          role: VisualRole.bismillah,
          applyHeaderStyle: false,
          applyHeaderLayout: false,
          colorHex: document.header.style.colorHex,
        ),
      );
    }
    for (final line in data.centerLines) {
      center.write(_headerParagraph(line, alignment: 'center', bold: true));
    }
    final left = StringBuffer();
    for (final line in data.leftLines) {
      left.write(_headerParagraph(line, alignment: 'right'));
    }
    return '<w:tbl>'
        '<w:tblPr><w:bidiVisual/><w:tblW w:w="5000" w:type="pct"/>$borders</w:tblPr>'
        '<w:tr>'
        '<w:tc><w:tcPr><w:tcW w:w="1500" w:type="pct"/></w:tcPr>$right</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="2000" w:type="pct"/></w:tcPr>$center</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="1500" w:type="pct"/></w:tcPr>$left</w:tc>'
        '</w:tr>'
        '</w:tbl>';
  }

  /// فقرة عربية (RTL دائماً) في الترويسة أو التذييل: تنسيق الترويسة الذي
  /// اختاره المدرس (خط/حجم/عريض/مائل/تسطير/لون/تباعد أسطر) يُطبَّق ما لم
  /// يُطلب غيره — فإعداد الترويسة في الواجهة مصدر وحيد يصل إلى الملف.
  ///
  /// [applyHeaderLayout] يضيف إعدادات التخطيط الخاصة بسطور الترويسة
  /// (المحاذاة، والمسافة بعد الفقرة، وارتفاع السطر الأساسي 1.6× معامل
  /// الورقة — الرقم نفسه في المعاينة والـ PDF): تُستثنى منه البسملة
  /// والتذييل. والحجم الافتراضي 10pt مطابقةً لهما أيضاً.
  String _headerParagraph(
    String text, {
    required String alignment,
    VisualRole role = VisualRole.headerBody,
    bool bold = false,
    PaperFont? font,
    bool applyHeaderStyle = true,
    bool applyHeaderLayout = true,
    String? colorHex,
  }) {
    final style = applyHeaderStyle ? document.header.style : null;
    // الحجم/الوزن/الميل/التسطير/الخط/ارتفاع السطر من عقد الطباعة الوحيد:
    // تنسيق الترويسة الذي اختاره المدرس ([style]) يتقدم، ثم الاستبدال
    // الموضعي (البسملة بخطها، عمود الوسط الغامق)، ثم قيمة الدور المرجعية
    // مضروبة بمعامل الورقة مرة واحدة.
    final resolved = _roleStyle(
      role,
      override: style,
      bold: role == VisualRole.headerBody ? bold : null,
      font: font,
    );
    final effectiveBold = resolved.bold;
    final effectiveSize = resolved.halfPoints;
    final fontName = DocxDocumentExportService._fontName(resolved.font);
    final color = _paragraphColor(resolved, explicit: colorHex, style: style);
    final line = resolved.lineTwips;
    // المسافة بعد كل سطر ترويسة (إعداد المدرس: بكسل منطقي ← تويب).
    final spacingAfter = !applyHeaderLayout || style?.paragraphSpacing == null
        ? null
        : PaperMetrics.twips(style!.paragraphSpacing!);
    // المحاذاة: إعداد المدرس يتجاوز محاذاة العمود — و«بداية السطر» في
    // مستند RTL هي اليمين، كما في المعاينة والـ PDF.
    final effectiveAlign = !applyHeaderLayout || style?.align == null
        ? alignment
        : _wordAlign(style!.align);
    final runProperties = _RunProperties(
      bold: effectiveBold,
      italic: resolved.italic,
      underline: resolved.underline,
      color: color,
      size: effectiveSize,
      font: fontName,
      rtl: true,
    );
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$effectiveAlign"/>'
        '<w:spacing${spacingAfter == null ? '' : ' w:before="0" w:after="$spacingAfter"'} w:line="$line" w:lineRule="auto"/></w:pPr>'
        '${_runsXml(text, runProperties, effectiveSize / 2)}'
        '</w:p>';
  }

  // ------------------------------- التذييل -------------------------------

  /// التذييل: جدول عائم مثبّت أسفل صندوق النص في آخر صفحة (بعد آخر سؤال):
  /// التوقيع الثاني يميناً (إن وُجد) ← العبارة الختامية وسطاً ← التوقيع
  /// الأساسي يساراً. الجدول `bidiVisual` فالخلية الأولى عند اليمين.
  void _buildFooterTable(StringBuffer body) {
    final data = blueprint.footer;
    final marginTwips = (document.settings.marginMm / 25.4 * 1440).round();
    final width = _pageWidthTwips - 2 * marginTwips;
    final side = (width * 0.3).round();
    final middle = width - 2 * side;

    String signature(SignatureBlueprint? source) {
      if (source == null) {
        return '<w:p/>';
      }
      // سطر التذييل يأخذ تنسيق نص الترويسة (خط/حجم/لون/تباعد أسطر) لكن
      // لا محاذاة الترويسة ولا مسافة فقراتها — كالمعاينة والـ PDF. ودور
      // `headerBody` في العقد يحمل ارتفاع السطر 1.6× معامل الورقة نفسه.
      final title = _headerParagraph(
        source.title,
        alignment: 'center',
        bold: true,
        applyHeaderLayout: false,
      );
      final nameLine = _headerParagraph(
        source.nameLine,
        alignment: 'center',
        applyHeaderLayout: false,
      );
      return '$title$nameLine';
    }

    String cell(int cellWidth, String content) =>
        '<w:tc><w:tcPr><w:tcW w:w="$cellWidth" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
        '$content</w:tc>';

    final phrase = data.closingPhrase;
    body.write(
      '<w:tbl><w:tblPr>'
      '<w:tblpPr w:leftFromText="0" w:rightFromText="0" w:vertAnchor="margin" '
      'w:horzAnchor="margin" w:tblpXSpec="center" w:tblpYSpec="bottom"/>'
      '<w:bidiVisual/><w:tblW w:w="$width" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
      '</w:tblPr>'
      '<w:tblGrid><w:gridCol w:w="$side"/><w:gridCol w:w="$middle"/><w:gridCol w:w="$side"/></w:tblGrid>'
      '<w:tr>'
      '${cell(side, signature(data.secondary))}'
      '${cell(middle, phrase == null ? '<w:p/>' : _headerParagraph(phrase, alignment: 'center', bold: true, applyHeaderLayout: false))}'
      '${cell(side, signature(data.primary))}'
      '</w:tr></w:tbl>'
      // فقرة مرساة صغيرة تتبع الجدول العائم (لا تأخذ مساحة تُذكر).
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr></w:p>',
    );
  }

  /// نمط الدور من **عقد الطباعة الوحيد** [ExamTypography] — نفس الجدول الذي
  /// تقرأه المعاينة ومحرك PDF، بمعاملَي الورقة مطبَّقين مرة واحدة فيه.
  VisualTextStyle _roleStyle(
    VisualRole role, {
    PaperTextStyle? override,
    bool? bold,
    double? sizePt,
    double? lineHeight,
    int? color,
    PaperFont? font,
  }) {
    return ExamTypography.resolve(
      role,
      settings: document.settings,
      layout: document.layout,
      override: override,
      bold: bold,
      sizePt: sizePt,
      lineHeight: lineHeight,
      color: color,
      font: font,
    );
  }

  /// اللون النهائي لفقرة: لون صريح، أو لون العنصر، أو لون الدور من العقد
  /// (`null` = لون النص الافتراضي في Word).
  String? _paragraphColor(
    VisualTextStyle resolved, {
    String? explicit,
    PaperTextStyle? style,
  }) {
    final hex = explicit ?? style?.colorHex;
    if (hex != null) {
      return hex;
    }
    final argb = resolved.color;
    if (argb == null) {
      return null;
    }
    return (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  // ------------------------------- الأسئلة -------------------------------

  Future<void> _buildQuestion(StringBuffer body, QuestionBlueprint data) async {
    final question = data.model;
    final bodyStyle = question.style.copyWith(color: () => null);
    final titleStyle = question.style.copyWith(
      align: () => question.titleAlign ?? question.style.align,
      color: () => question.effectiveTitleColor,
    );
    final bodyContent = data.semanticBody;
    // الترتيب مطابق للوحة المعاينة ومحرك الـ PDF حرفياً:
    // القسم ← سطر العنوان ← النص ← نقاط السؤال ← الفروع.
    if (data.section != null) {
      _reportProgress('question ${question.id} section:started');
      // سطر القسم: 12.5pt ومحاذاته من النموذج (`categoryAlign`) — نفس مقاس
      // المعاينة ومحرك PDF ونفس قرار المحاذاة، وبلا فجوة قبله أو بعده
      // (المعاينة تلصقه بسطر العنوان).
      _writeStyledParagraph(
        body,
        data.section!,
        role: VisualRole.category,
        alignmentOverride: question.categoryAlign,
        before: 0,
        after: 0,
        runs: data.category == null
            ? null
            : _semanticRuns(data.category!.content),
      );
      _reportProgress('question ${question.id} section:completed');
    }
    // سطر العنوان: الرقم ← المنطوق ← الدرجة **جريانات مستقلة** (لا نص
    // مدموج) بفجوات المسافات نفسها التي تفصل عناصر المعاينة.
    _reportProgress('question ${question.id} title:started');
    _writeStyledParagraph(
      body,
      data.title.line,
      // الدور يحمل الحجم (11pt) والعرض (غامق) وارتفاع السطر (1.7) من
      // العقد — لا رقم مكتوب هنا.
      role: VisualRole.questionTitle,
      style: titleStyle,
      color: titleStyle.colorHex,
      before: 0,
      after: PaperMetrics.twips(VisualMetrics.elementGapPx),
      border: question.showFrame,
      runs: _titleRuns(
        data.title,
        bold: true,
        color: titleStyle.colorHex,
      ),
    );
    _reportProgress('question ${question.id} title:completed');
    if (data.body != null) {
      _reportProgress('question ${question.id} body:started');
      _writeStyledParagraph(
        body,
        data.body!,
        role: VisualRole.questionBody,
        style: bodyStyle.copyWith(
          align: () => question.bodyAlign ?? question.style.align,
        ),
        before: question.style.paragraphSpacing == null
            ? PaperMetrics.twips(VisualMetrics.elementGapPx)
            : 0,
        after: 0,
        runs: bodyContent == null ? null : _semanticRuns(bodyContent),
      );
      _reportProgress('question ${question.id} body:completed');
    }
    _reportProgress('question ${question.id} points:started');
    _writePoints(
      body,
      data.points,
      style: bodyStyle,
      indent: _pointIndentTwips,
      firstGapPx: VisualMetrics.elementGapPx,
    );
    _reportProgress('question ${question.id} points:completed');
    for (final branch in data.branches) {
      _reportProgress(
        'question ${question.id} branch ${branch.model.id}:started',
      );
      await _buildBranch(
        body,
        branch,
        questionParagraphSpacing: question.style.paragraphSpacing,
      );
      _reportProgress(
        'question ${question.id} branch ${branch.model.id}:completed',
      );
    }
    _reportProgress('question ${question.id} attachments:started');
    await _buildAttachments(body, question.attachments);
    _reportProgress('question ${question.id} attachments:completed');
    // العناصر المرتبطة بهذا السؤال تُكتب مع فقراته (مرساة نسبية للفقرة).
    _reportProgress('question ${question.id} owned-elements:started');
    await _buildOwnedElements(body, question.id);
    _reportProgress('question ${question.id} owned-elements:completed');
    _buildDivider(body, question.dividerAfter);
  }

  /// نقاط مرقَّمة (داخل سؤال أو فرع) بتسلسلها المتصل — وتحت كل نقطة
  /// «اختيار من متعدد» سطر خياراتها. الفارغة تماماً تُحذف.
  /// إزاحة صف النقطة عن بداية الكتلة (تويب مشتق من العقد البصري).
  int get _pointIndentTwips => PaperMetrics.twips(VisualMetrics.pointIndentPx);

  /// إزاحة صف الخيارات داخل النقطة (تويب).
  int get _optionIndentTwips => PaperMetrics.twips(VisualMetrics.optionIndentPx);

  /// إزاحة كتلة الفرع عن بداية السؤال (تويب).
  int get _branchIndentTwips => PaperMetrics.twips(VisualMetrics.branchIndentPx);

  void _writePoints(
    StringBuffer body,
    List<PointBlueprint> points, {
    required PaperTextStyle? style,
    required int indent,
    required double firstGapPx,
  }) {
    var written = 0;
    for (final point in points) {
      if (!point.isPrintable) {
        continue;
      }
      final pointStyle =
          point.item.align != null ? style?.copyWith(align: () => point.item.align) : style;
      final customSpacing = style?.paragraphSpacing;
      // الفجوة قبل أول نقطة = فجوة الكتلة (سؤال: 2px، فرع: 1px)، وبين
      // نقطتين = فجوة المسافة بين الفقرات (صفر افتراضاً) — كما في
      // المعاينة ومحرك PDF بالبكسل المنطقي نفسه.
      final before = customSpacing != null
          ? 0
          : (written == 0
              ? PaperMetrics.twips(firstGapPx)
              : PaperMetrics.twips(VisualMetrics.itemGapPx));
      if (point.line.trim().isNotEmpty) {
        // أجزاء النقطة (الرقم/النص/القوسان/الدرجة) جريانات مستقلة:
        // الرقم غامق وحده، وهو تفريق لا تعبّر عنه الفقرة المدموجة.
        _writeStyledParagraph(
          body,
          point.line,
          role: VisualRole.point,
          style: pointStyle,
          indent: indent,
          before: before,
          after: customSpacing == null ? 0 : _paragraphSpacingTwips(customSpacing),
          runs: _pointRuns(point),
        );
        written++;
      }
      if (point.optionsLine.isNotEmpty) {
        _writeStyledParagraph(
          body,
          point.optionsLine,
          role: VisualRole.option,
          style: pointStyle,
          indent: indent + _optionIndentTwips,
          before: PaperMetrics.twips(VisualMetrics.optionTopGapPx),
          after: customSpacing == null ? 0 : _paragraphSpacingTwips(customSpacing),
          runs: _optionRuns(point.options),
        );
      }
    }
  }

  Future<void> _buildBranch(
    StringBuffer body,
    BranchBlueprint data, {
    double? questionParagraphSpacing,
  }) async {
    final branch = data.model;
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    // الفرع الفارغ تماماً يُحذف من الملف كاملاً ولا يترك فقرات فارغة.
    if (!data.isPrintable(ignoredAttachmentIds: globalElementIds)) {
      return;
    }
    _writeStyledParagraph(
      body,
      data.title.line,
      role: VisualRole.branchTitle,
      style: branch.style,
      indent: _branchIndentTwips,
      before: questionParagraphSpacing == null
          ? PaperMetrics.twips(VisualMetrics.elementGapPx)
          : _paragraphSpacingTwips(questionParagraphSpacing),
      after: PaperMetrics.twips(VisualMetrics.branchGapPx),
      border: branch.showFrame,
      runs: _titleRuns(data.title, bold: true),
    );
    if (data.body != null) {
      _writeStyledParagraph(
        body,
        data.body!,
        role: VisualRole.branchBody,
        style: branch.style,
        indent: _branchIndentTwips,
        before: branch.style.paragraphSpacing == null
            ? PaperMetrics.twips(VisualMetrics.branchGapPx)
            : 0,
        after: 0,
        runs: data.bodyContent == null
            ? null
            : _semanticRuns(data.bodyContent!),
      );
    }
    _writePoints(
      body,
      data.points,
      style: branch.style,
      indent: _pointIndentTwips,
      firstGapPx: VisualMetrics.branchGapPx,
    );
    await _buildAttachments(body, branch.attachments);
    _buildDivider(body, branch.dividerAfter);
  }

  void _buildDivider(StringBuffer body, PaperDivider? divider) {
    if (divider == null) {
      return;
    }
    final width = (divider.thickness * 8).round().clamp(4, 48);
    body.write(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="$width" w:space="4" w:color="000000"/></w:pBdr>'
      '<w:spacing w:before="${(divider.spacingBefore * 20).round()}" w:after="${(divider.spacingAfter * 20).round()}"/>'
      '</w:pPr></w:p>',
    );
  }

  // ------------------------- المرفقات: صور/أشكال/نص -------------------------

  Future<void> _buildAttachments(
    StringBuffer body,
    List<FloatingElement> attachments,
  ) async {
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    for (final sourceElement in attachments) {
      if (globalElementIds.contains(sourceElement.id)) {
        continue;
      }
      final element = _legacyFloatingElement(sourceElement);
      _reportProgress('attachment ${element.id}:started');
      if (element.isTextBox) {
        _buildTextBox(body, element);
        _reportProgress('attachment ${element.id}:completed');
        continue;
      }
      if (element.isFormula) {
        await _buildFormulaElement(body, element);
        _reportProgress('attachment ${element.id}:completed');
        continue;
      }
      if (element.type == FloatingElementType.image) {
        final bytes = element.bytes;
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        _embedImage(body, Uint8List.fromList(bytes), element.width, element.height);
        _reportProgress('attachment ${element.id}:completed');
        continue;
      }
      // شكل متجه: يُرسم صورة عند توفر المرسّم، وإلا عنصر نصي بديل.
      Uint8List? raster;
      if (shapeRasterizer != null) {
        try {
          raster = await shapeRasterizer!(element, element.width, element.height);
        } catch (_) {
          raster = null;
        }
      }
      if (raster != null && raster.isNotEmpty) {
        _embedImage(body, raster, element.width, element.height);
      } else {
        _writeParagraph(
          body,
          '[شكل: ${element.shape?.arabicLabel ?? 'شكل'}]',
          italic: true,
          color: '6B7280',
          alignment: 'center',
          before: 60,
          after: 60,
        );
      }
      _reportProgress('attachment ${element.id}:completed');
    }
  }

  void _buildTextBox(
    StringBuffer body,
    FloatingElement element, {
    bool floatingOnPage = false,
    bool pageAnchored = true,
    String? textOverride,
  }) {
    final text = textOverride ??
        (element.label.trim().isEmpty ? ' ' : element.label.trim());
    final border = element.framed
        ? '<w:tblBorders><w:top w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
            '<w:left w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
            '<w:bottom w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
            '<w:right w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
            '<w:insideH w:val="single" w:sz="6" w:space="0" w:color="111827"/>'
            '<w:insideV w:val="single" w:sz="6" w:space="0" w:color="111827"/></w:tblBorders>'
        : '<w:tblBorders><w:top w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'
            '<w:left w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'
            '<w:bottom w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'
            '<w:right w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'
            '<w:insideH w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'
            '<w:insideV w:val="nil" w:sz="0" w:space="0" w:color="auto"/></w:tblBorders>';
    final align = _wordAlign(element.textStyle.align);
    final font = DocxDocumentExportService._fontName(
      element.textStyle.font ?? document.settings.defaultFont,
    );
    final baseSize =
        element.textStyle.fontSize ?? 11 * document.settings.fontScale;
    final size = (baseSize * 2).round().clamp(16, 72);
    final line = (240 * document.settings.lineSpacing).round();
    final runProperties = _RunProperties(
      bold: element.textStyle.bold == true,
      italic: element.textStyle.italic == true,
      underline: element.textStyle.underline == true,
      size: size,
      font: font,
      rtl: !document.layout.isLtr,
    );
    final widthTwips = (PaperMetrics.pt(element.width) * 20).round();
    final heightTwips = (PaperMetrics.pt(element.height) * 20).round();
    final referenceWidth = pageAnchored
        ? ExamCanvasGeometry.width
        : ExamCanvasGeometry.contentWidthFor(document.settings.marginMm);
    final physicalLeftPx = document.layout.isLtr
        ? element.dx
        : referenceWidth - element.dx - element.width;
    final xTwips = (PaperMetrics.pt(physicalLeftPx) * 20).round();
    final yTwips = (PaperMetrics.pt(element.dy) * 20).round();
    final tableWidth = floatingOnPage
        ? '<w:tblW w:w="$widthTwips" w:type="dxa"/>'
        : '<w:tblW w:w="5000" w:type="pct"/>';
    // عنصر السؤال يُثبَّت على margin النص (column) ويتبع فقرته (text)،
    // والعنصر الحر يُثبَّت على الصفحة كما كان.
    final horizontalAnchor = pageAnchored ? 'page' : 'margin';
    final verticalAnchor = pageAnchored ? 'page' : 'text';
    final tablePosition = floatingOnPage
        ? '<w:tblpPr w:horzAnchor="$horizontalAnchor" w:vertAnchor="$verticalAnchor" '
            'w:tblpX="$xTwips" w:tblpY="$yTwips"/>'
        : '';
    final tableLayout = floatingOnPage ? '<w:tblLayout w:type="fixed"/>' : '';
    final grid = floatingOnPage ? '<w:tblGrid><w:gridCol w:w="$widthTwips"/></w:tblGrid>' : '';
    final rowProperties = floatingOnPage
        ? '<w:trPr><w:trHeight w:val="$heightTwips" w:hRule="atLeast"/></w:trPr>'
        : '';
    final cellWidth = floatingOnPage
        ? '<w:tcW w:w="$widthTwips" w:type="dxa"/>'
        : '';
    body.write(
      '<w:tbl><w:tblPr>$tablePosition<w:bidiVisual/>$tableWidth$border$tableLayout</w:tblPr>'
      '$grid<w:tr>$rowProperties<w:tc><w:tcPr>$cellWidth</w:tcPr>'
      '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}<w:jc w:val="$align"/>'
      '<w:spacing w:line="$line" w:lineRule="auto"/></w:pPr>'
      '${_runsXml(text, runProperties, size / 2)}</w:p></w:tc></w:tr></w:tbl>',
    );
  }

  /// صيغة عنصر معادلة حرّ كـ**معادلة Word أصلية** (`m:oMathPara`)؛ ويعيد
  /// `null` إن تعذّر تمثيلها بُنيةً (فيرتدّ Caller إلى الرسم ثم إلى النص).
  ///
  /// حجم الخط: ما حدّده المدرس للعنصر إن حدّد، وإلا فراغ الصندوق نفسه
  /// (أصغر ضلعه بالنقاط) — وهو المقاس الذي كانت الصورة تُرسَم به ثم تُلاءَم،
  /// فتبقى المعادلة على مقياس الورقة كما كانت، بلا تمديد يُفلطحها: في Word
  /// المعادلة بحجم خطها (حدّة كاملة وتحرير متاح)، والإطار يحتفظ بحدّه
  /// وموضعه وحجمه.
  String? _formulaMathZone(FloatingElement element) {
    final label = element.label.trim();
    if (label.isEmpty) {
      return null;
    }
    final configured = element.textStyle.fontSize;
    final fontSizePt = configured != null
        ? configured.clamp(11.0, 72.0).toDouble()
        : math
            .min(PaperMetrics.pt(element.height), PaperMetrics.pt(element.width))
            .clamp(11.0, 72.0)
            .toDouble();
    return OmmlFromEquation.mathParagraphXml(
      label,
      fontSizePt: fontSizePt,
      extraRunProperties: _mathRunProperties(_formulaRunProperties(element)),
    );
  }

  /// تنسيق نص عنصر المعادلة (يُورَّث للمعادلة نفسها: غامق/مائل/لون).
  String _formulaRunProperties(FloatingElement element) {
    final style = element.textStyle;
    final buffer = StringBuffer();
    if (style.bold == true) {
      buffer.write('<w:b/>');
    }
    if (style.italic == true) {
      buffer.write('<w:i/>');
    }
    final color = style.colorHex;
    if (color != null) {
      buffer.write('<w:color w:val="$color"/>');
    }
    return buffer.toString();
  }

  void _embedImage(StringBuffer body, Uint8List bytes, double widthPx, double heightPx) {
    final widthPt = PaperMetrics.pt(widthPx);
    final heightPt = PaperMetrics.pt(heightPx);
    if (widthPt <= 0 || heightPt <= 0) {
      return;
    }
    body.write(
      '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}<w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>'
      '<w:r>${_drawingXml(bytes, widthPt, heightPt)}</w:r></w:p>',
    );
  }

  /// الممرّ الوحيد لعناصر المعادلات ([FloatingElementType.formula]) في
  /// الملف — مرفقاتٍ كانت أو مرتبطة بسؤال أو حرّة على الصفحة:
  /// **فقرة في تدفق النص** (موسَّطة) لا عنصراً عائماً، فلا تتراكب المعادلات
  /// ولا يتغير ترتيبها داخل Word أبداً.
  ///
  /// تُصدَّر أولاً **معادلة Word أصلية** (`m:oMathPara` قابلة للتحرير؛
  /// انظر [_formulaMathZone]) — فإن تعذّر تمثيلها بُنيةً (مصفوفة…) رُسمت
  /// بمحرك المعاينة نفسه (لقطة `flutter_math_fork` عالية الدقة) بمقاسها على
  /// الورقة (تصغير فقط حتى لا تتشوّه ولا تفقد الحدّة)، وإن تعذّر رسمها
  /// كُتبت نصاً رياضياً مقروءاً — ولا يظهر كود LaTeX الخام في أي حالة.
  Future<void> _buildFormulaElement(
    StringBuffer body,
    FloatingElement element,
  ) async {
    _reportProgress('formula ${element.id}:started');
    final label = element.label.trim();
    if (label.isEmpty) {
      _reportProgress('formula ${element.id}:empty');
      return;
    }
    final mathZone = _formulaMathZone(element);
    _reportProgress('formula ${element.id}:omml=${mathZone != null}');
    if (mathZone != null) {
      // معادلة Word حقيقية في فقرة مستقلة (محاذاة كما في باقي المرفقات).
      body.write(
        '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}'
        '<w:jc w:val="center"/><w:spacing w:before="60" w:after="60"/>'
        '</w:pPr>$mathZone</w:p>',
      );
      _reportProgress('formula ${element.id}:completed');
      return;
    }
    final boxWidthPt = PaperMetrics.pt(element.width);
    final boxHeightPt = PaperMetrics.pt(element.height);
    // حجم خط الرسم يتبع ارتفاع الصندوق: الرسم يخرج قريباً من مقاسه النهائي
    // فلا يحتاج تكبيراً يُفقد الحدّة.
    final raster = await _rasterizeMath(_MathPlaceholder(label, boxHeightPt));
    if (raster == null || raster.pngBytes.isEmpty) {
      // تعذّر ترسيم المعادلة: تُكتب نصاً رياضياً مقروءاً بدل كودها.
      _writeParagraph(
        body,
        EquationModel.readableText(label),
        italic: true,
        color: '6B7280',
        alignment: 'center',
        before: 60,
        after: 60,
      );
      _reportProgress('formula ${element.id}:fallback-text');
      return;
    }
    final naturalWidth = raster.widthPt;
    final naturalHeight = raster.heightPt;
    var widthPt = boxWidthPt > 0 ? boxWidthPt : naturalWidth;
    var heightPt = boxHeightPt > 0 ? boxHeightPt : naturalHeight;
    if (naturalWidth > 0 && naturalHeight > 0 && widthPt > 0 && heightPt > 0) {
      final scale = math.min(
        math.min(widthPt / naturalWidth, heightPt / naturalHeight),
        2.0,
      );
      widthPt = naturalWidth * scale;
      heightPt = naturalHeight * scale;
    }
    body.write(
      '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}<w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>'
      '<w:r>${_drawingXml(raster.pngBytes, widthPt, heightPt)}</w:r></w:p>',
    );
    _reportProgress('formula ${element.id}:completed');
  }

  /// XML رسم مضمّن (بلا فقرة وبلا run) مع تسجيل الصورة في حزمة الملف.
  ///
  /// يُستخدم لصور المرفقات **ومعادلات LaTeX** المرسومة: الأولى في فقرة
  /// مستقلة، والثانية داخل سطر النص نفسه (رسم سطري بجانب الكلام).
  String _drawingXml(Uint8List bytes, double widthPt, double heightPt) {
    var width = widthPt;
    var height = heightPt;
    if (width > DocxDocumentExportService._maxImageWidthPt) {
      final scale = DocxDocumentExportService._maxImageWidthPt / width;
      width *= scale;
      height *= scale;
    }
    final emuW = (width / 72 * 914400).round();
    final emuH = (height / 72 * 914400).round();
    final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final relationId = 'rIdImg${images.length + 2}';
    images.add(
      _EmbeddedImage(
        data: bytes,
        extension: isJpeg ? 'jpeg' : 'png',
        contentType: isJpeg ? 'image/jpeg' : 'image/png',
        relationId: relationId,
        widthEmu: emuW,
        heightEmu: emuH,
      ),
    );
    final id = _drawingId++;
    return '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$emuW" cy="$emuH"/>'
        '<wp:docPr id="$id" name="Picture $id"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Picture $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relationId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$emuW" cy="$emuH"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>';
  }

  // ------------------------------- فقرات -------------------------------

  int _paragraphSpacingTwips(double logicalPixels) =>
      (PaperMetrics.pt(logicalPixels) * 20).round();

  /// جريان نصّي واحد داخل فقرة Word: نصّه وتنسيقه الخاص.
  ///
  /// وجود هذا النوع هو ما يمنع «دمج» أجزاء العنصر (رقم ← منطوق ← درجة،
  /// أو تسمية نقطة ← نصها ← قوساها ← درجتها، أو تسمية خيار ← نصه) في نص
  /// واحد لا يعرف Word أجزاءه: كل جزء جريان مستقل بـ`<w:r>` خاصة به —
  /// تماماً كما تفصل المعاينة عناصرها ويطبع PDF كتلته.
  static String _runPropertiesXml({
    required bool bold,
    required bool italic,
    required bool underline,
    required bool highlight,
    required String? color,
    required int size,
    required String font,
    required bool rtl,
  }) {
    final buffer = StringBuffer('<w:rPr>${rtl ? '<w:rtl/>' : ''}');
    if (bold) {
      buffer.write('<w:b/>');
    }
    if (italic) {
      buffer.write('<w:i/>');
    }
    if (underline) {
      buffer.write('<w:u w:val="single"/>');
    }
    if (highlight) {
      buffer.write('<w:highlight w:val="yellow"/>');
    }
    if (color != null) {
      buffer.write('<w:color w:val="$color"/>');
    }
    buffer.write(
      '<w:sz w:val="$size"/><w:szCs w:val="$size"/>'
      '<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>'
      '</w:rPr>',
    );
    return buffer.toString();
  }

  /// فقرة منسّقة بدور من العقد البصري.
  ///
  /// الحجم (أنصاف النقاط) والوزن والميل والتسطير والخط وارتفاع السطر كلها
  /// تأتي **نهائية** من [ExamTypography] — فما يُكتب في Word هو ما تراه
  /// المعاينة وما يطبعه PDF بالضبط. تنسيق العنصر المخصص (`style.fontSize`
  /// و`style.lineHeight`) مطلق ويتقدم على القيم المرجعية، كما في العقد.
  ///
  /// [alignmentOverride] يسمح لمحاذاة خاصة بالسياق (سطر القسم
  /// `categoryAlign`) أن تسود على تنسيق العنصر.
  void _writeStyledParagraph(
    StringBuffer body,
    String text, {
    required VisualRole role,
    PaperTextStyle? style,
    PaperAlign? alignmentOverride,
    String? color,
    int? indent,
    int? before,
    int? after,
    bool border = false,
    List<DocxRunSpec>? runs,
  }) {
    final resolved = _roleStyle(role, override: style);
    final paragraphRtl = _paragraphDirection(
      text,
      runs,
      fallbackRtl: !document.layout.isLtr,
    );
    _writeParagraph(
      body,
      text,
      runs: runs,
      bold: resolved.bold,
      italic: resolved.italic,
      underline: resolved.underline,
      size: resolved.halfPoints,
      // الحجم نهائي من العقد: لا ضرب ثانٍ بمعامل الورقة هنا.
      scaleSize: false,
      border: border,
      color: _paragraphColor(resolved, explicit: color, style: style),
      indent: indent,
      before: before,
      after: style?.paragraphSpacing == null
          ? after
          : _paragraphSpacingTwips(style!.paragraphSpacing!),
      lineHeight: resolved.lineHeight,
      alignment: _wordAlign(
        alignmentOverride ?? style?.align,
        alignmentRtl: documentIr.direction == DocumentDirection.rtl,
      ),
      font: DocxDocumentExportService._fontName(resolved.font),
      directionRtl: paragraphRtl,
    );
  }

  /// محاذاة Word من محاذاة النموذج — بمراعاة **اتجاه كتلة LayoutDocument**:
  /// `start`/`end` يتبعان اتجاه الكتلة حتى إن احتوت فقرتها مقطعاً يبدأ بنص
  /// لاتيني (اتجاه BiDi للجريان لا يغيّر معنى المحاذاة المنطقية للكتلة).
  String _wordAlign(PaperAlign? align, {bool? alignmentRtl}) {
    final isLtr = alignmentRtl == null
        ? document.layout.isLtr
        : !alignmentRtl;
    switch (align) {
      case null:
        // «بلا محاذاة» = بداية السطر حسب **اتجاه الورقة**، وهو ما تفعله
        // المعاينة (`TextAlign.start`) وPDF (افتراضي السمة `start`): كانت
        // تعيد «right» دائماً فتدفع ورقة LTR إلى اليمين بلا سبب.
        return isLtr ? 'left' : 'right';
      case PaperAlign.start:
        return isLtr ? 'left' : 'right';
      case PaperAlign.end:
        return isLtr ? 'right' : 'left';
      case PaperAlign.center:
        return 'center';
      case PaperAlign.justify:
        return 'both';
      case PaperAlign.left:
        return 'left';
      case PaperAlign.right:
        return 'right';
    }
  }

  void _writeParagraph(
    StringBuffer body,
    String text, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
    int size = 22,
    bool scaleSize = true,
    bool border = false,
    String? color,
    double? lineHeight,
    bool highlight = false,
    int? indent,
    int? before,
    int? after,
    String? alignment,
    String? font,
    bool? directionRtl,
    List<DocxRunSpec>? runs,
  }) {
    // The paragraph takes the direction of its first strong character, falling
    // back to the document direction only when the text has no strong script.
    final paragraphRtl = directionRtl ??
        _paragraphDirection(
          text,
          runs,
          fallbackRtl: !document.layout.isLtr,
        );
    final effectiveAlignment = alignment ??
        _wordAlign(
          null,
          alignmentRtl: documentIr.direction == DocumentDirection.rtl,
        );
    final effectiveSize = scaleSize
        ? (size * document.settings.fontScale).round().clamp(12, 96)
        : size.clamp(12, 96);
    // تباعد أسطر العنصر المخصص يسود، وإلا العام من إعدادات الورقة (240 = مفرد).
    final line = (240 * (lineHeight ?? document.settings.lineSpacing)).round();
    body.write('<w:p><w:pPr>${paragraphRtl ? '<w:bidi/>' : ''}<w:jc w:val="$effectiveAlignment"/>');
    if (border) {
      body.write(
        '<w:pBdr><w:top w:val="single" w:sz="6" w:space="4" w:color="000000"/>'
        '<w:left w:val="single" w:sz="6" w:space="4" w:color="000000"/>'
        '<w:bottom w:val="single" w:sz="6" w:space="4" w:color="000000"/>'
        '<w:right w:val="single" w:sz="6" w:space="4" w:color="000000"/>'
        '</w:pBdr>',
      );
    }
    if (indent != null) {
      // إزاحة **منطقية** تتبع اتجاه الفقرة: `w:start` هو المفتاح الاتجاهي في
      // OOXML (يتحول يميناً في فقرة `w:bidi` ويساراً في LTR دون أن يتغير
      // الملف). ويُكتب معه المفتاح الفيزيائي لجهة البداية في الاتجاه الحالي
      // ليقرأه أي محرر لا يدعم الصيغة الاتجاهية — فلا ينخفض الحد في Word قديم
      // ولا يُجعَل `w:right` حلاً عالمياً: كان يُزاح فقرات LTR إلى اليمين.
      final startSide = paragraphRtl ? 'w:right' : 'w:left';
      body.write('<w:ind w:start="$indent" $startSide="$indent"/>');
    }
    body.write(
      '<w:spacing${before == null ? '' : ' w:before="$before"'}${after == null ? '' : ' w:after="$after"'} w:line="$line" w:lineRule="auto"/>',
    );
    // مقاس ASCII والعربي معاً (`w:sz` + `w:szCs`) وخط المجموعة والخط
    // اللاتيني معاً: Word يستعمل `w:szCs` لنص المجموعة العربية، وبدونه لا
    // يظهر أي تغيير في الحجم على الورقة العربية مهما ضبطه المدرس.
    final fontName =
        font ?? DocxDocumentExportService._fontName(document.settings.defaultFont);
    body.write('</w:pPr>');
    if (runs == null) {
      body.write(
        _runsXml(
          text,
          _RunProperties(
            bold: bold,
            italic: italic,
            underline: underline,
            highlight: highlight,
            color: color,
            size: effectiveSize,
            font: fontName,
            rtl: paragraphRtl,
          ),
          effectiveSize / 2,
        ),
      );
    } else {
      // كل جزء جريان مستقل: تنسيقه الخاص يتقدم، وما لم يحدده يتبع الفقرة.
      for (final run in runs) {
        final runSize = (run.size ?? effectiveSize).clamp(12, 96);
        body.write(
          _runsXml(
            run.text,
            _RunProperties(
              bold: run.bold ?? bold,
              italic: run.italic ?? italic,
              underline: run.underline ?? underline,
              highlight: highlight,
              color: run.color ?? color,
              size: runSize,
              font: run.font ?? fontName,
              rtl: run.rtl ?? paragraphRtl,
            ),
            runSize / 2,
            forceRtl: run.rtl,
            visualRun: run.visualRun,
          ),
        );
      }
    }
    body.write('</w:p>');
  }

  /// Title parts remain distinct Word runs, retaining DocumentIR's direction
  /// and each source-authored VisualRun (including math and Quran styling).
  List<DocxRunSpec> _titleRuns(
    TitleLineBlueprint title, {
    bool bold = true,
    int? size,
    String? color,
    String? font,
  }) {
    final parts = <List<DocxRunSpec>>[];
    if (title.number.trim().isNotEmpty) {
      parts.add(<DocxRunSpec>[
        ..._semanticNodeRuns(title.semanticNumber),
        if (title.separatorNode != null)
          ..._semanticNodeRuns(title.separatorNode!),
      ]);
    }
    if (title.hasStatement) {
      parts.add(_semanticRuns(title.semanticStatement));
    }
    if (title.marks != null) {
      parts.add(
        title.marksNode == null
            ? <DocxRunSpec>[DocxRunSpec(title.marks!)]
            : _semanticNodeRuns(title.marksNode!).toList(growable: false),
      );
    }

    DocxRunSpec styled(DocxRunSpec run) => DocxRunSpec(
          run.text,
          bold: bold,
          size: size,
          color: color,
          font: font,
          rtl: run.rtl,
          visualRun: run.visualRun,
        );

    final runs = <DocxRunSpec>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      if (part.isEmpty) continue;
      if (runs.isNotEmpty) {
        runs.add(styled(DocxRunSpec(' ', rtl: part.first.rtl)));
      }
      runs.addAll(part.map(styled));
    }
    return runs;
  }

  /// Point parts keep source direction/style while the label remains bold.
  List<DocxRunSpec> _pointRuns(
    PointBlueprint point, {
    bool bold = false,
    int? size,
    String? color,
    String? font,
  }) {
    final parts = <({List<DocxRunSpec> runs, bool bold})>[];
    if (point.label.trim().isNotEmpty) {
      parts.add((runs: _semanticRuns(point.semanticLabel), bold: true));
    }
    if (point.text.trim().isNotEmpty) {
      parts.add((runs: _semanticRuns(point.semanticText), bold: bold));
    }
    if (point.trailer != null) {
      final trailer = point.trailerContent;
      parts.add((
        runs: trailer == null
            ? <DocxRunSpec>[DocxRunSpec(point.trailer!) ]
            : _semanticRuns(trailer),
        bold: bold,
      ));
    }
    if (point.marks != null) {
      final marks = point.marksNode;
      parts.add((
        runs: marks == null
            ? <DocxRunSpec>[DocxRunSpec(point.marks!) ]
            : _semanticNodeRuns(marks).toList(growable: false),
        bold: bold,
      ));
    }

    DocxRunSpec styled(DocxRunSpec run, bool partBold) => DocxRunSpec(
          run.text,
          bold: partBold,
          size: size,
          color: color,
          font: font,
          rtl: run.rtl,
          visualRun: run.visualRun,
        );

    final runs = <DocxRunSpec>[];
    for (final part in parts) {
      if (part.runs.isEmpty) continue;
      if (runs.isNotEmpty) {
        runs.add(
          DocxRunSpec(
            ' ',
            bold: bold,
            size: size,
            color: color,
            font: font,
            rtl: part.runs.first.rtl,
          ),
        );
      }
      runs.addAll(part.runs.map((run) => styled(run, part.bold)));
    }
    return runs;
  }

  /// Option labels/content retain semantic direction and visual-run metadata.
  List<DocxRunSpec> _optionRuns(
    List<OptionBlueprint> options, {
    bool bold = false,
    int? size,
    String? color,
    String? font,
  }) {
    final runs = <DocxRunSpec>[];
    for (final option in options) {
      if (runs.isNotEmpty) {
        runs.add(const DocxRunSpec(_optionSeparator + _optionSeparator));
      }
      if (option.label.trim().isNotEmpty) {
        runs.addAll(
          _semanticRuns(option.semanticLabel).map(
            (run) => _styledSemanticRun(
              run,
              bold: bold,
              size: size,
              color: color,
              font: font,
            ),
          ),
        );
      }
      if (option.text.trim().isNotEmpty) {
        if (option.label.trim().isNotEmpty) {
          runs.add(DocxRunSpec(' ', bold: bold, size: size, color: color, font: font));
        }
        runs.addAll(
          _semanticRuns(option.semanticText).map(
            (run) => _styledSemanticRun(
              run,
              bold: bold,
              size: size,
              color: color,
              font: font,
            ),
          ),
        );
      }
    }
    return runs;
  }

  DocxRunSpec _styledSemanticRun(
    DocxRunSpec run, {
    required bool bold,
    int? size,
    String? color,
    String? font,
  }) =>
      DocxRunSpec(
        run.text,
        bold: bold,
        size: size,
        color: color,
        font: font,
        rtl: run.rtl,
        visualRun: run.visualRun,
      );

  /// فاصل الخيارات في Word: Word لا يضع خيارات الصف الواحد في سطر كالمعاينة
  /// وPDF (لا Wrap فيه)، فيُفصل بينها بمسافات غير قابلة للقطع بعدد يقارب
  /// الفجوة الأفقية نفسها — وهذا قيد معلن في تدقيق عقد التصدير لا ادّعاء
  /// تطابق.
  static const String _optionSeparator = '\u00A0\u00A0';

  /// فقرة منسّقة بدور من العقد البصري.

  /// يبني مقاطع الفقرة: نص عادي ككتلة `<w:r>` واحدة أو أكثر، وصيغ LaTeX
  /// **معادلات Word أصلية** `<m:oMath>` داخل الفقرة نفسها (تُحرَّر في Word
  /// كما تُحرَّر من أداتها، بلا صورة) — انظر [OmmlFromEquation].
  ///
  /// عند تعذّر تمثيل صيغة بُنيةً (مصفوفة، أسطر متعددة…) تُرسَم تلك الصيغة
  /// وحدها بمعامل [mathRasterizer] — أي بمحرك المعاينة نفسه — بعلامة موضع
  /// مؤقتة يستبدلها [_resolveMath] بالرسم بعد رسمه (فتبقى في مكانها من
  /// السطر وبالترتيب نفسه). وبدون مرسّم تُكتب نصاً رياضياً مقروءاً، وهو
  /// آخر ارتداد: لا يظهر كود LaTeX الخام في أي ملف.
  /// يبني جريانات الفقرة من **عقد المحتوى** نفسه ([RichContent.parse]) الذي
  /// تقرؤه المعاينة — لا بتحليل نصي ثانٍ.
  ///
  /// لكل مقطع تنسيقه المعلن في العقد (خط الآية القرآني مثلاً)، والصيغ تُبنى
  static bool? _rtlForDirection(DocumentDirection direction) => switch (direction) {
        DocumentDirection.rtl => true,
        DocumentDirection.ltr => false,
        DocumentDirection.auto || DocumentDirection.inherit => null,
      };

  bool _paragraphDirection(
    String text,
    List<DocxRunSpec>? runs, {
    required bool fallbackRtl,
  }) {
    final paragraphText = runs == null
        ? text
        : runs
            .where((run) => !(run.visualRun?.isMath ?? false))
            .map((run) => run.visualRun?.text ?? run.text)
            .join();
    return _directionalChunks(paragraphText, fallbackRtl).first.rtl;
  }

  List<DocxRunSpec> _semanticRuns(InlineContent content) => <DocxRunSpec>[
        for (final node in content.nodes) ..._semanticNodeRuns(node),
      ];

  Iterable<DocxRunSpec> _semanticNodeRuns(
    InlineNode node, {
    bool? inheritedRtl,
  }) sync* {
    final rtl = _rtlForDirection(node.direction) ?? inheritedRtl;
    if (node is LabelNode) {
      for (final child in node.content.nodes) {
        yield* _semanticNodeRuns(child, inheritedRtl: rtl);
      }
      return;
    }
    if (node is MarksNode) {
      yield* _semanticNodeRuns(node.opening, inheritedRtl: rtl);
      yield* _semanticNodeRuns(node.number, inheritedRtl: rtl);
      yield* _semanticNodeRuns(node.numberUnitGap, inheritedRtl: rtl);
      yield* _semanticNodeRuns(node.unit, inheritedRtl: rtl);
      yield* _semanticNodeRuns(node.closing, inheritedRtl: rtl);
      return;
    }
    if (node is RichRunNode) {
      if (node.run.text.isNotEmpty) {
        yield DocxRunSpec(
          node.run.text,
          rtl: rtl,
          visualRun: node.run,
        );
      }
      return;
    }
    for (final run in node.visualRuns) {
      if (run.text.isNotEmpty) {
        yield DocxRunSpec(run.text, rtl: rtl, visualRun: run);
      }
    }
  }

  List<({String text, bool rtl})> _directionalChunks(
    String text,
    bool fallbackRtl,
  ) {
    final resolved = FlutterTextMetrics.resolveDirectionalRuns(
      text,
      fallbackDirection: fallbackRtl
          ? DocumentDirection.rtl
          : DocumentDirection.ltr,
    );
    if (resolved.isEmpty) {
      return <({String text, bool rtl})>[(text: text, rtl: fallbackRtl)];
    }
    return resolved
        .map(
          (run) => (
            text: run.text,
            rtl: run.direction == DocumentDirection.rtl,
          ),
        )
        .toList(growable: false);
  }

  String _directionalTextXml(
    String text,
    _RunProperties properties, {
    VisualRunStyle? style,
    bool? forceRtl,
  }) {
    final chunks = forceRtl == null
        ? _directionalChunks(text, properties.rtl)
        : <({String text, bool rtl})>[(text: text, rtl: forceRtl)];
    final buffer = StringBuffer();
    for (final chunk in chunks) {
      final runProperties = properties.withRtl(chunk.rtl).merge(style).toXml();
      buffer.write(
        '<w:r>$runProperties<w:t xml:space="preserve">'
        '${_escapeXml(chunk.text)}</w:t></w:r>',
      );
    }
    return buffer.toString();
  }

  /// **معادلات Word أصلية** `<m:oMath>` داخل الفقرة نفسها (تُحرَّر في Word
  /// كما تُحرَّر من أداتها، بلا صورة) — انظر [OmmlFromEquation]. وعند تعذّر
  /// تمثيل صيغة بُنيةً (مصفوفة، أسطر متعددة…) تُرسَم تلك الصيغة وحدها بمعامل
  /// [mathRasterizer] — أي بمحرك المعاينة نفسه — بعلامة موضع مؤقتة يستبدلها
  /// [_resolveMath] بالرسم بعد رسمه (فتبقى في مكانها من السطر وبالترتيب
  /// نفسه). وبدون مرسّم تُكتب نصاً رياضياً مقروءاً، وهو آخر ارتداد: لا يظهر
  /// كود LaTeX الخام في أي ملف.
  String _runsXml(
    String text,
    _RunProperties properties,
    double fontSizePt, {
    bool? forceRtl,
    VisualRun? visualRun,
  }) {
    final sourceRuns = visualRun == null
        ? RichContent.parse(text).runs
        : <VisualRun>[visualRun];
    final runProperties = properties.toXml();
    // مسار سريع حين لا يغيّر العقد شيئاً: نص واحد يطابق الأصل حرفياً.
    // (وهو أيضاً ما يجعل الدولار المهروب `\$` يُكتب `$` كما في المعاينة، بلا
    // شرطة مائلة لا أصل لها على الورقة.)
    if (sourceRuns.length == 1 &&
        sourceRuns.single.isText &&
        sourceRuns.single.text == text) {
      return _directionalTextXml(
        text,
        properties,
        style: sourceRuns.single.style,
        forceRtl: forceRtl,
      );
    }
    final mathRunProperties = _mathRunProperties(runProperties);
    final ltrMathProperties = properties.withRtl(false).toXml();
    final buffer = StringBuffer();
    for (final run in sourceRuns) {
      if (run.text.isEmpty) {
        continue;
      }
      if (run.isMath) {
        if (run.text.trim().isEmpty) {
          continue;
        }
        final math = OmmlFromEquation.mathZoneXml(
          run.text,
          fontSizePt: fontSizePt,
          extraRunProperties: mathRunProperties,
        );
        if (math != null) {
          // المنطقة الرياضية ابن مباشر للفقرة (لا داخل <w:r>): تُدرج كما هي
          // بجانب الجريانات، فتنزل حيث نزل $...$ في الجملة تماماً.
          buffer.write(math);
          continue;
        }
        if (mathRasterizer != null) {
          final index = _mathQueue.length;
          _mathQueue.add(_MathPlaceholder(run.text, fontSizePt));
          buffer.write('<w:r>$ltrMathProperties${_mathMarker(index)}</w:r>');
          continue;
        }
        buffer.write(
          '<w:r>$ltrMathProperties<w:t xml:space="preserve">'
          '${_escapeXml(EquationModel.readableText(run.text))}</w:t></w:r>',
        );
        continue;
      }
      // Split mixed Arabic/Latin text by strong-script runs. Source-authored
      // styling (for example the Quran font) remains inherited on each run.
      buffer.write(
        _directionalTextXml(
          run.text,
          properties,
          style: run.style,
          forceRtl: forceRtl,
        ),
      );
    }
    return buffer.toString();
  }

  /// تنسيق جريانات المعادلة الموروث من جيرانها: غامق/مائل/لون الفقرة فقط.
  ///
  /// يُنتقى ولا يُنسخ كاملاً: `<w:rtl/>` يفسد ترتيب محارف الرياضيات (المنطقة
  /// الرياضية LTR مستقلة بطبيعتها)، و`w:sz` يرسله المُصدِّر من [fontSizePt]،
  /// و`w:rFonts` يُستبدل بخط الرياضيات الذي تطلبه OMML.
  static final RegExp _mathBoldPattern = RegExp('<w:b/>');
  static final RegExp _mathItalicPattern = RegExp('<w:i/>');
  static final RegExp _mathColorPattern =
      RegExp('<w:color w:val="[0-9A-Fa-f]{6}"/>');

  String _mathRunProperties(String runProperties) {
    if (runProperties.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    if (_mathBoldPattern.hasMatch(runProperties)) {
      buffer.write('<w:b/>');
    }
    if (_mathItalicPattern.hasMatch(runProperties)) {
      buffer.write('<w:i/>');
    }
    final color = _mathColorPattern.firstMatch(runProperties);
    final colorXml = color?.group(0);
    if (colorXml != null) {
      buffer.write(colorXml);
    }
    return buffer.toString();
  }

  /// علامة موضع صيغة داخل XML النص (نطاق خاص: لا يمسّها [_escapeXml]).
  static String _mathMarker(int index) => '\uE000$index\uE001';

  /// يرسم كل صيغ LaTeX المكتشفة ويستبدل علاماتها برسوم مضمّنة داخل الـ run
  /// نفسه؛ وما تعذّر رسمه يُكتب **نصاً رياضياً مقروءاً** (بلا أي كود LaTeX).
  Future<String> _resolveMath(String xml) async {
    if (_mathQueue.isEmpty) {
      return xml;
    }
    final cache = <String, MathRaster?>{};
    var resolved = xml;
    for (var index = 0; index < _mathQueue.length; index++) {
      final placeholder = _mathQueue[index];
      final key = '${placeholder.latex}|${placeholder.fontSizePt}';
      final hasCached = cache.containsKey(key);
      final raster = hasCached
          ? cache[key]
          : (cache[key] = await _rasterizeMath(placeholder));
      final marker = _mathMarker(index);
      resolved = resolved.replaceAll(
        marker,
        raster == null
            ? '<w:t xml:space="preserve">'
                '${_escapeXml(EquationModel.readableText(placeholder.latex))}</w:t>'
            : _drawingXml(raster.pngBytes, raster.widthPt, raster.heightPt),
      );
    }
    return resolved;
  }

  Future<MathRaster?> _rasterizeMath(_MathPlaceholder placeholder) async {
    final rasterizer = mathRasterizer;
    if (rasterizer == null) {
      return null;
    }
    try {
      return await rasterizer(placeholder.latex, placeholder.fontSizePt);
    } catch (_) {
      return null;
    }
  }

  static String _escapeXml(String input) {
    final validCharacters = StringBuffer();
    final normalizedInput = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    for (final rune in normalizedInput.runes) {
      final isValidXmlCharacter = rune == 0x9 ||
          rune == 0xA ||
          rune == 0xD ||
          (rune >= 0x20 && rune <= 0xD7FF) ||
          (rune >= 0xE000 && rune <= 0xFFFD) ||
          (rune >= 0x10000 && rune <= 0x10FFFF);
      if (isValidXmlCharacter) {
        validCharacters.writeCharCode(rune);
      }
    }

    return validCharacters
        .toString()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('\n', '</w:t><w:br/><w:t xml:space="preserve">');
  }
}

/// صيغة LaTeX واحدة التُقطت من نص الفقرة قبل رسمها.
class _MathPlaceholder {
  const _MathPlaceholder(this.latex, this.fontSizePt);

  final String latex;

  /// حجم خط المعادلة بالنقاط (نصف حجم Word) — يوافق رسم PDF نفسه.
  final double fontSizePt;
}
