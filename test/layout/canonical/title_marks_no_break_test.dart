// قاعدة طباعية: موضع درجة السؤال في نهاية سطر العنوان — لا تُفصل عنه.
//
// الحكم على `LayoutDocument` نفسه (المصدر الوحيد الذي يرسمه Preview وPDF)،
// لا على صورة ولا على «شكل مقبول»:
//   1. مجموعة الدرجة `(٢٠ درجة)` لا تنقسم بين سطرين.
//   2. لا تبدأ سطرًا وحدها: سطرها يحمل كلمة من عنوان السؤال.
//   3. موضعها نهاية السطر في سياق RTL: كل جريانات العنوان في سطرها إلى يمينها.
//
// الحالات: عنوان قصير يتّسع في سطر، وعنوان طويل يلتف، وهامش ضيّق يجبر الالتفاف
// (قاعدة العرض متغيّرة، لا إحداثيات ثابتة).
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

const String _shortStatement = 'أكمل المعادلة';

const String _longStatement =
    'اشرح دلالة الاستعارة في البيت الشعري الآتي ثم بيّن أثرها في المعنى العام '
    'ووازن بينها وبين الكناية في البيت الثاني مع التعليل';

ExamDocument _document({
  required String statement,
  double marginMm = 15,
}) =>
    ExamDocument(
      name: 'ركيزة درجة السؤال',
      header: ExamHeaderModel(subject: 'اللغة العربية'),
      settings: PaperSettings(
        marginMm: marginMm,
        showQuestionMarks: true,
        autoNumberQuestions: true,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: statement,
          marksOverride: 20,
        ),
      ],
    );

LayoutDocument _layout(ExamDocument document) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: ExamDocumentLayoutAdapter.configurationFor(document),
    fontMetrics: const FlutterTextMetrics(),
  );
}

Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    yield* _allBlocks(block.children);
  }
}

List<LayoutLine> _titleLines(LayoutDocument layout) {
  for (final page in layout.pages) {
    for (final block in _allBlocks(page.blocks)) {
      if (block.kind == LayoutBlockKind.title) {
        return block.allLines.toList(growable: false);
      }
    }
  }
  throw StateError('لا كتلة عنوان في التخطيط.');
}

bool _isMarks(LayoutRun run) =>
    run.semanticRole == LayoutSemanticRole.marks ||
    run.contentKind == LayoutContentKind.marks;

String _describe(LayoutLine line) =>
    '[${line.runs.map((run) => '"${run.text}"@${run.x.toStringAsFixed(1)}${_isMarks(run) ? "*" : ""}').join(' ')}]';

/// يفحص القاعدة ويعيد (عدد أسطر العنوان، عدد أسطر الدرجة).
({int titleLines, int marksLines}) _expectMarksRule(
  LayoutDocument layout, {
  required String caseName,
}) {
  final lines = _titleLines(layout);
  final marksLineIndices = <int>{};
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].runs.any(_isMarks)) {
      marksLineIndices.add(index);
    }
  }
  expect(marksLineIndices, isNotEmpty,
      reason: '[$caseName] لا مجموعة درجة في التخطيط — الاختبار لم يقس شيئًا.');

  // (1) لا انقسام: مجموعة الدرجة كلها في سطر واحد.
  expect(
    marksLineIndices.length,
    1,
    reason: '[$caseName] مجموعة الدرجة انقسمت على ${marksLineIndices.length} '
        'سطرًا: ${lines.map(_describe).toList()}',
  );

  final line = lines[marksLineIndices.single];
  // (2) لا تنفرد بسطر: معها كلمة من العنوان.
  final statementRuns = line.runs
      .where((run) => !_isMarks(run) && run.text.trim().isNotEmpty)
      .toList();
  expect(
    statementRuns,
    isNotEmpty,
    reason: '[$caseName] سطر الدرجة لا يحمل كلمة من العنوان: ${_describe(line)}',
  );

  // (3) نهاية السطر في RTL: الدرجة أقصى يسار سطرها.
  final marksRuns = line.runs.where(_isMarks).toList();
  final marksRight = marksRuns
      .map((run) => run.x + run.advance)
      .reduce((a, b) => a > b ? a : b);
  final statementLeft = statementRuns
      .map((run) => run.x)
      .reduce((a, b) => a < b ? a : b);
  expect(
    marksRight,
    lessThanOrEqualTo(statementLeft + 0.5),
    reason: '[$caseName] الدرجة ليست في نهاية السطر: يمين الدرجة='
        '$marksRight ويسار العنوان=$statementLeft.\n${_describe(line)}',
  );
  return (titleLines: lines.length, marksLines: marksLineIndices.length);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test('عنوان قصير: الدرجة في سطر العنوان نفسه (لا سطر مستقل)', () {
    final measured = _expectMarksRule(
      _layout(_document(statement: _shortStatement)),
      caseName: 'قصير',
    );
    expect(measured.titleLines, 1);
  });

  test('عنوان طويل يلتف: الدرجة تلتصق بآخر كلمة لا تنفرد', () {
    final measured = _expectMarksRule(
      _layout(_document(statement: _longStatement)),
      caseName: 'طويل',
    );
    expect(measured.titleLines, greaterThan(1),
        reason: 'العنوان لم يلتف أصلًا، فالاختبار لا يقيس حالة الالتفاف.');
  });

  test('هامش ضيّق (36 مم): الالتفاف لا يفصل الدرجة عن العنوان', () {
    final measured = _expectMarksRule(
      _layout(_document(statement: _longStatement, marginMm: 36)),
      caseName: 'هامش ضيّق',
    );
    expect(measured.titleLines, greaterThan(1));
  });

  test('هامش واسع (8 مم): ما زالت في نهاية السطر نفسه', () {
    _expectMarksRule(
      _layout(_document(statement: _longStatement, marginMm: 8)),
      caseName: 'هامش واسع',
    );
  });
}
