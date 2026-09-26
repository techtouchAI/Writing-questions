import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

void main() {
  group('ExamWizardController wizard flow', () {
    test('starts with one branchless question; branches are added explicitly', () {
      final controller = ExamWizardController();
      expect(controller.questions, hasLength(1));
      expect(controller.currentQuestion.branches, isEmpty);
      expect(controller.layout.questionLabel(controller.currentQuestion.questionNumber),
          'السؤال الأول');

      controller.addBranch(0);
      expect(controller.currentQuestion.branches, hasLength(1));
      expect(controller.layout.branchLabel(0), 'أ');
    });

    test('goToNextQuestion appends an empty question and opens it', () {
      final controller = ExamWizardController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.goToNextQuestion();

      expect(controller.questions, hasLength(2));
      expect(controller.currentQuestionIndex, 1);
      expect(controller.currentQuestion.questionNumber, 2);
      expect(notifications, greaterThan(0));

      controller.goToPreviousQuestion();
      expect(controller.currentQuestionIndex, 0);
      // العودة للتالي لا تضيف سؤالاً جديداً إن كان موجوداً.
      controller.goToNextQuestion();
      expect(controller.questions, hasLength(2));
    });

    test('addBranch adds أ then ب with the same tooling', () {
      final controller = ExamWizardController();
      controller.addBranch(0, type: QuestionType.multipleChoice);
      controller.addBranch(0);

      final branches = controller.currentQuestion.branches;
      expect(branches, hasLength(2));
      expect(branches[0].content.type, QuestionType.multipleChoice);
      expect(branches[1].content.type, QuestionType.multipleChoice);
      expect(controller.layout.branchLabel(1), 'ب');
    });

    test('branch edits are applied immutably and roll up into totals', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      final before = controller.document;

      controller.updateBranchText(ref, 'عرّف الفاعل');
      controller.updateBranchMarks(ref, 4);
      controller.updateBranchType(ref, QuestionType.fillInTheBlank);

      expect(identical(before, controller.document), isFalse);
      expect(controller.document.branchAt(ref).content.text, 'عرّف الفاعل');
      expect(controller.document.branchAt(ref).content.type, QuestionType.fillInTheBlank);
      expect(controller.document.totalMarks, 4);
      expect(before.totalMarks, 0);
    });

    test('a new branch starts with the same question type as the previous branch', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const first = BranchRef(questionIndex: 0, branchIndex: 0);
      controller.updateBranchType(first, QuestionType.multipleChoice);
      controller.updateBranchText(first, 'اختر الإجابة الصحيحة');

      controller.addBranch(0);
      controller.addBranch(0);

      final branches = controller.currentQuestion.branches;
      expect(branches, hasLength(3));
      // الفروع الجديدة تتبع «خيارات الفرع (أ)»: نفس النوع ونموذج الخيارات.
      expect(branches[1].content.type, QuestionType.multipleChoice);
      expect(branches[2].content.type, QuestionType.multipleChoice);
      expect(branches[1].content.options, hasLength(4));
      expect(branches[1].content.text, isEmpty);
    });

    test('removeQuestion keeps at least one question and renumbers', () {
      final controller = ExamWizardController();
      controller.goToNextQuestion();
      controller.goToNextQuestion();
      expect(controller.currentQuestionIndex, 2);

      controller.removeQuestion(2);
      expect(controller.questions, hasLength(2));
      expect(controller.currentQuestionIndex, 1);

      controller.removeQuestion(0);
      controller.removeQuestion(0);
      expect(controller.questions, hasLength(1));
      expect(controller.questions.single.questionNumber, 1);
    });
  });

  group('ExamWizardController in-place editing', () {
    test('updates an option text while keeping the correct-answer flag', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      controller.updateBranchType(ref, QuestionType.multipleChoice);
      controller.updateBranchContent(
        ref,
        controller.document.branchAt(ref).content.copyWith(
              options: <QuestionOption>[
                QuestionOption(text: 'الأولى', isCorrect: true),
                QuestionOption(text: 'الثانية'),
              ],
            ),
      );

      controller.updateBranchOptionText(ref, 1, 'الثانية معدّلة');
      controller.updateBranchOptionText(ref, 9, 'خارج النطاق');

      final options = controller.document.branchAt(ref).content.options;
      expect(options[0].text, 'الأولى');
      expect(options[0].isCorrect, isTrue);
      expect(options[1].text, 'الثانية معدّلة');
      expect(options[1].isCorrect, isFalse);
      expect(controller.document.branchAt(ref).content.type, QuestionType.multipleChoice);
    });

    test('updates the model answer used by the teacher version', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      expect(controller.document.branchAt(ref).content.modelAnswer, isEmpty);

      controller.updateBranchModelAnswer(ref, 'الإجابة: العَلم');

      expect(controller.document.branchAt(ref).content.modelAnswer, 'الإجابة: العَلم');
      expect(controller.document.branchAt(ref).content.type, QuestionType.essay);
    });
  });

  group('ExamWizardController drag & drop', () {
    test('swapBranchContent keeps headings and exchanges content/marks only', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.goToNextQuestion();
      controller.addBranch(1);
      controller.addBranch(1);
      const q1a = BranchRef(questionIndex: 0, branchIndex: 0);
      const q2b = BranchRef(questionIndex: 1, branchIndex: 1);
      controller.updateBranchText(q1a, 'محتوى الأول-أ');
      controller.updateBranchMarks(q1a, 5);
      controller.updateBranchText(q2b, 'محتوى الثاني-ب');
      controller.updateBranchMarks(q2b, 2);
      final firstId = controller.document.branchAt(q1a).id;

      controller.swapBranchContent(q1a, q2b);

      expect(controller.document.branchAt(q1a).content.text, 'محتوى الثاني-ب');
      expect(controller.document.branchAt(q1a).marks, 2);
      expect(controller.document.branchAt(q1a).id, firstId);
      expect(controller.document.branchAt(q2b).content.text, 'محتوى الأول-أ');
      expect(controller.document.branchAt(q2b).marks, 5);
      expect(controller.questions[0].questionNumber, 1);
      expect(controller.questions[1].questionNumber, 2);
    });
  });

  group('ExamWizardController attachments', () {
    FloatingElement square() => FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 0,
          dy: 0,
          width: 50,
          height: 50,
        );

    test('requires a selected branch and then anchors the element to it', () {
      final controller = ExamWizardController();
      expect(controller.addAttachment(square()), isFalse);

      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      controller.selectBranch(ref);
      final element = square();
      expect(controller.addAttachment(element), isTrue);
      expect(controller.document.branchAt(ref).attachments.single.id, element.id);

      controller.updateAttachment(ref, element.copyWith(dx: 40, width: 80));
      final updated = controller.document.branchAt(ref).attachments.single;
      expect(updated.dx, 40);
      expect(updated.width, 80);

      controller.removeAttachment(ref, element.id);
      expect(controller.document.branchAt(ref).attachments, isEmpty);
    });
  });

  group('ExamWizardController pagination', () {
    test('re-paginates from reported block heights without splitting questions', () {
      final controller = ExamWizardController();
      controller.goToNextQuestion();
      controller.goToNextQuestion();
      final ids = controller.questions.map((q) => q.id).toList();
      final pageHeight = PaperMetrics.pageContentHeightPx;

      controller.reportBlockHeight(PaperMetrics.headerBlockId, 120);
      controller.reportBlockHeight(ids[0], pageHeight * 0.5);
      controller.reportBlockHeight(ids[1], pageHeight * 0.45);
      controller.reportBlockHeight(ids[2], pageHeight * 0.3);

      expect(controller.isFullyMeasured, isTrue);
      final pages = controller.pageAssignments;
      expect(pages, hasLength(2));
      expect(pages[0], <String>[ids[0]]);
      expect(pages[1], <String>[ids[1], ids[2]]);
      expect(controller.pagination.pageIndexOf(PaperMetrics.headerBlockId), 0);
    });

    test('ignores sub-pixel height jitter to avoid rebuild loops', () {
      final controller = ExamWizardController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.reportBlockHeight(PaperMetrics.headerBlockId, 100);
      controller.reportBlockHeight(PaperMetrics.headerBlockId, 100.2);
      controller.reportBlockHeight(PaperMetrics.headerBlockId, 100.4);

      expect(notifications, 1);
      expect(controller.blockHeight(PaperMetrics.headerBlockId), 100);
    });

    test('unmeasured blocks are treated as empty until measured', () {
      final controller = ExamWizardController();
      expect(controller.isFullyMeasured, isFalse);
      expect(controller.pagination.pageCount, 1);
      expect(controller.pageAssignments.single, <String>[controller.questions.single.id]);
    });
  });

  test('restores an existing document and exposes it unchanged', () {
    final original = ExamWizardController().document;
    final restored = ExamWizardController(document: original);
    expect(restored.document.id, original.id);
    expect(restored.document.questions.single.branches, isEmpty);
  });

  group('ExamWizardController flexible labels', () {
    test('edits an option label without renumbering its siblings', () {
      final controller = ExamWizardController();
      controller.addBranch(0, type: QuestionType.multipleChoice);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      controller.updateBranchOptionLabel(ref, 1, 'B.');
      final document = controller.document;
      final options = document.branchAt(ref).content.options;
      expect(options[1].labelOverride, 'B.');
      expect(document.displayOptionLabel(options[1], 1), 'B.');
      // البقية تلقائية بفهارسها الأصلية.
      expect(document.displayOptionLabel(options[0], 0), '( أ )');
      expect(document.displayOptionLabel(options[2], 2), '( ج )');

      // فارغ = عودة للتلقائي، `-` = إخفاء.
      controller.updateBranchOptionLabel(ref, 1, '  ');
      expect(
        controller.document.branchAt(ref).content.options[1].labelOverride,
        isNull,
      );
      controller.updateBranchOptionLabel(ref, 1, '-');
      expect(
        controller.document.branchAt(ref).content.options[1].labelOverride,
        '',
      );
      expect(
        controller.document.displayOptionLabel(
          controller.document.branchAt(ref).content.options[1],
          1,
        ),
        '',
      );
    });

    test('edits an item label literally and ignores out-of-range edits', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      controller.addBranchItem(ref);

      controller.updateBranchItemLabel(ref, 0, 'أ-');
      final document = controller.document;
      expect(
        document.displayItemLabel(document.branchAt(ref).content.items[0], 0),
        'أ-',
      );

      controller.updateBranchItemLabel(ref, 5, 'x');
      controller.updateBranchItemLabel(
        const BranchRef(questionIndex: 0, branchIndex: 4),
        0,
        'x',
      );
      expect(document.branchAt(ref).content.items, hasLength(1));
    });

    test('removes the last branch and the last option (no minimums)', () {
      final controller = ExamWizardController();
      controller.addBranch(0, type: QuestionType.multipleChoice);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);

      for (var remaining = 4; remaining > 0; remaining--) {
        controller.removeBranchOption(ref, 0);
      }
      expect(controller.document.branchAt(ref).content.options, isEmpty);

      controller.removeBranch(ref);
      expect(controller.questions.single.branches, isEmpty);
    });

    test('ignores branch moves with stale indices instead of throwing', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.moveBranch(0, 0, 5);
      controller.moveBranch(0, 4, 0);
      expect(controller.questions.single.branches, hasLength(1));
    });
  });
}
