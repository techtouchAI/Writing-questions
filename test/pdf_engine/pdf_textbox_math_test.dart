// مربع النص العائم والمعادلة الحرة في ملف PDF: صيغهما تُرسم **لقطة من محرك
// العرض نفسه** كما في متن الورقة — لا كود LaTeX خاماً. يُقرأ الناتج عبر
// [PdfContentProbe] (قارئ مستقل لطبقة النص المرسومة فعلاً) والمطابقة على مراسي
// ASCII لأن طبقة النص العربية مشكّلة ومقلوبة بصرياً؛ وطبقة الرسم تُتحقق بعدّ
// كائنات الصور في الملف.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'fake_math_host.dart';
import 'pdf_content_probe.dart';

/// مربع نص فيه مرساتان ASCII حول صيغتين (المرساتان تُطبعان نصاً، والصيغ
/// تُرسم رسماً — فالفرق بينهما دليل على المسارين معاً).
ExamDocument _document() => ExamDocument(
      name: 'مربع نص',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'سؤال',
          attachments: <FloatingElement>[
            FloatingElement(
              type: FloatingElementType.shape,
              shape: FloatingShapeType.textBox,
              label: r'A1 $x^2$ B2 $\frac{a}{b}$',
              dx: 0,
              dy: 0,
              width: 300,
              height: 80,
            ),
          ],
        ),
      ],
    );

/// مستند فيه معادلة **حرة** (عنصر عائم) في موضع مطلق بعيد عن نص السؤال.
ExamDocument _formulaDocument() => ExamDocument(
      name: 'معادلة حرة',
      header: ExamHeaderModel.initial(subject: 'الفيزياء'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'سؤال',
          attachments: <FloatingElement>[
            FloatingElement(
              type: FloatingElementType.formula,
              label: r'\frac{a}{b}',
              dx: 200,
              dy: 950,
              width: 170,
              height: 80,
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // المضيف الوهمي يُلصق صوراً حقيقية: فتُختبر مطالبة العناصر العائمة باللقطة
  // (وهي الجولة الأولى من مرحلتي PDF: لا يُنسى مربع نص ولا بطاقة معادلة).
  final host = FakeMathHost();
  setUp(host.attach);
  tearDown(host.detach);

  test('المعادلة الحرة تُرسم صورةً في الـ PDF ولا تُكتب نصاً بديلاً', () async {
    final bytes =
        await PaginatedPdfExamEngine().generate(document: _formulaDocument());
    final probe = PdfContentProbe.fromBytes(bytes);
    final words = probe.lines
        .expand((line) => line.words.map((word) => word.text))
        .toList(growable: false);

    // النص البديل (‏\frac{a}{b}‏ كما كُتب) يُكتب فقط عند تعذّر اللقطة؛ غيابه
    // ودليلٌ على أن المعادلة نزلت صورةً في طبقة الرسم — صورة واحدة على الأقل.
    for (final token in <String>['frac', 'sqrt', r'$', '^', '_', '{', '}']) {
      final offenders =
          words.where((word) => word.contains(token)).toList(growable: false);
      expect(
        offenders,
        isEmpty,
        reason: 'المعادلة الحرة: رمز LaTeX خام «$token» ظهر نصاً مرسوماً.',
      );
    }
    expect(host.requestedLatex, contains(r'\frac{a}{b}'));
    expect(imagesInPdf(bytes), greaterThanOrEqualTo(1));
  });

  test('تعذّر اللقطة لا يُسقط المعادلة: نص مقروء وبلا كود ولا صورة كاذبة',
      () async {
    host.failingLatex = r'\frac{a}{b}';
    final bytes =
        await PaginatedPdfExamEngine().generate(document: _formulaDocument());
    final probe = PdfContentProbe.fromBytes(bytes);

    // ارتداد مقصود: لا صورة مُدّعاة ولا كود؛ ولا يستثني المحرك أي صيغة أخرى.
    expect(imagesInPdf(bytes), 0);
    for (final token in <String>[r'\', r'$', '{', '}']) {
      expect(
        probe.lines
            .expand((line) => line.words.map((word) => word.text))
            .where((word) => word.contains(token)),
        isEmpty,
        reason: 'الارتداد إلى النص المقروء سرّب رمزاً خاماً «$token».',
      );
    }
  });

  test('مربع النص يطبع صيغه صوراً من محرك العرض ولا يترك LaTeX خاماً', () async {
    final bytes = await PaginatedPdfExamEngine().generate(document: _document());
    final probe = PdfContentProbe.fromBytes(bytes);
    final words = probe.lines
        .expand((line) => line.words.map((word) => word.text))
        .toList(growable: false);

    // المرساتان النصيتان حيتان: طبقة النص تعمل داخل مربع النص.
    expect(words, contains('A1'));
    expect(words, contains('B2'));

    // ولا كود خام واحد في أي كلمة مرسومة.
    for (final token in <String>['frac', 'sqrt', r'$', '^', '_', '{', '}']) {
      final offenders =
          words.where((word) => word.contains(token)).toList(growable: false);
      expect(
        offenders,
        isEmpty,
        reason: 'مربع النص: رمز LaTeX خام «$token» ظهر كنص مرسوم بدل رسمه.',
      );
    }
    // الصيغتان داخل المربع ذهبتا إلى المحرك، ونزلت في الملف صورتهما.
    expect(host.requestedLatex, containsAll(<String>[r'x^2', r'\frac{a}{b}']));
    expect(imagesInPdf(bytes), greaterThanOrEqualTo(2));
  });
}
