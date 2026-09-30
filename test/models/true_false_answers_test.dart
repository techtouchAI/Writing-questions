import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

/// صح/خطأ: الإجابات تُحفظ في النموذج للتصحيح **ولا تُكتب على الورقة** —
/// لا كلمة «صح/خطأ» ولا علامة (✓/✗) ولا سطر «الإجابة الصحيحة»، تماماً
/// كالفراغات. الإجابات تُضبط مجمّعةً بترتيب العبارات (خيار واحد لكل عبارة).
void main() {
  group('True/false answers stay in the model and off the paper', () {
    test('BranchItem answers round-trip through storage', () {
      final item = BranchItem(text: 'الأرض كروية', isCorrect: true, align: PaperAlign.center);
      final map = item.toMap();
      expect(map['isCorrect'], isTrue);

      final restored = BranchItem.fromMap(map);
      expect(restored.isCorrect, isTrue);
      expect(restored.align, PaperAlign.center);

      final cleared = restored.copyWith(isCorrect: () => null);
      expect(cleared.isCorrect, isNull);
      expect(cleared.copyWith(isCorrect: () => false).isCorrect, isFalse);
    });

    test('BranchContent keeps per-item answers and the branch-level answer', () {
      final content = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[
          BranchItem(id: 'i1', text: 'عبارة أولى', isCorrect: true),
          BranchItem(id: 'i2', text: 'عبارة ثانية', isCorrect: false),
        ],
      );

      final restored = BranchContent.fromMap(content.toMap());
      expect(restored.items.map((item) => item.isCorrect), <bool?>[true, false]);

      final duplicated = content.duplicated();
      expect(duplicated.items.map((item) => item.isCorrect), <bool?>[true, false]);

      // الفرع بلا نقاط: إجابة واحدة للعبارة الواحدة.
      final single = BranchContent.empty(QuestionType.trueFalse);
      expect(single.trueFalseAnswer, isTrue);
      expect(single.withTrueFalseAnswer(false).trueFalseAnswer, isFalse);
    });

    test('legacy trueFalseFormat in stored files is ignored (no crash, no re-save)', () {
      // ملفات محفوظة سابقاً تحمل الحقل القديم: تُقرأ بسلام ولا يُعاد كتابته.
      final branchMap = <String, dynamic>{
        'type': 'trueFalse',
        'text': 'عبارة',
        'options': const <Object?>[],
        'modelAnswer': '',
        'trueFalseFormat': 'symbols',
      };
      final content = BranchContent.fromMap(branchMap);
      expect(content.type, QuestionType.trueFalse);
      expect(content.toMap().containsKey('trueFalseFormat'), isFalse);

      final questionMap = <String, dynamic>{
        'questionNumber': 1,
        'type': 'trueFalse',
        'branches': <Object?>[],
        'trueFalseFormat': 'symbols',
      };
      final question = QuestionModel.fromMap(questionMap);
      expect(question.toMap().containsKey('trueFalseFormat'), isFalse);
    });

    test('no printable type body nor answer-only items for true/false', () {
      final withItems = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[BranchItem(text: 'عبارة', isCorrect: true)],
      );
      expect(withItems.hasPrintableTypeBody(), isFalse);
      expect(withItems.hasPrintableTypeBody(), isFalse);

      final answerOnly = BranchContent(
        type: QuestionType.trueFalse,
        items: <BranchItem>[BranchItem()],
      );
      expect(answerOnly.hasExportableContent(), isFalse);
      expect(answerOnly.hasExportableContent(), isFalse);

      // الإجابة النموذجية لبقية الأنواع تبقى في نموذج المعلم وحده.
      final essay = BranchContent(type: QuestionType.essay, );
      expect(essay.hasPrintableTypeBody(), isFalse);
      expect(essay.hasPrintableTypeBody(), isTrue);
    });

    test('answers follow the statements when they are reordered', () {
      final document = ExamDocument(
        name: 'ورقة',
        header: ExamHeaderModel.ministerialDefault(subject: 'العلوم'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            type: QuestionType.trueFalse,
            items: <BranchItem>[
              BranchItem(id: 'i1', text: 'الأولى', isCorrect: true),
              BranchItem(id: 'i2', text: 'الثانية', isCorrect: false),
            ],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  items: <BranchItem>[
                    BranchItem(id: 'b1', text: 'عبارة أ', isCorrect: false),
                    BranchItem(id: 'b2', text: 'عبارة ب', isCorrect: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      final controller = ExamWizardController(document: document);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      // الإجابات مقترنة بعباراتها لا بمواضعها.
      controller.moveQuestionItem(0, 1, 0);
      expect(
        controller.questions.first.items.map((item) => item.text),
        <String>['الثانية', 'الأولى'],
      );
      expect(
        controller.questions.first.items.map((item) => item.isCorrect),
        <bool?>[false, true],
      );

      controller.moveBranchItem(ref, 1, 0);
      expect(
        controller.document.branchAt(ref).content.items.map((item) => item.isCorrect),
        <bool?>[true, false],
      );
    });

    test('controller edits grouped answers and keeps alignments working', () {
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
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      controller.updateQuestionItemAnswer(0, 0, true);
      expect(controller.questions.first.items.single.isCorrect, isTrue);
      controller.updateQuestionItemAnswer(0, 0, null);
      expect(controller.questions.first.items.single.isCorrect, isNull);

      controller.updateBranchItemAnswer(ref, 0, false);
      expect(controller.document.branchAt(ref).content.items.single.isCorrect, isFalse);

      // الفرع بلا نقاط: «خيار واحد» لإجابة الفرع.
      controller.updateBranchTrueFalseAnswer(ref, false);
      expect(controller.document.branchAt(ref).content.trueFalseAnswer, isFalse);
      controller.updateBranchTrueFalseAnswer(ref, true);
      expect(controller.document.branchAt(ref).content.trueFalseAnswer, isTrue);

      controller.updateQuestionPromptAlign(0, PaperAlign.left);
      expect(controller.questions.first.promptAlign, PaperAlign.left);
      controller.updateQuestionTitleAlign(0, PaperAlign.center);
      expect(controller.questions.first.titleAlign, PaperAlign.center);
    });
  });
}
