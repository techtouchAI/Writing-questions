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
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: 'سؤال',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
