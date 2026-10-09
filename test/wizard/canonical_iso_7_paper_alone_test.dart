import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

// Round-4 isolation for canonical E7: does the post-teardown 120s failure
// reproduce ALONE in a fresh isolate? If this passes, E7's failure is
// order-dependent (needs preceding tests); if it fails at 120s with body +
// teardown prints complete, the mechanism lives in the paper flow itself.

const String _hitMarker = 'CANONICALMARKER';

ExamDocument _document({
  String subject = 'English',
  String statement = 'Tap the $_hitMarker in this question.',
  String body = 'The body stays on the canonical page geometry.',
}) =>
    ExamDocument(
      name: 'Canonical preview interaction',
      header: ExamHeaderModel.initial(subject: subject),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'canonical-hit-question',
          questionNumber: 1,
          statement: statement,
          body: body,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iso-7: seam-free paper screen alone in a fresh isolate',
      (tester) async {
    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(() {
      debugPrint('[diag] iso-7: disposing');
      controller.dispose();
      debugPrint('[diag] iso-7: disposed');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: ExamPreviewScreen(onBackToQuestions: () {}),
        ),
      ),
    );
    debugPrint('[diag] iso-7: pumped widget');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('[diag] iso-7: pumped frames');

    expect(find.byType(CanonicalLayoutPreviewPage), findsNothing);
    expect(find.textContaining(_hitMarker), findsWidgets);
    expect(tester.takeException(), isNull);
    debugPrint('[diag] iso-7: done');
  },
          // Fail-fast bound (tightening, not loosening): healthy work here is
          // seconds; 120s bounds only hangs, 5x faster than the 600s default.
          timeout: const Timeout(Duration(seconds: 120)));
}
