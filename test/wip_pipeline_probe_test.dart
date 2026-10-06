// ملف تشخيصي مؤقّت: يقيس أين تتعطّل (أو تبطؤ) مسارات البناء في بيئة
// `flutter test` نفسها، بأسطر تُطبع فور وقوعها. لا يبقى هذا الملف بعد
// إغلاق العطل.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _doc() => ExamDocument(
      name: 'probe',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'p-q1',
          questionNumber: 1,
          statement: r'أوجد قيمة $x$ في المعادلة $x^2+2x+1=0$.',
          body: 'نص توضيحي لاختبار القياس والتقسيم على الصفحة.',
        ),
        QuestionModel(
          id: 'p-q2',
          questionNumber: 2,
          statement: 'سؤال ثانٍ لضمان التدفق إلى أكثر من صفحة عند اللزوم.',
          body: '${'كلمات متتابعة لملء السطر واختبار التدفق. ' * 40}',
        ),
      ],
    );

void _mark(String message) {
  // ignore: avoid_print
  print('[probe] $message');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probeA: canonical resolve awaited in the fake zone',
      (tester) async {
    final sw = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    _mark('A begin');
    var state = 'pending';
    final pending = CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    ).then<void>(
      (layout) {
        state = 'ok pages=${layout.pageCount}';
      },
      onError: (Object error) {
        state = 'error $error';
      },
    );
    unawaited(pending);
    var pumps = 0;
    for (; pumps < 20 && state == 'pending'; pumps++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    _mark('A state=$state pumps=$pumps elapsed=${sw.elapsedMilliseconds}ms');
  });

  testWidgets('probeB: canonical resolve inside runAsync', (tester) async {
    final sw = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: controller.document,
        sourceIr: controller.documentIr,
      ),
    );
    _mark('B pages=${layout?.pageCount} elapsed=${sw.elapsedMilliseconds}ms');
  });

  testWidgets('probeB2: fonts then resolve inside runAsync', (tester) async {
    final sw = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    final fonts = await tester.runAsync(() async {
      await FlutterTextMetrics.ensureFontsLoaded();
      return sw.elapsedMilliseconds;
    });
    _mark('B2 fonts done elapsed=${fonts}ms');
    final layout = await tester.runAsync(
      () => CanonicalLayoutService.resolve(
        document: controller.document,
        sourceIr: controller.documentIr,
      ),
    );
    _mark('B2 pages=${layout?.pageCount} elapsed=${sw.elapsedMilliseconds}ms');
  });

  test('probeC: canonical resolve in a plain test (real async)', () async {
    final sw = Stopwatch()..start();
    final layout = await CanonicalLayoutService.resolve(document: _doc());
    _mark('C pages=${layout.pageCount} elapsed=${sw.elapsedMilliseconds}ms');
  });

  testWidgets('probeD: preview screen drives canonical pages', (tester) async {
    final sw = Stopwatch()..start();
    tester.view.physicalSize = const Size(1600, 1240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: ExamPreviewScreen(onBackToQuestions: () {}),
        ),
      ),
    );
    _mark('D pumped widget at ${sw.elapsedMilliseconds}ms');
    var pumps = 0;
    for (; pumps < 30; pumps++) {
      await tester.pump(const Duration(milliseconds: 100));
      final found = find.byType(CanonicalLayoutPreviewPage).evaluate().length;
      if (found > 0) {
        _mark('D pages=$found at pump $pumps (${sw.elapsedMilliseconds}ms)');
        break;
      }
    }
    _mark(
      'D final pages=' 
      '${find.byType(CanonicalLayoutPreviewPage).evaluate().length} '
      'pumps=$pumps elapsed=${sw.elapsedMilliseconds}ms',
    );
  });

  testWidgets('probeE: editable DOCX build stages and timing', (tester) async {
    final sw = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    final bytes = await tester.runAsync(() async {
      final input =
          await DocxDocumentExportService.resolveEditablePaginationInput(
        document: controller.document,
        sourceIr: controller.documentIr,
      );
      _mark('E pagination input at ${sw.elapsedMilliseconds}ms');
      final built = await DocxDocumentExportService.buildDocumentDocxBytes(
        document: controller.document,
        legacyPaginationInput: input,
        onProgress: (stage) => _mark('E +${sw.elapsedMilliseconds}ms $stage'),
      ).timeout(const Duration(minutes: 3));
      return built.length;
    });
    _mark('E done bytes=$bytes elapsed=${sw.elapsedMilliseconds}ms');
  });
}
