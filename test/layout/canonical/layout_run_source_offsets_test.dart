import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

const String _source =
    'alpha\u00A0beta gamma delta epsilon zeta eta theta iota kappa lambda mu';

ExamDocument _document(String body) => ExamDocument(
      name: 'LayoutRun source offsets',
      header: ExamHeaderModel(subject: 'English'),
      settings: const PaperSettings(marginMm: 10),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'offset-q1',
          questionNumber: 1,
          statement: 'Source offsets',
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

List<LayoutRun> _runsForSource(LayoutDocument layout, String source) =>
    layout.allLines
        .expand((line) => line.runs)
        .where((run) => run.semanticNode?.legacyText == source)
        .toList(growable: false);

void _expectOffsetsReferToSource(List<LayoutRun> runs, String source) {
  expect(runs, isNotEmpty, reason: 'No runs retained the source text node.');
  for (final run in runs) {
    expect(run.sourceStartOffset, greaterThanOrEqualTo(0));
    expect(run.sourceEndOffset, greaterThan(run.sourceStartOffset));
    expect(run.sourceEndOffset, lessThanOrEqualTo(source.length));
    expect(
      source.substring(run.sourceStartOffset, run.sourceEndOffset),
      run.text,
      reason: 'Run ${run.id} does not map back to its exclusive UTF-16 source range.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test('LayoutRun exposes source intervals after wrapping and page placement', () {
    final layout = _layout(_document(_source), pageHeightPt: 1000);
    final runs = _runsForSource(layout, _source);
    _expectOffsetsReferToSource(runs, _source);

    expect(
      runs.any((run) => run.sourceStartOffset > 0),
      isTrue,
      reason: 'The wrapped source was not split into later source intervals.',
    );
    final ordered = List<LayoutRun>.of(runs)
      ..sort((a, b) => a.sourceStartOffset.compareTo(b.sourceStartOffset));
    expect(ordered.first.sourceStartOffset, 0);
    expect(ordered.last.sourceEndOffset, _source.length);
    for (var index = 0; index + 1 < ordered.length; index++) {
      expect(
        ordered[index].sourceEndOffset,
        lessThanOrEqualTo(ordered[index + 1].sourceStartOffset),
        reason: 'Source intervals overlap or run order was corrupted.',
      );
    }
  });

  test('source intervals survive line slicing across page fragments', () {
    final source = List<String>.filled(20, _source).join(' ');
    final layout = _layout(_document(source), pageHeightPt: 180);
    final questionFragments = layout.pages
        .expand((page) => page.blocks)
        .where((block) => block.semanticNodeId == 'offset-q1')
        .toList(growable: false);
    expect(questionFragments.length, greaterThan(1));
    expect(questionFragments.every((block) => block.split.isSplit), isTrue);

    final runs = _runsForSource(layout, source);
    _expectOffsetsReferToSource(runs, source);
  });

  test('mixed text/math runs keep offsets in the original editable field', () {
    const source = r'قبل المعادلة $x+1$ وبعدها English 42';
    final layout = _layout(_document(source), pageHeightPt: 1000);
    final runs = layout.allLines.expand((line) => line.runs).toList();
    final math = runs.singleWhere((run) => run.isMath);
    final before = runs.singleWhere((run) => run.text.contains('قبل'));
    final after = runs.singleWhere((run) => run.text.contains('وبعدها'));

    expect(source.substring(math.sourceStartOffset, math.sourceEndOffset), r'$x+1$');
    expect(
      source.substring(before.sourceStartOffset, before.sourceEndOffset),
      before.text,
    );
    expect(
      source.substring(after.sourceStartOffset, after.sourceEndOffset),
      after.text,
    );
    expect(after.sourceStartOffset, greaterThan(math.sourceEndOffset));
  });

  test('escaped dollar hit offsets map back across the removed source slash', () {
    const source = r'price \$5 then $x$';
    final layout = _layout(_document(source), pageHeightPt: 1000);
    final runs = layout.allLines.expand((line) => line.runs).toList();
    final plain = runs.singleWhere((run) => run.text.contains(r'$5'));
    final displayedDollar = plain.text.indexOf(r'$');
    final sourceMap = plain.sourceOffsetMap;

    expect(plain.text, contains(r'$5'));
    expect(sourceMap, isNotNull);
    expect(sourceMap!.length, plain.text.length + 1);
    final sourceSlash = source.indexOf(r'\$');
    expect(sourceMap[displayedDollar], sourceSlash);
    expect(sourceMap[displayedDollar + 1], sourceSlash + 2);
  });
}
