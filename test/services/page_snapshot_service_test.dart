import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/services/page_snapshot_service.dart';

void main() {
  testWidgets(
    'captureVisiblePage scrolls to an offscreen page before taking its snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(500, 250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final pageKeys = <GlobalKey>[
        GlobalKey(debugLabel: 'visible-page-0'),
        GlobalKey(debugLabel: 'offscreen-page-1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var index = 0; index < pageKeys.length; index++)
                    RepaintBoundary(
                      key: pageKeys[index],
                      child: SizedBox(
                        width: 320,
                        height: 320,
                        child: ColoredBox(
                          color: index == 0 ? Colors.red : Colors.blue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0);

      // يبدأ الالتقاط والصفحة الثانية كاملة خارج viewport؛ لا يكفي أن تكون
      // GlobalKey موجودة، بل يجب جلب الصفحة إلى العرض وانتظار paint.
      final captureFuture = PageSnapshotService.captureVisiblePage(
        pageKeys[1],
        pageIndex: 1,
        dpi: PageSnapshotService.canvasDpi,
      );
      await tester.pumpAndSettle();
      final snapshot = await tester.runAsync(() => captureFuture);

      expect(snapshot, isNotNull);
      final page = snapshot!;
      expect(scrollController.offset, greaterThan(0));
      expect(page.widthPx, 320);
      expect(page.heightPx, 320);
      expect(
        page.pngBytes.sublist(0, 8),
        <int>[137, 80, 78, 71, 13, 10, 26, 10],
        reason: 'يجب أن تكون اللقطة PNG صالحة بعد إظهار الصفحة.',
      );

      final decoded = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(page.pngBytes);
        try {
          return await codec.getNextFrame();
        } finally {
          codec.dispose();
        }
      });
      expect(decoded, isNotNull);
      final frame = decoded!;
      expect(frame.image.width, 320);
      expect(frame.image.height, 320);
      final pixel = await tester.runAsync(
        () => frame.image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(pixel, isNotNull);
      expect(
        pixel!.getUint8(2),
        greaterThan(200),
        reason: 'الصورة الملتقطة تخص الصفحة الثانية الزرقاء، لا الأولى.',
      );
      frame.image.dispose();
    },
  );
}
