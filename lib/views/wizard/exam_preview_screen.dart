import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../layout/document_direction.dart';
import '../../layout/document_ir.dart';
import '../../layout/canonical/canonical_layout_interaction.dart';
import '../../layout/canonical/canonical_layout_preview.dart';
import '../../layout/canonical/canonical_layout_service.dart';
import '../../layout/canonical/canonical_page_plan.dart';
import '../../layout/canonical/layout_document.dart';
import '../../layout/canonical/layout_units.dart';
import '../../layout/semantic/inline_nodes.dart';
import '../../layout/paper_metrics.dart';
import '../../layout/visual/visual_metrics.dart';
import '../../models/branch_item.dart';
import '../../models/exam_canvas_geometry.dart';
import '../../models/exam_document.dart';
import '../../models/equation_model.dart';
import '../../models/floating_element.dart';
import '../../models/paper_divider.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/point_kind.dart';
import '../../models/quran_text.dart';
import '../../models/subject_layout.dart';
import '../../models/tex_content.dart';
import '../../models/text_format_span.dart';
import '../../providers/exam_document_provider.dart';
import '../../providers/exam_wizard_controller.dart';
import '../../services/export_file_service.dart';
import '../../services/page_frame_store.dart';
import '../../services/pdf_export_service.dart';
import '../widgets/floating_element_view.dart';
import '../widgets/formula_inserter.dart';
import '../widgets/ltr_numeric_field.dart';
import '../widgets/paper_field.dart';
import '../widgets/paper_range_text_controller.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/smart_exam_toolbar.dart';
import '../widgets/tex_text.dart';
import '../widgets/visual_equation_editor.dart';
import 'canonical_preview_plan_controller.dart';
import 'canonical_editing_layer.dart';
import 'header_footer_forms.dart';
import 'paper_header_footer_view.dart';
import 'paper_styles.dart';
import 'preview_toolbar.dart';

/// مرجع عنصر عائم (مستندياً، أو مرفق قديم داخل سؤال/فرع).
class _AttachmentRef {
  const _AttachmentRef({
    required this.questionIndex,
    this.branchIndex,
    required this.elementId,
  });

  final int questionIndex;
  final int? branchIndex;
  final String elementId;

  factory _AttachmentRef.global(String elementId) => _AttachmentRef(
        questionIndex: -1,
        elementId: elementId,
      );

  bool get isGlobal => questionIndex < 0;
  bool get isQuestionLevel => !isGlobal && branchIndex == null;
}

class _CanonicalFieldBinding {
  const _CanonicalFieldBinding({
    required this.fieldKey,
    required this.sourceText,
    required this.content,
    required this.style,
    required this.onEdit,
    required this.onLongPress,
    this.hint,
  });

  final String? hint;
  final String fieldKey;
  final String sourceText;
  final InlineContent content;
  final TextStyle style;
  final ValueChanged<String> onEdit;
  final VoidCallback onLongPress;
}

/// خصائص التنسيق التي تُطبَّق على التحديد النصّي وحده.
enum _RangeFormatAttribute { bold, italic, underline }

/// هدف تنسيق نصّي محدَّد: نص الحقل المخزَّن ونطاقاته وطريقة حفظها.
///
/// وجود هذا الهدف يعني أن المدرس **داخل حقل نص**، فتنسيقاته تُطبَّق على
/// التحديد (أو الجزء الذي عليه المؤشر) لا على السؤال كله.
class _RangeFormatTarget {
  const _RangeFormatTarget({
    required this.text,
    required this.spans,
    required this.style,
    required this.save,
  });

  final String text;
  final List<TextFormatSpan> spans;

  /// نمط العنصر الافتراضي: هو مرجع «القيمة الحالية» عند قلب bold/italic/….
  final PaperTextStyle style;

  final void Function(List<TextFormatSpan> formats) save;
}

class _CanonicalSelectionPainter extends CustomPainter {
  const _CanonicalSelectionPainter({
    required this.page,
    required this.semanticNodeId,
    required this.selection,
  });

  final LayoutPage page;
  final String semanticNodeId;
  final TextSelection selection;

  @override
  void paint(Canvas canvas, Size size) {
    for (final block in page.blocks) {
      for (final line in block.allLines) {
        for (final run in line.runs) {
          if (run.semanticNodeId != semanticNodeId || run.isMath || run.text.isEmpty) {
            continue;
          }
          final painter = TextPainter(
            text: TextSpan(
              text: run.text,
              style: TextStyle(
                fontFamily: run.style.font.family,
                fontSize: LayoutUnits.ptToPx(run.style.fontSizePt),
                fontWeight: run.style.bold ? FontWeight.w700 : FontWeight.w400,
                fontStyle: run.style.italic ? FontStyle.italic : FontStyle.normal,
                letterSpacing: run.style.letterSpacingPt == null
                    ? null
                    : LayoutUnits.ptToPx(run.style.letterSpacingPt!),
                height: run.style.lineHeightFactor,
                decoration:
                    run.style.underline ? TextDecoration.underline : null,
              ),
            ),
            textDirection: run.direction == DocumentDirection.rtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
          )..layout(maxWidth: double.infinity);
          try {
            final start = _localOffset(run, selection.start);
            final end = _localOffset(run, selection.end);
            final runLeft = LayoutUnits.ptToPx(run.x);
            final runTop = LayoutUnits.ptToPx(line.baseline - run.baselineOffset);
            final runHeight = LayoutUnits.ptToPx(run.height);
            if (!selection.isCollapsed && start != end) {
              final boxes = painter.getBoxesForSelection(
                TextSelection(baseOffset: start, extentOffset: end),
              );
              for (final box in boxes) {
                canvas.drawRect(
                  Rect.fromLTRB(
                    runLeft + box.left,
                    runTop + box.top,
                    runLeft + box.right,
                    runTop + box.bottom,
                  ),
                  Paint()..color = const Color(0x553B82F6),
                );
              }
            } else if (selection.isCollapsed &&
                selection.extentOffset >= run.sourceStartOffset &&
                selection.extentOffset <= _sourceEnd(run)) {
              final caret = painter.getOffsetForCaret(
                TextPosition(offset: start),
                Rect.zero,
              );
              final x = runLeft + caret.dx;
              canvas.drawLine(
                Offset(x, runTop),
                Offset(x, runTop + runHeight),
                Paint()
                  ..color = const Color(0xFF2563EB)
                  ..strokeWidth = 1.25,
              );
            }
          } finally {
            painter.dispose();
          }
        }
      }
    }
  }

  static int _sourceEnd(LayoutRun run) =>
      run.sourceEndOffset > run.sourceStartOffset
          ? run.sourceEndOffset
          : run.sourceStartOffset + run.text.length;

  static int _localOffset(LayoutRun run, int sourceOffset) {
    final sourceMap = run.sourceOffsetMap;
    if (sourceMap != null && sourceMap.isNotEmpty) {
      var nearest = 0;
      var nearestDistance = (sourceMap.first - sourceOffset).abs();
      for (var index = 1; index < sourceMap.length; index++) {
        final distance = (sourceMap[index] - sourceOffset).abs();
        if (distance < nearestDistance) {
          nearest = index;
          nearestDistance = distance;
        }
      }
      return nearest;
    }
    return (sourceOffset - run.sourceStartOffset)
        .clamp(0, run.text.length)
        .toInt();
  }

  @override
  bool shouldRepaint(covariant _CanonicalSelectionPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.semanticNodeId != semanticNodeId ||
      oldDelegate.selection != selection;
}

/// حوار إدخال نصي/رقمي مشترك يملك دورة حياة الـ controller داخليًا.
///
/// تحرير الـ controller فور عودة `showDialog` غير آمن: مسار الخروج المتحرك
/// يعيد بناء الحقل ويعيد الاشتراك في الـ controller المحرَّر
/// (استخدام-بعد-التحرير) — لذا يُحرَّر هنا في `dispose` فقط.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialText,
    this.hintText,
    this.helperText,
    this.saveLabel = 'حفظ',
    this.numeric = false,
    this.maxLines,
  });

  final String title;
  final String initialText;
  final String? hintText;
  final String? helperText;
  final String saveLabel;
  final bool numeric;

  /// عدد أسطر الحقل النصي (null = سطر واحد) — يُتجاهل في الوضع الرقمي.
  final int? maxLines;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: widget.numeric
          ? LtrNumericField(
              controller: _field,
              hintText: widget.hintText,
              decoration: InputDecoration(
                hintText: widget.hintText,
                helperText: widget.helperText,
                border: const OutlineInputBorder(),
              ),
            )
            : TextField(
              controller: _field,
              autofocus: true,
              maxLines: widget.maxLines,
              decoration: InputDecoration(
                hintText: widget.hintText,
                helperText: widget.helperText,
                border: const OutlineInputBorder(),
              ),
            ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

typedef CanonicalPreviewLayoutResolver = Future<LayoutDocument> Function({
  required ExamDocument document,
  required DocumentIR sourceIr,
});

typedef CanonicalPreviewAssetLoader =
    Future<CanonicalLayoutPreviewAssets> Function({
  required LayoutDocument layout,
  required ExamDocument document,
});

/// الخطوة 3: معاينة A4 تفاعلية بسطحين — يُختار أحدهما بحقن الوصلات.
///
/// - **سطح الورقة التفاعلي (الافتراضي)**: بلا وصلات محقونة تُبنى الورقة
///   كودجات قابلة للتحرير ([_buildPage]) فوق خطة LayoutEngine المشتركة؛
///   المعادلات تُرسم في مكانها، والنقر
///   يفتح محرر المحتوى المختلط. هذا سطح الإنتاج.
/// - **سطح canonical (محقون)**: مع [canonicalLayoutResolver] و
///   [canonicalPreviewAssetLoader] تُرسم هندسة [LayoutDocument] مباشرةً
///   ([CanonicalLayoutPreviewPage]) بلا إعادة التفاف أو تقسيم، والنقرات
///   تتحول إلى source offset. افتراضي الحقن يبقي مسار IME التشخيصي القديم؛
///   [enableSeparateEditorCandidate] يختار محررًا أصليًا خارج الورقة، اختياريًا
///   فقط حتى اكتمال جدول التغطية، ولا يفعّل هذا المسار في الإنتاج.
/// - **التصدير**: PDF المتجهي يحسم هندسته عند الطلب دون اعتماد على
///   حالة المعاينة الحية؛ وهو المسار الوحيد للتصدير.
/// - **التحديد والتنسيق**: تحديد سؤال/فرع/ترويسة/مربع نص (منفرد أو متعدد)
///   ثم تنسيقه من شريط المعاينة (خط/حجم/عريض/محاذاة/إطار).
/// - **إعادة الترتيب**: سحب سؤال كامل أو فرع داخل سؤاله؛ الإفلات على فرع
///   في سؤال آخر يبدّل المحتوى فقط (العناوين ثابتة).
/// - **العناصر العائمة**: صور/أشكال/مربعات نص ومعادلات على مستوى المستند
///   وصفحة A4، مستقلة عن السؤال والفرع؛ وتبقى المرفقات القديمة مدعومة.
///   تحريك بالسحب المباشر بين الصفحات، تغيير حجم (الصور بنسبة ثابتة)، تدوير،
///   إطار، حذف — والنقرة المزدوجة على مربع النص تفتح محرّره.
/// - **العرض**: تكبير/تصغير/ملاءمة/توسيط، وقفل يمنع التحريك العرضي.
class ExamPreviewScreen extends StatefulWidget {
  const ExamPreviewScreen({
    super.key,
    required this.onBackToQuestions,
    this.canonicalLayoutResolver,
    this.canonicalPreviewAssetLoader,
    this.enableSeparateEditorCandidate = false,
  });

  final VoidCallback onBackToQuestions;
  final CanonicalPreviewLayoutResolver? canonicalLayoutResolver;
  final CanonicalPreviewAssetLoader? canonicalPreviewAssetLoader;

  /// Integration candidate only. Requires BOTH injected canonical adapters;
  /// production remains on its repaired surface until the coverage gate passes.
  final bool enableSeparateEditorCandidate;

  @override
  State<ExamPreviewScreen> createState() => _ExamPreviewScreenState();
}

class _ExamPreviewScreenState extends State<ExamPreviewScreen> {
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{};
  final FormulaInserter _inserter = FormulaInserter();
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final Map<int, GlobalKey> _pageCanvasKeys = <int, GlobalKey>{};
  final GlobalKey _canonicalEditorViewport = GlobalKey(debugLabel: 'canonical-editor-viewport');
  late final Listenable _canonicalEditorScroll = Listenable.merge(<Listenable>[_vScroll, _hScroll]);
  bool _canonicalEditorOpen = false;
  int? _canonicalEditorPageHint;

  /// جذور اللقط (RepaintBoundary) لكل صفحة في المعاينة الحية.
  final Map<int, GlobalKey> _pageSnapshotKeys = <int, GlobalKey>{};

  /// **مصدر الحقيقة الوحيد للصفحات**: خطة `LayoutEngine` نفسها التي يطبعها PDF.
  ///
  /// كان السطح التفاعلي يبني صفحاته من `controller.pagination` (ارتفاعات
  /// ودجات مقاسة بالبكسل) بينما PDF يبنيها من `LayoutEngine` (نقاط): قِيس
  /// الفرق 4 صفحات مقابل 3 على المستند المرجعي نفسه. لم يبقَ في هذا الملف أي
  /// مسار يقسّم الصفحات بنفسه.
  late final CanonicalPreviewPlanController _planController;
  /// صور سطح العرض القانوني (رياضيات/عناصر عائمة): لا تُحمَّل إلا حين يكون
  /// هذا السطح هو المعروض، وللتخطيط نفسه فقط.
  CanonicalLayoutPreviewAssets? _canonicalPreviewAssets;
  LayoutDocument? _canonicalPreviewAssetsLayout;
  LayoutDocument? _canonicalPreviewAssetsFailedLayout;

  ExamWizardController? _controller;
  _AttachmentRef? _selectedAttachment;
  String? _selectedDividerKey;
  String? _activeItemFieldKey;
  String? _activeFieldKey;
  String? _activeCanonicalSemanticNodeId;
  final Map<String, PaperAlign> _fieldAlignments = <String, PaperAlign>{};
  bool _isBusy = false;

  /// سحب فوري لأي عنصر حر. نقطة الإمساك تبقى ثابتة داخل العنصر، ويُعاد
  /// تحويل المؤشر إلى إحداثيات الصفحة التي يمر فوقها؛ لذلك يمكن نقله بين
  /// صفحات A4 دون المرور على سؤال أو إعادة إرفاقه يدوياً.
  int? _dragPointer;
  Offset? _dragStartScreen;
  Offset? _dragLastScreen;
  Offset? _dragLastPaper;
  Offset? _dragAnchorWithinElement;
  int? _dragPageIndex;
  _AttachmentRef? _dragRef;

  /// هل تحرّك الإصبع فعليًّا في السحب الجاري؟ (للتفريق بين السحب والنقر).
  bool _dragMoved = false;

  /// آخر نقر على أي عنصر عائم (معرّفه ووقته) — لكشف النقر المزدوج على
  /// مربع النص يدويًّا: الفوز الفوري بساحة الإيماءات في مسار السحب يمنع
  /// وصول النقرة إلى [GestureDetector].
  String? _lastAttachmentTapId;
  Duration? _lastAttachmentTapTime;

  /// وقت آخر لمس على أي عنصر عائم (يقيسه الغلاف الخارجي في [Listener]).
  Duration? _lastPointerDownTime;

  /// معادلة حُرِّرت للتوّ وتنتظر أن يختار المستخدم موضعها على الورقة
  /// (نقرة على المكان المطلوب، أو سحبها من الشريط إلى الموضع).
  String? _stagedFormula;

  /// هل كتبت المعادلة المرشّحة كصيغة منفردة (`$$...$$`)?
  bool _stagedFormulaIsBlock = false;

  /// قفل التحريك: يمنع السحب وتغيير الحجم (التكبير والتمرير متاحان).
  bool _locked = false;

  /// التحديد المتعدد للتنسيق الجماعي.
  bool _multiSelect = false;
  final Set<String> _selectedQuestions = <String>{};
  final Set<BranchRef> _selectedBranches = <BranchRef>{};
  bool _headerSelected = false;

  /// تلميح «أنت الآن في وضع التحديد» يُعرض مرة واحدة في الجلسة عند الدخول
  /// بالضغط المطوّل (لا مع كل ضغطة فيزعج المستخدم).
  bool _selectionHintShown = false;
  bool _showFormulas = false;

  double _zoom = 1.0;
  double _viewportWidth = 0;
  bool _didAutoFit = false;

  static const double _minZoom = 0.4;
  static const double _maxZoom = 2.5;

  @override
  void initState() {
    super.initState();
    _planController = CanonicalPreviewPlanController()..onChanged = _onPlanChanged;
  }

  void _onPlanChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ExamWizardController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_syncFieldsFromModel);
      _controller = controller..addListener(_syncFieldsFromModel);
      _planController.request(controller.document, controller.documentIr);
    }
  }

  @override
  void dispose() {
    _controller?.applyLayoutPlan(null);
    _controller?.removeListener(_syncFieldsFromModel);
    _planController.onChanged = null;
    _planController.dispose();
    _canonicalPreviewAssets?.dispose();
    _canonicalPreviewAssets = null;
    for (final field in _fields.values) {
      field.dispose();
    }
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _trimPageKeysByIndices(Iterable<int> indices) {
    final valid = indices.toSet();
    _pageCanvasKeys.removeWhere((key, _) => !valid.contains(key));
  }

  // ------------------------------------------------------------------
  // حقول التحرير المباشر
  // ------------------------------------------------------------------

  bool _syncingFields = false;
  final Map<String, ValueChanged<String>> _fieldEdits = {};

  TextEditingController _field(String key, String initial, ValueChanged<String> onEdit) {
    // Refresh index-based callbacks after moves/deletions; controllers keep
    // their stable IDs, but their owners may now occupy different indices.
    _fieldEdits[key] = onEdit;
    return _fields.putIfAbsent(key, () {
      // متحكم يرسم تنسيق النطاقات داخل الحقل نفسه (لا طبقة فوقه).
      final field = PaperRangeTextEditingController(text: initial);
      var previousText = initial;
      var previousState = const TextFormatState();
      var previousSelection = field.selection;
      field.addListener(() {
        final text = field.text;
        if (text != previousText) {
          previousText = text;
          if (!_syncingFields) _fieldEdits[key]?.call(text);
          return;
        }
        // تغيّر التحديد وحده ليس تحريرًا، لكنه يغيّر حالة أزرار التنسيق:
        // تُعاد قراءة النطاق، ويحدث البناء فقط إذا تغيّرت الحالة فعلًا
        // (تنقّل المؤشر داخل الكلمة نفسها لا يهزّ الشاشة).
        if (_activeFieldKey != key || _multiSelect) return;
        final selectionChanged = field.selection != previousSelection;
        previousSelection = field.selection;
        final state = _selectionFormatState() ?? const TextFormatState();
        if (state == previousState && !(_separateEditorCandidate && selectionChanged)) return;
        previousState = state;
        _refreshSelectionFormatState();
      });
      return field;
    });
  }

  static String _statementKey(String questionId) => 'statement-$questionId';
  static String _bodyKey(String questionId) => 'body-$questionId';
  static String _categoryKey(String questionId) => 'category-$questionId';
  static String _branchStatementKey(String branchId) => 'branch-statement-$branchId';
  static String _branchBodyKey(String branchId) => 'branch-body-$branchId';
  static String _itemKey(String itemId) => 'item-$itemId';
  static String _optionKey(String itemId, int index) => 'option-$itemId-$index';

  /// يزامن الحقول مع النموذج بعد تغيّر خارجي (تبديل المحتوى بالسحب مثلاً).
  ///
  /// أثناء الكتابة يكون النموذج مساوياً للحقل أصلاً فلا يحدث أي تعديل.
  void _syncFieldsFromModel() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_syncingFields) return;
    _syncingFields = true;
    try {
      final document = controller.document;
      void sync(String key, String value) {
        final field = _fields[key];
        if (field != null && field.text != value) {
          field.text = value;
        }
      }

      void syncPoints(List<BranchItem> points) {
        for (final point in points) {
          sync(_itemKey(point.id), point.text);
          for (var index = 0; index < point.options.length; index++) {
            sync(_sourceOptionKey(point, index), point.options[index].text);
          }
        }
      }

      for (final question in document.questions) {
        sync(_statementKey(question.id), question.statement);
        sync(_bodyKey(question.id), question.body);
        sync(_categoryKey(question.id), question.category);
        syncPoints(question.items);
        for (final branch in question.branches) {
          sync(_branchStatementKey(branch.id), branch.content.statement);
          sync(_branchBodyKey(branch.id), branch.content.body);
          syncPoints(branch.content.items);
        }
      }
      _disposeStaleFields(document);
    } finally {
      _syncingFields = false;
      final controller = _controller;
      if (controller != null) {
        _planController.request(controller.document, controller.documentIr);
      }
    }
  }

  /// السطح القانوني للرسم (اختباري/تشخيصي) يُختار بحقن الوصلتين؛ وإلا فالسطح
  /// التفاعلي. **الاثنان يقرآن الخطة نفسها** — الاختلاف في آلية الرسم فقط.
  bool get _useCanonicalSurface =>
      widget.canonicalLayoutResolver != null &&
      widget.canonicalPreviewAssetLoader != null;

  bool get _separateEditorCandidate =>
      _useCanonicalSurface && widget.enableSeparateEditorCandidate;

  /// الخطة الحالية إن كانت تخصّ المستند الحالي بالذات (وإلا فلا هندسة).
  CanonicalPagePlan? get _pagePlan {
    final controller = _controller;
    final plan = _planController.plan;
    if (controller == null || plan == null) return null;
    return _planController.matches(controller.document, controller.documentIr)
        ? plan
        : null;
  }

  /// صفحة السؤال كما قرّرها المحرك (لا كما قاسها ودجت).
  int? _planPageOfQuestion(String questionId) => _pagePlan?.pageIndexOf(questionId);

  /// أعلى كتلة السؤال داخل صفحتها بالبكسل — من هندسة الخطة نفسها.
  double? _planBlockTopPx(String questionId) {
    final plan = _pagePlan;
    if (plan == null) return null;
    return plan.blockTopPxOf(questionId);
  }

  /// حالة «لا خطة بعد»: تخطيط جارٍ، أو فشل حسم مع إعادة محاولة.
  ///
  /// لا تُخترع هندسة بديلة هنا: قبل هذه البوابة كان السطح يرسم من ارتفاع
  /// ودجات مقاسة، فكان يعرض صفحات لا تطابق PDF عند أول إطار. الآن يُعرض ما
  /// هو صادق: الخطة لم تُحسم بعد.
  Widget _buildPlanPending({required bool failed}) {
    return SizedBox(
      width: ExamCanvasGeometry.width,
      height: 320,
      child: Center(
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(height: 8),
                  const Text('تعذّر تجهيز خطة الصفحات.'),
                  TextButton.icon(
                    onPressed: _retryCanonicalPreview,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }

  /// يحمّل صور السطح القانوني لتخطيط الخطة الحالية وحدها.
  void _ensureCanonicalAssets(LayoutDocument? planLayout, ExamDocument document) {
    if (!_useCanonicalSurface || planLayout == null) return;
    if (identical(_canonicalPreviewAssetsLayout, planLayout)) return;
    if (identical(_canonicalPreviewAssetsFailedLayout, planLayout)) return;
    _canonicalPreviewAssetsLayout = planLayout;
    final loader = widget.canonicalPreviewAssetLoader;
    unawaited(() async {
      try {
        final assets = loader == null
            ? await CanonicalLayoutPreviewAssets.load(
                layout: planLayout,
                document: document,
              )
            : await loader(layout: planLayout, document: document);
        if (!mounted || !identical(_canonicalPreviewAssetsLayout, planLayout)) {
          assets.dispose();
          return;
        }
        final previous = _canonicalPreviewAssets;
        setState(() => _canonicalPreviewAssets = assets);
        previous?.dispose();
      } catch (error, stackTrace) {
        ExportFileService.logError(
          'Canonical preview assets failed',
          error,
          stackTrace,
        );
        if (!mounted || !identical(_canonicalPreviewAssetsLayout, planLayout)) return;
        setState(() {
          _canonicalPreviewAssets = null;
          _canonicalPreviewAssetsFailedLayout = planLayout;
        });
      }
    }());
  }

  void _retryCanonicalPreview() {
    final failed = _planController.failedFor;
    final controller = _controller;
    if (controller == null) return;
    if (failed != null) {
      _planController.retry(controller.document, controller.documentIr);
      return;
    }
    setState(() {
      _canonicalPreviewAssetsFailedLayout = null;
      _canonicalPreviewAssetsLayout = null;
    });
  }

  /// يتخلّص من تحكمات الحقول التي حُذف أصحابها (سؤال أو فرع أو نقطة) فلا
  /// تتراكم تحكمات بلا مالك. الحذف يتم **بعد اكتمال الإطار** كي لا يُحرَّر
  /// تحكم ما زال مربوطاً بحقل في الشجرة الحالية.
  void _disposeStaleFields(ExamDocument document) {
    final live = <String>{};
    void addPoints(List<BranchItem> points) {
      for (final point in points) {
        live.add(_itemKey(point.id));
        for (var index = 0; index < point.options.length; index++) {
          live.add(_sourceOptionKey(point, index));
        }
      }
    }

    for (final question in document.questions) {
      live
        ..add(_statementKey(question.id))
        ..add(_bodyKey(question.id))
        ..add(_categoryKey(question.id));
      addPoints(question.items);
      for (final branch in question.branches) {
        live
          ..add(_branchStatementKey(branch.id))
          ..add(_branchBodyKey(branch.id));
        addPoints(branch.content.items);
      }
    }
    final stale = _fields.keys.where((key) => !live.contains(key)).toList(growable: false);
    if (stale.isEmpty) {
      return;
    }
    // يُزال القيد فوراً (فلا يُعاد استخدام تحكم نقطة محذوفة)، ويُحرَّر التحكم
    // بعد اكتمال إطارين — فالإطار الأول يُسقط الحقول من الشجرة، والثاني
    // يضمن أن التحكم لم يبق مربوطاً بأي حقل قبل تحريره.
    for (final key in stale) {
      if (identical(_inserter.controller, _fields[key])) _inserter.controller = null;
      _fieldEdits.remove(key);
    }
    final orphaned = <TextEditingController>[
      for (final key in stale) _fields.remove(key)!,
    ];
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final controller in orphaned) {
          controller.dispose();
        }
      });
    });
  }

  static double? _parseMarks(String value) {
    final normalized = value.trim().replaceAll('،', '.').replaceAll(',', '.');
    if (normalized.isEmpty) {
      return 0;
    }
    final marks = double.tryParse(normalized);
    return marks != null && marks.isFinite && marks >= 0 ? marks : null;
  }

  static String _formatMarksInput(double marks) {
    if (marks == 0) {
      return '';
    }
    return marks == marks.truncateToDouble() ? marks.toInt().toString() : marks.toString();
  }

  // ------------------------------------------------------------------
  // التحديد
  // ------------------------------------------------------------------

  void _clearSelection() {
    _selectedQuestions.clear();
    _selectedBranches.clear();
    _headerSelected = false;
    _selectedAttachment = null;
    _selectedDividerKey = null;
    _activeItemFieldKey = null;
    _activeFieldKey = null;
    _activeCanonicalSemanticNodeId = null;
  }

  void _tapQuestion(int index) {
    final controller = _controller!;
    final id = controller.questions[index].id;
    setState(() {
      if (_multiSelect) {
        if (!_selectedQuestions.remove(id)) {
          _selectedQuestions.add(id);
        }
      } else {
        _clearSelection();
        _selectedQuestions.add(id);
      }
      controller.selectQuestion(index);
      if (!_multiSelect) {
        controller.selectBranch(null);
      }
    });
  }

  void _tapBranch(BranchRef ref) {
    final controller = _controller!;
    setState(() {
      if (_multiSelect) {
        if (!_selectedBranches.remove(ref)) {
          _selectedBranches.add(ref);
        }
        controller.selectBranch(ref);
      } else {
        _clearSelection();
        _selectedBranches.add(ref);
        controller.selectBranch(ref);
      }
    });
  }

  void _tapHeader() {
    setState(() {
      final was = _headerSelected;
      _clearSelection();
      _headerSelected = !was;
    });
  }

  /// مفتاح «تحديد متعدد» في الشريط: يفتح الوضع ويُغلقه ويفرّغ التحديد عند
  /// كل تبديل (كما كان) — والخروج يلغي كل تحديد فلا تبقى عناصر «معلّقة»
  /// بلا وضع يفسّرها.
  void _toggleMultiSelect() {
    setState(() {
      _multiSelect = !_multiSelect;
      _clearSelection();
    });
  }

  /// الضغط المطوّل على أي موضع من السؤال: يفتح وضع التحديد المتعدد ويحدد
  /// السؤال، أو يقلب تحديده إن كان الوضع مفتوحاً (سلوك شريط خطوة الأسئلة
  /// نفسه، موسَّعاً ليشمل أي نقطة من كتلة السؤال لا رقمها وحده).
  void _longPressQuestion(int index) {
    final controller = _controller!;
    final id = controller.questions[index].id;
    final wasInMultiSelect = _multiSelect;
    setState(() {
      if (!_multiSelect) {
        _clearSelection();
        _multiSelect = true;
        _selectedQuestions.add(id);
      } else if (!_selectedQuestions.remove(id)) {
        _selectedQuestions.add(id);
      }
      controller.selectQuestion(index);
      if (!wasInMultiSelect) {
        controller.selectBranch(null);
      }
    });
    _announceSelectionMode(wasInMultiSelect);
  }

  /// الضغط المطوّل على أي موضع من الفرع (منطوقه أو نصه أو نقاطه أو خياراتها):
  /// يفتح وضع التحديد المتعدد ويحدد الفرع، أو يقلب تحديده داخله.
  /// استدعاء الضغط المطوّل المناسب لعنوان النقاط: نقطة سؤال مباشرة أو نقطة
  /// فرع. تُستعمل حقول النقاط والخيارات نفسها في المسارين، فلا يعرف الحقل
  /// تلقائياً إلى أي كتلة ينتمي، فيمرَّر إليه هذا الاستدعاء صراحة.
  VoidCallback _pointsOwnerLongPress(PointsOwner owner) {
    final branchIndex = owner.branchIndex;
    if (branchIndex == null) {
      return () => _longPressQuestion(owner.questionIndex);
    }
    return () => _longPressBranch(
          BranchRef(questionIndex: owner.questionIndex, branchIndex: branchIndex),
        );
  }

  void _longPressBranch(BranchRef ref) {
    final controller = _controller!;
    final wasInMultiSelect = _multiSelect;
    setState(() {
      if (!_multiSelect) {
        _clearSelection();
        _multiSelect = true;
      }
      if (!_selectedBranches.remove(ref)) {
        _selectedBranches.add(ref);
      }
      controller.selectBranch(ref);
    });
    _announceSelectionMode(wasInMultiSelect);
  }

  /// رسالة قصيرة عند الدخول إلى وضع التحديد بالضغط المطوّل (مرة واحدة).
  void _announceSelectionMode(bool wasInMultiSelect) {
    if (wasInMultiSelect || _selectionHintShown) {
      return;
    }
    _selectionHintShown = true;
    _showMessage('وضع التحديد المتعدد: انقر أي عنصر آخر لإضافته أو إزالته.');
  }

  /// «تحديد الكل» في الشريط: يحدد كل أسئلة الورقة وفروعها دفعة واحدة
  /// (تنسيق جماعي حقيقي لكل محتوى منطقة الأسئلة)، ومرة أخرى يلغي تحديد
  /// الجميع مع البقاء في الوضع — كزر «تحديد الكل» في شريط خطوة الأسئلة.
  void _toggleSelectAll() {
    final controller = _controller;
    if (controller == null || controller.questions.isEmpty) {
      _showMessage('لا توجد أسئلة لتحديدها.');
      return;
    }
    setState(() {
      if (_allBlocksSelected) {
        _selectedQuestions.clear();
        _selectedBranches.clear();
        return;
      }
      _multiSelect = true;
      _headerSelected = false;
      _selectedAttachment = null;
      _selectedDividerKey = null;
      _selectedQuestions
        ..clear()
        ..addAll(controller.questions.map((question) => question.id));
      _selectedBranches
        ..clear()
        ..addAll(<BranchRef>[
          for (var questionIndex = 0;
              questionIndex < controller.questions.length;
              questionIndex++)
            for (var branchIndex = 0;
                branchIndex < controller.questions[questionIndex].branches.length;
                branchIndex++)
              BranchRef(questionIndex: questionIndex, branchIndex: branchIndex),
        ]);
    });
    if (!_selectionHintShown) {
      _selectionHintShown = true;
      _showMessage('حُددت أسئلة الورقة وفروعها كلها — طبّق التنسيق ثم ألغِ التحديد.');
    }
  }

  /// هل أسئلة الورقة وفروعها محددة كلها؟ (المصدر الوحيد لحالة زر «تحديد الكل»).
  bool get _allBlocksSelected {
    final controller = _controller;
    if (controller == null || controller.questions.isEmpty) {
      return false;
    }
    for (final question in controller.questions) {
      if (!_selectedQuestions.contains(question.id)) {
        return false;
      }
    }
    for (var questionIndex = 0;
        questionIndex < controller.questions.length;
        questionIndex++) {
      for (var branchIndex = 0;
          branchIndex < controller.questions[questionIndex].branches.length;
          branchIndex++) {
        if (!_selectedBranches
            .contains(BranchRef(questionIndex: questionIndex, branchIndex: branchIndex))) {
          return false;
        }
      }
    }
    return true;
  }

  /// عدد كتل الورقة القابلة للتحديد (أسئلة + فروع).
  int get _selectableBlockCount {
    final controller = _controller;
    if (controller == null) {
      return 0;
    }
    var count = controller.questions.length;
    for (final question in controller.questions) {
      count += question.branches.length;
    }
    return count;
  }

  /// عدد الكتل المحددة فعلاً (المعرفات الباقية في النموذج فقط).
  int get _selectedBlockCount {
    final controller = _controller;
    if (controller == null) {
      return 0;
    }
    var count = 0;
    for (final question in controller.questions) {
      if (_selectedQuestions.contains(question.id)) {
        count++;
      }
    }
    for (final ref in _selectedBranches) {
      if (controller.document.containsRef(ref)) {
        count++;
      }
    }
    return count;
  }

  /// هل الفرع [ref] محدد حالياً (منفرداً أو ضمن متعدد)؟
  bool _isBranchSelected(BranchRef ref) {
    if (_selectedBranches.contains(ref)) {
      return true;
    }
    return !_multiSelect && _controller?.selectedBranch == ref;
  }

  /// هل السؤال [index] محدد؟
  bool _isQuestionSelected(int index) {
    final questions = _controller!.questions;
    // حارس أمان: فهرس قديم أثناء إعادة بناء متداخلة = غير محدد لا عطل.
    if (index < 0 || index >= questions.length) {
      return false;
    }
    final id = questions[index].id;
    if (_selectedQuestions.contains(id)) {
      return true;
    }
    return !_multiSelect && _controller?.selectedQuestionIndex == index;
  }

  String _selectionLabel(ExamDocument document) {
    if (_selectedAttachment != null) {
      final ref = _selectedAttachment!;
      final element = _findAttachment(document, ref);
      if (element == null) {
        return '';
      }
      if (element.isImage) {
        return 'صورة';
      }
      if (element.isTextBox) {
        return 'مربع نص';
      }
      return 'شكل: ${element.shape?.arabicLabel ?? ''}';
    }
    if (_selectedDividerKey != null) {
      return 'فاصل';
    }
    final branches = _selectedBranches.where(document.containsRef).toList();
    if (_headerSelected) {
      return 'الترويسة';
    }
    if (branches.isNotEmpty && _selectedQuestions.isNotEmpty) {
      return 'تحديد متعدد (${document.formatNumber(branches.length + _selectedQuestions.length)})';
    }
    if (branches.length == 1) {
      final ref = branches.single;
      return 'الفرع ${document.displayBranchLabel(ref.questionIndex, ref.branchIndex)}'
          ' — ${document.displayQuestionLabel(document.questions[ref.questionIndex])}';
    }
    if (branches.length > 1) {
      return '${document.formatNumber(branches.length)} فروع';
    }
    if (_selectedQuestions.length == 1) {
      final question = document.questionById(_selectedQuestions.single);
      if (question != null) {
        return document.displayQuestionLabel(question);
      }
    }
    if (_selectedQuestions.length > 1) {
      return '${document.formatNumber(_selectedQuestions.length)} أسئلة';
    }
    final single = _controller?.selectedBranch;
    if (single != null && document.containsRef(single)) {
      return 'الفرع ${document.displayBranchLabel(single.questionIndex, single.branchIndex)}';
    }
    if (document.questions.isNotEmpty) {
      final index = _controller!.selectedQuestionIndex ?? _controller!.currentQuestionIndex;
      return document.displayQuestionLabel(document.questions[index]);
    }
    return '';
  }

  FloatingElement? _findAttachment(ExamDocument document, _AttachmentRef ref) {
    final freeElement = document.floatingElementById(ref.elementId);
    if (freeElement != null || ref.isGlobal) {
      return freeElement;
    }
    if (ref.questionIndex < 0 || ref.questionIndex >= document.questions.length) {
      return null;
    }
    final question = document.questions[ref.questionIndex];
    final list = ref.branchIndex == null
        ? question.attachments
        : (ref.branchIndex! < 0 || ref.branchIndex! >= question.branches.length
            ? const <FloatingElement>[]
            : question.branches[ref.branchIndex!].attachments);
    for (final element in list) {
      if (element.id == ref.elementId) {
        return element;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // التحكم بالمسافة بين الأسئلة
  // ------------------------------------------------------------------

  List<int> _questionSpacingTargets() {
    final controller = _controller;
    if (controller == null ||
        controller.questions.isEmpty ||
        _selectedAttachment != null ||
        _headerSelected ||
        _selectedDividerKey != null) {
      return const <int>[];
    }
    final indexes = <int>{};
    for (final id in _selectedQuestions) {
      final index = controller.document.indexOfQuestion(id);
      if (index >= 0) indexes.add(index);
    }
    for (final ref in _selectedBranches) {
      if (controller.document.containsRef(ref)) indexes.add(ref.questionIndex);
    }
    if (indexes.isNotEmpty) return indexes.toList()..sort();
    final branch = controller.selectedBranch;
    if (branch != null && controller.document.containsRef(branch)) {
      return <int>[branch.questionIndex];
    }
    final question = controller.selectedQuestionIndex;
    if (question != null) return <int>[question];
    return <int>[controller.currentQuestionIndex];
  }

  double? _activeQuestionSpacing() {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) return null;
    final first = _controller!.questions[targets.first].spacingAfter;
    return targets.every(
      (index) => (_controller!.questions[index].spacingAfter - first).abs() < 0.01,
    )
        ? first
        : null;
  }

  void _applyQuestionSpacing(double spacing) {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) {
      _showMessage('حدد سؤالاً أو فرعاً لتغيير المسافة بعد السؤال.');
      return;
    }
    for (final index in targets) {
      _controller!.updateQuestionSpacing(index, spacing);
    }
  }

  Future<void> _showCustomQuestionSpacing() async {
    final targets = _questionSpacingTargets();
    if (targets.isEmpty) {
      _showMessage('حدد سؤالاً أولاً لتغيير المسافة بينه وبين السؤال التالي.');
      return;
    }
    final current = _controller!.questions[targets.first].spacingAfter;
    final saved = await _showTextInputDialog(
      title: 'المسافة بين الأسئلة',
      initialText: current.toString(),
      hintText: '0 = بلا فراغ إضافي',
      helperText: 'أدخل قيمة من 0 إلى 200 بكسل.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) return;
    final spacing = double.tryParse(saved.trim().replaceAll('،', '.').replaceAll(',', '.'));
    if (spacing == null || !spacing.isFinite || spacing < 0 || spacing > 200) {
      _showMessage('المسافة يجب أن تكون بين 0 و200 بكسل.', isError: true);
      return;
    }
    _applyQuestionSpacing(spacing);
  }

  // ------------------------------------------------------------------
  // تنسيق التحديد
  // ------------------------------------------------------------------

  /// يجمع أهداف التنسيق: فروع، أسئلة، ترويسة، مربعات نص.
  ///
  /// بلا تحديد صريح يُستخدم «العنصر النشط»: الفرع المحدد، وإلا السؤال
  /// المحدد، وإلا السؤال المفتوح حالياً.
  ({List<BranchRef> branches, List<int> questions, bool header, List<_AttachmentRef> boxes})
      _styleTargets() {
    final controller = _controller!;
    final document = controller.document;
    if (_selectedAttachment != null) {
      final element = _findAttachment(document, _selectedAttachment!);
      if (element != null && element.isTextBox) {
        return (branches: const [], questions: const [], header: false, boxes: [_selectedAttachment!]);
      }
      return (branches: const [], questions: const [], header: false, boxes: const []);
    }
    final branches =
        _selectedBranches.where(document.containsRef).toList(growable: false);
    final questions = <int>[];
    for (final id in _selectedQuestions) {
      final index = document.indexOfQuestion(id);
      if (index != -1) {
        questions.add(index);
      }
    }
    if (branches.isNotEmpty || questions.isNotEmpty || _headerSelected) {
      return (branches: branches, questions: questions, header: _headerSelected, boxes: const []);
    }
    final single = controller.selectedBranch;
    if (single != null && document.containsRef(single)) {
      return (branches: [single], questions: const [], header: false, boxes: const []);
    }
    final selectedQuestion = controller.selectedQuestionIndex;
    if (selectedQuestion != null) {
      return (branches: const [], questions: [selectedQuestion], header: false, boxes: const []);
    }
    if (document.questions.isEmpty) {
      return (
        branches: const [],
        questions: const [],
        header: false,
        boxes: const [],
      );
    }
    return (
      branches: const [],
      questions: [controller.currentQuestionIndex],
      header: false,
      boxes: const [],
    );
  }

  /// النمط المعروض في الشريط (من أول هدف).
  PaperTextStyle _activeStyle() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.textStyle ??
          PaperTextStyle.empty;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).style;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].style;
    }
    if (targets.header) {
      return document.header.style;
    }
    return PaperTextStyle.empty;
  }

  int? _activeColor() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.textStyle.color;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).style.color;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].effectiveTitleColor;
    }
    if (targets.header) {
      return document.header.style.color;
    }
    return null;
  }

  String _colorTooltip() {
    final targets = _styleTargets();
    return targets.questions.isNotEmpty &&
            targets.branches.isEmpty &&
            !targets.header &&
            targets.boxes.isEmpty
        ? 'لون عنوان السؤال'
        : 'لون النص';
  }

  /// معاملا القياس العامّان من إعدادات الورقة (حجم الخط الأساسي وتباعد
  /// الأسطر) — يُمرَّران لكل أنماط اللوحة حتى تكبر الورقة وتصغر معاً.
  double get _fontScale => _controller!.document.settings.fontScale;
  double get _heightScale => _controller!.document.settings.heightScale;

  /// يقيس نمطاً أساسياً مباشراً بمعاملَي الورقة (للأنماط بلا [resolve]).
  TextStyle _scaled(TextStyle base) => PaperStyles.scale(
        base,
        fontScale: _fontScale,
        heightScale: _heightScale,
      );

  bool? _activeFrame() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    if (targets.boxes.isNotEmpty) {
      return _findAttachment(document, targets.boxes.first)?.framed;
    }
    if (targets.branches.isNotEmpty) {
      return document.branchAt(targets.branches.first).showFrame;
    }
    if (targets.questions.isNotEmpty) {
      return document.questions[targets.questions.first].showFrame;
    }
    if (targets.header) {
      return document.settings.headerBorder;
    }
    return null;
  }

  /// مجموعة النقاط التي تحمل النقطة [pointId] (سؤال أو فرع) أو `null`.
  PointsOwner? _ownerOfPoint(ExamDocument document, String pointId) {
    for (var q = 0; q < document.questions.length; q++) {
      final question = document.questions[q];
      if (question.items.any((point) => point.id == pointId)) {
        return PointsOwner.question(q);
      }
      for (var b = 0; b < question.branches.length; b++) {
        if (question.branches[b].content.items.any((point) => point.id == pointId)) {
          return PointsOwner.branch(BranchRef(questionIndex: q, branchIndex: b));
        }
      }
    }
    return null;
  }

  BranchItem? _findItem(String itemId) {
    final doc = _controller?.document;
    if (doc == null) return null;
    final owner = _ownerOfPoint(doc, itemId);
    if (owner == null) return null;
    for (final point in doc.pointsOf(owner)) {
      if (point.id == itemId) return point;
    }
    return null;
  }

  /// مفاتيح الحقول التي لها نظير مباشر في الموديل — تُقرأ من الموديل دائماً
  /// (ولا تتأثر ببقايا _fieldAlignments بعد التراجع).
  bool _isModelBackedAlignKey(String fieldKey) =>
      fieldKey.startsWith('statement-') ||
      fieldKey.startsWith('body-') ||
      fieldKey.startsWith('category-') ||
      fieldKey.startsWith('branch-') ||
      _isOptionFieldKey(fieldKey) ||
      fieldKey.startsWith('item-');

  static final RegExp _optionKeyPattern = RegExp(r'^option-(.+)-(\d+)$');

  bool _isOptionFieldKey(String key) => key.startsWith('option-') || key.startsWith('option:');

  String _sourceOptionKey(BranchItem point, int index) => _separateEditorCandidate
      ? 'option:${Uri.encodeComponent(point.id)}:${Uri.encodeComponent(point.options[index].id)}'
      : _optionKey(point.id, index);

  /// Candidate option keys encode MODEL IDs, not mutable list positions.
  /// Legacy print controls keep their existing index keys until replacement.
  ({String pointId, int index})? _optionSourceTarget(String key) {
    if (key.startsWith('option:')) {
      final parts = key.split(':');
      if (parts.length != 3) return null;
      try {
        final pointId = Uri.decodeComponent(parts[1]);
        final optionId = Uri.decodeComponent(parts[2]);
        final point = _findItem(pointId);
        final index = point?.options.indexWhere((option) => option.id == optionId) ?? -1;
        return index < 0 ? null : (pointId: pointId, index: index);
      } on FormatException {
        return null;
      }
    }
    final match = _optionKeyPattern.firstMatch(key);
    if (match == null) return null;
    final pointId = match.group(1)!;
    final index = int.parse(match.group(2)!);
    final point = _findItem(pointId);
    return point == null || index >= point.options.length ? null : (pointId: pointId, index: index);
  }

  /// Resolve IDs at INPUT TIME, including the same-frame interval before a
  /// provider notification has rebuilt the view/callbacks. No copied model or
  /// alternate edit path: dispatch to the existing update methods only.
  void _writeCanonicalSource(String key, String value) {
    final controller = _controller;
    if (controller == null) return;
    final document = controller.document;
    final option = _optionSourceTarget(key);
    if (option != null) {
      final owner = _ownerOfPoint(document, option.pointId);
      if (owner != null) controller.updatePointOptionText(owner, option.pointId, option.index, value);
      return;
    }
    if (key.startsWith('item-')) {
      final id = key.substring('item-'.length);
      final owner = _ownerOfPoint(document, id);
      if (owner != null) controller.updatePointText(owner, id, value);
      return;
    }
    for (final prefix in <String>['branch-statement-', 'branch-body-']) {
      if (!key.startsWith(prefix)) continue;
      final ref = _findBranchRef(document, key.substring(prefix.length));
      if (ref == null) return;
      if (prefix == 'branch-statement-') { controller.updateBranchStatement(ref, value); }
      else { controller.updateBranchBody(ref, value); }
      return;
    }
    for (final prefix in <String>['statement-', 'body-', 'category-']) {
      if (!key.startsWith(prefix)) continue;
      final index = document.indexOfQuestion(key.substring(prefix.length));
      if (index < 0) return;
      if (prefix == 'statement-') { controller.updateQuestionStatement(index, value); }
      else if (prefix == 'body-') { controller.updateQuestionBody(index, value); }
      else { controller.updateQuestionCategory(index, value); }
      return;
    }
  }

  /// المحاذاة المحفوظة في الموديل لمفتاح حقل (null = غير محددة).
  PaperAlign? _modelAlignFor(String fieldKey) {
    final doc = _controller?.document;
    if (doc == null) {
      return null;
    }
    if (fieldKey.startsWith('statement-')) {
      final question = doc.questionById(fieldKey.substring('statement-'.length));
      return question == null ? null : question.titleAlign ?? question.style.align;
    }
    if (fieldKey.startsWith('body-')) {
      final question = doc.questionById(fieldKey.substring('body-'.length));
      return question == null ? null : question.bodyAlign ?? question.style.align;
    }
    // سطر القسم: محاذاته تُحفظ في النموذج (`categoryAlign`) فتصل إلى
    // المعاينة وPDF وWord — لا تبقى في خريطة الشاشة وحدها.
    if (fieldKey.startsWith('category-')) {
      final question = doc.questionById(fieldKey.substring('category-'.length));
      return question?.categoryAlign;
    }
    for (final prefix in const <String>['branch-statement-', 'branch-body-']) {
      if (fieldKey.startsWith(prefix)) {
        final ref = _findBranchRef(doc, fieldKey.substring(prefix.length));
        if (ref == null) {
          return null;
        }
        final branch = doc.branchAt(ref);
        return prefix == 'branch-statement-'
            ? branch.titleAlign ?? branch.style.align
            : branch.bodyAlign ?? branch.style.align;
      }
    }
    if (_isOptionFieldKey(fieldKey)) {
      final option = _optionSourceTarget(fieldKey);
      return option == null ? null : _findItem(option.pointId)?.options[option.index].align;
    }
    if (fieldKey.startsWith('item-')) {
      return _findItem(fieldKey.substring('item-'.length))?.align;
    }
    return null;
  }

  BranchRef? _findBranchRef(ExamDocument document, String branchId) {
    for (var q = 0; q < document.questions.length; q++) {
      final bIdx = document.questions[q].indexOfBranch(branchId);
      if (bIdx != -1) {
        return BranchRef(questionIndex: q, branchIndex: bIdx);
      }
    }
    return null;
  }

  TextAlign _textAlignFor(String fieldKey, {TextAlign fallback = TextAlign.start}) {
    if (_isModelBackedAlignKey(fieldKey)) {
      final model = _modelAlignFor(fieldKey);
      return model != null ? PaperStyles.toTextAlign(model) : fallback;
    }
    if (_fieldAlignments.containsKey(fieldKey)) {
      return PaperStyles.toTextAlign(_fieldAlignments[fieldKey]);
    }
    return fallback;
  }

  PaperAlign? _activeAlign() {
    if (_activeFieldKey != null) {
      if (_isModelBackedAlignKey(_activeFieldKey!)) {
        final model = _modelAlignFor(_activeFieldKey!);
        if (model != null) {
          return model;
        }
      } else if (_fieldAlignments.containsKey(_activeFieldKey)) {
        return _fieldAlignments[_activeFieldKey];
      }
    }
    return _activeStyle().align;
  }

  /// يطبّق محاذاة على الحقل النشط وحده (كما في Word: الفقرة الحالية)؛ وبلا
  /// حقل نشط تُطبَّق على عناصر التحديد.
  void _onAlignChanged(PaperAlign align) {
    setState(() {
      if (_activeFieldKey != null) {
        _fieldAlignments[_activeFieldKey!] = align;
      }
    });

    final controller = _controller!;
    final document = controller.document;
    final key = _activeFieldKey;
    if (key == null) {
      // لا حقل نشط: تُطبَّق على الأهداف المحددة (سؤال/فرع كامل).
      _applyStyle((current) => current.copyWith(align: () => align));
      return;
    }

    // 1. نقطة محددة: تتغير محاذاة تلك النقطة وحدها (في الموديل مباشرةً
    //    فتصل إلى PDF/Word أيضاً).
    if (key.startsWith('item-')) {
      final pointId = key.substring('item-'.length);
      final owner = _ownerOfPoint(document, pointId);
      if (owner != null) {
        controller.updatePointAlign(owner, pointId, align);
      }
      return;
    }

    // 2. خيار «اختيار من متعدد» محدد: محاذاته وحده.
    final option = _optionSourceTarget(key);
    if (option != null) {
      final owner = _ownerOfPoint(document, option.pointId);
      if (owner != null) controller.updatePointOptionAlign(owner, option.pointId, option.index, align);
      return;
    }

    // 3. منطوق السؤال (سطر العنوان).
    if (key.startsWith('statement-')) {
      final index = document.indexOfQuestion(key.substring('statement-'.length));
      if (index != -1) {
        controller.updateQuestionTitleAlign(index, align);
      }
      return;
    }

    // 3ب. سطر القسم: محاذاته في النموذج مباشرةً (categoryAlign).
    if (key.startsWith('category-')) {
      final index = document.indexOfQuestion(key.substring('category-'.length));
      if (index != -1) {
        controller.updateQuestionCategoryAlign(index, align);
      }
      return;
    }

    // 4. نص السؤال: تحديث واحد يكتب bodyAlign وstyle.align معاً = خطوة
    //    تراجع واحدة.
    if (key.startsWith('body-')) {
      final index = document.indexOfQuestion(key.substring('body-'.length));
      if (index != -1) {
        controller.updateQuestionBodyAlign(index, align);
      }
      return;
    }

    // 5. منطوق الفرع ونصه: كلٌّ فقرة مستقلة (لا تتبادل المحاذاة مع الأخرى).
    for (final prefix in const <String>['branch-statement-', 'branch-body-']) {
      if (key.startsWith(prefix)) {
        final ref = _findBranchRef(document, key.substring(prefix.length));
        if (ref != null) {
          if (prefix == 'branch-statement-') {
            controller.updateBranchTitleAlign(ref, align);
          } else {
            controller.updateBranchBodyAlign(ref, align);
          }
        }
        return;
      }
    }
    // حقل بلا موديل مخصص بعد (مثل قسم السؤال) — يبقى في خريطة الشاشة.
  }

  /// حقل النص النشط إن كان من حقول النموذج القابلة للتنسيق بالنطاقات.
  _RangeFormatTarget? _activeRangeTarget() {
    final controller = _controller;
    final key = _activeFieldKey;
    if (controller == null || key == null) return null;
    final document = controller.document;
    if (key.startsWith('branch-statement-') || key.startsWith('branch-body-')) {
      final isStatement = key.startsWith('branch-statement-');
      final id = key.substring(isStatement ? 17 : 12);
      for (var questionIndex = 0;
          questionIndex < document.questions.length;
          questionIndex++) {
        final branches = document.questions[questionIndex].branches;
        for (var branchIndex = 0;
            branchIndex < branches.length;
            branchIndex++) {
          final branch = branches[branchIndex];
          if (branch.id != id) continue;
          final ref = BranchRef(
            questionIndex: questionIndex,
            branchIndex: branchIndex,
          );
          final content = branch.content;
          return _RangeFormatTarget(
            text: isStatement ? content.statement : content.body,
            spans:
                isStatement ? content.statementFormats : content.bodyFormats,
            style: branch.style,
            save: isStatement
                ? (formats) =>
                    controller.updateBranchStatementFormats(ref, formats)
                : (formats) =>
                    controller.updateBranchBodyFormats(ref, formats),
          );
        }
      }
      return null;
    }
    // نقاط السؤال وفرعه وخياراتها: نفس نموذج النطاقات، لا مسار تنسيق ثانٍ.
    if (key.startsWith('item-') || _isOptionFieldKey(key)) {
      final isOption = _isOptionFieldKey(key);
      final String pointId;
      int? optionIndex;
      if (isOption) {
        final option = _optionSourceTarget(key);
        if (option == null) return null;
        pointId = option.pointId;
        optionIndex = option.index;
      } else {
        pointId = key.substring('item-'.length);
      }
      // مالك النقطة يُحسم من المستند نفسه (نفس مصدر المحاذاة أعلاه)، فلا
      // تُنسخ نقاط إلى حالة عرض موازية.
      final owner = _ownerOfPoint(document, pointId);
      final point = _findItem(pointId);
      if (owner == null || point == null) return null;
      final ownerStyle = owner.branchIndex == null
          ? document.questions[owner.questionIndex].style
          : document
              .branchAt(BranchRef(
                questionIndex: owner.questionIndex,
                branchIndex: owner.branchIndex!,
              ))
              .style;
      if (!isOption) {
        return _RangeFormatTarget(
          text: point.text,
          spans: point.textFormats,
          style: ownerStyle,
          save: (formats) =>
              controller.updatePointTextFormats(owner, pointId, formats),
        );
      }
      final index = optionIndex!;
      if (index < 0 || index >= point.options.length) return null;
      final option = point.options[index];
      return _RangeFormatTarget(
        text: option.text,
        spans: option.formats,
        style: ownerStyle,
        save: (formats) => controller.updatePointOptionFormats(
          owner,
          pointId,
          index,
          formats,
        ),
      );
    }
    final isStatement = key.startsWith('statement-');
    final isBody = key.startsWith('body-');
    if (!isStatement && !isBody) return null;
    final id = key.substring(isStatement ? 10 : 5);
    for (var index = 0; index < controller.questions.length; index++) {
      final question = controller.questions[index];
      if (question.id != id) continue;
      return _RangeFormatTarget(
        text: isStatement ? question.statement : question.body,
        spans: isStatement ? question.statementFormats : question.bodyFormats,
        style: question.style,
        save: isStatement
            ? (formats) => controller.updateQuestionStatementFormats(
                  index,
                  formats,
                )
            : (formats) =>
                controller.updateQuestionBodyFormats(index, formats),
      );
    }
    return null;
  }

  /// النطاق المحدَّد فعليًّا في الحقل النشط.
  ///
  /// القاعدة المعلنة: **لا نطاق بلا تحديد**. المؤشر المطوي (نقرة في حقل)
  /// يُبقي سلوك التنسيق القديم: تعديل النمط الافتراضي للعنصر. أما تحديد نصّي
  /// حقيقي فيأخذ مساره الخاص: bold/italic/underline/اللون على المحارف وحدها.
  TextFormatSpan? _selectedRange(_RangeFormatTarget target) {
    final field = _fields[_activeFieldKey];
    final selection = field?.selection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      return null;
    }
    return TextFormatSpans.targetRange(
      target.text,
      start: selection.baseOffset,
      end: selection.extentOffset,
    );
  }

  /// حالة أزرار الشريط من **التحديد الفعلي** لا من نمط العنصر.
  ///
  /// `null` = لا تحديد نصّي في حقل قابل للتنسيق، فيبقى العرض على نمط العنصر
  /// (سلوك المحرر قبل هذه الميزة). وعند وجود تحديد تُقرأ خصائص كل محرف في
  /// النطاق فوق نمط العنصر: متّفقة ⇒ `true/false`، مختلفة ⇒ `null` (مختلط)،
  /// وهو ما يعرضه [PreviewToolbar] غير مفعّل بدل ادّعاء حالةٍ واحدة.
  TextFormatState? _selectionFormatState() {
    final target = _activeRangeTarget();
    if (target == null) return null;
    final range = _selectedRange(target);
    if (range == null) return null;
    return TextFormatSpans.stateForRange(
      target.spans,
      start: range.start,
      end: range.end,
      baseBold: target.style.bold ?? false,
      baseItalic: target.style.italic ?? false,
      baseUnderline: target.style.underline ?? false,
      baseColor: target.style.color,
    );
  }

  /// إعادة بناء آمنة عند تغيّر التحديد (قد يصل الإشعار أثناء بناء إطار).
  void _refreshSelectionFormatState() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// يقلب bold/italic/underline على التحديد وحده.
  ///
  /// القاعدة المعلنة: داخل حقل نص لا يوجد «تنسيق للسؤال كله». مؤشر مطوٍ يعني
  /// الكلمة التي عليه؛ وحقل فارغ يعني رسالة لا تعديل.
  void _toggleSelectionFormat(_RangeFormatAttribute attribute) {
    final target = _activeRangeTarget();
    final range = target == null ? null : _selectedRange(target);
    if (target == null || range == null) {
      // لا حقل نصي نشط: يبقى التنسيق نمطًا افتراضيًا للعنصر المحدَّد.
      _applyStyle((current) => switch (attribute) {
            _RangeFormatAttribute.bold =>
              current.copyWith(bold: () => !(current.bold ?? false)),
            _RangeFormatAttribute.italic =>
              current.copyWith(italic: () => !(current.italic ?? false)),
            _RangeFormatAttribute.underline =>
              current.copyWith(underline: () => !(current.underline ?? false)),
          });
      return;
    }
    final current = TextFormatSpans.attributeAt(target.spans, range.start);
    final bool value;
    switch (attribute) {
      case _RangeFormatAttribute.bold:
        value = !(current?.bold ?? target.style.bold ?? false);
        break;
      case _RangeFormatAttribute.italic:
        value = !(current?.italic ?? target.style.italic ?? false);
        break;
      case _RangeFormatAttribute.underline:
        value = !(current?.underline ?? target.style.underline ?? false);
        break;
    }
    target.save(
      TextFormatSpans.apply(
        target.spans,
        TextFormatSpan(
          start: range.start,
          end: range.end,
          bold: attribute == _RangeFormatAttribute.bold ? value : null,
          italic: attribute == _RangeFormatAttribute.italic ? value : null,
          underline: attribute == _RangeFormatAttribute.underline ? value : null,
        ),
        textLength: target.text.length,
      ),
    );
  }

  /// يطبّق اللون على التحديد وحده؛ `null` = عودة إلى لون العنصر.
  void _applySelectionColor(int? color) {
    final target = _activeRangeTarget();
    final range = target == null ? null : _selectedRange(target);
    if (target == null || range == null) {
      _applyColor(color);
      return;
    }
    target.save(
      color == null
          ? TextFormatSpans.clear(
              target.spans,
              start: range.start,
              end: range.end,
              color: true,
              textLength: target.text.length,
            )
          : TextFormatSpans.apply(
              target.spans,
              TextFormatSpan(
                start: range.start,
                end: range.end,
                color: color,
              ),
              textLength: target.text.length,
            ),
    );
  }

  void _applyStyle(PaperTextStyle Function(PaperTextStyle current) update) {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    // تنسيق واحد على كل الأهداف = خطوة تراجع واحدة (MSO): دفعة واحدة
    // تجمع الفروع والأسئلة بدل commit لكل هدف.
    final branchStyles = <BranchRef, PaperTextStyle>{
      for (final ref in targets.branches) ref: update(document.branchAt(ref).style),
    };
    final questionStyles = <int, PaperTextStyle>{
      for (final index in targets.questions) index: update(document.questions[index].style),
    };
    if (branchStyles.isNotEmpty || questionStyles.isNotEmpty) {
      controller.applyStyleBatch(
        branchStyles: branchStyles,
        questionStyles: questionStyles,
      );
      applied = true;
    }
    if (targets.header) {
      controller.updateHeaderStyle(update(document.header.style));
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) {
        continue;
      }
      _updateAttachmentElement(ref, element.copyWith(textStyle: update(element.textStyle)));
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق التنسيق.');
    }
  }

  /// عند تحديد سؤال يلوّن هذا الأمر عنوانه فقط؛ الفروع ومربعات النص
  /// والترويسة تحتفظ بتنسيقها المعتاد.
  void _applyColor(int? color) {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    for (final ref in targets.branches) {
      controller.updateBranchStyle(
        ref,
        document.branchAt(ref).style.copyWith(color: () => color),
      );
      applied = true;
    }
    for (final index in targets.questions) {
      controller.updateQuestionTitleColor(index, color);
      applied = true;
    }
    if (targets.header) {
      controller.updateHeaderStyle(
        document.header.style.copyWith(color: () => color),
      );
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) continue;
      _updateAttachmentElement(
        ref,
        element.copyWith(
          textStyle: element.textStyle.copyWith(color: () => color),
        ),
      );
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق اللون.');
    }
  }

  void _toggleFrame() {
    final controller = _controller!;
    final document = controller.document;
    final targets = _styleTargets();
    var applied = false;
    for (final ref in targets.branches) {
      controller.toggleBranchFrame(ref);
      applied = true;
    }
    for (final index in targets.questions) {
      controller.toggleQuestionFrame(index);
      applied = true;
    }
    if (targets.header) {
      controller.updateSettings(
        document.settings.copyWith(headerBorder: !document.settings.headerBorder),
      );
      applied = true;
    }
    for (final ref in targets.boxes) {
      final element = _findAttachment(document, ref);
      if (element == null) {
        continue;
      }
      _updateAttachmentElement(ref, element.copyWith(framed: !element.framed));
      applied = true;
    }
    if (!applied) {
      _showMessage('حدد عنصراً أولاً لإضافة إطار حوله.');
    }
  }

  // ------------------------------------------------------------------
  // إجراءات
  // ------------------------------------------------------------------

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// موضع افتراضي لعنصر جديد بإحداثيات الورقة **المطلقة**: رأس كتلة السؤال
  /// المحدد (فتظهر الصورة/الشكل قريباً من سياقه كما كان)، ويسحبه المستخدم بعد
  /// ذلك إلى أي نقطة على الورقة.
  ///
  /// العناصر تُرسم الآن في طبقة الصفحة بإحداثي مطلق، فلو تُرك (0،0) لظهرت في
  /// أعلى الورقة بعيداً عن السؤال — ومن هنا جاء هذا الحساب.
  /// السؤال المحدد حالياً (مالك العناصر الجديدة) أو `null` إن لا تحديد.
  String? _selectedOwnerQuestionId() {
    final controller = _controller;
    if (controller == null || controller.questions.isEmpty) {
      return null;
    }
    final index = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex;
    if (index == null || index < 0 || index >= controller.questions.length) {
      return null;
    }
    return controller.questions[index].id;
  }

  /// موضع افتراضي للعنصر الجديد: داخل السؤال المحدد (مرتبطاً به) إن وُجد
  /// تحديد — وإلا موضع حر على صفحة السؤال النشط.
  FloatingElement _withDefaultPosition(FloatingElement element) {
    final controller = _controller;
    if (controller == null) {
      return element;
    }
    final owner = _selectedOwnerQuestionId();
    if (owner != null) {
      final rect = _pagePlan?.questionRectPx(owner);
      if (rect != null) {
        final maxDx = math.max(0.0, rect.width - element.width);
        final maxDy = math.max(0.0, rect.height - element.height);
        return element.withOwner(owner).copyWith(
              pageIndex: rect.pageIndex,
              dx: maxDx / 2,
              dy: math.min(maxDy, 8),
            );
      }
    }
    if (controller.questions.isEmpty) {
      return element.copyWith(
        pageIndex: 0,
        dx: ExamCanvasGeometry.defaultElementDx,
        dy: ExamCanvasGeometry.defaultElementDy,
      );
    }
    final questionIndex = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex ?? controller.currentQuestionIndex;
    final pageIndex = _planPageOfQuestion(controller.questions[questionIndex].id) ?? 0;
    final top = _blockTopOnPage(questionIndex);
    return element.copyWith(
      pageIndex: pageIndex,
      dx: 8,
      dy: (top ?? ExamCanvasGeometry.defaultElementDy) + 8,
    );
  }

  /// إحداثيات العنصر **المطلقة على ورقته**: العنصر المرتبط بسؤال يُزاح
  /// بمستطيل سؤاله (والسؤال قد ينتقل بين الصفحات)، والعنصر الحر كما هو.
  ({int pageIndex, double dx, double dy}) _elementGeometry(
    ExamWizardController controller,
    FloatingElement element,
  ) {
    final owner = element.ownerQuestionId;
    if (owner == null) {
      return (pageIndex: element.pageIndex, dx: element.dx, dy: element.dy);
    }
    // الحساب نفسه في مكان واحد (المتحكم): لا تُشتق صفحة العنصر وموضعه هنا مرة
    // ثانية، وإلا اختلفت مع الحصر عند أول تعديل.
    final rect = controller.questionRect(owner);
    if (rect == null) {
      return (pageIndex: element.pageIndex, dx: element.dx, dy: element.dy);
    }
    return (
      pageIndex: rect.pageIndex,
      dx: rect.left + element.dx,
      dy: rect.top + element.dy,
    );
  }

  /// أعلى كتلة السؤال [questionIndex] داخل صفحتها (إحداثي ورقة مطلق)، أو
  /// `null` إن لم تُقسَّم الورقة بعد.
  double? _blockTopOnPage(int questionIndex) {
    final controller = _controller;
    final questions = controller?.questions;
    if (controller == null || questions == null || questions.isEmpty) {
      return null;
    }
    final index = questionIndex < 0 || questionIndex >= questions.length
        ? questions.length - 1
        : questionIndex;
    return _planBlockTopPx(questions[index].id);
  }

  /// يفتح محرّر المعادلات ثم يُنتج معادلة **حرة** تُحدّد موضعها بنفسك.
  ///
  /// بعد الإكمال في المحرّر تصبح المعادلة بطاقةً جاهزة (في شريط الصيغ):
  /// تُسحب إلى أي نقطة على الورقة فتُقام هناك، أو تنقر مكانها على الورقة
  /// فتستقر تحته — بلا التزام بحقل نصي ولا بسؤال معيّن. (من أراد معادلة
  /// سطرية وسط الجملة فبإمكانه تحرير الصيغ داخل الحقول عبر «تحرير معادلة».)
  Future<void> _openEquationEditor({
    String? template,
    bool preferBlock = false,
    bool editExisting = false,
  }) async {
    // «تحرير معادلة»: صيغة موجودة داخل حقل نصي تُحرَّر في مكانها (لمن أراد
    // معادلة سطرية وسط الجملة). أمّا مكتبة الصيغ و«محرر المعادلات» فتُنتج
    // معادلة **حرة** تُسحب إلى أي موضع.
    if (editExisting) {
      final active = _inserter.controller;
      if (active == null) {
        _showMessage('انقر داخل حقل نصي أولاً لتحرير معادلته.');
        return;
      }
      await _editEquationInFieldController(
        active,
        template: template,
        preferBlock: preferBlock,
        editExisting: true,
      );
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: template ?? _stagedFormula,
      initialIsBlock: preferBlock || _stagedFormulaIsBlock,
    );
    if (snippet == null || !mounted) {
      return;
    }
    final latex = _formulaBodyOf(snippet);
    if (latex.trim().isEmpty) {
      return;
    }
    setState(() {
      _stagedFormula = latex;
      _stagedFormulaIsBlock = snippet.startsWith(r'$$');
    });
    _showMessage('اختر موضع المعادلة: اضغط على الورقة — أو اسحبها من الشريط إلى مكانها.');
  }

  /// يستخرج جسم الصيغة ([FloatingElement.label]) من مقطع المحرّر.
  static String _formulaBodyOf(String snippet) {
    var body = snippet.trim();
    if (body.startsWith(r'$$') && body.endsWith(r'$$') && body.length >= 4) {
      body = body.substring(2, body.length - 2);
    } else if (body.startsWith(r'$') && body.endsWith(r'$') && body.length >= 2) {
      body = body.substring(1, body.length - 1);
    }
    return body.trim();
  }

  /// يوضع المرشح عند [tapPosition] داخل صفحة A4 محددة، كنقطة حرة مستقلة
  /// عن السؤال أو الفرع. نقطة النقر تصبح مركز المعادلة.
  void _placeStagedFormula(
    Offset tapPosition, {
    required int pageIndex,
  }) {
    final latex = _stagedFormula;
    if (latex == null) {
      return;
    }
    const elementWidth = 170.0;
    const elementHeight = 80.0;
    final board = _boardPositionFromLocal(
      tapPosition,
      width: elementWidth,
      height: elementHeight,
    );
    final element = FloatingElement(
      type: FloatingElementType.formula,
      label: latex,
      dx: board.dx,
      dy: board.dy,
      pageIndex: pageIndex,
      width: elementWidth,
      height: elementHeight,
    );
    // مع سؤال محدد: المعادلة تصير جزءاً من السؤال وتُحصر داخل حدوده؛
    // وبلا تحديد تبقى عنصراً حراً في أي نقطة من الورقة.
    final owner = _selectedOwnerQuestionId();
    final added = _controller!.addFloatingElement(
      element,
      pageIndex: pageIndex,
      ownerQuestionId: owner,
    );
    if (!added) {
      _showMessage('تعذر إدراج المعادلة. حاول اختيار موضع آخر على الورقة.');
      return;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(element.id);
    });
    _showMessage(
      owner == null
          ? 'أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.'
          : 'أُدرجت المعادلة داخل السؤال المحدد — حركتها محصورة فيه.',
    );
  }

  /// يضيف عنصراً إلى الورقة: إن كان سؤال محدداً ارتبط به ووُضع داخله، وإلا
  /// صار عنصراً حراً على صفحة السؤال النشط.
  void _addAttachmentToSelection(FloatingElement element) {
    element = _withDefaultPosition(element);
    final controller = _controller!;
    final added = controller.addFloatingElement(
      element,
      pageIndex: element.pageIndex,
      ownerQuestionId: element.ownerQuestionId,
    );
    if (added) {
      setState(() => _selectedAttachment = _AttachmentRef.global(element.id));
      if (element.ownerQuestionId != null) {
        _showMessage('أُضيف العنصر داخل السؤال المحدد — حرّكته محصورة فيه.');
      }
      return;
    }
    _showMessage('تعذر إضافة العنصر إلى الورقة.');
  }

  void _addImageToSelection(List<int> bytes) {
    _addAttachmentToSelection(
      FloatingElement(
        type: FloatingElementType.image,
        bytes: Uint8List.fromList(bytes),
        dx: 0,
        dy: 0,
        width: ExamCanvasGeometry.defaultElementSize,
        height: ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  Future<void> _pickImageToSelection() async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage('تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.', isError: true),
    );
    if (!mounted) return;
    if (bytes != null) {
      _addImageToSelection(bytes);
    }
  }

  void _addShapeToSelection(FloatingShapeType shape) {
    _addAttachmentToSelection(
      FloatingElement(
        type: FloatingElementType.shape,
        shape: shape,
        dx: 0,
        dy: 0,
        width: shape == FloatingShapeType.line || shape == FloatingShapeType.divider
            ? ExamCanvasGeometry.defaultElementSize * 2
            : ExamCanvasGeometry.defaultElementSize,
        height: shape == FloatingShapeType.line || shape == FloatingShapeType.divider
            ? 24
            : ExamCanvasGeometry.defaultElementSize,
      ),
    );
  }

  void _addTextBox() {
    final element = _newTextBoxElement();
    _addAttachmentToSelection(element);
    _editNewTextBox(element.id);
  }

  /// مربع نص افتراضي (180×90 بكسل لوحة) عند موضع العنصر الافتراضي في الصفحة.
  static FloatingElement _newTextBoxElement() => FloatingElement(
        type: FloatingElementType.shape,
        shape: FloatingShapeType.textBox,
        dx: 0,
        dy: 0,
        width: 180,
        height: 90,
      );

  /// يفتح محرّر نص المربع المضاف للتوّ ثم يذكّر بأن السحب المباشر يحرّكه.
  ///
  /// يُشترط أن يكون المربع [elementId] هو **المحدد حالياً** للتأكد من
  /// نجاح إضافته قبل فتح المحرر.
  void _editNewTextBox(String elementId) {
    if (_selectedAttachment?.elementId != elementId) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final ref = _selectedAttachment;
      if (!mounted || ref == null || ref.elementId != elementId) {
        return;
      }
      await _editTextBox(ref);
      if (mounted) {
        _showMessage('اسحب مربع النص مباشرةً لتحريكه في أي موضع داخل الورقة.');
      }
    });
  }

  void _addDividerToSelection() {
    final controller = _controller!;
    final document = controller.document;
    final branches = _selectedBranches.where(document.containsRef).toList();
    if (branches.length == 1) {
      controller.setBranchDivider(branches.single, const PaperDivider());
      _showMessage('تمت إضافة فاصل بعد الفرع.');
      return;
    }
    final single = controller.selectedBranch;
    if (single != null && _selectedQuestions.isEmpty && _selectedBranches.isEmpty) {
      controller.setBranchDivider(single, const PaperDivider());
      _showMessage('تمت إضافة فاصل بعد الفرع.');
      return;
    }
    var questionTarget = controller.selectedQuestionIndex;
    if (questionTarget == null && _selectedQuestions.length == 1) {
      questionTarget = document.indexOfQuestion(_selectedQuestions.single);
      if (questionTarget == -1) {
        questionTarget = null;
      }
    }
    questionTarget ??= controller.currentQuestionIndex;
    controller.setQuestionDivider(questionTarget, const PaperDivider());
    _showMessage('تمت إضافة فاصل بعد السؤال.');
  }

  void _updateAttachmentElement(
    _AttachmentRef ref,
    FloatingElement element, {
    bool preservePageIndex = false,
  }) {
    final controller = _controller!;
    if (ref.isGlobal || controller.document.floatingElementById(element.id) != null) {
      controller.updateFloatingElement(element);
      return;
    }
    // رفع المرفق المحفوظ بصيغة قديمة عند أول تعديل، مع إبقائه على صفحة
    // سؤاله الحالية ما لم يغيّر المستخدم الصفحة أثناء السحب.
    final ownerPage = _planPageOfQuestion(
          controller.questions[ref.questionIndex].id,
        ) ??
        element.pageIndex;
    final placed = element.copyWith(
      pageIndex: preservePageIndex || element.pageIndex != 0 ? element.pageIndex : ownerPage,
    );
    if (ref.branchIndex == null) {
      controller.updateQuestionAttachment(
        ref.questionIndex,
        placed,
        pageIndex: placed.pageIndex,
      );
    } else {
      controller.updateAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        placed,
        pageIndex: placed.pageIndex,
      );
    }
  }

  /// يربط العنصر بالسؤال المحدد أو يفصل ارتباطه عنه.
  void _toggleElementOwner(_AttachmentRef ref, FloatingElement element) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (element.isQuestionOwned) {
      controller.setElementOwner(element.id, null);
      _showMessage('فُصل العنصر عن السؤال — صار حراً في أي موضع على الورقة.');
      return;
    }
    final owner = _selectedOwnerQuestionId();
    if (owner == null) {
      _showMessage('حدد سؤالاً أولاً (بنقرة عليه) ثم اربط العنصر به.');
      return;
    }
    controller.setElementOwner(element.id, owner);
    _showMessage('رُبط العنصر بالسؤال — حركته محصورة داخل حدوده.');
  }

  void _removeAttachmentElement(_AttachmentRef ref) {
    final controller = _controller!;
    if (ref.isGlobal || controller.document.floatingElementById(ref.elementId) != null) {
      controller.removeFloatingElement(ref.elementId);
    } else if (ref.branchIndex == null) {
      controller.removeQuestionAttachment(ref.questionIndex, ref.elementId);
    } else {
      controller.removeAttachment(
        BranchRef(questionIndex: ref.questionIndex, branchIndex: ref.branchIndex!),
        ref.elementId,
      );
    }
    setState(() => _selectedAttachment = null);
  }

  /// يفتح محرّر المعادلات المرئي لمعادلة قائمة على الورقة ويحفظ نتيجتها.
  ///
  /// التعديل لا يمسّ الموضع: يبقى العنصر حيث وضعه المستخدم تماماً.
  Future<void> _editFormulaElement(_AttachmentRef ref) async {
    final document = _controller!.document;
    final element = _findAttachment(document, ref);
    if (element == null) {
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: element.label,
      saveLabel: 'حفظ',
    );
    if (snippet == null || !mounted) {
      return;
    }
    final latex = _formulaBodyOf(snippet);
    if (latex.isEmpty) {
      return;
    }
    _updateAttachmentElement(ref, element.copyWith(label: latex));
  }

  Future<void> _editTextBox(_AttachmentRef ref) async {
    final document = _controller!.document;
    final element = _findAttachment(document, ref);
    if (element == null) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'مربع نص',
      initialText: element.label,
      hintText: 'اكتب النص هنا... (ملاحظة، تمنيات...)',
      maxLines: 4,
    );
    if (saved == null) {
      return;
    }
    _updateAttachmentElement(ref, element.copyWith(label: saved));
  }

  /// يعرض حوار [_TextInputDialog] المشترك ويعيد النص المحفوظ
  /// (أو null عند الإلغاء) — الـ controller مملوك للحوار نفسه.
  Future<String?> _showTextInputDialog({
    required String title,
    required String initialText,
    String? hintText,
    String? helperText,
    String saveLabel = 'حفظ',
    bool numeric = false,
    int? maxLines,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: title,
        initialText: initialText,
        hintText: hintText,
        helperText: helperText,
        saveLabel: saveLabel,
        numeric: numeric,
        maxLines: maxLines,
      ),
    );
  }

  /// رقم السؤال: ما يكتبه المدرس يُطبع حرفياً («س١/»، «السؤال الاول/»)،
  /// والفارغ = ترقيم تلقائي من نمط التسمية العام.
  Future<void> _editQuestionLabel(int questionIndex) async {
    final controller = _controller!;
    final document = controller.document;
    final question = document.questions[questionIndex];
    final saved = await _showTextInputDialog(
      title: 'رقم السؤال',
      initialText: question.numberOverride ?? '',
      hintText: 'مثال: س١/ أو السؤال الاول/ — تلقائي: '
          '${document.autoQuestionLabel(question)}${document.layout.questionSeparator}',
      helperText: 'يُطبع كما تكتبه تماماً. اتركه فارغاً للعودة للترقيم التلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateQuestionNumberOverride(questionIndex, saved);
  }

  /// درجة السؤال: يكتب المدرس الرقم الخام فقط («20») فيطبعه النظام
  /// «(٢٠ درجة)»؛ والفارغ = مجموع درجات الفروع والنقاط تلقائياً.
  Future<void> _editQuestionMarks(int questionIndex) async {
    final controller = _controller!;
    final document = controller.document;
    final question = document.questions[questionIndex];
    final saved = await _showTextInputDialog(
      title: 'درجة السؤال',
      initialText: _formatMarksInput(question.marksOverride ?? 0),
      hintText: 'اكتب الرقم فقط، مثال: 20',
      helperText: 'تُطبع تلقائياً بصيغة (${document.formatNumber(20)} ${document.layout.marksUnit}). '
          'فارغ = مجموع درجات الفروع تلقائياً.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    if (saved.trim().isEmpty) {
      controller.updateQuestionMarksOverride(questionIndex, null);
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 20).', isError: true);
      return;
    }
    controller.updateQuestionMarksOverride(questionIndex, marks);
  }

  /// رقم الفرع («أ»...) — يُضاف القوس تلقائياً؛ فارغ = تلقائي من الفهرس.
  Future<void> _editBranchLabel(BranchRef ref) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final branch = document.branchAt(ref);
    final saved = await _showTextInputDialog(
      title: 'رقم الفرع',
      initialText: branch.labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoBranchLabel(ref.branchIndex)}',
      helperText: 'مثال: أ — يُضاف القوس تلقائياً. فارغ = تلقائي.',
    );
    if (saved == null) {
      return;
    }
    controller.updateBranchLabelOverride(ref, saved);
  }

  /// درجة الفرع: الرقم الخام فقط، ويطبعه النظام «(٥ درجة)».
  Future<void> _editBranchMarks(BranchRef ref) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsRef(ref)) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'درجة الفرع',
      initialText: _formatMarksInput(document.branchAt(ref).marks),
      hintText: 'اكتب الرقم فقط، مثال: 5',
      helperText: 'تُطبع تلقائياً بصيغة (${document.formatNumber(5)} ${document.layout.marksUnit}).',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 5).', isError: true);
      return;
    }
    controller.updateBranchMarks(ref, marks);
  }

  void _addBranchToSelected() {
    final controller = _controller!;
    final target = controller.selectedBranch?.questionIndex ??
        controller.selectedQuestionIndex ?? controller.currentQuestionIndex;
    controller.addBranch(target);
  }

  /// مزود المكتبة إن وُجد فوق الشاشة (قد تُفتح الشاشة مستقلة في الاختبارات).
  ExamDocumentProvider? _libraryProvider() {
    try {
      return context.read<ExamDocumentProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final provider = _libraryProvider();
    if (provider == null) {
      _showMessage('الحفظ غير متاح في هذا السياق.', isError: true);
      return;
    }
    setState(() => _isBusy = true);
    try {
      await provider.saveDocument(_controller!.document.touched());
      if (mounted) {
        _showMessage('تم حفظ الورقة.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر حفظ الورقة. حاول مرة أخرى.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// يصدّر الـPDF من **التخطيط نفسه** المعروض، ولا يمرّر توزيع صفحات منفصلاً:
  /// تمرير توزيع بجانب التخطيط كان يترك باباً لقرار تقسيم ثانٍ في المسار.
  Future<void> _exportPdf({LayoutDocument? layoutDocument}) async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    final document = controller.document;
    setState(() => _isBusy = true);
    try {
      if (
          layoutDocument != null &&
          !identical(layoutDocument.source, controller.documentIr)) {
        throw const ExportException(
          'تغيّر المستند بعد حساب صفحات المراجعة. افتح المراجعة مجدداً.',
        );
      }
      final bytes = await PdfExportService.buildDocumentPdfBytes(
              document: document,
              // التخطيط المعروض نفسه يُرسم، فلا يُعاد حساب هندسة في PDF.
              layoutDocument: layoutDocument ?? _pagePlan?.layout,
            );
      if (!mounted) {
        return;
      }
      await _saveToLibrary();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            title: 'معاينة ورقة الأسئلة',
            fileName: '${controller.document.name}_ورقة_الامتحان.pdf',
          ),
        ),
      );
    } catch (error, stackTrace) {
      ExportFileService.logError('Wizard PDF export failed', error, stackTrace);
      if (mounted) {
        _showMessage(
          error is ExportException
              ? error.message
              : 'تعذر إنشاء ملف الـ PDF. حاول مرة أخرى.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// كل ورقة تصل للتصدير تُحفظ في مكتبة الأوراق تلقائياً.
  Future<void> _saveToLibrary() async {
    final provider = _libraryProvider();
    if (provider == null) {
      return;
    }
    try {
      await provider.saveDocument(_controller!.document.touched());
    } catch (_) {
      // فشل الحفظ الصامت لا يمنع إتمام التصدير؛ يُبلغ المستخدم برسالة.
      if (mounted) {
        _showMessage('تم التصدير، لكن تعذّر حفظ الورقة في المكتبة.', isError: true);
      }
    }
  }

  /// حوار إدخال حجم خط حر (6..32) للتحديد الحالي.
  Future<void> _showCustomFontSize() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق الحجم.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'حجم خط مخصص',
      initialText: _activeStyle().fontSize?.toStringAsFixed(0) ?? '',
      hintText: 'مثال: 13 (بين 6 و 32)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final size = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (size == null || !size.isFinite || size < 6 || size > 32) {
      _showMessage('أدخل حجماً بين 6 و 32.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(fontSize: () => size));
  }

  /// تباعد أسطر مخصص (حوار حر) — يطبق على التحديد الحالي.
  Future<void> _showCustomLineHeight() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق التباعد.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'تباعد أسطر مخصص',
      initialText: _activeStyle().lineHeight?.toString() ?? '',
      hintText: 'مثال: 1.3 (بين 0.5 و 4.0)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    final value = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value < 0.5 || value > 4.0) {
      _showMessage('أدخل تباعداً بين 0.5 و 4.0.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(lineHeight: () => value));
  }

  /// مسافة مخصصة بين الفقرات (بكسل منطقي)، مستقلة عن تباعد السطر.
  Future<void> _showCustomParagraphSpacing() async {
    final targets = _styleTargets();
    if (targets.branches.isEmpty && targets.questions.isEmpty) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق المسافة.');
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'المسافة بين الفقرات',
      initialText: _activeStyle().paragraphSpacing?.toString() ?? '',
      hintText: 'مثال: 4 (بين 0 و 40 بكسل)',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) return;
    final value = double.tryParse(
      saved.trim().replaceAll('،', '.').replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value < 0 || value > 40) {
      _showMessage('أدخل مسافة بين 0 و 40 بكسل.', isError: true);
      return;
    }
    _applyStyle((current) => current.copyWith(paragraphSpacing: () => value));
  }

  /// لون نص مخصص HEX (حوار حر) — يطبق على التحديد الحالي.
  Future<void> _showCustomColor() async {
    final targets = _styleTargets();
    final hasTarget = targets.branches.isNotEmpty ||
        targets.questions.isNotEmpty ||
        targets.header ||
        targets.boxes.isNotEmpty;
    if (!hasTarget) {
      _showMessage('حدد سؤالاً أو فرعاً أولاً لتطبيق اللون.');
      return;
    }
    final activeColor = _activeColor();
    final initialColor = activeColor == null
        ? ''
        : (activeColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final saved = await _showTextInputDialog(
      title: _colorTooltip() == 'لون عنوان السؤال'
          ? 'لون عنوان السؤال المخصص'
          : 'لون نص مخصص',
      initialText: initialColor,
      hintText: 'مثال: 1E3A8A أو #B91C1C',
      saveLabel: 'تطبيق',
    );
    if (saved == null) {
      return;
    }
    var hex = saved.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null || (hex.length != 6 && hex.length != 8)) {
      _showMessage('أدخل لون HEX صحيحاً (6 خانات مثل 1E3A8A).', isError: true);
      return;
    }
    final argb = hex.length == 6 ? 0xFF000000 | parsed : parsed;
    _applyColor(argb);
  }

  /// ترقيم النقطة (سؤال أو فرع): مخصص حرفي، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editPointLabel(PointsOwner owner, String pointId) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final points = document.pointsOf(owner);
    final index = points.indexWhere((point) => point.id == pointId);
    if (index < 0) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'ترقيم النقطة',
      initialText: points[index].labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoItemLabel(index)}',
      helperText: 'مثال: أ-، 1) — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updatePointLabel(owner, pointId, saved);
  }

  /// درجة النقطة: الرقم الخام فقط («2») فيطبعه النظام «(٢ درجة)».
  ///
  /// الفارغ يعيد الدرجة صفراً (بلا درجة معلنة)، والإعداد «إظهار درجات
  /// الأسئلة» وحده يقرر ظهورها على الورقة.
  Future<void> _editPointMarks(PointsOwner owner, String pointId) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final points = document.pointsOf(owner);
    final index = points.indexWhere((point) => point.id == pointId);
    if (index < 0) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'درجة النقطة',
      initialText: _formatMarksInput(points[index].marks),
      hintText: 'اكتب الرقم فقط، مثال: 2',
      helperText:
          'تُطبع بصيغة (${document.formatNumber(2)} ${document.layout.marksUnit}). '
          'فارغ = بلا درجة.',
      saveLabel: 'تطبيق',
      numeric: true,
    );
    if (saved == null) {
      return;
    }
    if (saved.trim().isEmpty) {
      controller.updatePointMarks(owner, pointId, 0);
      return;
    }
    final marks = _parseMarks(saved);
    if (marks == null) {
      _showMessage('أدخل الدرجة رقماً صحيحاً فقط (مثال: 2).', isError: true);
      return;
    }
    controller.updatePointMarks(owner, pointId, marks);
  }

  /// تسمية الخيار: مخصصة حرفياً، فارغ = تلقائي، `-` = إخفاء.
  Future<void> _editOptionLabel(PointsOwner owner, String pointId, int index) async {
    final controller = _controller!;
    final document = controller.document;
    if (!document.containsOwner(owner)) {
      return;
    }
    final options = document.pointsOf(owner)
        .where((point) => point.id == pointId)
        .expand((point) => point.options)
        .toList(growable: false);
    if (index < 0 || index >= options.length) {
      return;
    }
    final saved = await _showTextInputDialog(
      title: 'تسمية الخيار',
      initialText: options[index].labelOverride ?? '',
      hintText: 'تلقائي: ${document.autoOptionLabel(index)}',
      helperText: 'مثال: ( أ )، A. — فارغ = تلقائي، - = إخفاء.',
    );
    if (saved == null) {
      return;
    }
    controller.updatePointOptionLabel(owner, pointId, index, saved);
  }

  /// يفتح محرر المعادلات المرئي للحقل النشط (مسار شريط الصيغ).
  ///
  /// - [template] صيغة جاهزة تُحمَّل في المحرر (أو null لمعادلة فارغة).
  /// - [preferBlock] يقترح النمط المنفرد `$$...$$`.
  /// - [editExisting] يحرّر صيغة موجودة في الحقل بدل إدراج جديدة.
  /// يحرّر صيغ الحقل [fieldKey] (زر الفرع/المعاينة الغنية) أو يدرج جديدة.
  Future<void> _editEquationInField(String fieldKey) async {
    final field = _fields[fieldKey];
    if (field == null) {
      return;
    }
    _inserter.controller = field;
    await _editEquationInFieldController(field, editExisting: true);
  }

  Future<void> _editEquationInFieldController(
    TextEditingController active, {
    String? template,
    bool preferBlock = false,
    bool editExisting = false,
  }) async {
    TexMathSpan? editingSpan;
    var initialLatex = template;
    var initialIsBlock = preferBlock;
    if (template == null && editExisting) {
      final spans = TexContent.findSpans(active.text);
      if (spans.length == 1) {
        editingSpan = spans.single;
      } else if (spans.length > 1) {
        final offset = active.selection.isValid ? active.selection.start : -1;
        final atCursor = spans
            .where((span) => offset >= span.start && offset <= span.end)
            .toList(growable: false);
        if (atCursor.isNotEmpty) {
          editingSpan = atCursor.first;
        } else {
          editingSpan = await showEquationSpanPicker(
            context: context,
            spans: spans,
          );
          if (editingSpan == null) {
            return;
          }
        }
      }
      if (editingSpan != null) {
        initialLatex = editingSpan.latex;
        initialIsBlock = editingSpan.isBlock;
      }
    }
    if (!mounted) {
      return;
    }
    final snippet = await showVisualEquationEditor(
      context: context,
      initialLatex: initialLatex,
      initialIsBlock: initialIsBlock,
      saveLabel: editingSpan == null ? 'إدراج' : 'حفظ',
    );
    if (snippet == null || !mounted) {
      return;
    }
    if (editingSpan != null) {
      // يستبدل الصيغة في موضعها الأصلي تماماً (بفهارس findSpans).
      active.text =
          active.text.replaceRange(editingSpan.start, editingSpan.end, snippet);
      active.selection =
          TextSelection.collapsed(offset: editingSpan.start + snippet.length);
    } else {
      _inserter.controller = active;
      _inserter.insert(snippet);
    }
  }

  /// يُلغي المعادلة المرشّحة (إن أراد المستخدم التراجع قبل إقامتها).
  void _clearStagedFormula() {
    if (_stagedFormula == null) {
      return;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
    });
    _showMessage('أُلغي إدراج المعادلة.');
  }

  /// نهاية سحب بطاقة المعادلة من الشريط: يُسقطها [DragTarget] على الورقة.
  ///
  /// إن لم تُسقط على الورقة (سحب ملغى) تبقى مرشّحة كي ينقر المستخدم موضعها
  /// بنفسه، فنرشده إلى ذلك.
  void _handleFormulaDragEnd(DraggableDetails details) {
    if (_stagedFormula == null) {
      return;
    }
    _showMessage('لم يُسقط العنصر على الورقة: انقر داخل الورقة لتحديد موضع المعادلة.');
  }

  Future<void> _showReview() async {
    if (_isBusy) {
      return;
    }
    final controller = _controller!;
    final document = controller.document;
    var pageAssignments = <List<String>>[];
    LayoutDocument? canonicalReviewLayout;
    setState(() => _isBusy = true);
    try {
      // نفس كائن التخطيط المعروض على الشاشة: لا هندسة موازية للمراجعة/التصدير.
      final livePlan = _pagePlan;
      canonicalReviewLayout = livePlan?.layout ??
          (identical(_planController.plan?.layout.source, controller.documentIr)
              ? _planController.plan?.layout
              : null);
      canonicalReviewLayout ??= await CanonicalLayoutService.resolve(
        document: document,
        sourceIr: controller.documentIr,
      );
      if (!mounted ||
          !identical(_controller, controller) ||
          !identical(controller.document, document) ||
          !identical(canonicalReviewLayout.source, controller.documentIr)) {
        return;
      }
      pageAssignments = canonicalReviewLayout.questionPageAssignments;
    } catch (error, stackTrace) {
      ExportFileService.logError('Preview pagination failed', error, stackTrace);
      if (mounted) {
        _showMessage('تعذر حساب توزيع صفحات التصدير.');
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
    if (!mounted) {
      return;
    }
    final globalElementIds =
        document.floatingElements.map((element) => element.id).toSet();
    final exportableQuestions = document.questions
        .where((question) => question.hasExportableContent(
              ignoredAttachmentIds: globalElementIds,
            ))
        .toList(growable: false);
    final exportableBranchCount = exportableQuestions
        .expand((question) => question.branches)
        .where((branch) => branch.hasExportableContentIn(
              ignoredAttachmentIds: globalElementIds,
            ))
        .length;
    final exportableMarks = exportableQuestions.fold<double>(
      0,
      (sum, question) => sum + question.marks,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('مراجعة الورقة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _reviewRow(
                'عدد الأسئلة',
                document.formatNumber(exportableQuestions.length),
              ),
              _reviewRow('عدد الفروع', document.formatNumber(exportableBranchCount)),
              _reviewRow(
                'عدد الصفحات',
                document.formatNumber(pageAssignments.length),
              ),
              _reviewRow(
                'الدرجة الكلية',
                '${document.formatNumber(exportableMarks)} ${document.layout.marksUnit}',
              ),
              _reviewRow('حجم الورق', 'A4'),
              _reviewRow('الخط الافتراضي', document.settings.defaultFont.arabicLabel),
              _reviewRow('نمط التسمية', document.settings.questionLabelStyle.arabicLabel),
              _reviewRow(
                'الهوامش',
                '${document.settings.marginMm.toStringAsFixed(0)} مم',
              ),
              _reviewRow(
                'تباعد الأسطر',
                document.settings.lineSpacing.toStringAsFixed(2),
              ),
              _reviewRow(
                'صفحات المعاينة',
                document.formatNumber(canonicalReviewLayout?.pageCount ?? 0),
              ),
              const Divider(height: 20),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('رجوع'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportPdf(layoutDocument: canonicalReviewLayout);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('تصدير PDF'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSlider({
    required String label,
    required String value,
    required double sliderValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: sliderValue,
          min: min,
          max: max,
          divisions: divisions,
          label: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _showSettings() async {
    final controller = _controller!;
    final originalSettings = controller.document.settings;
    var settings = originalSettings;
    // ملفات الإطار المختارة داخل هذا الحوار: تُحذف المتروكة منها عند الإلغاء أو
    // الاستبدال حتى لا تتراكم ملفات يتيمة.
    final sessionFramePaths = <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('إعدادات الورقة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SwitchListTile(
                  dense: true,
                  title: const Text('ترقيم تلقائي للأسئلة', style: TextStyle(fontSize: 13)),
                  value: settings.autoNumberQuestions,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(autoNumberQuestions: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('ترميز تلقائي للفروع (أ، ب...)', style: TextStyle(fontSize: 13)),
                  value: settings.autoLetterBranches,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(autoLetterBranches: value),
                  ),
                ),
                DropdownButtonFormField<PaperNumerals>(
                  value: settings.numerals,
                  decoration: const InputDecoration(
                    labelText: 'نسق الأرقام',
                    hintText: 'اختر شكل الأرقام المطبوعة (١٢٣ أو 123)',
                    helperText: 'يسري على الأسئلة والفروع والنقاط والتواريخ في الورقة.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PaperNumerals.values
                      .map((n) => DropdownMenuItem<PaperNumerals>(
                            value: n,
                            child: Text(n.arabicLabel, style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => settings = settings.copyWith(numerals: value));
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<QuestionLabelStyle>(
                  value: settings.questionLabelStyle,
                  decoration: const InputDecoration(
                    labelText: 'نمط تسمية الأسئلة',
                    hintText: 'اختر «رسمي (السؤال الأول)» أو «مختصر (س1)»',
                    helperText: 'ما تكتبه يدوياً في رقم أي سؤال يتقدم على النمط دائماً.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: QuestionLabelStyle.values
                      .map((style) => DropdownMenuItem<QuestionLabelStyle>(
                            value: style,
                            child: Text(
                              style.arabicLabel,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(
                        () => settings = settings.copyWith(questionLabelStyle: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PaperFont>(
                  value: settings.defaultFont,
                  decoration: const InputDecoration(
                    labelText: 'الخط الافتراضي للورقة',
                    hintText: 'اختر خط متن الورقة الافتراضي',
                    helperText: 'يسري على كل نص لم تخصّص له خطاً من شريط التنسيق.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PaperFont.values
                      .map((font) => DropdownMenuItem<PaperFont>(
                            value: font,
                            child: Text(
                              font.arabicLabel,
                              style: TextStyle(fontSize: 13, fontFamily: font.family),
                            ),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => settings = settings.copyWith(defaultFont: value));
                    }
                  },
                ),
                _settingsSlider(
                  label: 'هوامش الصفحة',
                  value: '${settings.marginMm.toStringAsFixed(0)} مم',
                  sliderValue: settings.marginMm,
                  min: PaperSettings.minMarginMm,
                  max: PaperSettings.maxMarginMm,
                  divisions: 17,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(marginMm: value),
                  ),
                ),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'الهامش هو حشوة الإطار: يبتعد النص بقدره عن حافة الورقة فلا يتداخل مع الإطار.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                _settingsSlider(
                  label: 'حجم الخط الأساسي',
                  value: settings.baseFontSize.toStringAsFixed(1),
                  sliderValue: settings.baseFontSize,
                  min: 8,
                  max: 16,
                  divisions: 16,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(baseFontSize: value),
                  ),
                ),
                _settingsSlider(
                  label: 'تباعد الأسطر العام',
                  value: settings.lineSpacing.toStringAsFixed(2),
                  sliderValue: settings.lineSpacing,
                  min: 1,
                  max: 2.5,
                  divisions: 15,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(lineSpacing: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إظهار درجات الأسئلة', style: TextStyle(fontSize: 13)),
                  value: settings.showQuestionMarks,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(showQuestionMarks: value),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إطار حول الصفحة', style: TextStyle(fontSize: 13)),
                  value: settings.pageBorder,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(pageBorder: value),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text(
                    'صورة إطار الصفحة (PNG شفاف)',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    settings.hasFrameImage
                        ? 'صورة مختارة: تُرسم خلف النص بحجم الورقة كاملة'
                        : 'اختر صورة PNG شفافة بحجم A4 (اختياري) — يبتعد النص عنها بقدر الهوامش',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextButton(
                        onPressed: () async {
                          final path = await _pickFrameImage();
                          if (path != null) {
                            sessionFramePaths.add(path);
                            setDialogState(
                              () => settings = settings.copyWith(
                                frameImagePath: () => path,
                                pageBorder: true,
                              ),
                            );
                          }
                        },
                        child: Text(settings.hasFrameImage ? 'تغيير' : 'اختيار'),
                      ),
                      if (settings.hasFrameImage)
                        IconButton(
                          tooltip: 'إزالة صورة الإطار',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => setDialogState(
                            () => settings = settings.copyWith(frameImagePath: () => null),
                          ),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('إطار حول الترويسة', style: TextStyle(fontSize: 13)),
                  value: settings.headerBorder,
                  onChanged: (value) => setDialogState(
                    () => settings = settings.copyWith(headerBorder: value),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                for (final path in sessionFramePaths) {
                  unawaited(PageFrameStore.delete(path));
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                controller.updateSettings(settings);
                final kept = settings.frameImagePath;
                for (final path in <String?>[
                  originalSettings.frameImagePath,
                  ...sessionFramePaths,
                ]) {
                  if (path != null && path != kept) {
                    unawaited(PageFrameStore.delete(path));
                  }
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  /// يختار صورة إطار PNG من المعرض ويحفظها في مساحة التطبيق (يعيد مسارها).
  Future<String?> _pickFrameImage() async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage(
        'تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.',
        isError: true,
      ),
    );
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      return await PageFrameStore.save(bytes);
    } catch (error, stackTrace) {
      ExportFileService.logError('Page frame save failed', error, stackTrace);
      _showMessage('تعذر حفظ صورة الإطار على الجهاز.', isError: true);
      return null;
    }
  }

  // ------------------------------------------------------------------
  // التكبير والعرض
  // ------------------------------------------------------------------

  void _zoomBy(double factor) {
    setState(() => _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom));
  }

  void _fitToScreen() {
    if (_viewportWidth <= 0) {
      return;
    }
    setState(
      () => _zoom = ((_viewportWidth - 24) / ExamCanvasGeometry.width)
          .clamp(_minZoom, 1.5),
    );
  }

  /// يوسّط الورقة مع الحفاظ على الزوم الحالي (لا يعيد الملاءمة).
  void _centerPaper() {
    if (_vScroll.hasClients) {
      _vScroll.jumpTo(0);
    }
    if (_hScroll.hasClients && _hScroll.position.maxScrollExtent > 0) {
      _hScroll.jumpTo(_hScroll.position.maxScrollExtent / 2);
    }
  }

  void _maybeAutoFit() {
    if (_didAutoFit || _viewportWidth <= 0) {
      return;
    }
    _didAutoFit = true;
    if (_viewportWidth < ExamCanvasGeometry.width + 24) {
      _fitToScreen();
    }
  }

  // ------------------------------------------------------------------
  // البناء
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamWizardController>();
    final document = controller.document;
    final layout = controller.layout;
    // الوصلة تُقرأ من الودجت الحالي في كل بناء: الحالة قد تبقى حيّة بعد
    // استبدال الودجت (مستند/وصلات أخرى)، فالتقاطها مرة واحدة يحسم المستند
    // الجديد بوصلة القديم.
    _planController.resolver = widget.canonicalLayoutResolver;
    // الخطة هي مصدر الصفحات: تُطلب للمستند الحالي وتُعرض كما هي (حتى لو كانت
    // نسخة اللحظة السابقة أثناء الحسم) كي لا تفقد الحقول التركيز مع كل حرف.
    _planController.request(document, controller.documentIr);
    // المتحكم يحصر العناصر المرتبطة بالسؤال داخل مستطيله: يقرأ الخطة نفسها.
    controller.applyLayoutPlan(_pagePlan);
    final pagePlan = _planController.plan;
    if (pagePlan != null) {
      _trimPageKeysByIndices(pagePlan.pages.map((page) => page.index));
      if (_useCanonicalSurface) _ensureCanonicalAssets(pagePlan.layout, document);
    }
    final canonicalAssets = _canonicalPreviewAssets;
    final planFailed = identical(_planController.failedFor, document);
    final activeStyle = _activeStyle();
    final selectionFormat = _selectionFormatState();

    return Scaffold(
      appBar: AppBar(
        // العنوان ثابت حرفياً (تعتمد عليه اختبارات الواجهة)؛ عدد الصفحات
        // يظهر في حوار المراجعة قبل التصدير.
        title: const Text('الخطوة 3: معاينة A4'),
        leading: IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'العودة للأسئلة',
          onPressed: widget.onBackToQuestions,
        ),
        actions: <Widget>[
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'إعدادات الورقة',
            onPressed: _isBusy ? null : _showSettings,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.save_outlined),
            tooltip: 'حفظ الورقة',
            onPressed: _isBusy ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // شريط أدوات السؤال: **خارج الورقة**، لا يشارك هندستها ولا يغيّر
          // مقاساتها (§19.15). مساحة اللمس 48dp كاملة، ويُعطَّل حين لا يكون
          // سؤال واحد محدَّداً حتى لا يعمل على السؤال الخطأ.
          _buildQuestionActionsBar(controller),
          PreviewToolbar(
            selectionLabel: _selectionLabel(document),
            canUndo: controller.canUndo,
            onUndo: controller.undo,
            canRedo: controller.canRedo,
            onRedo: controller.redo,
            locked: _locked,
            onToggleLock: () => setState(() => _locked = !_locked),
            zoom: _zoom,
            onZoomIn: () => _zoomBy(1.2),
            onZoomOut: () => _zoomBy(1 / 1.2),
            onZoomReset: () => setState(() => _zoom = 1.0),
            onFit: _fitToScreen,
            onCenter: _centerPaper,
            multiSelect: _multiSelect,
            onToggleMultiSelect: _toggleMultiSelect,
            onToggleSelectAll: _toggleSelectAll,
            allBlocksSelected: _allBlocksSelected,
            selectedBlockCount: _selectedBlockCount,
            totalBlockCount: _selectableBlockCount,
            formatCount: document.formatNumber,
            activeFont: activeStyle.font,
            onFontChanged: (font) => _applyStyle(
              (current) => current.copyWith(font: () => font),
            ),
            activeFontSize: activeStyle.fontSize,
            onFontSizeChanged: (size) {
              // القيمة المميزة NaN تعني «حجم مخصص» من قائمة الشريط.
              if (size != null && size.isNaN) {
                _showCustomFontSize();
                return;
              }
              _applyStyle((current) => current.copyWith(fontSize: () => size));
            },
            isBold:
                selectionFormat == null ? activeStyle.bold : selectionFormat.bold,
            onToggleBold: () =>
                _toggleSelectionFormat(_RangeFormatAttribute.bold),
            isItalic: selectionFormat == null
                ? activeStyle.italic
                : selectionFormat.italic,
            onToggleItalic: () =>
                _toggleSelectionFormat(_RangeFormatAttribute.italic),
            isUnderline: selectionFormat == null
                ? activeStyle.underline
                : selectionFormat.underline,
            onToggleUnderline: () =>
                _toggleSelectionFormat(_RangeFormatAttribute.underline),
            activeAlign: _activeAlign(),
            onAlignChanged: _onAlignChanged,
            activeLineHeight: activeStyle.lineHeight,
            onLineHeightChanged: (value) {
              // القيمة المميزة NaN تعني «تباعد مخصص» من قائمة الشريط.
              if (value != null && value.isNaN) {
                _showCustomLineHeight();
                return;
              }
              _applyStyle((current) => current.copyWith(lineHeight: () => value));
            },
            activeParagraphSpacing: activeStyle.paragraphSpacing,
            onParagraphSpacingChanged: (value) {
              if (value != null && value.isNaN) {
                _showCustomParagraphSpacing();
                return;
              }
              _applyStyle(
                (current) => current.copyWith(paragraphSpacing: () => value),
              );
            },
            activeQuestionSpacing: _activeQuestionSpacing(),
            onQuestionSpacingChanged: (spacing) {
              if (spacing.isNaN) {
                _showCustomQuestionSpacing();
                return;
              }
              _applyQuestionSpacing(spacing);
            },
            activeColor:
                selectionFormat == null ? _activeColor() : selectionFormat.color,
            colorTooltip: _colorTooltip(),
            onColorChanged: (value) {
              // القيمة المميزة -1 تعني «لون مخصص» (HEX) من قائمة الشريط.
              if (value != null && value == PreviewToolbar.customColorSentinel) {
                _showCustomColor();
                return;
              }
              _applySelectionColor(value);
            },
            hasFrame: _activeFrame(),
            onToggleFrame: _toggleFrame,
            showFormulas: _showFormulas,
            onToggleFormulas: () => setState(() => _showFormulas = !_showFormulas),
            onSave: _save,
            onExportPdf: _showReview,
            isBusy: _isBusy,
          ),
          if (_showFormulas)
            SmartExamToolbar(
              inserter: _inserter,
              onInsertText: _insertText,
              onAddImage: _addImageToSelection,
              onPickImage: _pickImageToSelection,
              onAddShape: _addShapeToSelection,
              onAddQuestion: controller.addQuestion,
              onAddBranch: _addBranchToSelected,
              onAddTextBox: _addTextBox,
              onAddDivider: _addDividerToSelection,
              stagedFormula: _stagedFormula,
              onEquationEditor: _openEquationEditor,
              onAddFormula: _openEquationEditor,
              onFormulaDragEnd: _handleFormulaDragEnd,
              onClearStagedFormula: _clearStagedFormula,
            ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportWidth = constraints.maxWidth;
                SchedulerBinding.instance.addPostFrameCallback((_) => _maybeAutoFit());
                final pageCanvasWidth = pagePlan?.layout.pages.fold<double>(
                      0,
                      (largest, page) => math.max(
                        largest,
                        LayoutUnits.ptToPx(page.pageSize.width),
                      ),
                    ) ??
                    ExamCanvasGeometry.width;
                final contentWidth = math.max(
                  _viewportWidth,
                  pageCanvasWidth * _zoom + 24,
                );
                return Stack(
                  key: _canonicalEditorViewport,
                  children: <Widget>[
                    SingleChildScrollView(
                      key: const ValueKey<String>('paper-v-scroll'),
                      controller: _vScroll,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SingleChildScrollView(
                        key: const ValueKey<String>('paper-h-scroll'),
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            children: <Widget>[
                              if (pagePlan == null)
                                _buildPlanPending(failed: planFailed)
                              else if (!_useCanonicalSurface)
                                for (final page in pagePlan.pages)
                                  _buildPaperZoomedPage(
                                    controller,
                                    layout,
                                    page,
                                    pagePlan.pageCount,
                                    pagePlan,
                                  )
                              else if (canonicalAssets != null)
                                for (final page in pagePlan.layout.pages)
                                  _buildCanonicalZoomedPage(
                                    controller,
                                    pagePlan.layout,
                                    page,
                                    canonicalAssets,
                                    interactive: true,
                                  )
                              else if (identical(
                                _canonicalPreviewAssetsFailedLayout,
                                pagePlan.layout,
                              ))
                                SizedBox(
                                  width: 794,
                                  height: 320,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(
                                          Icons.error_outline,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(height: 8),
                                        const Text('تعذّر تجهيز المعاينة القانونية.'),
                                        TextButton.icon(
                                          onPressed: _retryCanonicalPreview,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('إعادة المحاولة'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(
                                  width: 794,
                                  height: 320,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_separateEditorCandidate && pagePlan != null && _canonicalEditorOpen && !_locked)
                      Positioned.fill(child: _buildSeparateCanonicalEditor(controller, pagePlan.layout)),
                      if (_isBusy)
                        const Positioned.fill(
                          child: AbsorbPointer(
                            child: ColoredBox(
                              color: Colors.white,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<InlineNode, _CanonicalFieldBinding> _canonicalFieldBindings(
    ExamWizardController controller,
    DocumentIR source,
  ) {
    final result = <InlineNode, _CanonicalFieldBinding>{};
    TextStyle fieldStyle(TextStyle role, PaperTextStyle override) => PaperStyles.resolve(
      role, override, defaultFont: controller.document.settings.defaultFont,
      fontScale: _fontScale, heightScale: _heightScale,
    );
    void bind(
      InlineContent content, {
      required String fieldKey,
      required String sourceText,
      required TextStyle style,
      required ValueChanged<String> onEdit,
      required VoidCallback onLongPress,
    }) {
      final binding = _CanonicalFieldBinding(
        fieldKey: fieldKey,
        sourceText: sourceText,
        content: content,
        style: style,
        onEdit: _separateEditorCandidate ? (value) => _writeCanonicalSource(fieldKey, value) : onEdit,
        onLongPress: onLongPress,
      );
      void addNodes(Iterable<InlineNode> nodes) {
        for (final node in nodes) {
          result[node] = binding;
          if (node is LabelNode) addNodes(node.content.nodes);
        }
      }

      addNodes(content.nodes);
    }

    for (final question in source.questions) {
      final questionIndex = controller.questions.indexWhere((model) => model.id == question.id);
      if (questionIndex < 0) continue;
      final model = controller.questions[questionIndex];
      void questionLongPress() => _longPressQuestion(questionIndex);
      bind(
        question.content,
        fieldKey: _statementKey(model.id),
        sourceText: model.statement,
        style: fieldStyle(PaperStyles.question, model.style.copyWith(color: () => model.effectiveTitleColor)),
        onEdit: (value) => controller.updateQuestionStatement(questionIndex, value),
        onLongPress: questionLongPress,
      );
      final body = question.body;
      if (body != null) {
        bind(
          body.content,
          fieldKey: _bodyKey(model.id),
          sourceText: model.body,
          style: fieldStyle(PaperStyles.prompt, model.style.copyWith(color: () => null)),
          onEdit: (value) => controller.updateQuestionBody(questionIndex, value),
          onLongPress: questionLongPress,
        );
      }
      final category = question.category;
      if (category != null) {
        bind(
          category.content,
          fieldKey: _categoryKey(model.id),
          sourceText: model.category,
          style: _scaled(PaperStyles.category),
          onEdit: (value) => controller.updateQuestionCategory(questionIndex, value),
          onLongPress: questionLongPress,
        );
      }
      final questionOwner = PointsOwner.question(questionIndex);
      for (final point in question.points) {
        final itemIndex = model.items.indexWhere((value) => value.id == point.id);
        if (itemIndex < 0) continue;
        final item = model.items[itemIndex];
        bind(
          point.content,
          fieldKey: _itemKey(item.id),
          sourceText: item.text,
          style: fieldStyle(PaperStyles.item, model.style.copyWith(color: () => null)),
          onEdit: (value) => controller.updatePointText(questionOwner, item.id, value),
          onLongPress: questionLongPress,
        );
        final options = point.options?.options ?? const <OptionNode>[];
        for (final option in options) {
          final optionIndex = item.options.indexWhere((model) => model.id == option.id);
          if (optionIndex < 0) continue;
          bind(
            option.content,
            fieldKey: _sourceOptionKey(item, optionIndex),
            sourceText: item.options[optionIndex].text,
            style: fieldStyle(PaperStyles.option, model.style.copyWith(color: () => null)),
            onEdit: (value) => controller.updatePointOptionText(
              questionOwner,
              item.id,
              optionIndex,
              value,
            ),
            onLongPress: questionLongPress,
          );
        }
      }

      for (final branch in question.branches) {
        final branchIndex = model.branches.indexWhere((model) => model.id == branch.id);
        if (branchIndex < 0) continue;
        final branchModel = model.branches[branchIndex];
        final branchRef = BranchRef(
          questionIndex: questionIndex,
          branchIndex: branchIndex,
        );
        void branchLongPress() => _longPressBranch(branchRef);
        bind(
          branch.content,
          fieldKey: _branchStatementKey(branch.id),
          sourceText: branchModel.content.statement,
          style: fieldStyle(PaperStyles.body(controller.document.layout), branchModel.style),
          onEdit: (value) => controller.updateBranchStatement(branchRef, value),
          onLongPress: branchLongPress,
        );
        final branchBody = branch.body;
        if (branchBody != null) {
          bind(
            branchBody.content,
            fieldKey: _branchBodyKey(branch.id),
            sourceText: branchModel.content.body,
            style: fieldStyle(PaperStyles.body(controller.document.layout), branchModel.style),
            onEdit: (value) => controller.updateBranchBody(branchRef, value),
            onLongPress: branchLongPress,
          );
        }
        final branchOwner = PointsOwner.branch(branchRef);
        for (final point in branch.points) {
          final itemIndex = branchModel.content.items
              .indexWhere((value) => value.id == point.id);
          if (itemIndex < 0) continue;
          final item = branchModel.content.items[itemIndex];
          bind(
            point.content,
            fieldKey: _itemKey(item.id),
            sourceText: item.text,
            style: fieldStyle(PaperStyles.item, branchModel.style),
            onEdit: (value) => controller.updatePointText(branchOwner, item.id, value),
            onLongPress: branchLongPress,
          );
          for (final option in point.options?.options ?? const <OptionNode>[]) {
            final optionIndex = item.options.indexWhere((model) => model.id == option.id);
            if (optionIndex < 0) continue;
            bind(
              option.content,
              fieldKey: _sourceOptionKey(item, optionIndex),
              sourceText: item.options[optionIndex].text,
              style: fieldStyle(PaperStyles.option, branchModel.style),
              onEdit: (value) => controller.updatePointOptionText(
                branchOwner,
                item.id,
                optionIndex,
                value,
              ),
              onLongPress: branchLongPress,
            );
          }
        }
      }
    }
    return result;
  }

  LayoutRun? _canonicalRunById(LayoutPage page, String? runId) {
    if (runId == null) return null;
    for (final block in page.blocks) {
      for (final line in block.allLines) {
        for (final run in line.runs) {
          if (run.id == runId) return run;
        }
      }
    }
    for (final placement in page.floatingElements) {
      for (final line in placement.labelLines) {
        for (final run in line.runs) {
          if (run.id == runId) return run;
        }
      }
    }
    return null;
  }

  /// Route printed metadata to the SAME dialogs as the legacy title widgets.
  /// Resolve current model IDs, never use a stale layout's positional index.
  bool _handleCandidateMetadataTap(ExamWizardController controller, DocumentIR source, CanonicalHitTestResult hit) {
    if (!_separateEditorCandidate) return false;
    final id = hit.semanticNodeId;
    bool label(String owner) => id.startsWith('$owner/title/label');
    bool marks(String owner) => id.startsWith('$owner/title/marks');
    for (final question in source.questions) {
      final q = controller.questions.indexWhere((model) => model.id == question.id);
      if (q < 0) continue;
      for (final branch in question.branches) {
        final owner = '${question.id}/branch/${branch.id}';
        if (!label(owner) && !marks(owner)) continue;
        final b = controller.questions[q].branches.indexWhere((model) => model.id == branch.id);
        if (b < 0) return false;
        final ref = BranchRef(questionIndex: q, branchIndex: b);
        _tapBranch(ref);
        unawaited(label(owner) ? _editBranchLabel(ref) : _editBranchMarks(ref));
        return true;
      }
      if (label(question.id) || marks(question.id)) {
        _tapQuestion(q);
        unawaited(label(question.id) ? _editQuestionLabel(q) : _editQuestionMarks(q));
        return true;
      }
    }
    return false;
  }

  void _handleCanonicalPageTap(
    ExamWizardController controller,
    LayoutDocument layout,
    LayoutPage page,
    Map<InlineNode, _CanonicalFieldBinding> bindings,
    CanonicalPagePointerEvent event,
  ) {
    if (_stagedFormula != null && !_locked) {
      _placeStagedFormula(event.localPositionPx, pageIndex: page.index);
      return;
    }
    final hit = event.hit;
    if (hit == null || hit.isFloatingElement) return;
    if (_separateEditorCandidate) _canonicalEditorPageHint = page.index;
    if (_handleCandidateMetadataTap(controller, layout.source, hit)) return;
    final run = _canonicalRunById(page, hit.runId);
    final binding = run?.semanticNode == null ? null : bindings[run!.semanticNode];
    if (binding != null && run != null) {
      if (_separateEditorCandidate) {
        _canonicalEditorOpen = true;
        _canonicalEditorPageHint = page.index;
      }
      final field = _field(binding.fieldKey, binding.sourceText, binding.onEdit);
      final offset = (hit.sourceOffset ?? 0).clamp(0, field.text.length).toInt();
      field.selection = TextSelection.collapsed(offset: offset);
      _activateField(
        binding.fieldKey,
        field,
        canonicalSemanticNodeId: hit.semanticNodeId,
      );
      if (run.isMath && binding.content.hasMath) {
        unawaited(_editEquationInField(binding.fieldKey));
      }
      return;
    }
    _selectCanonicalBlock(controller, layout.source, hit);
  }

  void _handleCanonicalPageLongPress(
    ExamWizardController controller,
    LayoutDocument layout,
    LayoutPage page,
    Map<InlineNode, _CanonicalFieldBinding> bindings,
    CanonicalPagePointerEvent event,
  ) {
    final hit = event.hit;
    if (hit == null || hit.isFloatingElement) return;
    final run = _canonicalRunById(page, hit.runId);
    final binding = run?.semanticNode == null ? null : bindings[run!.semanticNode];
    if (binding != null && run != null) {
      if (_activeFieldKey == binding.fieldKey && !_multiSelect && !run.isMath) {
        final field = _fields[binding.fieldKey];
        if (field != null) {
          final selection = _wordSelectionAt(
            field.text,
            (hit.sourceOffset ?? 0).clamp(0, field.text.length).toInt(),
          );
          field.selection = selection;
          return;
        }
      }
      binding.onLongPress();
      return;
    }
    _selectCanonicalBlock(controller, layout.source, hit, longPress: true);
  }

  TextSelection _wordSelectionAt(String text, int offset) {
    if (text.isEmpty) return const TextSelection.collapsed(offset: 0);
    var start = offset.clamp(0, text.length).toInt();
    var end = start;
    bool isWordUnit(int index) {
      final unit = text.substring(index, index + 1);
      return !RegExp(r'\s').hasMatch(unit);
    }

    if (start == text.length && start > 0) start--;
    if (start < text.length && isWordUnit(start)) {
      end = start + 1;
      while (start > 0 && isWordUnit(start - 1)) {
        start--;
      }
      while (end < text.length && isWordUnit(end)) {
        end++;
      }
      return TextSelection(baseOffset: start, extentOffset: end);
    }
    return TextSelection.collapsed(offset: offset);
  }

  void _selectCanonicalBlock(
    ExamWizardController controller,
    DocumentIR source,
    CanonicalHitTestResult hit, {
    bool longPress = false,
  }) {
    if (hit.semanticNodeId == 'header' ||
        hit.semanticNodeId.startsWith('header/')) {
      _tapHeader();
      return;
    }
    if (hit.semanticNodeId == 'footer' ||
        hit.semanticNodeId.startsWith('footer/')) {
      unawaited(_editHeaderAndFooter());
      return;
    }
    for (final question in source.questions) {
      for (final branch in question.branches) {
        if (hit.semanticNodeId == branch.id ||
            hit.semanticNodeId.startsWith('${branch.id}/') ||
            hit.blockId == branch.id ||
            (hit.blockId?.startsWith('${branch.id}/') ?? false)) {
          final ref = BranchRef(
            questionIndex: question.index,
            branchIndex: branch.index,
          );
          if (longPress) {
            _longPressBranch(ref);
          } else {
            _tapBranch(ref);
          }
          return;
        }
      }
      if (hit.semanticNodeId == question.id ||
          hit.semanticNodeId.startsWith('${question.id}/') ||
          hit.blockId == question.id ||
          (hit.blockId?.startsWith('${question.id}/') ?? false)) {
        if (longPress) {
          _longPressQuestion(question.index);
        } else {
          _tapQuestion(question.index);
        }
        return;
      }
    }
  }

  int? _canonicalPageForCursor(
    LayoutDocument layout,
    String? semanticNodeId,
    int? sourceOffset,
  ) {
    if (semanticNodeId == null || sourceOffset == null) return null;
    for (final page in layout.pages) {
      for (final block in page.blocks) {
        for (final line in block.allLines) {
          for (final run in line.runs) {
            if (run.semanticNodeId != semanticNodeId || run.isMath) continue;
            final end = run.sourceEndOffset > run.sourceStartOffset
                ? run.sourceEndOffset
                : run.sourceStartOffset + run.text.length;
            if (sourceOffset >= run.sourceStartOffset && sourceOffset <= end) {
              return page.index;
            }
          }
        }
      }
    }
    return null;
  }

  ({_CanonicalFieldBinding binding, String ownerId, String questionId})? _candidateOptionalBinding(ExamWizardController controller, {String? fieldKey}) {
    final document = controller.document;
    final key = fieldKey ?? _activeFieldKey;
    TextStyle style(TextStyle role, PaperTextStyle override) => PaperStyles.resolve(
      role, override, defaultFont: document.settings.defaultFont,
      fontScale: _fontScale, heightScale: _heightScale,
    );
    for (var q = 0; q < document.questions.length; q++) {
      final question = document.questions[q];
      final ir = controller.documentIr.questionById(question.id);
      final statement = key == _statementKey(question.id);
      if (statement || key == _bodyKey(question.id)) {
        final text = statement ? question.statement : question.body;
        return (ownerId: question.id, questionId: question.id, binding: _CanonicalFieldBinding(
          fieldKey: statement ? _statementKey(question.id) : _bodyKey(question.id), sourceText: text,
          content: (statement ? ir?.content : ir?.body?.content) ?? InlineContent.fromSource(text),
          style: statement
              ? style(PaperStyles.question, question.style.copyWith(color: () => question.effectiveTitleColor))
              : style(PaperStyles.prompt, question.style.copyWith(color: () => null)),
          hint: statement ? 'منطوق السؤال' : 'نص السؤال (اختياري)',
          onEdit: (value) => _writeCanonicalSource(statement ? _statementKey(question.id) : _bodyKey(question.id), value),
          onLongPress: () => _longPressQuestion(q),
        ));
      }
      for (var b = 0; b < question.branches.length; b++) {
        final branch = question.branches[b];
        final statement = key == _branchStatementKey(branch.id);
        if (!statement && key != _branchBodyKey(branch.id)) continue;
        final ref = BranchRef(questionIndex: q, branchIndex: b);
        final branchIr = ir?.branches.where((candidate) => candidate.id == branch.id).firstOrNull;
        return (ownerId: branch.id, questionId: question.id, binding: _CanonicalFieldBinding(
          fieldKey: statement ? _branchStatementKey(branch.id) : _branchBodyKey(branch.id),
          sourceText: statement ? branch.content.statement : branch.content.body,
          content: (statement ? branchIr?.content : branchIr?.body?.content) ??
            InlineContent.fromSource(statement ? branch.content.statement : branch.content.body),
          style: style(PaperStyles.body(document.layout), branch.style),
          hint: statement ? 'منطوق الفرع' : 'نص الفرع (اختياري)',
          onEdit: (value) => _writeCanonicalSource(statement ? _branchStatementKey(branch.id) : _branchBodyKey(branch.id), value),
          onLongPress: () => _longPressBranch(ref),
        ));
      }
    }
    return null;
  }

  Iterable<LayoutBlock> _canonicalDescendants(Iterable<LayoutBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* _canonicalDescendants(block.children);
    }
  }

  Widget _buildSeparateCanonicalEditor(ExamWizardController controller, LayoutDocument layout) {
    final bindings = _canonicalFieldBindings(controller, layout.source);
    ({LayoutPage page, LayoutRect anchor, _CanonicalFieldBinding binding})? target;
    var bestDistance = double.infinity;
    final source = _activeFieldKey == null ? null : _fields[_activeFieldKey];
    final selection = source?.selection;
    final offset = selection != null && selection.isValid ? selection.extentOffset : 0;
    for (final page in layout.pages) {
      for (final block in page.blocks) {
        for (final line in block.allLines) {
          for (final run in line.runs) {
            final binding = bindings[run.semanticNode];
            if (binding == null || binding.fieldKey != _activeFieldKey) continue;
            final end = run.sourceEndOffset;
            final distance = offset < run.sourceStartOffset ? (run.sourceStartOffset - offset).toDouble()
                : offset > end ? (offset - end).toDouble() : 0.0;
            if (distance > bestDistance) continue;
            if (distance == bestDistance &&
                (target?.page.index == _canonicalEditorPageHint || page.index != _canonicalEditorPageHint)) continue;
            bestDistance = distance;
            target = (page: page, anchor: line.rect, binding: binding);
          }
        }
      }
    }
    if (target == null) {
      final body = _candidateOptionalBinding(controller);
      if (body != null) {
        // No invented printed box: use the actual owner/title on this page.
        // An entirely unprinted owner uses the shared plan's unplanned anchor.
        for (final ownerId in <String>{body.ownerId, body.questionId}) {
          for (final page in layout.pages) {
            for (final block in _canonicalDescendants(page.blocks)) {
              if (block.semanticNodeId != ownerId) continue;
              if (target != null && page.index != _canonicalEditorPageHint) continue;
              final lines = block.allLines;
              target = (page: page, anchor: lines.isEmpty ? block.rect : lines.first.rect, binding: body.binding);
            }
          }
          if (target != null) break;
        }
        if (target == null) {
          final plan = CanonicalPagePlan.fromLayout(layout);
          for (final page in plan.pages) {
            if (!page.unplannedQuestionIds.contains(body.questionId)) continue;
            target = (page: layout.pages[page.index],
              anchor: LayoutRect.fromLTWH(page.bodyBounds.left, page.bodyBounds.top, page.bodyBounds.width, 0),
              binding: body.binding);
            break;
          }
        }
      }
    }
    if (target == null) return const SizedBox.shrink();
    final binding = target.binding;
    final pageKey = _pageCanvasKeys.putIfAbsent(target.page.index, () => GlobalKey());
    return CanonicalEditingLayer(
      key: const ValueKey<String>('canonical-native-editing-layer'),
      viewportKey: _canonicalEditorViewport,
      pageKey: pageKey,
      anchorPt: target.anchor,
      scrollChanges: _canonicalEditorScroll,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Row(children: <Widget>[
            const Expanded(child: Padding(padding: EdgeInsetsDirectional.only(start: 12), child: Text('تحرير المحتوى'))),
            IconButton(
              tooltip: 'إغلاق محرر المحتوى',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); setState(() => _canonicalEditorOpen = false); },
              icon: const Icon(Icons.close),
            ),
          ]),
          Flexible(child: SingleChildScrollView(
            key: const ValueKey<String>('canonical-native-editor-scroll'),
            padding: const EdgeInsets.all(12),
            child: _paperField(
              fieldKey: binding.fieldKey,
              controller: _field(binding.fieldKey, binding.sourceText, binding.onEdit),
              style: binding.style,
              semanticContent: binding.content,
              autofocus: true,
              minimumInteractiveHeight: 48,
              hint: binding.hint,
              matchPrintedTextWidth: false,
              onLongPress: binding.onLongPress,
            ),
          )),
        ]),
      ),
    );
  }

  Widget _buildCanonicalPage(
    ExamWizardController controller,
    LayoutDocument layout,
    LayoutPage page,
    CanonicalLayoutPreviewAssets assets, {
    required bool interactive,
  }) {
    final sourceDocument = controller.document;
    final bindings = _canonicalFieldBindings(controller, layout.source);
    _CanonicalFieldBinding? activeBinding;
    if (_activeFieldKey != null) {
      for (final binding in bindings.values) {
        if (binding.fieldKey == _activeFieldKey) {
          activeBinding = binding;
          break;
        }
      }
    }
    final currentBinding = activeBinding;
    final activeNodeId = _activeCanonicalSemanticNodeId;
    final activeFieldController = currentBinding == null
        ? null
        : _fields[currentBinding.fieldKey];
    final activeSelection = activeFieldController?.selection;
    final selectionToPaint = activeSelection != null && activeSelection.isValid
        ? activeSelection
        : null;
    final activeOffset = activeSelection != null && activeSelection.isValid
        ? activeSelection.extentOffset
        : null;
    final activePageIndex = _canonicalPageForCursor(
      layout,
      activeNodeId,
      activeOffset,
    );
    final pageHasActiveNode = activeNodeId != null &&
        page.blocks.any((block) => block.allLines.any((line) =>
            line.runs.any((run) => run.semanticNodeId == activeNodeId)));
    final pageWidth = LayoutUnits.ptToPx(page.pageSize.width);
    final pageHeight = LayoutUnits.ptToPx(page.pageSize.height);
    final selectionDecorations = <Widget>[];
    void collectSelectionDecorations(Iterable<LayoutBlock> blocks) {
      for (final block in blocks) {
        var selected = false;
        if (block.kind == LayoutBlockKind.question) {
          final question = layout.source.questionById(block.semanticNodeId);
          selected = question != null && _isQuestionSelected(question.index);
        } else if (block.kind == LayoutBlockKind.branch) {
          for (final question in layout.source.questions) {
            for (final branch in question.branches) {
              if (branch.id == block.semanticNodeId) {
                selected = _isBranchSelected(BranchRef(
                  questionIndex: question.index,
                  branchIndex: branch.index,
                ));
              }
            }
          }
        }
        if (selected) {
          selectionDecorations.add(
            Positioned.fromRect(
              rect: Rect.fromLTWH(
                LayoutUnits.ptToPx(block.rect.left),
                LayoutUnits.ptToPx(block.rect.top),
                LayoutUnits.ptToPx(block.rect.width),
                LayoutUnits.ptToPx(block.rect.height),
              ),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x0C2563EB),
                    border: Border.all(color: PaperStyles.accent, width: 1.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          );
        }
        collectSelectionDecorations(block.children);
      }
    }
    collectSelectionDecorations(page.blocks);

    final children = <Widget>[
      CanonicalLayoutPreviewPage(
        key: ValueKey<String>('canonical-preview-page-${page.index}'),
        layoutDocument: layout,
        page: page,
        document: sourceDocument,
        assets: assets,
        onTap: interactive
            ? (event) => _handleCanonicalPageTap(
                  controller,
                  layout,
                  page,
                  bindings,
                  event,
                )
            : null,
        onLongPress: interactive
            ? (event) => _handleCanonicalPageLongPress(
                  controller,
                  layout,
                  page,
                  bindings,
                  event,
                )
            : null,
      ),
      if (interactive) ...selectionDecorations,
      if (interactive)
        for (final placement in page.floatingElements)
          if (placement.deferredReason == null)
            _buildCanonicalFloatingInteraction(
              controller,
              layout,
              page,
              placement,
            ),
      if (interactive &&
          !_separateEditorCandidate &&
          currentBinding != null &&
          pageHasActiveNode &&
          page.index == activePageIndex)
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: PaperField(
            key: ValueKey<String>(currentBinding.fieldKey),
            controller: _field(
              currentBinding.fieldKey,
              currentBinding.sourceText,
              currentBinding.onEdit,
            ),
            style: const TextStyle(fontSize: 12),
            semanticContent: currentBinding.content,
            canonicalInteractionOnly: true,
            autofocus: true,
            onActivate: () => _activateField(
              currentBinding.fieldKey,
              _field(
                currentBinding.fieldKey,
                currentBinding.sourceText,
                currentBinding.onEdit,
              ),
            ),
            onEditFormula: () => _editEquationInField(currentBinding.fieldKey),
            onLongPress: currentBinding.onLongPress,
            allowTextSelection: !_multiSelect,
            renderBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      if (interactive &&
          currentBinding != null &&
          pageHasActiveNode &&
          selectionToPaint != null)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CanonicalSelectionPainter(
                page: page,
                semanticNodeId: activeNodeId,
                selection: selectionToPaint,
              ),
            ),
          ),
        ),
    ];

    final pageCanvas = Container(
      key: _pageCanvasKeys.putIfAbsent(
        page.index,
        () => GlobalKey(debugLabel: 'canonical-page-canvas-${page.index}'),
      ),
      width: pageWidth,
      height: pageHeight,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: children,
      ),
    );
    return Directionality(
      textDirection: layout.direction == DocumentDirection.ltr
          ? TextDirection.ltr
          : TextDirection.rtl,
      child: pageCanvas,
    );
  }

  Widget _buildCanonicalFloatingInteraction(
    ExamWizardController controller,
    LayoutDocument layout,
    LayoutPage page,
    LayoutFloatPlacement placement,
  ) {
    final ref = _attachmentRefForId(controller.document, placement.reference.id);
    final element = _findAttachment(controller.document, ref);
    if (element == null || placement.rect.isEmpty) return const SizedBox.shrink();
    final selected = _selectedAttachment?.elementId == ref.elementId;
    final rect = Rect.fromLTWH(
      LayoutUnits.ptToPx(placement.rect.left),
      LayoutUnits.ptToPx(placement.rect.top),
      LayoutUnits.ptToPx(placement.rect.width),
      LayoutUnits.ptToPx(placement.rect.height),
    );
    final input = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        if (!_locked)
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(),
            (EagerGestureRecognizer instance) {},
          ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _lastPointerDownTime = event.timeStamp;
          _beginCanonicalAttachmentDrag(
            ref,
            element,
            page,
            placement,
            event.pointer,
            event.position,
          );
        },
        onPointerMove: (event) =>
            _updateCanonicalAttachmentDrag(event.pointer, event.position, layout),
        onPointerUp: (event) {
          if (event.pointer == _dragPointer && !_dragMoved) {
            _selectAttachment(ref);
            final current = _findAttachment(_controller!.document, ref) ?? element;
            _noteAttachmentTap(ref, current, _lastPointerDownTime);
          }
          _endAttachmentDrag(event.pointer);
        },
        onPointerCancel: (event) => _endAttachmentDrag(event.pointer),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: selected
                ? Border.all(color: PaperStyles.accent, width: 1.5)
                : null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: input),
          if (selected && !_locked && (element.isTextBox || element.isFormula))
            Positioned(
              right: 0,
              top: 0,
              child: _elementHandle(
                key: ValueKey<String>('canonical-edit-element-${element.id}'),
                icon: Icons.edit,
                tooltip: element.isFormula ? 'تحرير المعادلة' : 'تحرير مربع النص',
                color: PaperStyles.accent,
                onTap: () => element.isFormula
                    ? _editFormulaElement(ref)
                    : _editTextBox(ref),
              ),
            ),
          if (selected && !_locked)
            Positioned(
              right: 0,
              bottom: 0,
              child: _elementHandle(
                key: ValueKey<String>('canonical-resize-element-${element.id}'),
                icon: Icons.south_east,
                tooltip: 'اسحب لتغيير الحجم',
                color: PaperStyles.accent,
                onTap: () => _scaleAttachment(ref, element, 1.1),
                onPanUpdate: (details) =>
                    _resizeAttachmentByDrag(ref, element, details),
              ),
            ),
          if (selected &&
              !_locked &&
              !element.isTextBox &&
              !element.isImage)
            Positioned(
              left: 0,
              bottom: 0,
              child: _elementHandle(
                key: ValueKey<String>('canonical-rotate-element-${element.id}'),
                icon: Icons.rotate_right,
                tooltip: 'تدوير العنصر 45°',
                color: PaperStyles.accent,
                onTap: () => _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    rotationDegrees: (element.rotationDegrees + 45) % 360,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _AttachmentRef _attachmentRefForId(ExamDocument document, String elementId) {
    if (document.floatingElements.any((element) => element.id == elementId)) {
      return _AttachmentRef.global(elementId);
    }
    for (var questionIndex = 0;
        questionIndex < document.questions.length;
        questionIndex++) {
      final question = document.questions[questionIndex];
      if (question.attachments.any((element) => element.id == elementId)) {
        return _AttachmentRef(questionIndex: questionIndex, elementId: elementId);
      }
      for (var branchIndex = 0; branchIndex < question.branches.length; branchIndex++) {
        final branch = question.branches[branchIndex];
        if (branch.attachments.any((element) => element.id == elementId)) {
          return _AttachmentRef(
            questionIndex: questionIndex,
            branchIndex: branchIndex,
            elementId: elementId,
          );
        }
      }
    }
    return _AttachmentRef.global(elementId);
  }

  void _beginCanonicalAttachmentDrag(
    _AttachmentRef ref,
    FloatingElement element,
    LayoutPage page,
    LayoutFloatPlacement placement,
    int pointer,
    Offset screenPosition,
  ) {
    final local = _localPositionOnPage(page.index, screenPosition);
    final left = LayoutUnits.ptToPx(placement.rect.left);
    final top = LayoutUnits.ptToPx(placement.rect.top);
    _dragPointer = pointer;
    _dragRef = ref;
    _dragStartScreen = screenPosition;
    _dragLastScreen = screenPosition;
    _dragLastPaper = Offset(left, top);
    _dragPageIndex = page.index;
    _dragAnchorWithinElement = local == null
        ? Offset(
            LayoutUnits.ptToPx(placement.rect.width / 2),
            LayoutUnits.ptToPx(placement.rect.height / 2),
          )
        : Offset(local.dx - left, local.dy - top);
    _dragMoved = false;
  }

  void _updateCanonicalAttachmentDrag(
    int pointer,
    Offset screenPosition,
    LayoutDocument layout,
  ) {
    final start = _dragStartScreen;
    final previousScreen = _dragLastScreen;
    final previousPaper = _dragLastPaper;
    final anchor = _dragAnchorWithinElement;
    final ref = _dragRef;
    final controller = _controller;
    if (controller == null ||
        start == null ||
        previousScreen == null ||
        previousPaper == null ||
        anchor == null ||
        ref == null ||
        pointer != _dragPointer ||
        _locked) {
      return;
    }
    if (!_dragMoved && (screenPosition - start).distance <= kTouchSlop) return;
    _dragMoved = true;
    final element = _findAttachment(controller.document, ref);
    if (element == null) return;

    final targetPage = _pageAtGlobalPosition(screenPosition);
    final int pageIndex;
    final Offset target;
    if (targetPage != null) {
      pageIndex = targetPage.pageIndex;
      target = Offset(
        targetPage.local.dx - anchor.dx,
        targetPage.local.dy - anchor.dy,
      );
    } else {
      pageIndex = _dragPageIndex ?? element.pageIndex;
      final delta = (screenPosition - previousScreen) / _zoom;
      target = previousPaper + delta;
    }
    _moveCanonicalAttachmentTo(layout, ref, element, target, pageIndex);
    _dragLastPaper = target;
    _dragLastScreen = screenPosition;
  }

  void _moveCanonicalAttachmentTo(
    LayoutDocument layout,
    _AttachmentRef ref,
    FloatingElement element,
    Offset physicalTopLeftPx,
    int pageIndex,
  ) {
    final controller = _controller;
    if (controller == null) return;
    final pageWidthPx = LayoutUnits.ptToPx(layout.pageSize.width);
    final marginPx = LayoutUnits.ptToPx(
      layout.pages.first.contentBounds.left,
    );
    final maxLeft = pageWidthPx - 24;
    final maxTop = LayoutUnits.ptToPx(layout.pageSize.height) - 24;
    final left = physicalTopLeftPx.dx
        .clamp(24 - element.width, maxLeft)
        .toDouble();
    final top = physicalTopLeftPx.dy
        .clamp(24 - element.height, maxTop)
        .toDouble();
    final ownerId = element.ownerQuestionId;
    if (ownerId == null) {
      final logicalDx = layout.direction == DocumentDirection.rtl
          ? pageWidthPx - left - element.width
          : left;
      _updateAttachmentElement(
        ref,
        element.copyWith(pageIndex: pageIndex, dx: logicalDx, dy: top),
        preservePageIndex: true,
      );
      return;
    }

    LayoutBlock? ownerBlock;
    LayoutPage? ownerPage;
    for (final page in layout.pages) {
      if (page.index != pageIndex) continue;
      final candidates = <LayoutBlock>[];
      void collect(Iterable<LayoutBlock> blocks) {
        for (final block in blocks) {
          candidates.add(block);
          collect(block.children);
        }
      }

      collect(page.blocks);
      for (final candidate in candidates) {
        if (candidate.semanticNodeId == ownerId) {
          ownerBlock = candidate;
          ownerPage = page;
          break;
        }
      }
      if (ownerBlock != null) break;
    }
    if (ownerBlock == null || ownerPage == null) return;
    final logicalDx = layout.direction == DocumentDirection.rtl
        ? pageWidthPx - left - element.width - marginPx
        : left - marginPx;
    _updateAttachmentElement(
      ref,
      element.copyWith(
        pageIndex: ownerPage.index,
        dx: logicalDx.clamp(0.0, pageWidthPx).toDouble(),
        dy: (top - LayoutUnits.ptToPx(ownerBlock.rect.top))
            .clamp(0.0, maxTop)
            .toDouble(),
      ),
      preservePageIndex: true,
    );
  }

  // سطح الورقة التفاعلي (الافتراضي): FittedBox بنفس نسبة الأبعاد = تكبير
  // تخطيطي صحيح (القياس الداخلي يبقى بالمقاس الحقيقي، والتفاعل مع الحقول
  // يعمل تحت كل تكبير).
  Widget _buildPaperZoomedPage(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    CanonicalPagePlanPage page,
    int pageCount,
    CanonicalPagePlan plan,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: ExamCanvasGeometry.width * _zoom,
        height: ExamCanvasGeometry.height * _zoom,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: ExamCanvasGeometry.width,
            height: ExamCanvasGeometry.height,
            child: _buildPage(
              controller,
              layout,
              page,
              pageCount,
              plan,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanonicalZoomedPage(
    ExamWizardController controller,
    LayoutDocument layout,
    LayoutPage page,
    CanonicalLayoutPreviewAssets assets, {
    required bool interactive,
  }) {
    final width = LayoutUnits.ptToPx(page.pageSize.width);
    final height = LayoutUnits.ptToPx(page.pageSize.height);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: width * _zoom,
        height: height * _zoom,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: width,
            height: height,
            child: RepaintBoundary(
              key: _pageSnapshotKeys.putIfAbsent(
                page.index,
                () => GlobalKey(
                  debugLabel: 'canonical-page-snapshot-${page.index}',
                ),
              ),
              child: _buildCanonicalPage(
                controller,
                layout,
                page,
                assets,
                interactive: interactive,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // سطح الورقة التفاعلي: ودجات قابلة للتحرير فوق خطة المحرك المشتركة
  // (انظر [_buildPaperZoomedPage])؛ لا محرك ترقيم منافس.
  /// صفحة واحدة من **خطة المحرك**: مقاطع الكتل كما قرّرها `LayoutEngine`، لا
  /// كما قاسها هذا الودجت.
  ///
  /// السؤال الممتدّ يُرسم هنا في **مقاطعه**: نافذة على صفحة بدايته ونافذة على
  /// صفحة تكملته، بارتفاع المقطع وإزاحته من الخطة. الكتل المبنية هي نفسها في
  /// المقطعين وبمتحكماتها نفسها، فلا يوجد مصدر نصّي ثانٍ — انظر §19.9 في
  /// docs/p3_editor_preview_export_unification.md.
  Widget _buildPage(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    CanonicalPagePlanPage page,
    int pageCount,
    CanonicalPagePlan plan, {
    bool interactive = true,
    bool showPreviewChrome = true,
  }) {
    final document = controller.document;
    final documentIr = controller.documentIr;
    final blocks = <Widget>[];
    // (1) الترويسة من الخطة: الصفحة الأولى فقط، وحين يقرّر المحرك وجودها.
    // تُرشَّح المعرّفات المحذوفة أثناء حسم تعديل كي لا يبقى فراغ كتلة.
    if (page.hasHeader && page.index == 0) {
      blocks.add(_buildHeaderBlock(controller));
    }

    // (2) محتوى الصفحة = **مقاطع** الخطة بترتيبها (بدايات وتكملات)، ثم
    // الأسئلة بلا محتوى مطبوع (§19.7) التي لا تدخل الورقة.
    //
    // لماذا المقاطع لا `questionIds` فقط؟ لأن السؤال الممتدّ كان يُرسم كاملاً
    // في صفحة بدايته ويُقصّ عند حدّ الصفحة، فما يراه المدرس ناقص عمّا يطبعه
    // PDF. الآن كل صفحة ترسم نافذة المقطع التي حدّدها المحرك: الارتفاع
    // والإزاحة من الخطة نفسها، والكتلة المبنية هي الكتلة نفسها بمتحكماتها.
    final entries = <({CanonicalPagePlanFragment? fragment, String questionId})>[
      for (final fragment in page.fragments)
        if (documentIr.questionById(fragment.questionId) != null)
          (fragment: fragment, questionId: fragment.questionId),
      for (final id in page.unplannedQuestionIds)
        if (documentIr.questionById(id) != null &&
            !page.fragments.any((fragment) => fragment.questionId == id))
          (fragment: null, questionId: id),
    ];
    double? pendingSpacing;
    for (final entry in entries) {
      if (blocks.isNotEmpty && pendingSpacing != null) {
        blocks.add(SizedBox(height: pendingSpacing));
      }
      final fragment = entry.fragment;
      final questionData = documentIr.questionById(entry.questionId);
      if (questionData == null) {
        continue;
      }
      // بحث بالمعرف لا بالهوية: نسخ المستند تستبدل النسخ لا المعرفات.
      final questionIndex = questionData.index;
      // مقطع التكملة يأخذ مفاتيح ودجت مميّزة (الحقول تشترك في المتحكم نفسه،
      // فلا يجوز أن تتشابه مفاتيحها)؛ ومقطع البداية يبقى بمفاتيحه المعتادة.
      final suffix =
          fragment != null && fragment.isContinuation ? '/slice${fragment.fragmentIndex}' : '';
      final previousSuffix = _sliceKeySuffix;
      _sliceKeySuffix = suffix;
      Widget measured = const SizedBox.shrink();
      try {
        measured = _buildQuestionBlock(
          controller,
          layout,
          questionData,
          sliceSuffix: suffix,
          titleHeightPt: plan.titleHeightPtOf(questionData.id),
          plan: plan,
        );
      } finally {
        _sliceKeySuffix = previousSuffix;
      }
      Widget block = measured;
      if (fragment != null && fragment.isSplit) {
        block = _buildQuestionFragmentSlice(fragment, block, suffix);
      }
      // إفلات سؤال مسحوب هنا يعيد ترتيبه (السؤال وحدة لا تتجزأ). لا يُعرض هدف
      // إفلات على مقطع التكملة: موضعه ليس «بداية» يمكن الترتيب عندها.
      final acceptsDrop = interactive && (fragment == null || !fragment.isContinuation);
      blocks.add(
        acceptsDrop
            ? DragTarget<int>(
                onWillAcceptWithDetails: (details) =>
                    !_locked && details.data != questionIndex,
                onAcceptWithDetails: (details) =>
                    controller.moveQuestion(details.data, questionIndex),
                builder: (context, candidates, _) {
                  final highlighted = candidates.isNotEmpty;
                  return Container(
                    decoration: highlighted
                        ? BoxDecoration(
                            color: const Color(0x1A2563EB),
                            border: Border.all(color: PaperStyles.accent, width: 1.4),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: block,
                  );
                },
              )
            : block,
      );
      final question = document.questionById(entry.questionId);
      // فجوة ما بعد المقطع: صفر إن كان السؤال يستمرّ (المقطع يلتصق بحدّ
      // الصفحة)، وإلا فجوة السؤال من نموذجه كما كانت.
      pendingSpacing = fragment != null && fragment.continuesOnNext
          ? 0.0
          : (question?.spacingAfter ?? PaperMetrics.blockSpacingPx);
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
    // كتلة أطول من الصفحة: المحرك هو من قرّر التصغير ومقداره.
    if (page.scaleFactor < 0.999) {
      content = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: PaperMetrics.contentWidthFor(document.settings.marginMm),
          child: content,
        ),
      );
    }

    // كل العناصر العائمة تُرسم في طبقة **الصفحة** بإحداثياتها المطلقة:
    // فيصير موضعها حرًّا فعلًا في أي نقطة على الورقة (أعلى/أسفل/جوانب)،
    // وقابلةً للمس والسحب في أي مكان (اختبار الإصابة لا يتجاوز حدود الأب،
    // والطبقة بحجم الورقة كاملة)، وبنفس الإحداثيات في PDF و Word.
    final pageAttachments = <_AttachmentRef>[];
    final globalReferences =
        documentIr.floatingElements?.elements ?? const <FloatingElementReference>[];
    final globalElementIds = globalReferences.map((reference) => reference.id).toSet();
    final seenElementIds = <String>{};
    int resolvedPageIndex(FloatingElement element) => _elementGeometry(controller, element)
        .pageIndex
        .clamp(0, math.max(0, pageCount - 1))
        .toInt();

    for (final reference in globalReferences) {
      final element = document.floatingElementById(reference.id);
      if (element != null &&
          resolvedPageIndex(element) == page.index &&
          seenElementIds.add(reference.id)) {
        pageAttachments.add(_AttachmentRef.global(reference.id));
      }
    }

    void collect(QuestionBlock question) {
      for (final reference in question.attachments?.elements ??
          const <FloatingElementReference>[]) {
        if (globalElementIds.contains(reference.id) ||
            !seenElementIds.add(reference.id)) {
          continue;
        }
        pageAttachments.add(
          _AttachmentRef(
            questionIndex: question.index,
            elementId: reference.id,
          ),
        );
      }
      for (final branch in question.branches) {
        for (final reference in branch.attachments?.elements ??
            const <FloatingElementReference>[]) {
          if (globalElementIds.contains(reference.id) ||
              !seenElementIds.add(reference.id)) {
            continue;
          }
          pageAttachments.add(
            _AttachmentRef(
              questionIndex: branch.questionIndex,
              branchIndex: branch.index,
              elementId: reference.id,
            ),
          );
        }
      }
    }

    for (final blockId in page.blockIds) {
      final question = documentIr.questionById(blockId);
      if (question != null) collect(question);
    }
    // لا تعويض بـ«كل العناصر في الصفحة الأولى قبل القياس»: صفحة العنصر تأتي من
    // الخطة نفسها التي تحكم صفحة سؤاله، فإن لم تُحسم الخطة بعد بقي العنصر في
    // صفحته المحفوظة فقط (انظر ExamWizardController.questionRect).

    Widget buildBody({required bool highlighted}) {
      Widget body = Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned.fill(
            child: _buildPageStack(
              controller,
              page,
              pageCount,
              content,
              document,
              highlighted: highlighted,
              interactive: interactive,
            ),
          ),
          for (final ref in pageAttachments) ..._buildPageElement(controller, ref),
          // Controls are siblings in the page-sized hit-test area and painted
          // last so other attachments cannot cover them. Non-interactive render bypasses
          // them entirely because they are editor chrome, not paper content.
          if (interactive)
            for (final ref in pageAttachments)
              if (!_locked && _selectedAttachment?.elementId == ref.elementId)
                _buildAttachmentToolbar(ref, _findAttachment(document, ref)!),
        ],
      );
      if (interactive && _stagedFormula != null && !_locked) {
        body = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _placeStagedFormula(
            details.localPosition,
            pageIndex: page.index,
          ),
          child: body,
        );
      }
      return body;
    }

    final pageShell = Container(
      key: _pageCanvasKeys.putIfAbsent(
        page.index,
        () => GlobalKey(
          debugLabel: 'a4-page-canvas-${page.index}',
        ),
      ),
      width: ExamCanvasGeometry.width,
      height: ExamCanvasGeometry.height,
      clipBehavior: Clip.antiAlias,
      // إطار الشاشة (الظل والحدّ الرقيق) زينة عرض لا جزء من الورقة: الحدّ كان
      // داخل `decoration`، و`Container` يحسب `decoration.padding` (سماكة
      // الحدّ) حشوةً فعلية، فيضيق عمود النصّ 2px (1.5pt) عن عمود PDF على كل
      // صفحة — فينكسر السطر في موضع آخر (قِيس في preview_field_geometry_test).
      // الحدّ الآن في `foregroundDecoration`: يُرسم ولا يحجز مساحة.
      decoration: showPreviewChrome
          ? const BoxDecoration(
              color: Colors.white,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            )
          : const BoxDecoration(color: Colors.white),
      foregroundDecoration: showPreviewChrome
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
            )
          : null,
      child: KeyedSubtree(
        key: ValueKey<String>('a4-page-${page.index}'),
        child: interactive
            ? DragTarget<FloatingElement>(
                onWillAcceptWithDetails: (details) => !_locked,
                onAcceptWithDetails: (details) =>
                    _acceptFormulaDrop(page.index, details),
                builder: (context, candidates, _) =>
                    buildBody(highlighted: candidates.isNotEmpty),
              )
            : buildBody(highlighted: false),
      ),
    );

    return Directionality(
      textDirection: layout.textDirection,
      child: RepaintBoundary(child: pageShell),
    );
  }

  /// يهيّئ محتوى الصفحة (الإطار + الكتل + تذييل آخر صفحة) داخل الهوامش؛
  /// والعناصر العائمة طبقة مستقلة فوقه بإحداثيات الصفحة.
  ///
  /// صندوق المحتوى كله يُشتق من هامش واحد (`marginMm`) هو نفسه حشوة الإطار،
  /// فيبتعد النص عن الإطار بقدره دائماً. ولا ترقيم للصفحات إطلاقاً.
  ///
  /// الطبقة نفسها **بحجم الورقة كاملة** وتُدخل الهوامش على أبنائها: اختبار
  /// الإصابة في Flutter لا يتجاوز حدود الأب، فلو كانت الطبقة بحجم مساحة
  /// الطباعة لصار أي عنصر يسحبه المستخدم إلى هامش الورقة غير قابل للمس. الآن
  /// كل نقطة في الورقة قابلة للإصابة (والقصّ على حدود الورقة في [Container]).
  Widget _buildPageStack(
    ExamWizardController controller,
    CanonicalPagePlanPage page,
    int pageCount,
    Widget content,
    ExamDocument document, {
    required bool highlighted,
    required bool interactive,
  }) {
    final settings = document.settings;
    final margin = ExamCanvasGeometry.marginFor(settings.marginMm);
    // حدّ المتن السفلي من الخطة نفسها (لا من ارتفاع تذييل مقاس هنا).
    final bodyBottomPt = page.bodyBounds.top + page.bodyBounds.height;
    final bottomInsetPx = page.scaleFactor < 0.999
        ? LayoutUnits.ptToPx(page.pageHeightPt - bodyBottomPt)
        : 0.0;
    // صندوق صفحة كامل ⇒ كل العناصر العائمة قابلة للمس أينما وُضعت.
    Widget stack = Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        // الإطار خلف المحتوى: صورة PNG بحجم الورقة أو إطار متجه داخل الهامش.
        if (settings.pageBorder)
          Positioned.fill(
            child: IgnorePointer(child: _buildPageFrame(settings, margin)),
          ),
        // `bottom` يُترك مفتوحاً في الصفحة العادية كي لا يُضغط المحتوى لو
        // اختلف الحبر عن المتن بطول سطر واحد؛ وفي صفحة التصغير يُربط بحدّ
        // المتن المحسوب من الخطة.
        Positioned(
          top: margin,
          left: margin,
          right: margin,
          bottom: page.scaleFactor < 0.999 ? bottomInsetPx : null,
          child: content,
        ),
        // وجود التذييل قرار الخطة (آخر صفحة لا تُفترض من الفهرس).
        if (page.hasFooter)
          Positioned(
            left: margin,
            right: margin,
            bottom: margin,
            child: _buildFooterBlock(controller, interactive: interactive),
          ),
      ],
    );
    if (highlighted) {
      stack = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.accent, width: 1.6),
        ),
        child: stack,
      );
    }
    return stack;
  }

  /// إطار الصفحة: صورة PNG مختارة تغطي الورقة كاملة (وإن تعذّر فتحها يُرسم
  /// الإطار المتجه)، وإلا إطار متجه بسيط في منتصف المسافة بين الحافة والنص.
  Widget _buildPageFrame(PaperSettings settings, double margin) {
    final vector = Padding(
      padding: EdgeInsets.all(margin * 0.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: PaperStyles.ink, width: 1.4),
        ),
      ),
    );
    if (!settings.hasFrameImage) {
      return vector;
    }
    return Image.file(
      File(settings.frameImagePath!),
      fit: BoxFit.fill,
      errorBuilder: (context, error, stackTrace) => vector,
    );
  }

  /// تذييل آخر صفحة (للقراءة فقط). لا يُقاس هنا: موضعه وحجزه قرّرهما المحرك
  /// في الخطة، وهذا الودجت يرسم النصّ فقط.
  Widget _buildFooterBlock(
    ExamWizardController controller, {
    required bool interactive,
  }) {
    final document = controller.document;
    Widget footer = Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _headerSelected
              ? PaperStyles.primary.withOpacity(0.45)
              : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: PaperFooterView(
        semanticFooter: controller.documentIr.footer,
        style: document.header.style,
        defaultFont: document.settings.defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      ),
    );
    if (interactive) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _tapHeader,
        child: footer,
      );
    }
    return footer;
  }

  RenderBox? _pageRenderBox(int pageIndex) {
    final renderObject = _pageCanvasKeys[pageIndex]?.currentContext?.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize ? renderObject : null;
  }

  Offset? _localPositionOnPage(int pageIndex, Offset globalPosition) {
    final box = _pageRenderBox(pageIndex);
    return box?.globalToLocal(globalPosition);
  }

  ({int pageIndex, Offset local})? _pageAtGlobalPosition(Offset globalPosition) {
    final pageIndexes = _pageCanvasKeys.keys.toList()..sort();
    for (final pageIndex in pageIndexes) {
      final box = _pageRenderBox(pageIndex);
      if (box == null) continue;
      final local = box.globalToLocal(globalPosition);
      if (Rect.fromLTWH(0, 0, box.size.width, box.size.height).contains(local)) {
        return (pageIndex: pageIndex, local: local);
      }
    }
    return null;
  }

  /// يستقبل بطاقة معادلة أُفلتت على صفحة A4 ويقيمها في الموضع الدقيق.
  void _acceptFormulaDrop(
    int pageIndex,
    DragTargetDetails<FloatingElement> details,
  ) {
    final local = _localPositionOnPage(pageIndex, details.offset);
    if (local == null) return;
    // [DragTargetDetails.offset] موضع المؤشر العام لحظة الإفلات، فينزل
    // العنصر مركزاً تحته تماماً حيث أراد المستخدم.
    final board = _boardPositionFromLocal(
      local,
      width: details.data.width,
      height: details.data.height,
    );
    _dropFormulaOnPage(details.data, board.dx, board.dy, pageIndex: pageIndex);
  }

  /// يبني عنصراً عائماً في موضعه **المطلق** على الورقة (بكسل اللوحة كما كتبه
  /// المستخدم) فوق كل الكتل، فتكون الحركة والإقامة حرّة تماماً.
  Iterable<Widget> _buildPageElement(
    ExamWizardController controller,
    _AttachmentRef ref,
  ) sync* {
    final element = _findAttachment(controller.document, ref);
    if (element == null) {
      yield const SizedBox.shrink();
      return;
    }
    // [_buildAttachment] يعيد عنصراً موضعه `PositionedDirectional` بإحداثيات
    // الورقة نفسها: `dy` من أعلى الورقة، و`dx` من حافة القراءة — فطبقة الصفحة
    // تحمل الإحداثي المطلق بلا لفّ إضافي (ولفّه بـ Positioned يفسد بيانات
    // الأب في Stack).
    yield KeyedSubtree(
      key: ValueKey<String>('page-element-${element.id}'),
      child: _buildAttachment(controller, ref, element),
    );
  }

  /// يُنشئ المعادلة المسحوبة من الشريط في موضع الإفلات على صفحة [pageIndex].
  bool _dropFormulaOnPage(
    FloatingElement element,
    double dx,
    double dy, {
    required int pageIndex,
  }) {
    final controller = _controller;
    if (controller == null) {
      return false;
    }
    final owner = _selectedOwnerQuestionId();
    final ownerRect = owner == null ? null : _pagePlan?.questionRectPx(owner);
    final placed = element.copyWith(
      dx: ownerRect == null ? dx : math.max(0, dx - ExamCanvasGeometry.marginFor(controller.document.settings.marginMm)),
      dy: ownerRect == null ? dy : math.max(0, dy - ownerRect.top),
      pageIndex: ownerRect?.pageIndex ?? pageIndex,
    );
    final added = controller.addFloatingElement(
      placed,
      pageIndex: placed.pageIndex,
      ownerQuestionId: owner,
    );
    if (!added) {
      _showMessage('تعذر إدراج المعادلة في هذه الصفحة.');
      return false;
    }
    setState(() {
      _stagedFormula = null;
      _stagedFormulaIsBlock = false;
      _selectedAttachment = _AttachmentRef.global(placed.id);
    });
    _showMessage(
      owner == null
          ? 'أُدرجت المعادلة — اسحبها بحرية بين صفحات الورقة.'
          : 'أُدرجت المعادلة داخل السؤال المحدد — حركتها محصورة فيه.',
    );
    return true;
  }

  // ------------------------------------------------------------------
  // الترويسة — قابلة للتحرير والتحديد والتنسيق
  // ------------------------------------------------------------------

  /// الترويسة بثلاثة أعمدة (للقراءة فقط على الورقة): النقر يحدّدها لتنسيقها
  /// من الشريط، وزر «تعديل» الظاهر عند تحديدها يفتح ورقة تعديل بيانات
  /// الترويسة والتذييل بتلميحات إرشادية لكل حقل.
  Widget _buildHeaderBlock(ExamWizardController controller) {
    final document = controller.document;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _tapHeader,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
            color: _headerSelected
                ? PaperStyles.primary.withOpacity(0.45)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: <Widget>[
            PaperHeaderView(
              semanticHeader: controller.documentIr.header,
              style: document.header.style,
              defaultFont: document.settings.defaultFont,
              fontScale: _fontScale,
              heightScale: _heightScale,
            ),
            // أداة تحرير فقط (لا تُطبع ولا تغيّر ارتفاع الكتلة).
            if (_headerSelected)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: IconButton(
                  tooltip: 'تعديل الترويسة والتذييل',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _editHeaderAndFooter,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ورقة تعديل بيانات الترويسة والتذييل: النموذجان نفسهما في الخطوة 1،
  /// وكل تعديل يُطبَّق مباشرة على الورقة (وتتبعه إعادة التقسيم الورقي).
  Future<void> _editHeaderAndFooter() async {
    final controller = _controller!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'تعديل الترويسة والتذييل',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              HeaderForm(
                initial: controller.document.header,
                onChanged: (header) =>
                    controller.updateHeader(header, coalesceKey: 'header-form'),
              ),
              const SizedBox(height: 20),
              FooterForm(
                initial: controller.document.footer,
                onChanged: (footer) =>
                    controller.updateFooter(footer, coalesceKey: 'footer-form'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // السؤال الكامل (كتلة لا تتجزأ) وفروعه
  // ------------------------------------------------------------------

  /// سطر عنوان (سؤال أو فرع) بلا طفح مهما كبر خط الورقة: تسمية الرقم والدرجة
  /// محدودتان بنسبة من عرض السطر فتتلفّفان داخل حدودهما، ويبقى لمنطوق السؤال
  /// وأزرار الإجراءات مكانه. الحد الأقصى لا يغيّر العرض العادي: لا أثر له إلا
  /// إذا تجاوز المحتوى عرض السطر فعلاً.
  /// الشريط الذي يحمل أدوات السؤال **والفرع** خارج الورقة.
  ///
  /// فصل صريح بين هندسة الورق المطبوعة وواجهة التحكم: الشريط لا يدخل
  /// `_buildQuestionBlock`/`_buildBranchBody` ولا يشارك في قياس أي صفّ، فلا
  /// يغيّر ارتفاع العنوان ولا عرض المنطوق ولا هوامش الصفحة (ولا يعرف عنه
  /// المحرك أو PDF شيئاً).
  ///
  /// الهدف: مساحة لمس 48dp (الحدّ الأدنى في Material) على شاشة الهاتف، بدل
  /// أزرار كانت تُسحق إلى 31px/40px داخل صفوف ارتفاعها من الخطة. الشريط
  /// أفقي قابل للتمرير، فيبقى كل زرّ 48dp حتى على شاشة ضيقة بدل أن يُصغَّر.
  ///
  /// كل مجموعة تعمل على هدفها وحده: أدوات السؤال على السؤال المستهدف، وأدوات
  /// الفرع على فرع واحد محدَّد/نشط (أو الفرع الوحيد في السؤال) — وإلا تُعطَّل
  /// بدل أن تعمل على عنصر لم يقصده المستخدم.
  /// Equivalent access to existing optional source fields when the print
  /// contract deliberately gives their owner no ink or hit box. No placeholder
  /// is inserted into the page; persistent IDs survive popup/model changes.
  Widget _buildCandidateEmptyFields(ExamWizardController controller) {
    final document = controller.document;
    final entries = <({String key, String label})>[];
    for (var q = 0; q < document.questions.length; q++) {
      final question = document.questions[q];
      final name = 'السؤال ${document.formatNumber(q + 1)}';
      if (question.statement.trim().isEmpty) entries.add((key: _statementKey(question.id), label: '$name — المنطوق'));
      if (question.body.trim().isEmpty) entries.add((key: _bodyKey(question.id), label: '$name — النص الاختياري'));
      for (var b = 0; b < question.branches.length; b++) {
        final branch = question.branches[b];
        final name = 'السؤال ${document.formatNumber(q + 1)} — الفرع ${document.formatNumber(b + 1)}';
        if (branch.content.statement.trim().isEmpty) entries.add((key: _branchStatementKey(branch.id), label: '$name — المنطوق'));
        if (branch.content.body.trim().isEmpty) entries.add((key: _branchBodyKey(branch.id), label: '$name — النص الاختياري'));
      }
    }
    return SizedBox(width: 48, height: 48, child: PopupMenuButton<String>(
      key: const ValueKey<String>('canonical-empty-fields'),
      tooltip: 'تحرير حقل غير مطبوع', icon: const Icon(Icons.edit_note),
      enabled: !_locked && !_isBusy && !_multiSelect && entries.isNotEmpty,
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        for (final entry in entries) PopupMenuItem<String>(
          key: ValueKey<String>('canonical-empty-${entry.key}'), value: entry.key,
          height: 48, child: Text(entry.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
      onSelected: (key) {
        final owner = _candidateOptionalBinding(controller, fieldKey: key);
        if (owner == null) return;
        final binding = owner.binding;
        _canonicalEditorOpen = true;
        _canonicalEditorPageHint = null;
        _activateField(key, _field(key, binding.sourceText, binding.onEdit));
      },
    ));
  }

  Widget _buildQuestionActionsBar(ExamWizardController controller) {
    final index = _actionQuestionIndex();
    final branchRef = _actionBranchRef();
    final questionEnabled = index != null && !_locked && !_isBusy;
    final branchEnabled = branchRef != null && !_locked && !_isBusy;
    final question = index == null ? null : controller.questions[index];
    final branch = branchRef == null ? null : controller.document.branchAt(branchRef);

    Widget button({
      required String key,
      required IconData icon,
      required String tooltip,
      required bool enabled,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        key: ValueKey<String>(key),
        iconSize: 20,
        // 48dp صريحة: لا تعتمد على الحشوة الافتراضية ولا على visualDensity.
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.all(8),
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: enabled ? onPressed : null,
      );
    }

    final PointsOwner? editOwner = _multiSelect ? null
        : _selectedBranches.length == 1
            ? PointsOwner.branch(_selectedBranches.single)
            : _selectedQuestions.length == 1 && index != null
                ? PointsOwner.question(index) : null;

    Widget divider() => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 28,
            width: 1,
            child: ColoredBox(color: Color(0x22000000)),
          ),
        );

    final label = question == null
        ? 'حدّد سؤالاً واحداً لتحرير أدواته'
        : branch == null
            ? 'أدوات السؤال ${controller.document.formatNumber(index! + 1)}'
            : 'أدوات السؤال ${controller.document.formatNumber(index! + 1)} — الفرع ${branchRef!.branchIndex + 1}';

    return Material(
      key: const ValueKey<String>('question-actions-bar'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    if (_separateEditorCandidate) _buildCandidateEmptyFields(controller),
                    button(
                      key: 'question-action-edit-body',
                      icon: Icons.edit_note,
                      tooltip: 'تحرير نص السؤال أو الفرع',
                      enabled: editOwner != null && !_locked && !_isBusy,
                      onPressed: () => _editOwnerBody(editOwner!),
                    ),
                    button(
                      key: 'question-action-add-point',
                      icon: Icons.add,
                      tooltip: 'إضافة نقطة',
                      enabled: editOwner != null && !_locked && !_isBusy,
                      onPressed: () => controller.addPoint(editOwner!),
                    ),
                    button(
                      key: 'question-action-add-branch',
                      icon: Icons.add,
                      tooltip: 'إضافة فرع',
                      enabled: questionEnabled,
                      onPressed: () => controller.addBranch(index!),
                    ),
                    button(
                      key: 'question-action-duplicate',
                      icon: Icons.copy_outlined,
                      tooltip: 'نسخ السؤال',
                      enabled: questionEnabled,
                      onPressed: () => controller.duplicateQuestion(index!),
                    ),
                    if (controller.questions.length > 1)
                      button(
                        key: 'question-action-delete',
                        icon: Icons.delete_outline,
                        tooltip: 'حذف السؤال',
                        enabled: questionEnabled,
                        onPressed: () => _confirmDeleteQuestion(index!),
                      ),
                    if (_separateEditorCandidate) ...<Widget>[
                      button(key: 'question-action-label', icon: Icons.numbers,
                        tooltip: 'رقم السؤال', enabled: questionEnabled,
                        onPressed: () => _editQuestionLabel(index!)),
                      button(key: 'question-action-marks', icon: Icons.grade_outlined,
                        tooltip: 'درجة السؤال', enabled: questionEnabled,
                        onPressed: () => _editQuestionMarks(index!)),
                    ],
                    divider(),
                    if (_separateEditorCandidate) ...<Widget>[
                      button(key: 'branch-action-label', icon: Icons.numbers,
                        tooltip: 'رقم الفرع', enabled: branchEnabled,
                        onPressed: () => _editBranchLabel(branchRef!)),
                      button(key: 'branch-action-marks', icon: Icons.grade_outlined,
                        tooltip: 'درجة الفرع', enabled: branchEnabled,
                        onPressed: () => _editBranchMarks(branchRef!)),
                    ],
                    button(
                      key: 'branch-action-duplicate',
                      icon: Icons.copy_all_outlined,
                      tooltip: 'نسخ الفرع',
                      enabled: branchEnabled,
                      onPressed: () => controller.duplicateBranch(branchRef!),
                    ),
                    button(
                      key: 'branch-action-equation',
                      icon: Icons.functions,
                      tooltip: 'إدراج/تحرير معادلة',
                      enabled: branchEnabled,
                      onPressed: () => _editEquationInField(
                        _branchStatementKey(controller.document
                            .branchAt(branchRef!)
                            .id),
                      ),
                    ),
                    button(
                      key: 'branch-action-delete',
                      icon: Icons.delete_outline,
                      tooltip: 'حذف الفرع',
                      enabled: branchEnabled,
                      onPressed: () => controller.removeBranch(branchRef!),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Existing optional body field, edited with the SAME source controller.
  /// Its empty placeholder and add-point action must never enter printed flow.
  Future<void> _editOwnerBody(PointsOwner owner) async {
    final controller = _controller!;
    final branchRef = owner.isBranch ? BranchRef(
      questionIndex: owner.questionIndex, branchIndex: owner.branchIndex!) : null;
    final questionId = controller.questions[owner.questionIndex].id;
    final branchId = branchRef == null ? null : controller.document.branchAt(branchRef).id;
    final fieldKey = branchId == null ? _bodyKey(questionId) : _branchBodyKey(branchId);
    final initial = branchRef == null ? controller.questions[owner.questionIndex].body
        : controller.document.branchAt(branchRef).content.body;
    final field = _field(fieldKey, initial, (value) {
      if (_separateEditorCandidate) {
        _writeCanonicalSource(fieldKey, value);
      } else if (branchRef == null) {
        controller.updateQuestionBody(owner.questionIndex, value);
      } else {
        controller.updateBranchBody(branchRef, value);
      }
    });
    if (_separateEditorCandidate) {
      _canonicalEditorOpen = true;
      _activateField(fieldKey, field);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider<ExamWizardController>.value(
        // Dialog routes are above this screen's provider in Navigator. Reuse
        // its existing owner; .value must NOT dispose the shared controller.
        value: controller,
        child: AlertDialog(
          title: Text(branchRef == null ? 'نص السؤال' : 'نص الفرع'),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Consumer<ExamWizardController>(
                  builder: (context, current, _) {
                    final question = current.documentIr.questionById(questionId);
                    final content = branchId == null
                        ? question?.body?.content
                        : question?.branches.where((b) => b.id == branchId).firstOrNull?.body?.content;
                    final model = current.questions[owner.questionIndex];
                    final style = branchRef == null
                        ? model.style : current.document.branchAt(branchRef).style;
                    return _paperField(
                      fieldKey: fieldKey,
                      controller: field,
                      matchPrintedTextWidth: false,
                      minimumInteractiveHeight: 48,
                      style: PaperStyles.resolve(
                        branchRef == null ? PaperStyles.prompt : PaperStyles.body(current.document.layout),
                        style.copyWith(color: () => null),
                        defaultFont: current.document.settings.defaultFont,
                        fontScale: _fontScale,
                        heightScale: _heightScale,
                      ),
                      semanticContent: content,
                      hint: branchRef == null ? 'نص السؤال (اختياري)' : 'نص الفرع (اختياري)',
                    );
                  },
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// الفرع الذي تعمل عليه أدوات الفرع.
  ///
  /// ترتيب الحسم: تحديد صريح لفرع واحد ← الفرع النشط في المتحكم ← الفرع
  /// الوحيد في السؤال المستهدف (حالته لا تحتمل اللبس). غير ذلك `null`، فتبقى
  /// الأزرار معطّلة بدل أن تحذف أو تنسخ فرعاً لم يقصده المستخدم.
  BranchRef? _actionBranchRef() {
    final controller = _controller;
    if (controller == null) return null;
    final document = controller.document;
    if (_selectedBranches.length == 1) {
      final ref = _selectedBranches.single;
      if (document.containsRef(ref)) return ref;
    }
    if (_selectedBranches.length > 1) return null;
    final selected = controller.selectedBranch;
    if (selected != null && document.containsRef(selected)) return selected;
    final questionIndex = _actionQuestionIndex();
    if (questionIndex == null) return null;
    final branches = controller.questions[questionIndex].branches;
    if (branches.length == 1) {
      return BranchRef(questionIndex: questionIndex, branchIndex: 0);
    }
    return null;
  }

  /// السؤال الذي تعمل عليه أدوات الشريط: التحديد الصريح أولاً، ثم سؤال الفرع
  /// المحدَّد، ثم السؤال النشط (الذي حقلُه محرَّر). يعيد `null` عند التعدد أو
  /// الغياب — فلا تعمل الأدوات على سؤال لم يقصده المستخدم.
  int? _actionQuestionIndex() {
    final controller = _controller;
    if (controller == null || controller.questions.isEmpty) {
      return null;
    }
    if (_selectedQuestions.length > 1) {
      return null;
    }
    if (_selectedBranches.length > 1) {
      return null;
    }
    final targets = _questionSpacingTargets();
    if (targets.length != 1) {
      return null;
    }
    final index = targets.single;
    return index >= 0 && index < controller.questions.length ? index : null;
  }

  Widget _titleRow({
    required Widget dragHandle,
    required Widget label,
    required Widget statement,
    required Widget marks,
    // أدوات الصفّ **للفرع فقط** حالياً. صفّ السؤال لا يمرّر شيئاً: أدواته في
    // شريط خارج الورقة (§19.15) كي لا تحدّد هندسته.
    List<Widget> actions = const <Widget>[],
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            dragHandle,
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.34),
              child: label,
            ),
            const SizedBox(width: VisualMetrics.titleGapPx),
            Expanded(child: statement),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.26),
              child: marks,
            ),
            ...actions,
          ],
        );
      },
    );
  }

  /// يقيّد صفّاً في كتلة الورقة بارتفاعه من الخطة حين يكون معروفاً.
  ///
  /// الأدوات المضمّنة في الصفّ (أزرار تحرير) لا يجوز أن تحدّد ارتفاع الورقة:
  /// الخطة وPDF يحسبان ارتفاع الصفّ من أسطره. تقييد الصفّ يترك الأدوات في
  /// مكانها (وتُقيَّد هي نفسها بالارتفاع) بلا حشوة تعويضية ولا تغيير قياس.
  Widget _planRowHeight({required Widget child, double? heightPt}) {
    if (heightPt == null || heightPt <= 0) return child;
    return SizedBox(height: LayoutUnits.ptToPx(heightPt), child: child);
  }

  /// لاحقة مفاتيح ودجت المقطع الجاري بناؤه (`/sliceN` أو فارغة).
  ///
  /// تُضبط أثناء بناء مقطع التكملة وحده: الحقول تشترك في المتحكمات نفسها (§19.9)
  /// ولا يجوز أن تتكرّر مفاتيحها في الشجرة. البناء متزامن، وتُعاد القيمة إلى
  /// سابقتها في `finally` فلا تتسرّب إلى كتلة أخرى.
  String _sliceKeySuffix = '';

  /// مقطع سؤال على صفحة: **نافذة** من الكتلة الكاملة، بهندسة الخطة.
  ///
  /// الارتفاع وإزاحة البداية من الخطة (نقاط ← بكسل)، والكتلة المبنية هي نفسها
  /// التي تُبنى في صفحة البداية وبنفس المتحكمات: لكل حقل مصدر نصّي واحد،
  /// والمقاطع عروض متزامنة له — لا محرّر ثانٍ ولا نسخ نصّ.
  Widget _buildQuestionFragmentSlice(
    CanonicalPagePlanFragment fragment,
    Widget block,
    String suffix,
  ) {
    final offsetPx = LayoutUnits.ptToPx(fragment.sourceTopPt);
    final heightPx = LayoutUnits.ptToPx(fragment.heightPt);
    return SizedBox(
      key: ValueKey<String>('page-slice-${fragment.questionId}$suffix'),
      height: heightPx,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.translate(
            key: ValueKey<String>('page-slice-offset-${fragment.questionId}$suffix'),
            offset: Offset(0, -offsetPx),
            child: block,
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    QuestionBlock data, {
    /// لاحقة مفاتيح ودجت مقطع التكملة (`/sliceN`)؛ فارغة في مقطع البداية.
    String sliceSuffix = '',

    /// ارتفاع صفّ العنوان من الخطة (نقاط) — يقود الورقة بدل ارتفاع الأدوات.
    double? titleHeightPt,

    /// الخطة: تُستعمل لارتفاعات صفوف العناوين (السؤال وفروعه) فقط.
    CanonicalPagePlan? plan,
  }) {
    final document = controller.document;
    final question = document.questions[data.index];
    final questionIndex = data.index;
    final selected = _isQuestionSelected(questionIndex);
    final defaultFont = document.settings.defaultFont;
    final bodyStyle = question.style.copyWith(color: () => null);
    final titleStyle = PaperStyles.resolve(
      PaperStyles.question,
      question.style.copyWith(color: () => question.effectiveTitleColor),
      defaultFont: defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final textStyle = PaperStyles.resolve(
      PaperStyles.prompt,
      bodyStyle,
      defaultFont: defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final paragraphSpacing = question.style.paragraphSpacing;
    // الفجوات من العقد البصري الوحيد (لا أرقام محلية تُنحرف عن PDF وWord).
    final blockSpacing = paragraphSpacing ?? VisualMetrics.elementGapPx;
    final itemSpacing = paragraphSpacing ?? VisualMetrics.itemGapPx;
    final owner = PointsOwner.question(questionIndex);
    final statementKey = _statementKey(question.id);
    final bodyKey = _bodyKey(question.id);

    Widget block = Column(
      key: ValueKey<String>('question-block-${question.id}$sliceSuffix'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // عنوان قسم السؤال: نص قابل للتحرير مباشرة على الورقة.
        if (data.category != null)
          _paperField(
            fieldKey: _categoryKey(question.id),
            onLongPress: () => _longPressQuestion(questionIndex),
            controller: _field(
              _categoryKey(question.id),
              question.category,
              (value) => controller.updateQuestionCategory(questionIndex, value),
            ),
            style: _scaled(PaperStyles.category),
            textAlign: _textAlignFor(_categoryKey(question.id), fallback: TextAlign.start),
            hint: 'عنوان القسم...',
            semanticContent: data.category!.content,
          ),
        // سطر العنوان: الرقم ← المنطوق ← الدرجة «(٢٠ درجة)» في سطر واحد.
        //
        // الصفّ **هندسة ورق مطبوعة**: لا يحمل أدوات تحرير إطلاقاً (§19.12،
        // §19.15). أدوات السؤال (إضافة فرع/نسخ/حذف) انتقلت إلى شريط في واجهة
        // التطبيق خارج الورقة: داخل الصف كانت تفرض ارتفاعاً 40px على صفّ
        // ارتفاعه 23.25pt وتأكل ~113px من عرض المنطوق فيلتفّ سطرين بينما
        // الخطة وPDF يبقيانه سطراً واحداً. ومع ذلك يبقى `_planRowHeight` حدّاً
        // حارساً: ارتفاع الصفّ من الخطة لا من أطول ودجة فيه.
        _planRowHeight(
          heightPt: titleHeightPt,
          child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _tapQuestion(questionIndex),
          child: _titleRow(
            dragHandle: _locked
                    ? Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: Colors.grey.shade300,
                      )
                    : LongPressDraggable<int>(
                        data: questionIndex,
                        feedback: Material(
                          elevation: 4,
                          color: Colors.white,
                          child: Container(
                            width: 320,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _readableInlineContent(
                                _feedbackTitleContent(data.title),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _scaled(PaperStyles.question),
                            ),
                          ),
                        ),
                        childWhenDragging: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: Colors.grey.shade300,
                        ),
                        child: Semantics(
                          label: 'اضغط مطولاً واسحب لنقل السؤال كاملاً',
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
            label: Tooltip(
              message: 'انقر لتعديل رقم السؤال',
              child: GestureDetector(
                onTap: () => _editQuestionLabel(questionIndex),
                child: _semanticInline(data.title.labelContent, titleStyle),
              ),
            ),
            statement: _paperField(
              fieldKey: statementKey,
              onLongPress: () => _longPressQuestion(questionIndex),
              controller: _field(
                statementKey,
                question.statement,
                (value) => controller.updateQuestionStatement(questionIndex, value),
              ),
              style: titleStyle,
              textAlign: _textAlignFor(
                statementKey,
                fallback: PaperStyles.toTextAlign(
                  question.titleAlign ?? question.style.align,
                ),
              ),
              hint: layout.isLtr
                  ? 'Question statement...'
                  : 'اكتب منطوق السؤال هنا...',
              semanticContent: data.content,
            ),
            marks: _marksTarget(
              marks: data.title.marks,
              showPlaceholder: document.settings.showQuestionMarks,
              style: titleStyle,
              onEdit: () => _editQuestionMarks(questionIndex),
            ),
          ),
          ),
        ),
        // نص السؤال الفارغ يحرّر من الشريط، ولا يحجز مساحة مطبوعة.
        if (data.body != null) ...<Widget>[
          if (blockSpacing > 0) SizedBox(height: blockSpacing),
          _paperField(
            fieldKey: bodyKey,
            onLongPress: () => _longPressQuestion(questionIndex),
            controller: _field(
              bodyKey,
              question.body,
              (value) => controller.updateQuestionBody(questionIndex, value),
            ),
            style: textStyle,
            textAlign: _textAlignFor(
              bodyKey,
              fallback: PaperStyles.toTextAlign(
                question.bodyAlign ?? question.style.align,
              ),
            ),
            hint: layout.isLtr
                ? 'Question text (optional)...'
                : 'نص السؤال (اختياري) — يُحذف من الورقة إن تُرك فارغاً',
            semanticContent: data.body?.content,
          ),
        ],
        // نقاط السؤال المباشرة (١-، ٢-، ٣-...) بأنواعها المختلطة وتسلسلها المتصل.
        for (var index = 0; index < data.points.length; index++) ...<Widget>[
          if ((index == 0 ? blockSpacing : itemSpacing) > 0)
            SizedBox(height: index == 0 ? blockSpacing : itemSpacing),
          _pointRow(
            controller,
            owner,
            data.points[index],
            textStyle,
            PaperStyles.toTextAlign(question.style.align),
          ),
        ],
        // السؤال الجديد يبدأ بلا فروع؛ تُنشأ فقط بطلب صريح (زر +).
        if (question.branches.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 44, top: 2, bottom: 2),
            child: Text(
              layout.isLtr
                  ? 'No branches yet — tap + to add one.'
                  : 'لا فروع بعد — انقر + لإضافة فرع.',
              style: PaperStyles.hint(textStyle),
            ),
          ),
        for (final branch in data.branches) ...<Widget>[
          if (blockSpacing > 0) SizedBox(height: blockSpacing),
          _buildBranchBlock(controller, layout, branch, plan),
        ],
        if (question.dividerAfter != null)
          _buildDividerWidget(
            key: 'q:${question.id}',
            divider: question.dividerAfter!,
            onDelete: () => controller.setQuestionDivider(questionIndex, null),
            onThicken: () => controller.setQuestionDivider(
              questionIndex,
              question.dividerAfter!.copyWith(
                thickness: question.dividerAfter!.thickness >= 3 ? 1.2 : 3,
              ),
            ),
            onCycleWidth: () => controller.setQuestionDivider(
              questionIndex,
              question.dividerAfter!.copyWith(
                widthFraction: _nextDividerWidth(question.dividerAfter!.widthFraction),
              ),
            ),
          ),
      ],
    );

    // Keep the render/widget ancestry stable when focus selects a question.
    // Inserting wrappers here used to dispose PaperField's FocusNode while
    // a tap was opening rich text or the keyboard was entering text.
    block = Container(
      padding: EdgeInsets.all(
        question.showFrame ? VisualMetrics.questionFramePaddingPx : 0,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: question.showFrame ? PaperStyles.ink : Colors.transparent,
          width: question.showFrame ? 1 : 0,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: block,
    );
    // مؤشّر التحديد **لا يغيّر الهندسة**: كان `padding: EdgeInsets.all(1)`
    // عند التحديد يضيّق عمود نصّ السؤال 2px (1.5pt)، فينكسر السطر في موضع
    // آخر ما دام السؤال محدَّداً/قيد التحرير ثم يعود عند إلغاء التحديد —
    // وهو بالضبط نوع الاختلاف الذي تُلاحقه بوابة preview_field_geometry.
    // فيُرسم الإطار كطبقة عليا (بلا حشوة) داخل `Stack` موجود في الحالتين،
    // فلا تتغيّر سلسلة العناصر التي يعتمد عليها ثبات التركيز والكتابة.
    block = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        block,
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: PaperStyles.primary.withOpacity(0.45),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );

    // حافظ على حجز المساحة للمرفقات القديمة فقط. العناصر المسجّلة على
    // مستوى المستند لا تغيّر ارتفاع السؤال عند سحبها.
    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final questionAttachments = _attachmentModels(
      document,
      data.attachments,
      questionIndex: questionIndex,
    );
    final minHeight = _legacyAttachmentMinHeight(questionAttachments, globalIds);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, minWidth: double.infinity),
      // الضغط المطوّل في أي موضع من كتلة السؤال (بما فيها الفراغات والنقاط
      // وأرقامها، وحقول النص غير المفعّلة) يفتح وضع التحديد المتعدد ويحدد
      // السؤال — بلا تعارض مع سحب المقبض (LongPressDraggable أعمق فيفوز)
      // ولا مع تأشير النص داخل حقل قيد التحرير.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _longPressQuestion(questionIndex),
        child: block,
      ),
    );
  }

  /// درجة سطر العنوان «(٢٠ درجة)»: نقرة تفتح إدخال الرقم الخام فقط. وحين
  /// لا درجة تظهر أداة «+ درجة» (أداة تحرير لا تُطبع) إن كانت الدرجات مفعّلة.
  Widget _semanticInline(
    InlineContent content,
    TextStyle style, {
    TextAlign textAlign = TextAlign.start,
  }) =>
      TexText.fromRichContent(
        content.richContent,
        style: style,
        mathTextStyle: style,
        textAlign: textAlign,
        expandToWidth: false,
      );

  Widget _marksTarget({
    required MarksNode? marks,
    required bool showPlaceholder,
    required TextStyle style,
    required VoidCallback onEdit,
  }) {
    if (marks != null) {
      return Tooltip(
        message: 'انقر لتعديل الدرجة',
        child: GestureDetector(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: _semanticInline(InlineContent(<InlineNode>[marks]), style),
          ),
        ),
      );
    }
    if (!showPlaceholder) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'إضافة درجة',
      child: GestureDetector(
        onTap: onEdit,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('+ درجة', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ),
      ),
    );
  }

  List<FloatingElement> _attachmentModels(
    ExamDocument document,
    AttachmentBlock? attachments, {
    required int questionIndex,
    int? branchIndex,
  }) {
    if (attachments == null) return const <FloatingElement>[];
    final models = <FloatingElement>[];
    for (final reference in attachments.elements) {
      final element = _findAttachment(
        document,
        _AttachmentRef(
          questionIndex: questionIndex,
          branchIndex: branchIndex,
          elementId: reference.id,
        ),
      );
      if (element != null) models.add(element);
    }
    return models;
  }

  double _legacyAttachmentMinHeight(
    Iterable<FloatingElement> attachments,
    Set<String> globalIds,
  ) {
    var minHeight = 0.0;
    for (final element in attachments) {
      if (globalIds.contains(element.id)) {
        continue;
      }
      final bottom = element.dy + element.height;
      if (bottom > minHeight) {
        minHeight = bottom;
      }
    }
    return minHeight;
  }

  Future<void> _confirmDeleteQuestion(int index) async {
    final controller = _controller!;
    final label = controller.document.displayQuestionLabel(controller.questions[index]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السؤال'),
        content: Text('هل تريد حذف $label بجميع فروعه ومرفقاته؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.removeQuestion(index);
      setState(_clearSelection);
    }
  }

  Widget _buildBranchBlock(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchBlock data,
    CanonicalPagePlan? plan,
  ) {
    final ref = BranchRef(
      questionIndex: data.questionIndex,
      branchIndex: data.index,
    );
    final branch = controller.document.branchAt(ref);
    final selected = _isBranchSelected(ref);

    // مقبض السحب وحده يبدأ السحب (حتى لا يتعارض مع تحديد النص في الحقول)؛
    // الهدف هو كتلة الفرع كاملة.
    final dragHandle = _locked
            ? Icon(
                Icons.drag_indicator,
                size: 16,
                color: Colors.grey.shade300,
              )
            : LongPressDraggable<BranchRef>(
                data: ref,
                feedback: Material(
                  elevation: 4,
                  color: Colors.white,
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.all(8),
                    // معاينة السحب تُعرض نصاً مقروءاً: لا كود LaTeX حتى في
                    // العنصر العائم أثناء السحب.
                    child: Text(
                      _readableInlineContent(
                        _feedbackTitleContent(
                          data.title,
                          includeMarks: false,
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _scaled(PaperStyles.body(layout)),
                    ),
                  ),
                ),
                childWhenDragging: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: Colors.grey.shade300,
                ),
                // لا Tooltip هنا: مُعرِّف الضغط المطوّل الخاص به يتنافس مع بدء السحب.
                child: Semantics(
                  label: 'اضغط مطولاً واسحب لنقل الفرع أو تبديل محتواه مع فرع آخر',
                  child: Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              );

    return DragTarget<BranchRef>(
      key: ValueKey<String>('branch-target-${branch.id}'),
      onWillAcceptWithDetails: (details) => !_locked && details.data != ref,
      onAcceptWithDetails: (details) {
        final from = details.data;
        if (from.questionIndex == ref.questionIndex) {
          // داخل السؤال نفسه: نقل وإعادة ترميز (المحتوى كما هو).
          controller.moveBranch(ref.questionIndex, from.branchIndex, ref.branchIndex);
        } else {
          // بين سؤالين: تبديل المحتوى والدرجة فقط (العناوين ثابتة).
          controller.swapBranchContent(from, ref);
        }
      },
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        Widget body = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _tapBranch(ref),
          onLongPress: () => _longPressBranch(ref),
          child: Container(
            // إزاحة الفرع عن بداية السؤال من العقد البصري (26px): تُطبَّق
            // مرة واحدة هنا فيحاذي عنوان الفرع ونصه ونقاطه ما يطبعه PDF
            // وWord بنفس الرقم — لا 4px حشوةً تُضاف فوقها.
            padding: EdgeInsets.zero,
            color: highlighted ? const Color(0x1A2563EB) : null,
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: highlighted
                    ? PaperStyles.accent
                    : selected
                        ? PaperStyles.primary.withOpacity(0.45)
                        : Colors.transparent,
                width: highlighted ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _buildBranchBody(
              controller,
              layout,
              ref,
              data,
              dragHandle,
              isSelected: selected,
              plan: plan,
            ),
          ),
        );
        body = Container(
          padding: EdgeInsets.all(
            branch.showFrame ? VisualMetrics.branchFramePaddingPx : 0,
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: branch.showFrame ? PaperStyles.ink : Colors.transparent,
              width: branch.showFrame ? 0.8 : 0,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: body,
        );
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: VisualMetrics.branchIndentPx),
          child: body,
        );
      },
    );
  }

  /// الفرع بنفس بنية السؤال: الرقم ← المنطوق ← الدرجة (سطر واحد) ← النص (يُحذف
  /// كلياً عند فراغه) ← النقاط المرقّمة بأنواعها المختلطة.
  Widget _buildBranchBody(
    ExamWizardController controller,
    SubjectLayoutTemplate layout,
    BranchRef ref,
    BranchBlock data,
    Widget dragHandle, {
    required bool isSelected,
    CanonicalPagePlan? plan,
  }) {
    final document = controller.document;
    final branch = document.branchAt(ref);
    final content = branch.content;
    final bodyStyle = PaperStyles.resolve(
      PaperStyles.body(layout),
      branch.style,
      defaultFont: document.settings.defaultFont,
      fontScale: _fontScale,
      heightScale: _heightScale,
    );
    final paragraphSpacing = branch.style.paragraphSpacing;
    final firstItemSpacing = paragraphSpacing ?? VisualMetrics.branchGapPx;
    final itemSpacing = paragraphSpacing ?? VisualMetrics.itemGapPx;
    final statementKey = _branchStatementKey(branch.id);
    final bodyKey = _branchBodyKey(branch.id);
    final owner = PointsOwner.branch(ref);
    final branchAlign = PaperStyles.toTextAlign(branch.style.align);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // صفّ عنوان الفرع هندسة ورق مثل صفّ السؤال: ارتفاعه من الخطة، وأدواته
        // (نسخ/معادلة/حذف) في الشريط خارج الورقة (§19.15).
        _planRowHeight(
          heightPt: plan?.branchTitleHeightPtOf(data.questionId, data.id),
          child: _titleRow(
          dragHandle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: dragHandle,
          ),
          label: Tooltip(
            message: 'انقر لتعديل رقم الفرع',
            child: GestureDetector(
              onTap: () => _editBranchLabel(ref),
              child: _semanticInline(
                data.title.labelContent,
                bodyStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          statement: _paperField(
            fieldKey: statementKey,
            onLongPress: () => _longPressBranch(ref),
            controller: _field(
              statementKey,
              content.statement,
              (value) => controller.updateBranchStatement(ref, value),
            ),
            style: bodyStyle,
            textAlign: _textAlignFor(statementKey, fallback: branchAlign),
            hint: layout.isLtr ? 'Branch statement...' : 'اكتب منطوق الفرع هنا...',
            mushafStyle: true,
            semanticContent: data.content,
          ),
          marks: _marksTarget(
            marks: data.title.marks,
            showPlaceholder: document.settings.showQuestionMarks,
            style: bodyStyle,
            onEdit: () => _editBranchMarks(ref),
          ),
        ),
        ),
        // نص الفرع الفارغ يحرّر من الشريط، ولا يحجز مساحة مطبوعة.
        if (data.body != null)
          Padding(
            // لا إزاحة إضافية: كتلة الفرع نفسها مُزاحة عن السؤال بمقدار
            // `branchIndentPx`، ونص الفرع يأخذ الإزاحة نفسها في PDF وWord.
            padding: EdgeInsetsDirectional.only(top: firstItemSpacing),
            child: _paperField(
              fieldKey: bodyKey,
              onLongPress: () => _longPressBranch(ref),
              controller: _field(
                bodyKey,
                content.body,
                (value) => controller.updateBranchBody(ref, value),
              ),
              style: bodyStyle,
              textAlign: _textAlignFor(bodyKey, fallback: branchAlign),
              hint: layout.isLtr
                  ? 'Branch text (optional)...'
                  : 'نص الفرع (اختياري) — يُحذف من الورقة إن تُرك فارغاً',
              semanticContent: data.body?.content,
            ),
          ),
        for (var index = 0; index < data.points.length; index++) ...<Widget>[
          if ((index == 0 ? firstItemSpacing : itemSpacing) > 0)
            SizedBox(height: index == 0 ? firstItemSpacing : itemSpacing),
          _pointRow(controller, owner, data.points[index], bodyStyle, branchAlign),
        ],
        if (branch.dividerAfter != null)
          _buildDividerWidget(
            key: 'b:${branch.id}',
            divider: branch.dividerAfter!,
            onDelete: () => controller.setBranchDivider(ref, null),
            onThicken: () => controller.setBranchDivider(
              ref,
              branch.dividerAfter!.copyWith(
                thickness: branch.dividerAfter!.thickness >= 3 ? 1.2 : 3,
              ),
            ),
            onCycleWidth: () => controller.setBranchDivider(
              ref,
              branch.dividerAfter!.copyWith(
                widthFraction: _nextDividerWidth(branch.dividerAfter!.widthFraction),
              ),
            ),
          ),
      ],
    );

    final globalIds = document.floatingElements.map((element) => element.id).toSet();
    final legacyAttachments = _attachmentModels(
      document,
      data.attachments,
      questionIndex: ref.questionIndex,
      branchIndex: ref.branchIndex,
    );
    if (legacyAttachments.isEmpty) {
      return column;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: _legacyAttachmentMinHeight(legacyAttachments, globalIds),
        minWidth: double.infinity,
      ),
      child: column,
    );
  }

  /// سطر نقطة واحدة (داخل سؤال أو فرع بالمسار نفسه): الرقم المتصل ← النص ←
  /// ما يُلحقه نوعها (قوسا «صح/خطأ» أو فراغ «إكمال الفراغ») ← الدرجة، وتحتها
  /// خيارات «اختيار من متعدد». أدوات النوع والحذف تظهر عند تفعيل النقطة فقط.
  Widget _pointRow(
    ExamWizardController controller,
    PointsOwner owner,
    PointBlock point,
    TextStyle bodyStyle,
    TextAlign ownerAlign,
  ) {
    final document = controller.document;
    final sourceItems = owner.isBranch
        ? document.branchAt(
            BranchRef(
              questionIndex: owner.questionIndex,
              branchIndex: owner.branchIndex!,
            ),
          ).content.items
        : document.questions[owner.questionIndex].items;
    final item = sourceItems.firstWhere((candidate) => candidate.id == point.id);
    final fieldKey = _itemKey(item.id);
    final showActions = _activeItemFieldKey == fieldKey;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: VisualMetrics.pointIndentPx,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Tooltip(
                message: 'انقر لتعديل ترقيم النقطة',
                child: GestureDetector(
                  onTap: () => _editPointLabel(owner, item.id),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: VisualMetrics.optionTopGapPx,
                      left: VisualMetrics.pointLabelGapPx,
                    ),
                    child: point.labelContent.isEmpty
                            ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                            : _semanticInline(
                            point.labelContent,
                            bodyStyle.copyWith(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: _paperField(
                  fieldKey: fieldKey,
                  onLongPress: _pointsOwnerLongPress(owner),
                  controller: _field(
                    fieldKey,
                    item.text,
                    (value) => controller.updatePointText(owner, item.id, value),
                  ),
                  style: bodyStyle,
                  textAlign: _textAlignFor(fieldKey, fallback: ownerAlign),
                  hint: point.kind.textHint,
                  semanticContent: point.content,
                ),
              ),
              if (point.trailer != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: _semanticInline(point.trailer!, bodyStyle),
                ),
              _marksTarget(
                marks: point.marks,
                showPlaceholder: controller.document.settings.showQuestionMarks,
                style: bodyStyle,
                onEdit: () => _editPointMarks(owner, item.id),
              ),
              if (showActions) ...<Widget>[
                PopupMenuButton<PointKind>(
                  tooltip: 'نوع النقطة',
                  onSelected: (kind) => controller.updatePointKind(owner, item.id, kind),
                  itemBuilder: (context) => <PopupMenuEntry<PointKind>>[
                    for (final kind in PointKind.values)
                      PopupMenuItem<PointKind>(
                        value: kind,
                        child: Text(kind.arabicLabel),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.swap_horiz, size: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف النقطة',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => controller.removePoint(owner, item.id),
                ),
              ],
            ],
          ),
          if (point.options != null)
            _buildPointOptions(
              controller,
              owner,
              item,
              point,
              bodyStyle,
              ownerAlign,
            ),
        ],
      ),
    );
  }

  /// عرض حقل الخيار الواحد على اللوحة (بكسل منطقي) — قريب من توزيع
  /// الخيارات في الورقة المطبوعة مع إبقائها قابلة للتحرير في مكانها.
  static const double _optionFieldWidth = VisualMetrics.optionBoxWidthPx;

  /// خيارات نقطة «اختيار من متعدد»: كل خيار حقل كتابة مباشر بعرض ثابت، تحت
  /// نص النقطة، والخيارات الفارغة تبقى ظاهرة ليُكتب فيها (الطباعة تستثني
  /// الفارغ). زر «+ خيار» يظهر عند تفعيل النقطة أو أحد خياراتها.
  Widget _buildPointOptions(
    ExamWizardController controller,
    PointsOwner owner,
    BranchItem item,
    PointBlock point,
    TextStyle bodyStyle,
    TextAlign ownerAlign,
  ) {
    final options = point.options!.options;
    final active = _activeItemFieldKey == _itemKey(item.id) ||
            (_activeFieldKey?.startsWith('option-${item.id}-') ?? false);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: VisualMetrics.optionIndentPx,
        top: VisualMetrics.optionTopGapPx,
      ),
      child: Wrap(
        spacing: VisualMetrics.optionWrapSpacingPx,
        runSpacing: VisualMetrics.optionRunSpacingPx,
        children: <Widget>[
          for (var index = 0; index < options.length; index++)
            SizedBox(
              width: _optionFieldWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Tooltip(
                    message: 'انقر لتعديل تسمية الخيار',
                    child: GestureDetector(
                      onTap: () => _editOptionLabel(owner, item.id, index),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: options[index].labelContent.isEmpty
                                ? const Icon(Icons.tag, size: 12, color: Colors.grey)
                                : _semanticInline(options[index].labelContent, bodyStyle),
                      ),
                    ),
                  ),
                  const SizedBox(width: VisualMetrics.optionLabelGapPx),
                  Expanded(
                    child: _paperField(
                      fieldKey: _optionKey(item.id, index),
                      onLongPress: _pointsOwnerLongPress(owner),
                      controller: _field(
                        _optionKey(item.id, index),
                        item.options[index].text,
                        (value) => controller.updatePointOptionText(
                          owner,
                          item.id,
                          index,
                          value,
                        ),
                      ),
                      style: bodyStyle,
                      textAlign: _textAlignFor(
                        _optionKey(item.id, index),
                        fallback: ownerAlign,
                      ),
                      hint: 'اكتب الخيار هنا...',
                      semanticContent: options[index].content,
                    ),
                  ),
                  // أداة الحذف تخص وضع التحرير ولا تدخل صورة الورقة النهائية.
                  InkWell(
                      onTap: () =>
                          controller.removePointOption(owner, item.id, index),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          if (active)
            InkWell(
              onTap: () => controller.addPointOption(owner, item.id),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add, size: 14, color: PaperStyles.accent),
                    Text(
                      'خيار',
                      style: TextStyle(fontSize: 11, color: PaperStyles.accent),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// عرض الفاصل التالي في دورة (كامل ← ثلثان ← ثلث ← كامل).
  static double _nextDividerWidth(double current) {
    if ((current - 1.0).abs() < 0.01) {
      return 0.66;
    }
    if ((current - 0.66).abs() < 0.05) {
      return 0.33;
    }
    return 1.0;
  }

  static String _dividerWidthLabel(double widthFraction) {
    if ((widthFraction - 1.0).abs() < 0.01) {
      return 'كامل';
    }
    if ((widthFraction - 0.66).abs() < 0.05) {
      return 'ثلثان';
    }
    if ((widthFraction - 0.33).abs() < 0.05) {
      return 'ثلث';
    }
    return 'العرض';
  }

  Widget _buildDividerWidget({
    required String key,
    required PaperDivider divider,
    required VoidCallback onDelete,
    required VoidCallback onThicken,
    required VoidCallback onCycleWidth,
  }) {
    final selected = _selectedDividerKey == key;
    return GestureDetector(
      key: ValueKey<String>('divider-$key'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _clearSelection();
        _selectedDividerKey = key;
      }),
      child: Container(
        padding: EdgeInsets.only(top: divider.spacingBefore, bottom: divider.spacingAfter),
        color: selected ? const Color(0x1A2563EB) : null,
        child: Column(
          children: <Widget>[
            Center(
              child: FractionallySizedBox(
                widthFactor: divider.widthFraction,
                child: Container(height: divider.thickness, color: PaperStyles.primary),
              ),
            ),
            if (selected)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: onThicken,
                    icon: const Icon(Icons.line_weight, size: 14),
                    label: const Text('السماكة', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton.icon(
                    onPressed: onCycleWidth,
                    icon: const Icon(Icons.swap_horiz, size: 14),
                    label: Text(
                      _dividerWidthLabel(divider.widthFraction),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      onDelete();
                      setState(() => _selectedDividerKey = null);
                    },
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('حذف', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// صندوق محتوى المرفق (حد التحديد + العرض) — يُبنى طازجًا كل استدعاء
  /// لاستخدامه في مواضع السحب المختلفة (child/feedback/childWhenDragging).
  Widget _buildAttachmentContent(
    ExamWizardController controller,
    FloatingElement element,
    bool selected,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: selected ? Border.all(color: PaperStyles.accent, width: 1.4) : null,
      ),
      child: FloatingElementView(
        element: element,
        semanticLabel: controller.documentIr.floatingElementById(element.id)?.label,
        defaultFont: controller.document.settings.defaultFont,
        fontScale: _fontScale,
        heightScale: _heightScale,
      ),
    );
  }

  /// غلاف السحب لعنصر عائم (صورة/شكل/مربع نص).
  ///
  /// السحب **مباشر دائمًا** بلا تحديد مسبق ولا ضغط مطوّل: العنصر يُمسك من أي
  /// نقطة داخل مستطيله ويتبع الإصبع فورًا. سابقًا كان التحريك يتطلب ضغطًا
  /// مطوّلًا (أو تحديدًا مسبقًا) وهو ما جعل مربعات النص تبدو «ثابتة لا
  /// تتحرك». الورقة المقفلة ([_locked]) وحدها تمنع التحريك، وفيها يُعاد
  /// المحتوى وحده بلا ساحة إيماءات فتَمُرّ النقرات إلى [GestureDetector]
  /// الأب.
  ///
  /// المقابل المقصود: الإمساك المباشر يحجب تمرير الصفحة فوق مستطيل العنصر
  /// نفسه (ثمن مقبول لأن التحريك المباشر هو المطلوب)، وما عدا ذلك من الورقة
  /// يعمل كما كان.
  ///
  /// ملاحظة تقنية: `GestureDetector.onPanUpdate` لا يصلح هنا لأن حدّ
  /// الانزلاق المطلوب للفوز بساحة الإيماءات ضعف حدّ التمرير (`kPanSlop`
  /// = 2×`kTouchSlop`) فيسبق تمريرُ الصفحة العنصرَ إلى الفوز؛ لذلك يُعلن
  /// [EagerGestureRecognizer] الفوز فورًا وتُحسب الإزاحة من الفرق المطلق
  /// بين إحداثيات المؤشر العامة (بكسل الشاشة) مقسومةً على التكبير.
  Widget _buildAttachmentDraggable(
    ExamWizardController controller,
    _AttachmentRef ref,
    FloatingElement element,
    bool selected,
  ) {
    if (_locked) {
      return _buildAttachmentContent(controller, element, selected);
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (EagerGestureRecognizer instance) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) =>
            _beginAttachmentDrag(ref, element, event.pointer, event.position),
        onPointerMove: (event) =>
            _updateAttachmentDrag(event.pointer, event.position),
        onPointerUp: (event) {
          if (event.pointer == _dragPointer && !_dragMoved) {
            // لمسة بلا حركة = نقرة: تحدّد العنصر ثم تُسجَّل لكشف النقر
            // المزدوج (فتح محرّر مربع النص) لأن الفوز الفوري بساحة
            // الإيماءات يمنع وصول النقرة إلى [GestureDetector] الأب.
            _selectAttachment(ref);
            _noteAttachmentTap(ref, element, _lastPointerDownTime);
          }
          _endAttachmentDrag(event.pointer);
        },
        onPointerCancel: (event) => _endAttachmentDrag(event.pointer),
        child: _buildAttachmentContent(controller, element, selected),
      ),
    );
  }

  /// يبدأ سحباً فورياً للعنصر عند لمس المؤشر [pointer] ويحفظ نقطة الإمساك.
  void _beginAttachmentDrag(
    _AttachmentRef ref,
    FloatingElement element,
    int pointer,
    Offset position,
  ) {
    final controller = _controller;
    final fallbackPage = element.pageIndex;
    final ownerPage = controller != null && element.ownerQuestionId != null
        ? _elementGeometry(controller, element).pageIndex
        : controller != null &&
                !ref.isGlobal &&
                ref.questionIndex >= 0 &&
                ref.questionIndex < controller.questions.length
            ? _planPageOfQuestion(controller.questions[ref.questionIndex].id) ??
                fallbackPage
            : fallbackPage;
    final pageCount = _pagePlan?.pageCount ?? 1;
    final pageIndex = ownerPage.clamp(0, math.max(0, pageCount - 1)).toInt();
    if (controller == null) {
      return;
    }
    final local = _localPositionOnPage(pageIndex, position);
    final geometry = _elementGeometry(controller, element);
    final physicalLeft = _layoutIsLtr
        ? geometry.dx
        : ExamCanvasGeometry.width - geometry.dx - element.width;

    _dragPointer = pointer;
    _dragRef = ref;
    _dragStartScreen = position;
    _dragLastScreen = position;
    _dragLastPaper = Offset(geometry.dx, geometry.dy);
    _dragPageIndex = pageIndex;
    _dragAnchorWithinElement = local == null
        ? Offset(element.width / 2, element.height / 2)
        : Offset(local.dx - physicalLeft, local.dy - geometry.dy);
    _dragMoved = false;
  }

  /// يتابع المؤشر [pointer] ويحوّل موضعه إلى صفحة A4 الحالية؛ وبذلك يمكن
  /// نقل العنصر إلى صفحة أخرى من دون إسناده إلى سؤال جديد.
  void _updateAttachmentDrag(int pointer, Offset position) {
    final start = _dragStartScreen;
    final lastScreen = _dragLastScreen;
    final lastPaper = _dragLastPaper;
    final anchor = _dragAnchorWithinElement;
    final ref = _dragRef;
    final controller = _controller;
    if (ref == null ||
        start == null ||
        lastScreen == null ||
        lastPaper == null ||
        anchor == null ||
        controller == null ||
        pointer != _dragPointer) {
      return;
    }
    // لا حركة قبل تجاوز حدّ الانزلاق: تبقى اللمسة العادية نقرة ولا يقفز العنصر.
    if (!_dragMoved && (position - start).distance <= kTouchSlop) {
      return;
    }
    _dragMoved = true;
    final element = _findAttachment(controller.document, ref);
    if (element == null) return;

    final hitPage = _pageAtGlobalPosition(position);
    final int pageIndex;
    final Offset target;
    if (hitPage != null) {
      pageIndex = hitPage.pageIndex;
      final physicalLeft = hitPage.local.dx - anchor.dx;
      target = Offset(
        _layoutIsLtr
            ? physicalLeft
            : ExamCanvasGeometry.width - physicalLeft - element.width,
        hitPage.local.dy - anchor.dy,
      );
    } else {
      // في الفراغ بين صفحتين أو خارج حافة الشاشة: استمر من آخر إحداثي
      // على الصفحة الحالية، ثم أعد الالتقاط عند دخول صفحة أخرى.
      pageIndex = _dragPageIndex ?? element.pageIndex;
      final step = (position - lastScreen) / _zoom;
      target = lastPaper + Offset(
        _layoutIsLtr ? step.dx : -step.dx,
        step.dy,
      );
    }
    _moveAttachmentTo(ref, target, pageIndex: pageIndex);
    final moved = _findAttachment(controller.document, ref);
    if (moved != null) {
      final geometry = _elementGeometry(controller, moved);
      _dragPageIndex = geometry.pageIndex;
      _dragLastPaper = Offset(geometry.dx, geometry.dy);
    }
    _dragLastScreen = position;
  }

  /// يُنهي السحب الفوري (رفع الإصبع أو إلغاء المؤشر).
  void _endAttachmentDrag(int pointer) {
    if (pointer != _dragPointer) {
      return;
    }
    _dragPointer = null;
    _dragRef = null;
    _dragStartScreen = null;
    _dragLastScreen = null;
    _dragLastPaper = null;
    _dragAnchorWithinElement = null;
    _dragPageIndex = null;
    _dragMoved = false;
  }

  /// يسجّل نقرة على مربع نص ويكشف النقر المزدوج (فتح محرّره).
  ///
  /// تُستدعى من مساري التحديد والسحب الفوري معًا، والمقارنة على ساعة أحداث
  /// المؤشر نفسها ([timeStamp] من الغلاف الخارجي) لا على ساعة النظام.
  void _noteAttachmentTap(
    _AttachmentRef ref,
    FloatingElement element,
    Duration? timeStamp,
  ) {
    // مربع النص يفتح محرّر نصه، والمعادلة تفتح محرّر المعادلات المرئي.
    if ((!element.isTextBox && !element.isFormula) || _locked || timeStamp == null) {
      _lastAttachmentTapId = null;
      _lastAttachmentTapTime = null;
      return;
    }
    final previous = _lastAttachmentTapTime;
    final isDoubleTap = _lastAttachmentTapId == ref.elementId &&
        previous != null &&
        (timeStamp - previous).abs() <= kDoubleTapTimeout;
    _lastAttachmentTapId = ref.elementId;
    _lastAttachmentTapTime = isDoubleTap ? null : timeStamp;
    if (isDoubleTap) {
      if (element.isFormula) {
        _editFormulaElement(ref);
      } else {
        _editTextBox(ref);
      }
    }
  }

  /// هل الورقة لاتينية الاتجاه؟ (`false` = عربية، فـ `dx` من اليمين).
  bool get _layoutIsLtr => _controller?.document.layout.isLtr ?? false;

  /// يحوّل موقعاً فيزيائياً داخل **الورقة** (من أعلى-يسارها) إلى إحداثيات
  /// [FloatingElement]: `dy` من أعلى الورقة، و`dx` من حافة القراءة (اليمين
  /// في الأوراق العربية)، والنقطة تصبح **مركز** العنصر.
  Offset _boardPositionFromLocal(
    Offset local, {
    required double width,
    required double height,
  }) {
    final dy = local.dy - height / 2;
    if (_layoutIsLtr) {
      return Offset(local.dx - width / 2, dy);
    }
    // عكس النقطة: مسافتها من الحافة اليمنى بدل اليسرى.
    final fromRight = ExamCanvasGeometry.width - local.dx;
    return Offset(fromRight + width / 2, dy);
  }

  /// يحدّد العنصر [ref] ويُظهر مقابضه (الحذف/التحرير).
  ///
  /// يُستدعى من مسار السحب المباشر عند انتهاء لمسة بلا حركة، لأن
  /// [EagerGestureRecognizer] يفوز بساحة الإيماءات فلا تصل النقرة إلى
  /// [GestureDetector] الأب؛ ويُستدعى كذلك من ذلك الأب في حال قفل الورقة
  /// (لا ساحة إيماءات حينها).
  void _selectAttachment(_AttachmentRef ref) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (ref.isGlobal) {
      controller.selectBranch(null);
    } else {
      controller.selectBranch(
        ref.branchIndex == null
            ? null
            : BranchRef(
                questionIndex: ref.questionIndex,
                branchIndex: ref.branchIndex!,
              ),
      );
      controller.selectQuestion(ref.questionIndex);
    }
    setState(() {
      _clearSelection();
      _selectedAttachment = ref;
    });
  }

  /// يضع العنصر [ref] في الموضع المطلوب على صفحة A4، مستقلاً عن الأسئلة.
  /// يسمح بدخول الهوامش وخروج جزء من العنصر خارج الحافة، مع إبقاء 24 بكسلاً
  /// منه داخل الصفحة كي يستطيع المستخدم إمساكه مجدداً.
  void _moveAttachmentTo(
    _AttachmentRef ref,
    Offset target, {
    required int pageIndex,
  }) {
    final controller = _controller;
    if (controller == null) return;
    final element = _findAttachment(controller.document, ref);
    if (element == null) return;
    const anchor = 24.0;
    final maxDx = ExamCanvasGeometry.width - anchor;
    final maxDy = ExamCanvasGeometry.height - anchor;
    final absolute = element.copyWith(
      pageIndex: pageIndex,
      dx: target.dx.clamp(anchor - element.width, maxDx).toDouble(),
      dy: target.dy.clamp(anchor - element.height, maxDy).toDouble(),
    );
    final owner = element.ownerQuestionId;
    if (owner == null) {
      _updateAttachmentElement(ref, absolute, preservePageIndex: true);
      return;
    }
    // عنصر مرتبط بسؤال: يُحوَّل الموضع المطلق إلى إحداثيات نسبةً للسؤال،
    // والمراقب (المتحكم) يحصره داخل حدوده — فلا يخرج منه بالسحب أبداً.
    final rect = _pagePlan?.questionRectPx(owner);
    if (rect == null) {
      _updateAttachmentElement(ref, absolute, preservePageIndex: true);
      return;
    }
    final margin = ExamCanvasGeometry.marginFor(controller.document.settings.marginMm);
    _updateAttachmentElement(
      ref,
      element.copyWith(
        pageIndex: rect.pageIndex,
        dx: math.max(0, absolute.dx - margin),
        dy: math.max(0, absolute.dy - rect.top),
      ),
      preservePageIndex: true,
    );
  }

  Widget _elementHandle({
    required Key key,
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
    ValueChanged<DragUpdateDetails>? onPanUpdate,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanUpdate: onPanUpdate,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: CircleAvatar(
              radius: 10,
              backgroundColor: color,
              child: Icon(icon, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _scaleAttachment(
    _AttachmentRef ref,
    FloatingElement element,
    double factor,
  ) {
    final width = (element.width * factor).clamp(24.0, 600.0).toDouble();
    final height = element.isImage
        ? width * (element.height / element.width)
        : (element.height * factor).clamp(24.0, 600.0).toDouble();
    _updateAttachmentElement(ref, element.copyWith(width: width, height: height));
  }

  void _resizeAttachmentByDrag(
    _AttachmentRef ref,
    FloatingElement element,
    DragUpdateDetails details,
  ) {
    final current = _findAttachment(_controller!.document, ref) ?? element;
    final horizontalDelta = _layoutIsLtr ? details.delta.dx : -details.delta.dx;
    final width = (current.width + horizontalDelta / _zoom)
        .clamp(24.0, 600.0)
        .toDouble();
    final height = current.isImage
        ? width * (current.height / current.width)
        : (current.height + details.delta.dy / _zoom)
            .clamp(24.0, 600.0)
            .toDouble();
    _updateAttachmentElement(ref, current.copyWith(width: width, height: height));
  }

  Widget _buildAttachment(
    ExamWizardController controller,
    _AttachmentRef ref,
    FloatingElement element,
  ) {
    final selected = _selectedAttachment?.elementId == ref.elementId;
    // العنصر المرتبط بسؤال يُرسم نسبةً إلى سؤال المالك: إن سافر السؤال بين
    // الصفحات سافر معه العنصر، وإن تغيّر ارتفاع السؤال بقي داخله.
    final geometry = _elementGeometry(controller, element);
    return PositionedDirectional(
      start: geometry.dx,
      top: geometry.dy,
      width: element.width,
      height: element.height,
      // غلاف قياس وقت اللمس فقط (لا يستهلك الإيماءة): يحتاجه كشف النقر
      // المزدوج على مربع النص في المسارين (التحديد والسحب الفوري).
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (event) => _lastPointerDownTime = event.timeStamp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _selectAttachment(ref);
            _noteAttachmentTap(ref, element, _lastPointerDownTime);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                // صندوق إمساك شفاف: يضمن بدء السحب من أي نقطة داخل
                // المستطيل (بعض الأشكال لا تختبر الإصابة بذاتها)، ويقع في
                // مسار السحب المباشر الذي يحدّد العنصر عند النقر (لأن اللمس
                // يفوز بساحة الإيماءات فلا يصل إلى [GestureDetector]).
                child: _buildAttachmentDraggable(
                  controller,
                  ref,
                  element,
                  selected,
                ),
              ),
              if (selected && !_locked)
                Positioned(
                  left: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('delete-element-${element.id}'),
                    icon: Icons.close,
                    tooltip: 'حذف العنصر',
                    color: PaperStyles.danger,
                    onTap: () => _removeAttachmentElement(ref),
                  ),
                ),
              // ربط/فصل العنصر بالسؤال: المرتبط يبقى داخل سؤال المالك ويسافر
              // معه، والمفصول يبقى حراً في أي نقطة من الورقة.
              if (selected && !_locked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('owner-element-${element.id}'),
                    icon: element.isQuestionOwned
                        ? Icons.link_off
                        : Icons.link,
                    tooltip: element.isQuestionOwned
                        ? 'فصل العنصر عن السؤال'
                        : 'ربط العنصر بالسؤال المحدد',
                    color: PaperStyles.primary,
                    onTap: () => _toggleElementOwner(ref, element),
                  ),
                ),
              if (selected && !_locked && element.isFormula)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('edit-element-${element.id}'),
                    icon: Icons.functions,
                    tooltip: 'تحرير المعادلة',
                    color: PaperStyles.accent,
                    onTap: () => _editFormulaElement(ref),
                  ),
                ),
              if (selected && !_locked && element.isTextBox)
                Positioned(
                  right: 0,
                  top: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('edit-element-${element.id}'),
                    icon: Icons.edit,
                    tooltip: 'تحرير مربع النص',
                    color: PaperStyles.accent,
                    onTap: () => _editTextBox(ref),
                  ),
                ),
              if (selected && !_locked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('resize-element-${element.id}'),
                    icon: Icons.south_east,
                    tooltip: 'اسحب لتغيير الحجم',
                    color: PaperStyles.accent,
                    onTap: () => _scaleAttachment(ref, element, 1.1),
                    onPanUpdate: (details) =>
                        _resizeAttachmentByDrag(ref, element, details),
                  ),
                ),
              // مقبض التدوير يأتي **بعد** مقبض تغيير الحجم في الـStack:
              // الإيماءات تُختبر من آخر ابن إلى أوله، فمع العناصر الصغيرة
              // (60×60) يتقاطع صندوقا المقبضين (40×40 لكل منهما) ويبتلع
              // مقبضُ الحجم نقرةَ التدوير إن كان هو الأخير — فلا يدور العنصر
              // أبداً. جعله الأخير يضمن وصول النقرة إلى التدوير، ويبقى مقبض
              // الحجم فعالاً في وسطه (خارج تقاطع الصندوقين).
              if (selected &&
                  !_locked &&
                  !element.isTextBox &&
                  !element.isImage)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _elementHandle(
                    key: ValueKey<String>('rotate-element-${element.id}'),
                    icon: Icons.rotate_right,
                    tooltip: 'تدوير العنصر 45°',
                    color: PaperStyles.accent,
                    onTap: () => _updateAttachmentElement(
                      ref,
                      element.copyWith(
                        rotationDegrees: (element.rotationDegrees + 45) % 360,
                      ),
                    ),
                  ),
                ),

            ],
          ),
        ),
      ),
    );
  }

  /// شريط أدوات مصغّر فوق العنصر المحدد: تكبير/تصغير ومحاذاة دقيقة وأدواته.
  /// جميع الأزرار لها مساحة لمس كافية للأجهزة اللوحية والهواتف.
  Widget _buildAttachmentToolbar(_AttachmentRef ref, FloatingElement element) {
    const toolbarWidth = 460.0;
    const toolbarHeight = 40.0;
    final controller = _controller!;
    final pageCount = _pagePlan?.pageCount ?? 1;
    final elementPage = ref.isGlobal
        ? element.pageIndex
        : _planPageOfQuestion(controller.questions[ref.questionIndex].id) ??
            element.pageIndex;
    final pageIndex = elementPage.clamp(0, math.max(0, pageCount - 1)).toInt();
    // العنصر المرتبط بسؤال يتبع سؤاله: تُعرض أدوات الشريط عند موضعه الحقيقي
    // على الصفحة، ولا يُتاح «نقل إلى صفحة أخرى» (السؤال هو الذي ينتقل).
    final geometry = _elementGeometry(controller, element);
    final below = geometry.dy < 52;
    return PositionedDirectional(
      start: geometry.dx
          .clamp(0.0, ExamCanvasGeometry.width - toolbarWidth)
          .toDouble(),
      top: (below ? geometry.dy + element.height + 8 : geometry.dy - toolbarHeight)
          .clamp(0.0, ExamCanvasGeometry.height - toolbarHeight)
          .toDouble(),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (element.isImage)
              _attachTool(
                Icons.image_outlined,
                'استبدال الصورة',
                () => _replaceImage(ref, element),
              ),
            _attachTool(
              Icons.zoom_out,
              'تصغير العنصر',
              () => _scaleAttachment(ref, element, 0.9),
            ),
            _attachTool(
              Icons.zoom_in,
              'تكبير العنصر',
              () => _scaleAttachment(ref, element, 1.1),
            ),
            if (!element.isImage && !element.isTextBox) ...<Widget>[
              _attachTool(
                Icons.remove,
                'تقليل سماكة الحد',
                () => _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    strokeWidth:
                        (element.strokeWidth - 0.5).clamp(0.5, 12.0).toDouble(),
                  ),
                ),
              ),
              _attachTool(
                Icons.add,
                'زيادة سماكة الحد',
                () => _updateAttachmentElement(
                  ref,
                  element.copyWith(
                    strokeWidth:
                        (element.strokeWidth + 0.5).clamp(0.5, 12.0).toDouble(),
                  ),
                ),
              ),
            ],
            _attachTool(
              Icons.format_align_right,
              'محاذاة لليمين',
              () => _alignAttachment(ref, element, 'right'),
            ),
            _attachTool(
              Icons.format_align_center,
              'توسيط العنصر',
              () => _alignAttachment(ref, element, 'center'),
            ),
            _attachTool(
              Icons.format_align_left,
              'محاذاة لليسار',
              () => _alignAttachment(ref, element, 'left'),
            ),
            _attachTool(
              Icons.vertical_align_top,
              'محاذاة للأعلى',
              () => _alignAttachmentVertically(ref, element, 'top'),
            ),
            _attachTool(
              Icons.vertical_align_center,
              'توسيط عمودياً',
              () => _alignAttachmentVertically(ref, element, 'center'),
            ),
            _attachTool(
              Icons.vertical_align_bottom,
              'محاذاة للأسفل',
              () => _alignAttachmentVertically(ref, element, 'bottom'),
            ),
            if (!element.isQuestionOwned && pageIndex > 0)
              _attachTool(
                Icons.keyboard_arrow_up,
                'نقل إلى الصفحة السابقة',
                () => _moveAttachmentToPage(ref, element, pageIndex - 1),
              ),
            if (!element.isQuestionOwned && pageIndex < pageCount - 1)
              _attachTool(
                Icons.keyboard_arrow_down,
                'نقل إلى الصفحة التالية',
                () => _moveAttachmentToPage(ref, element, pageIndex + 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachTool(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 36,
          height: 40,
          child: Icon(icon, size: 18, color: PaperStyles.accent),
        ),
      ),
    );
  }

  void _moveAttachmentToPage(
    _AttachmentRef ref,
    FloatingElement element,
    int pageIndex,
  ) {
    final controller = _controller!;
    final geometry = _elementGeometry(controller, element);
    _moveAttachmentTo(ref, Offset(geometry.dx, geometry.dy), pageIndex: pageIndex);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final targetContext = _pageCanvasKeys[pageIndex]?.currentContext;
      if (mounted && targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.08,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          ),
        );
      }
    });
  }

  /// يستبدل صورة العنصر [ref] بصورة جديدة (الموضع والمقاس كما هما).
  Future<void> _replaceImage(_AttachmentRef ref, FloatingElement element) async {
    final bytes = await pickImageBytes(
      onError: () => _showMessage('تعذر فتح الصورة. تحقق من صلاحية الوصول للصور وحاول مجدداً.', isError: true),
    );
    if (!mounted) return;
    if (bytes == null) {
      return;
    }
    _updateAttachmentElement(
      ref,
      element.copyWith(bytes: Uint8List.fromList(bytes)),
    );
    _showMessage('تم استبدال الصورة.');
  }

  /// يحاذي العنصر أفقياً ([edge]: يمين/وسط/يسار) داخل هوامش الطباعة.
  /// الإحداثي يأخذ اتجاه الورقة بالحسبان لأن RTL يقيس `dx` من اليمين.
  void _alignAttachment(_AttachmentRef ref, FloatingElement element, String edge) {
    final margin = ExamCanvasGeometry.marginFor(
      _controller!.document.settings.marginMm,
    );
    final maxPhysicalLeft = ExamCanvasGeometry.width - margin - element.width;
    final isLtr = _controller!.document.layout.isLtr;
    final double dx;
    if (edge == 'center') {
      dx = (ExamCanvasGeometry.width - element.width) / 2;
    } else if (edge == 'right') {
      dx = isLtr ? maxPhysicalLeft : margin;
    } else {
      dx = isLtr ? margin : maxPhysicalLeft;
    }
    _updateAttachmentElement(ref, element.copyWith(dx: dx));
  }

  /// يحاذي العنصر رأسياً داخل صفحة A4 مع احترام الهامش.
  void _alignAttachmentVertically(
    _AttachmentRef ref,
    FloatingElement element,
    String edge,
  ) {
    final margin = ExamCanvasGeometry.marginFor(
      _controller!.document.settings.marginMm,
    );
    final dy = switch (edge) {
      'top' => margin,
      'center' => (ExamCanvasGeometry.height - element.height) / 2,
      _ => ExamCanvasGeometry.height - margin - element.height,
    };
    _updateAttachmentElement(ref, element.copyWith(dy: dy));
  }

  /// عرض منسّق لنص الفرع: الآيات القرآنية بالخط القرآني (Amiri) دائماً.
  ///
  /// وأما «أسلوب المصحف» — توسيط الآية القائمة بذاتها وتكبيرها — فيتبع
  /// تفضيل القالب ([SubjectLayoutTemplate.prefersQuranicFont]، أي قالب
  /// التربية الإسلامية)؛ وهو **نفس قرار محرك الـ PDF** حرفياً فلا تنحرف
  /// الشاشة عن الطباعة.
  Widget _buildRichPreview(
    SubjectLayoutTemplate layout,
    String text,
    TextStyle bodyStyle, {
    TextAlign textAlign = TextAlign.start,
    InlineContent? semanticContent,
  }) {
    final standaloneVerse = semanticContent?.isStandaloneQuranVerse ??
        QuranText.isStandaloneVerse(text);
    final mushafVerse = layout.prefersQuranicFont && standaloneVerse;
    final quranStyle = mushafVerse
        ? _scaled(PaperStyles.verse(layout))
        : PaperStyles.quranic(bodyStyle);
    if (semanticContent != null) {
      return TexText.fromRichContent(
        semanticContent.richContent,
        style: bodyStyle,
        mathTextStyle: bodyStyle,
        quranStyle: quranStyle,
        textAlign: mushafVerse ? TextAlign.center : textAlign,
      );
    }
    return TexText(
      text,
      style: bodyStyle,
      mathTextStyle: bodyStyle,
      quranStyle: quranStyle,
      textAlign: mushafVerse ? TextAlign.center : textAlign,
    );
  }

  /// حقل النص على الورقة: **الشكل النهائي فقط** — معادلات مرسومة وآيات
  /// بخطها، لا رموز LaTeX خام (`$...$`) على الورقة إطلاقاً.
  ///
  /// النص العادي يُحرَّر مباشرة في مكانه؛ وما إن يحتوي على صيغة/آية حتى
  /// يُعرض منسّقاً (نفس محرك الطباعة حرفياً) والنقر يفتح التحرير: محرر
  /// المعادلات المرئي للصيغ الخالصة، وإلا تحرير المصدر في مكانه.
  void _insertText(String text) {
    if (!_inserter.hasTarget) {
      _showMessage('انقر داخل حقل نصي على الورقة أولاً.');
      return;
    }
    _inserter.insert(text);
  }

  void _activateField(
    String key,
    TextEditingController field, {
    String? canonicalSemanticNodeId,
  }) {
    _inserter.controller = field;
    final activeCanonicalNodeId = canonicalSemanticNodeId ??
        (_activeFieldKey == key ? _activeCanonicalSemanticNodeId : null);
    final controller = _controller!;
    final document = controller.document;
    // هل المفتاح لنقطة من [points] (نصها أو أحد خياراتها)؟
    final option = _optionSourceTarget(key);
    bool belongsToPoints(List<BranchItem> points) => points.any(
          (point) => key == _itemKey(point.id) || option?.pointId == point.id,
        );
    setState(() {
      if (!_multiSelect) {
        _clearSelection();
      } else {
        _activeItemFieldKey = null;
      }
      _activeFieldKey = key;
      _activeCanonicalSemanticNodeId = activeCanonicalNodeId;
      for (var q = 0; q < document.questions.length; q++) {
        final question = document.questions[q];
        final isQuestionPoint = belongsToPoints(question.items);
        if (key == _statementKey(question.id) ||
            key == _bodyKey(question.id) ||
            key == _categoryKey(question.id) ||
            isQuestionPoint) {
          _activeItemFieldKey =
              isQuestionPoint && key.startsWith('item-') ? key : null;
          _selectedQuestions.add(question.id);
          controller.selectBranch(null);
          controller.selectQuestion(q);
          return;
        }
        for (var b = 0; b < question.branches.length; b++) {
          final branch = question.branches[b];
          final isBranchPoint = belongsToPoints(branch.content.items);
          if (key == _branchStatementKey(branch.id) ||
              key == _branchBodyKey(branch.id) ||
              isBranchPoint) {
            _activeItemFieldKey =
                isBranchPoint && key.startsWith('item-') ? key : null;
            final ref = BranchRef(questionIndex: q, branchIndex: b);
            _selectedBranches.add(ref);
            controller.selectBranch(ref);
            return;
          }
        }
      }
    });
  }

  Widget _paperField({
    required String fieldKey,
    required TextEditingController controller,
    required TextStyle style,
    TextAlign textAlign = TextAlign.start,
    String? hint,
    bool mushafStyle = false,
    bool matchPrintedTextWidth = true,
    bool autofocus = false,
    double minimumInteractiveHeight = 0,
    InlineContent? semanticContent,
    VoidCallback? onLongPress,
  }) {
    final layout = _controller!.document.layout;
    // مفاتيح حقول مقطع التكملة مميّزة: الحقلان (البداية والتكملة) يشتركان في
    // المتحكم الواحد، ويجب أن يبقى كل مفتاح في الشجرة وحيداً.
    return PaperField(
      key: ValueKey<String>('$fieldKey$_sliceKeySuffix'),
      controller: controller,
      autofocus: autofocus,
      minimumInteractiveHeight: minimumInteractiveHeight,
      style: style,
      matchPrintedTextWidth: matchPrintedTextWidth,
      semanticContent: semanticContent,
      textAlign: textAlign,
      hint: hint,
      onActivate: () => _activateField(fieldKey, controller),
      onEditFormula: () => _editEquationInField(fieldKey),
      // في وضع التحديد المتعدد لا يبتلع الحقل الضغط المطوّل: يمرّ إلى كتلة
      // السؤال/الفرع فتُحدَّد من أي موضع (والنص غير قابل للتأشير وقتها).
      allowTextSelection: !_multiSelect,
      // الضغط المطوّل على أي موضع داخل الكتلة (نص السؤال أو الفرع أو نقطة
      // أو خيار) يفعّل التحديد المتعدد ويحدّد الكتلة نفسها.
      onLongPress: onLongPress,
      // نص الفرع وحده يتبع «أسلوب المصحف» (توسيط الآية القائمة بذاتها)
      // كما في محرك الـ PDF — وبقية الحقول تُعرض بمحاذاة الحقل نفسها.
      renderBuilder: (text) {
        if (mushafStyle) {
          return _buildRichPreview(
            layout,
            text,
            style,
            textAlign: textAlign,
            semanticContent: semanticContent,
          );
        }
        if (semanticContent != null) {
          return TexText.fromRichContent(
            semanticContent.richContent,
                style: style,
            mathTextStyle: style,
            textAlign: textAlign,
          );
        }
        return TexText(
          text,
          style: style,
          mathTextStyle: style,
          textAlign: textAlign,
        );
      },
    );
  }
}

InlineContent _feedbackTitleContent(
  TitleParagraphBlock title, {
  bool includeMarks = true,
}) {
  final nodes = <InlineNode>[...title.labelContent.nodes];
  if (title.statement.isNotEmpty) {
    nodes
      ..add(const SeparatorNode(' '))
      ..addAll(title.statement.nodes);
  }
  if (includeMarks && title.marks != null) {
    nodes
      ..add(const SeparatorNode(' '))
      ..add(title.marks!);
  }
  return InlineContent(nodes);
}

/// Text for lightweight drag previews is derived from typed inline nodes;
/// LaTeX is shown readably and never as raw source code.
String _readableInlineContent(InlineContent content) {
  final buffer = StringBuffer();

  void appendNode(InlineNode node) {
    if (node is MathNode) {
      buffer.write(EquationModel.readableText(node.source));
    } else if (node is TextNode) {
      buffer.write(node.text);
    } else if (node is QuranNode) {
      buffer.write(node.source);
    } else if (node is LabelNode) {
      for (final child in node.content.nodes) {
        appendNode(child);
      }
    } else if (node is NumberNode) {
      buffer.write(node.displayText);
    } else if (node is SeparatorNode) {
      buffer.write(node.text);
    } else if (node is MarksNode) {
      appendNode(node.opening);
      appendNode(node.number);
      appendNode(node.numberUnitGap);
      appendNode(node.unit);
      appendNode(node.closing);
    }
  }

  for (final node in content.nodes) {
    appendNode(node);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}