import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
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

Future<String> _documentXml(
  ExamDocument document, {
  required bool teacher,
  List<List<String>>? pageAssignments,
}) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
    isTeacherVersion: teacher,
    pageAssignments: pageAssignments,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  final xml = archive.findFile('word/document.xml');
  expect(xml, isNotNull);
  return utf8.decode(xml!.content as List<int>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // إجابات صح/خطأ لا تُكتب على الورقة إطلاقاً — لا في ورقة الطالب ولا في
    // نموذج المعلم (كما في الفراغات: العبارات وحدها بالترتيب).
    expect(xml.contains('(صح)'), isFalse);
    expect(xml.contains('(خطأ)'), isFalse);
    expect(xml.contains('الإجابة الصحيحة'), isFalse);
    // أما الإجابات النموذجية (فراغ/مقالي) فتبقى في نموذج المعلم.
    expect(xml.contains('الإجابة النموذجية'), isTrue);
  });

  test('uses paragraph spacing and line height while coloring only the title', () async {
    final document = ExamDocument(
      name: 'تنسيق مستقل',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'styled',
          questionNumber: 1,
          prompt: 'متن السؤال غير الملوّن',
          style: const PaperTextStyle(
            color: 0xFF12AB34,
            lineHeight: 1.5,
            paragraphSpacing: 6,
          ),
          items: <BranchItem>[BranchItem(id: 'item', text: 'نقطة السؤال')],
          branches: <BranchModel>[
            BranchModel(
              id: 'choices',
              style: const PaperTextStyle(lineHeight: 1.25, paragraphSpacing: 12),
              content: BranchContent(
                type: QuestionType.multipleChoice,
                text: 'اختر الإجابة',
                options: <QuestionOption>[QuestionOption(text: 'الخيار الأول')],
              ),
            ),
          ],
        ),
      ],
    );
    final xml = await _documentXml(document, teacher: false);
    final questionSpacingTwips = (PaperMetrics.pt(6) * 20).round();
    final optionSpacingTwips = (PaperMetrics.pt(12) * 20).round();

    expect(RegExp('w:color w:val="12AB34"').allMatches(xml), hasLength(1));
    expect(xml.contains('متن السؤال غير الملوّن'), isTrue);
    expect(xml.contains('نقطة السؤال'), isTrue);
    expect(xml.contains('w:line="360"'), isTrue);
    expect(xml.contains('w:line="300"'), isTrue);
    expect(xml.contains('w:after="$questionSpacingTwips"'), isTrue);
    expect(xml.contains('w:after="$optionSpacingTwips"'), isTrue);
  });

  test('omits empty editable questions and rejects stale page assignments', () async {
    final document = ExamDocument(
      name: 'أسئلة قابلة للطباعة',
      header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'empty',
          questionNumber: 1,
          category: 'لا ينبغي تصدير هذا القسم',
        ),
        QuestionModel(
          id: 'visible',
          questionNumber: 2,
          prompt: 'السؤال الذي يظهر في الملف',
        ),
      ],
    );
    final xml = await _documentXml(
      document,
      teacher: false,
      pageAssignments: const <List<String>>[
        <String>['empty', 'visible'],
      ],
    );

    expect(xml.contains('لا ينبغي تصدير هذا القسم'), isFalse);
    expect(xml.contains('السؤال الذي يظهر في الملف'), isTrue);
    expect(xml.contains('<w:br w:type="page"/>'), isFalse);
  });
}
