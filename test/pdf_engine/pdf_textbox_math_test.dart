// مربع النص العائم في ملف PDF: صيغته (`$...$`) تُرسم **رسم متجه** كما في
// متن الورقة — لا كود LaTeX خاماً. يُقرأ الناتج عبر [PdfContentProbe]
// (قارئ مستقل لطبقة النص المرسومة فعلاً) والمطابقة على مراسي ASCII لأن
// طبقة النص العربية مشكّلة ومقلوبة بصرياً.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

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

  test('المعادلة الحرة تُرسم في الـ PDF ولا تُكتب نصاً بديلاً', () async {
    final bytes =
        await PaginatedPdfExamEngine().generate(document: _formulaDocument());
    final probe = PdfContentProbe.fromBytes(bytes);
    final words = probe.lines
        .expand((line) => line.words.map((word) => word.text))
        .toList(growable: false);

    // النص البديل (‏$\frac{a}{b}$‏) هو ما يُكتب لو فشل رسم المتجه؛ غيابه
    // دليل أن المعادلة رُسمت في طبقة الصفحة من SVG.
    for (final token in <String>['frac', 'sqrt', r'$', '^', '_', '{', '}']) {
      final offenders =
          words.where((word) => word.contains(token)).toList(growable: false);
      expect(
        offenders,
        isEmpty,
        reason: 'المعادلة الحرة: رمز LaTeX خام «$token» ظهر نصاً مرسوماً.',
      );
    }
  });

  test('مربع النص يطبع صيغه رسماً متجهًا ولا يترك LaTeX خاماً', () async {
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
  });
}
