// المقاطع الغنية تصل إلى Word بتنسيقها المعلن: خط الآية القرآني، والصيغة
// معادلة Word أصلية، لا نصاً واحداً يقرؤه كل راسم بقواعده.
//
// العقد واحد: [RichContent.parse] تقرؤه المعاينة (TexText) وWord (_runsXml)،
// فما يراه المدرس على الشاشة هو ما يُكتب في الملف — وهذا ما يقيسه الاختبار
// على XML حقيقي من DOCX مفكوك، لا على وجود الشيفرة.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

/// آية موسومة بقوسَي المصحف (تُكتب رموزاً تهريبية فلا تنعكس بصرياً في المصدر).
const String _verse = '\uFD3Fآية\uFD3E';

ExamDocument _documentWith(String pointText) => ExamDocument(
      name: 'مقاطع',
      header: ExamHeaderModel.initial(subject: 'التربية الإسلامية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'اكتب ما يلي',
          items: <BranchItem>[
            BranchItem(id: 'p1', kind: PointKind.plain, text: pointText),
          ],
        ),
      ],
    );

Future<String> _docxXml(ExamDocument document) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
}

/// فقرة Word التي تحوي [needle] كاملةً (من `<w:p>` إلى `</w:p>`).
String _paragraphWith(String xml, String needle) {
  for (final match in RegExp('<w:p>.*?</w:p>', dotAll: true).allMatches(xml)) {
    if (match.group(0)!.contains(needle)) {
      return match.group(0)!;
    }
  }
  fail('لم أجد فقرة تحوي «$needle».');
}

/// جريانات الفقرة: نصّ كل جريان وخصائصه.
List<({String text, String properties})> _runs(String paragraph) {
  final runs = <({String text, String properties})>[];
  for (final match in RegExp(r'<w:r>(.*?)</w:r>', dotAll: true).allMatches(paragraph)) {
    final run = match.group(1)!;
    final properties = RegExp(r'<w:rPr>(.*?)</w:rPr>', dotAll: true)
            .firstMatch(run)
            ?.group(1) ??
        '';
    final text = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
        .allMatches(run)
        .map((piece) => piece.group(1)!)
        .join();
    runs.add((text: text, properties: properties));
  }
  return runs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('العقد: قطع واحد تقرؤه المعاينة وWord', () {
    test(r'الصيغة تُقطَع أولاً: أقواس المصحف داخل $...$ تبقى رياضيات', () {
      final content = RichContent.parse('\$y \uFD3Fث\uFD3E\$');
      expect(content.runs, hasLength(1));
      expect(content.runs.single.isMath, isTrue);
      expect(content.hasQuran, isFalse,
          reason: 'قوس المصحف داخل صيغة ليس مقطعاً قرآنياً.');
    });

    test('الآية تحمل قوسيها كاملين وخطها المعلن في المقطع نفسه', () {
      final content = RichContent.parse('قال $_verse ثم');
      expect(content.runs.map((run) => run.kind), <VisualRunKind>[
        VisualRunKind.text,
        VisualRunKind.quran,
        VisualRunKind.text,
      ]);
      final quran = content.runs[1];
      expect(quran.text, _verse, reason: 'القوسان جزء من نص المقطع.');
      expect(quran.style?.font, PaperFont.amiri);
      expect(quran.isBlockMath, isFalse);
    });

    test('الصيغة المنفصلة تُعلَن كتلة والسطرية تُعلَن سطرية', () {
      final block = RichContent.parse(r'$$\int_0^1 x\,dx$$');
      expect(block.runs.single.isMath, isTrue);
      expect(block.runs.single.isBlockMath, isTrue);
      final inline = RichContent.parse(r'$x^2$');
      expect(inline.runs.single.isMath, isTrue);
      expect(inline.runs.single.isBlockMath, isFalse);
    });

    test(r'الدولار المهروب `\$` نص عادي بلا شرطة مائلة', () {
      final content = RichContent.parse(r'سعر $5 ثم \$10');
      expect(content.plainText, isNot(contains(r'\$')));
      expect(content.plainText, contains(r'$10'));
    });

    test('`withStyle` يدمج ولا يمحو ما أُعلن سابقاً', () {
      final quran = RichContent.parse(_verse).runs.single;
      final merged = quran.withStyle(const VisualRunStyle(bold: true));
      expect(merged.style?.font, PaperFont.amiri);
      expect(merged.style?.bold, isTrue);
      expect(merged.text, quran.text);
    });
  });

  group('Word: المقاطع تُكتب بتنسيقها', () {
    test('الآية تُكتب بخط Amiri والنص المجاور بخط الورقة', () async {
      final xml = await _docxXml(_documentWith('قال $_verse ثم'));
      final paragraph = _paragraphWith(xml, _verse);
      final runs = _runs(paragraph);
      expect(runs.length, greaterThanOrEqualTo(2),
          reason: 'لا يُدمج المقطع القرآني في جريان النص العام.');
      final quranRun = runs.firstWhere((run) => run.text.contains(_verse));
      expect(quranRun.properties, contains('w:cs="Amiri"'),
          reason: 'خط الآية المعلن في العقد يجب أن يظهر في الملف.');
      final plainRun = runs.firstWhere((run) => run.text.contains('قال'));
      expect(plainRun.properties, isNot(contains('w:cs="Amiri"')),
          reason: 'النص العادي يبقى بخط الورقة.');
    });

    test('الصيغة معادلة Word أصلية لا نصاً ولا صورة', () async {
      final xml = await _docxXml(_documentWith(r'ناتج $x^2+1$ صحيح'));
      expect(xml, contains('<m:oMath>'));
      expect(xml, contains('x'), reason: 'محتوى الصيغة داخل المنطقة الرياضية.');
      expect(xml, isNot(contains(r'$x^2+1$')),
          reason: 'لا يظهر كود LaTeX الخام في الملف.');
    });

    test(r'الدولار المهروب يُكتب `$` كما في المعاينة (لا شرطة مائلة)', () async {
      final xml = await _docxXml(_documentWith(r'سعر \$10 فقط'));
      expect(xml, contains(r'سعر $10 فقط'));
      expect(xml, isNot(contains(r'\$')));
    });
  });

  test('مربع النص الحر يحمل تنسيق الفقرات نفسه في Word (w:szCs)', () async {
    final document = ExamDocument(
      name: 'عنصر حر',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(id: 'q1', questionNumber: 1, statement: 'سؤال'),
      ],
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'free-text',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          label: 'نص عربي حر',
          dx: 40,
          dy: 90,
          width: 140,
          height: 60,
        ),
      ],
    );
    final xml = await _docxXml(document);
    final paragraph = _paragraphWith(xml, 'نص عربي حر');
    // `w:szCs` هو ما يجعل Word يحترم حجم الخط في النص العربي — كان يسقط
    // من مربعات النص الحرة دون الفقرات، فاختلف الحجم بينهما.
    expect(paragraph, contains('<w:szCs '));
  });
}
