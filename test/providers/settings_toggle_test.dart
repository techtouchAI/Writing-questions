import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

ExamDocument _document() {
  BranchModel branch(String text) => BranchModel(
        content: BranchContent(type: QuestionType.essay, text: text),
      );
  return ExamDocument(
    name: 'ورقة',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        branches: <BranchModel>[branch('أول'), branch('ثانٍ')],
      ),
      QuestionModel(
        questionNumber: 2,
        branches: <BranchModel>[branch('ثالث')],
      ),
    ],
  );
}

void main() {
  group('ExamWizardController autoLetterBranches toggle', () {
    test('disabling freezes the displayed branch labels', () {
      final controller = ExamWizardController(document: _document());
      controller.updateSettings(
        controller.document.settings.copyWith(autoLetterBranches: false),
      );

      final document = controller.document;
      expect(
        document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 0)).labelOverride,
        'أ',
      );
      expect(
        document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 1)).labelOverride,
        'ب',
      );
      expect(
        document.branchAt(const BranchRef(questionIndex: 1, branchIndex: 0)).labelOverride,
        'أ',
      );
    });

    test('frozen labels travel like manual numbering; re-enabling clears', () {
      final controller = ExamWizardController(document: _document());
      controller.updateSettings(
        controller.document.settings.copyWith(autoLetterBranches: false),
      );
      controller.moveBranch(0, 0, 1);

      // التسمية المثبتة تنتقل مع فرعها (كالأرقام المكتوبة يدوياً).
      expect(controller.document.displayBranchLabel(0, 0), 'ب');
      expect(
        controller.document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 0)).content.text,
        'ثانٍ',
      );
      expect(controller.document.displayBranchLabel(0, 1), 'أ');

      // الحذف لا يعيد ترقيم الباقي في الوضع اليدوي.
      controller.removeBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      expect(controller.document.displayBranchLabel(0, 0), 'أ');

      controller.updateSettings(
        controller.document.settings.copyWith(autoLetterBranches: true),
      );
      expect(
        controller.document
            .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
            .labelOverride,
        isNull,
      );
      expect(controller.document.displayBranchLabel(0, 0), 'أ');
    });

    test('keeps pre-existing manual labels when freezing', () {
      final controller = ExamWizardController(document: _document());
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      controller.updateBranchLabelOverride(ref, 'أولاً');
      controller.updateSettings(
        controller.document.settings.copyWith(autoLetterBranches: false),
      );
      expect(controller.document.branchAt(ref).labelOverride, 'أولاً');
      expect(controller.document.displayBranchLabel(0, 0), 'أولاً');
    });

    test('compact question style flows through the controller', () {
      final controller = ExamWizardController(document: _document());
      controller.updateSettings(
        controller.document.settings.copyWith(
          questionLabelStyle: QuestionLabelStyle.compact,
        ),
      );
      final document = controller.document;
      expect(document.displayQuestionLabel(document.questions[0]), 'س١');
      expect(document.displayQuestionLabel(document.questions[1]), 'س٢');
    });
  });
}
