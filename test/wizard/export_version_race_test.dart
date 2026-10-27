import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../pdf_engine/pdf_content_probe.dart';
import '../support/production_evidence_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);
  for (final width in [320.0, 360.0]) {
    testWidgets('real export UI refuses superseded bytes after async completion at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ExamWizardController(document: ExamDocument(name: 'Export generation race',
        header: ExamHeaderModel.initial(subject: 'English'), questions: [
          QuestionModel(id: 'export-race', questionNumber: 1, statement: 'OLDEXPORT'),
        ]));
      addTearDown(controller.dispose);
      final release = Completer<void>();
      var encoded = false;
      await tester.pumpWidget(MaterialApp(home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller, child: ExamPreviewScreen(onBackToQuestions: () {},
          pdfDocumentBuilder: ({required ExamDocument document, LayoutDocument? layoutDocument}) async {
            // Generate REAL bytes from the exact snapshot provided by the real
            // review/export UI; only completion timing is controlled.
            final bytes = await PdfExportService.buildDocumentPdfBytes(
              document: document, layoutDocument: layoutDocument);
            expect(PdfContentProbe.fromBytes(bytes).words.any((word) => word.text == 'OLDEXPORT'), isTrue);
            encoded = true;
            await release.future;
            return bytes;
          }))));
      await tester.pumpAndSettle();
      final review = find.byTooltip('مراجعة وتصدير PDF');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.text('مراجعة الورقة'), findsOneWidget);
      await tester.tap(find.text('تصدير PDF'));
      // Allow font/asset/PDF futures to finish, but not the controlled export
      // completion. This models an asynchronous external/keyboard/media update.
      for (var i = 0; i < 500 && !encoded; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(encoded, isTrue);
      controller.updateQuestionStatement(0, 'NEWEXPORT');
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('تغيّر المستند أثناء التصدير. أعد التصدير للنسخة الحالية.'), findsOneWidget);
      expect(find.text('معاينة ورقة الأسئلة'), findsNothing,
        reason: 'Old PDF bytes may not be shown or named as the current version.');
      // Independently inspect a REAL PDF of the now-current snapshot.
      final fresh = await tester.runAsync(() => PdfExportService.buildDocumentPdfBytes(document: controller.document));
      final words = PdfContentProbe.fromBytes(fresh!).words;
      expect(words.any((word) => word.text == 'NEWEXPORT'), isTrue);
      expect(words.any((word) => word.text == 'OLDEXPORT'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
