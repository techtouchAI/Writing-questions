import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

/// ارتفاع صندوق المحتوى للهامش الافتراضي (15 مم) على لوحة المعاينة.
double get _pageHeight => PaperMetrics.pageContentHeightFor(PaperSettings.defaultMarginMm);

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

    test('addBranch adds أ then ب as empty branches', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.addBranch(0);

      final branches = controller.currentQuestion.branches;
      expect(branches, hasLength(2));
      expect(branches[0].content.isEmpty, isTrue);
      expect(branches[1].content.items, isEmpty);
      expect(controller.layout.branchLabel(1), 'ب');
    });

    test('branch edits are applied immutably and roll up into totals', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      final before = controller.document;

      controller.updateBranchStatement(ref, 'عرّف الفاعل');
      controller.updateBranchBody(ref, 'نص إضافي');
      controller.updateBranchMarks(ref, 4);

      expect(identical(before, controller.document), isFalse);
      expect(controller.document.branchAt(ref).content.statement, 'عرّف الفاعل');
      expect(controller.document.branchAt(ref).content.body, 'نص إضافي');
      expect(controller.document.totalMarks, 4);
      expect(before.totalMarks, 0);
    });

    test('question statement, body and raw marks are stored as typed', () {
      final controller = ExamWizardController();
      controller.updateQuestionStatement(0, 'اختر الإجابة الصحيحة');
      controller.updateQuestionBody(0, 'اقرأ النص ثم أجب');
      controller.updateQuestionMarksOverride(0, 20);
      controller.updateQuestionNumberOverride(0, ' س١/ ');

      final question = controller.currentQuestion;
      expect(question.statement, 'اختر الإجابة الصحيحة');
      expect(question.body, 'اقرأ النص ثم أجب');
      expect(question.marksOverride, 20);
      expect(question.numberOverride, 'س١/');

      // الفارغ يعيد الدرجة والرقم إلى التلقائي.
      controller.updateQuestionMarksOverride(0, null);
      controller.updateQuestionNumberOverride(0, '  ');
      expect(controller.currentQuestion.marksOverride, isNull);
      expect(controller.currentQuestion.numberOverride, isNull);
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

  group('ExamWizardController points (question and branch share one API)', () {
    const question = PointsOwner.question(0);
    final branch = PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 0));

    test('kinds mix in one group and numbering stays one continuous sequence', () {
      final controller = ExamWizardController();
      controller.addPoint(question, BranchItem(id: 'a', text: 'عبارة'));
      controller.addPoint(question, BranchItem(id: 'b', text: 'جملة'));
      controller.addPoint(question, BranchItem(id: 'c', text: 'سؤال'));
      controller.updatePointKind(question, 'a', PointKind.trueFalse);
      controller.updatePointKind(question, 'b', PointKind.fillBlank);
      controller.updatePointKind(question, 'c', PointKind.multipleChoice);

      final points = controller.questions.single.items;
      expect(points.map((point) => point.kind), <PointKind>[
        PointKind.trueFalse,
        PointKind.fillBlank,
        PointKind.multipleChoice,
      ]);
      final document = controller.document;
      expect(
        <String>[
          for (var i = 0; i < points.length; i++) document.displayItemLabel(points[i], i),
        ],
        <String>['١-', '٢-', '٣-'],
      );
      // نقطة «اختيار من متعدد» بدأت بأربعة خيارات فارغة.
      expect(points[2].options, hasLength(4));
    });

    test('edits a point by id so moves never retarget the wrong one', () {
      final controller = ExamWizardController();
      controller.addPoint(question, BranchItem(id: 'a', text: 'الأولى'));
      controller.addPoint(question, BranchItem(id: 'b', text: 'الثانية'));
      controller.movePoint(question, 1, 0);

      controller.updatePointText(question, 'a', 'الأولى معدّلة');
      expect(controller.questions.single.items.map((point) => point.text),
          <String>['الثانية', 'الأولى معدّلة']);
      controller.updatePointText(question, 'missing', 'x');
      expect(controller.questions.single.items, hasLength(2));

      controller.removePoint(question, 'b');
      expect(controller.questions.single.items.single.id, 'a');
    });

    test('updates an option text in place (بدون أي علم إجابة)', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.addPoint(
        branch,
        BranchItem(
          id: 'mc',
          kind: PointKind.multipleChoice,
          options: <QuestionOption>[
            QuestionOption(text: 'الأولى'),
            QuestionOption(text: 'الثانية'),
          ],
        ),
      );

      controller.updatePointOptionText(branch, 'mc', 1, 'الثانية معدّلة');
      controller.updatePointOptionText(branch, 'mc', 9, 'خارج النطاق');

      final options = controller.pointsOf(branch).single.options;
      expect(options, hasLength(2));
      expect(options[0].text, 'الأولى');
      expect(options[1].text, 'الثانية معدّلة');
      // الخيارات نصّية فقط: لا حقل إجابة ولا تمييز لخيار صحيح.
      expect(options.map((option) => option.toMap().containsKey('isCorrect')),
          everyElement(isFalse));
    });

    test('adds and removes options without any minimum', () {
      final controller = ExamWizardController();
      controller.addPoint(question, BranchItem(id: 'mc', kind: PointKind.multipleChoice));
      expect(controller.pointsOf(question).single.options, hasLength(4));

      controller.addPointOption(question, 'mc');
      expect(controller.pointsOf(question).single.options, hasLength(5));
      for (var remaining = 5; remaining > 0; remaining--) {
        controller.removePointOption(question, 'mc', 0);
      }
      expect(controller.pointsOf(question).single.options, isEmpty);
    });

    test('edits an option label without renumbering its siblings', () {
      final controller = ExamWizardController();
      controller.addPoint(question, BranchItem(id: 'mc', kind: PointKind.multipleChoice));

      controller.updatePointOptionLabel(question, 'mc', 1, 'B.');
      var document = controller.document;
      var options = controller.pointsOf(question).single.options;
      expect(options[1].labelOverride, 'B.');
      expect(document.displayOptionLabel(options[1], 1), 'B.');
      // البقية تلقائية بفهارسها الأصلية.
      expect(document.displayOptionLabel(options[0], 0), '( أ )');
      expect(document.displayOptionLabel(options[2], 2), '( ج )');

      // فارغ = عودة للتلقائي، `-` = إخفاء.
      controller.updatePointOptionLabel(question, 'mc', 1, '  ');
      expect(controller.pointsOf(question).single.options[1].labelOverride, isNull);
      controller.updatePointOptionLabel(question, 'mc', 1, '-');
      document = controller.document;
      options = controller.pointsOf(question).single.options;
      expect(options[1].labelOverride, '');
      expect(document.displayOptionLabel(options[1], 1), '');
    });

    test('edits a point label literally and ignores stale owners', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.addPoint(branch, BranchItem(id: 'p'));

      controller.updatePointLabel(branch, 'p', 'أ-');
      final document = controller.document;
      expect(document.displayItemLabel(controller.pointsOf(branch).single, 0), 'أ-');

      const stale = PointsOwner.question(7);
      controller.updatePointLabel(stale, 'p', 'x');
      controller.addPoint(PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 4)));
      expect(controller.pointsOf(stale), isEmpty);
      expect(controller.pointsOf(branch), hasLength(1));
    });

    test('setPointCount grows with empty points and trims from the end', () {
      final controller = ExamWizardController();
      controller.setPointCount(question, 3);
      expect(controller.pointsOf(question), hasLength(3));
      controller.updatePointText(question, controller.pointsOf(question).first.id, 'باقية');
      controller.setPointCount(question, 1);
      expect(controller.pointsOf(question).single.text, 'باقية');
      controller.setPointCount(question, 500);
      expect(controller.pointsOf(question), hasLength(200));
    });

    test('identical content does not add an undo step', () {
      final controller = ExamWizardController();
      controller.addPoint(question, BranchItem(id: 'a', text: 'نص'));
      controller.undo();
      controller.redo();
      final before = controller.document;
      controller.updatePointText(question, 'a', 'نص');
      expect(identical(controller.document, before), isTrue);
    });
  });

  group('ExamWizardController header and footer', () {
    test('updates the header and footer as one undoable step each', () {
      final controller = ExamWizardController();
      controller.updateHeader(
        controller.document.header.copyWith(schoolName: 'متوسطة حليف القرآن', time: 'ساعتان'),
      );
      controller.updateFooter(
        controller.document.footer.withSecondaryAdded(),
      );

      expect(controller.document.header.schoolName, 'متوسطة حليف القرآن');
      expect(controller.document.footer.hasSecondary, isTrue);
      controller.undo();
      expect(controller.document.footer.hasSecondary, isFalse);
      controller.undo();
      expect(controller.document.header.schoolName, isEmpty);
    });

    test('typing coalesces into a single history entry', () {
      final controller = ExamWizardController();
      for (final text in <String>['م', 'مد', 'مدر', 'مدرسة']) {
        controller.updateHeader(
          controller.document.header.copyWith(schoolName: text),
          coalesceKey: 'header-form',
        );
      }
      controller.updateFooter(const ExamFooterModel(closingPhrase: ''));
      expect(controller.document.header.schoolName, 'مدرسة');
      controller.undo(); // التذييل
      expect(controller.document.header.schoolName, 'مدرسة');
      controller.undo(); // كل ضربات الحروف دفعةً واحدة
      expect(controller.document.header.schoolName, isEmpty);
      expect(controller.canUndo, isFalse);
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
      controller.updateBranchStatement(q1a, 'محتوى الأول-أ');
      controller.updateBranchMarks(q1a, 5);
      controller.updateBranchStatement(q2b, 'محتوى الثاني-ب');
      controller.updateBranchMarks(q2b, 2);
      final firstId = controller.document.branchAt(q1a).id;

      controller.swapBranchContent(q1a, q2b);

      expect(controller.document.branchAt(q1a).content.statement, 'محتوى الثاني-ب');
      expect(controller.document.branchAt(q1a).marks, 2);
      expect(controller.document.branchAt(q1a).id, firstId);
      expect(controller.document.branchAt(q2b).content.statement, 'محتوى الأول-أ');
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

    test('floating elements exist and move without any question or branch', () {
      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'ورقة بلا أسئلة',
          header: ExamHeaderModel.initial(),
        ),
      );
      final element = square();

      expect(controller.addFloatingElement(element, pageIndex: 2), isTrue);
      expect(controller.document.questions, isEmpty);
      expect(controller.document.floatingElements.single.pageIndex, 2);

      controller.updateFloatingElement(element.copyWith(dx: 32, pageIndex: 1));
      expect(controller.document.floatingElements.single.dx, 32);
      expect(controller.document.floatingElements.single.pageIndex, 1);

      controller.removeFloatingElement(element.id);
      expect(controller.document.floatingElements, isEmpty);
      expect(controller.document.questions, isEmpty);
    });
  });

  group('ExamWizardController pagination', () {
    test('re-paginates from reported block heights without splitting questions', () {
      final controller = ExamWizardController();
      controller.goToNextQuestion();
      controller.goToNextQuestion();
      final ids = controller.questions.map((q) => q.id).toList();
      final pageHeight = _pageHeight;

      controller.reportBlockHeight(PaperMetrics.headerBlockId, 120);
      controller.reportBlockHeight(ids[0], pageHeight * 0.5);
      controller.reportBlockHeight(ids[1], pageHeight * 0.45);
      controller.reportBlockHeight(ids[2], pageHeight * 0.3);
      controller.reportBlockHeight(PaperMetrics.footerBlockId, 20);

      expect(controller.isFullyMeasured, isTrue);
      final pages = controller.pageAssignments;
      expect(pages, hasLength(2));
      expect(pages[0], <String>[ids[0]]);
      expect(pages[1], <String>[ids[1], ids[2]]);
      expect(controller.pagination.pageIndexOf(PaperMetrics.headerBlockId), 0);
    });

    test('the measured footer is reserved under the last block only', () {
      final controller = ExamWizardController();
      final id = controller.questions.single.id;
      final pageHeight = _pageHeight;

      controller.reportBlockHeight(PaperMetrics.headerBlockId, 100);
      controller.reportBlockHeight(id, pageHeight - 100 - PaperMetrics.blockSpacingPx - 5);
      // بلا تذييل مقيس: تتسع كل الكتل في صفحة واحدة.
      expect(controller.footerReserve, 0);
      expect(controller.isFullyMeasured, isFalse,
          reason: 'The zero footer reserve is provisional until the footer is measured.');
      expect(controller.pagination.pageCount, 1);

      controller.reportBlockHeight(PaperMetrics.footerBlockId, 60);
      expect(controller.isFullyMeasured, isTrue);
      expect(controller.footerReserve, 60 + PaperMetrics.blockSpacingPx);
      // السؤال الأخير لم يعد يتسع مع التذييل فانتقل كاملاً لصفحة جديدة.
      expect(controller.pagination.pageCount, 2);
      expect(controller.pageAssignments, <List<String>>[
        <String>[],
        <String>[id],
      ]);
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

    test('the page margin setting changes the content box used by pagination', () {
      final controller = ExamWizardController();
      final id = controller.questions.single.id;
      controller.reportBlockHeight(PaperMetrics.headerBlockId, 100);
      controller.reportBlockHeight(id, 850);
      expect(controller.pagination.pageCount, 1);

      // هامش أكبر ⇒ صندوق أقصر ⇒ لا يتسع السؤال مع الترويسة في الصفحة نفسها.
      controller.updateSettings(
        controller.document.settings.copyWith(marginMm: PaperSettings.maxMarginMm),
      );
      expect(controller.pagination.pageCount, 2);
    });
  });

  test('restores an existing document and exposes it unchanged', () {
    final original = ExamWizardController().document;
    final restored = ExamWizardController(document: original);
    expect(restored.document.id, original.id);
    expect(restored.document.questions.single.branches, isEmpty);
  });

  group('ExamWizardController branch handling', () {
    test('removes the last branch (no minimum)', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
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

    test('the branch number is typed by the teacher or derived from its index', () {
      final controller = ExamWizardController();
      controller.addBranch(0);
      controller.addBranch(0);
      const second = BranchRef(questionIndex: 0, branchIndex: 1);
      expect(controller.document.displayBranchLabel(0, 1), 'ب');

      controller.updateBranchLabelOverride(second, ' ثانياً ');
      expect(controller.document.displayBranchLabel(0, 1), 'ثانياً');
      controller.updateBranchLabelOverride(second, '');
      expect(controller.document.displayBranchLabel(0, 1), 'ب');
    });
  });
}
