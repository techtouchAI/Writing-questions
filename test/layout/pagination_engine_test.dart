import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/pagination_engine.dart';

void main() {
  group('PaginationEngine', () {
    test('keeps blocks on one page while they fit', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'header', height: 100),
          PageBlock(id: 'q1', height: 200),
          PageBlock(id: 'q2', height: 200),
        ],
        pageHeight: 600,
        spacing: 10,
      );

      expect(result.pageCount, 1);
      expect(result.pages.single.blockIds, <String>['header', 'q1', 'q2']);
      expect(result.pages.single.usedHeight, 520);
    });

    test('moves a whole question to the next page when it does not fit', () {
      // 100 + 10 + 200 + 10 + 200 = 520؛ السؤال الثالث (200) لا يتسع في 600
      // فينتقل كاملاً إلى بداية الصفحة الثانية — لا يُقسَّم أبداً.
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'header', height: 100),
          PageBlock(id: 'q1', height: 200),
          PageBlock(id: 'q2', height: 200),
          PageBlock(id: 'q3', height: 200),
        ],
        pageHeight: 600,
        spacing: 10,
      );

      expect(result.pageCount, 2);
      expect(result.pages[0].blockIds, <String>['header', 'q1', 'q2']);
      expect(result.pages[1].blockIds, <String>['q3']);
      expect(result.pages[1].usedHeight, 200);
      expect(result.pageIndexOf('q3'), 1);
      expect(result.pageIndexOf('q1'), 0);
    });

    test('uses shared spacing when a block has no override', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'first', height: 100),
          PageBlock(id: 'second', height: 100),
        ],
        pageHeight: 205,
        spacing: 5,
      );

      expect(result.pages.single.usedHeight, 205);
    });

    test('uses the previous question spacing, including zero, without leaking it across pages', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'q1', height: 100, spacingAfter: 40),
          PageBlock(id: 'q2', height: 100, spacingAfter: 0),
          PageBlock(id: 'q3', height: 100),
        ],
        pageHeight: 250,
        spacing: 10,
      );

      expect(result.pageCount, 2);
      expect(result.pages[0].blockIds, <String>['q1', 'q2']);
      expect(result.pages[0].usedHeight, 240);
      expect(result.pages[1].blockIds, <String>['q3']);
      expect(result.pages[1].usedHeight, 100);
    });

    test('a block exactly filling the remaining space stays on the page', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'a', height: 300),
          PageBlock(id: 'b', height: 290),
        ],
        pageHeight: 600,
        spacing: 10,
      );

      expect(result.pageCount, 1);
    });

    test('a block taller than a page gets its own page flagged as overflowing', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'a', height: 100),
          PageBlock(id: 'huge', height: 900),
          PageBlock(id: 'c', height: 100),
        ],
        pageHeight: 600,
      );

      expect(result.pageCount, 3);
      expect(result.pages[1].blockIds, <String>['huge']);
      expect(result.pages[1].overflows, isTrue);
      expect(result.pages[0].overflows, isFalse);
      expect(result.pages[2].blockIds, <String>['c']);
    });

    test('supports a shorter first page (space consumed by the header)', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[
          PageBlock(id: 'q1', height: 250),
          PageBlock(id: 'q2', height: 250),
        ],
        pageHeight: 600,
        firstPageHeight: 300,
      );

      expect(result.pageCount, 2);
      expect(result.pages[0].blockIds, <String>['q1']);
      expect(result.pages[1].blockIds, <String>['q2']);
    });

    test('always yields at least one (empty) page', () {
      final result = PaginationEngine.paginate(
        blocks: const <PageBlock>[],
        pageHeight: 600,
      );

      expect(result.pageCount, 1);
      expect(result.pages.single.isEmpty, isTrue);
    });

    group('last-page footer reserve', () {
      test('is taken from the last block only', () {
        // 100 + 10 + 200 + 10 + 200 = 520 ≤ 600 بلا حجز.
        final withoutReserve = PaginationEngine.paginate(
          blocks: const <PageBlock>[
            PageBlock(id: 'header', height: 100),
            PageBlock(id: 'q1', height: 200),
            PageBlock(id: 'q2', height: 200),
          ],
          pageHeight: 600,
          spacing: 10,
        );
        expect(withoutReserve.pageCount, 1);

        // حجز 100 ⇒ المتاح لآخر كتلة 500 (< 520) ⇒ q2 كاملاً لصفحة جديدة،
        // بينما بقية الكتل (قبل الأخيرة) لا تتأثر بالحجز.
        final withReserve = PaginationEngine.paginate(
          blocks: const <PageBlock>[
            PageBlock(id: 'header', height: 100),
            PageBlock(id: 'q1', height: 200),
            PageBlock(id: 'q2', height: 200),
          ],
          pageHeight: 600,
          spacing: 10,
          lastPageReserve: 100,
        );
        expect(withReserve.pageCount, 2);
        expect(withReserve.pages[0].blockIds, <String>['header', 'q1']);
        expect(withReserve.pages[1].blockIds, <String>['q2']);
      });

      test('a small reserve changes nothing when the last block still fits', () {
        final result = PaginationEngine.paginate(
          blocks: const <PageBlock>[
            PageBlock(id: 'header', height: 100),
            PageBlock(id: 'q1', height: 200),
          ],
          pageHeight: 600,
          spacing: 10,
          lastPageReserve: 80,
        );
        expect(result.pageCount, 1);
        expect(result.pages.single.overflows, isFalse);
      });

      test('a last block taller than page minus reserve is scaled instead of cut', () {
        final result = PaginationEngine.paginate(
          blocks: const <PageBlock>[PageBlock(id: 'huge', height: 580)],
          pageHeight: 600,
          lastPageReserve: 50,
        );
        expect(result.pageCount, 1);
        expect(result.pages.single.overflows, isTrue);
      });

      test('the header alone still leaves room for the footer on its page', () {
        final result = PaginationEngine.paginate(
          blocks: const <PageBlock>[PageBlock(id: 'header', height: 560)],
          pageHeight: 600,
          lastPageReserve: 80,
        );
        expect(result.pageCount, 1);
        expect(result.pages.single.overflows, isTrue);
      });

      test('rejects a negative reserve', () {
        expect(
          () => PaginationEngine.paginate(
            blocks: const <PageBlock>[],
            pageHeight: 600,
            lastPageReserve: -1,
          ),
          throwsArgumentError,
        );
      });
    });

    test('rejects a non-positive page height', () {
      expect(
        () => PaginationEngine.paginate(blocks: const <PageBlock>[], pageHeight: 0),
        throwsArgumentError,
      );
    });
  });
}
