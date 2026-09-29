import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';

void main() {
  group('TrueFalseFormat & ItemAlignment Models', () {
    test('BranchItem align field serializes and deserializes', () {
      final item = BranchItem(text: 'نقطة اختبار', align: PaperAlign.center);
      expect(item.align, PaperAlign.center);

      final map = item.toMap();
      expect(map['align'], 'center');

      final restored = BranchItem.fromMap(map);
      expect(restored.align, PaperAlign.center);
      expect(restored.text, 'نقطة اختبار');

      final copied = restored.copyWith(align: () => PaperAlign.left);
      expect(copied.align, PaperAlign.left);
    });

    test('BranchContent trueFalseFormat defaults to words and round-trips symbols', () {
      final defaultContent = BranchContent(type: QuestionType.trueFalse);
      expect(defaultContent.trueFalseFormat, 'words');
      expect(defaultContent.toMap().containsKey('trueFalseFormat'), isFalse);

      final symbolsContent = BranchContent(
        type: QuestionType.trueFalse,
        trueFalseFormat: 'symbols',
        items: [BranchItem(text: 'س1', isCorrect: true)],
      );
      expect(symbolsContent.trueFalseFormat, 'symbols');

      final map = symbolsContent.toMap();
      expect(map['trueFalseFormat'], 'symbols');

      final restored = BranchContent.fromMap(map);
      expect(restored.trueFalseFormat, 'symbols');
      expect(restored.items.single.text, 'س1');

      final duplicated = symbolsContent.duplicated();
      expect(duplicated.trueFalseFormat, 'symbols');
    });

    test('QuestionModel trueFalseFormat, titleAlign, promptAlign round-trip correctly', () {
      final question = QuestionModel(
        questionNumber: 1,
        trueFalseFormat: 'symbols',
        titleAlign: PaperAlign.center,
        promptAlign: PaperAlign.justify,
      );

      final map = question.toMap();
      expect(map['trueFalseFormat'], 'symbols');
      expect(map['titleAlign'], 'center');
      expect(map['promptAlign'], 'justify');

      final restored = QuestionModel.fromMap(map);
      expect(restored.trueFalseFormat, 'symbols');
      expect(restored.titleAlign, PaperAlign.center);
      expect(restored.promptAlign, PaperAlign.justify);

      final dup = question.duplicated(questionNumber: question.questionNumber);
      expect(dup.trueFalseFormat, 'symbols');
      expect(dup.titleAlign, PaperAlign.center);
      expect(dup.promptAlign, PaperAlign.justify);
    });

    test('ExamWizardController updates trueFalseFormat and alignments', () {
      final doc = ExamDocument(
        name: 'امتحان تجريبي',
        header: ExamHeaderModel.ministerialDefault(),
        questions: [
          QuestionModel(
            questionNumber: 1,
            prompt: 'نص السؤال الأول',
            branches: [
              BranchModel(
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  items: [BranchItem(text: 'العبارة الأولى', isCorrect: true)],
                ),
              ),
            ],
          ),
        ],
      );

      final controller = ExamWizardController(document: doc);
      expect(controller.questions.first.trueFalseFormat, 'words');

      controller.updateQuestionTrueFalseFormat(0, 'symbols');
      expect(controller.questions.first.trueFalseFormat, 'symbols');

      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      expect(controller.document.branchAt(ref).content.trueFalseFormat, 'words');

      controller.updateBranchTrueFalseFormat(ref, 'symbols');
      expect(controller.document.branchAt(ref).content.trueFalseFormat, 'symbols');

      controller.updateQuestionPromptAlign(0, PaperAlign.left);
      expect(controller.questions.first.promptAlign, PaperAlign.left);

      controller.updateQuestionTitleAlign(0, PaperAlign.center);
      expect(controller.questions.first.titleAlign, PaperAlign.center);
    });
  });
}
