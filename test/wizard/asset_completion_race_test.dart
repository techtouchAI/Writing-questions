import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../pdf_engine/pdf_content_probe.dart';
import '../support/production_evidence_fonts.dart';

Future<({CanonicalLayoutPreviewAssets assets, Uint8List png})> _image(WidgetTester tester, Color color) async {
  final value = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return (assets: CanonicalLayoutPreviewAssets(floatingImages: {'race-image': image}),
      png: data!.buffer.asUint8List());
  });
  return value!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);
  for (final width in [320.0, 360.0]) {
    testWidgets('late decoded image cannot replace current media; export while old assets pending at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = await _image(tester, const Color(0xffff0000));
      final current = await _image(tester, const Color(0xff00ff00));
      final initial = ExamDocument(name: 'Real media completion race',
        header: ExamHeaderModel.initial(subject: 'English'), questions: [
          QuestionModel(id: 'media-owner', questionNumber: 1, statement: 'OLDASSET'),
        ], floatingElements: [FloatingElement(id: 'race-image', type: FloatingElementType.image,
          bytes: old.png, dx: 80, dy: 220, width: 40, height: 40)]);
      final controller = ExamWizardController(document: initial);
      addTearDown(controller.dispose);
      final delayed = Completer<CanonicalLayoutPreviewAssets>();
      var started = false;
      await tester.pumpWidget(MaterialApp(home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller, child: ExamPreviewScreen(onBackToQuestions: () {},
          canonicalLayoutResolver: ({required ExamDocument document, required DocumentIR sourceIr}) =>
            CanonicalLayoutService.resolve(document: document, sourceIr: sourceIr),
          canonicalPreviewAssetLoader: ({required LayoutDocument layout, required ExamDocument document}) {
            if (identical(document, initial)) { started = true; return delayed.future; }
            return Future.value(current.assets);
          }))));
      for (var i = 0; i < 500 && !started; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(started, isTrue);
      controller.updateQuestionStatement(0, 'NEWASSET');
      controller.updateFloatingElement(controller.document.floatingElements.single.copyWith(bytes: current.png));
      for (var i = 0; i < 500 && find.byType(CanonicalLayoutPreviewPage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(find.byType(CanonicalLayoutPreviewPage), findsOneWidget);
      final displayed = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage));
      expect(displayed.assets, same(current.assets));
      expect(identical(displayed.layoutDocument.source, controller.documentIr), isTrue);
      // The old decoding future is STILL pending during a real new-version PDF.
      final bytes = await tester.runAsync(() => PdfExportService.buildDocumentPdfBytes(
        document: controller.document, layoutDocument: displayed.layoutDocument));
      final pdf = PdfContentProbe.fromBytes(bytes!);
      expect(pdf.words.any((word) => word.text == 'NEWASSET'), isTrue);
      expect(pdf.words.any((word) => word.text == 'OLDASSET'), isFalse);
      expect(pdf.imageCount, 1, reason: 'The currently loaded media must not be missing from the actual PDF.');
      delayed.complete(old.assets);
      await tester.pumpAndSettle();
      final afterLate = tester.widget<CanonicalLayoutPreviewPage>(find.byType(CanonicalLayoutPreviewPage));
      expect(afterLate.assets, same(current.assets));
      final rgba = await tester.runAsync(() => afterLate.assets.floatingImages['race-image']!
        .toByteData(format: ui.ImageByteFormat.rawRgba));
      expect(rgba!.buffer.asUint8List().take(4), [0, 255, 0, 255],
        reason: 'Actual decoded preview pixels remain new/green, not late old/red.');
      expect(tester.takeException(), isNull);
    });
  }
}
