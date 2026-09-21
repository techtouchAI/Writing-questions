import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/exam.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import 'export_file_name.dart';

class DocxExportService {
  const DocxExportService._();

  static Future<File> exportExamToDocx({
    required Exam exam,
    bool isTeacherVersion = false,
    String? fileName,
  }) async {
    final archive = Archive();
    _addTextFile(archive, '[Content_Types].xml', _contentTypesXml);
    _addTextFile(archive, '_rels/.rels', _globalRelationshipsXml);
    _addTextFile(
      archive,
      'word/_rels/document.xml.rels',
      _documentRelationshipsXml,
    );
    _addTextFile(archive, 'word/styles.xml', _stylesXml);
    _addTextFile(
      archive,
      'word/document.xml',
      _buildDocumentXml(exam, isTeacherVersion),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('فشل ضغط ملف Word.');
    }

    final outputDirectory = await getApplicationDocumentsDirectory();
    final suffix = isTeacherVersion ? 'نموذج_الإجابة' : 'ورقة_الامتحان';
    final requestedFileName =
        fileName ?? '${exam.name}_$suffix_${DateTime.now().millisecondsSinceEpoch}';
    final safeFileName = ExportFileName.fileName(
      value: requestedFileName,
      extension: '.docx',
      fallbackStem: suffix,
    );
    final file = File('${outputDirectory.path}/$safeFileName');
    await file.writeAsBytes(zipBytes, flush: true);
    return file;
  }

  static Future<void> shareDocxFile(File file, {String? subject}) async {
    final xFile = XFile(
      file.path,
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    await Share.shareXFiles(
      <XFile>[xFile],
      text: subject ?? 'تصدير الاختبار بصيغة Word',
    );
  }

  static void _addTextFile(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _buildDocumentXml(Exam exam, bool isTeacherVersion) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
      )
      ..write('<w:body>')
      ..write(_buildHeaderTable(exam, isTeacherVersion));

    if (exam.header.generalInstructions.trim().isNotEmpty) {
      _writeParagraph(
        buffer,
        'تعليمات الاختبار: ${exam.header.generalInstructions}',
        italic: true,
        color: '4B5563',
        before: 120,
        after: 160,
      );
    }

    buffer.write(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" w:color="1E3A8A"/></w:pBdr><w:spacing w:after="240"/></w:pPr></w:p>',
    );

    for (var index = 0; index < exam.questions.length; index++) {
      buffer.write(
        _buildQuestionXml(
          index + 1,
          exam.questions[index],
          isTeacherVersion,
        ),
      );
    }

    buffer
      ..write('<w:sectPr>')
      ..write('<w:pgSz w:w="11906" w:h="16838"/>')
      ..write(
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>',
      )
      ..write('<w:bidi/>')
      ..write('</w:sectPr>')
      ..write('</w:body>')
      ..write('</w:document>');

    return buffer.toString();
  }

  static String _buildHeaderTable(Exam exam, bool isTeacherVersion) {
    final header = exam.header;
    final versionLabel = isTeacherVersion
        ? 'نموذج الإجابة وتوزيع الدرجات للمعلم — العام الدراسي: ${header.academicYear}'
        : 'العام الدراسي: ${header.academicYear}';

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
      ${_tableParagraph(header.institutionName, bold: true, size: 24)}
      ${_tableParagraph('المادة: ${header.subject}')}
      ${_tableParagraph('الصف: ${header.gradeStage}')}
      ${header.instructor.trim().isEmpty ? '' : _tableParagraph('المعلم: ${header.instructor}', size: 20)}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1600" w:type="pct"/></w:tcPr>
      ${_tableParagraph(header.title, bold: true, size: 28, alignment: 'center', color: '1E3A8A')}
      ${_tableParagraph(versionLabel, italic: true, alignment: 'center', color: isTeacherVersion ? 'DC2626' : '4B5563')}
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="1700" w:type="pct"/></w:tcPr>
      ${_tableParagraph('الزمن: ${header.duration}')}
      ${_tableParagraph('الدرجة الكلية: ${_formatMarks(exam.totalMarks)} درجة', bold: true)}
      ${isTeacherVersion ? '' : _tableParagraph('اسم الطالب: .................................', size: 20)}
    </w:tc>
  </w:tr>
</w:tbl>
''';
  }

  static String _tableParagraph(
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
        '<w:sz w:val="$size"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
  }

  static String _buildQuestionXml(
    int index,
    Question question,
    bool isTeacherVersion,
  ) {
    final buffer = StringBuffer();
    _writeParagraph(
      buffer,
      'س$index: ${question.title} [${_formatMarks(question.marks)} درجة]',
      bold: true,
      size: 26,
      color: '111827',
      before: 180,
      after: 80,
    );

    switch (question.type) {
      case QuestionType.multipleChoice:
        _writeMultipleChoiceOptions(buffer, question, isTeacherVersion);
        break;
      case QuestionType.trueFalse:
        _writeTrueFalseAnswer(buffer, question, isTeacherVersion);
        break;
      case QuestionType.fillInTheBlank:
        _writeFillInTheBlankAnswer(buffer, question, isTeacherVersion);
        break;
      case QuestionType.essay:
        _writeEssayAnswerArea(buffer, question, isTeacherVersion);
        break;
    }

    if (isTeacherVersion && question.explanation.trim().isNotEmpty) {
      _writeParagraph(
        buffer,
        'سبب الإجابة / الملاحظات: ${question.explanation}',
        italic: true,
        size: 20,
        color: '2563EB',
        indent: 400,
        before: 40,
        after: 80,
      );
    }

    return buffer.toString();
  }

  static void _writeMultipleChoiceOptions(
    StringBuffer buffer,
    Question question,
    bool isTeacherVersion,
  ) {
    const labels = <String>['أ', 'ب', 'ج', 'د', 'هـ', 'و'];
    final nonEmptyOptions = question.options
        .where((option) => option.text.trim().isNotEmpty)
        .toList(growable: false);

    for (var index = 0; index < nonEmptyOptions.length; index++) {
      final option = nonEmptyOptions[index];
      final isCorrect = isTeacherVersion && option.isCorrect;
      final label = index < labels.length ? labels[index] : '${index + 1}';
      _writeParagraph(
        buffer,
        '( $label )  ${option.text}${isCorrect ? '  ✔ الإجابة الصحيحة' : ''}',
        bold: isCorrect,
        size: 22,
        color: isCorrect ? '065F46' : null,
        highlight: isCorrect,
        indent: 400,
        before: 40,
        after: 40,
      );
    }
  }

  static void _writeTrueFalseAnswer(
    StringBuffer buffer,
    Question question,
    bool isTeacherVersion,
  ) {
    if (!isTeacherVersion) {
      _writeParagraph(
        buffer,
        'الإجابة: (     ) صح      /      (     ) خطأ',
        size: 22,
        indent: 400,
        before: 60,
        after: 60,
      );
      return;
    }

    final correctOptions = question.options
        .where((option) => option.isCorrect)
        .map((option) => option.text)
        .toList(growable: false);
    final correctAnswer =
        correctOptions.isEmpty ? 'غير محدد' : correctOptions.first;
    _writeParagraph(
      buffer,
      'الإجابة الصحيحة: $correctAnswer ✔',
      bold: true,
      size: 22,
      color: '065F46',
      highlight: true,
      indent: 400,
      before: 60,
      after: 60,
    );
  }

  static void _writeFillInTheBlankAnswer(
    StringBuffer buffer,
    Question question,
    bool isTeacherVersion,
  ) {
    if (!isTeacherVersion) {
      _writeParagraph(
        buffer,
        'الإجابة: ........................................................................................',
        size: 22,
        indent: 400,
        before: 80,
        after: 120,
      );
      return;
    }

    _writeParagraph(
      buffer,
      'الإجابة النموذجية: ${_modelAnswerOrPlaceholder(question)}',
      bold: true,
      size: 22,
      color: '065F46',
      highlight: true,
      indent: 400,
      before: 60,
      after: 80,
    );
  }

  static void _writeEssayAnswerArea(
    StringBuffer buffer,
    Question question,
    bool isTeacherVersion,
  ) {
    if (isTeacherVersion) {
      _writeParagraph(
        buffer,
        'الإجابة النموذجية وعناصر التقييم: ${_modelAnswerOrPlaceholder(question)}',
        bold: true,
        size: 22,
        color: '065F46',
        indent: 400,
        before: 60,
        after: 80,
      );
      return;
    }

    for (var index = 0; index < 4; index++) {
      _writeParagraph(
        buffer,
        '.......................................................................................................................................................',
        size: 20,
        color: '9CA3AF',
        before: 60,
        after: 60,
      );
    }
  }

  static String _modelAnswerOrPlaceholder(Question question) {
    final answer = question.modelAnswer.trim();
    return answer.isEmpty ? 'غير محدد' : answer;
  }

  static void _writeParagraph(
    StringBuffer buffer,
    String text, {
    bool bold = false,
    bool italic = false,
    int size = 22,
    String? color,
    bool highlight = false,
    int? indent,
    int? before,
    int? after,
  }) {
    buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/>');
    if (indent != null) {
      buffer.write('<w:ind w:right="$indent"/>');
    }
    if (before != null || after != null) {
      buffer.write(
        '<w:spacing${before == null ? '' : ' w:before="$before"'}${after == null ? '' : ' w:after="$after"'}/>',
      );
    }
    buffer.write('</w:pPr><w:r><w:rPr><w:rtl/>');
    if (bold) {
      buffer.write('<w:b/>');
    }
    if (italic) {
      buffer.write('<w:i/>');
    }
    if (highlight) {
      buffer.write('<w:highlight w:val="yellow"/>');
    }
    if (color != null) {
      buffer.write('<w:color w:val="$color"/>');
    }
    buffer.write(
      '<w:sz w:val="$size"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>',
    );
    buffer.write('<w:t xml:space="preserve">${_escapeXml(text)}</w:t>');
    buffer.write('</w:r></w:p>');
  }

  static String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
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

  static const String _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  static const String _globalRelationshipsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const String _documentRelationshipsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const String _stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Traditional Arabic" w:hAnsi="Traditional Arabic" w:cs="Traditional Arabic"/>
        <w:sz w:val="24"/>
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
