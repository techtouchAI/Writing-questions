import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

/// التطبيق لكتابة الأسئلة فقط: **لا عنصر إجابة في أي مرحلة**.
///
/// هذه الاختبارات تحرس ذلك من جهتين:
/// 1. لا سطح بيانات للإجابات في النموذج (لا `isCorrect` ولا إجابة نموذجية
///    ولا صيغة صح/خطأ)، ولا جسم مطبوع لأنواع لا يُطبع لها جسم.
/// 2. ملفات محفوظة بالصيغة القديمة (تحمل حقول الإجابات) تُقرأ بسلام وتُهمَل
///    حقولها فلا تُعاد كتابتها.
void main() {
  group('لا سطح للإجابات في النموذج', () {
    test('ملفات قديمة بحقول الإجابة تُقرأ بسلام وبلا إعادة كتابتها', () {
      final item = BranchItem.fromMap(<String, dynamic>{
        'id': 'i1',
        'text': 'الأرض كروية',
        'isCorrect': true,
      });
      expect(item.text, 'الأرض كروية');
      expect(item.toMap().containsKey('isCorrect'), isFalse);

      final content = BranchContent.fromMap(<String, dynamic>{
        'type': 'trueFalse',
        'text': 'عبارة',
        'options': const <Object?>[],
        'modelAnswer': 'إجابة قديمة',
        'modelAnswerAlign': 'center',
        'trueFalseFormat': 'symbols',
      });
      expect(content.type, QuestionType.trueFalse);
      final map = content.toMap();
      expect(map.containsKey('modelAnswer'), isFalse);
      expect(map.containsKey('modelAnswerAlign'), isFalse);
      expect(map.containsKey('trueFalseFormat'), isFalse);

      final question = QuestionModel.fromMap(<String, dynamic>{
        'questionNumber': 1,
        'type': 'trueFalse',
        'branches': <Object?>[],
        'trueFalseFormat': 'symbols',
        'teacherVersion': true,
      });
      expect(question.toMap().containsKey('trueFalseFormat'), isFalse);
      expect(question.toMap().containsKey('teacherVersion'), isFalse);
    });

    test('صح/خطأ بلا جسم مطبوع وبلا عبارة إجابة-فقط', () {
      final withItems = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[BranchItem(text: 'عبارة')],
      );
      expect(withItems.hasPrintableTypeBody, isFalse);

      final emptyStatement = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[BranchItem()],
      );
      expect(emptyStatement.hasExportableContent, isFalse);
    });

    test('الفراغات والمقالي بلا جسم مطبوع أيضاً (مساحتها في نص الفرع)', () {
      for (final type in <QuestionType>[
        QuestionType.fillInTheBlank,
        QuestionType.definitions,
        QuestionType.essay,
      ]) {
        expect(BranchContent(type: type).hasPrintableTypeBody, isFalse);
      }
      // الاختيار من متعدد وحده له جسم مطبوع — بشرط أن يحمل الخيار نصاً.
      expect(BranchContent.empty(QuestionType.multipleChoice).hasPrintableTypeBody, isFalse);
      expect(
        BranchContent(
          type: QuestionType.multipleChoice,
          options: <QuestionOption>[QuestionOption(text: 'خيار')],
        ).hasPrintableTypeBody,
        isTrue,
      );
    });
  });

  group('ترتيب العبارات يحفظ نصها ومحاذاتها', () {
    test('النقل يعيد ترتيب النصوص ويحفظ المحاذاة', () {
      final document = ExamDocument(
        name: 'ورقة',
        header: ExamHeaderModel.ministerialDefault(subject: 'العلوم'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            type: QuestionType.trueFalse,
            items: <BranchItem>[
              BranchItem(id: 'i1', text: 'الأولى', align: PaperAlign.center),
              BranchItem(id: 'i2', text: 'الثانية', align: PaperAlign.left),
            ],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  items: <BranchItem>[
                    BranchItem(id: 'b1', text: 'عبارة أ'),
                    BranchItem(id: 'b2', text: 'عبارة ب'),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      final controller = ExamWizardController(document: document);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      controller.moveQuestionItem(0, 1, 0);
      expect(
        controller.questions.first.items.map((item) => item.text),
        <String>['الثانية', 'الأولى'],
      );
      expect(controller.questions.first.items.first.align, PaperAlign.left);
      expect(controller.questions.first.items.last.align, PaperAlign.center);

      controller.moveBranchItem(ref, 1, 0);
      expect(
        controller.document.branchAt(ref).content.items.map((item) => item.text),
        <String>['عبارة ب', 'عبارة أ'],
      );
    });

    test('تعديلات المحاذاة والدرجة تعمل كما كانت', () {
      final document = ExamDocument(
        name: 'ورقة',
        header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            prompt: 'نص السؤال الأول',
            items: <BranchItem>[BranchItem(text: 'عبارة')],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  items: <BranchItem>[BranchItem(text: 'عبارة الفرع')],
                ),
              ),
            ],
          ),
        ],
      );

      final controller = ExamWizardController(document: document);
      controller.updateQuestionPromptAlign(0, PaperAlign.left);
      expect(controller.questions.first.promptAlign, PaperAlign.left);
      controller.updateQuestionTitleAlign(0, PaperAlign.center);
      expect(controller.questions.first.titleAlign, PaperAlign.center);
    });
  });
}
