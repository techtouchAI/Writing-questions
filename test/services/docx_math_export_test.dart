import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
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
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: r'احسب $x^2 + 1$ ثم اكتب الناتج',
          marksOverride: 10,
          items: <BranchItem>[
            BranchItem(id: 'qi1', text: r'النقطة الأولى $\frac{a}{b}$'),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                type: QuestionType.essay,
                text: r'برهن أن $bad_{formula}$ صحيحة',
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

Future<Archive> _archive(ExamDocument document, {MathRasterizer? rasterizer}) async {
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

void main() {
  setUp(() {
    _capturedLatex.clear();
    _capturedSizes.clear();
  });

  test('صيغ LaTeX تُرسم صوراً في Word ولا تظهر أكواداً خامة', () async {
    final archive = await _archive(_document(), rasterizer: _fakeRasterizer);
    final xml = _xml(archive);

    // الرسوم مضمّنة داخل الفقرة نفسها (run واحد لكل معادلة).
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml.contains('rIdImg'), isTrue);
    expect(archive.findFile('word/media/image1.png'), isNotNull);
    expect(
      utf8.decode(
        archive.findFile('[Content_Types].xml')!.content as List<int>,
      ).contains('image/png'),
      isTrue,
    );

    // لا كود خام — لا للصيغة ولا لعلامات الدولار.
    expect(xml.contains('x^2 + 1'), isFalse);
    expect(xml.contains(r'\frac{a}{b}'), isFalse);
    expect(xml.contains(r'\sqrt{2}'), isFalse);
    expect(xml.contains('x^2'), isFalse);

    // النص المحيط بالصيغ باقٍ في مكانه.
    expect(xml.contains('احسب'), isTrue);
    expect(xml.contains('ثم اكتب الناتج'), isTrue);
    expect(xml.contains('النقطة الأولى'), isTrue);
    expect(xml.contains('ملاحظة:'), isTrue);

    // كل الصيغ ذهبت إلى المرسّم بالحجم الصحيح (نصف حجم Word بالنقاط).
    expect(_capturedLatex, contains('x^2 + 1'));
    expect(_capturedLatex, contains(r'\frac{a}{b}'));
    expect(_capturedLatex, contains(r'\sqrt{2}'));
    expect(_capturedSizes.every((size) => size > 0), isTrue);
  });

  test('بلا مخصّص رسم يبقى نص الصيغة كما هو (توافق خلفي)', () async {
    final archive = await _archive(_document());
    final xml = _xml(archive);

    expect(xml.contains('<w:drawing>'), isFalse);
    expect(xml.contains('x^2 + 1'), isTrue);
    expect(archive.findFile('word/media/image1.png'), isNull);
  });

  test('المعادلة الحرة تُصدَّر صورة معادلة لا نصاً', () async {
    final document = _document();
    final question = document.questions.first;
    final withFormula = document.withQuestionAt(
      0,
      question.copyWith(
        attachments: <FloatingElement>[
          ...question.attachments,
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
    final archive = await _archive(withFormula, rasterizer: _fakeRasterizer);
    final xml = _xml(archive);

    // الصيغة ذهبت للمرسّم (لا نصاً خاماً) ونتيجتها صورة داخل الملف.
    expect(_capturedLatex, contains(r'\frac{a}{b}'));
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml.contains(r'\frac{a}{b}'), isFalse);
    expect(archive.findFile('word/media/image1.png'), isNotNull);
  });

  test('الصيغة التي يتعذّر رسمها تُكتب نصاً بدل إسقاطها', () async {
    final archive = await _archive(_document(), rasterizer: _fakeRasterizer);
    final xml = _xml(archive);

    // الصيغة المرفوضة بقيت نصاً، وشقيقاتها رُسمت.
    expect(xml.contains('bad_{formula}'), isTrue);
    expect(xml.contains('<w:drawing>'), isTrue);
  });

  test('فشل المرسّم لا يُسقط التصدير', () async {
    final archive = await _archive(_document(), rasterizer: _throwingRasterizer);
    final xml = _xml(archive);

    expect(xml.contains('<w:drawing>'), isFalse);
    expect(xml.contains('x^2 + 1'), isTrue);
    expect(xml.contains('احسب'), isTrue);
  });
}
