import '../document_ir.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// **خطة الصفحات المشتركة** — الإسقاط الوحيد المسموح للورقة على صفحات.
///
/// من يقرأها: سطح المعاينة التفاعلي (الودجات القابلة للتحرير) وسطح المعاينة
/// القانوني وPDF. ومن ينتجها: `LayoutEngine` وحده داخل `LayoutDocument`.
///
/// لماذا نوع مستقل بدل قراءة `controller.pagination`؟
///   كان في الإنتاج محركان يتخذان القرار نفسه: `PaginationEngine` (ارتفاعات
///   ودجات مقاسة بالبكسل) لسطح التحرير، و`LayoutEngine` (نقاط، قياس نصّ حقيقي)
///   لـPDF. قِيس الفرق على مستند مرجعي: المعاينة 4 صفحات
///   `[q1,q2 | q3 | q4 | q5,q6,q7]` مقابل 3 صفحات في PDF
///   `[q1,q2,q3 | q4,q5 | q6,q7]` — أي أن ما يراه المدرس ليس ما يُطبع.
///   لذلك صار القرار واحداً في المحرك، وهذا النوع مجرّد **إسقاط** له، لا محرك.
///
/// ما لا يحتويه ولماذا: لا يُقاس هنا أي نصّ ولا يُحسب أي ارتفاع — كل القيم
/// مأخوذة من `LayoutDocument` كما هي. أي منطق قياس في هذا الملف يكون محركاً
/// ثانياً بالبكسل، وهو العيب الذي أُزيل.
class CanonicalPagePlanPage {
  const CanonicalPagePlanPage({
    required this.index,
    required this.questionIds,
    required this.continuedQuestionIds,
    required this.overflows,
    required this.scaleFactor,
    required this.usedHeightPt,
    required this.capacityPt,
    required this.bodyBounds,
    required this.pageHeightPt,
    required this.hasHeader,
    required this.hasFooter,
    this.unplannedQuestionIds = const <String>[],
  });

  /// فهرس الصفحة (من الصفر).
  final int index;

  /// الأسئلة التي **تبدأ** في هذه الصفحة، بترتيب القراءة.
  final List<String> questionIds;

  /// الأسئلة التي **تستمرّ** من الصفحة السابقة (سؤال أطول من صفحة واحدة).
  ///
  /// فصل السؤال على حدود الأسطر سياسة محرك التخطيط نفسه، ومسجَّل هنا صراحةً
  /// كي لا يُخفى: سطح التحرير يرسم السؤال مرة واحدة في صفحة بدايته، وتكملته
  /// تُطبع في PDF (قيدُ عرض معلن في docs/p3_editor_preview_export_unification
  /// §19 — لا يمكن تقطيع `TextEditingController` واحد على صفحتين دون تفريع
  /// نموذج التحرير).
  final List<String> continuedQuestionIds;

  /// كتل الصفحة كما يرسمها سطح التحرير: أسئلة هذه الصفحة (بلا الترويسة؛
  /// السطح يُضيف مفتاح الترويسة من عنده على الصفحة الأولى).
  List<String> get blockIds => questionIds;

  /// هل تحتوي الصفحة سؤالاً أكبر من مساحة الصفحة فصُغِّر (كما في PDF)؟
  final bool overflows;

  /// معامل التصغير المطبَّق على كتلة الصفحة (1.0 = بلا تصغير).
  final double scaleFactor;

  /// الارتفاع المستهلك بالنقاط كما يقيسه المحرك، وسعة الصفحة.
  final double usedHeightPt;
  final double capacityPt;

  /// مستطيل المتن في هذه الصفحة (نقاط) — مصدر حدود الصفحة نفسها.
  final LayoutRect bodyBounds;

  /// ارتفاع الورقة الكامل (نقاط) — لحساب الإزاحات من أسفل الصفحة.
  final double pageHeightPt;

  final bool hasHeader;
  final bool hasFooter;

  /// أسئلة **بلا محتوى مطبوع** مُرساة في هذه الصفحة (سياسة §19.7).
  ///
  /// لا تدخل خطة الورقة ولا PDF (المحرك يستبعدها لأنها لا تطبع شيئاً)، لكن
  /// سطح التحرير يجب أن يعرضها: المدرس يكتب فيها من المعاينة نفسها. إرساؤها
  /// هنا قرار **موضع عرض** لا قرار تقسيم: لا تغيّر صفحات ولا ارتفاعاً محسوباً
  /// ولا محتوى PDF.
  final List<String> unplannedQuestionIds;
}

/// خطة الصفحات الكاملة: `LayoutDocument` نفسه + إسقاط صفحاته.
class CanonicalPagePlan {
  CanonicalPagePlan._(
    this.layout,
    this.pages,
    this._pageOfBlock,
    this._unplannedByPage,
  ) : assert(pages.length == layout.pages.length);

  factory CanonicalPagePlan.fromLayout(LayoutDocument layout) {
    final pageOfBlock = <String, int>{};
    final started = <String>{};
    // المرور الأول: أسئلة البداية/التكملة والمقياس لكل صفحة.
    final drafts = <({
      int index,
      List<String> starts,
      List<String> continued,
      double scale,
      double usedHeightPt,
      LayoutPage page,
    })>[];
    for (final page in layout.pages) {
      final starts = <String>[];
      final continued = <String>[];
      var scale = 1.0;
      var usedBottom = page.bodyBounds.top;
      for (final block in page.blocks) {
        if (block.kind != LayoutBlockKind.question) continue;
        final id = block.semanticNodeId;
        if (started.contains(id)) {
          continued.add(id);
        } else {
          starts.add(id);
          started.add(id);
          pageOfBlock.putIfAbsent(id, () => page.index);
        }
        if (block.scaleFactor < scale) scale = block.scaleFactor;
        final bottom = block.rect.bottom;
        if (bottom > usedBottom) usedBottom = bottom;
      }
      drafts.add((
        index: page.index,
        starts: starts,
        continued: continued,
        scale: scale,
        usedHeightPt: (usedBottom - page.bodyBounds.top)
            .clamp(0.0, double.infinity)
            .toDouble(),
        page: page,
      ));
    }

    // المرور الثاني: إرساء الأسئلة غير المخطَّطة (بلا محتوى مطبوع) في صفحة
    // أقرب سؤال مخطَّط يسبقها، أو الأولى إن سبقت كل الأسئلة.
    final unplanned = <int, List<String>>{};
    var anchor = drafts.isEmpty ? 0 : drafts.first.index;
    for (final question in layout.source.questions) {
      final planned = pageOfBlock[question.id];
      if (planned != null) {
        anchor = planned;
        continue;
      }
      (unplanned[anchor] ??= <String>[]).add(question.id);
    }

    final pages = <CanonicalPagePlanPage>[
      for (final draft in drafts)
        CanonicalPagePlanPage(
          index: draft.index,
          questionIds: List<String>.unmodifiable(draft.starts),
          continuedQuestionIds: List<String>.unmodifiable(draft.continued),
          overflows: draft.scale < 0.999,
          scaleFactor: draft.scale,
          usedHeightPt: draft.usedHeightPt,
          capacityPt: draft.page.bodyBounds.height,
          bodyBounds: draft.page.bodyBounds,
          pageHeightPt: draft.page.pageSize.height,
          hasHeader: draft.page.headerBounds != null,
          hasFooter: draft.page.footerBounds != null,
          unplannedQuestionIds: List<String>.unmodifiable(
            unplanned[draft.index] ?? const <String>[],
          ),
        ),
    ];
    return CanonicalPagePlan._(
      layout,
      List<CanonicalPagePlanPage>.unmodifiable(pages),
      Map<String, int>.unmodifiable(pageOfBlock),
      Map<int, List<String>>.unmodifiable(unplanned),
    );
  }

  /// التخطيط الذي تنتسب إليه الخطة — مصدر كل قيمة فيها.
  final LayoutDocument layout;

  final List<CanonicalPagePlanPage> pages;
  final Map<String, int> _pageOfBlock;
  final Map<int, List<String>> _unplannedByPage;

  int get pageCount => pages.length;

  /// الصفحة التي يبدأ فيها السؤال/الكتلة (لا صفحة تكملته).
  int? pageIndexOf(String blockId) => _pageOfBlock[blockId];

  /// توزيع الأسئلة كما يطبعه PDF (سؤال التكملة يظهر في كل صفحة يغطيها).
  List<List<String>> get questionAssignments => layout.questionPageAssignments;

  /// هل الخطة تخصّ هذا المصدر الدلالي بالذات؟ (نسخ المستند تستبدل النسخة.)
  bool isFor(DocumentIR source) => identical(layout.source, source);

  /// أعلى كتلة السؤال داخل صفحتها **بالبكسل المنطقي** (لوحة المعاينة).
  ///
  /// يُستخدم لوضع العناصر العائمة التابعة للسؤال: موضعها يُشتق من هندسة
  /// الخطة نفسها لا من مجموع ارتفاعات ودجات مقاسة.
  double? blockTopPxOf(String questionId) {
    for (final page in layout.pages) {
      for (final block in page.blocks) {
        if (block.semanticNodeId == questionId &&
            block.kind == LayoutBlockKind.question) {
          return LayoutUnits.ptToPx(block.rect.top);
        }
      }
    }
    return null;
  }

  /// مستطيل كتلة السؤال بالبكسل (الصفحة والحدود) أو `null` إن لم تُخطَّط.
  ({int pageIndex, double left, double top, double width, double height})?
      questionRectPx(String questionId) {
    for (final page in layout.pages) {
      for (final block in page.blocks) {
        if (block.semanticNodeId == questionId &&
            block.kind == LayoutBlockKind.question) {
          return (
            pageIndex: page.index,
            left: LayoutUnits.ptToPx(block.rect.left),
            top: LayoutUnits.ptToPx(block.rect.top),
            width: LayoutUnits.ptToPx(block.rect.width),
            height: LayoutUnits.ptToPx(block.rect.height),
          );
        }
      }
    }
    return null;
  }

  /// هل هناك سؤال بلا محتوى مطبوع (لا يظهر في الورقة/PDF لكنه يُحرَّر)؟
  bool get hasUnplannedQuestions => _unplannedByPage.isNotEmpty;

  /// أسئلة لا تدخل الورقة المطبوعة، بترتيب المصدر.
  List<String> get unplannedQuestionIds => List<String>.unmodifiable(
        <String>[
          for (final ids in _unplannedByPage.values) ...ids,
        ],
      );

  /// هل تحتوي الخطة سؤالاً يمتدّ على أكثر من صفحة؟
  bool get hasContinuations =>
      pages.any((page) => page.continuedQuestionIds.isNotEmpty);
}
