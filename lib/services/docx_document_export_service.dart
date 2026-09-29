import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../layout/paper_metrics.dart';
import '../models/branch_item.dart';
import '../models/branch_model.dart';
import '../models/exam_canvas_geometry.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_font.dart';
import '../models/paper_text_style.dart';
import '../models/question_model.dart';
import '../models/question_type.dart';
import '../models/tex_content.dart';
import '../pdf_engine/paginated_pdf_exam_engine.dart';
import 'export_file_service.dart';

/// مخصّص تحويل شكل متجه إلى صورة نقطية (لأن Word لا يقبل SVG الداخلي
/// بنفس البساطة؛ يُمرَّر من الواجهة حيث يتوفر مسجّل الرسم).
///
/// يعيد بايتات PNG/JPG أو `null` عند التعذّر (يُكتب عنصر نصي بديل).
typedef ShapeRasterizer = Future<Uint8List?> Function(
  FloatingElement element,
  double widthPx,
  double heightPx,
);

/// معادلة LaTeX مرسومة صورةً: بايتات PNG بمقاساتها بالنقاط (pt).
class MathRaster {
  const MathRaster({
    required this.pngBytes,
    required this.widthPt,
    required this.heightPt,
  });

  final Uint8List pngBytes;
  final double widthPt;
  final double heightPt;
}

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
/// يحافظ قدر الإمكان على: الترويسة، ترتيب الأسئلة والفروع والنقاط،
/// النصوص، الدرجات، المحاذاة، الخطوط، الفواصل، مربعات النص، والصور
/// (مضمّنة فعلياً) — والأشكال تُرسم صوراً عبر [ShapeRasterizer]، وصيغ
/// LaTeX (`$...$` و`$$...$$`) تُرسم معادلاتٍ عبر [MathRasterizer] بدل أن
/// تظهر أكواداً خامة.
class DocxDocumentExportService {
  const DocxDocumentExportService._();

  /// أقصى عرض لصورة داخل النص بالنقاط (يقارب عرض محتوى A4).
  static const double _maxImageWidthPt = 430;

  static Future<File> exportDocumentToDocx({
    required ExamDocument document,
    bool isTeacherVersion = false,
    String? fileName,
    Directory? outputDirectory,
    ShapeRasterizer? shapeRasterizer,
    MathRasterizer? mathRasterizer,
    List<List<String>>? pageAssignments,
  }) async {
    final bytes = await buildDocumentDocxBytes(
      document: document,
      isTeacherVersion: isTeacherVersion,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      pageAssignments: pageAssignments,
    );
    final suffix = isTeacherVersion ? 'نموذج_الإجابة' : 'ورقة_الامتحان';
    return ExportFileService.writeExportFile(
      baseName: fileName ?? '${document.name}_$suffix',
      extension: 'docx',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  static Future<Uint8List> buildDocumentDocxBytes({
    required ExamDocument document,
    bool isTeacherVersion = false,
    ShapeRasterizer? shapeRasterizer,
    MathRasterizer? mathRasterizer,
    List<List<String>>? pageAssignments,
  }) async {
    final builder = _DocxBuilder(
      document: document,
      isTeacherVersion: isTeacherVersion,
      shapeRasterizer: shapeRasterizer,
      mathRasterizer: mathRasterizer,
      pageAssignments: pageAssignments,
    );
    await builder.build();
    final archive = Archive();
    _addTextFile(archive, '[Content_Types].xml', builder.contentTypesXml);
    _addTextFile(archive, '_rels/.rels', _globalRelationshipsXml);
    _addTextFile(archive, 'word/_rels/document.xml.rels', builder.documentRelationshipsXml);
    _addTextFile(archive, 'word/styles.xml', _stylesXml(document));
    _addTextFile(archive, 'word/document.xml', builder.documentXml);
    if (builder.footerXml != null) {
      _addTextFile(archive, 'word/footer1.xml', builder.footerXml!);
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
        <w:bidi/>
        <w:jc w:val="right"/>
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
    required this.isTeacherVersion,
    required this.shapeRasterizer,
    required this.mathRasterizer,
    required this.pageAssignments,
  });

  final ExamDocument document;
  final bool isTeacherVersion;
  final ShapeRasterizer? shapeRasterizer;
  final MathRasterizer? mathRasterizer;
  final List<List<String>>? pageAssignments;

  final List<_EmbeddedImage> images = <_EmbeddedImage>[];
  int _drawingId = 1;

  /// صيغ LaTeX المكتشفة في النصوص عند كتابة الفقرات، بترتيب ظهورها — تُرسم
  /// وتُستبدل علاماتها بعد اكتمال النص (انظر [_resolveMath]).
  final List<_MathPlaceholder> _mathQueue = <_MathPlaceholder>[];

  late final String documentXml;
  late final String contentTypesXml;
  late final String documentRelationshipsXml;

  /// تذييل ترقيم الصفحات (`null` = لا ترقيم حسب إعدادات الورقة).
  String? footerXml;

  static const String _footerRelationId = 'rIdFooter';

  Future<void> build() async {
    final body = StringBuffer();
    body.write(_buildHeaderTable());
    if (document.header.instructions.trim().isNotEmpty) {
      _writeParagraph(
        body,
        document.header.instructions.trim(),
        italic: true,
        color: '4B5563',
        alignment: 'center',
        before: 120,
        after: 80,
      );
    }
    if (document.header.notes.trim().isNotEmpty) {
      _writeParagraph(
        body,
        document.header.notes.trim(),
        italic: true,
        color: '4B5563',
        alignment: 'center',
        before: 40,
        after: 120,
      );
    }
    final headerSpacingAfter = (PaperMetrics.pt(PaperMetrics.blockSpacingPx) * 20).round();
    body.write(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" w:color="1E3A8A"/></w:pBdr>'
      '<w:spacing w:after="$headerSpacingAfter"/></w:pPr></w:p>',
    );
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
          _writeQuestionSpacing(body, question.spacingAfter);
        }
      }
    }

    // بعد اكتمال كل النصوص: تُرسم صيغ LaTeX ($...$ و$$...$$) وتُستبدل
    // علاماتها برسوم مضمّنة — قبل بناء قوائم الصور في الحزمة.
    final resolvedBody = await _resolveMath(body.toString());

    final marginTwips = (document.settings.marginMm / 25.4 * 1440).round();
    if (document.settings.showPageNumbers) {
      footerXml = _buildFooter();
    }
    documentXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>'
        '$resolvedBody'
        '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="$marginTwips" w:right="$marginTwips" w:bottom="$marginTwips" w:left="$marginTwips"/>'
        '${document.settings.pageBorder ? '<w:pgBorders w:offsetFrom="page"><w:top w:val="single" w:sz="12" w:space="24" w:color="1E3A8A"/><w:left w:val="single" w:sz="12" w:space="24" w:color="1E3A8A"/><w:bottom w:val="single" w:sz="12" w:space="24" w:color="1E3A8A"/><w:right w:val="single" w:sz="12" w:space="24" w:color="1E3A8A"/></w:pgBorders>' : ''}'
        '<w:bidi/>'
        '${footerXml == null ? '' : '<w:footerReference r:id="$_footerRelationId" w:type="default"/>'}'
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
    overrides.write('''
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>${footerXml == null ? '' : '\n  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'}
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
    if (footerXml != null) {
      rels.write(
        '\n  <Relationship Id="$_footerRelationId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>',
      );
    }
    rels.write('\n</Relationships>');
    documentRelationshipsXml = rels.toString();
  }

  Future<List<List<QuestionModel>>> _resolvedQuestionPages() async {
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final printableQuestions = document.questions
        .where((question) => question.hasExportableContent(
              teacher: isTeacherVersion,
              ignoredAttachmentIds: globalElementIds,
            ))
        .toList(growable: false);
    final questionsById = <String, QuestionModel>{
      for (final question in printableQuestions) question.id: question,
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
        isTeacherVersion: isTeacherVersion,
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
      final assignedPage = element.pageIndex.clamp(0, pageCount - 1).toInt();
      if (assignedPage != pageIndex || !seenIds.add(element.id)) {
        continue;
      }
      if (element.isTextBox) {
        _buildTextBox(body, element, floatingOnPage: true);
        continue;
      }
      if (element.isFormula) {
        final label = element.label.trim();
        if (label.isEmpty) {
          continue;
        }
        final boxWidthPt = PaperMetrics.pt(element.width);
        final boxHeightPt = PaperMetrics.pt(element.height);
        final raster = await _rasterizeMath(_MathPlaceholder(label, boxHeightPt));
        if (raster == null || raster.pngBytes.isEmpty) {
          _buildTextBox(
            body,
            element,
            floatingOnPage: true,
            textOverride: '\$$label\$',
          );
          continue;
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
        );
        continue;
      }
      if (element.isImage) {
        final bytes = element.bytes;
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        _writeAnchoredImageParagraph(
          body,
          Uint8List.fromList(bytes),
          PaperMetrics.pt(element.width),
          PaperMetrics.pt(element.height),
          dx: element.dx,
          dy: element.dy,
          rotationDegrees: element.rotationDegrees,
        );
        continue;
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
        );
      } else {
        _buildTextBox(
          body,
          element,
          floatingOnPage: true,
          textOverride: '[شكل: ${element.shape?.arabicLabel ?? 'شكل'}]',
        );
      }
    }
  }

  void _writeAnchoredImageParagraph(
    StringBuffer body,
    Uint8List bytes,
    double widthPt,
    double heightPt, {
    required double dx,
    required double dy,
    required double rotationDegrees,
  }) {
    if (bytes.isEmpty || widthPt <= 0 || heightPt <= 0) {
      return;
    }
    body.write(
      '<w:p><w:pPr><w:bidi/><w:spacing w:before="0" w:after="0" '
      'w:line="1" w:lineRule="exact"/></w:pPr>'
      '<w:r>${_positionedDrawingXml(bytes, widthPt, heightPt, dx: dx, dy: dy, rotationDegrees: rotationDegrees)}</w:r></w:p>',
    );
  }

  String _positionedDrawingXml(
    Uint8List bytes,
    double widthPt,
    double heightPt, {
    required double dx,
    required double dy,
    required double rotationDegrees,
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
    final physicalLeftPx = document.layout.isLtr
        ? dx
        : ExamCanvasGeometry.width - dx - widthPx;
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
    return '<w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" '
        'simplePos="0" relativeHeight="$id" behindDoc="0" locked="0" '
        'layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="page"><wp:posOffset>$xEmu</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="page"><wp:posOffset>$yEmu</wp:posOffset></wp:positionV>'
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

  /// تذييل ترقيم الصفحات («صفحة X من Y») بحقول Word الحية.
  String _buildFooter() {
    final layout = document.layout;
    final before = layout.isLtr ? 'Page ' : 'صفحة ';
    final middle = layout.isLtr ? ' of ' : ' من ';
    String run(String text) =>
        '<w:r><w:rPr><w:rtl/><w:sz w:val="18"/><w:color w:val="4B5563"/>'
        '<w:rFonts w:cs="${DocxDocumentExportService._fontName(document.settings.defaultFont)}"/>'
        '</w:rPr><w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r>';
    String field(String instruction) =>
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText xml:space="preserve"> $instruction </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '${run('1')}'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>'
        '${run(before)}${field('PAGE')}${run(middle)}${field('NUMPAGES')}'
        '</w:p>'
        '</w:ftr>';
  }

  // ------------------------------- الترويسة -------------------------------

  String _buildHeaderTable() {
    final header = document.header;
    final title = header.title.trim().isEmpty
        ? header.center.lines[1]
        : header.title.trim();
    // نموذج المعلم يُوسم باسمه؛ وورقة الطالب بلا أي عدّادات على الورقة
    // (لا الدرجة الكلية ولا عدد الأسئلة — الإجابة في دفتر الطالب).
    final versionLabel =
        isTeacherVersion ? 'نموذج الإجابة وتوزيع الدرجات للمعلم' : '';
    final titleAlign = header.style.align == null
        ? 'center'
        : _wordAlign(header.style.align);
    final borders = document.settings.headerBorder
        ? '''
    <w:tblBorders>
      <w:top w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:left w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:bottom w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:right w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
    </w:tblBorders>'''
        : '';

    return '''
<w:tbl>
  <w:tblPr>
    <w:tblW w:w="5000" w:type="pct"/>
    <w:bidiVisual/>$borders
  </w:tblPr>
  <w:tr>
    <w:tc>
      <w:tcPr><w:tcW w:w="1700" w:type="pct"/></w:tcPr>
      ${_tableCellLines(header.right.lines)}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1600" w:type="pct"/></w:tcPr>
      ${title.trim().isEmpty ? '' : _tableParagraph(title, bold: true, size: 28, alignment: titleAlign, color: '1E3A8A')}
      ${_tableParagraph(header.center.lines[0], alignment: 'center')}
      ${_tableParagraph(header.center.lines[2], alignment: 'center')}
      ${versionLabel.isEmpty ? '' : _tableParagraph(versionLabel, italic: true, alignment: 'center', color: 'DC2626')}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1700" w:type="pct"/></w:tcPr>
      ${_tableCellLines(header.left.lines)}
    </w:tc>
  </w:tr>
</w:tbl>
''';
  }

  String _tableCellLines(List<String> lines) {
    final buffer = StringBuffer();
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      buffer.write(_tableParagraph(line));
    }
    return buffer.toString();
  }

  String _tableParagraph(
    String text, {
    bool bold = false,
    bool italic = false,
    int size = 22,
    String alignment = 'right',
    String? color,
  }) {
    // تنسيق الترويسة (خط/حجم/عريض) كما صممه المدرس، مع قياس حجم الأساس
    // بمعامل الورقة العام وتباعد أسطرها.
    final headerStyle = document.header.style;
    final effectiveBold = headerStyle.bold ?? bold;
    final effectiveItalic = headerStyle.italic ?? italic;
    final effectiveSize = headerStyle.fontSize != null
        ? (headerStyle.fontSize! * 2).round().clamp(12, 96)
        : (size * document.settings.fontScale).round().clamp(12, 96);
    final font = DocxDocumentExportService._fontName(
      headerStyle.font ?? document.settings.defaultFont,
    );
    // محاذاة الترويسة كما حددها المدرس في الموديل تعلو الافتراضي العمودي
    // (يمين/وسط) — نفس ما تعرضه الشاشة بعد النقر على زر المحاذاة.
    final effectiveAlign = headerStyle.align != null
        ? _wordAlign(headerStyle.align)
        : alignment;
    final line = (240 * document.settings.lineSpacing).round();
    final runProperties =
        '<w:rPr><w:rtl/>${effectiveBold ? '<w:b/>' : ''}${effectiveItalic ? '<w:i/>' : ''}'
        '${headerStyle.underline == true ? '<w:u w:val="single"/>' : ''}'
        '${color == null ? '' : '<w:color w:val="$color"/>'}'
        '<w:sz w:val="$effectiveSize"/><w:rFonts w:cs="$font"/></w:rPr>';
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$effectiveAlign"/>'
        '<w:spacing w:line="$line" w:lineRule="auto"/></w:pPr>'
        '${_runsXml(text, runProperties, effectiveSize / 2)}'
        '</w:p>';
  }

  // ------------------------------- الأسئلة -------------------------------

  Future<void> _buildQuestion(StringBuffer body, QuestionModel question) async {
    final layout = document.layout;
    final questionIndex = document.indexOfQuestion(question.id);
    final bodyStyle = question.style.copyWith(color: () => null);
    final titleStyle = question.style.copyWith(
      align: () => question.titleAlign ?? question.style.align,
      color: () => question.effectiveTitleColor,
    );
    final titleColor = titleStyle.colorHex ?? '111827';
    final marksPart = document.settings.showQuestionMarks
        ? ' [${document.formatNumber(question.marks)} ${layout.marksUnit}]'
        : '';
    // الترتيب مطابق للوحة المعاينة ومحرك الـ PDF حرفياً:
    // القسم ← العنوان ← النص ← نقاط السؤال ← الفروع.
    if (question.category.trim().isNotEmpty) {
      _writeParagraph(
        body,
        question.category.trim(),
        bold: true,
        size: 24,
        color: '1E3A8A',
        before: 40,
        after: 40,
      );
    }
    _writeStyledParagraph(
      body,
      '${document.displayQuestionLabel(question)}$marksPart',
      style: titleStyle,
      bold: true,
      size: 26,
      color: titleColor,
      before: 180,
      after: 60,
      border: question.showFrame,
    );
    if (question.prompt.trim().isNotEmpty) {
      _writeStyledParagraph(
        body,
        question.prompt,
        style: bodyStyle.copyWith(
          align: () => question.promptAlign ?? question.style.align,
        ),
        size: 24,
        before: question.style.paragraphSpacing == null ? 40 : 0,
        after: 40,
      );
    }
    // نقاط السؤال المباشرة (1، 2، 3...) — نفس مسار نقاط الفرع في الطباعة.
    for (var i = 0; i < question.items.length; i++) {
      final item = question.items[i];
      if (!item.showsInExport(teacher: isTeacherVersion, trueFalse: false)) {
        continue;
      }
      _writeItemParagraph(
        body,
        item,
        i,
        style: bodyStyle,
        trueFalse: false,
        trueFalseFormat: question.trueFalseFormat,
      );
    }
    for (var index = 0; index < question.branches.length; index++) {
      await _buildBranch(
        body,
        question.branches[index],
        questionIndex,
        index,
        questionParagraphSpacing: question.style.paragraphSpacing,
      );
    }
    await _buildAttachments(body, question.attachments);
    _buildDivider(body, question.dividerAfter);
  }

  /// فقرة نقطة مرقَّمة (داخل سؤال أو فرع) — ترقيم تلقائي/مخصص + درجة +
  /// إجابة صح/خطأ في نموذج المعلم وحده.
  void _writeItemParagraph(
    StringBuffer body,
    BranchItem item,
    int index, {
    required PaperTextStyle? style,
    required bool trueFalse,
    String trueFalseFormat = 'words',
  }) {
    final layout = document.layout;
    final itemMarks = item.marks > 0
        ? ' [${document.formatNumber(item.marks)} ${layout.marksUnit}]'
        : '';
    var itemAnswer = '';
    if (isTeacherVersion && trueFalse && item.isCorrect != null) {
      if (trueFalseFormat == 'symbols') {
        itemAnswer = item.isCorrect! ? ' (✓)' : ' (✗)';
      } else {
        itemAnswer = layout.isLtr
            ? (item.isCorrect! ? ' (True)' : ' (False)')
            : (item.isCorrect! ? ' (صح)' : ' (خطأ)');
      }
    }
    final itemLabel = document.displayItemLabel(item, index);
    final chunks = <String>[
      if (itemLabel.isNotEmpty) itemLabel,
      if (item.text.trim().isNotEmpty) item.text,
    ];
    final line = '${chunks.join(' ')}$itemMarks$itemAnswer';
    if (line.trim().isEmpty) {
      return;
    }
    final itemStyle = item.align != null ? style?.copyWith(align: () => item.align) : style;
    _writeStyledParagraph(
      body,
      line,
      style: itemStyle,
      size: 22,
      indent: 800,
      before: style?.paragraphSpacing == null ? 30 : 0,
      after: 30,
    );
  }

  Future<void> _buildBranch(
    StringBuffer body,
    BranchModel branch,
    int questionIndex,
    int branchIndex, {
    double? questionParagraphSpacing,
  }) async {
    final layout = document.layout;
    final content = branch.content;
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    // الفرع الفارغ تماماً يُحذف من الملف كاملاً ولا يترك فقرات فارغة.
    if (!branch.hasExportableContent(
      teacher: isTeacherVersion,
      ignoredAttachmentIds: globalElementIds,
    )) {
      return;
    }
    final label = questionIndex >= 0
        ? document.displayBranchLabel(questionIndex, branchIndex)
        : layout.branchLabel(branchIndex);
    final marksSuffix = branch.marks > 0
        ? ' [${document.formatNumber(branch.marks)} ${layout.marksUnit}]'
        : '';
    final hasText = content.text.trim().isNotEmpty;
    _writeStyledParagraph(
      body,
      hasText ? '$label) ${content.text}$marksSuffix' : '$label)$marksSuffix',
      style: branch.style,
      size: 22,
      indent: 400,
      before: questionParagraphSpacing == null
          ? 40
          : _paragraphSpacingTwips(questionParagraphSpacing),
      after: 40,
      border: branch.showFrame,
    );
    for (var i = 0; i < content.items.length; i++) {
      final item = content.items[i];
      if (!item.showsInExport(
          teacher: isTeacherVersion,
          trueFalse: content.type == QuestionType.trueFalse)) {
        continue;
      }
      _writeItemParagraph(
        body,
        item,
        i,
        style: branch.style,
        trueFalse: content.type == QuestionType.trueFalse,
        trueFalseFormat: content.trueFalseFormat,
      );
    }
    // مطابقة اللوحة ومحرك PDF حرفياً (انظر BranchContent.hasPrintableTypeBody).
    if (content.hasPrintableTypeBody(teacher: isTeacherVersion)) {
      _buildTypeBody(body, content, branch.style);
    }
    await _buildAttachments(body, branch.attachments);
    _buildDivider(body, branch.dividerAfter);
  }

  void _buildTypeBody(
      StringBuffer body, BranchContent content, PaperTextStyle? style) {
    final alignment = _wordAlign(style?.align);
    // محاذاة الإجابة النموذجية/صح-خطأ لها نظيرها في الموديل (فقرة مستقلة
    // كما في Word) وترث محاذاة الفرع عند غيابها.
    final answerAlign = content.modelAnswerAlign != null
        ? _wordAlign(content.modelAnswerAlign)
        : alignment;
    final lineHeight = style?.lineHeight;
    final styleColor = style?.colorHex;
    switch (content.type) {
      case QuestionType.multipleChoice:
        // الخيارات الفارغة تُحذف، لكن التسميات تبقى بفهارسها الأصلية
        // (مطابقة اللوحة) ولا يعاد ترقيم المخصص منها أبداً.
        for (var i = 0; i < content.options.length; i++) {
          final option = content.options[i];
          if (option.text.trim().isEmpty) {
            continue;
          }
          final correct = isTeacherVersion && option.isCorrect;
          final optionLabel = document.displayOptionLabel(option, i);
          final prefix = optionLabel.isEmpty ? '' : '$optionLabel  ';
          _writeParagraph(
            body,
            '$prefix${option.text}${correct ? '  ✔ الإجابة الصحيحة' : ''}',
            bold: correct,
            size: 22,
            color: styleColor ?? (correct ? '065F46' : null),
            highlight: correct,
            indent: 800,
            before: style?.paragraphSpacing == null ? 30 : 0,
            after: style?.paragraphSpacing == null
                ? 30
                : _paragraphSpacingTwips(style!.paragraphSpacing!),
            alignment:
                option.align != null ? _wordAlign(option.align) : alignment,
            lineHeight: lineHeight,
          );
        }
      case QuestionType.trueFalse:
        // ورقة الطالب: الأسئلة فقط — بلا مساحة إجابة مولَّدة على الورقة.
        if (!isTeacherVersion || content.items.isNotEmpty) {
          return;
        }
        final answer = content.trueFalseAnswer;
        final answerStr = content.trueFalseFormat == 'symbols'
            ? (answer ? '✓' : '✗')
            : (answer ? 'صح' : 'خطأ');
        _writeParagraph(
          body,
          'الإجابة الصحيحة: $answerStr ✔',
          bold: true,
          size: 22,
          color: styleColor ?? '065F46',
          highlight: true,
          indent: 800,
          before: style?.paragraphSpacing == null ? 40 : 0,
          after: style?.paragraphSpacing == null
              ? 40
              : _paragraphSpacingTwips(style!.paragraphSpacing!),
          alignment: answerAlign,
          lineHeight: lineHeight,
        );
      case QuestionType.fillInTheBlank:
        if (!isTeacherVersion) {
          return;
        }
        if (content.modelAnswer.trim().isEmpty) {
          return;
        }
        _writeParagraph(
          body,
          'الإجابة النموذجية: ${content.modelAnswer.trim()}',
          bold: true,
          size: 22,
          color: styleColor ?? '065F46',
          highlight: true,
          indent: 800,
          before: style?.paragraphSpacing == null ? 40 : 0,
          after: style?.paragraphSpacing == null
              ? 40
              : _paragraphSpacingTwips(style!.paragraphSpacing!),
          alignment: answerAlign,
          lineHeight: lineHeight,
        );
      case QuestionType.definitions:
      case QuestionType.essay:
        if (isTeacherVersion) {
          if (content.modelAnswer.trim().isEmpty) {
            return;
          }
          _writeParagraph(
            body,
            'الإجابة النموذجية وعناصر التقييم: ${content.modelAnswer.trim()}',
            bold: true,
            size: 22,
            color: styleColor ?? '065F46',
            indent: 800,
            before: style?.paragraphSpacing == null ? 40 : 0,
            after: style?.paragraphSpacing == null
                ? 40
                : _paragraphSpacingTwips(style!.paragraphSpacing!),
            alignment: answerAlign,
            lineHeight: lineHeight,
          );
          return;
        }
        // ورقة الطالب للأسئلة المقالية: بلا أسطر إجابة مولَّدة (الإجابة في دفتر الطالب).
    }
  }

  void _buildDivider(StringBuffer body, PaperDivider? divider) {
    if (divider == null) {
      return;
    }
    final width = (divider.thickness * 8).round().clamp(4, 48);
    body.write(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="$width" w:space="4" w:color="1E3A8A"/></w:pBdr>'
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
    final runProperties =
        '<w:rPr><w:rtl/>'
        '${element.textStyle.bold == true ? '<w:b/>' : ''}'
        '${element.textStyle.italic == true ? '<w:i/>' : ''}'
        '${element.textStyle.underline == true ? '<w:u w:val="single"/>' : ''}'
        '<w:sz w:val="$size"/><w:rFonts w:cs="$font"/></w:rPr>';
    final widthTwips = (PaperMetrics.pt(element.width) * 20).round();
    final heightTwips = (PaperMetrics.pt(element.height) * 20).round();
    final physicalLeftPx = document.layout.isLtr
        ? element.dx
        : ExamCanvasGeometry.width - element.dx - element.width;
    final xTwips = (PaperMetrics.pt(physicalLeftPx) * 20).round();
    final yTwips = (PaperMetrics.pt(element.dy) * 20).round();
    final tableWidth = floatingOnPage
        ? '<w:tblW w:w="$widthTwips" w:type="dxa"/>'
        : '<w:tblW w:w="5000" w:type="pct"/>';
    final tablePosition = floatingOnPage
        ? '<w:tblpPr w:horzAnchor="page" w:vertAnchor="page" '
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
      '<w:p><w:pPr><w:bidi/><w:jc w:val="$align"/>'
      '<w:spacing w:line="$line" w:lineRule="auto"/></w:pPr>'
      '${_runsXml(text, runProperties, size / 2)}</w:p></w:tc></w:tr></w:tbl>',
    );
  }

  void _embedImage(StringBuffer body, Uint8List bytes, double widthPx, double heightPx) {
    final widthPt = PaperMetrics.pt(widthPx);
    final heightPt = PaperMetrics.pt(heightPx);
    if (widthPt <= 0 || heightPt <= 0) {
      return;
    }
    body.write(
      '<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>'
      '<w:r>${_drawingXml(bytes, widthPt, heightPt)}</w:r></w:p>',
    );
  }

  /// يضيف فقرة معادلة حرة ([FloatingElementType.formula]) كصورة معادلة
  /// بمقاسها على الورقة (تصغير فقط حتى لا تتشوّه ولا تفقد الحدّة) — وإن
  /// تعذّر رسمها كُتبت الصيغة نصاً.
  Future<void> _buildFormulaAttachment(
    StringBuffer body,
    FloatingElement element,
  ) async {
    final label = element.label.trim();
    if (label.isEmpty) {
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
      '<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>'
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
    body.write('<w:p><w:pPr><w:bidi/><w:jc w:val="$alignment"/>');
    if (border) {
      body.write(
        '<w:pBdr><w:top w:val="single" w:sz="6" w:space="4" w:color="1E3A8A"/>'
        '<w:left w:val="single" w:sz="6" w:space="4" w:color="1E3A8A"/>'
        '<w:bottom w:val="single" w:sz="6" w:space="4" w:color="1E3A8A"/>'
        '<w:right w:val="single" w:sz="6" w:space="4" w:color="1E3A8A"/>'
        '</w:pBdr>',
      );
    }
    if (indent != null) {
      body.write('<w:ind w:right="$indent"/>');
    }
    body.write(
      '<w:spacing${before == null ? '' : ' w:before="$before"'}${after == null ? '' : ' w:after="$after"'} w:line="$line" w:lineRule="auto"/>',
    );
    final runProperties = StringBuffer('<w:rPr><w:rtl/>');
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
  /// كعلامة موضع مؤقتة يُستبدلها [MathRasterizer] برسم المعادلة بعد رسمها
  /// (انظر [_resolveMath]) — فيظهر الرمز المرسوم مكان `$...$` تماماً،
  /// وبالترتيب نفسه داخل السطر.
  String _runsXml(String text, String runProperties, double fontSizePt) {
    if (mathRasterizer == null || !TexContent.containsMath(text)) {
      return '<w:r>$runProperties<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r>';
    }
    final buffer = StringBuffer();
    for (final segment in TexContent.split(text)) {
      if (segment.isMath && segment.text.trim().isNotEmpty) {
        final index = _mathQueue.length;
        _mathQueue.add(_MathPlaceholder(segment.text, fontSizePt));
        buffer.write('<w:r>$runProperties${_mathMarker(index)}</w:r>');
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

  /// علامة موضع صيغة داخل XML النص (نطاق خاص: لا يمسّها [_escapeXml]).
  static String _mathMarker(int index) => '\uE000$index\uE001';

  /// يرسم كل صيغ LaTeX المكتشفة ويستبدل علاماتها برسوم مضمّنة داخل الـ run
  /// نفسه؛ وما تعذّر رسمه يُكتب نصاً كما كان (سلوك التصدير قبل إضافة الرسم).
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
            ? '<w:t xml:space="preserve">${_escapeXml(placeholder.latex)}</w:t>'
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
