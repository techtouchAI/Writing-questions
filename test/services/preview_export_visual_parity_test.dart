// التطابق البصري بلا أدوات خارجية: **نفس البكسلات** من المعاينة إلى الملف.
//
// لا يملك هذا الاختبار LibreOffice ولا عارض PDF، لكنه لا يحتاج إليهما في
// النمط الدقيق: التصدير الدقيق يعيد استخدام رسم Flutter نفسه. فيُثبَت هنا
// بالدليل البصري:
//   1. تُرسم صفحة A4 في المعاينة الحقيقية (شاشة `ExamPreviewScreen`).
//   2. يُلتقط جذر اللقط نفسه ([RepaintBoundary]) بالبكسل.
//   3. Word الدقيق يحمل **بايتات PNG نفسها** (تطابق بكسلي بالبناء).
//   4. PDF الدقيق يحمل الصورة بأبعاد البكسل نفسها (`/Width` و`/Height`)،
//      وصفحته A4 كاملة.
//   5. فحوص بصرية على اللقطة نفسها: مقاس الصفحة، وجود حبر، وحدود المحتوى
//      داخل هوامش الطباعة (لا قصّ ولا صفحة فارغة).
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _document() => ExamDocument(
      name: 'تطابق بصري',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      settings: const PaperSettings(),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'القواعد',
          statement: 'اختر الإجابة الصحيحة',
          body: 'اقرأ ثم أجب عن الأسئلة الآتية بعناية',
          marksOverride: 10,
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'أي الكلمات الآتية اسم؟',
              options: <QuestionOption>[
                QuestionOption(text: 'كتاب'),
                QuestionOption(text: 'يكتب'),
                QuestionOption(text: 'مكتوب'),
                QuestionOption(text: 'كاتب'),
              ],
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 4,
              content: BranchContent(
                statement: 'الفرع الأول',
                body: 'اشرح الفرق بين الاسم والفعل',
              ),
            ),
          ],
        ),
      ],
    );

/// لقطة الصفحة الأولى كما رسمها Flutter: PNG + بكسلات RGBA.
class _PreviewCapture {
  _PreviewCapture({
    required this.pngBytes,
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final Uint8List rgba;
  final int width;
  final int height;

  /// هل البكسل حبر؟ تُستثنى حلقة الإطار الخارجية (2px): لوحة المعاينة ترسم
  /// حداً رمادياً وظلاً حول الورقة، وليست جزءاً من المحتوى المطبوع.
  bool isInkAt(int x, int y) {
    const frame = 2;
    if (x < frame || y < frame || x >= width - frame || y >= height - frame) {
      return false;
    }
    final index = (y * width + x) * 4;
    final r = rgba[index];
    final g = rgba[index + 1];
    final b = rgba[index + 2];
    final a = rgba[index + 3];
    return a > 16 && (r < 245 || g < 245 || b < 245);
  }

  /// إطار الحبر (أقصى امتداد للبكسلات غير البيضاء) — يقيس «أين وصل الرسم».
  Rect inkBounds() {
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!isInkAt(x, y)) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }

  int inkInBand(int top, int bottom) {
    var count = 0;
    for (var y = top; y < bottom && y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isInkAt(x, y)) {
          count++;
        }
      }
    }
    return count;
  }
}

Future<_PreviewCapture> _capturePreviewPage(WidgetTester tester) async {
  // جذر اللقط هو أول RepaintBoundary بمقاس لوحة A4 في شجرة المعاينة.
  RenderRepaintBoundary? pageBoundary;
  for (final boundary
      in tester.renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))) {
    if (boundary.size.width == ExamCanvasGeometry.width &&
        boundary.size.height == ExamCanvasGeometry.height) {
      pageBoundary = boundary;
      break;
    }
  }
  expect(pageBoundary, isNotNull,
      reason: 'لم أجد جذر لقط الصفحة (RepaintBoundary بمقاس A4) في المعاينة.');

  final capture = await tester.runAsync(() async {
    final image = await pageBoundary!.toImage(pixelRatio: 1);
    final width = image.width;
    final height = image.height;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return _PreviewCapture(
      pngBytes: png!.buffer.asUint8List(),
      rgba: rgba!.buffer.asUint8List(),
      width: width,
      height: height,
    );
  });
  expect(capture, isNotNull);
  return capture!;
}

void main() {
  testWidgets('لقطة المعاينة = صور الملفات الدقيقة، والمحتوى داخل الهوامش',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = ExamWizardController(document: _document());
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: ExamPreviewScreen(onBackToQuestions: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final capture = await _capturePreviewPage(tester);

    // (1) مقاس اللقطة = لوحة A4 بالبكسل (794×1123 عند 96dpi).
    expect(capture.width, ExamCanvasGeometry.width.round());
    expect(capture.height, ExamCanvasGeometry.height.round());

    // (2) فحوص بصرية على الصفحة: حبر في الترويسة وحبر في المتن.
    final ink = capture.inkBounds();
    expect(ink.width, greaterThan(100), reason: 'الصفحة ليست فارغة.');
    expect(capture.inkInBand(0, 180), greaterThan(200),
        reason: 'يوجد حبر في نطاق الترويسة (أعلى الصفحة).');
    expect(capture.inkInBand(200, capture.height - 200), greaterThan(200),
        reason: 'يوجد حبر في نطاق الأسئلة (وسط الصفحة).');

    // (3) لا قصّ: كل الحبر داخل هوامش الطباعة (15مم ≈ 57px) بهامش سماح
    //     للحدود والظل الخارجي للوحة المعاينة.
    const margin = 15 / 25.4 * 96; // 15mm بالبكسل
    expect(ink.left, greaterThanOrEqualTo(margin - 8),
        reason: 'المحتوى لا يدخل الهامش الأيسر: ${ink.left}.');
    expect(ink.right, lessThanOrEqualTo(capture.width - margin + 8),
        reason: 'المحتوى لا يدخل الهامش الأيمن.');
    expect(ink.top, greaterThanOrEqualTo(4),
        reason: 'الترويسة لا تخرج من أعلى الصفحة.');
    expect(ink.bottom, lessThanOrEqualTo(capture.height - 4),
        reason: 'المحتوى لا يخرج من أسفل الصفحة.');

    // (4) Word الدقيق: بايتات PNG نفسها — تطابق بكسلي بالبناء.
    final snapshot = PageSnapshot(
      pageIndex: 0,
      pngBytes: capture.pngBytes,
      widthPx: ExamCanvasGeometry.width,
      heightPx: ExamCanvasGeometry.height,
    );
    final docxBytes = ExactExportService.buildDocxFromSnapshots(
      <PageSnapshot>[snapshot],
    );
    final archive = ZipDecoder().decodeBytes(docxBytes);
    expect(
      archive.findFile('word/media/page1.png')!.content,
      equals(capture.pngBytes),
      reason: 'Word الدقيق يحمل بكسلات المعاينة كما هي (لا إعادة رسم).',
    );

    // (5) PDF الدقيق: الصورة بأبعاد البكسل نفسها والصفحة A4 كاملة.
    final pdfBytes = await ExactExportService.buildPdfFromSnapshots(
      <PageSnapshot>[snapshot],
    );
    final pdf = latin1.decode(pdfBytes, allowInvalid: true);
    expect(pdf.contains('/Width ${capture.width}'), isTrue,
        reason: 'PDF يحمل الصورة بعرض بكسلات المعاينة (لا تحجيم).');
    expect(pdf.contains('/Height ${capture.height}'), isTrue,
        reason: 'PDF يحمل الصورة بارتفاع بكسلات المعاينة.');
    expect(
      RegExp(r'MediaBox\s*\[0 0 595\.[0-9]+ 841\.[0-9]+\]').hasMatch(pdf),
      isTrue,
      reason: 'الصفحة A4 كاملة: نسبة الصورة إلى الصفحة غير محرَّفة.',
    );
  });
}
