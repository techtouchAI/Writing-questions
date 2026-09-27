import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_competition_app/models/branch_item.dart';
import 'package:writing_competition_app/models/branch_model.dart';
import 'package:writing_competition_app/models/exam_document.dart';
import 'package:writing_competition_app/models/exam_header.dart';
import 'package:writing_competition_app/models/question_model.dart';
import 'package:writing_competition_app/models/question_type.dart';
import 'package:writing_competition_app/services/docx_document_export_service.dart';

ExamDocument _document() => ExamDocument(
      name: 'اختبار',
      header: ExamHeader(
        ministry: 'وزارة التربية',
        educationBody: 'المديرية العامة',
        school: 'ابتدائية النور',
        grade: 'الخامس',
        subject: 'الرياضيات',
        date: '٢٠٢٦/٩/٢٧',
        timeAllowed: '٩٠ دقيقة',
        totalMarks: '٥٠ درجة',
        teacherName: 'أ. محمد',
        invigilatorName: 'أ. علي',
        notes: 'يمنع استخدام الآلة الحاسبة',
      ),
      questions: [
        QuestionModel(
          id: 'q1',
          type: QuestionType.multipleChoice,
          title: 'السؤال الأول',
          marks: 10,
          prompt: 'ما ناتج ٢ + ٢؟',
          options: ['أربعة', 'خمسة'],
          modelAnswer: 'أربعة',
          items: [
            BranchItem(id: 'qi1', label: '1)', text: 'نقطة السؤال الأولى'),
            BranchItem(id: 'qi2', text: 'نقطة السؤال الثانية'),
          ],
          branches: [
            BranchModel(
              id: 'b1',
              title: 'الفرع أ',
              marks: 5,
              items: [
                BranchItem(id: 'bi1', text: 'نص الفرع بعنصر'),
              ],
            ),
          ],
        ),
        QuestionModel(
          id: 'q2',
          type: QuestionType.trueFalse,
          title: 'السؤال الثاني',
          marks: 6,
          prompt: 'ضع علامة صح أو خطأ',
          branches: [
            BranchModel(
              id: 'b2',
              marks: 3,
              items: [
                BranchItem(id: 'bi2', text: '١ + ١ = ٢', isCorrect: true),
                BranchItem(id: 'bi3', text: '١ + ١ = ٣', isCorrect: false),
              ],
            ),
          ],
        ),
        QuestionModel(
          id: 'q3',
          type: QuestionType.essay,
          title: 'السؤال الثالث',
          marks: 4,
          prompt: 'اكتب مقالاً قصيراً',
          modelAnswer: 'مقال نموذجي',
          branches: [],
        ),
      ],
    );

Future<String> _documentXml(ExamDocument document, {required bool teacher}) async {
  final bytes = await DocumentExportService.buildDocumentDocxBytes(
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
    final xml = await _documentXml(_document(), teacher: false);

    // الترويسة بلا فقرة الدرجة الكلية وعدد الأسئلة.
    expect(xml.contains('الدرجة الكلية'), isFalse);
    expect(xml.contains('إجمالي الدرجات'), isFalse);
    expect(xml.contains('عدد الأسئلة'), isFalse);
    expect(xml.contains('نموذج الإجابة وتوزيع الدرجات للمعلم'), isFalse);

    // نقاط السؤال داخل السؤال مع ترقيم تلقائي للعناصر بلا تسمية.
    expect(xml.contains('•1) نقطة السؤال الأولى'), isTrue);
    expect(xml.contains('•2) نقطة السؤال الثانية'), isTrue);

    // نقاط الفرع مدرجة.
    expect(xml.contains('نص الفرع بعنصر'), isTrue);

    // لا مساحات إجابة مولَّدة على ورقة الطالب.
    expect(xml.contains('الإجابة:'), isFalse);
    expect(xml.contains('........................................'), isFalse);

    // الترتيب: نقطة السؤال تسبق الفرع.
    final qi = xml.indexOf('نقطة السؤال الأولى');
    final bi = xml.indexOf('نص الفرع بعنصر');
    expect(qi, greaterThan(-1));
    expect(bi, greaterThan(qi));

    // خيارات MCQ باقية في ورقة الطالب.
    expect(xml.contains('( أ ) أربعة'), isTrue);
  });

  test('نموذج المعلم: توزيع الدرجات كامل وبلا فقرة الدرجة الكلية العامة', () async {
    final xml = await _documentXml(_document(), teacher: true);

    expect(xml.contains('نموذج الإجابة وتوزيع الدرجات للمعلم'), isTrue);
    expect(xml.contains('الدرجة الكلية'), isFalse);
    expect(xml.contains('عدد الأسئلة'), isFalse);

    // إجابات العناصر في نموذج المعلم لصح/خطأ.
    expect(xml.contains('( صح )'), isTrue);
    expect(xml.contains('( خطأ )'), isTrue);
    expect(xml.contains('الإجابة النموذجية'), isTrue);
  });
}
