import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../layout/paper_metrics.dart';
import '../models/branch_model.dart';
import '../models/exam_document.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_font.dart';
import '../models/paper_text_style.dart';
import '../models/question_model.dart';
import '../models/question_type.dart';
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

/// صورة مضمّنة في حزمة docx (أصلية أو مرسومة من شكل).
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
/// (مضمّنة فعلياً) — والأشكال تُرسم صوراً عبر [ShapeRasterizer] عند توفره.
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
  }) async {
    final bytes = await buildDocumentDocxBytes(
      document: document,
      isTeacherVersion: isTeacherVersion,
      shapeRasterizer: shapeRasterizer,
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
  }) async {
    final builder = _DocxBuilder(
      document: document,
      isTeacherVersion: isTeacherVersion,
      shapeRasterizer: shapeRasterizer,
    );
    await builder.build();
    final archive = Archive();
    _addTextFile(archive, '[Content_Types].xml', builder.contentTypesXml);
    _addTextFile(archive, '_rels/.rels', _globalRelationshipsXml);
    _addTextFile(archive, 'word/_rels/document.xml.rels', builder.documentRelationshipsXml);
    _addTextFile(archive, 'word/styles.xml', _stylesXml(document));
    _addTextFile(archive, 'word/document.xml', builder.documentXml);
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
  });

  final ExamDocument document;
  final bool isTeacherVersion;
  final ShapeRasterizer? shapeRasterizer;

  final List<_EmbeddedImage> images = <_EmbeddedImage>[];
  int _drawingId = 1;

  late final String documentXml;
  late final String contentTypesXml;
  late final String documentRelationshipsXml;

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
    body.write(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" w:color="1E3A8A"/></w:pBdr><w:spacing w:after="240"/></w:pPr></w:p>',
    );
    for (final question in document.questions) {
      await _buildQuestion(body, question);
    }

    final marginTwips = (document.settings.marginMm / 25.4 * 1440).round();
    documentXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>'
        '${body.toString()}'
        '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="$marginTwips" w:right="$marginTwips" w:bottom="$marginTwips" w:left="$marginTwips"/>'
        '<w:bidi/>'
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
    rels.write('\n</Relationships>');
    documentRelationshipsXml = rels.toString();
  }

  // ------------------------------- الترويسة -------------------------------

  String _buildHeaderTable() {
    final header = document.header;
    final layout = document.layout;
    final title = header.title.trim().isEmpty
        ? header.center.lines[1]
        : header.title.trim();
    final versionLabel = isTeacherVersion
        ? 'نموذج الإجابة وتوزيع الدرجات للمعلم'
        : 'عدد الأسئلة: ${document.formatNumber(document.questions.length)}';

    return '''
<w:tbl>
  <w:tblPr>
    <w:tblW w:w="5000" w:type="pct"/>
    <w:bidiVisual/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:left w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:bottom w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:right w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
    </w:tblBorders>
  </w:tblPr>
  <w:tr>
    <w:tc>
      <w:tcPr><w:tcW w:w="1700" w:type="pct"/></w:tcPr>
      ${_tableCellLines(header.right.lines)}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1600" w:type="pct"/></w:tcPr>
      ${_tableParagraph(title, bold: true, size: 28, alignment: 'center', color: '1E3A8A')}
      ${_tableParagraph(header.center.lines[0], alignment: 'center')}
      ${_tableParagraph(header.center.lines[2], alignment: 'center')}
      ${_tableParagraph(versionLabel, italic: true, alignment: 'center', color: isTeacherVersion ? 'DC2626' : '4B5563')}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1700" w:type="pct"/></w:tcPr>
      ${_tableCellLines(header.left.lines)}
      ${_tableParagraph(
        'الدرجة الكلية: ${document.formatNumber(document.totalMarks)} ${layout.marksUnit}',
        bold: true,
      )}
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
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$alignment"/></w:pPr>'
        '<w:r><w:rPr><w:rtl/>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
        '${color == null ? '' : '<w:color w:val="$color"/>'}'
        '<w:sz w:val="$size"/><w:rFonts w:cs="${DocxDocumentExportService._fontName(document.settings.defaultFont)}"/></w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
  }

  // ------------------------------- الأسئلة -------------------------------

  Future<void> _buildQuestion(StringBuffer body, QuestionModel question) async {
    final layout = document.layout;
    final questionIndex = document.indexOfQuestion(question.id);
    final marksPart = document.settings.showQuestionMarks
        ? ' [${document.formatNumber(question.marks)} ${layout.marksUnit}]'
        : '';
    _writeStyledParagraph(
      body,
      '${document.displayQuestionLabel(question)}$marksPart',
      style: question.style,
      bold: true,
      size: 26,
      color: '111827',
      before: 180,
      after: 60,
    );
    if (question.prompt.trim().isNotEmpty) {
      _writeStyledParagraph(
        body,
        question.prompt,
        style: question.style,
        size: 24,
        before: 40,
        after: 40,
      );
    }
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
    for (var index = 0; index < question.branches.length; index++) {
      await _buildBranch(body, question.branches[index], questionIndex, index);
    }
    await _buildAttachments(body, question.attachments);
    _buildDivider(body, question.dividerAfter);
  }

  Future<void> _buildBranch(
    StringBuffer body,
    BranchModel branch,
    int questionIndex,
    int branchIndex,
  ) async {
    final layout = document.layout;
    final content = branch.content;
    final label = questionIndex >= 0
        ? document.displayBranchLabel(questionIndex, branchIndex)
        : layout.branchLabel(branchIndex);
    final marksSuffix = branch.marks > 0
        ? ' [${document.formatNumber(branch.marks)} ${layout.marksUnit}]'
        : '';
    if (content.text.trim().isNotEmpty || content.items.isEmpty) {
      _writeStyledParagraph(
        body,
        '$label) ${content.text}$marksSuffix',
        style: branch.style,
        size: 22,
        indent: 400,
        before: 40,
        after: 40,
      );
    } else if (marksSuffix.isNotEmpty) {
      _writeStyledParagraph(
        body,
        '$label)$marksSuffix',
        style: branch.style,
        size: 22,
        indent: 400,
        before: 40,
        after: 40,
      );
    }
    for (var i = 0; i < content.items.length; i++) {
      final item = content.items[i];
      final itemMarks = item.marks > 0
          ? ' [${document.formatNumber(item.marks)} ${layout.marksUnit}]'
          : '';
      final text = item.text.trim().isEmpty ? '................................' : item.text;
      _writeStyledParagraph(
        body,
        '${document.formatNumber(i + 1)}- $text$itemMarks',
        style: branch.style,
        size: 22,
        indent: 800,
        before: 30,
        after: 30,
      );
    }
    if (!(content.plainText && !isTeacherVersion)) {
      _buildTypeBody(body, content);
    }
    if (isTeacherVersion && content.plainText && content.modelAnswer.trim().isNotEmpty) {
      _writeParagraph(
        body,
        'الإجابة النموذجية: ${content.modelAnswer}',
        bold: true,
        size: 22,
        color: '065F46',
        highlight: true,
        indent: 800,
        before: 40,
        after: 40,
      );
    }
    _buildDivider(body, branch.dividerAfter);
  }

  void _buildTypeBody(StringBuffer body, BranchContent content) {
    switch (content.type) {
      case QuestionType.multipleChoice:
        final options =
            content.options.where((o) => o.text.trim().isNotEmpty).toList();
        for (var i = 0; i < options.length; i++) {
          final correct = isTeacherVersion && options[i].isCorrect;
          _writeParagraph(
            body,
            '( ${document.layout.branchLabel(i)} )  ${options[i].text}${correct ? '  ✔ الإجابة الصحيحة' : ''}',
            bold: correct,
            size: 22,
            color: correct ? '065F46' : null,
            highlight: correct,
            indent: 800,
            before: 30,
            after: 30,
          );
        }
      case QuestionType.trueFalse:
        if (!isTeacherVersion) {
          _writeParagraph(
            body,
            'الإجابة: (     ) صح      /      (     ) خطأ',
            size: 22,
            indent: 800,
            before: 40,
            after: 40,
          );
          return;
        }
        final answer = content.trueFalseAnswer;
        _writeParagraph(
          body,
          'الإجابة الصحيحة: ${answer ? 'صح' : 'خطأ'} ✔',
          bold: true,
          size: 22,
          color: '065F46',
          highlight: true,
          indent: 800,
          before: 40,
          after: 40,
        );
      case QuestionType.fillInTheBlank:
        if (!isTeacherVersion) {
          _writeParagraph(
            body,
            'الإجابة: ........................................................................................',
            size: 22,
            indent: 800,
            before: 60,
            after: 60,
          );
          return;
        }
        _writeParagraph(
          body,
          'الإجابة النموذجية: ${_modelOrDash(content.modelAnswer)}',
          bold: true,
          size: 22,
          color: '065F46',
          highlight: true,
          indent: 800,
          before: 40,
          after: 40,
        );
      case QuestionType.essay:
        if (isTeacherVersion) {
          _writeParagraph(
            body,
            'الإجابة النموذجية وعناصر التقييم: ${_modelOrDash(content.modelAnswer)}',
            bold: true,
            size: 22,
            color: '065F46',
            indent: 800,
            before: 40,
            after: 40,
          );
          return;
        }
        for (var i = 0; i < document.layout.essayAnswerLines; i++) {
          _writeParagraph(
            body,
            '.......................................................................................................................................................',
            size: 20,
            color: '9CA3AF',
            before: 40,
            after: 40,
          );
        }
    }
  }

  String _modelOrDash(String model) =>
      model.trim().isEmpty ? 'غير محدد' : model.trim();

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
    for (final element in attachments) {
      if (element.isTextBox) {
        _buildTextBox(body, element);
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

  void _buildTextBox(StringBuffer body, FloatingElement element) {
    final text = element.label.trim().isEmpty ? ' ' : element.label.trim();
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
    final size = (((element.textStyle.fontSize ?? 11) * 2).round()).clamp(16, 72);
    body.write(
      '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:bidiVisual/>$border</w:tblPr>'
      '<w:tr><w:tc><w:p><w:pPr><w:bidi/><w:jc w:val="$align"/></w:pPr>'
      '<w:r><w:rPr><w:rtl/>'
      '${element.textStyle.bold == true ? '<w:b/>' : ''}'
      '${element.textStyle.italic == true ? '<w:i/>' : ''}'
      '${element.textStyle.underline == true ? '<w:u w:val="single"/>' : ''}'
      '<w:sz w:val="$size"/><w:rFonts w:cs="$font"/></w:rPr>'
      '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
    );
  }

  void _embedImage(StringBuffer body, Uint8List bytes, double widthPx, double heightPx) {
    var widthPt = PaperMetrics.pt(widthPx);
    var heightPt = PaperMetrics.pt(heightPx);
    if (widthPt <= 0 || heightPt <= 0) {
      return;
    }
    if (widthPt > DocxDocumentExportService._maxImageWidthPt) {
      final scale = DocxDocumentExportService._maxImageWidthPt / widthPt;
      widthPt *= scale;
      heightPt *= scale;
    }
    final emuW = (widthPt / 72 * 914400).round();
    final emuH = (heightPt / 72 * 914400).round();
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
    body.write(
      '<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>'
      '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$emuW" cy="$emuH"/>'
      '<wp:docPr id="$id" name="Picture $id"/>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Picture $id"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$relationId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$emuW" cy="$emuH"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
  }

  // ------------------------------- فقرات -------------------------------

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
  }) {
    _writeParagraph(
      body,
      text,
      bold: style?.bold ?? bold,
      italic: style?.italic ?? false,
      underline: style?.underline ?? false,
      size: style?.fontSize != null ? (style!.fontSize! * 2).round().clamp(12, 96) : size,
      color: color,
      indent: indent,
      before: before,
      after: after,
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
    String? color,
    bool highlight = false,
    int? indent,
    int? before,
    int? after,
    String alignment = 'right',
    String? font,
  }) {
    body.write('<w:p><w:pPr><w:bidi/><w:jc w:val="$alignment"/>');
    if (indent != null) {
      body.write('<w:ind w:right="$indent"/>');
    }
    if (before != null || after != null) {
      body.write(
        '<w:spacing${before == null ? '' : ' w:before="$before"'}${after == null ? '' : ' w:after="$after"'} />',
      );
    }
    body.write('</w:pPr><w:r><w:rPr><w:rtl/>');
    if (bold) {
      body.write('<w:b/>');
    }
    if (italic) {
      body.write('<w:i/>');
    }
    if (underline) {
      body.write('<w:u w:val="single"/>');
    }
    if (highlight) {
      body.write('<w:highlight w:val="yellow"/>');
    }
    if (color != null) {
      body.write('<w:color w:val="$color"/>');
    }
    body.write('<w:sz w:val="$size"/><w:rFonts w:cs="${font ?? DocxDocumentExportService._fontName(document.settings.defaultFont)}"/></w:rPr>');
    body.write('<w:t xml:space="preserve">${_escapeXml(text)}</w:t>');
    body.write('</w:r></w:p>');
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
