import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/exam.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import 'export_file_service.dart';

/// Builds Microsoft Word (.docx) documents directly as raw OpenXML.
///
/// A .docx file is a ZIP container holding several XML parts; this service
/// assembles a minimal, spec-compliant package with full right-to-left
/// support for Arabic exam papers (student and teacher variants).
abstract final class DocxExportService {
  static const String _mimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static const List<String> _choiceLetters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

  /// Generates the .docx file for [exam] and returns it as a [File].
  ///
  /// When [isTeacherVersion] is set, the document embeds the correct
  /// answers, model answers and grading notes instead of the blank answer
  /// areas the students fill in.
  static Future<File> exportExamToDocx({
    required Exam exam,
    bool isTeacherVersion = false,
    Directory? outputDirectory,
  }) async {
    final archive = Archive()
      ..addFile(_textPart('[Content_Types].xml', _contentTypesXml))
      ..addFile(_textPart('_rels/.rels', _globalRelsXml))
      ..addFile(_textPart('word/_rels/document.xml.rels', _documentRelsXml))
      ..addFile(_textPart('word/styles.xml', _stylesXml))
      ..addFile(
        _textPart('word/document.xml', _buildDocumentXml(exam, isTeacherVersion)),
      );

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw const ExportException('تعذر ضغط حزمة ملف Word.');
    }

    return ExportFileService.writeExportFile(
      baseName: exam.name,
      extension: 'docx',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  /// Opens the system share sheet for a previously generated file.
  static Future<void> shareDocxFile(File file, {String? subject}) {
    return ExportFileService.shareExportFile(
      file,
      mimeType: _mimeType,
      subject: subject,
    );
  }

  // ---------------------------------------------------------------------------
  // OpenXML assembly
  // ---------------------------------------------------------------------------

  static ArchiveFile _textPart(String name, String content) =>
      // `utf8.encode` produces the real byte length of the UTF-8 payload;
      // sizing the part by `String.length` (UTF-16 code units) would corrupt
      // any document containing Arabic text.
      ArchiveFile.bytes(name, utf8.encode(content));

  static String _buildDocumentXml(Exam exam, bool isTeacher) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body>',
      )
      ..write(_headerTable(exam, isTeacher))
      ..write(_instructionsParagraph(exam.header.generalInstructions))
      ..write(_dividerParagraph());

    for (var i = 0; i < exam.questions.length; i++) {
      buffer.write(_questionXml(i + 1, exam.questions[i], isTeacher));
    }

    // A4 page with 2 cm margins and a right-to-left section flow.
    buffer.write(
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>'
      '<w:bidi/></w:sectPr></w:body></w:document>',
    );
    return buffer.toString();
  }

  /// Builds a right-to-left, Arabic-styled paragraph from a single run.
  static String _rtlParagraph(
    String text, {
    bool bold = false,
    bool italic = false,
    bool highlighted = false,
    String colorHex = '111827',
    int halfPoints = 22,
    bool indented = false,
    String spacingBefore = '40',
    String spacingAfter = '40',
    String alignment = 'right',
  }) {
    final paragraphProps = StringBuffer('<w:bidi/><w:jc w:val="$alignment"/>');
    if (indented) paragraphProps.write('<w:ind w:right="400"/>');
    paragraphProps.write(
      '<w:spacing w:before="$spacingBefore" w:after="$spacingAfter"/>',
    );

    final runProps = StringBuffer('<w:rtl/>');
    if (bold) runProps.write('<w:b/>');
    if (italic) runProps.write('<w:i/>');
    if (highlighted) runProps.write('<w:highlight w:val="yellow"/>');
    runProps
      ..write('<w:color w:val="$colorHex"/>')
      ..write('<w:sz w:val="$halfPoints"/>')
      ..write('<w:rFonts w:ascii="Traditional Arabic" w:cs="Traditional Arabic"/>');

    return '<w:p><w:pPr>${paragraphProps}</w:pPr>'
        '<w:r><w:rPr>${runProps}</w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
  }

  static String _instructionsParagraph(String instructions) {
    if (instructions.isEmpty) return '';
    return _rtlParagraph(
      'تعليمات الاختبار: $instructions',
      italic: true,
      colorHex: '4B5563',
      spacingBefore: '120',
      spacingAfter: '160',
    );
  }

  static String _dividerParagraph() =>
      '<w:p><w:pPr><w:pBdr>'
      '<w:bottom w:val="single" w:sz="12" w:space="4" w:color="1E3A8A"/>'
      '</w:pBdr><w:spacing w:after="240"/></w:pPr></w:p>';

  static String _cellParagraph(
    String text, {
    bool bold = false,
    bool italic = false,
    int halfPoints = 22,
    String colorHex = '000000',
    String alignment = 'right',
  }) {
    final runProps = StringBuffer('<w:rtl/>');
    if (bold) runProps.write('<w:b/>');
    if (italic) runProps.write('<w:i/>');
    runProps
      ..write('<w:sz w:val="$halfPoints"/>')
      ..write('<w:color w:val="$colorHex"/>')
      ..write('<w:rFonts w:cs="Traditional Arabic"/>');
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$alignment"/></w:pPr>'
        '<w:r><w:rPr>${runProps}</w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
  }

  static String _headerCell(String paragraphs, int widthPct) =>
      '<w:tc><w:tcPr><w:tcW w:w="$widthPct" w:type="pct"/></w:tcPr>'
      '$paragraphs</w:tc>';

  static String _headerTable(Exam exam, bool isTeacher) {
    final header = exam.header;
    final institutionColumn = _headerCell(
      _cellParagraph(header.institutionName, bold: true, halfPoints: 24) +
          _cellParagraph('المادة: ${header.subject}') +
          _cellParagraph('الصف: ${header.gradeStage}'),
      3000,
    );

    final titleColumn = _headerCell(
      _cellParagraph(
            header.title,
            bold: true,
            halfPoints: 28,
            colorHex: '1E3A8A',
            alignment: 'center',
          ) +
          _cellParagraph(
            isTeacher
                ? '【 نموذج الإجابة وتوزيع الدرجات للمعلم 】'
                : 'العام الدراسي: ${header.academicYear}',
            italic: true,
            colorHex: 'DC2626',
            alignment: 'center',
          ),
      4000,
    );

    final detailsParagraphs = <String>[
      _cellParagraph('الزمن: ${header.duration}'),
      _cellParagraph(
        'الدرجة الكلية: ${_formatMarks(exam.totalMarks)} درجة',
        bold: true,
      ),
      if (!isTeacher)
        _cellParagraph('اسم الطالب: .................................', halfPoints: 20),
    ];
    final detailsColumn = _headerCell(detailsParagraphs.join(), 3000);

    return '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:bidiVisual/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>'
        '<w:left w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>'
        '<w:right w:val="single" w:sz="8" w:space="0" w:color="1E3A8A"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>'
        '</w:tblBorders></w:tblPr>'
        '<w:tr>$institutionColumn$titleColumn$detailsColumn</w:tr></w:tbl>';
  }

  static String _questionXml(int number, Question question, bool isTeacher) {
    final buffer = StringBuffer()
      ..write(_rtlParagraph(
        'س$number: ${question.title}  [${_formatMarks(question.marks)} درجة]',
        bold: true,
        halfPoints: 26,
        spacingBefore: '180',
        spacingAfter: '80',
      ));

    switch (question.type) {
      case QuestionType.multipleChoice:
        _writeMultipleChoice(buffer, question, isTeacher);
      case QuestionType.trueFalse:
        _writeTrueFalse(buffer, question, isTeacher);
      case QuestionType.fillInTheBlank:
        _writeFillInTheBlank(buffer, question, isTeacher);
      case QuestionType.essay:
        _writeEssay(buffer, question, isTeacher);
    }

    if (isTeacher && question.explanation.isNotEmpty) {
      buffer.write(_rtlParagraph(
        '💡 سبب الإجابة / الملاحظات: ${question.explanation}',
        italic: true,
        colorHex: '2563EB',
        halfPoints: 20,
        indented: true,
        spacingBefore: '40',
        spacingAfter: '80',
      ));
    }
    return buffer.toString();
  }

  static void _writeMultipleChoice(
    StringBuffer buffer,
    Question question,
    bool isTeacher,
  ) {
    for (var i = 0; i < question.options.length; i++) {
      final option = question.options[i];
      final letter =
          i < _choiceLetters.length ? _choiceLetters[i] : '${i + 1}';
      final isCorrect = isTeacher && option.isCorrect;
      buffer.write(_rtlParagraph(
        '( $letter )  ${option.text}${isCorrect ? '  ✔ (الإجابة الصحيحة)' : ''}',
        bold: isCorrect,
        highlighted: isCorrect,
        colorHex: isCorrect ? '065F46' : '111827',
        indented: true,
      ));
    }
  }

  static void _writeTrueFalse(
    StringBuffer buffer,
    Question question,
    bool isTeacher,
  ) {
    if (!isTeacher) {
      buffer.write(_rtlParagraph(
        'الإجابة: (     ) صح      /      (     ) خطأ',
        indented: true,
        spacingBefore: '60',
        spacingAfter: '60',
      ));
      return;
    }
    final correct = question.options.firstWhere(
      (option) => option.isCorrect,
      orElse: () => QuestionOption(text: 'غير محدد'),
    );
    buffer.write(_rtlParagraph(
      'الإجابة الصحيحة: ${correct.text} ✔',
      bold: true,
      highlighted: true,
      colorHex: '065F46',
      indented: true,
      spacingBefore: '60',
      spacingAfter: '60',
    ));
  }

  static void _writeFillInTheBlank(
    StringBuffer buffer,
    Question question,
    bool isTeacher,
  ) {
    if (!isTeacher) {
      final dots = '.' * 88;
      buffer.write(_rtlParagraph(
        'الإجابة: $dots',
        indented: true,
        spacingBefore: '80',
        spacingAfter: '120',
      ));
      return;
    }
    buffer.write(_rtlParagraph(
      'الإجابة النموذجية: ${question.modelAnswer}',
      bold: true,
      highlighted: true,
      colorHex: '065F46',
      indented: true,
      spacingBefore: '60',
      spacingAfter: '80',
    ));
  }

  static void _writeEssay(
    StringBuffer buffer,
    Question question,
    bool isTeacher,
  ) {
    if (!isTeacher) {
      // Four dotted lines for the student's handwritten answer.
      for (var line = 0; line < 4; line++) {
        buffer.write(_rtlParagraph(
          '.' * 148,
          colorHex: '9CA3AF',
          halfPoints: 20,
          spacingBefore: '60',
          spacingAfter: '60',
        ));
      }
      return;
    }
    buffer.write(_rtlParagraph(
      'الإجابة النموذجية وعناصر التقييم: ${question.modelAnswer}',
      bold: true,
      colorHex: '065F46',
      indented: true,
      spacingBefore: '60',
      spacingAfter: '80',
    ));
  }

  static String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Renders 2.0 as "2" and 1.5 as "1.5" for a cleaner printed paper.
  static String _formatMarks(double marks) =>
      marks % 1 == 0 ? marks.toInt().toString() : marks.toString();

  // ---------------------------------------------------------------------------
  // Package parts (constants)
  // ---------------------------------------------------------------------------

  static const String _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  static const String _globalRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const String _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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
