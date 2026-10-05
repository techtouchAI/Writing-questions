import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../layout/blueprint/exam_blueprint.dart';
import '../layout/document_ir.dart';
import '../layout/pagination_engine.dart';
import '../layout/paper_metrics.dart';
import '../models/branch_item.dart';
import '../models/branch_model.dart';
import '../models/exam_canvas_geometry.dart';
import '../models/exam_document.dart';
import '../models/exam_footer_model.dart';
import '../models/exam_header_model.dart';
import '../models/floating_element.dart';
import '../models/paper_divider.dart';
import '../models/paper_settings.dart';
import '../models/paper_text_style.dart';
import '../models/point_kind.dart';
import '../models/question_model.dart';
import '../models/question_option.dart';
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
              header: ExamHeaderModel.initial(),
              questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
            ),
        _currentQuestionIndex = 0;

  ExamDocument _document;
  int _currentQuestionIndex;
  BranchRef? _selectedBranch;
  int? _selectedQuestionIndex;
  final Map<String, double> _blockHeights = <String, double>{};
  PaginationResult? _paginationCache;
  ExamBlueprint? _blueprintCache;
  DocumentIR? _documentIrCache;

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
    _blueprintCache = null;
    _documentIrCache = null;
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
    _blueprintCache = null;
    _documentIrCache = null;
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

  /// مخطط الورقة المحلَّل للمستند الحالي (مخزَّن حتى التعديل التالي).
  ExamBlueprint get blueprint => _blueprintCache ??= ExamBlueprint.from(_document);

  /// Canonical semantic representation of the current blueprint, cached for
  /// the same lifetime as [blueprint].
  DocumentIR get documentIr => _documentIrCache ??= DocumentIR.fromBlueprint(
        blueprint: blueprint,
        document: _document,
      );

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

  // ============================ الترويسة والتذييل ============================

  /// يستبدل بيانات الترويسة كاملةً (من نموذج الخطوة 1 أو ورقة التحرير).
  ///
  /// [coalesceKey] يدمج الكتابة المتتالية في نقطة تراجع واحدة.
  void updateHeader(ExamHeaderModel header, {String? coalesceKey}) {
    _commit(_document.copyWith(header: header), coalesceKey: coalesceKey);
  }

  void updateHeaderStyle(PaperTextStyle style) {
    _commit(_document.copyWith(header: _document.header.copyWith(style: style)));
  }

  void updateSubject(String subject) {
    _commit(_document.copyWith(header: _document.header.copyWith(subject: subject)));
  }

  /// يستبدل التذييل كاملاً (العبارة الختامية والتوقيعان).
  void updateFooter(ExamFooterModel footer, {String? coalesceKey}) {
    _commit(_document.copyWith(footer: footer), coalesceKey: coalesceKey);
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

  void updateQuestionCategory(int index, String category) {
    _commit(_document.withQuestionAt(index, questions[index].copyWith(category: category)));
  }

  /// منطوق السؤال (يُطبع في سطر العنوان بعد الرقم) — يُحفظ حرفياً.
  void updateQuestionStatement(int index, String statement) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].statement == statement) {
      return;
    }
    _commit(
      _document.withQuestionAt(index, questions[index].copyWith(statement: statement)),
      coalesceKey: 'statement-${questions[index].id}',
    );
  }

  /// نص السؤال (تحت سطر العنوان، يُحذف كلياً عند فراغه) — يُحفظ حرفياً.
  void updateQuestionBody(int index, String body) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].body == body) {
      return;
    }
    _commit(
      _document.withQuestionAt(index, questions[index].copyWith(body: body)),
      coalesceKey: 'body-${questions[index].id}',
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

  /// تنسيق واحد على تحديد متعدد = **خطوة تراجع واحدة** (سلوك Word/MSO):
  /// يجمع تعديلات الفروع والأسئلة في commit بدل خطوة تراجع لكل هدف.
  void applyStyleBatch({
    Map<BranchRef, PaperTextStyle> branchStyles =
        const <BranchRef, PaperTextStyle>{},
    Map<int, PaperTextStyle> questionStyles = const <int, PaperTextStyle>{},
  }) {
    if (branchStyles.isEmpty && questionStyles.isEmpty) {
      return;
    }
    var next = _document;
    branchStyles.forEach((ref, style) {
      if (!next.containsRef(ref)) {
        return;
      }
      final branch = next.branchAt(ref);
      if (branch.style == style) {
        return;
      }
      next = next.withBranchAt(ref, branch.copyWith(style: style));
    });
    questionStyles.forEach((index, style) {
      if (index < 0 || index >= next.questions.length) {
        return;
      }
      final question = next.questions[index];
      if (question.style == style) {
        return;
      }
      next = next.withQuestionAt(index, question.copyWith(style: style));
    });
    _commit(next);
  }

  /// يغيّر لون عنوان السؤال وحده، وينظّف لون النمط القديم الذي كان يلوّن
  /// المتن كله في الإصدارات السابقة.
  void updateQuestionTitleColor(int index, int? color) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (color != null && (color < 0 || color > 0xFFFFFFFF)) {
      throw ArgumentError.value(color, 'color', 'لون العنوان يجب أن يكون ARGB صالحاً.');
    }
    final question = questions[index];
    final bodyStyle = question.style.copyWith(color: () => null);
    if (question.titleColor == color && question.style == bodyStyle) {
      return;
    }
    _commit(
      _document.withQuestionAt(
        index,
        question.copyWith(
          style: bodyStyle,
          titleColor: () => color,
        ),
      ),
      coalesceKey: 'question-title-color-$index',
    );
  }

  void updateQuestionBodyAlign(int index, PaperAlign? align) {
    RangeError.checkValidIndex(index, questions, 'index');
    final question = questions[index];
    if (question.bodyAlign == align && question.style.align == align) {
      return;
    }
    // نقرة محاذاة واحدة = خطوة تراجع واحدة (سلوك Word): تُكتب محاذاة النص
    // ومحاذاة نمط السؤال (الذي يشترك في عرض العنوان/النص) في commit واحد،
    // وإلا بقي أحد الاثنين بعد التراجع وظهر الشكل متحيزاً.
    _commit(_document.withQuestionAt(
      index,
      question.copyWith(
        bodyAlign: () => align,
        style: question.style.copyWith(align: () => align),
      ),
    ));
  }

  /// محاذاة سطر القسم (`category`) — تُحفظ في النموذج فيصل التغيير إلى
  /// المعاينة وPDF وWord معاً (كانت محاذاة القسم حيّة على الشاشة وحدها).
  void updateQuestionCategoryAlign(int index, PaperAlign? align) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].categoryAlign == align) {
      return;
    }
    _commit(_document.withQuestionAt(
      index,
      questions[index].copyWith(categoryAlign: () => align),
    ));
  }

  void updateQuestionTitleAlign(int index, PaperAlign? align) {
    RangeError.checkValidIndex(index, questions, 'index');
    if (questions[index].titleAlign == align) {
      return;
    }
    _commit(_document.withQuestionAt(
      index,
      questions[index].copyWith(titleAlign: () => align),
    ));
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

  // ============================ النقاط (سؤال أو فرع) ============================
  //
  // نقاط السؤال المباشرة ونقاط الفرع بنية واحدة؛ كل عملية هنا تعمل على
  // مجموعة يحدّدها [PointsOwner] وعلى نقطة بمعرفها الثابت (لا فهرس مأسور
  // وقت البناء)، فيبقى التعديل صحيحاً بعد النقل والترتيب.

  /// نقاط المجموعة [owner] (فارغة إن لم يعد العنوان موجوداً).
  List<BranchItem> pointsOf(PointsOwner owner) =>
      _document.containsOwner(owner) ? _document.pointsOf(owner) : const <BranchItem>[];

  /// يستبدل نقاط المجموعة دفعة واحدة (محرر النقاط المشترك).
  void setPoints(
    PointsOwner owner,
    List<BranchItem> points, {
    String? coalesceKey,
  }) {
    if (!_document.containsOwner(owner)) {
      return;
    }
    final current = _document.pointsOf(owner);
    if (current.length == points.length && _samePoints(current, points)) {
      return;
    }
    _commit(_document.withPoints(owner, points), coalesceKey: coalesceKey);
  }

  /// هل القائمتان بالمحتوى نفسه تماماً (مقارنة سريعة لتفادي نقاط تراجع فارغة)؟
  static bool _samePoints(List<BranchItem> first, List<BranchItem> second) {
    for (var i = 0; i < first.length; i++) {
      if (!first[i].sameContentAs(second[i])) {
        return false;
      }
    }
    return true;
  }

  void addPoint(PointsOwner owner, [BranchItem? point]) {
    setPoints(owner, <BranchItem>[...pointsOf(owner), point ?? BranchItem()]);
  }

  /// يضبط عدد النقاط دفعة واحدة (تُضاف فارغة أو تُقصّ الزائدة من النهاية).
  void setPointCount(PointsOwner owner, int count) {
    final points = pointsOf(owner);
    final safe = count.clamp(0, 200);
    if (points.length == safe) {
      return;
    }
    if (points.length > safe) {
      setPoints(owner, points.sublist(0, safe));
      return;
    }
    setPoints(owner, <BranchItem>[
      ...points,
      for (var i = points.length; i < safe; i++) BranchItem(),
    ]);
  }

  /// يعدّل نقطة واحدة بمعرفها عبر [update]؛ لا شيء إن لم توجد.
  void updatePoint(
    PointsOwner owner,
    String pointId,
    BranchItem Function(BranchItem point) update, {
    String? coalesceKey,
  }) {
    final points = pointsOf(owner);
    final index = points.indexWhere((point) => point.id == pointId);
    if (index < 0) {
      return;
    }
    final updated = List<BranchItem>.of(points);
    updated[index] = update(points[index]);
    setPoints(owner, updated, coalesceKey: coalesceKey);
  }

  void updatePointText(PointsOwner owner, String pointId, String text) {
    updatePoint(
      owner,
      pointId,
      (point) => point.copyWith(text: text),
      coalesceKey: 'item-$pointId',
    );
  }

  /// يغيّر نوع النقطة (نص حر/صح وخطأ/إكمال فراغ/اختيار من متعدد).
  void updatePointKind(PointsOwner owner, String pointId, PointKind kind) {
    updatePoint(owner, pointId, (point) => point.copyWith(kind: kind));
  }

  /// تسمية مخصصة للنقطة: فارغ = تلقائي، `-` = بلا تسمية.
  void updatePointLabel(PointsOwner owner, String pointId, String label) {
    updatePoint(
      owner,
      pointId,
      (point) => point.copyWith(labelOverride: () => _normalizeLabelOverride(label)),
    );
  }

  void updatePointMarks(PointsOwner owner, String pointId, double marks) {
    if (!marks.isFinite || marks < 0) {
      return;
    }
    updatePoint(owner, pointId, (point) => point.copyWith(marks: marks));
  }

  void updatePointAlign(PointsOwner owner, String pointId, PaperAlign? align) {
    updatePoint(owner, pointId, (point) => point.copyWith(align: () => align));
  }

  void removePoint(PointsOwner owner, String pointId) {
    setPoints(
      owner,
      <BranchItem>[
        for (final point in pointsOf(owner))
          if (point.id != pointId) point,
      ],
    );
  }

  void movePoint(PointsOwner owner, int from, int to) {
    final points = pointsOf(owner);
    if (from == to || from < 0 || from >= points.length) {
      return;
    }
    final updated = List<BranchItem>.of(points);
    final point = updated.removeAt(from);
    updated.insert(to.clamp(0, updated.length), point);
    setPoints(owner, updated);
  }

  /// فارغ = تلقائي (`null`)، `-` = إخفاء (`''`)، وإلا النص المخصص.
  static String? _normalizeLabelOverride(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed == '-' ? '' : trimmed;
  }

  // ----------------------- خيارات «اختيار من متعدد» -----------------------

  void _updateOptions(
    PointsOwner owner,
    String pointId,
    List<QuestionOption> Function(List<QuestionOption> options) update, {
    String? coalesceKey,
  }) {
    updatePoint(
      owner,
      pointId,
      (point) => point.copyWith(options: update(List<QuestionOption>.of(point.options))),
      coalesceKey: coalesceKey,
    );
  }

  /// نص خيار واحد (يُحرَّر مباشرة على الورقة).
  void updatePointOptionText(
    PointsOwner owner,
    String pointId,
    int optionIndex,
    String text,
  ) {
    _updateOptions(
      owner,
      pointId,
      (options) {
        if (optionIndex < 0 || optionIndex >= options.length) {
          return options;
        }
        options[optionIndex] = options[optionIndex].copyWith(text: text);
        return options;
      },
      coalesceKey: 'option-$pointId-$optionIndex',
    );
  }

  /// تسمية مخصصة للخيار: فارغ = تلقائي، `-` = بلا تسمية.
  void updatePointOptionLabel(
    PointsOwner owner,
    String pointId,
    int optionIndex,
    String label,
  ) {
    _updateOptions(owner, pointId, (options) {
      if (optionIndex < 0 || optionIndex >= options.length) {
        return options;
      }
      options[optionIndex] = options[optionIndex].copyWith(
        labelOverride: () => _normalizeLabelOverride(label),
      );
      return options;
    });
  }

  void updatePointOptionAlign(
    PointsOwner owner,
    String pointId,
    int optionIndex,
    PaperAlign? align,
  ) {
    _updateOptions(owner, pointId, (options) {
      if (optionIndex < 0 || optionIndex >= options.length) {
        return options;
      }
      options[optionIndex] = options[optionIndex].copyWith(align: () => align);
      return options;
    });
  }

  /// يضيف خياراً جديداً (عدد الخيارات حر).
  void addPointOption(PointsOwner owner, String pointId) {
    _updateOptions(
      owner,
      pointId,
      (options) => <QuestionOption>[...options, QuestionOption(text: '')],
    );
  }

  /// يحذف خياراً (لا حد أدنى: تُحذف كلها إن أراد المدرس).
  void removePointOption(PointsOwner owner, String pointId, int optionIndex) {
    _updateOptions(owner, pointId, (options) {
      if (optionIndex < 0 || optionIndex >= options.length) {
        return options;
      }
      return options..removeAt(optionIndex);
    });
  }

  // ============================ الفروع ============================

  void addBranch(int questionIndex) {
    RangeError.checkValidIndex(questionIndex, questions, 'questionIndex');
    _commit(_document.withQuestionAt(
      questionIndex,
      questions[questionIndex].withBranchAdded(BranchModel()),
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

  /// منطوق الفرع (يُطبع في سطر العنوان بعد الرقم).
  void updateBranchStatement(BranchRef ref, String statement) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.statement == statement) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        branch.copyWith(content: branch.content.copyWith(statement: statement)),
      ),
      coalesceKey: 'branch-statement-${branch.id}',
    );
  }

  /// نص الفرع (تحت سطر العنوان، يُحذف كلياً عند فراغه).
  void updateBranchBody(BranchRef ref, String body) {
    if (!_document.containsRef(ref)) {
      return;
    }
    final branch = _document.branchAt(ref);
    if (branch.content.body == body) {
      return;
    }
    _commit(
      _document.withBranchAt(
        ref,
        branch.copyWith(content: branch.content.copyWith(body: body)),
      ),
      coalesceKey: 'branch-body-${branch.id}',
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
    String? ownerQuestionId,
  }) {
    if (_document.floatingElementById(element.id) != null) {
      return false;
    }
    final owner = ownerQuestionId ?? element.ownerQuestionId;
    final owned = owner == null
        ? element
        : _clampElementToQuestion(element.withOwner(owner));
    final placed = owned.copyWith(
      pageIndex: pageIndex ??
          (owner == null ? element.pageIndex : _ownerPageIndex(owner)),
    );
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
    // أي كتابة لعنصر مرتبط بسؤال تمرّ من الحصر: لا يخرج عن سؤال المالك أبداً.
    final placed = element.isQuestionOwned ? _clampElementToQuestion(element) : element;
    final elements = List<FloatingElement>.of(_document.floatingElements)
      ..[index] = placed;
    _commit(
      _document.copyWith(
        floatingElements: elements,
        questions: _replaceLegacyMirrors(questions, element.id, placed),
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

  // ==================== ارتباط العناصر بالسؤال ====================

  /// هل يملك السؤال [questionId] عناصر حرة؟
  bool hasOwnedElements(String questionId) => _document.floatingElements
      .any((element) => element.ownerQuestionId == questionId);

  /// مستطيل سؤال على ورقته بإحداثيات اللوحة (بكسل منطقي)، أو `null` قبل قياس
  /// الكتل. هو المرجع الوحيد لقيد العناصر المرتبطة بالسؤال في كل المسارات.
  QuestionRect? questionRect(String questionId) {
    final pageIndex = pagination.pageIndexOf(questionId);
    if (pageIndex == null) {
      return null;
    }
    final page = pagination.pages[pageIndex];
    final position = page.blockIds.indexOf(questionId);
    if (position < 0) {
      return null;
    }
    final margin = ExamCanvasGeometry.marginFor(_document.settings.marginMm);
    final contentWidth = ExamCanvasGeometry.contentWidthFor(_document.settings.marginMm);
    var top = margin;
    for (final id in page.blockIds.take(position)) {
      if (id == PaperMetrics.headerBlockId) {
        top += (_blockHeights[id] ?? 0) + PaperMetrics.blockSpacingPx;
        continue;
      }
      final previous = _document.questionById(id);
      top += (_blockHeights[id] ?? 0) +
          (previous?.spacingAfter ?? PaperMetrics.blockSpacingPx);
    }
    return QuestionRect(
      pageIndex: pageIndex,
      left: margin,
      top: top,
      width: contentWidth,
      height: math.max(
        _blockHeights[questionId] ?? 0,
        ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  int _ownerPageIndex(String questionId) => pagination.pageIndexOf(questionId) ?? 0;

  /// يحصر عنصراً مملوكاً داخل مستطيل سؤاله: `dx`/`dy` نسبيان لأعلى-يمين
  /// محتوى السؤال، ولا يخرج منه أبداً حتى لو صار السؤال أصغر أو انتقل.
  FloatingElement clampElementToQuestion(FloatingElement element) {
    final owner = element.ownerQuestionId;
    if (owner == null) {
      return element;
    }
    return _clampElementToQuestion(element);
  }

  // المقياس الأدنى لعنصر مرتبط بسؤال — فلا يتحول لمربع غير قابل للاستعمال
  // إذا صغر سؤالُه (تُحصر الأبعاد كما الموضع داخل السؤال).
  static const double _minOwnedElementSize = 32.0;

  FloatingElement _clampElementToQuestion(FloatingElement element) {
    final owner = element.ownerQuestionId;
    if (owner == null) {
      return element;
    }
    final rect = questionRect(owner);
    if (rect == null) {
      return element.copyWith(
        dx: math.max(0, element.dx),
        dy: math.max(0, element.dy),
      );
    }
    final maxWidth = math.max(rect.width, _minOwnedElementSize);
    final maxHeight = math.max(rect.height, _minOwnedElementSize);
    final width = element.width.clamp(
      math.min(_minOwnedElementSize, maxWidth),
      maxWidth,
    ).toDouble();
    final height = element.height.clamp(
      math.min(_minOwnedElementSize, maxHeight),
      maxHeight,
    ).toDouble();
    return element.copyWith(
      pageIndex: rect.pageIndex,
      width: width,
      height: height,
      dx: element.dx.clamp(0.0, math.max(0.0, maxWidth - width)).toDouble(),
      dy: element.dy.clamp(0.0, math.max(0.0, maxHeight - height)).toDouble(),
    );
  }

  /// يربط عنصراً حراً بسؤال ([questionId]) أو يفكّ ارتباطه (`null`) مع
  /// إعادة حساب إحداثياته نسبةً إلى المرجع الجديد.
  ///
  /// - الربط: يُحوَّل الموضع من إحداثيات الورقة إلى إحداثيات محتوى السؤال ثم
  ///   يُحصر داخله.
  /// - الفك: يعود إلى إحداثيات الورقة المطلقة فيبقى في مكانه المرئي نفسه
  ///   ويصير حراً في أي نقطة على الورقة.
  void setElementOwner(String elementId, String? questionId) {
    final element = _document.floatingElementById(elementId);
    if (element == null) {
      return;
    }
    final margin = ExamCanvasGeometry.marginFor(_document.settings.marginMm);
    if (questionId == null) {
      final ownerRect = element.ownerQuestionId == null
          ? null
          : questionRect(element.ownerQuestionId!);
      if (ownerRect == null) {
        updateFloatingElement(element.withOwner(null));
        return;
      }
      updateFloatingElement(
        element.withOwner(null).copyWith(
              dx: margin + element.dx,
              dy: ownerRect.top + element.dy,
            ),
      );
      return;
    }
    if (_document.questionById(questionId) == null) {
      return;
    }
    if (element.ownerQuestionId == questionId) {
      updateFloatingElement(element);
      return;
    }
    final relativeDx = math.max(0.0, element.dx - margin);
    final relativeDy = math.max(0.0, element.dy - (questionRect(questionId)?.top ?? 0));
    updateFloatingElement(
      element.withOwner(questionId).copyWith(dx: relativeDx, dy: relativeDy),
    );
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

  /// هل قيست كل الكتل التي تؤثر في توزيع DOCX (الترويسة، كل الأسئلة،
  /// والتذييل الذي يحجز مساحة أسفل الصفحة الأخيرة)؟
  bool get isFullyMeasured =>
      _blockHeights.containsKey(PaperMetrics.headerBlockId) &&
      _blockHeights.containsKey(PaperMetrics.footerBlockId) &&
      questions.every((question) => _blockHeights.containsKey(question.id));

  /// ارتفاع التذييل المحجوز أسفل آخر كتلة (مقاسه + المسافة التي تفصله عنها)؛
  /// صفر قبل أن يُقاس التذييل في أول إطار.
  double get footerReserve {
    final height = _blockHeights[PaperMetrics.footerBlockId];
    return height == null ? 0 : height + PaperMetrics.blockSpacingPx;
  }

  /// نتيجة التقسيم الورقي الحالية على لوحة A4 (بكسل منطقي).
  ///
  /// الترويسة كتلة ثابتة في الصفحة الأولى؛ كل سؤال كتلة لا تتجزأ؛ والتذييل
  /// يحجز مكانه تحت آخر كتلة في آخر صفحة. الكتل غير المقاسة بعد تُعامل
  /// بارتفاع صفر حتى تُقاس في الإطار التالي.
  /// Reproducible input to the legacy paginator, including the actual measured
  /// widget heights used by the interactive editing surface.
  PaginationInput get paginationInput => PaginationInput(
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
        lastPageReserve: footerReserve,
        footerMeasured: _blockHeights.containsKey(PaperMetrics.footerBlockId),
      );

  PaginationResult get pagination =>
      _paginationCache ??= paginationInput.paginate();

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
    _blueprintCache = null;
    _documentIrCache = null;
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
