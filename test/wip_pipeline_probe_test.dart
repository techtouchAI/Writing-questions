// ملف تشخيصي مؤقّت (يُحذف بعد إغلاق العطل): يقيس أين يتوقّف — أو يبطؤ —
// مسار المعاينة القانونية داخل `flutter test` نفسه، بأسطر تُطبع فوراً.
//
// السؤال العملي: هل يكفي «المضخة» وحدها لبلوغ الصفحات؟ أم يلزم تبديل المضخة
// بنافذة زمن حقيقي كما تفعل ركيزة الانحدار البصري؟
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
      ],
    );

void _mark(String message) {
  // ignore: avoid_print
  print('[probe] $message');
}

Future<void> _install(WidgetTester tester, ExamWizardController controller) async {
  tester.view.physicalSize = const Size(1600, 1240);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probeA: canonical resolve awaited in the fake zone', (tester) async {
    final stopwatch = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    var state = 'pending';
    unawaited(CanonicalLayoutService.resolve(
      document: controller.document,
      sourceIr: controller.documentIr,
    ).then<void>(
      (layout) => state = 'ok pages=${layout.pageCount}',
      onError: (Object error) => state = 'error $error',
    ));
    for (var pump = 0; pump < 20 && state == 'pending'; pump++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    _mark('A state=$state elapsed=${stopwatch.elapsedMilliseconds}ms');
  });

  testWidgets('probeB: canonical resolve inside runAsync', (tester) async {
    final stopwatch = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    try {
      final layout = await tester.runAsync(
        () => CanonicalLayoutService.resolve(
          document: controller.document,
          sourceIr: controller.documentIr,
        ).timeout(const Duration(seconds: 60)),
      );
      _mark('B pages=${layout?.pageCount} elapsed=${stopwatch.elapsedMilliseconds}ms');
    } catch (error) {
      _mark('B threw $error elapsed=${stopwatch.elapsedMilliseconds}ms');
    }
  });

  testWidgets('probeB2: fonts then resolve inside runAsync', (tester) async {
    final stopwatch = Stopwatch()..start();
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    try {
      await tester.runAsync(
        () => FlutterTextMetrics.ensureFontsLoaded()
            .timeout(const Duration(seconds: 60)),
      );
      _mark('B2 fonts done elapsed=${stopwatch.elapsedMilliseconds}ms '
          '(starts=${FlutterTextMetrics.debugRegistrationStarts}, '
          'completed=${FlutterTextMetrics.debugRegistrationCompleted})');
      final layout = await tester.runAsync(
        () => CanonicalLayoutService.resolve(
          document: controller.document,
          sourceIr: controller.documentIr,
        ).timeout(const Duration(seconds: 60)),
      );
      _mark('B2 pages=${layout?.pageCount} elapsed=${stopwatch.elapsedMilliseconds}ms');
    } catch (error) {
      _mark('B2 threw $error elapsed=${stopwatch.elapsedMilliseconds}ms');
    }
  });

  test('probeC: canonical resolve in a plain test (real async)', () async {
    final stopwatch = Stopwatch()..start();
    try {
      final layout = await CanonicalLayoutService.resolve(document: _doc())
          .timeout(const Duration(seconds: 120));
      _mark('C pages=${layout.pageCount} elapsed=${stopwatch.elapsedMilliseconds}ms '
          '(starts=${FlutterTextMetrics.debugRegistrationStarts}, '
          'completed=${FlutterTextMetrics.debugRegistrationCompleted})');
    } catch (error) {
      _mark('C threw $error elapsed=${stopwatch.elapsedMilliseconds}ms');
    }
  });

  testWidgets('probeD: pump-only driver', (tester) async {
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    await _install(tester, controller);
    var pages = 0;
    var attempt = 0;
    for (; attempt < 40 && pages == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      pages = find.byType(CanonicalLayoutPreviewPage).evaluate().length;
    }
    _mark('D pages=$pages attempts=$attempt '
        'fields=${find.byType(TextField).evaluate().length}');
  });

  testWidgets('probeF: pump plus real-async alternation driver', (tester) async {
    final controller = ExamWizardController(document: _doc());
    addTearDown(controller.dispose);
    await _install(tester, controller);
    var pages = 0;
    var attempt = 0;
    for (; attempt < 80 && pages == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      pages = find.byType(CanonicalLayoutPreviewPage).evaluate().length;
    }
    if (pages > 0) {
      await tester.pumpAndSettle();
    }
    _mark('F pages=$pages attempts=$attempt '
        'fields=${find.byType(TextField).evaluate().length} '
        '(starts=${FlutterTextMetrics.debugRegistrationStarts}, '
        'completed=${FlutterTextMetrics.debugRegistrationCompleted})');
  });
}
