import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/header_step_screen.dart';
import 'package:writing_questions_app/views/wizard/question_step_screen.dart';

import '../support/production_evidence_fonts.dart';

// Reproduces the Android 050ea screenshot: a semantic Next node exists but is
// geometrically BEHIND the open keyboard. Presence/focus alone cannot pass.
void main() {
  setUpAll(loadProductionEvidenceFonts);
  for (final width in [320.0, 360.0]) {
    for (final header in [true, false]) {
      testWidgets('${header ? 'header' : 'question'} navigation stays above IME at $width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final controller = ExamWizardController();
        if (!header) controller.updateQuestionBody(0, 'Editable العربية 123');
        var submitted = false;
        final screen = header
            ? HeaderStepScreen(
                initialHeader: ExamHeaderModel.initial(subject: 'English العربية 2026'),
                initialFooter: const ExamFooterModel(),
                initialName: 'Keyboard 123',
                initialSettings: const PaperSettings(),
                onNext: (_, __, ___, ____) => submitted = true,
              )
            : QuestionStepScreen(onFinish: () {}, onBack: () {});
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ChangeNotifierProvider<ExamWizardController>.value(
            value: controller, child: screen,
          ),
        ));
        await tester.pumpAndSettle();
        // PointsEditor also owns a FilledButton ('تطبيق'). Never let a
        // generic first-button finder stand in for the actual navigation.
        final next = find.ancestor(
          of: find.text(header ? 'التالي: إعداد السؤال الأول' : 'التالي: سؤال جديد'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        expect(next, findsOneWidget);
        final original = tester.getRect(next);
        for (final inset in [300.0, 0.0, 360.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pumpAndSettle();
          final rect = tester.getRect(next);
          expect(rect.bottom, lessThanOrEqualTo(800 - inset));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(next.hitTestable(), findsOneWidget);
          if (!header) {
            final finish = find.ancestor(
              of: find.text('إنهاء وعرض النموذج'),
              matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
            );
            expect(tester.getRect(finish).bottom, lessThanOrEqualTo(800 - inset));
            expect(finish.hitTestable(), findsOneWidget);
          }
          if (inset == 0) expect(rect, original);
        }
        {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pump();
          if (header) {
            expect(submitted, isTrue);
          } else {
            expect(controller.currentQuestionIndex, 1);
            expect(controller.questions.length, 2);
            expect(controller.questions.first.body, 'Editable العربية 123');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }
}
