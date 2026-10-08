// Canonical word geometry: every text run exposes its measurable words with
// visual positions resolved by the same caret machinery as the run box, so
// positioned emitters can place words without measuring anything themselves.
// These invariants must survive wrapping, pagination moves, scaling, both
// text directions, NBSP-glued tokens, and diacritic-heavy verse words.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

/// FP-noise allowance for px→pt round-trips. Word pitches are differences of
/// converted caret positions, so closure holds up to floating-point rounding,
/// never up to a behavioral tolerance.
const double _fpEpsilon = 1e-6;

ExamDocument _document(String body) => ExamDocument(
      name: 'LayoutRun words',
      header: ExamHeaderModel(subject: 'English'),
      settings: const PaperSettings(marginMm: 10),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'words-q1',
          questionNumber: 1,
          statement: 'Words',
          body: body,
        ),
      ],
    );

LayoutDocument _layout(ExamDocument document, {required double pageHeightPt}) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  final configuration = ExamDocumentLayoutAdapter.configurationFor(
    document,
    pageSize: LayoutSize(width: 180, height: pageHeightPt),
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: configuration,
    fontMetrics: const FlutterTextMetrics(),
  );
}

List<String> _expectedPieces(String text) => canonicalWordPattern
    .allMatches(text)
    .map((match) => match.group(0)!)
    .toList(growable: false);

void _expectWordInvariants(LayoutDocument layout) {
  var textRuns = 0;
  for (final line in layout.allLines) {
    for (final run in line.runs) {
      if (run.isMath || run.isImage) {
        expect(run.words, isEmpty,
            reason: 'Run ${run.id} is not shaped text; it must carry no words.');
        continue;
      }
      final pieces = _expectedPieces(run.text);
      if (pieces.isEmpty) {
        expect(run.words, isEmpty,
            reason: 'Run ${run.id} has no word text; it must carry no words.');
        continue;
      }
      textRuns++;
      expect(
        run.words.map((word) => word.text).toList(growable: false),
        pieces,
        reason: 'Run ${run.id} words must be its whitespace split in order.',
      );
      // Structural: fragments are ICU words (never two ASCII-separated
      // words), so a text run carries at most one word. The PDF emitter
      // underlines per emitted word; if this ever fails, per-word emission
      // needs run-continuous underline rules before landing.
      expect(
        run.words.length,
        lessThanOrEqualTo(1),
        reason: 'Run ${run.id} carries more than one word.',
      );
      for (final word in run.words) {
        expect(word.x.isFinite, isTrue, reason: 'Run ${run.id} word x finite.');
        expect(word.advance, greaterThanOrEqualTo(0),
            reason: 'Run ${run.id} word advance must never be negative.');
      }
      if (run.direction == DocumentDirection.ltr) {
        for (var index = 0; index + 1 < run.words.length; index++) {
          expect(
            run.words[index].advance,
            closeTo(
              run.words[index + 1].x - run.words[index].x,
              _fpEpsilon,
            ),
            reason: 'Run ${run.id} LTR pitch must reach the next word.',
          );
        }
        final last = run.words.last;
        expect(
          last.x + last.advance,
          closeTo(run.x + run.width, _fpEpsilon),
          reason: 'Run ${run.id} last word must close on the run right edge.',
        );
        expect(last.x, greaterThanOrEqualTo(run.x - _fpEpsilon));
      } else {
        for (var index = 0; index + 1 < run.words.length; index++) {
          expect(
            run.words[index].advance,
            closeTo(
              run.words[index].x - run.words[index + 1].x,
              _fpEpsilon,
            ),
            reason: 'Run ${run.id} RTL pitch must reach the next word.',
          );
        }
        final last = run.words.last;
        expect(
          last.x - last.advance,
          closeTo(run.x, _fpEpsilon),
          reason: 'Run ${run.id} last word must close on the run left edge.',
        );
        expect(last.x - last.advance, greaterThanOrEqualTo(run.x - _fpEpsilon));
      }
    }
  }
  expect(textRuns, greaterThan(0), reason: 'No text runs measured.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test('word geometry closes on every run, tall and paginated', () {
    const body =
        'alpha\u00A0beta  gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau';
    _expectWordInvariants(_layout(_document(body), pageHeightPt: 1000));
    _expectWordInvariants(_layout(_document(body), pageHeightPt: 120));
  });

  test('word geometry holds for RTL Arabic with diacritics', () {
    const body = 'اقرأ النص ثم أجب: ﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾ (٢٠ درجة)';
    _expectWordInvariants(_layout(_document(body), pageHeightPt: 1000));
    _expectWordInvariants(_layout(_document(body), pageHeightPt: 120));
  });

  test('NBSP-glued tokens stay one word (never split like ASCII space)', () {
    // ECMAScript \s matches NBSP; the canonical word notion must not, or
    // glued tokens such as NBSP-joined numbers tear apart downstream.
    const body = 'alpha\u00A0beta gamma';
    final layout = _layout(_document(body), pageHeightPt: 1000);
    final runs = layout.allLines
        .expand((line) => line.runs)
        .where((run) => run.text.contains('alpha'))
        .toList(growable: false);
    expect(runs, hasLength(1));
    expect(
      runs.single.words.map((word) => word.text).toList(growable: false),
      <String>['alpha\u00A0beta'],
    );
  });
}
