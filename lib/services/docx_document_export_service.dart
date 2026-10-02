import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../docx/omml_from_equation.dart';
import '../layout/blueprint/exam_blueprint.dart';
import '../layout/paper_metrics.dart';
import '../models/exam_canvas_geometry.dart';
import '../models/exam_document.dart';
import '../models/latex_plain_text.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_font.dart';
import '../models/paper_text_style.dart';
import '../models/tex_content.dart';
import '../pdf_engine/paginated_pdf_exam_engine.dart';
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

/// مخصّص تحويل صيغة LaTeX إلى صورة نقطية (يُمرَّر من الواجهة حيث يتوفر
/// مسجّل الرسم؛ انظر `MathImageRenderer`).
///
/// يعيد [MathRaster] أو `null` عند التعذّر (فيكتب المصدر نص الصيغة كما هو).
typedef MathRasterizer = Future<MathRaster?> Function(
  String latex,
  double fontSizePt,
);

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
    List<List<String>>? pageAssignments,
    Uint8List? frameImage,
  }) async {
    final bytes = await buildDocumentDocxBytes(
      document: document,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      pageAssignments: pageAssignments,
      frameImage: frameImage,
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
    List<List<String>>? pageAssignments,
    Uint8List? frameImage,
  }) async {
    // صورة الإطار تُقرأ من مسارها عند عدم تمريرها (التصدير من المعاينة).
    final frame = document.settings.pageBorder
        ? (frameImage ?? await PageFrameStore.read(document.settings.frameImagePath))
        : null;
    final builder = _DocxBuilder(
      document: document,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      pageAssignments: pageAssignments,
      frameImage: frame,
    );
    await builder.build();
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

/// بانِي مستند Word الداخلي (يجمع الصور أثناء بناء XML).
class _DocxBuilder {
  _DocxBuilder({
    required this.document,
    required this.shapeRasterizer,
    required this.mathRasterizer,
    required this.pageAssignments,
    required this.frameImage,
  }) : blueprint = ExamBlueprint.from(document);

  final ExamDocument document;
  final ExamBlueprint blueprint;
  final ShapeRasterizer? shapeRasterizer;
  final MathRasterizer? mathRasterizer;
  final List<List<String>>? pageAssignments;

  /// صورة PNG الإطار (`null` = إطار متجه عند تفعيل «إطار حول الصفحة»).
  final Uint8List? frameImage;

  final List<_EmbeddedImage> images = <_EmbeddedImage>[];
  int _drawingId = 1;

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
    final body = StringBuffer();
    body.write(_buildHeaderTable());
    final headerSpacingAfter = (PaperMetrics.pt(PaperMetrics.blockSpacingPx) * 20).round();
    body.write('<w:p><w:pPr><w:spacing w:after="$headerSpacingAfter"/></w:pPr></w:p>');
    final questionPages = await _resolvedQuestionPages();
    for (var pageIndex = 0; pageIndex < questionPages.length; pageIndex++) {
      if (pageIndex > 0) {
        _writePageBreak(body);
      }
      await _buildFloatingElementsForPage(
        body,
        pageIndex,
        pageCount: questionPages.length,
      );
      final pageQuestions = questionPages[pageIndex];
      for (var index = 0; index < pageQuestions.length; index++) {
        final question = pageQuestions[index];
        await _buildQuestion(body, question);
        if (index < pageQuestions.length - 1) {
          _writeQuestionSpacing(body, question.model.spacingAfter);
        }
      }
    }
    // التذييل بعد آخر سؤال مباشرةً، مثبّتاً أسفل آخر صفحة.
    _buildFooterTable(body);

    // بعد اكتمال كل النصوص: تُرسم صيغ LaTeX ($...$ و$$...$$) وتُستبدل
    // علاماتها برسوم مضمّنة — قبل بناء قوائم الصور في الحزمة.
    final resolvedBody = await _resolveMath(body.toString());

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
    var candidate = pageAssignments;
    var validAssignments = candidate != null && candidate.isNotEmpty;
    if (candidate != null) {
      final assignedIds = <String>{};
      for (final page in candidate) {
        for (final id in page) {
          if (!questionsById.containsKey(id) || !assignedIds.add(id)) {
            validAssignments = false;
          }
        }
      }
      validAssignments = validAssignments &&
          assignedIds.length == expectedIds.length &&
          assignedIds.containsAll(expectedIds);
    }
    if (!validAssignments) {
      candidate = await PaginatedPdfExamEngine().resolveQuestionPages(
        document: document,
      );
    }

    final pageIds = candidate!.map((page) => List<String>.of(page)).toList(growable: true);
    if (pageIds.isEmpty) {
      pageIds.add(<String>[]);
    }
    return pageIds
        .map((page) => page.map((id) => questionsById[id]!).toList(growable: false))
        .toList(growable: false);
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
      await _buildFloatingElement(body, element, pageAnchored: true);
    }
  }

  /// يُصدّر العناصر المرتبطة بالسؤال [questionId] داخل فقرات السؤال نفسه
  /// (مرساة نسبية للفقرة) — فيبقى كل عنصر مع سؤاله.
  Future<void> _buildOwnedElements(StringBuffer body, String questionId) async {
    for (final element in document.floatingElements) {
      if (element.ownerQuestionId != questionId) {
        continue;
      }
      await _buildFloatingElement(body, element, pageAnchored: false);
    }
  }

  /// يصدّر عنصراً عائماً واحداً: مربع نص / معادلة / صورة / شكل.
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
      final label = element.label.trim();
      if (label.isEmpty) {
        return;
      }
      final mathZone = _formulaMathZone(element);
      if (mathZone != null) {
        // معادلة Word أصلية داخل الإطار العائم نفسه: حدّ الصندوق وموضعه
        // وحجم خطّه كما هي، والمعادلة داخله قابلة للتحرير بلا صورة.
        _buildTextBox(
          body,
          element,
          floatingOnPage: true,
          pageAnchored: pageAnchored,
          mathOverride: mathZone,
        );
        return;
      }
      final boxWidthPt = PaperMetrics.pt(element.width);
      final boxHeightPt = PaperMetrics.pt(element.height);
      final raster = await _rasterizeMath(_MathPlaceholder(label, boxHeightPt));
      if (raster == null || raster.pngBytes.isEmpty) {
        // تعذّر ترسيم المعادلة: تُكتب نصاً رياضياً مقروءاً بدل كودها.
        _buildTextBox(
          body,
          element,
          floatingOnPage: true,
          pageAnchored: pageAnchored,
          textOverride: LatexPlainText.of(label),
        );
        return;
      }
      var widthPt = boxWidthPt;
      var heightPt = boxHeightPt;
      if (raster.widthPt > 0 && raster.heightPt > 0 && widthPt > 0 && heightPt > 0) {
        final scale = math.min(
          math.min(widthPt / raster.widthPt, heightPt / raster.heightPt),
          2.0,
        );
        widthPt = raster.widthPt * scale;
        heightPt = raster.heightPt * scale;
      }
      final widthPx = PaperMetrics.px(widthPt);
      final heightPx = PaperMetrics.px(heightPt);
      _writeAnchoredImageParagraph(
        body,
        raster.pngBytes,
        widthPt,
        heightPt,
        dx: element.dx + (element.width - widthPx) / 2,
        dy: element.dy + (element.height - heightPx) / 2,
        rotationDegrees: element.rotationDegrees,
        pageAnchored: pageAnchored,
      );
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
          size: 34,
          font: PaperFont.amiri,
          applyHeaderStyle: false,
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
  /// اختاره المدرس (خط/حجم/عريض/مائل/تسطير/لون) يُطبَّق ما لم يُطلب غيره.
  String _headerParagraph(
    String text, {
    required String alignment,
    bool bold = false,
    int size = 22,
    PaperFont? font,
    bool applyHeaderStyle = true,
  }) {
    final style = applyHeaderStyle ? document.header.style : PaperTextStyle.empty;
    final effectiveBold = style.bold ?? bold;
    final effectiveSize = style.fontSize != null
        ? (style.fontSize! * 2).round().clamp(12, 96)
        : (size * document.settings.fontScale).round().clamp(12, 96);
    final fontName = DocxDocumentExportService._fontName(
      font ?? style.font ?? document.settings.defaultFont,
    );
    final color = style.colorHex;
    final line = (240 * document.settings.lineSpacing).round();
    final runProperties = '<w:rPr><w:rtl/>${effectiveBold ? '<w:b/>' : ''}'
        '${style.italic == true ? '<w:i/>' : ''}'
        '${style.underline == true ? '<w:u w:val="single"/>' : ''}'
        '${color == null ? '' : '<w:color w:val="$color"/>'}'
        '<w:sz w:val="$effectiveSize"/>'
        '<w:rFonts w:ascii="$fontName" w:hAnsi="$fontName" w:cs="$fontName"/></w:rPr>';
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$alignment"/>'
        '<w:spacing w:line="$line" w:lineRule="auto"/></w:pPr>'
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
      return '${_headerParagraph(source.title, alignment: 'center', bold: true)}'
          '${_headerParagraph(source.nameLine, alignment: 'center')}';
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
      '${cell(middle, phrase == null ? '<w:p/>' : _headerParagraph(phrase, alignment: 'center', bold: true))}'
      '${cell(side, signature(data.primary))}'
      '</w:tr></w:tbl>'
      // فقرة مرساة صغيرة تتبع الجدول العائم (لا تأخذ مساحة تُذكر).
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr></w:p>',
    );
  }

  // ------------------------------- الأسئلة -------------------------------

  Future<void> _buildQuestion(StringBuffer body, QuestionBlueprint data) async {
    final question = data.model;
    final bodyStyle = question.style.copyWith(color: () => null);
    final titleStyle = question.style.copyWith(
      align: () => question.titleAlign ?? question.style.align,
      color: () => question.effectiveTitleColor,
    );
    // الترتيب مطابق للوحة المعاينة ومحرك الـ PDF حرفياً:
    // القسم ← سطر العنوان ← النص ← نقاط السؤال ← الفروع.
    if (data.section != null) {
      _writeParagraph(
        body,
        data.section!,
        bold: true,
        size: 24,
        before: 40,
        after: 40,
      );
    }
    _writeStyledParagraph(
      body,
      data.title.line,
      style: titleStyle,
      bold: true,
      size: 26,
      color: titleStyle.colorHex,
      before: 180,
      after: 60,
      border: question.showFrame,
    );
    if (data.body != null) {
      _writeStyledParagraph(
        body,
        data.body!,
        style: bodyStyle.copyWith(
          align: () => question.bodyAlign ?? question.style.align,
        ),
        size: 24,
        before: question.style.paragraphSpacing == null ? 40 : 0,
        after: 40,
      );
    }
    _writePoints(body, data.points, style: bodyStyle, indent: 800);
    for (final branch in data.branches) {
      await _buildBranch(
        body,
        branch,
        questionParagraphSpacing: question.style.paragraphSpacing,
      );
    }
    await _buildAttachments(body, question.attachments);
    // العناصر المرتبطة بهذا السؤال تُكتب مع فقراته (مرساة نسبية للفقرة).
    await _buildOwnedElements(body, question.id);
    _buildDivider(body, question.dividerAfter);
  }

  /// نقاط مرقَّمة (داخل سؤال أو فرع) بتسلسلها المتصل — وتحت كل نقطة
  /// «اختيار من متعدد» سطر خياراتها. الفارغة تماماً تُحذف.
  void _writePoints(
    StringBuffer body,
    List<PointBlueprint> points, {
    required PaperTextStyle? style,
    required int indent,
  }) {
    for (final point in points) {
      if (!point.isPrintable) {
        continue;
      }
      final pointStyle =
          point.item.align != null ? style?.copyWith(align: () => point.item.align) : style;
      final before = style?.paragraphSpacing == null ? 30 : 0;
      if (point.line.trim().isNotEmpty) {
        _writeStyledParagraph(
          body,
          point.line,
          style: pointStyle,
          size: 22,
          indent: indent,
          before: before,
          after: 30,
        );
      }
      if (point.optionsLine.isNotEmpty) {
        _writeStyledParagraph(
          body,
          point.optionsLine,
          style: pointStyle,
          size: 22,
          indent: indent + 400,
          before: 0,
          after: 30,
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
      style: branch.style,
      size: 22,
      indent: 400,
      before: questionParagraphSpacing == null
          ? 40
          : _paragraphSpacingTwips(questionParagraphSpacing),
      after: 40,
      border: branch.showFrame,
    );
    if (data.body != null) {
      _writeStyledParagraph(
        body,
        data.body!,
        style: branch.style,
        size: 22,
        indent: 400,
        before: 0,
        after: 40,
      );
    }
    _writePoints(body, data.points, style: branch.style, indent: 800);
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
    for (final element in attachments) {
      if (globalElementIds.contains(element.id)) {
        continue;
      }
      if (element.isTextBox) {
        _buildTextBox(body, element);
        continue;
      }
      if (element.isFormula) {
        await _buildFormulaAttachment(body, element);
        continue;
      }
      if (element.type == FloatingElementType.image) {
        final bytes = element.bytes;
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        _embedImage(body, Uint8List.fromList(bytes), element.width, element.height);
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
    }
  }

  void _buildTextBox(
    StringBuffer body,
    FloatingElement element, {
    bool floatingOnPage = false,
    bool pageAnchored = true,
    String? textOverride,
    String? mathOverride,
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
    final runProperties =
        '<w:rPr>${document.layout.isLtr ? '' : '<w:rtl/>'}'
        '${element.textStyle.bold == true ? '<w:b/>' : ''}'
        '${element.textStyle.italic == true ? '<w:i/>' : ''}'
        '${element.textStyle.underline == true ? '<w:u w:val="single"/>' : ''}'
        '<w:sz w:val="$size"/><w:rFonts w:cs="$font"/></w:rPr>';
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
      '${mathOverride ?? _runsXml(text, runProperties, size / 2)}</w:p></w:tc></w:tr></w:tbl>',
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

  /// يضيف فقرة معادلة حرة ([FloatingElementType.formula]) إلى المرفقات:
  /// تُصدَّر أولاً **معادلة Word أصلية** (`m:oMathPara` في فقرة موسَّطة؛
  /// انظر [_formulaMathZone]) — فإن تعذّر تمثيلها بُنيةً رُسمت بمحرك المعاينة
  /// بمقاسها على الورقة (تصغير فقط حتى لا تتشوّه ولا تفقد الحدّة)، وإن تعذّر
  /// رسمها كُتبت نصاً رياضياً مقروءاً.
  Future<void> _buildFormulaAttachment(
    StringBuffer body,
    FloatingElement element,
  ) async {
    final label = element.label.trim();
    if (label.isEmpty) {
      return;
    }
    final mathZone = _formulaMathZone(element);
    if (mathZone != null) {
      // معادلة Word حقيقية في فقرة مستقلة (محاذاة كما في باقي المرفقات).
      body.write(
        '<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}'
        '<w:jc w:val="center"/><w:spacing w:before="60" w:after="60"/>'
        '</w:pPr>$mathZone</w:p>',
      );
      return;
    }
    final boxWidthPt = PaperMetrics.pt(element.width);
    final boxHeightPt = PaperMetrics.pt(element.height);
    // حجم خط الرسم يتبع ارتفاع الصندوق: الرسم يخرج قريباً من مقاسه النهائي
    // فلا يحتاج تكبيراً يُفقد الحدّة.
    final raster = await _rasterizeMath(_MathPlaceholder(label, boxHeightPt));
    if (raster == null || raster.pngBytes.isEmpty) {
      _writeParagraph(
        body,
        '\$$label\$',
        italic: true,
        color: '6B7280',
        alignment: 'center',
        before: 60,
        after: 60,
      );
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

  void _writeStyledParagraph(
    StringBuffer body,
    String text, {
    PaperTextStyle? style,
    bool bold = false,
    int size = 22,
    String? color,
    int? indent,
    int? before,
    int? after,
    bool border = false,
  }) {
    _writeParagraph(
      body,
      text,
      bold: style?.bold ?? bold,
      italic: style?.italic ?? false,
      underline: style?.underline ?? false,
      size: style?.fontSize != null
          ? (style!.fontSize! * 2).round().clamp(12, 96)
          : size,
      // الحجم المخصص لعنصر بعينه مطلق، وحجم الأساس يُقاس بمعامل الورقة.
      scaleSize: style?.fontSize == null,
      border: border,
      color: color ?? style?.colorHex,
      indent: indent,
      before: before,
      after: style?.paragraphSpacing == null
          ? after
          : _paragraphSpacingTwips(style!.paragraphSpacing!),
      lineHeight: style?.lineHeight,
      alignment: _wordAlign(style?.align),
      font: DocxDocumentExportService._fontName(
        style?.font ?? document.settings.defaultFont,
      ),
    );
  }

  static String _wordAlign(PaperAlign? align) {
    switch (align) {
      case null:
      case PaperAlign.start:
        return 'right';
      case PaperAlign.center:
        return 'center';
      case PaperAlign.end:
        return 'left';
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
    String alignment = 'right',
    String? font,
  }) {
    final effectiveSize = scaleSize
        ? (size * document.settings.fontScale).round().clamp(12, 96)
        : size.clamp(12, 96);
    // تباعد أسطر العنصر المخصص يسود، وإلا العام من إعدادات الورقة (240 = مفرد).
    final line = (240 * (lineHeight ?? document.settings.lineSpacing)).round();
    body.write('<w:p><w:pPr>${document.layout.isLtr ? '' : '<w:bidi/>'}<w:jc w:val="$alignment"/>');
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
      body.write('<w:ind w:right="$indent"/>');
    }
    body.write(
      '<w:spacing${before == null ? '' : ' w:before="$before"'}${after == null ? '' : ' w:after="$after"'} w:line="$line" w:lineRule="auto"/>',
    );
    final runProperties = StringBuffer('<w:rPr>${document.layout.isLtr ? '' : '<w:rtl/>'}');
    if (bold) {
      runProperties.write('<w:b/>');
    }
    if (italic) {
      runProperties.write('<w:i/>');
    }
    if (underline) {
      runProperties.write('<w:u w:val="single"/>');
    }
    if (highlight) {
      runProperties.write('<w:highlight w:val="yellow"/>');
    }
    if (color != null) {
      runProperties.write('<w:color w:val="$color"/>');
    }
    runProperties.write('<w:sz w:val="$effectiveSize"/><w:rFonts w:cs="${font ?? DocxDocumentExportService._fontName(document.settings.defaultFont)}"/></w:rPr>');
    body.write('</w:pPr>');
    body.write(_runsXml(text, runProperties.toString(), effectiveSize / 2));
    body.write('</w:p>');
  }

  /// يبني مقاطع الفقرة: نص عادي ككتلة `<w:r>` واحدة أو أكثر، وصيغ LaTeX
  /// **معادلات Word أصلية** `<m:oMath>` داخل الفقرة نفسها (تُحرَّر في Word
  /// كما تُحرَّر من أداتها، بلا صورة) — انظر [OmmlFromEquation].
  ///
  /// عند تعذّر تمثيل صيغة بُنيةً (مصفوفة، أسطر متعددة…) تُرسَم تلك الصيغة
  /// وحدها بمعامل [mathRasterizer] — أي بمحرك المعاينة نفسه — بعلامة موضع
  /// مؤقتة يستبدلها [_resolveMath] بالرسم بعد رسمه (فتبقى في مكانها من
  /// السطر وبالترتيب نفسه). وبدون مرسّم تُكتب نصاً رياضياً مقروءاً، وهو
  /// آخر ارتداد: لا يظهر كود LaTeX الخام في أي ملف.
  String _runsXml(String text, String runProperties, double fontSizePt) {
    if (!TexContent.containsMath(text)) {
      return '<w:r>$runProperties<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r>';
    }
    final mathRunProperties = _mathRunProperties(runProperties);
    final buffer = StringBuffer();
    for (final segment in TexContent.split(text)) {
      if (segment.isMath && segment.text.trim().isNotEmpty) {
        final math = OmmlFromEquation.mathZoneXml(
          segment.text,
          fontSizePt: fontSizePt,
          extraRunProperties: mathRunProperties,
        );
        if (math != null) {
          // المنطقة الرياضية ابن مباشر للفقرة (لا داخل <w:r>): تُدرج كما هي
          // بجانب الجريانات، فتنزل حيث نزلت $...$ في الجملة تماماً.
          buffer.write(math);
          continue;
        }
        if (mathRasterizer != null) {
          final index = _mathQueue.length;
          _mathQueue.add(_MathPlaceholder(segment.text, fontSizePt));
          buffer.write('<w:r>$runProperties${_mathMarker(index)}</w:r>');
          continue;
        }
        buffer.write(
          '<w:r>$runProperties<w:t xml:space="preserve">'
          '${_escapeXml(LatexPlainText.of(segment.text))}</w:t></w:r>',
        );
        continue;
      }
      if (segment.text.isEmpty) {
        continue;
      }
      buffer.write(
        '<w:r>$runProperties<w:t xml:space="preserve">${_escapeXml(segment.text)}</w:t></w:r>',
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
                '${_escapeXml(LatexPlainText.of(placeholder.latex))}</w:t>'
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
