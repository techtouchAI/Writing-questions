import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

/// التطبيق لكتابة الأسئلة فقط: **لا عنصر إجابة في أي مرحلة**.
///
/// هذه الاختبارات تحرس ذلك من جهتين:
/// 1. لا سطح بيانات للإجابات في النموذج (لا `isCorrect` ولا إجابة نموذجية
///    ولا صيغة صح/خطأ)، وقوسا إجابة «صح/خطأ» الفارغان يُضافان عند الطباعة فقط.
/// 2. ملفات محفوظة بحقول إجابات قديمة تُقرأ بسلام وتُهمَل حقولها فلا
///    تُعاد كتابتها.
void main() {
  group('لا سطح للإجابات في النموذج', () {
    test('ملفات بحقول الإجابة تُقرأ بسلام وبلا إعادة كتابتها', () {
      final item = BranchItem.fromMap(<String, dynamic>{
        'id': 'i1',
        'text': 'الأرض كروية',
        'kind': 'trueFalse',
        'isCorrect': true,
      });
      expect(item.text, 'الأرض كروية');
      expect(item.kind, PointKind.trueFalse);
      expect(item.toMap().containsKey('isCorrect'), isFalse);

      final content = BranchContent.fromMap(<String, dynamic>{
        'statement': 'عبارة',
        'modelAnswer': 'إجابة قديمة',
        'modelAnswerAlign': 'center',
        'trueFalseFormat': 'symbols',
      });
      expect(content.statement, 'عبارة');
      final map = content.toMap();
      expect(map.containsKey('modelAnswer'), isFalse);
      expect(map.containsKey('modelAnswerAlign'), isFalse);
      expect(map.containsKey('trueFalseFormat'), isFalse);

      final question = QuestionModel.fromMap(<String, dynamic>{
        'questionNumber': 1,
        'branches': <Object?>[],
        'trueFalseFormat': 'symbols',
        'teacherVersion': true,
      });
      expect(question.toMap().containsKey('trueFalseFormat'), isFalse);
      expect(question.toMap().containsKey('teacherVersion'), isFalse);
    });

    test('نقطة صح/خطأ بلا نص لا تظهر، ولا خيارات تُطبع لغير الاختيار من متعدد', () {
      final emptyStatement = BranchContent(
        items: <BranchItem>[BranchItem(kind: PointKind.trueFalse)],
      );
      expect(emptyStatement.hasExportableContent, isFalse);

      for (final kind in <PointKind>[
        PointKind.plain,
        PointKind.trueFalse,
        PointKind.fillBlank,
      ]) {
        final point = BranchItem(
          kind: kind,
          options: <QuestionOption>[QuestionOption(text: 'خيار')],
        );
        expect(point.hasVisibleOptions, isFalse, reason: kind.name);
      }
      // الاختيار من متعدد وحده يعرض خياراته — بشرط أن يحمل الخيار نصاً.
      expect(BranchItem(kind: PointKind.multipleChoice).hasVisibleOptions, isFalse);
      expect(
        BranchItem(
          kind: PointKind.multipleChoice,
          options: <QuestionOption>[QuestionOption(text: 'خيار')],
        ).hasVisibleOptions,
        isTrue,
      );
    });
  });

  group('ترتيب النقاط يحفظ نصها ومحاذاتها', () {
    test('النقل يعيد ترتيب النصوص ويحفظ المحاذاة', () {
      final document = ExamDocument(
        name: 'ورقة',
        header: ExamHeaderModel.initial(subject: 'العلوم'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            items: <BranchItem>[
              BranchItem(id: 'i1', text: 'الأولى', align: PaperAlign.center),
              BranchItem(id: 'i2', text: 'الثانية', align: PaperAlign.left),
            ],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  items: <BranchItem>[
                    BranchItem(id: 'b1', text: 'عبارة أ', kind: PointKind.trueFalse),
                    BranchItem(id: 'b2', text: 'عبارة ب', kind: PointKind.trueFalse),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      final controller = ExamWizardController(document: document);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      controller.movePoint(const PointsOwner.question(0), 1, 0);
      expect(
        controller.questions.first.items.map((item) => item.text),
        <String>['الثانية', 'الأولى'],
      );
      expect(controller.questions.first.items.first.align, PaperAlign.left);
      expect(controller.questions.first.items.last.align, PaperAlign.center);

      controller.movePoint(PointsOwner.branch(ref), 1, 0);
      expect(
        controller.document.branchAt(ref).content.items.map((item) => item.text),
        <String>['عبارة ب', 'عبارة أ'],
      );
    });

    test('تعديلات المحاذاة والدرجة تعمل كما كانت', () {
      final document = ExamDocument(
        name: 'ورقة',
        header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            body: 'نص السؤال الأول',
            items: <BranchItem>[BranchItem(text: 'عبارة')],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  items: <BranchItem>[BranchItem(text: 'عبارة الفرع')],
                ),
              ),
            ],
          ),
        ],
      );

      final controller = ExamWizardController(document: document);
      controller.updateQuestionBodyAlign(0, PaperAlign.left);
      expect(controller.questions.first.bodyAlign, PaperAlign.left);
      controller.updateQuestionTitleAlign(0, PaperAlign.center);
      expect(controller.questions.first.titleAlign, PaperAlign.center);
    });
  });
}
