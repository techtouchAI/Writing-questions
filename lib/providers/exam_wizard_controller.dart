import 'dart:async';

import 'package:flutter/foundation.dart';

import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_item.dart';
import '../models/branch_model.dart';
import '../models/exam_document.dart';
import '../models/exam_header_model.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_settings.dart';
import '../models/paper_text_style.dart';
import '../models/question_model.dart';
import '../models/question_option.dart';
import '../models/question_type.dart';
import '../models/subject_layout.dart';

/// حالة منشئ ورقة الأسئلة ومعاينة A4.
///
/// يفصل واجهة المستخدم عن:
/// 1. **تبديل المحتوى عند السحب والإفلات** ([swapBranchContent]) — يبدّل
///    المحتوى والدرجة فقط ويُبقي الهيكل الرقمي ثابتاً.
/// 2. **النقل وإعادة الترتيب** ([moveQuestion]/[moveBranch]/...) — ينقل
///    العنصر كاملاً بمحتواه.
/// 3. **التقسيم الورقي** ([pagination]) — يُعاد حسابه من ارتفاعات الكتل
///    المقاسة ديناميكياً عبر [PaginationEngine] بحيث لا يُفصل سؤال عن فروعه.
/// 4. **التراجع/الإعادة** ([undo]/[redo]) — سجل حالات للمستند كاملاً.
/// 5. **الحفظ التلقائي** ([enableAutoSave]) — حفظ صامت مُخفَّض بعد كل تعديل.
///
/// كل تعديل ينتج نسخة جديدة غير قابلة للتغيير من [ExamDocument].
class ExamWizardController extends ChangeNotifier {
  ExamWizardController({ExamDocument? document})
      : _document = document ??
            ExamDocument(
              name: 'ورقة أسئلة جديدة',
              header: ExamHeaderModel.ministerialDefault(),
              questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
            ),
        _currentQuestionIndex = 0;

  ExamDocument _document;
  int _currentQuestionIndex;
  BranchRef? _selectedBranch;
  int? _selectedQuestionIndex;
  final Map<String, double> _blockHeights = <String, double>{};
  PaginationResult? _paginationCache;

  // ============================ سجل التراجع ============================

  static const int _historyCap = 60;

  /// نافذة دمج الكتابة المتتالية (ضربات الحروف) في نقطة تراجع واحدة.
  static const Duration _coalesceWindow = Duration(milliseconds: 2500);

  final List<ExamDocument> _history = <ExamDocument>[];
  final List<ExamDocument> _future = <ExamDocument>[];
  String? _lastCoalesceKey;
  DateTime? _lastPushAt;

  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  /// يتراجع عن آخر تغيير هيكلي (أو دفعة كتابة).
  void undo() {
    if (_history.isEmpty) {
      return;
    }
    _future.add(_document);
    _document = _history.removeLast().normalized;
    _lastCoalesceKey = null;
    _paginationCache = null;
    _clampCurrentQuestion();
    _scheduleAutoSave();
    notifyListeners();
  }

  /// يعيد آخر تغيير مُتراجع عنه.
  void redo() {
    if (_future.isEmpty) {
      return;
    }
    _history.add(_document);
    if (_history.length > _historyCap) {
      _history.removeAt(0);
    }
    _document = _future.removeLast().normalized;
    _lastCoalesceKey = null;
    _paginationCache = null;
    _clampCurrentQuestion();
    _scheduleAutoSave();
    notifyListeners();
  }

  /// يفصل دفعة الكتابة الحالية كنقطة تراجع مستقلة (يُستدعى عند فقد التركيز).
  void checkpoint() {
    _lastCoalesceKey = null;
  }

  // ============================ الحفظ التلقائي ============================

  Future<void> Function(ExamDocument document)? _autoSave;
  Timer? _autoSaveTimer;
  bool _autoSaveInFlight = false;
  bool _autoSaveDirty = false;

  /// يفعّل الحفظ التلقائي الصامت بعد كل تعديل (بفاصل تهدئة ثانيتين).
  void enableAutoSave(Future<void> Function(ExamDocument document) save) {
    _autoSave = save;
  }

  void disableAutoSave() {
    _autoSave = null;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// هل يوجد حفظ تلقائي معلّق؟
  bool get hasPendingAutoSave => _autoSaveTimer?.isActive ?? false;

  void _scheduleAutoSave() {
    if (_autoSave == null) {
      return;
    }
    _autoSaveDirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _runAutoSave);
  }

  Future<void> _runAutoSave() async {
    if (_autoSave == null || !_autoSaveDirty || _autoSaveInFlight) {
      return;
    }
    _autoSaveInFlight = true;
    final snapshot = _document;
    try {
      await _autoSave!(snapshot);
      _autoSaveDirty = false;
    } catch (_) {
      // الحفظ التلقائي صامت: الفشل لا يقطع التحرير، وتبقى النسخة معلّقة
      // للمحاولة التالية عند أي تعديل جديد.
    } finally {
      _autoSaveInFlight = false;
    }
  }

  /// يفرغ أي حفظ معلّق فوراً (يُستدعى عند مغادرة المحرر).
  Future<void> flushAutoSave() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    await _runAutoSave();
  }

  // ============================ الوصول ============================

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

  /// السؤال المحدد في المعاينة (لمرفقات مستوى السؤال) — `null` = بلا تحديد.
  int? get selectedQuestionIndex {
    if (_selectedQuestionIndex == null ||
        _selectedQuestionIndex! < 0 ||
        _selectedQuestionIndex! >= questions.length) {
      return null;
    }
    return _selectedQuestionIndex;
  }

  // ============================ الترويسة ============================

  void updateHeader(ExamHeaderModel header) {
    _commit(_document.copyWith(header: header));
  }

  void updateHeaderLine(HeaderSlot slot, int lineIndex, String value) {
    _commit(
      _document.copyWith(header: _document.header.withLine(slot, lineIndex, value)),
      coalesceKey: 'header-${slot.name}-$lineIndex',
    );
  }

  void updateInstructions(String value) {
    _commit(
      _document.copyWith(header: _document.header.copyWith(instructions: value)),
      coalesceKey: 'header-instructions',
    );
  }

  void updateHeaderTitle(String value) {
    _commit(
      _document.copyWith(header: _document.header.copyWith(title: value)),
      coalesceKey: 'header-title',
    );
  }

  void updateHeaderNotes(String value) {
    _commit(
      _document.copyWith(header: _document.header.copyWith(notes: value)),
      coalesceKey: 'header-notes',
    );
  }

  void updateHeaderStyle(PaperTextStyle style) {
    _commit(_document.copyWith(header: _document.header.copyWith(style: style)));
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

  // ============================ إعدادات الورقة ============================

  void updateSettings(PaperSettings settings) {
    if (settings == _document.settings) {
      return;
    }
    var next = _document.copyWith(settings: settings);
    // التبديل بين الترقيم التلقائي واليدوي للفروع سلوك حقيقي: عند التعطيل
    // تُثبَّت التسميات المعروضة حالياً على كل فرع فتسافر معه عند النقل
    // (كالأرقام المكتوبة يدوياً) ولا يعيد الحذف ترقيم الباقي، وعند التفعيل
    // تُمسح التثبيتات فتعود التسميات مشتقة من الفهرس.
    if (settings.autoLetterBranches != _document.settings.autoLetterBranches) {
      next = settings.autoLetterBranches
          ? _clearedBranchLabels(next)
          : _frozenBranchLabels(next);
    }
    _commit(next);
  }

  /// يثبّت التسمية المعروضة لكل فرع كتسمية يدوية (وضع الترقيم اليدوي).
  static ExamDocument _frozenBranchLabels(ExamDocument document) {
    var next = document;
    for (var qi = 0; qi < next.questions.length; qi++) {
      final question = next.questions[qi];
      var changed = false;
      final branches = List<BranchModel>.of(question.branches);
      for (var bi = 0; bi < branches.length; bi++) {
        if (branches[bi].labelOverride == null ||
            branches[bi].labelOverride!.trim().isEmpty) {
          branches[bi] = branches[bi].copyWith(
            labelOverride: () => next.layout.branchLabel(bi),
          );
          changed = true;
        }
      }
      if (changed) {
        next = next.withQuestionAt(qi, question.copyWith(branches: branches));
      }
    }
    return next;
  }

  /// يمسح كل التسميات اليدوية للفروع (عودة للاشتقاق التلقائي من الفهرس).
  static ExamDocument _clearedBranchLabels(ExamDocument document) {
    var next = document;
    for (var qi = 0; qi < next.questions.length; qi++) {
      final question = next.questions[qi];
      var changed = false;
      final branches = List<BranchModel>.of(question.branches);
      for (var bi = 0; bi < branches.length; bi++) {
        if (branches[bi].labelOverride != null) {
          branches[bi] = branches[bi].copyWith(labelOverride: () => null);
          changed = true;
        }
      }
      if (changed) {
        next = next.withQuestionAt(qi, question.copyWith(branches: branches));
      }
    }
    return next;
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
    _clampCurrentQuestion();
  }

  /// ينقل سؤالاً كاملاً (وحدة لا تتجزأ) من [from] إلى [to].
  void moveQuestion(int from, int to) {
    if (from == to) {
      return;
    }
    RangeError.checkValidIndex(from, questions, 'from');
    _commit(_document.withQuestionMoved(from, to));
    _clampCurrentQuestion();
  }

  /// ينسخ سؤالاً كاملاً (كل المحتوى والتنسيق) بعد الأصل مباشرة.
  void duplicateQuestion(int index) {
    RangeError.checkValidIndex(index, questions, 'index');
    _commit(_document.withQuestionDuplicated(index));
  }

  void updateQuestionType(int index, QuestionType type) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].type == type) return;
    _commit(_document.withQuestionAt(index, questions[index].copyWith(type: type)));
  }

  void updateQuestionCategory(int index, String category) {
    _commit(_document.withQuestionAt(index, questions[index].copyWith(category: category)));
  }

  /// نص السؤال/تعليماته («أجب عن فرعين فقط:»...) — يُحفظ حرفياً.
  void updateQuestionPrompt(int index, String prompt) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].prompt == prompt) {
      return;
    }
    _commit(
      _document.withQuestionAt(index, questions[index].copyWith(prompt: prompt)),
      coalesceKey: 'prompt-$index-${questions[index].id}',
    );
  }

  /// درجة يدوية ثابتة للسؤال (`null` = حساب تلقائي من الفروع والنقاط).
  void updateQuestionMarksOverride(int index, double? marks) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (marks != null && (!marks.isFinite || marks < 0)) {
      return;
    }
    if (questions[index].marksOverride == marks) {
      return;
    }
    _commit(
      _document.withQuestionAt(
        index,
        questions[index].copyWith(marksOverride: () => marks),
      ),
    );
  }

  /// ترقيم يدوي ثابت للسؤال (نص فارغ/`null` = تلقائي).
  void updateQuestionNumberOverride(int index, String? number) {
    RangeError.checkValidIndex(index, questions, 'index');
    final normalized = number?.trim();
    _commit(
      _document.withQuestionAt(
        index,
        questions[index].copyWith(
          numberOverride: () => normalized == null || normalized.isEmpty ? null : normalized,
        ),
      ),
    );
  }

  void updateQuestionSpacing(int index, double spacing) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (!spacing.isFinite || spacing < 0 || spacing > 200) return;
    _commit(_document.withQuestionAt(index, questions[index].copyWith(spacingAfter: spacing)));
  }

  void updateQuestionStyle(int index, PaperTextStyle style) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].style == style) {
      return;
    }
    _commit(_document.withQuestionAt(index, questions[index].copyWith(style: style)));
  }

  void toggleQuestionFrame(int index) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    _commit(_document.withQuestionAt(index, question.copyWith(showFrame: !question.showFrame)));
  }

  /// فاصل بعد السؤال (`null` = حذف الفاصل).
  void setQuestionDivider(int index, PaperDivider? divider) {
    RangeError.checkValidIndex(index, questions, 'index');
    _commit(
      _document.withQuestionAt(
        index,
        questions[index].copyWith(dividerAfter: () => divider),
      ),
    );
  }

  // ======================== النقاط داخل السؤال (بلا فروع) ========================

  /// يحدّث نقاط السؤال المباشرة دفعة واحدة (محرر النقاط المشترك).
  void updateQuestionItems(int index, List<BranchItem> items) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    if (question.items.length == items.length &&
        _sameItemList(question.items, items)) {
      return;
    }
    _commit(_document.withQuestionAt(index, question.copyWith(items: items)));
  }

  void addQuestionItem(int index, [BranchItem? item]) {
    RangeError.checkValidIndex(index, questions, 'index');
    updateQuestionItems(index, <BranchItem>[...questions[index].items, item ?? BranchItem()]);
  }

  /// يضبط عدد نقاط السؤال دفعة واحدة (تُضاف فارغة أو تُقصّ الزائدة من النهاية).
  void setQuestionItemCount(int index, int count) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    final safe = count.clamp(0, 200);
    if (question.items.length == safe) {
      return;
    }
    if (question.items.length > safe) {
      updateQuestionItems(index, question.items.sublist(0, safe));
      return;
    }
    updateQuestionItems(index, <BranchItem>[
      ...question.items,
      for (var i = question.items.length; i < safe; i++) BranchItem(),
    ]);
  }

  void updateQuestionItemText(int index, int itemIndex, String text) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    RangeError.checkValidIndex(itemIndex, question.items, 'itemIndex');
    if (question.items[itemIndex].text == text) {
      return;
    }
    _commit(
      _document.withQuestionAt(
        index,
        question.withItemAt(itemIndex, question.items[itemIndex].copyWith(text: text)),
      ),
      coalesceKey: 'question-item-${question.items[itemIndex].id}',
    );
  }

  /// تسمية يدوية للنقطة: فارغ = تلقائي (`null`)، `-` = إخفاء (`''`).
  void updateQuestionItemLabel(int index, int itemIndex, String label) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    RangeError.checkValidIndex(itemIndex, question.items, 'itemIndex');
    updateQuestionItems(
      index,
      <BranchItem>[
        for (var i = 0; i < question.items.length; i++)
          i == itemIndex
              ? question.items[i].copyWith(
                  labelOverride: () => _normalizeLabelOverride(label),
                )
              : question.items[i],
      ],
    );
  }

  void updateQuestionItemMarks(int index, int itemIndex, double marks) {
    if (!marks.isFinite || marks < 0) {
      return;
    }
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    RangeError.checkValidIndex(itemIndex, question.items, 'itemIndex');
    if (question.items[itemIndex].marks == marks) {
      return;
    }
    updateQuestionItems(
      index,
      <BranchItem>[
        for (var i = 0; i < question.items.length; i++)
          i == itemIndex ? question.items[i].copyWith(marks: marks) : question.items[i],
      ],
    );
  }

  void removeQuestionItem(int index, int itemIndex) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    RangeError.checkValidIndex(itemIndex, question.items, 'itemIndex');
    updateQuestionItems(index, question.withItemRemoved(itemIndex).items);
  }

  void moveQuestionItem(int index, int from, int to) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (from == to) {
      return;
    }
    final question = questions[index];
    RangeError.checkValidIndex(from, question.items, 'from');
    updateQuestionItems(index, question.withItemMoved(from, to).items);
  }

  /// هل القائمتان محتوانهما متطابقان (مقارنة مرجعية سريعة للنقاط)؟
  static bool _sameItemList(List<BranchItem> first, List<BranchItem> second) {
    for (var i = 0; i < first.length; i++) {
      if (first[i].id != second[i].id ||
          first[i].text != second[i].text ||
          first[i].marks != second[i].marks ||
          first[i].isCorrect != second[i].isCorrect ||
          first[i].labelOverride != second[i].labelOverride) {
        return false;
      }
    }
    return true;
  }

  // ============================ الفروع ============================

  void addBranch(int questionIndex, {QuestionType? type}) {
    RangeError.checkValidIndex(questionIndex, questions, 'questionIndex');
    // «إضافة فرع جديد بنفس خيارات الفرع السابق»: يبدأ الفرع الجديد بنوع
    // الفرع الأخير (وبنموذج خياراته الافتراضي) بدل نوع ثابت، فيبقى (ب) و(ج)
    // على الأدوات نفسها التي اختارها المعلم للفرع (أ) — والفرع الأول في
    // سؤال بلا فروع يبدأ مقالياً.
    final branches = questions[questionIndex].branches;
    final resolvedType =
        type ?? (branches.isEmpty ? QuestionType.essay : branches.last.content.type);
    _commit(_document.withQuestionAt(
      questionIndex,
      questions[questionIndex].withBranchAdded(BranchModel(content: BranchContent.empty(resolvedType))),
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

  /// ينقل فرعاً داخل سؤاله (المحتوى كما هو، الموضع فقط يتغير).
  void moveBranch(int questionIndex, int from, int to) {
    RangeError.checkValidIndex(questionIndex, questions, 'questionIndex');
    final count = questions[questionIndex].branches.length;
    // مراجع السحب قد تقدُم بعد تعديل متزامن — تُرفض بهدوء بدل الرمي.
    if (from == to || from < 0 || from >= count || to < 0 || to > count) {
      return;
    }
    _commit(_document.withBranchMoved(questionIndex, from, to));
  }

  /// ينسخ فرعاً كاملاً بعد الأصل مباشرة.
  void duplicateBranch(BranchRef ref) {
    if (!_document.containsRef(ref)) {
      return;
    }
    _commit(_document.withBranchDuplicated(ref));
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

  /// وضع النص الحر: عرض النص والنقاط فقط دون مساحة إجابة مولّدة.
  void setBranchPlainText(BranchRef ref, bool plainText) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.plainText == plainText) {
      return;
    }
    updateBranchContent(ref, branch.content.copyWith(plainText: plainText));
  }

  void updateBranchText(BranchRef ref, String text) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.text == text) {
      return;
    }
    _commit(
      _document.withBranchAt(ref, branch.copyWith(content: branch.content.copyWith(text: text))),
      coalesceKey: 'branch-text-${branch.id}',
    );
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

  void updateBranchStyle(BranchRef ref, PaperTextStyle style) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.style == style) {
      return;
    }
    _commit(_document.withBranchAt(ref, branch.copyWith(style: style)));
  }

  void toggleBranchFrame(BranchRef ref) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    _commit(_document.withBranchAt(ref, branch.copyWith(showFrame: !branch.showFrame)));
  }

  /// فاصل بعد الفرع (`null` = حذف الفاصل).
  void setBranchDivider(BranchRef ref, PaperDivider? divider) {
    if (!_document.containsRef(ref)) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        _document.branchAt(ref).copyWith(dividerAfter: () => divider),
      ),
    );
  }

  /// تسمية يدوية ثابتة للفرع (نص فارغ/`null` = تلقائي من الفهرس).
  void updateBranchLabelOverride(BranchRef ref, String? label) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final normalized = label?.trim();
    _commit(
      _document.withBranchAt(
        ref,
        _document.branchAt(ref).copyWith(
          labelOverride: () => normalized == null || normalized.isEmpty ? null : normalized,
        ),
      ),
    );
  }

  /// تسمية مخصصة للخيار: فارغ = تلقائي، `-` = بلا تسمية.
  void updateBranchOptionLabel(BranchRef ref, int optionIndex, String label) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    if (optionIndex < 0 || optionIndex >= content.options.length) {
      return;
    }
    final options = List<QuestionOption>.of(content.options);
    options[optionIndex] = options[optionIndex].copyWith(
      labelOverride: () => _normalizeLabelOverride(label),
    );
    updateBranchContent(ref, content.copyWith(options: options));
  }

  /// تسمية مخصصة للنقطة: فارغ = تلقائي، `-` = بلا تسمية.
  void updateBranchItemLabel(BranchRef ref, int itemIndex, String label) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    if (itemIndex < 0 || itemIndex >= content.items.length) {
      return;
    }
    final items = List<BranchItem>.of(content.items);
    items[itemIndex] = items[itemIndex].copyWith(
      labelOverride: () => _normalizeLabelOverride(label),
    );
    updateBranchContent(ref, content.copyWith(items: items));
  }

  /// فارغ = تلقائي (`null`)، `-` = إخفاء (`''`)، وإلا النص المخصص.
  static String? _normalizeLabelOverride(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed == '-' ? '' : trimmed;
  }

  /// يحدّث نص خيار واحد داخل فرع (خيارات الاختيار من متعدد قابلة للتحرير
  /// مباشرة على الورقة، وتبقى علامة الإجابة الصحيحة كما هي).
  void updateBranchOptionText(BranchRef ref, int optionIndex, String text) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    if (optionIndex < 0 || optionIndex >= content.options.length) {
      return;
    }
    if (content.options[optionIndex].text == text) {
      return;
    }
    final options = List<QuestionOption>.of(content.options);
    options[optionIndex] = options[optionIndex].copyWith(text: text);
    _commit(
      _document.withBranchAt(
        ref,
        _document.branchAt(ref).copyWith(content: content.copyWith(options: options)),
      ),
      coalesceKey: 'option-${_document.branchAt(ref).id}-$optionIndex',
    );
  }

  /// يضيف خياراً جديداً لفرع اختيار من متعدد (عدد الخيارات حر).
  void addBranchOption(BranchRef ref) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    updateBranchContent(
      ref,
      content.copyWith(options: <QuestionOption>[...content.options, QuestionOption(text: '')]),
    );
  }

  /// يحذف خياراً (يبقى خيار واحد على الأقل).
  void removeBranchOption(BranchRef ref, int optionIndex) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    // لا حد أدنى للخيارات: تُحذف كلها إن أراد المدرس.
    if (optionIndex < 0 || optionIndex >= content.options.length) {
      return;
    }
    final options = List<QuestionOption>.of(content.options)..removeAt(optionIndex);
    updateBranchContent(ref, content.copyWith(options: options));
  }

  /// يحدّد الخيار الصحيح (لاختيار من متعدد).
  void setBranchOptionCorrect(BranchRef ref, int optionIndex, bool isCorrect) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    if (optionIndex < 0 || optionIndex >= content.options.length) {
      return;
    }
    final options = List<QuestionOption>.of(content.options);
    options[optionIndex] = options[optionIndex].copyWith(isCorrect: isCorrect);
    updateBranchContent(ref, content.copyWith(options: options));
  }

  /// يحدّث الإجابة النموذجية لفرع (فراغ/مقالي) — تُعرض وتُحرَّر في «نموذج
  /// الإجابة» على الورقة.
  void updateBranchModelAnswer(BranchRef ref, String modelAnswer) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final content = _document.branchAt(ref).content;
    if (content.modelAnswer == modelAnswer) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        _document.branchAt(ref).copyWith(content: content.copyWith(modelAnswer: modelAnswer)),
      ),
      coalesceKey: 'answer-${_document.branchAt(ref).id}',
    );
  }

  // ============================ النقاط داخل الفرع ============================

  void addBranchItem(BranchRef ref, [BranchItem? item]) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    updateBranchContent(ref, branch.content.withItemAdded(item));
  }

  /// يضبط عدد النقاط دفعة واحدة (تُضاف فارغة أو تُقصّ الزائدة من النهاية).
  void setBranchItemCount(BranchRef ref, int count) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    updateBranchContent(ref, branch.content.withItemCount(count));
  }

  /// يثبّت إجابة نقطة لصح/خطأ (نموذج المعلم فقط).
  void updateBranchItemAnswer(BranchRef ref, int itemIndex, bool? answer) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    final content = branch.content;
    if (itemIndex < 0 || itemIndex >= content.items.length) {
      return;
    }
    if (content.items[itemIndex].isCorrect == answer) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        branch.copyWith(content: content.withItemAnswer(itemIndex, answer)),
      ),
      coalesceKey: 'item-answer-${ref.questionIndex}-${ref.branchIndex}-$itemIndex',
    );
  }

  void updateBranchItemText(BranchRef ref, int itemIndex, String text) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    final content = branch.content;
    if (itemIndex < 0 || itemIndex >= content.items.length) {
      return;
    }
    if (content.items[itemIndex].text == text) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        branch.copyWith(
          content: content.withItemAt(itemIndex, content.items[itemIndex].copyWith(text: text)),
        ),
      ),
      coalesceKey: 'item-${content.items[itemIndex].id}',
    );
  }

  void updateBranchItemMarks(BranchRef ref, int itemIndex, double marks) {
    if (!_document.containsRef(ref) || !marks.isFinite || marks < 0) {
      return;
    }
    final branch = _document.branchAt(ref);
    final content = branch.content;
    if (itemIndex < 0 || itemIndex >= content.items.length) {
      return;
    }
    if (content.items[itemIndex].marks == marks) {
      return;
    }
    updateBranchContent(
      ref,
      content.withItemAt(itemIndex, content.items[itemIndex].copyWith(marks: marks)),
    );
  }

  void removeBranchItem(BranchRef ref, int itemIndex) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (itemIndex < 0 || itemIndex >= branch.content.items.length) {
      return;
    }
    updateBranchContent(ref, branch.content.withItemRemoved(itemIndex));
  }

  void moveBranchItem(BranchRef ref, int from, int to) {
    if (!_document.containsRef(ref) || from == to) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (from < 0 || from >= branch.content.items.length) {
      return;
    }
    updateBranchContent(ref, branch.content.withItemMoved(from, to));
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
    if (ref != null) {
      _selectedQuestionIndex = ref.questionIndex;
    }
    notifyListeners();
  }

  void selectQuestion(int? index) {
    if (index != null && (index < 0 || index >= questions.length)) {
      return;
    }
    if (_selectedQuestionIndex == index) {
      return;
    }
    _selectedQuestionIndex = index;
    notifyListeners();
  }

  // ============================ العناصر الحرة على الورقة ============================

  /// يضيف عنصراً مستقلاً على صفحة من صفحات المستند؛ لا يحتاج سؤالاً أو فرعاً.
  ///
  /// [mirrorQuestionIndex]/[mirrorBranchIndex] اختياريان للتوافق فقط مع
  /// واجهات/ملفات الإصدار القديم التي كانت تتوقع العنصر داخل قائمة المرفقات.
  /// مصدر الحقيقة هو [ExamDocument.floatingElements]، وحذف السؤال لا يحذفه.
  bool addFloatingElement(
    FloatingElement element, {
    int? pageIndex,
    int? mirrorQuestionIndex,
    int? mirrorBranchIndex,
  }) {
    if (_document.floatingElementById(element.id) != null) {
      return false;
    }
    final placed = element.copyWith(pageIndex: pageIndex ?? element.pageIndex);
    final nextQuestions = List<QuestionModel>.of(questions);
    if (mirrorQuestionIndex != null &&
        mirrorQuestionIndex >= 0 &&
        mirrorQuestionIndex < nextQuestions.length) {
      final question = nextQuestions[mirrorQuestionIndex];
      if (mirrorBranchIndex != null &&
          mirrorBranchIndex >= 0 &&
          mirrorBranchIndex < question.branches.length) {
        final branches = List<BranchModel>.of(question.branches);
        final branch = branches[mirrorBranchIndex];
        branches[mirrorBranchIndex] = branch.copyWith(
          attachments: <FloatingElement>[...branch.attachments, placed],
        );
        nextQuestions[mirrorQuestionIndex] = question.copyWith(branches: branches);
      } else {
        nextQuestions[mirrorQuestionIndex] = question.copyWith(
          attachments: <FloatingElement>[...question.attachments, placed],
        );
      }
    }
    _commit(_document.copyWith(
      floatingElements: <FloatingElement>[..._document.floatingElements, placed],
      questions: nextQuestions,
    ));
    return true;
  }

  /// يحدّث موضع/تنسيق/حجم عنصر حر؛ لا يحتاج معرفة بسؤاله السابق.
  void updateFloatingElement(FloatingElement element) {
    final index = _document.floatingElements.indexWhere((item) => item.id == element.id);
    if (index == -1) {
      return;
    }
    final elements = List<FloatingElement>.of(_document.floatingElements)..[index] = element;
    _commit(
      _document.copyWith(
        floatingElements: elements,
        questions: _replaceLegacyMirrors(questions, element.id, element),
      ),
      coalesceKey: 'floating-${element.id}',
    );
  }

  /// يحذف العنصر من المستند ومن أي نسخة توافقية قديمة له.
  void removeFloatingElement(String elementId) {
    final elements = _document.floatingElements
        .where((item) => item.id != elementId)
        .toList(growable: false);
    final nextQuestions = _replaceLegacyMirrors(questions, elementId, null);
    final hadMirror = !_sameQuestionAttachmentState(questions, nextQuestions);
    if (elements.length == _document.floatingElements.length && !hadMirror) {
      return;
    }
    _commit(_document.copyWith(floatingElements: elements, questions: nextQuestions));
  }

  /// يضيف عنصراً حراً عند استعمال واجهة الإصدار القديم (سؤال/فرع محدد).
  /// يظل يعيد false إذا لم يوجد فرع مستهدف، كما كانت الواجهة تتوقع سابقاً.
  bool addAttachment(FloatingElement element, {BranchRef? ref}) {
    final target = ref ?? selectedBranch;
    if (target == null || !_document.containsRef(target)) {
      return false;
    }
    return addFloatingElement(
      element,
      pageIndex: _pageIndexForQuestion(target.questionIndex),
      mirrorQuestionIndex: target.questionIndex,
      mirrorBranchIndex: target.branchIndex,
    );
  }

  /// رفع مرفق قديم عند أول تعديل له إلى قائمة العناصر الحرة.
  void updateAttachment(
    BranchRef ref,
    FloatingElement element, {
    int? pageIndex,
  }) {
    if (_document.floatingElementById(element.id) != null) {
      updateFloatingElement(element);
      return;
    }
    if (!_document.containsRef(ref) ||
        !_document.branchAt(ref).attachments.any((item) => item.id == element.id)) {
      return;
    }
    _liftLegacyAttachment(
      element,
      pageIndex: pageIndex ?? _pageIndexForQuestion(ref.questionIndex),
    );
  }

  void removeAttachment(BranchRef ref, String elementId) {
    if (_document.floatingElementById(elementId) != null) {
      removeFloatingElement(elementId);
      return;
    }
    if (_document.containsRef(ref) &&
        _document.branchAt(ref).attachments.any((item) => item.id == elementId)) {
      removeFloatingElement(elementId);
    }
  }

  /// واجهات التوافق القديمة — العنصر يُخزَّن الآن على مستوى المستند.
  bool addQuestionAttachment(FloatingElement element, {int? questionIndex}) {
    final target = questionIndex ?? selectedQuestionIndex ?? questions.length - 1;
    if (target < 0 || target >= questions.length) {
      return false;
    }
    return addFloatingElement(
      element,
      pageIndex: _pageIndexForQuestion(target),
      mirrorQuestionIndex: target,
    );
  }

  void updateQuestionAttachment(
    int questionIndex,
    FloatingElement element, {
    int? pageIndex,
  }) {
    if (_document.floatingElementById(element.id) != null) {
      updateFloatingElement(element);
      return;
    }
    if (questionIndex < 0 || questionIndex >= questions.length ||
        !questions[questionIndex].attachments.any((item) => item.id == element.id)) {
      return;
    }
    _liftLegacyAttachment(
      element,
      pageIndex: pageIndex ?? _pageIndexForQuestion(questionIndex),
    );
  }

  void removeQuestionAttachment(int questionIndex, String elementId) {
    if (questionIndex < 0 || questionIndex >= questions.length) {
      return;
    }
    if (_document.floatingElementById(elementId) != null ||
        questions[questionIndex].attachments.any((item) => item.id == elementId)) {
      removeFloatingElement(elementId);
    }
  }

  int _pageIndexForQuestion(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= questions.length) {
      return 0;
    }
    return pagination.pageIndexOf(questions[questionIndex].id) ?? 0;
  }

  void _liftLegacyAttachment(FloatingElement element, {required int pageIndex}) {
    final placed = element.copyWith(pageIndex: pageIndex);
    _commit(
      _document.copyWith(
        floatingElements: <FloatingElement>[..._document.floatingElements, placed],
        questions: _replaceLegacyMirrors(questions, element.id, placed),
      ),
      coalesceKey: 'floating-${element.id}',
    );
  }

  /// يزامن نسخة التوافق داخل السؤال/الفرع دون تغيير الملكية الحقيقية.
  static List<QuestionModel> _replaceLegacyMirrors(
    List<QuestionModel> source,
    String elementId,
    FloatingElement? replacement,
  ) {
    final result = List<QuestionModel>.of(source);
    for (var questionIndex = 0; questionIndex < result.length; questionIndex++) {
      final question = result[questionIndex];
      var questionChanged = false;
      final questionAttachments = <FloatingElement>[];
      for (final element in question.attachments) {
        if (element.id != elementId) {
          questionAttachments.add(element);
          continue;
        }
        questionChanged = true;
        if (replacement != null) questionAttachments.add(replacement);
      }
      final branches = List<BranchModel>.of(question.branches);
      for (var branchIndex = 0; branchIndex < branches.length; branchIndex++) {
        final branch = branches[branchIndex];
        var branchChanged = false;
        final branchAttachments = <FloatingElement>[];
        for (final element in branch.attachments) {
          if (element.id != elementId) {
            branchAttachments.add(element);
            continue;
          }
          branchChanged = true;
          questionChanged = true;
          if (replacement != null) branchAttachments.add(replacement);
        }
        if (branchChanged) {
          branches[branchIndex] = branch.copyWith(attachments: branchAttachments);
        }
      }
      if (questionChanged) {
        result[questionIndex] = question.copyWith(
          attachments: questionAttachments,
          branches: branches,
        );
      }
    }
    return result;
  }

  static bool _sameQuestionAttachmentState(
    List<QuestionModel> first,
    List<QuestionModel> second,
  ) {
    if (first.length != second.length) return false;
    for (var questionIndex = 0; questionIndex < first.length; questionIndex++) {
      final a = first[questionIndex];
      final b = second[questionIndex];
      if (a.attachments.length != b.attachments.length) return false;
      for (var index = 0; index < a.attachments.length; index++) {
        if (a.attachments[index].id != b.attachments[index].id) return false;
      }
      if (a.branches.length != b.branches.length) return false;
      for (var branchIndex = 0; branchIndex < a.branches.length; branchIndex++) {
        final aa = a.branches[branchIndex].attachments;
        final bb = b.branches[branchIndex].attachments;
        if (aa.length != bb.length) return false;
        for (var index = 0; index < aa.length; index++) {
          if (aa[index].id != bb[index].id) return false;
        }
      }
    }
    return true;
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
          PageBlock(
            id: question.id,
            height: _blockHeights[question.id] ?? 0,
            spacingAfter: question.spacingAfter,
          ),
      ],
      pageHeight: PaperMetrics.pageContentHeightFor(_document.settings.marginMm),
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

  // ============================ داخلي ============================

  void _clampCurrentQuestion() {
    if (_currentQuestionIndex >= questions.length) {
      _currentQuestionIndex = questions.length - 1;
    }
  }

  /// يثبّت نسخة جديدة من المستند مع دفع نقطة تراجع (ما لم تُدمج الكتابة).
  ///
  /// [coalesceKey]: مفتاح دمج الكتابة المتتالية (ضربات الحروف والسحب) —
  /// التعديلات المتتالية بنفس المفتاح خلال [_coalesceWindow] تُدمج في نقطة
  /// تراجع واحدة بدل إغراق السجل.
  void _commit(ExamDocument next, {String? coalesceKey}) {
    final now = DateTime.now();
    var pushHistory = true;
    if (coalesceKey != null &&
        coalesceKey == _lastCoalesceKey &&
        _lastPushAt != null &&
        now.difference(_lastPushAt!) < _coalesceWindow) {
      pushHistory = false;
    }
    if (pushHistory) {
      _history.add(_document);
      if (_history.length > _historyCap) {
        _history.removeAt(0);
      }
      _future.clear();
      _lastPushAt = now;
    }
    _lastCoalesceKey = coalesceKey;
    _document = next.normalized;
    _paginationCache = null;
    _scheduleAutoSave();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    super.dispose();
  }
}
