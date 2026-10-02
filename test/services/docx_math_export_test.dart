import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/docx/omml_from_equation.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

/// صورة PNG حقيقية صغيرة (1×1) تُستعمل بدل رسم المعادلة في الاختبارات،
/// لأن الرسم نفسه يحتاج محرّك Flutter (يُختبر في الواجهة).
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

final List<String> _capturedLatex = <String>[];
final List<double> _capturedSizes = <double>[];

/// مخصّص رسم وهمي: يسجّل ما طُلب منه ويرفض الصيغ التي تحوي `bad`.
Future<MathRaster?> _fakeRasterizer(String latex, double fontSizePt) async {
  _capturedLatex.add(latex);
  _capturedSizes.add(fontSizePt);
  if (latex.contains('bad')) {
    return null;
  }
  return MathRaster(pngBytes: _pngBytes, widthPt: 24, heightPt: 12);
}

Future<MathRaster?> _throwingRasterizer(String latex, double fontSizePt) {
  throw StateError('فشل الرسم');
}

ExamDocument _document() => ExamDocument(
      name: 'معادلات',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: r'احسب $x^2 + 1$ ثم اكتب الناتج',
          marksOverride: 10,
          items: <BranchItem>[
            BranchItem(id: 'qi1', text: r'النقطة الأولى $\frac{a}{b}$'),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                statement: r'برهن أن $bad_{formula}$ صحيحة',
              ),
            ),
          ],
          attachments: <FloatingElement>[
            FloatingElement(
              type: FloatingElementType.shape,
              shape: FloatingShapeType.textBox,
              label: r'ملاحظة: $\sqrt{2}$',
              dx: 0,
              dy: 0,
              width: 120,
              height: 60,
            ),
          ],
        ),
      ],
    );

/// سؤال يحمل صيغة واحدة فقط — لكل صيغة ملفها الاختباري الخاص.
ExamDocument _documentWithMath(String latex) {
  final document = _document();
  final question = document.questions.first;
  return document.withQuestionAt(
    0,
    question.copyWith(
      statement: 'أوجد قيمة ' + '\$' + latex + '\$',
      items: <BranchItem>[],
      branches: <BranchModel>[],
      attachments: <FloatingElement>[],
    ),
  );
}

/// كل صيغ المرحلة الأولى، بصورها كما يخزّنها المحرر المرئي.
const List<String> _mathSamples = <String>[
  r'5^{2}',
  r'x_{1}',
  r'{x_{1}}^{2}',
  r'\sqrt{66}',
  r'\sqrt[3]{x}',
  r'\frac{5}{8}',
  r'\frac{\frac{1}{2}}{3}',
  r'\sum_{i=1}^{n} i',
  r'\int_{0}^{1} x dx',
  r'\vec{F}',
  r'\hat{x}',
  r'\overline{AB}',
];

/// صيغة لا تُمثَّل بُنيةً (مصفوفة بأسطر وأعمدة): الوحيدة التي تُرسَم صورةً.
const String _matrixLatex = r'\begin{bmatrix}1&2\\3&4\end{bmatrix}';

/// سهم المتجه فوق المحرف في `m:acc`.
const String _vectorAccent = '\u20D7';

/// XML منطقة الرياضيات لصيغة واحدة — يُطبع ليراجَع عينياً في سجلّ التشغيل.
String _mathZone(String latex) {
  final xml = OmmlFromEquation.mathZoneXml(latex, fontSizePt: 11);
  // ignore: avoid_print
  print('OMML <$latex> → ${xml ?? 'null (ارتداد إلى الرسم)'}');
  return xml ?? '';
}

/// يتحقق من توازن الوسوم في `document.xml` (يمسك وسوماً رياضياتية غير مغلقة
/// أو وسم فقرة مغلقاً قبل أوانه، وهو ما يرفضه Word فوراً).
void _expectBalancedTags(String xml, {String context = ''}) {
  final tags = RegExp(r'<(/?)([a-z]+:[A-Za-z0-9]+)[^>]*?(/)?>');
  final stack = <String>[];
  for (final match in tags.allMatches(xml)) {
    final closing = (match.group(1) ?? '').isNotEmpty;
    final selfClosing = (match.group(3) ?? '').isNotEmpty;
    final name = match.group(2)!;
    if (selfClosing) {
      continue;
    }
    if (closing) {
      expect(stack.isNotEmpty && stack.last == name, isTrue,
          reason: 'وسم مغلق بلا مقابل: </$name> $context');
      stack.removeLast();
      continue;
    }
    stack.add(name);
  }
  expect(stack, isEmpty, reason: 'وسوم لم تُغلق: $stack $context');
}

/// الفقرة التي تحتوي أول منطقة رياضيات، كما كتبتها الحزمة.
String _paragraphHoldingMath(String xml) {
  final start = xml.indexOf('<m:oMath');
  expect(start, greaterThan(0), reason: 'لا منطقة رياضيات في الملف');
  final open = xml.lastIndexOf('<w:p>', start);
  final close = xml.indexOf('</w:p>', start);
  return xml.substring(open, close);
}

Future<Archive> _archive(
  ExamDocument document, {
  MathRasterizer? rasterizer,
}) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
    mathRasterizer: rasterizer,
  );
  return ZipDecoder().decodeBytes(bytes);
}

String _xml(Archive archive) {
  final file = archive.findFile('word/document.xml');
  expect(file, isNotNull);
  return utf8.decode(file!.content as List<int>);
}

/// يحوّل [document] إلى docx ويكتبه في `build/math_samples/` ليُفتح في Word
/// للمراجعة البشرية: هل المعادلة أصلية قابلة للتحرير؟ وهل شكلها مطابق؟
Future<String> _writeSample(
  String name,
  ExamDocument document, {
  MathRasterizer? rasterizer,
}) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
    mathRasterizer: rasterizer,
  );
  final directory = Directory('build/math_samples');
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final file = File('build/math_samples/$name.docx');
  file.writeAsBytesSync(bytes);
  return file.path;
}

String _sampleName(int index, String latex) {
  final slug = latex.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final number = (index + 1).toString().padLeft(2, '0');
  return '$number-$slug';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _capturedLatex.clear();
    _capturedSizes.clear();
  });

  test('كل صيغة تخرج معادلة Word أصلية، بلا رسم وبلا كود خام', () async {
    for (var index = 0; index < _mathSamples.length; index++) {
      final latex = _mathSamples[index];
      final document = _documentWithMath(latex);
      final archive = await _archive(document);
      final xml = _xml(archive);

      expect(xml.contains('<m:oMath>'), isTrue, reason: latex);
      // لا صورة ولا مرسّم: OMML يُغني عن الرسم في كل ما يُمثَّل بُنيةً.
      expect(xml.contains('<w:drawing>'), isFalse, reason: latex);
      expect(_capturedLatex, isEmpty, reason: latex);
      // لا كود LaTeX في الملف: لا أصل الصيغة ولا الشرطة المائلة ولا الدولار.
      expect(xml, isNot(contains(latex)), reason: latex);
      expect(xml, isNot(contains(r'$')), reason: latex);
      // المنطقة الرياضية ابن مباشر للفقرة، والفقرة تحتفظ بنصها العربي.
      expect(_paragraphHoldingMath(xml).contains('<w:pPr>'), isTrue,
          reason: latex);
      _expectBalancedTags(xml, context: latex);

      final path = await _writeSample(_sampleName(index, latex), document);
      // ignore: avoid_print
      print('ملف اختبار: $path');
    }
  });

  test('الصيغ المكافئة من لوحة المفاتيح (5² و x₁) تصبح بنيةً لا محرفاً', () {
    final superscript = _mathZone('5²');
    expect(superscript, contains('<m:sSup>'));
    expect(superscript, contains('<m:sup>'));
    expect(superscript, isNot(contains('5²')));

    final subscript = _mathZone('x₁');
    expect(subscript, contains('<m:sSub>'));
    expect(subscript, contains('<m:sub>'));
    expect(subscript, isNot(contains('x₁')));
  });

  test('بنية كل صيغة مطابقة لما يعرضه المحرر المرئي', () {
    expect(_mathZone(r'\frac{5}{8}'), contains('<m:f><m:num>'));
    expect(_mathZone(r'\frac{5}{8}'), contains('<m:den>'));

    // الجذر التربيعي يخفي الدرجة؛ التكعيبي يُظهرها.
    final sqrt = _mathZone(r'\sqrt{66}');
    expect(sqrt, contains('<m:rad>'));
    expect(sqrt, contains('<m:degHide m:val="1"/>'));
    expect(sqrt, contains('<m:deg/>'));
    final cubeRoot = _mathZone(r'\sqrt[3]{x}');
    expect(cubeRoot, isNot(contains('degHide')));
    expect(cubeRoot, contains('<m:deg>'));

    // كسرٌ في بسط كسر: تعشيش صحيح بلا فقد محتوى.
    expect(_mathZone(r'\frac{\frac{1}{2}}{3}'), contains('<m:num><m:f>'));

    // عامل كبير بحدوده: m:nary لا حرفٌ وعقد متفرقة.
    final sum = _mathZone(r'\sum_{i=1}^{n} i');
    expect(sum, contains('<m:nary>'));
    expect(sum, contains('<m:chr m:val="∑"/>'));
    expect(sum, contains('<m:subHide m:val="0"/>'));
    expect(sum, contains('<m:supHide m:val="0"/>'));
    expect(sum, contains('<m:e/>'));
    expect(_mathZone(r'\int_{0}^{1} x dx'), contains('<m:chr m:val="∫"/>'));

    // علامات فوق: سهم وقبعة بـ m:acc، وخط فوق بـ m:bar.
    expect(_mathZone(r'\vec{F}'), contains('<m:acc>'));
    expect(_mathZone(r'\vec{F}'), contains(_vectorAccent));
    expect(_mathZone(r'\hat{x}'), contains('<m:acc>'));
    expect(_mathZone(r'\overline{AB}'), contains('<m:bar>'));
    expect(_mathZone(r'\overline{AB}'), contains('<m:pos m:val="top"/>'));

    // اسم دالة: قائم (upright)، وm:rPr قبل w:rPr كما يفرض المخطط.
    final sine = _mathZone(r'\sin x');
    expect(sine, contains('<m:sty m:val="p"/>'));
    expect(sine.indexOf('<m:rPr>'), lessThan(sine.indexOf('<w:rPr>')));
  });

  test('TeX يرفع آخر وحدة فقط: في ax² تُرفع x وحدها', () {
    final zone = _mathZone('ax^2');
    expect(zone, contains('<m:sSup>'));
    final structure = zone.indexOf('<m:sSup>');
    expect(zone.indexOf('a</m:t>'), lessThan(structure));
    expect(zone.indexOf('x</m:t>'), greaterThan(structure));
  });

  test('سطر معادلة مستقل: m:oMathPara بمحاذاة وسطى', () {
    final para =
        OmmlFromEquation.mathParagraphXml(r'\frac{5}{8}', fontSizePt: 11);
    expect(para, isNotNull);
    expect(para!, startsWith('<m:oMathPara>'));
    expect(para, contains('<m:jc m:val="center"/>'));
    expect(para, contains('<m:oMath>'));
    _expectBalancedTags(para);
  });

  test('صيغة لا تُمثَّل تُرجع null للمُصدِّر لا استثناءً', () {
    expect(OmmlFromEquation.mathZoneXml(_matrixLatex, fontSizePt: 11), isNull);
    expect(
      OmmlFromEquation.mathZoneXml(r'\left(x', fontSizePt: 11),
      isNull,
      reason: r'\left مفتوح بلا \right',
    );
    expect(OmmlFromEquation.mathZoneXml('', fontSizePt: 11), isNull);
    expect(OmmlFromEquation.mathZoneXml('{}', fontSizePt: 11), isNull);
  });

  test('مرفق معادلة حرّة: معادلة Word في فقرة موسَّطة، بلا صورة', () async {
    final document = _document();
    final question = document.questions.first;
    final withFormula = document.withQuestionAt(
      0,
      question.copyWith(
        attachments: <FloatingElement>[
          FloatingElement(
            type: FloatingElementType.formula,
            label: r'\frac{a}{b}',
            dx: 300,
            dy: 700,
            width: 170,
            height: 80,
          ),
        ],
      ),
    );
    // المرسّم متاح لكنه لا يُستدعى: OMML يسبق الرسم دائماً.
    final archive = await _archive(withFormula, rasterizer: _fakeRasterizer);
    final xml = _xml(archive);

    expect(xml.contains('<m:oMathPara>'), isTrue);
    expect(xml.contains('<w:drawing>'), isFalse);
    expect(_capturedLatex, isEmpty);
    expect(xml, isNot(contains(r'\frac{a}{b}')));
    await _writeSample('13-formula-free', withFormula,
        rasterizer: _fakeRasterizer);
  });

  test('مربع نص فيه معادلة: المنطقة الرياضية داخل جدول الصندوق نفسه',
      () async {
    final archive = await _archive(_document());
    final xml = _xml(archive);

    // المعادلة صارت منطقة رياضيات، ومعها نص الصندوق العربي باقٍ في مكانه.
    expect(xml.contains('<m:oMath>'), isTrue);
    expect(xml.contains('ملاحظة:'), isTrue);
    expect(xml.contains('<w:drawing>'), isFalse);
    expect(xml, isNot(contains(r'\sqrt{2}')));
    expect(xml, isNot(contains(r'\frac{a}{b}')));
    // فرع السؤال الذي يحوي bad_{formula} يُمثَّل هو الآخر (دليل+أسّ).
    expect(xml.contains('<m:sSub>'), isTrue);
    await _writeSample('15-textbox-and-branches', _document());
  });

  test('ما لا يُمثَّل بُنيةً يُرسَم صورةً، وبلا مرسَّم يُكتب نصاً مقروءاً',
      () async {
    final document = _document();
    final question = document.questions.first;
    final withMatrix = document.withQuestionAt(
      0,
      question.copyWith(
        statement: 'رتّب المصفوفة ' + '\$' + _matrixLatex + r'$ في صفوف',
        items: <BranchItem>[],
        branches: <BranchModel>[],
        attachments: <FloatingElement>[],
      ),
    );

    // 1) مع المرسّم: الصيغة المتعذرة وحدها تُرسم وتُضمَّن في الفقرة.
    final drawn = await _archive(withMatrix, rasterizer: _fakeRasterizer);
    final drawnXml = _xml(drawn);
    expect(_capturedLatex, <String>[_matrixLatex]);
    expect(_capturedSizes.every((size) => size > 0), isTrue);
    expect(drawnXml.contains('<w:drawing>'), isTrue);
    expect(drawnXml, isNot(contains('\\begin')));
    expect(drawnXml.contains('رتّب المصفوفة'), isTrue);
    expect(drawnXml.contains('في صفوف'), isTrue);
    _expectBalancedTags(drawnXml);
    await _writeSample('14-matrix-rasterized', withMatrix,
        rasterizer: _fakeRasterizer);

    // 2) بلا مرسّم: لا كود خام — نصٌّ رياضي مقروء بدل الصورة.
    _capturedLatex.clear();
    final plain = await _archive(withMatrix);
    final plainXml = _xml(plain);
    expect(plainXml.contains('<w:drawing>'), isFalse);
    expect(plainXml, isNot(contains('\\begin')));
    expect(plainXml, isNot(contains(r'$')));
    expect(plainXml.contains('رتّب المصفوفة'), isTrue);
  });

  test('فشل المرسّم لا يُسقط التصدير: يرتد إلى النص المقروء', () async {
    final document = _document();
    final question = document.questions.first;
    final withMatrix = document.withQuestionAt(
      0,
      question.copyWith(
        statement: 'رتّب ' + '\$' + _matrixLatex + r'$ ثم اكتب الحد الأدنى',
        items: <BranchItem>[],
        branches: <BranchModel>[],
        attachments: <FloatingElement>[],
      ),
    );
    final archive =
        await _archive(withMatrix, rasterizer: _throwingRasterizer);
    final xml = _xml(archive);

    expect(xml.contains('<w:drawing>'), isFalse);
    expect(xml, isNot(contains('\\begin')));
    expect(xml, isNot(contains(r'$')));
    expect(xml.contains('رتّب'), isTrue);
    expect(xml.contains('ثم اكتب الحد الأدنى'), isTrue);
  });

  test('الورقة العربية RTL: bidi باقٍ، وجريان الرياضيات LTR خالص', () async {
    final archive = await _archive(_document());
    final xml = _xml(archive);

    // الفقرة العربية تحتفظ بمحاذاة RTL، والمعادلة داخلها كائن LTR مستقل.
    expect(_paragraphHoldingMath(xml).contains('<w:bidi/>'), isTrue);
    // ولا <w:rtl/> داخل جريان الرياضيات (وإلا انعكس ترتيب الرموز).
    var cursor = 0;
    var checked = 0;
    while (true) {
      final open = xml.indexOf('<m:r>', cursor);
      if (open < 0) {
        break;
      }
      final close = xml.indexOf('</m:r>', open);
      expect(xml.substring(open, close), isNot(contains('<w:rtl/>')));
      checked++;
      cursor = close + 1;
    }
    expect(checked, greaterThan(0));

    // عينة تُفتح في Word: سؤال عربي RTL وفيه معادلات — للتحقق البصري من أن
    // bidi للفقرات لم يفسد ومن أن جريان الرياضيات لم يننعكس.
    final path = await _writeSample('16-rtl-question', _document());
    // ignore: avoid_print
    print('عينة RTL: $path');
  });

  test('حجم المعادلة يُرث من الفقرة بأنصاف النقاط، وخط الرياضيات مصرّح', () {
    final zone =
        OmmlFromEquation.mathZoneXml(r'\frac{5}{8}', fontSizePt: 11);
    expect(zone, contains('<w:sz w:val="22"/>'));
    expect(zone, contains('<w:szCs w:val="22"/>'));
    expect(zone, contains('w:ascii="Cambria Math"'));

    // تنسيق الفقرة المورّث يصل إلى الجريان، بترتيب المخطط نفسه.
    final inherited = OmmlFromEquation.mathZoneXml(
      r'\frac{5}{8}',
      fontSizePt: 11,
      extraRunProperties: '<w:b/><w:i/><w:color w:val="FF0000"/>',
    );
    expect(inherited, contains('<w:rFonts w:ascii="Cambria Math" w:hAnsi="Cambria Math" '
        'w:cs="Cambria Math"/><w:b/><w:i/><w:color w:val="FF0000"/><w:sz'));
  });

  test('مساحة اختبار كاملة: ملف واحد بكل الصيغ للمراجعة في Word', () async {
    final document = _document();
    final question = document.questions.first;
    final allSamples = document.withQuestionAt(
      0,
      question.copyWith(
        statement: 'احسب مما يلي ثم اكتب الناتج في المكان المناسب',
        items: <BranchItem>[
          for (var index = 0; index < _mathSamples.length; index++)
            BranchItem(
              id: 'm$index',
              text: '(${index + 1}) ' + '\$' + _mathSamples[index] + '\$',
            ),
        ],
        branches: <BranchModel>[
          BranchModel(
            id: 'bm',
            marks: 4,
            content: BranchContent(
              statement: 'المصفوفة: ' + '\$' + _matrixLatex + '\$',
            ),
          ),
        ],
        attachments: <FloatingElement>[
          FloatingElement(
            type: FloatingElementType.formula,
            label: r'\frac{22}{7}',
            dx: 300,
            dy: 700,
            width: 170,
            height: 80,
          ),
        ],
      ),
    );
    final archive =
        await _archive(allSamples, rasterizer: _fakeRasterizer);
    final xml = _xml(archive);

    expect(xml.contains('<m:oMath>'), isTrue);
    expect(xml.contains('<m:oMathPara>'), isTrue);
    // المصفوفة وحدها ذهبت إلى الرسم.
    expect(_capturedLatex, <String>[_matrixLatex]);
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml, isNot(contains(r'$')));
    _expectBalancedTags(xml);
    final path = await _writeSample('00-all-samples', allSamples,
        rasterizer: _fakeRasterizer);
    // ignore: avoid_print
    print('عينة Word كاملة: $path');
  });

  test('جذر المساحة الخالية لا يترك معادلة بلا محتوى ولا وسوماً يتيمة', () {
    expect(_mathZone(''), isEmpty);
    expect(OmmlFromEquation.mathZoneXml(r'\frac{}{2}', fontSizePt: 11),
        contains('<m:num></m:num>'));
  });
}
