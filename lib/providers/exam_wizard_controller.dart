import 'package:flutter/foundation.dart';

import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_model.dart';
import '../models/exam_document.dart';
import '../models/exam_header_model.dart';
import '../models/floating_element.dart';
import '../models/question_model.dart';
import '../models/question_type.dart';
import '../models/subject_layout.dart';

/// حالة معالج إنشاء النموذج الوزاري (Wizard) وشاشة المعاينة A4.
///
/// يفصل واجهة المستخدم عن:
/// 1. **تبديل المحتوى عند السحب والإفلات** ([swapBranchContent]) — يبدّل
///    المحتوى والدرجة فقط ويُبقي الهيكل الرقمي ثابتاً.
/// 2. **التقسيم الورقي** ([pagination]) — يُعاد حسابه من ارتفاعات الكتل
///    المقاسة ديناميكياً عبر [PaginationEngine] بحيث لا يُفصل سؤال عن فروعه.
///
/// كل تعديل ينتج نسخة جديدة غير قابلة للتغيير من [ExamDocument].
class ExamWizardController extends ChangeNotifier {
  ExamWizardController({ExamDocument? document})
      : _document = document ??
            ExamDocument(
              name: 'نموذج وزاري جديد',
              header: ExamHeaderModel.ministerialDefault(),
              questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
            ),
        _currentQuestionIndex = 0;

  ExamDocument _document;
  int _currentQuestionIndex;
  BranchRef? _selectedBranch;
  final Map<String, double> _blockHeights = <String, double>{};
  PaginationResult? _paginationCache;

  ExamDocument get document => _document;
  SubjectLayoutTemplate get layout => _document.layout;
  List<QuestionModel> get questions => _document.questions;

  /// فهرس السؤال المفتوح حالياً في خطوة «إعداد السؤال».
  int get currentQuestionIndex => _currentQuestionIndex;
  QuestionModel get currentQuestion => questions[_currentQuestionIndex];

  BranchRef? get selectedBranch =>
      _selectedBranch != null && _document.containsRef(_selectedBranch!)
          ? _selectedBranch
          : null;

  // ============================ الترويسة ============================

  void updateHeader(ExamHeaderModel header) {
    _commit(_document.copyWith(header: header));
  }

  void updateHeaderLine(HeaderSlot slot, int lineIndex, String value) {
    _commit(_document.copyWith(header: _document.header.withLine(slot, lineIndex, value)));
  }

  void updateInstructions(String value) {
    _commit(_document.copyWith(header: _document.header.copyWith(instructions: value)));
  }

  void updateSubject(String subject) {
    _commit(_document.copyWith(header: _document.header.copyWith(subject: subject)));
  }

  void updateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _document.name) {
      return;
    }
    _commit(_document.copyWith(name: trimmed));
  }

  // ============================ الأسئلة ============================

  /// يحفظ السؤال الحالي ويفتح سؤالاً جديداً فارغاً («إعداد السؤال التالي»).
  void goToNextQuestion() {
    if (_currentQuestionIndex == questions.length - 1) {
      _commit(_document.withQuestionAdded());
    }
    _currentQuestionIndex += 1;
    notifyListeners();
  }

  void goToPreviousQuestion() {
    if (_currentQuestionIndex == 0) {
      return;
    }
    _currentQuestionIndex -= 1;
    notifyListeners();
  }

  void openQuestion(int index) {
    RangeError.checkValidIndex(index, questions, 'index');
    _currentQuestionIndex = index;
    notifyListeners();
  }

  void addQuestion() {
    _commit(_document.withQuestionAdded());
  }

  /// يحذف السؤال ويُعيد الترقيم (يبقى سؤال واحد على الأقل).
  void removeQuestion(int index) {
    if (questions.length == 1) {
      return;
    }
    _blockHeights.remove(questions[index].id);
    _commit(_document.withQuestionRemoved(index));
    if (_currentQuestionIndex >= questions.length) {
      _currentQuestionIndex = questions.length - 1;
    }
  }

  void updateQuestionCategory(int index, String category) {
    _commit(_document.withQuestionAt(index, questions[index].copyWith(category: category)));
  }

  // ============================ الفروع ============================

  void addBranch(int questionIndex, {QuestionType? type}) {
    final template = type == null ? null : BranchModel(content: BranchContent.empty(type));
    _commit(_document.withQuestionAt(
      questionIndex,
      questions[questionIndex].withBranchAdded(template),
    ));
  }

  void removeBranch(BranchRef ref) {
    if (!_document.containsRef(ref)) {
      return;
    }
    _commit(_document.withQuestionAt(
      ref.questionIndex,
      questions[ref.questionIndex].withBranchRemoved(ref.branchIndex),
    ));
  }

  void updateBranchContent(BranchRef ref, BranchContent content) {
    if (!_document.containsRef(ref)) {
      return;
    }
    _commit(_document.withBranchAt(ref, _document.branchAt(ref).copyWith(content: content)));
  }

  void updateBranchType(BranchRef ref, QuestionType type) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.type == type) {
      return;
    }
    updateBranchContent(ref, branch.content.copyWith(type: type));
  }

  void updateBranchText(BranchRef ref, String text) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.text == text) {
      return;
    }
    updateBranchContent(ref, branch.content.copyWith(text: text));
  }

  void updateBranchMarks(BranchRef ref, double marks) {
    if (!_document.containsRef(ref) || !marks.isFinite || marks < 0) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.marks == marks) {
      return;
    }
    _commit(_document.withBranchAt(ref, branch.copyWith(marks: marks)));
  }

  /// **القاعدة الذهبية**: يبدّل المحتوى والدرجة فقط بين خانتين؛ العناوين
  /// (السؤال الأول، الفرع أ) تبقى في مكانها.
  void swapBranchContent(BranchRef from, BranchRef to) {
    final updated = _document.swapBranchContent(from, to);
    if (identical(updated, _document)) {
      return;
    }
    _commit(updated);
  }

  void selectBranch(BranchRef? ref) {
    if (_selectedBranch == ref) {
      return;
    }
    _selectedBranch = ref;
    notifyListeners();
  }

  // ============================ المرفقات (الأدوات العائمة) ============================

  /// يضيف صورة/شكلاً فوق مساحة الفرع [ref] (أو الفرع المحدد حالياً).
  ///
  /// يعيد `false` إن لم يكن هناك فرع مستهدف.
  bool addAttachment(FloatingElement element, {BranchRef? ref}) {
    final target = ref ?? selectedBranch;
    if (target == null || !_document.containsRef(target)) {
      return false;
    }
    final branch = _document.branchAt(target);
    _commit(_document.withBranchAt(
      target,
      branch.copyWith(attachments: <FloatingElement>[...branch.attachments, element]),
    ));
    return true;
  }

  void updateAttachment(BranchRef ref, FloatingElement element) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    final index = branch.attachments.indexWhere((item) => item.id == element.id);
    if (index == -1) {
      return;
    }
    final attachments = List<FloatingElement>.of(branch.attachments)..[index] = element;
    _commit(_document.withBranchAt(ref, branch.copyWith(attachments: attachments)));
  }

  void removeAttachment(BranchRef ref, String elementId) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    final attachments =
        branch.attachments.where((item) => item.id != elementId).toList(growable: false);
    if (attachments.length == branch.attachments.length) {
      return;
    }
    _commit(_document.withBranchAt(ref, branch.copyWith(attachments: attachments)));
  }

  // ============================ التقسيم الورقي ============================

  /// تُبلّغ اللوحة عن الارتفاع المقاس لكتلة (الترويسة أو سؤال كامل).
  ///
  /// لا يُعاد الحساب إلا عند تغيّر فعلي يتجاوز نصف بكسل، لتجنّب حلقات
  /// إعادة البناء.
  void reportBlockHeight(String blockId, double height) {
    final previous = _blockHeights[blockId];
    if (previous != null && (previous - height).abs() < 0.5) {
      return;
    }
    _blockHeights[blockId] = height;
    _paginationCache = null;
    notifyListeners();
  }

  double? blockHeight(String blockId) => _blockHeights[blockId];

  /// هل قيست كل الكتل (الترويسة وكل الأسئلة)؟
  bool get isFullyMeasured =>
      _blockHeights.containsKey(PaperMetrics.headerBlockId) &&
      questions.every((question) => _blockHeights.containsKey(question.id));

  /// نتيجة التقسيم الورقي الحالية على لوحة A4 (بكسل منطقي).
  ///
  /// الترويسة كتلة ثابتة في الصفحة الأولى؛ كل سؤال كتلة لا تتجزأ.
  /// الكتل غير المقاسة بعد تُعامل بارتفاع صفر حتى تُقاس في الإطار التالي.
  PaginationResult get pagination {
    return _paginationCache ??= PaginationEngine.paginate(
      blocks: <PageBlock>[
        PageBlock(
          id: PaperMetrics.headerBlockId,
          height: _blockHeights[PaperMetrics.headerBlockId] ?? 0,
        ),
        for (final question in questions)
          PageBlock(id: question.id, height: _blockHeights[question.id] ?? 0),
      ],
      pageHeight: PaperMetrics.pageContentHeightPx,
      spacing: PaperMetrics.blockSpacingPx,
    );
  }

  /// توزيع الأسئلة على الصفحات (معرّفات الأسئلة لكل صفحة) — يُمرَّر إلى محرك
  /// الـ PDF ليطبع **نفس** التقسيم المعروض على الشاشة دون انحراف.
  List<List<String>> get pageAssignments {
    return <List<String>>[
      for (final page in pagination.pages)
        page.blockIds.where((id) => id != PaperMetrics.headerBlockId).toList(growable: false),
    ];
  }

  void _commit(ExamDocument next) {
    _document = next.normalized;
    _paginationCache = null;
    notifyListeners();
  }
}
