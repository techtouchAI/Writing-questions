import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

void main() {
  group('ExamWizardController wizard flow', () {
    test('starts with one question that has a single branch (أ)', () {
      final controller = ExamWizardController();
      expect(controller.questions, hasLength(1));
      expect(controller.currentQuestion.branches, hasLength(1));
      expect(controller.layout.questionLabel(controller.currentQuestion.questionNumber),
          'السؤال الأول');
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

    test('addBranch adds ب then ج with the same tooling', () {
      final controller = ExamWizardController();
      controller.addBranch(0, type: QuestionType.multipleChoice);
      controller.addBranch(0);

      final branches = controller.currentQuestion.branches;
      expect(branches, hasLength(3));
      expect(branches[1].content.type, QuestionType.multipleChoice);
      expect(controller.layout.branchLabel(2), 'ج');
    });

    test('branch edits are applied immutably and roll up into totals', () {
      final controller = ExamWizardController();
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

  group('ExamWizardController drag & drop', () {
    test('swapBranchContent keeps headings and exchanges content/marks only', () {
      final controller = ExamWizardController();
      controller.goToNextQuestion();
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
    expect(restored.document.questions.single.branches.single, isA<BranchModel>());
  });
}
