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

/// محرك التقسيم الورقي (Pagination) — منطق خالص بلا أي اعتماد على Flutter
/// أو pdf، يُستخدم **بنفس القواعد** للشاشة وللطباعة.
///
/// القاعدة الصارمة: الكتلة (السؤال الكامل بفروعه) **لا تُقسَّم أبداً**؛
/// إن لم تتسع في المساحة المتبقية من الصفحة الحالية تُنقل كاملة إلى بداية
/// الصفحة التالية. الكتلة الوحيدة الأطول من صفحة كاملة تُوضع منفردة في
/// صفحة خاصة بها (وتُصغَّر عند الرسم بدل أن تُقطع).
abstract final class PaginationEngine {
  /// يوزّع [blocks] على صفحات.
  ///
  /// - [pageHeight]: الارتفاع المتاح للمحتوى في الصفحة العادية.
  /// - [firstPageHeight]: الارتفاع المتاح في الصفحة الأولى (بعد الترويسة)؛
  ///   يساوي [pageHeight] افتراضياً.
  /// - [spacing]: المسافة الرأسية بين كتلتين متتاليتين في الصفحة نفسها.
  static PaginationResult paginate({
    required List<PageBlock> blocks,
    required double pageHeight,
    double? firstPageHeight,
    double spacing = 0,
  }) {
    if (pageHeight <= 0) {
      throw ArgumentError.value(pageHeight, 'pageHeight', 'يجب أن يكون موجباً.');
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

    for (final block in blocks) {
      final gap = currentIds.isEmpty ? 0.0 : gapAfter(previousBlock);
      final available = availableFor(pages.length);
      final fits = used + gap + block.height <= available + _epsilon;

      if (!fits && currentIds.isNotEmpty) {
        // القاعدة الذهبية: السؤال كاملاً إلى الصفحة التالية.
        flush();
      }

      final availableNow = availableFor(pages.length);
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
