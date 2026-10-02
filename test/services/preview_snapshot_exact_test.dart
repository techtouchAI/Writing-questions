// من الشاشة إلى الملف: صفحة المعاينة نفسها (بالبكسل) تصل إلى PDF وWord.
//
// هذا هو جوهر النمط الدقيق: لا محرك تخطيط ثانٍ. الاختبار يرسم صفحة A4
// حقيقية في شجرة Flutter، يلتقطها [PageSnapshotService] كما تلتقطها
// الواجهة، ثم:
//   * Word: يتحقق أن بايتات PNG المضمّنة في الحزمة هي **البايتات نفسها**
//     الملتقطة (تطابق بالبناء لا بالتشابه).
//   * PDF: صفحة واحدة بمقاس A4 كامل تحمل صورة (XObject) بلا أي نص معاد
//     تخطيطه.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';

void main() {
  testWidgets('لقطة صفحة المعاينة تُضمَّن ببايتاتها نفسها في Word وPDF',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pageKey = GlobalKey(debugLabel: 'exact-page');
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: RepaintBoundary(
              key: pageKey,
              child: Container(
                width: ExamCanvasGeometry.width,
                height: ExamCanvasGeometry.height,
                color: const Color(0xFFFFFFFF),
                padding: const EdgeInsets.all(24),
                child: const Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    'ورقة اختبار — التصدير الدقيق',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontSize: 20, color: Color(0xFF000000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 96dpi = بكسل اللوحة نفسه (1:1)، فالأبعاد معروفة مسبقاً.
    // `runAsync` لازم: لقط الصفحة ينتظر خيط الرسم الحقيقي، وبدونه لا يُسلَّم
    // المستقبل داخل زمن الاختبار المزيَّف.
    final snapshot = await tester.runAsync(
      () => PageSnapshotService.capturePage(
        pageKey,
        pageIndex: 0,
        dpi: PageSnapshotService.canvasDpi,
      ),
    );
    expect(snapshot, isNotNull);
    final page = snapshot!;
    expect(
      page.pngBytes.sublist(0, 8),
      <int>[137, 80, 78, 71, 13, 10, 26, 10],
      reason: 'اللقطة صورة PNG صالحة.',
    );
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(page.pngBytes);
      return codec.getNextFrame();
    });
    expect(decoded, isNotNull);
    expect(decoded!.image.width, ExamCanvasGeometry.width.round(),
        reason: 'عرض الصفحة الملتقطة = عرض لوحة A4.');
    expect(decoded.image.height, ExamCanvasGeometry.height.round(),
        reason: 'ارتفاع الصفحة الملتقطة = ارتفاع لوحة A4.');
    decoded.image.dispose();

    // ---------------- Word: البايتات نفسها داخل الحزمة ----------------
    final docxBytes = ExactExportService.buildDocxFromSnapshots(
      <PageSnapshot>[page],
    );
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final media = archive.findFile('word/media/page1.png');
    expect(media, isNotNull, reason: 'صورة الصفحة مضمّنة في الحزمة.');
    expect(
      media!.content,
      equals(page.pngBytes),
      reason: 'Word الدقيق لا يعيد ترميز الصورة: هي اللقطة نفسها ببايتاتها.',
    );
    final xml = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml.contains('<w:t'), isFalse,
        reason: 'لا نص قابل للتحرير في النمط الدقيق (معلن في الواجهة).');

    // ---------------- PDF: صفحة A4 فيها الصورة ----------------
    final pdfBytes = await ExactExportService.buildPdfFromSnapshots(
      <PageSnapshot>[page],
    );
    final pdf = latin1.decode(pdfBytes, allowInvalid: true);
    expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), '%PDF-');
    expect(
      RegExp(r'/Type\s*/Page[^s]').allMatches(pdf).length,
      1,
      reason: 'صفحة واحدة = لقطة واحدة.',
    );
    expect(
      RegExp(r'MediaBox\s*\[0 0 595\.[0-9]+ 841\.[0-9]+\]').hasMatch(pdf),
      isTrue,
      reason: 'مقاس A4 كامل: الصورة تغطي الورقة.',
    );
    expect(RegExp(r'/Subtype\s*/Image').hasMatch(pdf), isTrue,
        reason: 'الصفحة تحمل صورة اللقطة لا نصاً معاد تخطيطه.');
    // مساحة الصفحة في PDF = مساحة الورقة بالضبط (واهم لا يقصّ).
    expect(PaperMetrics.pointsPerPixel, closeTo(0.7497, 0.001));
  });
}
