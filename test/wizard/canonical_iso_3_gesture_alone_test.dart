import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_interaction.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

// Round-4 isolation for canonical test-3: does the startGesture/moveTo hang
// reproduce in a FRESH isolate with no preceding tests? If this hangs before
// 'moved', gesture dispatch itself is broken; if it passes, test-3's hang is
// order-dependent (wedged by an earlier test's leftovers).

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 40,
}) async {
  for (var attempt = 0; attempt < maxFrames && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _screenCanonical(ExamWizardController controller) => MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(
          onBackToQuestions: () {},
          canonicalLayoutResolver: ({
            required ExamDocument document,
            required DocumentIR sourceIr,
          }) =>
              CanonicalLayoutService.resolve(
            document: document,
            sourceIr: sourceIr,
          ),
          canonicalPreviewAssetLoader: ({
            required LayoutDocument layout,
            required ExamDocument document,
          }) =>
              CanonicalLayoutPreviewAssets.load(
            layout: layout,
            document: document,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iso-3: canonical floating drag alone in a fresh isolate',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const bodyPart =
        'هذا نص طويل يحافظ على حدود الصفحات ويضمن وجود صفحة هدف مستقلة '
        'لتحريك العنصر العائم إليها.';
    final document = ExamDocument(
      name: 'RTL floating page drag',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'drag-to-later-page',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 120,
          dy: 220,
          pageIndex: 1,
          width: 90,
          height: 80,
        ),
      ],
      questions: <QuestionModel>[
        QuestionModel(
          id: 'drag-pagination-question',
          questionNumber: 1,
          statement: 'ابدأ من RTL ثم English 123',
          body: List<String>.filled(200, bodyPart).join(' '),
        ),
      ],
    );
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_screenCanonical(controller));
    await _pumpUntil(
      tester,
      () => find.byType(CanonicalLayoutPreviewPage).evaluate().isNotEmpty,
    );
    debugPrint('[diag] iso-3: page found');

    final preview = tester.widget<CanonicalLayoutPreviewPage>(
      find.byKey(const ValueKey<String>('canonical-preview-page-1')),
    );
    final layout = preview.layoutDocument;
    expect(layout.pageCount, greaterThan(2));
    expect(identical(layout.source, controller.documentIr), isTrue);
    final sourcePage = layout.pages[1];
    final targetPage = layout.pages[2];
    final float = sourcePage.floatingElements.singleWhere(
      (placement) => placement.reference.id == 'drag-to-later-page',
    );
    final sourcePageRect = tester.getRect(
      find.byKey(const ValueKey<String>('canonical-preview-page-1')),
    );
    final targetPageRect = tester.getRect(
      find.byKey(const ValueKey<String>('canonical-preview-page-2')),
    );
    final sourceTransform = CanonicalPageTransform(
      screenLeft: sourcePageRect.left,
      screenTop: sourcePageRect.top,
      screenWidth: sourcePageRect.width,
      screenHeight: sourcePageRect.height,
      pageWidthPt: sourcePage.pageSize.width,
      pageHeightPt: sourcePage.pageSize.height,
    );
    final targetTransform = CanonicalPageTransform(
      screenLeft: targetPageRect.left,
      screenTop: targetPageRect.top,
      screenWidth: targetPageRect.width,
      screenHeight: targetPageRect.height,
      pageWidthPt: targetPage.pageSize.width,
      pageHeightPt: targetPage.pageSize.height,
    );
    final start = sourceTransform.screenPointFromPage(
      float.rect.left + float.rect.width / 2,
      float.rect.top + float.rect.height / 2,
    );
    final destination = targetTransform.screenPointFromPage(
      targetPage.pageSize.width / 2,
      targetPage.pageSize.height / 2,
    );
    debugPrint('[diag] iso-3: sighting done');

    final gesture = await tester.startGesture(Offset(start.x, start.y));
    debugPrint('[diag] iso-3: gesture started');
    await gesture.moveTo(Offset(destination.x, destination.y));
    debugPrint('[diag] iso-3: moved');
    await tester.pump(const Duration(milliseconds: 20));
    debugPrint('[diag] iso-3: pumped');
    await gesture.up();
    debugPrint('[diag] iso-3: up');
    await _pumpUntil(
      tester,
      () => controller.document.floatingElements.single.pageIndex == 2,
    );
    debugPrint('[diag] iso-3: dropped');

    expect(
      controller.document.floatingElements.single.pageIndex,
      2,
      reason: 'The canonical pointer must resolve the later page under the drag.',
    );
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-3: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));
}
