/// كتلة قابلة للتقسيم الورقي: سؤال كامل بفروعه (أو الترويسة) بارتفاع مقاس.
class PageBlock {
  const PageBlock({required this.id, required this.height, double? spacingAfter})
      : spacingAfter = spacingAfter ?? 10,
        _usesSharedSpacing = spacingAfter == null,
        assert(height >= 0),
        assert(spacingAfter == null || spacingAfter >= 0);

  final String id;
  final double height;

  /// Gap after this block when set; otherwise inherits [PaginationEngine.paginate]'s
  /// [spacing]. The field keeps its historical numeric default for compatibility.
  final double spacingAfter;
  final bool _usesSharedSpacing;
}

/// صفحة ناتجة عن التقسيم: معرّفات الكتل التي تحتويها بترتيبها.
class PaginatedPage {
  const PaginatedPage({
    required this.index,
    required this.blockIds,
    required this.usedHeight,
    required this.overflows,
  });

  /// فهرس الصفحة (يبدأ من الصفر).
  final int index;
  final List<String> blockIds;

  /// مجموع ارتفاعات الكتل والمسافات بينها.
  final double usedHeight;

  /// كتلة واحدة أطول من الصفحة كاملة وُضعت منفردة (تُصغَّر عند الرسم).
  final bool overflows;

  bool get isEmpty => blockIds.isEmpty;
}

/// نتيجة التقسيم الكاملة مع فهرس عكسي (كتلة ← صفحة).
class PaginationResult {
  PaginationResult(this.pages)
      : _pageOfBlock = <String, int>{
          for (final page in pages)
            for (final id in page.blockIds) id: page.index,
        };

  final List<PaginatedPage> pages;
  final Map<String, int> _pageOfBlock;

  int get pageCount => pages.length;

  int? pageIndexOf(String blockId) => _pageOfBlock[blockId];
}

/// Immutable input to the legacy [PaginationEngine]. Keeping the measured
/// blocks and page policy together lets exporters re-run the exact same
/// paginator instead of trusting a caller's page-ID list as proof.
class PaginationInput {
  PaginationInput({
    required Iterable<PageBlock> blocks,
    required this.pageHeight,
    this.firstPageHeight,
    this.spacing = 0,
    this.lastPageReserve = 0,
    this.footerMeasured = false,
  }) : blocks = List<PageBlock>.unmodifiable(blocks);

  final List<PageBlock> blocks;
  final double pageHeight;
  final double? firstPageHeight;
  final double spacing;
  final double lastPageReserve;

  /// Whether the footer height/reserve was measured (or authoritatively
  /// resolved as empty). Zero alone cannot distinguish an empty footer from an
  /// unmeasured footer.
  final bool footerMeasured;

  PaginationResult paginate() => PaginationEngine.paginate(
        blocks: blocks,
        pageHeight: pageHeight,
        firstPageHeight: firstPageHeight,
        spacing: spacing,
        lastPageReserve: lastPageReserve,
      );

  PaginationInput retainBlockIds(Set<String> ids) => PaginationInput(
        blocks: blocks.where((block) => ids.contains(block.id)),
        pageHeight: pageHeight,
        firstPageHeight: firstPageHeight,
        spacing: spacing,
        lastPageReserve: lastPageReserve,
        footerMeasured: footerMeasured,
      );
}

/// محرك التقسيم الورقي (Pagination) — منطق خالص بلا أي اعتماد على Flutter
/// أو pdf، يُستخدم **بنفس القواعد** للشاشة وللطباعة.
///
/// القاعدة الصارمة: الكتلة (السؤال الكامل بفروعه) **لا تُقسَّم أبداً**؛
/// إن لم تتسع في المساحة المتبقية من الصفحة الحالية تُنقل كاملة إلى بداية
/// الصفحة التالية. الكتلة الوحيدة الأطول من صفحة كاملة تُوضع منفردة في
/// صفحة خاصة بها (وتُصغَّر عند الرسم بدل أن تُقطع).
///
/// **حجز التذييل**: التذييل يُطبع في أسفل آخر صفحة فقط، لذلك تُحجز مساحته
/// ([paginate]`.lastPageReserve`) من **آخر كتلة** وحدها: إن لم تتسع الكتلة
/// الأخيرة مع التذييل انتقلت كاملة إلى صفحة جديدة، فلا يتداخل التذييل مع
/// الأسئلة أبداً ولا يتكرر في صفحة غير أخيرة.
abstract final class PaginationEngine {
  /// يوزّع [blocks] على صفحات.
  ///
  /// - [pageHeight]: الارتفاع المتاح للمحتوى في الصفحة العادية.
  /// - [firstPageHeight]: الارتفاع المتاح في الصفحة الأولى (بعد الترويسة)؛
  ///   يساوي [pageHeight] افتراضياً.
  /// - [spacing]: المسافة الرأسية بين كتلتين متتاليتين في الصفحة نفسها.
  /// - [lastPageReserve]: ارتفاع يُحجز في أسفل **الصفحة الأخيرة** (التذييل
  ///   وما يفصله عن آخر سؤال). يُطبَّق على آخر كتلة فقط.
  static PaginationResult paginate({
    required List<PageBlock> blocks,
    required double pageHeight,
    double? firstPageHeight,
    double spacing = 0,
    double lastPageReserve = 0,
  }) {
    if (pageHeight <= 0) {
      throw ArgumentError.value(pageHeight, 'pageHeight', 'يجب أن يكون موجباً.');
    }
    if (lastPageReserve < 0) {
      throw ArgumentError.value(lastPageReserve, 'lastPageReserve', 'يجب ألا يكون سالباً.');
    }
    final firstHeight = firstPageHeight ?? pageHeight;

    final pages = <PaginatedPage>[];
    var currentIds = <String>[];
    var used = 0.0;
    var currentOverflows = false;
    PageBlock? previousBlock;

    double availableFor(int pageIndex) => pageIndex == 0 ? firstHeight : pageHeight;
    double gapAfter(PageBlock? block) =>
        block == null || block._usesSharedSpacing ? spacing : block.spacingAfter;

    void flush() {
      pages.add(
        PaginatedPage(
          index: pages.length,
          blockIds: List<String>.unmodifiable(currentIds),
          usedHeight: used,
          overflows: currentOverflows,
        ),
      );
      currentIds = <String>[];
      used = 0;
      currentOverflows = false;
      previousBlock = null;
    }

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      // التذييل يحجز مكانه تحت الكتلة الأخيرة وحدها.
      final reserve = blockIndex == blocks.length - 1 ? lastPageReserve : 0.0;
      final gap = currentIds.isEmpty ? 0.0 : gapAfter(previousBlock);
      final available = availableFor(pages.length) - reserve;
      final fits = used + gap + block.height <= available + _epsilon;

      if (!fits && currentIds.isNotEmpty) {
        // القاعدة الذهبية: السؤال كاملاً إلى الصفحة التالية.
        flush();
      }

      final availableNow = availableFor(pages.length) - reserve;
      final gapNow = currentIds.isEmpty ? 0.0 : gapAfter(previousBlock);
      if (currentIds.isEmpty && block.height > availableNow + _epsilon) {
        // كتلة أطول من الصفحة كلها: تُوضع منفردة وتُعلَّم كمتجاوزة.
        currentOverflows = true;
      }
      currentIds.add(block.id);
      used += gapNow + block.height;
      previousBlock = block;
    }

    if (currentIds.isNotEmpty || pages.isEmpty) {
      flush();
    }
    return PaginationResult(List<PaginatedPage>.unmodifiable(pages));
  }

  static const double _epsilon = 0.01;
}
