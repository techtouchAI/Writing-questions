import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

ExamDocument _document() => ExamDocument(
      name: 'اختبار',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'القسم الأول',
          prompt: 'ما ناتج ٢ + ٢؟',
          marksOverride: 10,
          items: <BranchItem>[
            BranchItem(id: 'qi1', text: 'نقطة السؤال الأولى'),
            BranchItem(id: 'qi2', text: 'نقطة السؤال الثانية'),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                type: QuestionType.multipleChoice,
                text: 'اختر الإجابة',
                options: <QuestionOption>[
                  QuestionOption(text: 'أربعة', isCorrect: true),
                  QuestionOption(text: 'خمسة'),
                ],
                items: <BranchItem>[
                  BranchItem(id: 'bi1', text: 'نص الفرع بعنصر'),
                ],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          prompt: 'ضع علامة صح أو خطأ',
          marksOverride: 6,
          branches: <BranchModel>[
            BranchModel(
              id: 'b2',
              marks: 3,
              content: BranchContent(
                type: QuestionType.trueFalse,
                items: <BranchItem>[
                  BranchItem(id: 'bi2', text: '١ + ١ = ٢', isCorrect: true),
                  BranchItem(id: 'bi3', text: '١ + ١ = ٣', isCorrect: false),
                ],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q3',
          questionNumber: 3,
          prompt: 'اكتب مقالاً قصيراً',
          marksOverride: 4,
          branches: <BranchModel>[
            BranchModel(
              id: 'b3',
              marks: 4,
              content: BranchContent(
                type: QuestionType.essay,
                modelAnswer: 'مقال نموذجي',
              ),
            ),
          ],
        ),
      ],
    );

Future<String> _documentXml(ExamDocument document, {required bool teacher}) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
    isTeacherVersion: teacher,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  final xml = archive.findFile('word/document.xml');
  expect(xml, isNotNull);
  return utf8.decode(xml!.content as List<int>);
}

void main() {
  test('ورقة الطالب: الأسئلة فقط — نقاط السؤال مدرجة والترقيم تلقائي وبلا مساحات إجابة', () async {
    final document = _document();
    final xml = await _documentXml(document, teacher: false);

    // الترويسة بلا فقرة الدرجة الكلية وعدد الأسئلة.
    expect(xml.contains('الدرجة الكلية'), isFalse);
    expect(xml.contains('عدد الأسئلة'), isFalse);
    expect(xml.contains('نموذج الإجابة وتوزيع الدرجات للمعلم'), isFalse);

    // نقاط السؤال داخل السؤال مع الترقيم التلقائي من نموذج المستند نفسه.
    expect(xml.contains('${document.autoItemLabel(0)} نقطة السؤال الأولى'), isTrue);
    expect(xml.contains('${document.autoItemLabel(1)} نقطة السؤال الثانية'), isTrue);

    // نقاط الفرع مدرجة بنفس الترقيم التلقائي.
    expect(xml.contains('${document.autoItemLabel(0)} نص الفرع بعنصر'), isTrue);

    // لا مساحات إجابة مولَّدة على ورقة الطالب (الإجابة في دفتر الطالب).
    expect(xml.contains('الإجابة:'), isFalse);
    expect(xml.contains('الإجابة النموذجية'), isFalse);
    expect(xml.contains('........................................'), isFalse);

    // الترتيب: القسم ثم نقطة السؤال تسبق الفرع.
    final qi = xml.indexOf('نقطة السؤال الأولى');
    final bi = xml.indexOf('نص الفرع بعنصر');
    expect(qi, greaterThan(-1));
    expect(bi, greaterThan(qi));
    expect(xml.indexOf('القسم الأول'), lessThan(qi));

    // خيارات MCQ باقية في ورقة الطالب.
    expect(xml.contains('أربعة'), isTrue);
    expect(xml.contains('خمسة'), isTrue);
  });

  test('نموذج المعلم: توزيع الدرجات كامل وبلا فقرة الدرجة الكلية العامة', () async {
    final document = _document();
    final xml = await _documentXml(document, teacher: true);

    expect(xml.contains('نموذج الإجابة وتوزيع الدرجات للمعلم'), isTrue);
    expect(xml.contains('الدرجة الكلية'), isFalse);
    expect(xml.contains('عدد الأسئلة'), isFalse);

    // إجابات عناصر صح/خطأ في نموذج المعلم وحده.
    expect(xml.contains('( صح )'), isTrue);
    expect(xml.contains('( خطأ )'), isTrue);
    expect(xml.contains('الإجابة النموذجية'), isTrue);
  });
}
