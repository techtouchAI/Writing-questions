// Historical standalone reconstruction retained, NOT the measurement of the
// rendered fixture. In particular this runs without MathSnapshotHost, so the
// layout service may use fallback math metrics. Never overwrite the live-plan
// positions captured by visual_parity_fixture_test.dart.
// [C6-POS] TEMPORARY Preview text-position probe (non-gating). Not for merge.
//
// Question: where does the Preview paint each word and each line baseline, in
// the same layout points that the vector PDF uses? This file only records
// measurements. It changes no production file and asserts nothing about the
// gate. The PDF side is read by tool/diag_c6_text_positions.py from the gate's
// own vector.pdf, and the two are compared there.
//
// The Preview side mirrors CanonicalLayoutPreviewPage._paintRun and
// _paintText (lib/layout/canonical/canonical_layout_preview.dart): the same
// skip rule, the same TextStyle fields, the same TextPainter configuration, and
// the same paint offset (line.baseline - baselineOffset). The layout is
// resolved exactly as ExamPreviewScreen does, with controller.document and
// controller.documentIr.
//
// Output: build/visual_parity/c6diag/text_positions/reconstructed_positions.json
// Runs only in the c6-diagnostics CI job, with continue-on-error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

import 'visual_parity_fixture_test.dart' as fixture;
import '../support/c6_preview_positions.dart';

const String _outDir = 'build/visual_parity/c6diag/text_positions';
const String _outFile = '$_outDir/reconstructed_positions.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[C6-POS] Preview text positions (non-gating)',
    (tester) async {
      await tester.runAsync(() async {
        await fixture.loadAppFonts();
        final controller = ExamWizardController(
          document: fixture.fixtureDocument(),
        );
        final layout = await CanonicalLayoutService.resolve(
          document: controller.document,
          sourceIr: controller.documentIr,
        );
        controller.dispose();

        final out = c6PreviewPositions(layout, sourceKind: 'standalone-reconstruction');
        Directory(_outDir).createSync(recursive: true);
        File(_outFile).writeAsStringSync(jsonEncode(out));
        expect(out['pages'], isNotEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
