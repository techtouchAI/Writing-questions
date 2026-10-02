// تخطيط المعادلات الحقيقي داخل ملف Word — ليس «وجود m:oMath» فقط:
//   * ٦ أسئلة × ٣ معادلات = ١٨ معادلة، كلها مناطق رياضيات أصلية،
//     بترتيب الأسئلة: كل سؤال ← معادلاته ١/٢/٣ بالترتيب ← السؤال التالي،
//   * عناصر المعادلات (المملوكة لسؤال والحرّة على الصفحة) **فقرات في
//     التدفق** بترتيبها البصري (الأعلى فالأسفل) — لا `wp:anchor` ولا
//     `w:tblpPr` ولا جدول عائم حول أي معادلة: فلا تراكب ولا تداخل،
//   * الرسم البديل (مصفوفة) صورة **في التدفق** موسَّطة فقط حيث يلزم،
//   * والملف الحقيقي يُكتب في build/math_samples للمراجعة البصرية في Word.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/services/math_snapshot_renderer.dart'
    show MathRaster;

import '../pdf_engine/fake_math_host.dart';
import '../pdf_engine/pdf_content_probe.dart';

/// صورة PNG حقيقية صغيرة (1×1) للرسم البديل في الاختبارات.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<MathRaster?> _fakeRasterizer(String latex, double fontSizePt) async {
  if (latex.contains('bad')) {
    return null;
  }
  return MathRaster(pngBytes: _pngBytes, widthPt: 24, heightPt: 12);
}

Future<MathRaster?> _throwingRasterizer(String latex, double fontSizePt) {
  throw StateError('فشل الرسم');
}

/// ست صيغ تُمثَّل بُنيةً (OMML) — اثنتان لكل سؤال من الستة بالتناوب.
const List<String> _pool = <String>[
  r'5^{2} + 9',
  r'\sqrt{66}',
  r'\frac{5}{8}',
  r'x_{1} - x_{2}',
  r'\frac{\frac{1}{2}}{3}',
  r'\vec{F}',
];

const String _matrixLatex = r'\begin{bmatrix}1&2\\3&4\end{bmatrix}';

ExamDocument _sixByThree() => ExamDocument(
      name: '٦×٣',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        for (var q = 0; q < 6; q++)
          QuestionModel(
            id: 'q${q + 1}',
            questionNumber: q + 1,
            statement: 'س${q + 1}/ احسب مما يأتي ثم علل',
            items: <BranchItem>[
              for (var i = 0; i < 3; i++)
                BranchItem(
                  id: 'q${q + 1}i$i',
                  text: 'نق${q + 1}$i: أوجد قيمة \$${_pool[(q * 3 + i) % _pool.length]}\$',
                ),
            ],
          ),
      ],
    );

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

/// كل مواضع `<m:oMath>` بترتيبها في الملف.
List<int> _mathZonePositions(String xml) {
  final positions = <int>[];
  var cursor = 0;
  while (true) {
    final next = xml.indexOf('<m:oMath>', cursor);
    if (next < 0) {
      return positions;
    }
    positions.add(next);
    cursor = next + 1;
  }
}

/// كل مواضع `<m:oMathPara>` (فقرة معادلة مستقلة) بترتيبها.
List<int> _mathParaPositions(String xml) {
  final positions = <int>[];
  var cursor = 0;
  while (true) {
    final next = xml.indexOf('<m:oMathPara>', cursor);
    if (next < 0) {
      return positions;
    }
    positions.add(next);
    cursor = next + 1;
  }
}

/// الفقرة الكاملة التي تحتضن الموضع [position].
String _paragraphAt(String xml, int position) {
  final open = xml.lastIndexOf('<w:p>', position);
  final close = xml.indexOf('</w:p>', position);
  expect(open, greaterThanOrEqualTo(0));
  expect(close, greaterThan(position));
  return xml.substring(open, close);
}

/// توازن الوسوم — يرفضه Word فوراً عند أي كسر.
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

/// لا تعويم حول أي معادلة: لا مرساة صورة ولا جدول عائم في مقطعها.
void _expectNoFloatingAround(String xml, int position, {String context = ''}) {
  // نافذة حول فقرة المعادلة: من نهاية الفقرة السابقة حتى بداية التالية.
  final paragraph = _paragraphAt(xml, position);
  expect(paragraph, isNot(contains('wp:anchor')), reason: context);
  expect(paragraph, isNot(contains('w:tblpPr')), reason: context);
  expect(paragraph, isNot(contains('<w:tbl>')), reason: context);
  // وفقرة المعادلة فقرة تدفق عادية: خصائص فقرة عربية موسَّطة أو نقطة نص.
  expect(paragraph, contains('<w:pPr>'), reason: context);
}

Future<String> _writeSample(String name, Uint8List bytes) async {
  final directory = Directory('build/math_samples');
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final file = File('build/math_samples/$name');
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('ملف مراجعة: ${file.path}');
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // مضيف لقطات وهمي لاختبار الـ PDF الموازي: يلصق صوراً حقيقية مكان
  // لقطات المحرك (المواضع والأبعاد وطبقة النص حقيقية — كاختبار خط الأنابيب).
  final host = FakeMathHost();
  setUp(host.attach);
  tearDown(host.detach);

  test('٦ أسئلة × ٣ معادلات: ١٨ منطقة رياضيات مرتبة سؤالاً فسؤالاً', () async {
    final document = _sixByThree();
    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
    );
    final xml = _xml(ZipDecoder().decodeBytes(bytes));

    // 18 معادلة أصلية قابلة للتحرير — وبلا أي صورة (كلها تُمثَّل بُنيةً).
    final zones = _mathZonePositions(xml);
    expect(zones, hasLength(18));
    expect(xml, isNot(contains('<w:drawing>')));
    expect(xml, isNot(contains('wp:anchor')));

    // الترتيب: عنوان كل سؤال يسبق معادلاته الثلاث المرتبة، وهي تسبق
    // عنوان السؤال التالي — في الملف كله كما على اللوحة.
    final titlePositions = <int>[
      for (var q = 1; q <= 6; q++) xml.indexOf('س$q/ احسب مما يأتي'),
    ];
    for (final position in titlePositions) {
      expect(position, greaterThan(-1));
    }
    for (var q = 0; q < 6; q++) {
      final start = titlePositions[q];
      final end = q == 5 ? xml.length : titlePositions[q + 1];
      for (var i = 0; i < 3; i++) {
        final zone = zones[q * 3 + i];
        expect(zone, greaterThan(start),
            reason: 'معادلة ${i + 1} بعد عنوان سؤالها ${q + 1}');
        expect(zone, lessThan(end),
            reason: 'معادلة ${i + 1} داخل حدود سؤالها ${q + 1}');
        if (i > 0) {
          expect(zone, greaterThan(zones[q * 3 + i - 1]),
              reason: 'ترتيب المعادلات ١←٢←٣ داخل السؤال ${q + 1}');
        }
        // وترتيب نقاط السؤال نفسه في الملف يطابق ترتيب معادلاته.
        final point = xml.indexOf('نق${q + 1}$i:', start);
        expect(point, greaterThan(start));
        expect(point, lessThan(zone));
        if (i > 0) {
          final previousPoint = xml.indexOf('نق${q + 1}${i - 1}:', start);
          expect(previousPoint, lessThan(point));
        }
      }
    }

    // كل منطقة رياضيات في فقرة عربية RTL (بلا تداخل مع فقرات أخرى).
    final firstParagraph = _paragraphAt(xml, zones.first);
    expect(firstParagraph, contains('<w:bidi/>'));
    expect(firstParagraph, contains('<w:r>'));

    // لا كود LaTeX ولا دولارات في الملف كله.
    expect(xml, isNot(contains(r'$')));
    expect(xml, isNot(contains(r'\frac')));
    expect(xml, isNot(contains(r'\sqrt')));
    _expectBalancedTags(xml);

    await _writeSample('real-docx-6x3-math.docx', bytes);
  });

  test('معادلات مملوكة لسؤال: فقرات في التدفق تحته بترتيبها البصري', () async {
    final document = _sixByThree().copyWith(
      floatingElements: <FloatingElement>[
        // أُضيفت الأسفل أولاً (dy=300) ثم الأعلى (dy=120): التصدير يعيد
        // الترتيب البصري (الأعلى فالأسفل) لا ترتيب الإضافة.
        FloatingElement(
          id: 'f-low',
          type: FloatingElementType.formula,
          label: r'\frac{22}{7}',
          dx: 40,
          dy: 300,
          width: 150,
          height: 70,
          ownerQuestionId: 'q1',
        ),
        FloatingElement(
          id: 'f-high',
          type: FloatingElementType.formula,
          label: r'\sqrt{66}',
          dx: 40,
          dy: 120,
          width: 150,
          height: 70,
          ownerQuestionId: 'q1',
        ),
      ],
    );
    final xml = _xml(await _archive(document));

    // فقرتا معادلة مستقلتان (عنصران مملوكان) + ١٨ منطقة سطرية.
    final paras = _mathParaPositions(xml);
    expect(paras, hasLength(2));
    expect(_mathZonePositions(xml), hasLength(20));

    // الأعلى (√66) تسبق الأسفل (22/7) في الملف.
    final firstParagraph = _paragraphAt(xml, paras[0]);
    final secondParagraph = _paragraphAt(xml, paras[1]);
    expect(firstParagraph, contains('<m:rad>'));
    expect(secondParagraph, contains('<m:f>'));

    // كلتاهما داخل حدود السؤال الأول (بين عنوانه وعنوان التالي).
    final q1 = xml.indexOf('س1/ احسب مما يأتي');
    final q2 = xml.indexOf('س2/ احسب مما يأتي');
    expect(paras[0], greaterThan(q1));
    expect(paras[1], greaterThan(paras[0]));
    expect(paras[1], lessThan(q2));

    // في التدفق: بلا مراسٍ وبلا جداول عائمة وبلا صور.
    _expectNoFloatingAround(xml, paras[0], context: 'f-high');
    _expectNoFloatingAround(xml, paras[1], context: 'f-low');
    expect(xml, isNot(contains('wp:anchor')));
    expect(xml, isNot(contains('<w:drawing>')));
    expect(firstParagraph, contains('<w:bidi/>'));
    expect(firstParagraph, contains('<w:jc w:val="center"/>'));
    _expectBalancedTags(xml);
  });

  test('معادلات حرة على الصفحة: في التدفق بترتيب بصري وبلا تعويم', () async {
    final document = _sixByThree().copyWith(
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'p-low',
          type: FloatingElementType.formula,
          label: r'\frac{1}{2}',
          dx: 60,
          dy: 500,
          width: 140,
          height: 60,
          pageIndex: 0,
        ),
        FloatingElement(
          id: 'p-high',
          type: FloatingElementType.formula,
          label: r'\sqrt{2}',
          dx: 60,
          dy: 80,
          width: 140,
          height: 60,
          pageIndex: 0,
        ),
      ],
    );
    final xml = _xml(await _archive(document));

    final paras = _mathParaPositions(xml);
    expect(paras, hasLength(2));

    // الأعلى (√2) أولاً ثم الأسفل (1/2) — وكلاهما قبل أسئلة الصفحة.
    final firstParagraph = _paragraphAt(xml, paras[0]);
    final secondParagraph = _paragraphAt(xml, paras[1]);
    expect(firstParagraph, contains('<m:rad>'));
    expect(secondParagraph, contains('<m:f>'));
    final q1 = xml.indexOf('س1/ احسب مما يأتي');
    expect(paras[1], lessThan(q1));

    _expectNoFloatingAround(xml, paras[0], context: 'p-high');
    _expectNoFloatingAround(xml, paras[1], context: 'p-low');
    expect(xml, isNot(contains('wp:anchor')));
    expect(xml, isNot(contains('<w:drawing>')));
    _expectBalancedTags(xml);
  });

  test('الارتداد صورةً يبقى في التدفق: مصفوفة مملوكة بلا مراسٍ', () async {
    final document = _sixByThree().copyWith(
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'm1',
          type: FloatingElementType.formula,
          label: _matrixLatex,
          dx: 40,
          dy: 150,
          width: 200,
          height: 90,
          ownerQuestionId: 'q1',
        ),
      ],
    );

    // مع المرسّم: صورة المعادلة المتعذرة وحدها — وفي فقرة تدفق موسَّطة.
    final xml = _xml(await _archive(document, rasterizer: _fakeRasterizer));
    expect(_mathZonePositions(xml), hasLength(18));
    expect(xml, contains('<w:drawing>'));
    // الصورة ليست مرساة عائمة: الرسم مضمّن (wp:inline) في فقرة موسَّطة.
    expect(xml, isNot(contains('wp:anchor')));
    final drawing = xml.indexOf('<w:drawing>');
    final q1 = xml.indexOf('س1/ احسب مما يأتي');
    final q2 = xml.indexOf('س2/ احسب مما يأتي');
    expect(drawing, greaterThan(q1));
    expect(drawing, lessThan(q2));
    final paragraph = _paragraphAt(xml, drawing);
    expect(paragraph, contains('<w:jc w:val="center"/>'));
    expect(paragraph, contains('<w:bidi/>'));
    // لا كود المصفوفة الخام في الملف.
    expect(xml, isNot(contains(r'\begin')));
    expect(xml, isNot(contains(r'$')));
    _expectBalancedTags(xml);

    // وبلا مرسّم عامل: نص مقروء في التدفق بدل الصورة و بدل الكود.
    final thrown = _xml(await _archive(document, rasterizer: _throwingRasterizer));
    expect(thrown, isNot(contains('<w:drawing>')));
    expect(thrown, isNot(contains(r'\begin')));
    expect(thrown, isNot(contains(r'$')));
    for (final digit in <String>['1', '2', '3', '4']) {
      expect(thrown, contains(digit));
    }

    // وبلا مرسّم إطلاقاً: النص المقروء نفسه.
    final plain = _xml(await _archive(document));
    expect(plain, isNot(contains('<w:drawing>')));
    expect(plain, isNot(contains(r'\begin')));

    final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
      document: document,
      mathRasterizer: _fakeRasterizer,
    );
    await _writeSample('real-docx-owned-matrix-inflow.docx', bytes);
  });

  test('PDF الموازي: الورقة نفسها ٦×٣ تُرسم من محرك المعاينة بلا نص خام',
      () async {
    // نفس المحرك الذي يعرض المعاينة (flutter_math_fork عبر مضيف اللقطات):
    // كل الصيغ الست الفريدة تُطلب له وتُنزل صوراً — المكتبة تعيد استعمال
    // صورة الصيغة المتطابقة، فالعدد ≥ ٦ صور لـ١٨ موضعاً.
    final bytes =
        await PaginatedPdfExamEngine().generate(document: _sixByThree());

    expect(host.requestedLatex, containsAll(_pool));
    expect(imagesInPdf(bytes), greaterThanOrEqualTo(_pool.length));

    // لا رمز LaTeX خاماً في طبقة النص المرسومة (كل صيغة صورة).
    final words = <String>[
      for (final line in PdfContentProbe.fromBytes(bytes).lines)
        ...line.words.map((word) => word.text),
    ];
    expect(words, isNotEmpty);
    for (final token in <String>[
      'frac', 'sqrt', '{', '}', '\\', r'$', '^', '_',
    ]) {
      expect(
        words.where((word) => word.contains(token)).toList(),
        isEmpty,
        reason: 'رمز خام «$token» ظهر نصاً مرسوماً في PDF الورقة ٦×٣.',
      );
    }

    await _writeSample('real-pdf-6x3-math.pdf', bytes);
  });
}
