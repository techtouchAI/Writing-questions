import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../models/question_type.dart';

class DocxExportService {
  static Future<File> exportExamToDocx({
    required Exam exam,
    bool isTeacherVersion = false,
    String? fileName,
  }) async {
    final archive = Archive();

    // 1. [Content_Types].xml
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.length,
      utf8.encode(_contentTypesXml),
    ));

    // 2. _rels/.rels
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _globalRelsXml.length,
      utf8.encode(_globalRelsXml),
    ));

    // 3. word/_rels/document.xml.rels
    archive.addFile(ArchiveFile(
      'word/_rels/document.xml.rels',
      _documentRelsXml.length,
      utf8.encode(_documentRelsXml),
    ));

    // 4. word/styles.xml
    archive.addFile(ArchiveFile(
      'word/styles.xml',
      _stylesXml.length,
      utf8.encode(_stylesXml),
    ));

    // 5. word/document.xml (Content)
    final documentXml = _buildDocumentXml(exam, isTeacherVersion);
    archive.addFile(ArchiveFile(
      'word/document.xml',
      documentXml.length,
      utf8.encode(documentXml),
    ));

    // Zip encode
    final encoder = ZipEncoder();
    final zipBytes = encoder.encode(archive);
    if (zipBytes == null) {
      throw Exception('فشل ضغط ملف DOCX');
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final suffix = isTeacherVersion ? 'نموذج_الاجابة' : 'ورقة_الامتحان';
    final name = fileName ?? '${exam.name.replaceAll(' ', '_')}_${suffix}_${DateTime.now().millisecondsSinceEpoch}.docx';
    final file = File('${outputDir.path}/$name');
    await file.writeAsBytes(zipBytes, flush: true);
    return file;
  }

  static Future<void> shareDocxFile(File file, {String? subject}) async {
    final xFile = XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    await Share.shareXFiles([xFile], text: subject ?? 'تصدير الاختبار بصيغة Word');
  }

  static String _buildDocumentXml(Exam exam, bool isTeacher) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.write('<w:body>');

    // Document Header Table (Institution, Details, Student info)
    buffer.write(_buildHeaderTable(exam, isTeacher));

    // General Instructions
    if (exam.header.generalInstructions.isNotEmpty) {
      buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:before="120" w:after="160"/></w:pPr>');
      buffer.write('<w:r><w:rPr><w:rtl/><w:i/><w:color w:val="4B5563"/><w:rFonts w:ascii="Traditional Arabic" w:cs="Traditional Arabic"/></w:rPr>');
      buffer.write('<w:t xml:space="preserve">تعليمات الاختبار: ${_escapeXml(exam.header.generalInstructions)}</w:t>');
      buffer.write('</w:r></w:p>');
    }

    buffer.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" w:color="1E3A8A"/></w:pBdr><w:spacing w:after="240"/></w:pPr></w:p>');

    // Questions Rendering
    for (int i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      buffer.write(_buildQuestionXml(i + 1, q, isTeacher));
    }

    // Document Body Section Properties (A4, 1-inch margins, RTL)
    buffer.write('<w:sectPr>');
    buffer.write('<w:pgSz w:w="11906" w:h="16838"/>'); // A4 in dxa
    buffer.write('<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>'); // 2cm margins
    buffer.write('<w:bidi/>');
    buffer.write('</w:sectPr>');

    buffer.write('</w:body>');
    buffer.write('</w:document>');
    return buffer.toString();
  }

  static String _buildHeaderTable(Exam exam, bool isTeacher) {
    final h = exam.header;
    final totalMarks = exam.totalMarks;

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
      <w:tcPr><w:tcW w:w="3000" w:type="pct"/></w:tcPr>
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:b/><w:sz w:val="24"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>${_escapeXml(h.institutionName)}</w:t></w:r>
      </w:p>
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>المادة: ${_escapeXml(h.subject)}</w:t></w:r>
      </w:p>
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>الصف: ${_escapeXml(h.gradeStage)}</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="4000" w:type="pct"/></w:tcPr>
      <w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:b/><w:sz w:val="28"/><w:color w:val="1E3A8A"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>${_escapeXml(h.title)}</w:t></w:r>
      </w:p>
      <w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:i/><w:sz w:val="22"/><w:color w:val="DC2626"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>${isTeacher ? '【 نموذج الإجابة وتوزيع الدرجات للمعلم 】' : 'العام الدراسي: ' + _escapeXml(h.academicYear)}</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="3000" w:type="pct"/></w:tcPr>
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>الزمن: ${_escapeXml(h.duration)}</w:t></w:r>
      </w:p>
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:b/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>الدرجة الكلية: $totalMarks درجة</w:t></w:r>
      </w:p>
      ${!isTeacher ? '''
      <w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:rtl/><w:sz w:val="20"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr><w:t>اسم الطالب: .................................</w:t></w:r>
      </w:p>
      ''' : ''}
    </w:tc>
  </w:tr>
</w:tbl>
''';
  }

  static String _buildQuestionXml(int index, Question q, bool isTeacher) {
    final buffer = StringBuffer();

    // Question Title + Mark
    buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:before="180" w:after="80"/></w:pPr>');
    buffer.write('<w:r><w:rPr><w:rtl/><w:b/><w:sz w:val="26"/><w:color w:val="111827"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
    buffer.write('<w:t xml:space="preserve">س$index: ${_escapeXml(q.title)} </w:t>');
    buffer.write('</w:r>');
    buffer.write('<w:r><w:rPr><w:rtl/><w:color w:val="6B7280"/><w:sz w:val="20"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
    buffer.write('<w:t xml:space="preserve"> [${q.marks} درجة]</w:t>');
    buffer.write('</w:r>');
    buffer.write('</w:p>');

    // Rendering according to QuestionType
    if (q.type == QuestionType.multipleChoice) {
      final choiceLetters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];
      for (int i = 0; i < q.options.length; i++) {
        final opt = q.options[i];
        final letter = i < choiceLetters.length ? choiceLetters[i] : '${i + 1}';
        final isHighlighted = isTeacher && opt.isCorrect;

        buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="40" w:after="40"/></w:pPr>');
        buffer.write('<w:r><w:rPr><w:rtl/>${isHighlighted ? '<w:b/><w:highlight w:val="yellow"/><w:color w:val="065F46"/>' : ''}<w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve"> ( $letter )  ${_escapeXml(opt.text)} ${isHighlighted ? ' ✔ (الإجابة الصحيحة)' : ''}</w:t>');
        buffer.write('</w:r></w:p>');
      }
    } else if (q.type == QuestionType.trueFalse) {
      buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="60" w:after="60"/></w:pPr>');
      if (!isTeacher) {
        buffer.write('<w:r><w:rPr><w:rtl/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve">الإجابة: (     ) صح      /      (     ) خطأ</w:t>');
        buffer.write('</w:r>');
      } else {
        final correct = q.options.firstWhere(
          (o) => o.isCorrect,
          orElse: () => QuestionOption(text: 'صح', isCorrect: true),
        );
        buffer.write('<w:r><w:rPr><w:rtl/><w:b/><w:highlight w:val="yellow"/><w:color w:val="065F46"/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve">الإجابة الصحيحة: ${_escapeXml(correct.text)} ✔</w:t>');
        buffer.write('</w:r>');
      }
      buffer.write('</w:p>');
    } else if (q.type == QuestionType.fillInTheBlank) {
      if (!isTeacher) {
        buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="80" w:after="120"/></w:pPr>');
        buffer.write('<w:r><w:rPr><w:rtl/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve">الإجابة: ........................................................................................</w:t>');
        buffer.write('</w:r></w:p>');
      } else {
        buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="60" w:after="80"/></w:pPr>');
        buffer.write('<w:r><w:rPr><w:rtl/><w:b/><w:highlight w:val="yellow"/><w:color w:val="065F46"/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve">الإجابة النموذجية: ${_escapeXml(q.modelAnswer)}</w:t>');
        buffer.write('</w:r></w:p>');
      }
    } else if (q.type == QuestionType.essay) {
      if (!isTeacher) {
        // Print 4 dotted lines for student answer writing
        for (int l = 0; l < 4; l++) {
          buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:before="60" w:after="60"/></w:pPr>');
          buffer.write('<w:r><w:rPr><w:rtl/><w:color w:val="9CA3AF"/><w:sz w:val="20"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
          buffer.write('<w:t>.......................................................................................................................................................</w:t>');
          buffer.write('</w:r></w:p>');
        }
      } else {
        buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="60" w:after="80"/></w:pPr>');
        buffer.write('<w:r><w:rPr><w:rtl/><w:b/><w:color w:val="065F46"/><w:sz w:val="22"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
        buffer.write('<w:t xml:space="preserve">الإجابة النموذجية وعناصر التقييم: ${_escapeXml(q.modelAnswer)}</w:t>');
        buffer.write('</w:r></w:p>');
      }
    }

    // Explanation (in Teacher version if available)
    if (isTeacher && q.explanation.isNotEmpty) {
      buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:ind w:right="400"/><w:spacing w:before="40" w:after="80"/></w:pPr>');
      buffer.write('<w:r><w:rPr><w:rtl/><w:i/><w:color w:val="2563EB"/><w:sz w:val="20"/><w:rFonts w:cs="Traditional Arabic"/></w:rPr>');
      buffer.write('<w:t xml:space="preserve">💡 سبب الإجابة / الملاحظات: ${_escapeXml(q.explanation)}</w:t>');
      buffer.write('</w:r></w:p>');
    }

    return buffer.toString();
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

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
